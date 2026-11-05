package payment

import (
	"bytes"
	"context"
	"crypto/sha512"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// MidtransConfig konfigurasi Midtrans Snap.
type MidtransConfig struct {
	ServerKey string // auth Basic + verifikasi signature
	ClientKey string // dipakai klien (opsional di server)
	Env       string // sandbox | production
	SnapBase  string // override base URL (test/mock); kosong = dari Env
	// APIBase override base URL API status (`/v2/{order_id}/status`) untuk
	// test/mock; kosong = dari Env. Host API BERBEDA dari host Snap.
	APIBase string
}

// MidtransGateway implementasi PaymentGateway untuk Midtrans Snap.
type MidtransGateway struct {
	serverKey string
	clientKey string
	snapBase  string
	apiBase   string
	http      *http.Client
}

// SnapBaseSandbox / SnapBaseProduction base URL Snap Midtrans.
const (
	SnapBaseSandbox    = "https://app.sandbox.midtrans.com"
	SnapBaseProduction = "https://app.midtrans.com"
)

// APIBaseSandbox / APIBaseProduction base URL API Midtrans (cek status
// transaksi). Berbeda host dari Snap: `api.*`, bukan `app.*`.
const (
	APIBaseSandbox    = "https://api.sandbox.midtrans.com"
	APIBaseProduction = "https://api.midtrans.com"
)

// NewMidtransGateway membuat gateway Midtrans. Bila SnapBase/APIBase kosong,
// base URL dipilih dari Env (default sandbox).
func NewMidtransGateway(cfg MidtransConfig) *MidtransGateway {
	production := strings.EqualFold(strings.TrimSpace(cfg.Env), "production")
	base := strings.TrimRight(strings.TrimSpace(cfg.SnapBase), "/")
	if base == "" {
		if production {
			base = SnapBaseProduction
		} else {
			base = SnapBaseSandbox
		}
	}
	apiBase := strings.TrimRight(strings.TrimSpace(cfg.APIBase), "/")
	if apiBase == "" {
		if production {
			apiBase = APIBaseProduction
		} else {
			apiBase = APIBaseSandbox
		}
	}
	return &MidtransGateway{
		serverKey: strings.TrimSpace(cfg.ServerKey),
		clientKey: strings.TrimSpace(cfg.ClientKey),
		snapBase:  base,
		apiBase:   apiBase,
		http:      &http.Client{Timeout: 20 * time.Second},
	}
}

// SnapBase mengembalikan base URL Snap yang dipakai (untuk log/diagnostik).
func (g *MidtransGateway) SnapBase() string { return g.snapBase }

// APIBase mengembalikan base URL API status yang dipakai (log/diagnostik).
func (g *MidtransGateway) APIBase() string { return g.apiBase }

// midtransChargeRequest body POST /snap/v1/transactions.
type midtransChargeRequest struct {
	TransactionDetails struct {
		OrderID     string `json:"order_id"`
		GrossAmount int64  `json:"gross_amount"`
	} `json:"transaction_details"`
	CustomerDetails map[string]any   `json:"customer_details,omitempty"`
	ItemDetails     []map[string]any `json:"item_details,omitempty"`
	Callbacks       struct {
		Finish string `json:"finish"`
	} `json:"callbacks"`
}

// midtransChargeResponse respons Snap (subset).
type midtransChargeResponse struct {
	Token         string   `json:"token"`
	RedirectURL   string   `json:"redirect_url"`
	ErrorMessages []string `json:"error_messages"`
}

// CreateTransaction memanggil Snap API untuk membuat token pembayaran.
func (g *MidtransGateway) CreateTransaction(ctx context.Context, orderID string, amount int64, customer map[string]any) (PaymentIntent, error) {
	if g.serverKey == "" {
		return PaymentIntent{}, errors.New("midtrans server key belum dikonfigurasi")
	}
	if strings.TrimSpace(orderID) == "" {
		return PaymentIntent{}, errors.New("order_id wajib diisi")
	}
	if amount <= 0 {
		return PaymentIntent{}, errors.New("gross_amount harus > 0")
	}
	var body midtransChargeRequest
	body.TransactionDetails.OrderID = orderID
	body.TransactionDetails.GrossAmount = amount
	body.CustomerDetails = customer
	body.Callbacks.Finish = "malva://payment/return?reference=" + url.QueryEscape(orderID)
	raw, err := json.Marshal(body)
	if err != nil {
		return PaymentIntent{}, err
	}
	endpoint := g.snapBase + "/snap/v1/transactions"
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, endpoint, bytes.NewReader(raw))
	if err != nil {
		return PaymentIntent{}, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Accept", "application/json")
	// Basic auth: base64(serverKey + ":") tanpa password.
	req.Header.Set("Authorization", "Basic "+base64.StdEncoding.EncodeToString([]byte(g.serverKey+":")))

	resp, err := g.http.Do(req)
	if err != nil {
		return PaymentIntent{}, err
	}
	defer func() { _ = resp.Body.Close() }()
	respBody, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return PaymentIntent{}, err
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return PaymentIntent{}, fmt.Errorf("midtrans snap error %d: %s", resp.StatusCode, strings.TrimSpace(string(respBody)))
	}
	var out midtransChargeResponse
	if err := json.Unmarshal(respBody, &out); err != nil {
		return PaymentIntent{}, err
	}
	if out.Token == "" {
		return PaymentIntent{}, fmt.Errorf("midtrans snap tidak mengembalikan token: %s", strings.TrimSpace(string(respBody)))
	}
	return PaymentIntent{OrderID: orderID, Token: out.Token, RedirectURL: out.RedirectURL}, nil
}

