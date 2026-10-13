// Package payment menyediakan abstraksi gateway pembayaran sehingga
// provider (Midtrans, kelak Xendit) bisa ditukar tanpa menyentuh handler.
package payment

import (
	"context"
	"net/http"
)

// PaymentIntent hasil pembuatan transaksi di gateway (mis. Snap Midtrans).
type PaymentIntent struct {
	OrderID     string `json:"order_id"`
	Token       string `json:"token"`        // snap_token
	RedirectURL string `json:"redirect_url"` // halaman pembayaran gateway
}

// WebhookEvent event notifikasi pembayaran yang sudah dinormalisasi.
// Field mengikuti bentuk notifikasi Midtrans (order_id + status_code +
// gross_amount + transaction_status + signature_key).
type WebhookEvent struct {
	OrderID       string `json:"order_id"`
	StatusCode    string `json:"status_code"`
	GrossAmount   string `json:"gross_amount"` // string desimal, mis. "150000.00"
	Status        string `json:"transaction_status"`
	FraudStatus   string `json:"fraud_status"`
	Signature     string `json:"signature_key"`
	TransactionID string `json:"transaction_id"`
	PaymentType   string `json:"payment_type"`
	Raw           []byte `json:"-"`
}

// PaymentGateway kontrak minimal yang dipakai server. Implementasi
// menangani auth + verifikasi signature sesuai provider.
type PaymentGateway interface {
	// CreateTransaction membuat transaksi dan mengembalikan token/redirect.
	CreateTransaction(ctx context.Context, orderID string, amount int64, customer map[string]any) (PaymentIntent, error)
	// ParseWebhook mendekode body notifikasi menjadi WebhookEvent.
	ParseWebhook(body []byte, headers http.Header) (WebhookEvent, error)
	// VerifySignature memvalidasi keaslian notifikasi (tanpa network).
	VerifySignature(evt WebhookEvent) bool
}
