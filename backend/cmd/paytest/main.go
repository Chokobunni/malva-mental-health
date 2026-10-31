// Command paytest adalah harness uji end-to-end pembayaran sandbox Midtrans
// untuk Malva. Seluruh langkah dijalankan lewat HTTP publik — tool ini TIDAK
// menyentuh database dan hanya memakai paket internal yang bebas koneksi
// (clock untuk zona WIB, security untuk penyamaran email).
//
// Yang diuji (urut):
//  1. login akun pasien uji                       POST /v1/auth/login
//  2. buat booking pending (bila -booking-id kosong) POST /v1/bookings
//  3. buat pembayaran (reference + redirect_url)  POST /v1/payments
//  4. hitung signature SHA-512 Midtrans           (lokal, server key dari env)
//  5. kirim notifikasi settlement                 POST /v1/webhooks/payment
//  6. pastikan status pembayaran menjadi paid     GET  /v1/payments/{reference}
//  7. kirim ulang payload IDENTIK (idempotensi)   POST /v1/webhooks/payment
//  8. kirim signature palsu (harus ditolak 401)   POST /v1/webhooks/payment
//
// Pemakaian:
//
//	export MALVA_PAYTEST_EMAIL=pasien-uji@contoh.id
//	export MALVA_PAYTEST_PASSWORD=...
//	export MALVA_MIDTRANS_SERVER_KEY=...          # dari dashboard Midtrans sandbox
//
//	go run ./cmd/paytest -professional-id <uuid> -dry-run   # lihat rencana saja
//	go run ./cmd/paytest -professional-id <uuid>            # jalankan sungguhan
//	go run ./cmd/paytest -booking-id <uuid>                 # pakai booking pending yang ada
//
// PERINGATAN PENTING:
// Tanpa -dry-run, tool ini MENULIS DATA NYATA ke backend target: booking baru,
// payment baru, baris payment_events, dan booking tersebut akan berubah menjadi
// `paid` (plus sesi/agenda) bila signature dianggap sah. Jalankan HANYA terhadap
// lingkungan sandbox/staging, lalu bersihkan ID yang dicetak di akhir secara
// manual. Server key tidak pernah dicetak maupun dicatat ke log.
package main

import (
	"bytes"
	"context"
	"crypto/sha512"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"

	"malva/backend/internal/clock"
	"malva/backend/internal/security"
)

// Status hasil tiap langkah.
const (
	statusPass = "PASS"
	statusFail = "FAIL"
	statusSkip = "SKIP"
)

// defaultBaseURL sengaja diarahkan ke API produksi agar tidak ada tebakan;
// uji sebenarnya tetap harus diarahkan ke sandbox lewat -base-url.
const defaultBaseURL = "https://api.malva.web.id"

// statusCodeSettlement adalah status_code yang dikirim Midtrans pada notifikasi
// yang sudah dibayar penuh. Ikut dihitung dalam signature.
const statusCodeSettlement = "200"

// signaturePalsu adalah signature yang pasti tidak sah; dipakai untuk
// membuktikan webhook menolak notifikasi tanpa signature benar.
const signaturePalsu = "deadbeef"

func main() {
	if err := run(); err != nil {
		fmt.Fprintln(os.Stderr, "\npaytest: "+err.Error())
		os.Exit(1)
	}
}

// config menampung seluruh masukan CLI/env.
type config struct {
	baseURL         string
	email           string
	password        string
	accessToken     string
	serverKey       string
	bookingID       string
	professionalID  string
	serviceType     string
	sessionType     string
	bookingDate     string
	slotTime        string
	durationMinutes int
	paymentMethod   string
	dryRun          bool
	timeout         time.Duration
}

// parseFlags membaca flag lalu melengkapinya dari environment.
func parseFlags() (config, error) {
	var cfg config
	var timeoutSeconds int

	flag.StringVar(&cfg.baseURL, "base-url", defaultBaseURL, "basis URL backend Malva (tanpa garis miring di akhir)")
	flag.StringVar(&cfg.email, "email", os.Getenv("MALVA_PAYTEST_EMAIL"), "email akun pasien uji (default env MALVA_PAYTEST_EMAIL)")
	flag.StringVar(&cfg.password, "password", os.Getenv("MALVA_PAYTEST_PASSWORD"), "password akun pasien uji (default env MALVA_PAYTEST_PASSWORD; env lebih aman daripada flag)")
	flag.StringVar(&cfg.accessToken, "access-token", os.Getenv("MALVA_PAYTEST_TOKEN"), "access token siap pakai (default env MALVA_PAYTEST_TOKEN); bila diisi, langkah login DILEWATI dan role diperiksa lewat GET /v1/me. Untuk akun SSO/Google yang tidak punya password.")
	flag.StringVar(&cfg.bookingID, "booking-id", "", "pakai booking pending yang sudah ada (lewati pembuatan booking)")
	flag.StringVar(&cfg.professionalID, "professional-id", "", "ID profesional terverifikasi untuk membuat booking baru")
	flag.StringVar(&cfg.serviceType, "service-type", "quick_consult", "service_type booking baru (quick_consult atau quick_consult_video)")
	flag.StringVar(&cfg.sessionType, "session-type", "chat", "session_type booking baru (chat atau video)")
	flag.StringVar(&cfg.bookingDate, "booking-date", "", "tanggal booking baru, format 2006-01-02 (kosong = cari slot otomatis)")
	flag.StringVar(&cfg.slotTime, "slot-time", "", "jam booking baru, format 15:04 (kosong = cari slot otomatis)")
	flag.IntVar(&cfg.durationMinutes, "duration-minutes", 30, "durasi booking baru dalam menit (server menimpanya dengan durasi slot jadwal)")
	flag.StringVar(&cfg.paymentMethod, "payment-method", "qris", "label payment_method yang disimpan pada record payment")
	flag.BoolVar(&cfg.dryRun, "dry-run", false, "cetak rencana request tanpa mengirim apa pun")
	flag.IntVar(&timeoutSeconds, "timeout", 20, "batas waktu tiap request dalam detik")
	flag.Parse()

	cfg.baseURL = strings.TrimRight(strings.TrimSpace(cfg.baseURL), "/")
	cfg.email = strings.ToLower(strings.TrimSpace(cfg.email))
	cfg.password = strings.TrimSpace(cfg.password)
	cfg.accessToken = strings.TrimSpace(cfg.accessToken)
	cfg.bookingID = strings.TrimSpace(cfg.bookingID)
	cfg.professionalID = strings.TrimSpace(cfg.professionalID)
	cfg.serviceType = strings.ToLower(strings.TrimSpace(cfg.serviceType))
	cfg.sessionType = strings.ToLower(strings.TrimSpace(cfg.sessionType))
	cfg.bookingDate = strings.TrimSpace(cfg.bookingDate)
	cfg.slotTime = strings.TrimSpace(cfg.slotTime)
	cfg.paymentMethod = strings.TrimSpace(cfg.paymentMethod)
	// Server key hanya dibaca dari environment: flag akan terlihat di riwayat
	// shell dan daftar proses.
	cfg.serverKey = strings.TrimSpace(os.Getenv("MALVA_MIDTRANS_SERVER_KEY"))

	if cfg.baseURL == "" {
		return config{}, errors.New("-base-url tidak boleh kosong")
	}
	if timeoutSeconds <= 0 {
		return config{}, errors.New("-timeout harus lebih besar dari 0 detik")
	}
	cfg.timeout = time.Duration(timeoutSeconds) * time.Second
	return cfg, nil
}

