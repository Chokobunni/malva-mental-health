package server

import (
	"bytes"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"malva/backend/internal/auth"
	"malva/backend/internal/config"
)

func newGatewayTestServer() (*Server, auth.Manager) {
	cfg := config.Config{
		AllowedOrigins:    []string{"https://api.malva.id"},
		PaymentMode:       config.PaymentModeGateway,
		MidtransServerKey: "SB-Mid-server-testkey",
		MidtransEnv:       "sandbox",
	}
	logger := slog.New(slog.NewTextHandler(testWriter{}, nil))
	mgr := auth.NewManager("12345678901234567890123456789012")
	return New(cfg, mgr, nil, nil, logger), mgr
}

// TestPaymentWebhookRejectsInvalidSignature: signature salah -> 401 tanpa
// menyentuh store (AC-4.2). Server punya gateway tapi store nil.
func TestPaymentWebhookRejectsInvalidSignature(t *testing.T) {
	srv, _ := newGatewayTestServer()
	body := `{"order_id":"TXN-1","status_code":"200","gross_amount":"150000.00","transaction_status":"settlement","signature_key":"deadbeef"}`
	req := httptest.NewRequest(http.MethodPost, "/v1/webhooks/payment", bytes.NewReader([]byte(body)))
	rec := httptest.NewRecorder()
	srv.Routes().ServeHTTP(rec, req)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d (%s)", rec.Code, rec.Body.String())
	}
}

// TestMarkPaidGoneInGatewayMode: mark-paid dinonaktifkan di mode gateway
// (AC-4.4). Dicek sebelum menyentuh store, jadi store nil aman.
func TestMarkPaidGoneInGatewayMode(t *testing.T) {
	srv, mgr := newGatewayTestServer()
	token, _ := mgr.Issue("patient-1", "patient")
	req := httptest.NewRequest(http.MethodPost, "/v1/payments/mark-paid", bytes.NewReader([]byte(`{"reference":"TXN-1"}`)))
	req.Header.Set("Authorization", "Bearer "+token)
	rec := httptest.NewRecorder()
	srv.Routes().ServeHTTP(rec, req)
	if rec.Code != http.StatusGone {
		t.Fatalf("expected 410, got %d (%s)", rec.Code, rec.Body.String())
	}
}

// TestDefaultRefundKey memastikan kunci idempotensi default deterministik.
func TestDefaultRefundKey(t *testing.T) {
	if got := defaultRefundKey("sess-1", "refund"); got != "refund:care_session:sess-1:refund" {
		t.Fatalf("kunci refund salah: %s", got)
	}
	if got := defaultRefundKey("sess-1", "credit"); got != "refund:care_session:sess-1:credit" {
		t.Fatalf("kunci credit salah: %s", got)
	}
}

// TestParseGrossAmount memastikan parsing gross_amount Midtrans ("150000.00").
func TestParseGrossAmount(t *testing.T) {
	cases := map[string]int64{
		"150000.00": 150000,
		"125000":    125000,
		"":          0,
		"abc":       0,
		"0.00":      0,
	}
	for in, want := range cases {
		if got := parseGrossAmount(in); got != want {
			t.Fatalf("parseGrossAmount(%q)=%d, want %d", in, got, want)
		}
	}
}
