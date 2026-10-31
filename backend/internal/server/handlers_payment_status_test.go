package server

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
	"malva/backend/internal/store"
)

// ============================================================
// STATUS PEMBAYARAN & KONFIGURASI MODE PEMBAYARAN
//
// Latar belakang: di mode gateway klien tidak boleh mengonfirmasi pembayaran
// sendiri (mark-paid membalas 410), sedangkan webhook Midtrans bisa terlambat
// beberapa detik sampai menit. Dua endpoint diuji di sini:
//   - GET /v1/payments/{reference}: hanya pasien pemilik, dan bila sudah 'paid'
//     memicu aktivasi best-effort (sesi tetap muncul walau webhook telat).
//   - GET /v1/config/payment: publik, tanpa membocorkan key apa pun.
// ============================================================

// paymentStatusFixture menyiapkan pasien + profesional + server test.
type paymentStatusFixture struct {
	srv     *Server
	db      *sql.DB
	patient store.User
	prof    store.User
}

func newPaymentStatusFixture(t *testing.T, db *sql.DB, st *store.Store) paymentStatusFixture {
	t.Helper()
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      fmt.Sprint("STR-PS-", time.Now().UnixNano()),
		SIPNumber:      fmt.Sprint("SIP-PS-", time.Now().UnixNano()),
	})
	return paymentStatusFixture{
		srv:     newOnboardingTestServer(db),
		db:      db,
		patient: patient,
		prof:    prof,
	}
}

// getStatus memanggil handler status seperti klien (GET /v1/payments/{ref}).
func (f paymentStatusFixture) getStatus(t *testing.T, reference string, claims auth.Claims) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/v1/payments/"+reference, nil)
	req.SetPathValue("reference", reference)
	f.srv.getPaymentStatus(rec, req, claims)
	return rec
}

// TestGetPaymentStatusOwnerReturns200 mengunci kontrak dasar: pasien pemilik
// mendapat 200 beserta objek payment, dan session_id kosong bila sesinya belum
// ada (pembayaran masih pending).
func TestGetPaymentStatusOwnerReturns200(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	f := newPaymentStatusFixture(t, db, st)
	start := clock.Now().In(wibLoc).AddDate(0, 0, 3)
	_, pay := createPendingBookingAt(t, db, st, f.patient.ID, f.prof.ID, "quick_consult", "chat", start)

	rec := f.getStatus(t, pay.Reference, auth.Claims{Subject: f.patient.ID, Role: "patient"})
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, mau 200 (body: %s)", rec.Code, rec.Body.String())
	}
	var payload struct {
		Payment   store.Payment `json:"payment"`
		SessionID string        `json:"session_id"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("body bukan JSON: %v", err)
	}
	if payload.Payment.Reference != pay.Reference {
		t.Errorf("payment.reference = %q, mau %q", payload.Payment.Reference, pay.Reference)
	}
	if payload.Payment.Status != "pending" {
		t.Errorf("payment.status = %q, mau \"pending\"", payload.Payment.Status)
	}
	if payload.SessionID != "" {
		t.Errorf("session_id = %q, mau kosong saat belum ada sesi", payload.SessionID)
	}
}

// TestGetPaymentStatusOtherPatientNotFound memastikan reference milik pasien
// lain tidak bisa ditebak: balasan 404, bukan 403 (yang membocorkan keberadaan).
func TestGetPaymentStatusOtherPatientNotFound(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	f := newPaymentStatusFixture(t, db, st)
	other := createIdentityTestUser(t, db, st, "patient", nil)
	start := clock.Now().In(wibLoc).AddDate(0, 0, 3)
	_, pay := createPendingBookingAt(t, db, st, f.patient.ID, f.prof.ID, "quick_consult", "chat", start)

	rec := f.getStatus(t, pay.Reference, auth.Claims{Subject: other.ID, Role: "patient"})
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, mau 404 agar keberadaan payment pasien lain tidak bocor (body: %s)",
			rec.Code, rec.Body.String())
	}
	if strings.Contains(rec.Body.String(), pay.Reference) {
		t.Errorf("body tidak boleh memuat reference: %s", rec.Body.String())
	}
}

// TestGetPaymentStatusProfessionalForbidden: endpoint ini hanya untuk pasien.
func TestGetPaymentStatusProfessionalForbidden(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	f := newPaymentStatusFixture(t, db, st)
	start := clock.Now().In(wibLoc).AddDate(0, 0, 3)
	_, pay := createPendingBookingAt(t, db, st, f.patient.ID, f.prof.ID, "quick_consult", "chat", start)

	rec := f.getStatus(t, pay.Reference, auth.Claims{Subject: f.prof.ID, Role: "professional"})
	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, mau 403 untuk role profesional (body: %s)", rec.Code, rec.Body.String())
	}
}

// TestGetPaymentStatusUnknownReferenceNotFound mengunci klaim #1: reference
// yang tidak pernah diterbitkan dibalas 404 (bukan 500), sehingga polling
// klien berhenti dengan pesan "tidak ditemukan", bukan galat server.
func TestGetPaymentStatusUnknownReferenceNotFound(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	f := newPaymentStatusFixture(t, db, st)

	rec := f.getStatus(t, "REF-TIDAK-ADA-"+fmt.Sprint(time.Now().UnixNano()),
		auth.Claims{Subject: f.patient.ID, Role: "patient"})
	if rec.Code != http.StatusNotFound {
		t.Fatalf("status = %d, mau 404 untuk reference tak dikenal (body: %s)", rec.Code, rec.Body.String())
	}
}

// TestGetPaymentStatusPaidActivatesSession mengunci manfaat utama endpoint ini:
// pembayaran sudah 'paid' (webhook sudah menandai lunas) tetapi sesinya belum
// ada — karena aktivasi webhook gagal/tertunda. Pemeriksaan status oleh pasien
// harus memicu aktivasi sehingga sesinya muncul, dan idempoten saat dipanggil
// dua kali.
func TestGetPaymentStatusPaidActivatesSession(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	f := newPaymentStatusFixture(t, db, st)
	ctx := context.Background()
	start := clock.Now().In(wibLoc).AddDate(0, 0, 3)
	booking, pay := createPendingBookingAt(t, db, st, f.patient.ID, f.prof.ID, "quick_consult", "chat", start)

	// Webhook sudah menandai lunas (payment & booking 'paid'), tetapi aktivasi
	// belum berjalan: belum ada sesi.
	if _, err := st.MarkPaymentPaid(ctx, pay.Reference, "ext-"+pay.Reference); err != nil {
		t.Fatalf("tandai payment lunas: %v", err)
	}
	if n := countSessionsForBooking(t, db, booking.ID); n != 0 {
		t.Fatalf("prasyarat gagal: sudah ada %d sesi sebelum cek status", n)
	}

	rec := f.getStatus(t, pay.Reference, auth.Claims{Subject: f.patient.ID, Role: "patient"})
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, mau 200 (body: %s)", rec.Code, rec.Body.String())
	}
	var first struct {
		SessionID string `json:"session_id"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &first); err != nil {
		t.Fatalf("body bukan JSON: %v", err)
	}
	if strings.TrimSpace(first.SessionID) == "" {
		t.Fatalf("session_id kosong: sesi tidak dibuat padahal pembayaran sudah lunas")
	}
	if n := countSessionsForBooking(t, db, booking.ID); n != 1 {
		t.Fatalf("jumlah sesi = %d, mau 1", n)
	}

	// Idempoten: panggilan kedua tidak membuat sesi kedua.
	rec2 := f.getStatus(t, pay.Reference, auth.Claims{Subject: f.patient.ID, Role: "patient"})
	if rec2.Code != http.StatusOK {
		t.Fatalf("panggilan kedua status = %d, mau 200", rec2.Code)
	}
	var second struct {
		SessionID string `json:"session_id"`
	}
	if err := json.Unmarshal(rec2.Body.Bytes(), &second); err != nil {
		t.Fatalf("body kedua bukan JSON: %v", err)
	}
	if second.SessionID != first.SessionID {
		t.Errorf("session_id berubah antar panggilan: %q -> %q", first.SessionID, second.SessionID)
	}
	if n := countSessionsForBooking(t, db, booking.ID); n != 1 {
		t.Errorf("jumlah sesi setelah panggilan kedua = %d, mau 1", n)
	}
}