// run menjalankan seluruh alur uji dan mengembalikan error bila ada langkah
// yang FAIL (exit code non-zero) atau bila masukan belum lengkap.
func run() error {
	cfg, err := parseFlags()
	if err != nil {
		return err
	}
	if cfg.dryRun {
		printPlan(cfg)
		return nil
	}
	// Mode aman: tanpa kredensial, jangan menebak-nebak dan jangan menulis.
	// Access token siap pakai dihitung sebagai kredensial: jalur ini dipakai
	// untuk akun SSO (mis. login Google) yang tidak punya password.
	if cfg.accessToken == "" && (cfg.email == "" || cfg.password == "") {
		return errors.New("kredensial belum diisi — set MALVA_PAYTEST_EMAIL & MALVA_PAYTEST_PASSWORD, " +
			"atau MALVA_PAYTEST_TOKEN untuk akun SSO tanpa password, " +
			"atau jalankan dengan -dry-run untuk melihat rencana request tanpa mengirim apa pun")
	}
	if cfg.bookingID == "" && cfg.professionalID == "" {
		return errors.New("tentukan -booking-id (memakai booking pending yang sudah ada) atau -professional-id (membuat booking baru)")
	}

	r := &runner{cfg: cfg, cl: newClient(cfg)}
	ctx := context.Background()

	// Pratinjau konfigurasi pembayaran: gratis, publik, dan menjelaskan apakah
	// langkah webhook memang bisa bermakna (butuh mode gateway).
	r.reportPaymentMode(ctx)

	r.doAll(ctx)
	r.printSummary()

	if fails := r.rep.count(statusFail); fails > 0 {
		return fmt.Errorf("ada %d langkah FAIL — lihat ringkasan di atas", fails)
	}
	return nil
}

// ============================================================
// KLIEN HTTP
// ============================================================

// client adalah pembungkus minimal net/http: JSON masuk, JSON keluar, token
// bearer opsional, dan timeout per request.
type client struct {
	baseURL string
	timeout time.Duration
	token   string
	http    *http.Client
}

func newClient(cfg config) *client {
	return &client{
		baseURL: cfg.baseURL,
		timeout: cfg.timeout,
		http:    &http.Client{Timeout: cfg.timeout},
	}
}

// request mengirim satu request JSON dan mengembalikan status + body mentah.
// Context selalu diberi timeout agar satu endpoint yang menggantung tidak
// menahan seluruh uji.
func (c *client) request(ctx context.Context, method, path string, payload any, withAuth bool) (int, []byte, error) {
	reqCtx, cancel := context.WithTimeout(ctx, c.timeout)
	defer cancel()

	var body io.Reader
	if payload != nil {
		raw, err := json.Marshal(payload)
		if err != nil {
			return 0, nil, fmt.Errorf("gagal menyusun body %s %s: %w", method, path, err)
		}
		body = bytes.NewReader(raw)
	}
	req, err := http.NewRequestWithContext(reqCtx, method, c.baseURL+path, body)
	if err != nil {
		return 0, nil, err
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("User-Agent", "malva-paytest/1")
	if payload != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	if withAuth {
		req.Header.Set("Authorization", "Bearer "+c.token)
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return 0, nil, err
	}
	defer func() { _ = resp.Body.Close() }()
	raw, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return resp.StatusCode, nil, err
	}
	return resp.StatusCode, raw, nil
}

// ============================================================
// BENTUK PAYLOAD & RESPONS
// ============================================================

// loginPayload mengikuti server.loginRequest.
type loginPayload struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

// bookingPayload mengikuti server.createBookingRequest. price tidak dipakai
// server (harga selalu dihitung dari tarif profesional), jadi dibiarkan 0.
type bookingPayload struct {
	PatientID       string `json:"patient_id,omitempty"`
	ProfessionalID  string `json:"professional_id"`
	ServiceType     string `json:"service_type"`
	SessionType     string `json:"session_type"`
	BookingDate     string `json:"booking_date"`
	SlotTime        string `json:"slot_time"`
	DurationMinutes int    `json:"duration_minutes"`
	Price           int64  `json:"price"`
}

