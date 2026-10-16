package payment

import (
	"context"
	"encoding/json"
	"net/http"
	"testing"
)

// TestMidtransSignatureValid memastikan signature yang dihitung benar
// diterima (tanpa network).
func TestMidtransSignatureValid(t *testing.T) {
	const (
		serverKey  = "SB-Mid-server-testkey"
		orderID    = "TXN-20261020100000-123456"
		statusCode = "200"
		gross      = "150000.00"
	)
	gw := NewMidtransGateway(MidtransConfig{ServerKey: serverKey})
	evt := WebhookEvent{
		OrderID:     orderID,
		StatusCode:  statusCode,
		GrossAmount: gross,
		Signature:   MidtransSignature(orderID, statusCode, gross, serverKey),
	}
	if !gw.VerifySignature(evt) {
		t.Fatal("signature valid seharusnya diterima")
	}
}

// TestMidtransSignatureInvalid memastikan signature salah / server key
// salah / kosong ditolak.
func TestMidtransSignatureInvalid(t *testing.T) {
	const (
		serverKey = "SB-Mid-server-testkey"
		orderID   = "TXN-20261020100000-123456"
		gross     = "150000.00"
	)
	gw := NewMidtransGateway(MidtransConfig{ServerKey: serverKey})

	cases := map[string]WebhookEvent{
		"signature palsu":  {OrderID: orderID, StatusCode: "200", GrossAmount: gross, Signature: "deadbeef"},
		"signature kosong": {OrderID: orderID, StatusCode: "200", GrossAmount: gross},
		"gross diubah": {
			OrderID: orderID, StatusCode: "200", GrossAmount: "1.00",
			Signature: MidtransSignature(orderID, "200", gross, serverKey),
		},
	}
	for name, evt := range cases {
		if gw.VerifySignature(evt) {
			t.Fatalf("%s: seharusnya ditolak", name)
		}
	}

	// Server key berbeda -> signature dari key lain harus gagal.
	other := NewMidtransGateway(MidtransConfig{ServerKey: "kunci-lain"})
	evt := WebhookEvent{
		OrderID: orderID, StatusCode: "200", GrossAmount: gross,
		Signature: MidtransSignature(orderID, "200", gross, serverKey),
	}
	if other.VerifySignature(evt) {
		t.Fatal("signature dari server key lain seharusnya ditolak")
	}

	// Tanpa server key -> selalu false (fail-closed).
	empty := NewMidtransGateway(MidtransConfig{})
	if empty.VerifySignature(evt) {
		t.Fatal("tanpa server key verifikasi harus false")
	}
}

// TestMidtransParseWebhookAndVerify memastikan body notifikasi Midtrans
// ter-decode dan signature-nya tervalidasi end-to-end (tanpa network).
func TestMidtransParseWebhookAndVerify(t *testing.T) {
	const serverKey = "SB-Mid-server-testkey"
	orderID := "TXN-20261020100000-654321"
	gross := "150000.00"
	statusCode := "200"
	sig := MidtransSignature(orderID, statusCode, gross, serverKey)

	payload := map[string]any{
		"order_id":           orderID,
		"status_code":        statusCode,
		"gross_amount":       gross,
		"transaction_status": "settlement",
		"fraud_status":       "accept",
		"signature_key":      sig,
		"transaction_id":     "abc-123",
		"payment_type":       "bank_transfer",
	}
	body, _ := json.Marshal(payload)

	gw := NewMidtransGateway(MidtransConfig{ServerKey: serverKey})
	evt, err := gw.ParseWebhook(body, http.Header{})
	if err != nil {
		t.Fatalf("parse webhook gagal: %v", err)
	}
	if evt.OrderID != orderID || evt.Status != "settlement" || evt.TransactionID != "abc-123" {
		t.Fatalf("event tidak ter-decode dengan benar: %+v", evt)
	}
	if !gw.VerifySignature(evt) {
		t.Fatal("signature hasil parse seharusnya valid")
	}

	// Body kosong / bukan JSON -> error.
	if _, err := gw.ParseWebhook([]byte("  "), nil); err == nil {
		t.Fatal("body kosong seharusnya error")
	}
	if _, err := gw.ParseWebhook([]byte("{not json"), nil); err == nil {
		t.Fatal("body bukan JSON seharusnya error")
	}
}

// TestMidtransSnapBase memastikan pemilihan base URL sesuai env/override.
func TestMidtransSnapBase(t *testing.T) {
	if got := NewMidtransGateway(MidtransConfig{Env: "sandbox"}).SnapBase(); got != SnapBaseSandbox {
		t.Fatalf("sandbox base salah: %s", got)
	}
	if got := NewMidtransGateway(MidtransConfig{Env: "production"}).SnapBase(); got != SnapBaseProduction {
		t.Fatalf("production base salah: %s", got)
	}
	if got := NewMidtransGateway(MidtransConfig{SnapBase: "http://localhost:9000/"}).SnapBase(); got != "http://localhost:9000" {
		t.Fatalf("override base salah: %s", got)
	}
}

// TestMidtransCreateTransactionRequiresKey memastikan CreateTransaction
// menolak lebih awal tanpa server key (tanpa network).
func TestMidtransCreateTransactionRequiresKey(t *testing.T) {
	gw := NewMidtransGateway(MidtransConfig{})
	if _, err := gw.CreateTransaction(context.Background(), "TXN-1", 1000, nil); err == nil {
		t.Fatal("tanpa server key CreateTransaction harus error")
	}
	gw2 := NewMidtransGateway(MidtransConfig{ServerKey: "k"})
	if _, err := gw2.CreateTransaction(context.Background(), "", 1000, nil); err == nil {
		t.Fatal("order_id kosong harus error")
	}
	if _, err := gw2.CreateTransaction(context.Background(), "TXN-1", 0, nil); err == nil {
		t.Fatal("amount 0 harus error")
	}
}