// midtransStatusResponse respons `GET /v2/{order_id}/status` (subset).
type midtransStatusResponse struct {
	OrderID           string `json:"order_id"`
	StatusCode        string `json:"status_code"`
	StatusMessage     string `json:"status_message"`
	GrossAmount       string `json:"gross_amount"`
	TransactionStatus string `json:"transaction_status"`
	FraudStatus       string `json:"fraud_status"`
	TransactionID     string `json:"transaction_id"`
	SignatureKey      string `json:"signature_key"`
}

// FetchStatus menanyakan status transaksi terkini ke API Midtrans
// (`GET /v2/{order_id}/status`). Dipakai saat webhook belum tiba sehingga
// polling klien tidak bergantung pada ketepatan waktu notifikasi.
//
// Keamanan: GET langsung ke API HTTPS Midtrans memakai server-key Basic auth
// adalah verifikasi otoritatif, berbeda dari webhook masuk yang wajib memiliki
// signature valid. Respons GET tidak mensyaratkan verifikasi signature webhook.
// Identitas order tetap harus persis sama dengan permintaan;
// pemanggil juga memverifikasi gross_amount dan fraud_status sebelum aktivasi.
//
// "Transaksi belum ada" BUKAN kegagalan dan TIDAK membawa signature: Midtrans
// membalas HTTP 200 dengan `status_code:"404"` di dalam body. Itu dikembalikan
// sebagai status "pending" tanpa error (lihat catatan di badan fungsi).
func (g *MidtransGateway) FetchStatus(ctx context.Context, orderID string) (GatewayStatus, error) {
	if g.serverKey == "" {
		return GatewayStatus{}, errors.New("midtrans server key belum dikonfigurasi")
	}
	orderID = strings.TrimSpace(orderID)
	if orderID == "" {
		return GatewayStatus{}, errors.New("order_id wajib diisi")
	}
	endpoint := g.apiBase + "/v2/" + url.PathEscape(orderID) + "/status"
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return GatewayStatus{}, err
	}
	req.Header.Set("Accept", "application/json")
	req.Header.Set("Authorization", "Basic "+base64.StdEncoding.EncodeToString([]byte(g.serverKey+":")))

	resp, err := g.http.Do(req)
	if err != nil {
		return GatewayStatus{}, err
	}
	defer func() { _ = resp.Body.Close() }()
	body, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return GatewayStatus{}, err
	}
	if resp.StatusCode == http.StatusNotFound {
		// Transaksi belum ada di sisi Midtrans (mis. token baru dibuat dan
		// belum dipakai membayar). Perlakukan seperti pending.
		return GatewayStatus{Status: "pending", StatusCode: "404"}, nil
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return GatewayStatus{}, fmt.Errorf("midtrans status error %d: %s", resp.StatusCode, strings.TrimSpace(string(body)))
	}
	var out midtransStatusResponse
	if err := json.Unmarshal(body, &out); err != nil {
		return GatewayStatus{}, fmt.Errorf("respons status midtrans tidak valid: %w", err)
	}
	// PENTING (hasil uji langsung ke sandbox): untuk transaksi yang BELUM ADA,
	// Midtrans membalas **HTTP 200** dengan `status_code: "404"` DI DALAM BODY
	// — bukan HTTP 404 — dan respons itu TIDAK membawa `signature_key` maupun
	// `gross_amount`:
	//   {"status_code":"404","status_message":"Transaction doesn't exist.",...}
	// Kondisi ini normal (token Snap baru dibuat, pengguna belum membayar), jadi
	// harus diperlakukan pending TANPA error — kalau tidak, endpoint polling
	// mencatat error tiap 3 detik dan bisa menolak respons karena signature kosong.
	statusCode := strings.TrimSpace(out.StatusCode)
	msg := strings.ToLower(strings.TrimSpace(out.StatusMessage))
	notFound := statusCode == "404" ||
		strings.Contains(msg, "doesn't exist") ||
		strings.Contains(msg, "doesnt exist")
	if notFound {
		return GatewayStatus{Status: "pending", StatusCode: statusCode}, nil
	}

	// Kode status lain di luar "200" tidak kita pahami: perlakukan sebagai
	// pending tanpa error agar polling tidak pernah gagal karena hal yang tidak
	// dikenali.
	if statusCode != "200" {
		return GatewayStatus{Status: "pending", StatusCode: statusCode}, nil
	}

	// Respons berasal dari permintaan backend terautentikasi ke API Midtrans.
	// Jangan terapkan aturan signature webhook di sini; tetap tolak transaksi
	// lain, bahkan bila nominal atau signature kebetulan sama.
	if out.OrderID != orderID {
		return GatewayStatus{}, errors.New("order_id respons status midtrans tidak cocok")
	}

	// `transaction_status` kosong/tak dikenal juga diperlakukan pending.
	txStatus := strings.ToLower(strings.TrimSpace(out.TransactionStatus))
	switch txStatus {
	case "settlement", "capture", "pending", "expire", "cancel", "deny":
	default:
		txStatus = "pending"
	}
	return GatewayStatus{
		Status:        txStatus,
		FraudStatus:   strings.ToLower(strings.TrimSpace(out.FraudStatus)),
		StatusCode:    statusCode,
		GrossAmount:   strings.TrimSpace(out.GrossAmount),
		TransactionID: strings.TrimSpace(out.TransactionID),
	}, nil
}