// paymentPayload mengikuti server.createPaymentRequest.
type paymentPayload struct {
	BookingID     string `json:"booking_id"`
	PaymentMethod string `json:"payment_method"`
}

// webhookPayload mengikuti bentuk notifikasi Midtrans yang didekode
// payment.WebhookEvent. Urutan field tidak memengaruhi signature; yang penting
// nilai order_id + status_code + gross_amount apa adanya.
type webhookPayload struct {
	OrderID           string `json:"order_id"`
	StatusCode        string `json:"status_code"`
	GrossAmount       string `json:"gross_amount"`
	TransactionStatus string `json:"transaction_status"`
	FraudStatus       string `json:"fraud_status"`
	SignatureKey      string `json:"signature_key"`
	TransactionID     string `json:"transaction_id"`
	PaymentType       string `json:"payment_type"`
	TransactionTime   string `json:"transaction_time"`
}

type loginResponse struct {
	AccessToken string `json:"access_token"`
	User        struct {
		ID    string `json:"id"`
		Email string `json:"email"`
		Role  string `json:"role"`
	} `json:"user"`
}

type bookingResponse struct {
	Booking struct {
		ID     string `json:"id"`
		Status string `json:"status"`
		Price  int64  `json:"price"`
	} `json:"booking"`
}

type paymentResponse struct {
	Payment struct {
		Reference        string `json:"reference"`
		Status           string `json:"status"`
		GrossAmount      int64  `json:"gross_amount"`
		ServiceFeeAmount int64  `json:"service_fee_amount"`
		RedirectURL      string `json:"redirect_url"`
	} `json:"payment"`
	Breakdown struct {
		Consultation int64 `json:"consultation"`
		ServiceFee   int64 `json:"service_fee"`
		Total        int64 `json:"total"`
	} `json:"breakdown"`
}

type paymentStatusResponse struct {
	Payment struct {
		Reference string `json:"reference"`
		Status    string `json:"status"`
		PaidAt    string `json:"paid_at"`
	} `json:"payment"`
	SessionID string `json:"session_id"`
}

type slotsResponse struct {
	Off   bool `json:"off"`
	Slots []struct {
		Time      string `json:"time"`
		Available bool   `json:"available"`
	} `json:"slots"`
}

type paymentConfigResponse struct {
	Env      string `json:"env"`
	Mode     string `json:"mode"`
	Provider string `json:"provider"`
}

// meResponse adalah balasan GET /v1/me: {"user":{...}}. Dipakai jalur
// -access-token untuk memastikan identitas dan role sebelum menulis data.
type meResponse struct {
	User struct {
		ID    string `json:"id"`
		Email string `json:"email"`
		Role  string `json:"role"`
	} `json:"user"`
}

// apiError mengekstrak pesan "error" dari body JSON backend agar detail langkah
// tetap informatif tanpa mencetak seluruh body (bisa memuat data pribadi).
func apiError(raw []byte) string {
	var e struct {
		Error string `json:"error"`
	}
	if err := json.Unmarshal(raw, &e); err == nil && strings.TrimSpace(e.Error) != "" {
		return strings.TrimSpace(e.Error)
	}
	body := strings.TrimSpace(string(raw))
	if body == "" {
		return "(body kosong)"
	}
	if len(body) > 200 {
		body = body[:200] + "…"
	}
	return body
}

// ============================================================
// RINGKASAN HASIL
// ============================================================

type stepResult struct {
	no     int
	name   string
	status string
	detail string
}

// report menampung semua hasil langkah; dicetak langsung saat terjadi dan
// diulang sebagai tabel ringkasan di akhir.
type report struct {
	items []stepResult
}

func (r *report) add(no int, name, status, detail string) {
	r.items = append(r.items, stepResult{no: no, name: name, status: status, detail: detail})
	line := fmt.Sprintf("[%s] %d. %s", status, no, name)
	if detail != "" {
		line += " — " + detail
	}
	fmt.Println(line)
}

// count menghitung langkah berstatus tertentu.
func (r *report) count(status string) int {
	n := 0
	for _, it := range r.items {
		if it.status == status {
			n++
		}
	}
	return n
}

// ============================================================
// PELAKSANA LANGKAH
// ============================================================

// runner menyimpan keadaan antar langkah: klien, hasil, dan ID yang dibuat
// (untuk dibersihkan manual setelah uji).
type runner struct {
	cfg config
	cl  *client
	rep report

	bookingID      string // booking yang dipakai uji
	bookingDibuat  bool   // true bila booking dibuat oleh tool ini
	reference      string // reference payment yang dibuat
	redirectURL    string
	grossWebhook   string // gross_amount bentuk Midtrans, mis. "152000.00"
	paymentMode    string // "gateway" / "simulation" dari /v1/config/payment
	webhookPayload []byte // payload settlement yang sudah ditandatangani
}

