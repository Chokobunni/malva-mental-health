package server

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
	"malva/backend/internal/payment"
	"malva/backend/internal/store"
)

// ============================================================
// WEBHOOK PEMBAYARAN — LEVEL HTTP (bukan activatePaidBooking langsung)
//
// Test di activation_slot_terminal_test.go memanggil activatePaidBooking
// secara langsung. Yang menentukan nasib gateway (retry 5xx selamanya vs
// selesai) adalah RESPONS HTTP paymentWebhook. Berkas ini menguji jalur
// lengkap: ParseWebhook -> VerifySignature -> RecordPaymentEvent ->
// MarkPaymentPaid -> activatePaidBooking -> status payment_events + balasan.
//
// Memakai gateway Midtrans ASLI (signature dihitung seperti Midtrans) supaya
// verifikasi signature benar-benar dijalankan, bukan di-fake.
// ============================================================

const webhookTestServerKey = "SB-Mid-server-WEBHOOKTESTKEY"

// newWebhookServer membangun Server dengan gateway Midtrans asli + kalender
// fake di atas store DB test.
func newWebhookServer(t *testing.T, db *sql.DB, cal meetCalendar) *Server {
	t.Helper()
	srv := newOnboardingTestServer(db)
	srv.payment = payment.NewMidtransGateway(payment.MidtransConfig{ServerKey: webhookTestServerKey})
	srv.calendar = cal
	return srv
}

// createPendingBookingAt membuat booking 'pending' + payment 'pending' pada
// slot start (boleh di masa lalu: CreateBooking tidak memvalidasi waktu).
// Mendaftarkan cleanup untuk care_sessions & payment_events (tak punya FK ke
// users sehingga tidak ikut terhapus saat user dibersihkan).
func createPendingBookingAt(t *testing.T, db *sql.DB, st *store.Store,
	patientID, profID, serviceType, sessionType string, start time.Time) (store.Booking, store.Payment) {
	t.Helper()
	ctx := context.Background()
	ref := fmt.Sprintf("REF-WH-%d", time.Now().UnixNano())

	t.Cleanup(func() {
		cctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		_, _ = db.ExecContext(cctx, `DELETE FROM care_sessions WHERE patient_id = $1`, patientID)
		_, _ = db.ExecContext(cctx, `DELETE FROM payment_events WHERE external_id = $1`, ref)
	})

	b, err := st.CreateBooking(ctx, store.Booking{
		PatientID:       patientID,
		ProfessionalID:  profID,
		ServiceType:     serviceType,
		SessionType:     sessionType,
		BookingDate:     start.In(wibLoc).Format("2006-01-02"),
		SlotTime:        start.In(wibLoc).Format("15:04"),
		DurationMinutes: 30,
		Price:           100000,
	})
	if err != nil {
		t.Fatalf("buat booking: %v", err)
	}
	p, err := st.CreatePayment(ctx, store.Payment{
		BookingID:         b.ID,
		PaymentMethod:     "qris",
		GrossAmount:       100000,
		ServiceFeeAmount:  2000,
		PlatformFeeAmount: 10000,
		NetAmount:         90000,
		Reference:         ref,
	})
	if err != nil {
		t.Fatalf("buat payment: %v", err)
	}
	return b, p
}

// postSettlement mengirim notifikasi settlement Midtrans yang valid
// (signature dihitung dari serverKey) ke handler paymentWebhook.
func postSettlement(t *testing.T, srv *Server, reference, gross string) *httptest.ResponseRecorder {
	t.Helper()
	evt := map[string]string{
		"order_id":           reference,
		"status_code":        "200",
		"gross_amount":       gross,
		"transaction_status": "settlement",
		"transaction_id":     "txn-" + reference,
		"fraud_status":       "accept",
		"signature_key":      payment.MidtransSignature(reference, "200", gross, webhookTestServerKey),
	}
	body, err := json.Marshal(evt)
	if err != nil {
		t.Fatalf("marshal webhook: %v", err)
	}
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/webhooks/payment", bytes.NewReader(body))
	srv.paymentWebhook(rec, req)
	return rec
}