// TestPaymentConfigHandlerGatewayNoSecrets mengunci kontrak GET
// /v1/config/payment: mode dilaporkan apa adanya dan TIDAK pernah memuat
// server/client key.
func TestPaymentConfigHandlerGatewayNoSecrets(t *testing.T) {
	const serverKey = "SB-Mid-server-RAHASIA-JANGAN-BOCOR"
	const clientKey = "SB-Mid-client-RAHASIA-JANGAN-BOCOR"
	srv := newOnboardingTestServer(nil)
	srv.cfg.PaymentMode = "gateway"
	srv.cfg.MidtransEnv = "sandbox"
	srv.cfg.MidtransServerKey = serverKey
	srv.cfg.MidtransClientKey = clientKey

	rec := httptest.NewRecorder()
	srv.paymentConfigHandler(rec, httptest.NewRequest(http.MethodGet, "/v1/config/payment", nil))

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, mau 200 (body: %s)", rec.Code, rec.Body.String())
	}
	var payload map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("body bukan JSON: %v", err)
	}
	if payload["mode"] != "gateway" {
		t.Errorf("mode = %q, mau \"gateway\"", payload["mode"])
	}
	if payload["provider"] != "midtrans" {
		t.Errorf("provider = %q, mau \"midtrans\"", payload["provider"])
	}
	if payload["env"] != "sandbox" {
		t.Errorf("env = %q, mau \"sandbox\"", payload["env"])
	}
	body := rec.Body.String()
	for _, secret := range []string{serverKey, clientKey, "RAHASIA"} {
		if strings.Contains(body, secret) {
			t.Fatalf("respons membocorkan kredensial (%q): %s", secret, body)
		}
	}
}

// TestPaymentConfigHandlerDefaultSimulation: tanpa konfigurasi, mode jatuh ke
// "simulation" sehingga klien tidak pernah mengira gateway aktif.
func TestPaymentConfigHandlerDefaultSimulation(t *testing.T) {
	srv := newOnboardingTestServer(nil)

	rec := httptest.NewRecorder()
	srv.paymentConfigHandler(rec, httptest.NewRequest(http.MethodGet, "/v1/config/payment", nil))

	var payload map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("body bukan JSON: %v", err)
	}
	if payload["mode"] != "simulation" {
		t.Errorf("mode = %q, mau \"simulation\" saat PaymentMode kosong", payload["mode"])
	}
	if payload["env"] != "sandbox" {
		t.Errorf("env = %q, mau \"sandbox\" sebagai default", payload["env"])
	}
}