// reportPaymentMode membaca GET /v1/config/payment (publik) hanya sebagai
// konteks: bila mode bukan gateway, langkah webhook tidak akan bermakna.
func (r *runner) reportPaymentMode(ctx context.Context) {
	code, raw, err := r.cl.request(ctx, http.MethodGet, "/v1/config/payment", nil, false)
	if err != nil || code != http.StatusOK {
		fmt.Println("Info: konfigurasi pembayaran tidak terbaca; lanjut dengan asumsi mode gateway.")
		return
	}
	var out paymentConfigResponse
	if err := json.Unmarshal(raw, &out); err != nil {
		fmt.Println("Info: konfigurasi pembayaran tidak dapat diparse; lanjut dengan asumsi mode gateway.")
		return
	}
	r.paymentMode = strings.ToLower(strings.TrimSpace(out.Mode))
	fmt.Printf("Info: mode pembayaran=%s env=%s provider=%s\n", r.paymentMode, out.Env, out.Provider)
	if r.paymentMode != "gateway" {
		fmt.Println("PERINGATAN: backend bukan mode gateway — webhook pembayaran akan membalas 200 \"ignored\" dan langkah 5-7 tidak akan membuktikan apa pun.")
	}
}

// doAll menjalankan langkah 1-8 secara berurutan. Bila sebuah langkah gagal
// secara fatal (tidak ada reference untuk dilanjutkan), sisa langkah ditandai
// SKIP agar ringkasan tetap lengkap.
func (r *runner) doAll(ctx context.Context) {
	if !r.stepLogin(ctx) {
		r.skipDari(2, "dibatalkan: login gagal")
		return
	}
	if !r.stepBooking(ctx) {
		r.skipDari(3, "dibatalkan: booking gagal")
		return
	}
	if !r.stepPayment(ctx) {
		r.skipDari(4, "dibatalkan: pembayaran tidak terbentuk")
		return
	}
	if !r.stepSignature() {
		// Tanpa server key, notifikasi yang sah tidak mungkin dibuat.
		r.skipDari(5, "tanpa MALVA_MIDTRANS_SERVER_KEY")
		return
	}
	r.stepWebhookSettlement(ctx)
	r.stepStatusPaid(ctx)
	r.stepWebhookReplay(ctx)
	r.stepWebhookSignaturePalsu(ctx)
}

// skip menandai satu langkah yang tidak dapat dijalankan.
func (r *runner) skip(no int, alasan string) {
	r.rep.add(no, namaLangkah(no), statusSkip, alasan)
}

// skipDari menandai langkah `mulai` sampai 8 sebagai SKIP agar ringkasan tetap
// menampilkan semua langkah meski rantai terhenti di tengah.
func (r *runner) skipDari(mulai int, alasan string) {
	for no := mulai; no <= 8; no++ {
		r.skip(no, alasan)
	}
}

// namaLangkah memberi label pendek yang konsisten untuk setiap nomor langkah.
func namaLangkah(no int) string {
	switch no {
	case 1:
		return "login"
	case 2:
		return "buat booking"
	case 3:
		return "buat pembayaran"
	case 4:
		return "hitung signature"
	case 5:
		return "kirim webhook settlement"
	case 6:
		return "status pembayaran jadi paid"
	case 7:
		return "kirim ulang payload identik (idempotensi)"
	case 8:
		return "tolak signature palsu (401)"
	default:
		return "langkah"
	}
}

// stepLogin menukar email/password menjadi access token. Token disimpan di
// klien dan TIDAK pernah dicetak.
func (r *runner) stepLogin(ctx context.Context) bool {
	// Jalur token siap pakai: akun SSO (Google) tidak punya password, jadi
	// login email/password pasti gagal. Token dipakai apa adanya, lalu
	// identitas + role dipastikan lewat GET /v1/me agar uji tidak berjalan
	// dengan akun berperan salah.
	if r.cfg.accessToken != "" {
		return r.stepLoginViaToken(ctx)
	}
	code, raw, err := r.cl.request(ctx, http.MethodPost, "/v1/auth/login",
		loginPayload{Email: r.cfg.email, Password: r.cfg.password}, false)
	if err != nil {
		r.rep.add(1, namaLangkah(1), statusFail, "request gagal: "+err.Error())
		return false
	}
	if code != http.StatusOK {
		r.rep.add(1, namaLangkah(1), statusFail,
			fmt.Sprintf("HTTP %d untuk %s: %s", code, security.MaskEmail(r.cfg.email), apiError(raw)))
		return false
	}
	var out loginResponse
	if err := json.Unmarshal(raw, &out); err != nil {
		r.rep.add(1, namaLangkah(1), statusFail, "respons bukan JSON: "+err.Error())
		return false
	}
	if strings.TrimSpace(out.AccessToken) == "" {
		r.rep.add(1, namaLangkah(1), statusFail, "respons tidak memuat access_token")
		return false
	}
	r.cl.token = out.AccessToken
	if out.User.Role != "patient" {
		r.rep.add(1, namaLangkah(1), statusFail,
			fmt.Sprintf("akun %s berperan %q; uji ini butuh akun pasien", security.MaskEmail(r.cfg.email), out.User.Role))
		return false
	}
	r.rep.add(1, namaLangkah(1), statusPass,
		fmt.Sprintf("%s (role pasien, access_token diterima & disembunyikan)", security.MaskEmail(r.cfg.email)))
	return true
}

