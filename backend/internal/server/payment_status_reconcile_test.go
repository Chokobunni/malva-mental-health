package server

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log/slog"
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
// POLLING OTORITATIF KE GATEWAY
//
// Status `paid` di DB hanya lahir dari webhook. Bila notifikasi gateway telat
// (atau URL notifikasi belum diisi), pasien yang SUDAH membayar akan terus
// melihat "Menunggu pembayaran". Karena itu GET /v1/payments/{reference}
// menanyakan status langsung ke gateway saat pembayaran masih `pending`.
//
// Yang dikunci di sini:
//   - settlement/capture -> ditandai lunas + sesi lahir (idempoten);
//   - pending/expire/cancel/deny & fraud challenge -> tidak mengubah apa pun;
//   - kegagalan gateway tidak pernah menggagalkan respons (200 + status DB);
//   - payment yang masih terlalu baru (< 5 detik) tidak ditanyakan ke gateway;
//   - gateway tanpa dukungan StatusFetcher tetap 200 memakai status DB.
// ============================================================

// fakeStatusGateway mengimplementasikan PaymentGateway + StatusFetcher.
type fakeStatusGateway struct {
	status payment.GatewayStatus
	err    error
	calls  int
}

func (f *fakeStatusGateway) CreateTransaction(context.Context, string, int64, map[string]any) (payment.PaymentIntent, error) {
	return payment.PaymentIntent{}, nil
}

func (f *fakeStatusGateway) ParseWebhook([]byte, http.Header) (payment.WebhookEvent, error) {
	return payment.WebhookEvent{}, nil
}

func (f *fakeStatusGateway) VerifySignature(payment.WebhookEvent) bool { return false }

func (f *fakeStatusGateway) FetchStatus(context.Context, string) (payment.GatewayStatus, error) {
	f.calls++
	return f.status, f.err
}

// fakeLegacyGateway hanya memenuhi PaymentGateway (tanpa FetchStatus) — meniru
// gateway yang tidak mendukung pemeriksaan status.
type fakeLegacyGateway struct{}

func (f *fakeLegacyGateway) CreateTransaction(context.Context, string, int64, map[string]any) (payment.PaymentIntent, error) {
	return payment.PaymentIntent{}, nil
}

func (f *fakeLegacyGateway) ParseWebhook([]byte, http.Header) (payment.WebhookEvent, error) {
	return payment.WebhookEvent{}, nil
}

func (f *fakeLegacyGateway) VerifySignature(payment.WebhookEvent) bool { return false }

type reconcileFixture struct {
	srv     *Server
	db      *sql.DB
	st      *store.Store
	patient store.User
	prof    store.User
}

func newReconcileFixture(t *testing.T, gw payment.PaymentGateway) reconcileFixture {
	t.Helper()
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      fmt.Sprint("STR-RC2-", time.Now().UnixNano()),
		SIPNumber:      fmt.Sprint("SIP-RC2-", time.Now().UnixNano()),
	})
	srv := newOnboardingTestServer(db)
	srv.payment = gw
	return reconcileFixture{srv: srv, db: db, st: st, patient: patient, prof: prof}
}

// pendingPayment membuat booking + payment pending ber-gateway midtrans dengan
// umur tertentu (age) agar ambang 5 detik bisa diuji.
func (f reconcileFixture) pendingPayment(t *testing.T, age time.Duration) (store.Booking, store.Payment) {
	t.Helper()
	ctx := context.Background()
	start := clock.Now().In(wibLoc).AddDate(0, 0, 3)
	booking, pay := createPendingBookingAt(t, f.db, f.st, f.patient.ID, f.prof.ID,
		"quick_consult", "chat", start)
	if _, err := f.st.UpdatePaymentGateway(ctx, pay.Reference, "midtrans",
		"snap-token", "https://app.sandbox.midtrans.com/snap/v4/redirection/x"); err != nil {
		t.Fatalf("tandai payment sebagai transaksi gateway: %v", err)
	}
	if _, err := f.db.ExecContext(ctx,
		`UPDATE payments SET created_at = now() - make_interval(secs => $2) WHERE id = $1`,
		pay.ID, age.Seconds()); err != nil {
		t.Fatalf("atur umur payment: %v", err)
	}
	return booking, pay
}