// ParseWebhook mendekode notifikasi Midtrans menjadi WebhookEvent.
func (g *MidtransGateway) ParseWebhook(body []byte, _ http.Header) (WebhookEvent, error) {
	if len(bytes.TrimSpace(body)) == 0 {
		return WebhookEvent{}, errors.New("body webhook kosong")
	}
	var evt WebhookEvent
	if err := json.Unmarshal(body, &evt); err != nil {
		return WebhookEvent{}, fmt.Errorf("body webhook tidak valid: %w", err)
	}
	evt.Raw = body
	if strings.TrimSpace(evt.OrderID) == "" {
		return WebhookEvent{}, errors.New("order_id wajib ada pada notifikasi")
	}
	return evt, nil
}

// VerifySignature memvalidasi signature Midtrans:
// sha512(order_id + status_code + gross_amount + serverKey) == signature_key.
func (g *MidtransGateway) VerifySignature(evt WebhookEvent) bool {
	if g.serverKey == "" {
		return false
	}
	expected := MidtransSignature(evt.OrderID, evt.StatusCode, evt.GrossAmount, g.serverKey)
	got := strings.ToLower(strings.TrimSpace(evt.Signature))
	return got != "" && subtleConstantEqual(expected, got)
}

// MidtransSignature menghitung sha512 hex dari gabungan field notifikasi.
// Diekspor agar dapat diuji dan dipakai tooling lokal.
func MidtransSignature(orderID, statusCode, grossAmount, serverKey string) string {
	sum := sha512.Sum512([]byte(orderID + statusCode + grossAmount + serverKey))
	return hex.EncodeToString(sum[:])
}

// subtleConstantEqual membandingkan dua string hex dengan waktu konstan.
func subtleConstantEqual(a, b string) bool {
	if len(a) != len(b) {
		return false
	}
	var diff byte
	for i := 0; i < len(a); i++ {
		diff |= a[i] ^ b[i]
	}
	return diff == 0
}