// TestPaymentWebhookSlotPassedReturns200AndNoSession membuktikan di level HTTP
// bahwa settlement untuk slot yang sudah lewat (2 jam lalu) TIDAK memicu 5xx
// (yang akan diulang gateway selamanya), tidak membuat sesi masa lalu, dan
// menandai event 'processed'.
func TestPaymentWebhookSlotPassedReturns200AndNoSession(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	srv := newWebhookServer(t, db, nil) // chat: tidak butuh kalender
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      fmt.Sprint("STR-WH-", time.Now().UnixNano()),
		SIPNumber:      fmt.Sprint("SIP-WH-", time.Now().UnixNano()),
	})

	start := clock.Now().In(wibLoc).Add(-2 * time.Hour)
	booking, pay := createPendingBookingAt(t, db, st, patient.ID, prof.ID, "quick_consult", "chat", start)

	rec := postSettlement(t, srv, pay.Reference, "102000.00")
	if rec.Code != http.StatusOK {
		t.Fatalf("status webhook = %d, mau 200 (uang sudah masuk, 5xx = retry selamanya): %s", rec.Code, rec.Body.String())
	}

	// Tidak ada sesi masa lalu.
	if _, err := st.GetCareSessionByBookingID(context.Background(), booking.ID); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("tidak boleh ada sesi untuk slot lewat, dapat err = %v", err)
	}
	// Event ditandai processed (bukan 'received' yang akan diproses ulang).
	status, found, err := st.PaymentEventStatus(context.Background(), "midtrans", pay.Reference, "settlement")
	if err != nil || !found {
		t.Fatalf("event payment tidak tercatat: found=%v err=%v", found, err)
	}
	if status != "processed" {
		t.Errorf("status event = %q, mau \"processed\"", status)
	}
	// Booking tetap 'paid' untuk rekonsiliasi manual.
	saved, err := st.GetBooking(context.Background(), booking.ID)
	if err != nil {
		t.Fatalf("baca booking: %v", err)
	}
	if saved.Status != "paid" {
		t.Errorf("status booking = %q, mau tetap \"paid\"", saved.Status)
	}
	// Kedua pihak dinotifikasi sekali.
	assertRescheduleNotified(t, st, patient.ID, prof.ID, booking.ID)
}

// TestPaymentWebhookReplayDoesNotDuplicate mengirim notifikasi settlement yang
// SAMA tiga kali: tiap kiriman harus 200, tidak ada sesi ganda, dan notifikasi
// tidak berlipat (event 'processed' menelan replay tanpa menjalankan ulang
// aktivasi).
func TestPaymentWebhookReplayDoesNotDuplicate(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	srv := newWebhookServer(t, db, nil)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      fmt.Sprint("STR-WH-", time.Now().UnixNano()),
		SIPNumber:      fmt.Sprint("SIP-WH-", time.Now().UnixNano()),
	})

	start := clock.Now().In(wibLoc).Add(-2 * time.Hour)
	booking, pay := createPendingBookingAt(t, db, st, patient.ID, prof.ID, "quick_consult", "chat", start)

	for i := 0; i < 3; i++ {
		rec := postSettlement(t, srv, pay.Reference, "102000.00")
		if rec.Code != http.StatusOK {
			t.Fatalf("kiriman ke-%d status = %d, mau 200: %s", i+1, rec.Code, rec.Body.String())
		}
	}

	if _, err := st.GetCareSessionByBookingID(context.Background(), booking.ID); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("replay tidak boleh membuat sesi, dapat err = %v", err)
	}
	// Dedupe: tetap 1 notifikasi per pengguna walau dikirim 3x.
	assertRescheduleNotified(t, st, patient.ID, prof.ID, booking.ID)
}

// TestPaymentWebhookSuccessfulActivationReplayNoDuplicateSession membuktikan
// jalur SUKSES penuh di level HTTP: settlement untuk slot masa depan dengan
// Google siap membuat tepat satu sesi + link. Pengulangan webhook yang sama 3x
// tetap 200 tanpa sesi kedua dan tanpa notifikasi berlipat (idempoten).
func TestPaymentWebhookSuccessfulActivationReplayNoDuplicateSession(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	const wantURL = "https://meet.google.com/suc-ces-ok1"
	fake := &fakeMeetCalendar{createEventID: "evt-wh-ok", createMeetURL: wantURL}
	srv := newWebhookServer(t, db, fake)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      fmt.Sprint("STR-WH-", time.Now().UnixNano()),
		SIPNumber:      fmt.Sprint("SIP-WH-", time.Now().UnixNano()),
	})
	linkReadyProfessional(t, st, prof.ID)

	start := clock.Now().In(wibLoc).AddDate(0, 0, 3)
	booking, pay := createPendingBookingAt(t, db, st, patient.ID, prof.ID, "quick_consult_video", "video", start)

	for i := 0; i < 3; i++ {
		rec := postSettlement(t, srv, pay.Reference, "102000.00")
		if rec.Code != http.StatusOK {
			t.Fatalf("kiriman ke-%d status = %d, mau 200: %s", i+1, rec.Code, rec.Body.String())
		}
	}

	session, err := st.GetCareSessionByBookingID(context.Background(), booking.ID)
	if err != nil {
		t.Fatalf("sesi berbayar tidak tersimpan: %v", err)
	}
	if session.MeetingURL != wantURL {
		t.Errorf("meeting_url = %q, mau %q", session.MeetingURL, wantURL)
	}
	// Tepat satu sesi (tidak ada sesi ganda): hitung semua sesi untuk booking.
	if n := countSessionsForBooking(t, db, booking.ID); n != 1 {
		t.Fatalf("jumlah sesi untuk booking = %d, mau 1 (replay tidak boleh membuat sesi ganda)", n)
	}
	if fake.createCalls != 1 {
		t.Errorf("CreateMeetEvent dipanggil %d kali, mau 1", fake.createCalls)
	}
	// Notifikasi sesi terjadwal tidak berlipat walau webhook 3x.
	for _, uid := range []string{patient.ID, prof.ID} {
		if n := countNotifications(t, st, uid, "session_scheduled", booking.ID); n > 1 {
			t.Errorf("notifikasi session_scheduled user %q = %d, mau ≤1", uid, n)
		}
	}
}