// stepLoginViaToken memakai access token yang sudah ada (-access-token /
// MALVA_PAYTEST_TOKEN) dan melewati POST /v1/auth/login. Role tetap diverifikasi
// lewat GET /v1/me: token milik profesional/admin akan membuat createPayment
// ditolak 403, jadi lebih baik digagalkan di sini dengan pesan jelas.
// Token tidak pernah dicetak, hanya disimpan di klien.
func (r *runner) stepLoginViaToken(ctx context.Context) bool {
	r.cl.token = r.cfg.accessToken
	code, raw, err := r.cl.request(ctx, http.MethodGet, "/v1/me", nil, true)
	if err != nil {
		r.rep.add(1, namaLangkah(1), statusFail, "login dilewati (token siap pakai) tetapi GET /v1/me gagal: "+err.Error())
		return false
	}
	if code != http.StatusOK {
		r.rep.add(1, namaLangkah(1), statusFail,
			fmt.Sprintf("login dilewati (token siap pakai) tetapi GET /v1/me membalas HTTP %d: %s", code, apiError(raw)))
		return false
	}
	var out meResponse
	if err := json.Unmarshal(raw, &out); err != nil {
		r.rep.add(1, namaLangkah(1), statusFail, "respons /v1/me bukan JSON: "+err.Error())
		return false
	}
	if out.User.Role != "patient" {
		r.rep.add(1, namaLangkah(1), statusFail,
			fmt.Sprintf("akun %s berperan %q; uji ini butuh akun pasien",
				security.MaskEmail(out.User.Email), out.User.Role))
		return false
	}
	r.rep.add(1, namaLangkah(1), statusPass,
		fmt.Sprintf("login DILEWATI, memakai -access-token: %s (role pasien, user_id %s, token disembunyikan)",
			security.MaskEmail(out.User.Email), out.User.ID))
	return true
}

// stepBooking memakai -booking-id bila diberikan, atau membuat booking pending
// baru lewat POST /v1/bookings.
func (r *runner) stepBooking(ctx context.Context) bool {
	if r.cfg.bookingID != "" {
		r.bookingID = r.cfg.bookingID
		r.rep.add(2, namaLangkah(2), statusPass, "memakai booking dari -booking-id: "+r.bookingID)
		return true
	}

	date, slot := r.cfg.bookingDate, r.cfg.slotTime
	if date == "" || slot == "" {
		d, s, err := r.cariSlot(ctx)
		if err != nil {
			r.rep.add(2, namaLangkah(2), statusFail, err.Error())
			return false
		}
		date, slot = d, s
	}

	payload := bookingPayload{
		ProfessionalID:  r.cfg.professionalID,
		ServiceType:     r.cfg.serviceType,
		SessionType:     r.cfg.sessionType,
		BookingDate:     date,
		SlotTime:        slot,
		DurationMinutes: r.cfg.durationMinutes,
	}
	code, raw, err := r.cl.request(ctx, http.MethodPost, "/v1/bookings", payload, true)
	if err != nil {
		r.rep.add(2, namaLangkah(2), statusFail, "request gagal: "+err.Error())
		return false
	}
	if code != http.StatusCreated {
		r.rep.add(2, namaLangkah(2), statusFail,
			fmt.Sprintf("HTTP %d (%s %s): %s", code, date, slot, apiError(raw)))
		return false
	}
	var out bookingResponse
	if err := json.Unmarshal(raw, &out); err != nil {
		r.rep.add(2, namaLangkah(2), statusFail, "respons bukan JSON: "+err.Error())
		return false
	}
	if out.Booking.ID == "" {
		r.rep.add(2, namaLangkah(2), statusFail, "respons tidak memuat booking.id")
		return false
	}
	r.bookingID = out.Booking.ID
	r.bookingDibuat = true
	r.rep.add(2, namaLangkah(2), statusPass,
		fmt.Sprintf("booking %s (%s %s, status %s, harga %d)", out.Booking.ID, date, slot, out.Booking.Status, out.Booking.Price))
	return true
}

// cariSlot mencari slot praktik pertama yang masih tersedia dalam 14 hari ke
// depan lewat endpoint publik GET /v1/doctors/{id}/slots. Dipakai hanya bila
// pengguna tidak menentukan -booking-date/-slot-time sendiri (booking butuh
// slot yang cocok dengan jadwal mingguan profesional + lead time 24 jam).
func (r *runner) cariSlot(ctx context.Context) (string, string, error) {
	if r.cfg.professionalID == "" {
		return "", "", errors.New("-professional-id kosong sehingga slot tidak bisa dicari; isi -booking-date dan -slot-time")
	}
	base := "/v1/doctors/" + url.PathEscape(r.cfg.professionalID) + "/slots"
	mulai := clock.Now()
	for i := 1; i <= 14; i++ {
		tanggal := mulai.AddDate(0, 0, i).Format("2006-01-02")
		code, raw, err := r.cl.request(ctx, http.MethodGet, base+"?date="+url.QueryEscape(tanggal), nil, false)
		if err != nil {
			return "", "", fmt.Errorf("gagal membaca slot %s: %w", tanggal, err)
		}
		if code != http.StatusOK {
			return "", "", fmt.Errorf("gagal membaca slot %s: HTTP %d: %s", tanggal, code, apiError(raw))
		}
		var out slotsResponse
		if err := json.Unmarshal(raw, &out); err != nil {
			return "", "", fmt.Errorf("respons slot %s bukan JSON: %w", tanggal, err)
		}
		if out.Off {
			continue
		}
		for _, s := range out.Slots {
			if s.Available && strings.TrimSpace(s.Time) != "" {
				return tanggal, strings.TrimSpace(s.Time), nil
			}
		}
	}
	return "", "", errors.New("tidak ada slot tersedia dalam 14 hari ke depan untuk profesional ini; isi -booking-date dan -slot-time manual")
}