// statusResult memanggil handler status sebagai pasien pemilik.
func (f reconcileFixture) statusResult(t *testing.T, reference string) (int, map[string]any) {
	t.Helper()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/v1/payments/"+reference, nil)
	req.SetPathValue("reference", reference)
	f.srv.getPaymentStatus(rec, req, auth.Claims{Subject: f.patient.ID, Role: "patient"})
	var payload map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &payload)
	return rec.Code, payload
}

func paymentStatusOf(t *testing.T, payload map[string]any) string {
	t.Helper()
	raw, ok := payload["payment"].(map[string]any)
	if !ok {
		t.Fatalf("respons tidak memuat objek payment: %+v", payload)
	}
	return fmt.Sprint(raw["status"])
}

// Exercise the real HTTP gateway and persistence path, rather than a fake
// StatusFetcher that bypasses provider response validation.
func TestPaymentStatusReconcilesAuthenticatedCapture(t *testing.T) {
	for _, tc := range []struct {
		name, returnedOrder, amount, fraud, wantStatus string
		wantSessions                                   int
	}{
		{name: "capture_without_webhook_signature", amount: "102000.00", fraud: "accept", wantStatus: "paid", wantSessions: 1},
		{name: "wrong_order", returnedOrder: "TXN-OTHER", amount: "102000.00", fraud: "accept", wantStatus: "pending"},
		{name: "wrong_amount", amount: "1.00", fraud: "accept", wantStatus: "pending"},
		{name: "fraud_challenge", amount: "102000.00", fraud: "challenge", wantStatus: "pending"},
		{name: "fraud_deny", amount: "102000.00", fraud: "deny", wantStatus: "pending"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var reference string
			provider := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				key, password, ok := r.BasicAuth()
				if r.Method != http.MethodGet || r.URL.Path != "/v2/"+reference+"/status" || !ok || key != "sandbox-status-test-key" || password != "" {
					w.WriteHeader(http.StatusUnauthorized)
					return
				}
				order := reference
				if tc.returnedOrder != "" {
					order = tc.returnedOrder
				}
				_ = json.NewEncoder(w).Encode(map[string]string{
					"order_id": order, "status_code": "200", "status_message": "Success, transaction found",
					"transaction_status": "capture", "fraud_status": tc.fraud, "gross_amount": tc.amount,
					"transaction_id": "captured-status-transaction", "payment_type": "credit_card", "currency": "IDR",
				})
			}))
			defer provider.Close()
			gateway := payment.NewMidtransGateway(payment.MidtransConfig{ServerKey: "sandbox-status-test-key", APIBase: provider.URL})
			f := newReconcileFixture(t, gateway)
			booking, pay := f.pendingPayment(t, 10*time.Second)
			reference = pay.Reference
			for attempt := 0; attempt < 2; attempt++ {
				code, payload := f.statusResult(t, pay.Reference)
				if code != http.StatusOK || paymentStatusOf(t, payload) != tc.wantStatus {
					t.Fatalf("capture reconciliation: HTTP %d status=%s, want %s", code, paymentStatusOf(t, payload), tc.wantStatus)
				}
				if n := countSessionsForBooking(t, f.db, booking.ID); n != tc.wantSessions {
					t.Fatalf("sessions=%d, want %d", n, tc.wantSessions)
				}
			}
		})
	}
}