// countSessionsForBooking menghitung baris care_sessions untuk sebuah booking.
func countSessionsForBooking(t *testing.T, db *sql.DB, bookingID string) int {
	t.Helper()
	var n int
	if err := db.QueryRowContext(context.Background(),
		`SELECT COUNT(*) FROM care_sessions WHERE booking_id = $1`, bookingID).Scan(&n); err != nil {
		t.Fatalf("hitung sesi booking: %v", err)
	}
	return n
}

// level HTTP: settlement untuk slot yang keburu TERISI sesi lain membalas 200,
// booking tetap 'paid' (tidak kembali ke 'pending'), dan pembuatan payment
// baru untuk booking itu ditolak — inti C6 (tidak bisa bayar dua kali).
func TestPaymentWebhookSlotTakenKeepsPaidAndBlocksSecondPayment(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	srv := newWebhookServer(t, db, nil)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	other := createIdentityTestUser(t, db, st, "patient", nil)
	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      fmt.Sprint("STR-WH-", time.Now().UnixNano()),
		SIPNumber:      fmt.Sprint("SIP-WH-", time.Now().UnixNano()),
	})

	start := clock.Now().In(wibLoc).AddDate(0, 0, 3)
	booking, pay := createPendingBookingAt(t, db, st, patient.ID, prof.ID, "quick_consult", "chat", start)
	startAt, err := parseWIBDateTime(booking.BookingDate + "T" + booking.SlotTime)
	if err != nil {
		t.Fatalf("parse slot: %v", err)
	}
	// Sesi lain sudah menempati slot itu.
	t.Cleanup(func() {
		cctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		_, _ = db.ExecContext(cctx, `DELETE FROM care_sessions WHERE patient_id = $1`, other.ID)
	})
	if _, err := st.CreateCareSession(context.Background(), store.CareSession{
		PatientID:       other.ID,
		ProfessionalID:  prof.ID,
		SessionType:     "chat",
		ScheduledAt:     startAt,
		DurationMinutes: 30,
		Status:          "scheduled",
	}); err != nil {
		t.Fatalf("buat sesi penempat slot: %v", err)
	}

	rec := postSettlement(t, srv, pay.Reference, "102000.00")
	if rec.Code != http.StatusOK {
		t.Fatalf("status webhook = %d, mau 200: %s", rec.Code, rec.Body.String())
	}
	if _, err := st.GetCareSessionByBookingID(context.Background(), booking.ID); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("tidak boleh ada sesi kedua di slot yang sama, dapat err = %v", err)
	}
	saved, err := st.GetBooking(context.Background(), booking.ID)
	if err != nil {
		t.Fatalf("baca booking: %v", err)
	}
	if saved.Status != "paid" {
		t.Fatalf("status booking = %q, mau \"paid\" (bukan kembali ke pending)", saved.Status)
	}
	assertRescheduleNotified(t, st, patient.ID, prof.ID, booking.ID)

	// Bukti tidak bisa bayar dua kali di level HTTP: POST /v1/payments ditolak.
	body := `{"booking_id":"` + booking.ID + `","payment_method":"qris"}`
	req := httptest.NewRequest(http.MethodPost, "/v1/payments", bytes.NewReader([]byte(body)))
	recPay := httptest.NewRecorder()
	srv.createPayment(recPay, req, auth.Claims{Subject: patient.ID, Role: "patient"})
	if recPay.Code != http.StatusCreated || !strings.Contains(recPay.Body.String(), pay.Reference) || !strings.Contains(recPay.Body.String(), `"status":"paid"`) {
		t.Fatalf("retry must return the existing paid payment: %d %s", recPay.Code, recPay.Body.String())
	}
}