// stepPayment membuat payment pending dan mencatat reference + nominal yang
// nanti dipakai pada notifikasi webhook.
func (r *runner) stepPayment(ctx context.Context) bool {
	code, raw, err := r.cl.request(ctx, http.MethodPost, "/v1/payments",
		paymentPayload{BookingID: r.bookingID, PaymentMethod: r.cfg.paymentMethod}, true)
	if err != nil {
		r.rep.add(3, namaLangkah(3), statusFail, "request gagal: "+err.Error())
		return false
	}
	if code != http.StatusCreated {
		r.rep.add(3, namaLangkah(3), statusFail, fmt.Sprintf("HTTP %d: %s", code, apiError(raw)))
		return false
	}
	var out paymentResponse
	if err := json.Unmarshal(raw, &out); err != nil {
		r.rep.add(3, namaLangkah(3), statusFail, "respons bukan JSON: "+err.Error())
		return false
	}
	if out.Payment.Reference == "" {
		r.rep.add(3, namaLangkah(3), statusFail, "respons tidak memuat payment.reference")
		return false
	}
	r.reference = out.Payment.Reference
	r.grossWebhook = grossAmountWebhook(out)
	if r.grossWebhook == "" {
		r.rep.add(3, namaLangkah(3), statusFail, "nominal pembayaran tidak terbaca dari respons")
		return false
	}
	detail := fmt.Sprintf("reference %s, gross_amount %s", r.reference, r.grossWebhook)
	if out.Payment.RedirectURL != "" {
		r.redirectURL = out.Payment.RedirectURL
		detail += ", redirect_url " + out.Payment.RedirectURL
	}
	r.rep.add(3, namaLangkah(3), statusPass, detail)
	return true
}

// grossAmountWebhook menentukan gross_amount yang dipakai notifikasi Midtrans.
// Nominal yang dikirim ke gateway saat createPayment adalah breakdown.total
// (harga konsultasi + biaya layanan), bukan payment.gross_amount saja; Midtrans
// mengirimkannya kembali dengan dua angka desimal.
func grossAmountWebhook(p paymentResponse) string {
	total := p.Breakdown.Total
	if total <= 0 {
		total = p.Payment.GrossAmount + p.Payment.ServiceFeeAmount
	}
	if total <= 0 {
		return ""
	}
	return strconv.FormatInt(total, 10) + ".00"
}

// stepSignature menyusun payload settlement beserta signature SHA-512
// Midtrans: sha512(order_id + status_code + gross_amount + serverKey).
// Server key hanya dipakai di sini dan tidak pernah dicetak.
func (r *runner) stepSignature() bool {
	if r.cfg.serverKey == "" {
		r.rep.add(4, namaLangkah(4), statusSkip,
			"MALVA_MIDTRANS_SERVER_KEY kosong — signature sah tidak bisa dihitung, notifikasi tidak dikirim")
		return false
	}
	evt := webhookPayload{
		OrderID:           r.reference,
		StatusCode:        statusCodeSettlement,
		GrossAmount:       r.grossWebhook,
		TransactionStatus: "settlement",
		FraudStatus:       "accept",
		TransactionID:     fmt.Sprintf("paytest-%d", clock.Now().UnixNano()),
		PaymentType:       strings.ToLower(strings.TrimSpace(r.cfg.paymentMethod)),
		TransactionTime:   clock.Now().Format("2006-01-02 15:04:05"),
	}
	evt.SignatureKey = midtransSignature(evt.OrderID, evt.StatusCode, evt.GrossAmount, r.cfg.serverKey)
	raw, err := json.Marshal(evt)
	if err != nil {
		r.rep.add(4, namaLangkah(4), statusFail, "gagal menyusun payload webhook: "+err.Error())
		return false
	}
	r.webhookPayload = raw
	r.rep.add(4, namaLangkah(4), statusPass,
		fmt.Sprintf("sha512(order_id=%s + %s + %s + server_key) dihitung lokal (server key disembunyikan)",
			evt.OrderID, evt.StatusCode, evt.GrossAmount))
	return true
}

// midtransSignature menghitung sha512 hex dari gabungan field notifikasi —
// rumus yang sama dengan payment.MidtransSignature di sisi server.
func midtransSignature(orderID, statusCode, grossAmount, serverKey string) string {
	sum := sha512.Sum512([]byte(orderID + statusCode + grossAmount + serverKey))
	return hex.EncodeToString(sum[:])
}

// stepWebhookSettlement mengirim notifikasi settlement yang sah; harapan 200.
func (r *runner) stepWebhookSettlement(ctx context.Context) {
	code, raw, err := r.cl.request(ctx, http.MethodPost, "/v1/webhooks/payment", json.RawMessage(r.webhookPayload), false)
	if err != nil {
		r.rep.add(5, namaLangkah(5), statusFail, "request gagal: "+err.Error())
		return
	}
	if code != http.StatusOK {
		r.rep.add(5, namaLangkah(5), statusFail, fmt.Sprintf("HTTP %d (harap 200): %s", code, apiError(raw)))
		return
	}
	r.rep.add(5, namaLangkah(5), statusPass, fmt.Sprintf("HTTP 200 %s", ringkasBody(raw)))
}

// stepStatusPaid memastikan pembayaran benar-benar berubah menjadi `paid`.
func (r *runner) stepStatusPaid(ctx context.Context) {
	st, code, raw, err := r.ambilStatus(ctx)
	if err != nil {
		r.rep.add(6, namaLangkah(6), statusFail, err.Error())
		return
	}
	if code != http.StatusOK {
		r.rep.add(6, namaLangkah(6), statusFail, fmt.Sprintf("HTTP %d: %s", code, apiError(raw)))
		return
	}
	if st.Payment.Status != "paid" {
		r.rep.add(6, namaLangkah(6), statusFail, fmt.Sprintf("status %q (harap \"paid\")", st.Payment.Status))
		return
	}
	detail := "status paid"
	if st.SessionID != "" {
		detail += ", session_id " + st.SessionID
	}
	r.rep.add(6, namaLangkah(6), statusPass, detail)
}