// TestPaymentStatusReconcileMarksPaidFromGateway: webhook belum tiba, tetapi
// gateway bilang settlement -> pembayaran jadi lunas, sesi lahir, dan
// panggilan kedua tidak membuat sesi tambahan.
func TestPaymentStatusReconcileMarksPaidFromGateway(t *testing.T) {
	gw := &fakeStatusGateway{status: payment.GatewayStatus{
		Status: "settlement", FraudStatus: "accept", TransactionID: "txn-ok", GrossAmount: "102000.00",
	}}
	f := newReconcileFixture(t, gw)
	booking, pay := f.pendingPayment(t, 10*time.Second)

	code, payload := f.statusResult(t, pay.Reference)
	if code != http.StatusOK {
		t.Fatalf("status = %d, mau 200", code)
	}
	if got := paymentStatusOf(t, payload); got != "paid" {
		t.Fatalf("status payment = %q, mau \"paid\" (gateway bilang settlement)", got)
	}
	if fmt.Sprint(payload["session_id"]) == "" {
		t.Fatalf("session_id kosong: sesi tidak dibuat setelah pembayaran lunas")
	}
	if n := countSessionsForBooking(t, f.db, booking.ID); n != 1 {
		t.Fatalf("jumlah sesi = %d, mau 1", n)
	}

	// Idempoten: polling berikutnya tidak menambah sesi.
	code, payload = f.statusResult(t, pay.Reference)
	if code != http.StatusOK {
		t.Fatalf("panggilan kedua status = %d, mau 200", code)
	}
	if got := paymentStatusOf(t, payload); got != "paid" {
		t.Errorf("panggilan kedua status payment = %q, mau \"paid\"", got)
	}
	if n := countSessionsForBooking(t, f.db, booking.ID); n != 1 {
		t.Errorf("jumlah sesi setelah panggilan kedua = %d, mau 1", n)
	}
}

// TestPaymentStatusReconcileKeepsPending: gateway masih pending -> status DB
// tidak berubah dan respons tetap 200.
func TestPaymentStatusReconcileKeepsPending(t *testing.T) {
	gw := &fakeStatusGateway{status: payment.GatewayStatus{Status: "pending"}}
	f := newReconcileFixture(t, gw)
	booking, pay := f.pendingPayment(t, 10*time.Second)

	code, payload := f.statusResult(t, pay.Reference)
	if code != http.StatusOK {
		t.Fatalf("status = %d, mau 200", code)
	}
	if got := paymentStatusOf(t, payload); got != "pending" {
		t.Errorf("status payment = %q, mau tetap \"pending\"", got)
	}
	if fmt.Sprint(payload["session_id"]) != "" {
		t.Errorf("session_id = %v, mau kosong saat belum lunas", payload["session_id"])
	}
	if n := countSessionsForBooking(t, f.db, booking.ID); n != 0 {
		t.Errorf("jumlah sesi = %d, mau 0", n)
	}
	if gw.calls != 1 {
		t.Errorf("FetchStatus dipanggil %d kali, mau 1", gw.calls)
	}
}

// TestPaymentStatusReconcileSurvivesGatewayError: endpoint ini dipanggil tiap
// 3 detik — kegagalan gateway tidak boleh jadi error bagi klien.
func TestPaymentStatusReconcileSurvivesGatewayError(t *testing.T) {
	gw := &fakeStatusGateway{err: fmt.Errorf("gateway timeout")}
	f := newReconcileFixture(t, gw)
	_, pay := f.pendingPayment(t, 10*time.Second)

	code, payload := f.statusResult(t, pay.Reference)
	if code != http.StatusOK {
		t.Fatalf("status = %d, mau 200 walau gateway gagal", code)
	}
	if got := paymentStatusOf(t, payload); got != "pending" {
		t.Errorf("status payment = %q, mau tetap \"pending\"", got)
	}
}

// TestPaymentStatusReconcileSkipsFreshPayment: payment yang baru dibuat belum
// ditanyakan ke gateway (hindari balapan dengan pembuatan transaksi Snap).
func TestPaymentStatusReconcileSkipsFreshPayment(t *testing.T) {
	gw := &fakeStatusGateway{status: payment.GatewayStatus{Status: "settlement", FraudStatus: "accept"}}
	f := newReconcileFixture(t, gw)
	_, pay := f.pendingPayment(t, time.Second)

	code, payload := f.statusResult(t, pay.Reference)
	if code != http.StatusOK {
		t.Fatalf("status = %d, mau 200", code)
	}
	if gw.calls != 0 {
		t.Errorf("FetchStatus dipanggil %d kali untuk payment berumur 1 detik, mau 0", gw.calls)
	}
	if got := paymentStatusOf(t, payload); got != "pending" {
		t.Errorf("status payment = %q, mau \"pending\"", got)
	}
}

// TestPaymentStatusReconcileSkipsUnsupportedGateway: gateway tanpa
// StatusFetcher tetap 200 memakai status DB.
func TestPaymentStatusReconcileSkipsUnsupportedGateway(t *testing.T) {
	f := newReconcileFixture(t, &fakeLegacyGateway{})
	_, pay := f.pendingPayment(t, 10*time.Second)

	code, payload := f.statusResult(t, pay.Reference)
	if code != http.StatusOK {
		t.Fatalf("status = %d, mau 200", code)
	}
	if got := paymentStatusOf(t, payload); got != "pending" {
		t.Errorf("status payment = %q, mau \"pending\"", got)
	}
}

