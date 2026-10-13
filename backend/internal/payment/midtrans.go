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
	"strings"
	"time"
)

// MidtransConfig konfigurasi Midtrans Snap.
type MidtransConfig struct {
	ServerKey string // auth Basic + verifikasi signature
	ClientKey string // dipakai klien (opsional di server)
	Env       string // sandbox | production
	SnapBase  string // override base URL (test/mock); kosong = dari Env
}

// MidtransGateway implementasi PaymentGateway untuk Midtrans Snap.
type MidtransGateway struct {
	serverKey string
	clientKey string
	snapBase  string
	http      *http.Client
}

// SnapBaseSandbox / SnapBaseProduction base URL Snap Midtrans.
const (
	SnapBaseSandbox    = "https://app.sandbox.midtrans.com"
	SnapBaseProduction = "https://app.midtrans.com"
)

// NewMidtransGateway membuat gateway Midtrans. Bila SnapBase kosong,
// base URL dipilih dari Env (default sandbox).
func NewMidtransGateway(cfg MidtransConfig) *MidtransGateway {
	base := strings.TrimRight(strings.TrimSpace(cfg.SnapBase), "/")
	if base == "" {
		if strings.EqualFold(strings.TrimSpace(cfg.Env), "production") {
			base = SnapBaseProduction
		} else {
			base = SnapBaseSandbox
		}
	}
	return &MidtransGateway{
		serverKey: strings.TrimSpace(cfg.ServerKey),
		clientKey: strings.TrimSpace(cfg.ClientKey),
		snapBase:  base,
		http:      &http.Client{Timeout: 20 * time.Second},
	}
}

// SnapBase mengembalikan base URL Snap yang dipakai (untuk log/diagnostik).
func (g *MidtransGateway) SnapBase() string { return g.snapBase }

// midtransChargeRequest body POST /snap/v1/transactions.
type midtransChargeRequest struct {
	TransactionDetails struct {
		OrderID     string `json:"order_id"`
		GrossAmount int64  `json:"gross_amount"`
	} `json:"transaction_details"`
	CustomerDetails map[string]any   `json:"customer_details,omitempty"`
	ItemDetails     []map[string]any `json:"item_details,omitempty"`
}

// midtransChargeResponse respons Snap (subset).
type midtransChargeResponse struct {
	Token       string `json:"token"`
	RedirectURL string `json:"redirect_url"`
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