// stepWebhookReplay mengirim ulang payload settlement yang PERSIS sama. Harapan:
// tetap 200 (tanpa pesan galat) dan status tidak berubah menjadi ganda.
func (r *runner) stepWebhookReplay(ctx context.Context) {
	code, body, err := r.cl.request(ctx, http.MethodPost, "/v1/webhooks/payment", json.RawMessage(r.webhookPayload), false)
	if err != nil {
		r.rep.add(7, namaLangkah(7), statusFail, "request gagal: "+err.Error())
		return
	}
	if code != http.StatusOK {
		r.rep.add(7, namaLangkah(7), statusFail, fmt.Sprintf("HTTP %d pada pengiriman ulang (harap 200): %s", code, apiError(body)))
		return
	}
	st, code, bodyStatus, err := r.ambilStatus(ctx)
	if err != nil {
		r.rep.add(7, namaLangkah(7), statusFail, "webhook diulang 200 tetapi status tidak terbaca: "+err.Error())
		return
	}
	if code != http.StatusOK {
		r.rep.add(7, namaLangkah(7), statusFail, fmt.Sprintf("HTTP %d saat memeriksa status: %s", code, apiError(bodyStatus)))
		return
	}
	if st.Payment.Status != "paid" {
		r.rep.add(7, namaLangkah(7), statusFail, fmt.Sprintf("status berubah menjadi %q setelah replay", st.Payment.Status))
		return
	}
	r.rep.add(7, namaLangkah(7), statusPass,
		fmt.Sprintf("webhook diulang: HTTP 200 %s; pemeriksaan status: tetap paid", ringkasBody(body)))
}

// stepWebhookSignaturePalsu membuktikan notifikasi tanpa signature sah ditolak
// (401) sehingga orang luar tidak bisa menandai pembayaran lunas.
func (r *runner) stepWebhookSignaturePalsu(ctx context.Context) {
	var evt webhookPayload
	if err := json.Unmarshal(r.webhookPayload, &evt); err != nil {
		r.rep.add(8, namaLangkah(8), statusFail, "payload sebelumnya tidak bisa dibaca ulang: "+err.Error())
		return
	}
	evt.SignatureKey = signaturePalsu
	raw, err := json.Marshal(evt)
	if err != nil {
		r.rep.add(8, namaLangkah(8), statusFail, "gagal menyusun payload signature palsu: "+err.Error())
		return
	}
	code, body, err := r.cl.request(ctx, http.MethodPost, "/v1/webhooks/payment", json.RawMessage(raw), false)
	if err != nil {
		r.rep.add(8, namaLangkah(8), statusFail, "request gagal: "+err.Error())
		return
	}
	if code != http.StatusUnauthorized {
		r.rep.add(8, namaLangkah(8), statusFail, fmt.Sprintf("HTTP %d (harap 401): %s", code, apiError(body)))
		return
	}
	r.rep.add(8, namaLangkah(8), statusPass, fmt.Sprintf("HTTP 401 %s", ringkasBody(body)))
}

// ambilStatus membaca GET /v1/payments/{reference} (butuh auth pasien pemilik).
func (r *runner) ambilStatus(ctx context.Context) (paymentStatusResponse, int, []byte, error) {
	var out paymentStatusResponse
	code, raw, err := r.cl.request(ctx, http.MethodGet,
		"/v1/payments/"+url.PathEscape(r.reference), nil, true)
	if err != nil {
		return out, code, raw, fmt.Errorf("request status gagal: %w", err)
	}
	if code != http.StatusOK {
		return out, code, raw, nil
	}
	if err := json.Unmarshal(raw, &out); err != nil {
		return out, code, raw, fmt.Errorf("respons status bukan JSON: %w", err)
	}
	return out, code, raw, nil
}

// ringkasBody menampilkan isi balasan sesingkat mungkin; body webhook tidak
// memuat data pribadi sehingga aman ditampilkan.
func ringkasBody(raw []byte) string {
	body := strings.TrimSpace(string(raw))
	if len(body) > 160 {
		body = body[:160] + "…"
	}
	if body == "" {
		return "(body kosong)"
	}
	return body
}

// printSummary mencetak tabel ringkasan PASS/FAIL/SKIP dan daftar ID yang perlu
// dibersihkan manual dari database target.
func (r *runner) printSummary() {
	fmt.Println("\n================ RINGKASAN ================")
	for _, it := range r.rep.items {
		fmt.Printf("  %-4s %d. %-38s %s\n", it.status, it.no, it.name, it.detail)
	}
	fmt.Printf("  Total: %d PASS, %d FAIL, %d SKIP\n",
		r.rep.count(statusPass), r.rep.count(statusFail), r.rep.count(statusSkip))

	if r.bookingID != "" || r.reference != "" {
		fmt.Println("\nDATA YANG DIBUAT DI BACKEND — BERSIHKAN MANUAL:")
		if r.bookingID != "" {
			label := "diberikan lewat -booking-id (tidak dibuat tool ini)"
			if r.bookingDibuat {
				label = "dibuat tool ini"
			}
			fmt.Printf("  booking_id : %s  [%s]\n", r.bookingID, label)
		}
		if r.reference != "" {
			fmt.Printf("  reference  : %s  (payment + payment_events terkait)\n", r.reference)
		}
		fmt.Println("  Catatan: booking yang sudah paid juga meninggalkan sesi/agenda dan baris earnings.")
	}
}

// ============================================================
// RENCANA DRY-RUN
// ============================================================