// TestPaymentStatusReconcileIgnoresFraudChallenge: settlement dengan fraud
// status "challenge" belum boleh dianggap lunas.
func TestPaymentStatusReconcileIgnoresFraudChallenge(t *testing.T) {
	gw := &fakeStatusGateway{status: payment.GatewayStatus{
		Status: "settlement", FraudStatus: "challenge", TransactionID: "txn-challenge",
	}}
	f := newReconcileFixture(t, gw)
	_, pay := f.pendingPayment(t, 10*time.Second)

	code, payload := f.statusResult(t, pay.Reference)
	if code != http.StatusOK {
		t.Fatalf("status = %d, mau 200", code)
	}
	if got := paymentStatusOf(t, payload); got != "pending" {
		t.Errorf("status payment = %q, mau tetap \"pending\" saat fraud challenge", got)
	}
}

// TestPaymentStatusReconcileSkipsNonGatewayPayment: payment yang bukan
// transaksi gateway (gateway kosong, mis. mode simulasi) tidak pernah
// ditanyakan ke gateway.
func TestPaymentStatusReconcileSkipsNonGatewayPayment(t *testing.T) {
	gw := &fakeStatusGateway{status: payment.GatewayStatus{Status: "settlement", FraudStatus: "accept"}}
	f := newReconcileFixture(t, gw)
	ctx := context.Background()
	start := clock.Now().In(wibLoc).AddDate(0, 0, 3)
	_, pay := createPendingBookingAt(t, f.db, f.st, f.patient.ID, f.prof.ID,
		"quick_consult", "chat", start)
	if _, err := f.db.ExecContext(ctx,
		`UPDATE payments SET created_at = now() - make_interval(secs => 30) WHERE id = $1`,
		pay.ID); err != nil {
		t.Fatalf("atur umur payment: %v", err)
	}

	code, payload := f.statusResult(t, pay.Reference)
	if code != http.StatusOK {
		t.Fatalf("status = %d, mau 200", code)
	}
	if gw.calls != 0 {
		t.Errorf("FetchStatus dipanggil %d kali untuk payment tanpa gateway, mau 0", gw.calls)
	}
	if got := paymentStatusOf(t, payload); got != "pending" {
		t.Errorf("status payment = %q, mau \"pending\"", got)
	}
}

// TestPaymentStatusReconcileNotExistLogsNothing mengunci kasus NORMAL "transaksi
// belum ada di Midtrans": fetcher mengembalikan pending tanpa error (Midtrans
// membalas HTTP 200 dengan status_code "404" di body). Endpoint dipanggil klien
// tiap 3 detik, jadi kondisi ini tidak boleh menghasilkan log error/warning
// sama sekali — kalau tidak, log produksi banjir dan seolah ada kegagalan.
func TestPaymentStatusReconcileNotExistLogsNothing(t *testing.T) {
	gw := &fakeStatusGateway{status: payment.GatewayStatus{Status: "pending", StatusCode: "404"}}
	f := newReconcileFixture(t, gw)
	var logs bytes.Buffer
	f.srv.logger = slog.New(slog.NewTextHandler(&logs, &slog.HandlerOptions{Level: slog.LevelDebug}))
	_, pay := f.pendingPayment(t, 10*time.Second)

	code, payload := f.statusResult(t, pay.Reference)
	if code != http.StatusOK {
		t.Fatalf("status = %d, mau 200", code)
	}
	if got := paymentStatusOf(t, payload); got != "pending" {
		t.Errorf("status payment = %q, mau tetap \"pending\"", got)
	}
	if gw.calls != 1 {
		t.Errorf("FetchStatus dipanggil %d kali, mau 1", gw.calls)
	}
	if strings.Contains(logs.String(), "level=WARN") || strings.Contains(logs.String(), "level=ERROR") {
		t.Fatalf("kondisi normal (transaksi belum ada) tidak boleh menulis log error/warning: %s", logs.String())
	}
}