// printPlan mencetak seluruh request yang AKAN dikirim tanpa mengirim apa pun.
// Dipakai sebagai mode aman default ketika kredensial belum tersedia.
func printPlan(cfg config) {
	kredensial := "BELUM diisi — uji sungguhan akan menolak berjalan"
	if cfg.email != "" && cfg.password != "" {
		kredensial = "tersedia lewat flag/env"
	}
	email := security.MaskEmail(cfg.email)
	if email == "" {
		email = "(belum diisi)"
	}
	serverKey := "TIDAK ADA — langkah 4-8 akan SKIP"
	if cfg.serverKey != "" {
		serverKey = "tersedia (nilai disembunyikan)"
	}
	tujuan := "-booking-id " + cfg.bookingID
	if cfg.bookingID == "" {
		tujuan = "bookings baru untuk professional " + cfg.professionalID
		if cfg.professionalID == "" {
			tujuan = "BELUM ditentukan — isi -booking-id atau -professional-id"
		}
	}

	fmt.Println("RENCANA UJI PEMBAYARAN (DRY-RUN) — tidak ada request yang dikirim")
	fmt.Println("================================================================")
	fmt.Printf("  base_url    : %s\n", cfg.baseURL)
	fmt.Printf("  akun        : %s (%s)\n", email, kredensial)
	fmt.Printf("  server key  : %s\n", serverKey)
	fmt.Printf("  booking     : %s\n", tujuan)
	fmt.Printf("  timeout     : %s per request\n", cfg.timeout)
	fmt.Println()

	fmt.Println("1. POST /v1/auth/login")
	fmt.Printf("     body        : {\"email\":%q,\"password\":\"(disembunyikan)\"}\n", email)
	fmt.Println("     harapan     : 200 + access_token (token tidak dicetak)")
	fmt.Println("     catatan     : akun harus berperan pasien (createPayment menolak role lain)")

	fmt.Println("2. POST /v1/bookings")
	if cfg.bookingID != "" {
		fmt.Printf("     dilewati    : memakai booking yang diberikan (%s)\n", cfg.bookingID)
	} else {
		slot := "(dicari otomatis)"
		if cfg.bookingDate != "" && cfg.slotTime != "" {
			slot = cfg.bookingDate + " " + cfg.slotTime
		} else {
			fmt.Printf("     pra-syarat  : GET /v1/doctors/%s/slots?date=YYYY-MM-DD (slot bebas 14 hari ke depan)\n", cfg.professionalID)
		}
		fmt.Printf("     body        : {\"professional_id\":%q,\"service_type\":%q,\"session_type\":%q,\"booking_date\":...,\"slot_time\":...,\"duration_minutes\":%d}\n",
			cfg.professionalID, cfg.serviceType, cfg.sessionType, cfg.durationMinutes)
		fmt.Printf("     slot        : %s\n", slot)
		fmt.Println("     harapan     : 201 + booking.id berstatus pending")
	}

	fmt.Println("3. POST /v1/payments  (Bearer access_token)")
	fmt.Printf("     body        : {\"booking_id\":<booking_id>,\"payment_method\":%q}\n", cfg.paymentMethod)
	fmt.Println("     harapan     : 201 + payment.reference, gross_amount, redirect_url")
	fmt.Println("     catatan     : mode gateway membuat transaksi Snap nyata di Midtrans (sandbox)")

	fmt.Println("4. hitung signature (lokal, tanpa network)")
	fmt.Println("     rumus       : signature_key = sha512_hex(order_id + status_code + gross_amount + server_key)")
	fmt.Println("     nilai       : order_id=<reference>, status_code=" + statusCodeSettlement + ", gross_amount=<breakdown.total> (mis. \"152000.00\")")
	if cfg.serverKey == "" {
		fmt.Println("     status      : SKIP — MALVA_MIDTRANS_SERVER_KEY tidak ada, langkah 5-8 tidak bisa dijalankan")
	} else {
		fmt.Println("     status      : dihitung lokal; server key tidak pernah dicetak")
	}

	fmt.Println("5. POST /v1/webhooks/payment")
	fmt.Println("     body        : {\"order_id\":<reference>,\"status_code\":\"200\",\"gross_amount\":<total>,\"transaction_status\":\"settlement\",\"fraud_status\":\"accept\",\"signature_key\":<sha512>,\"transaction_id\":\"paytest-...\",...}")
	fmt.Println("     harapan     : 200 {\"status\":\"ok\"} — pembayaran ditandai paid + booking diaktivasi")

	fmt.Println("6. GET /v1/payments/{reference}  (Bearer access_token)")
	fmt.Println("     harapan     : 200 dengan payment.status == \"paid\"")

	fmt.Println("7. POST /v1/webhooks/payment  (payload identik byte-per-byte)")
	fmt.Println("     harapan     : 200 tanpa proses ganda; status tetap paid (bukti idempotensi payment_events)")

	fmt.Println("8. POST /v1/webhooks/payment  (signature_key=\"" + signaturePalsu + "\")")
	fmt.Println("     harapan     : 401 invalid signature, tanpa efek samping")

	fmt.Println("\nPERINGATAN: tanpa -dry-run, langkah 1-8 MENULIS DATA NYATA ke backend di atas")
	fmt.Println("(booking, payment, payment_events, dan booking menjadi paid). Jalankan hanya di sandbox.")
	fmt.Println("ID yang dibuat dicetak di akhir dengan label \"BERSIHKAN MANUAL\".")
	fmt.Println("\nUntuk menjalankan sungguhan:")
	fmt.Println("  export MALVA_PAYTEST_EMAIL=... MALVA_PAYTEST_PASSWORD=... MALVA_MIDTRANS_SERVER_KEY=...")
	fmt.Printf("  go run ./cmd/paytest -base-url %s %s\n", cfg.baseURL, flagRingkas(cfg))
}

// flagRingkas menyusun contoh perintah tanpa membocorkan kredensial.
func flagRingkas(cfg config) string {
	if cfg.bookingID != "" {
		return "-booking-id " + cfg.bookingID
	}
	if cfg.professionalID != "" {
		return "-professional-id " + cfg.professionalID
	}
	return "-professional-id <uuid>"
}
