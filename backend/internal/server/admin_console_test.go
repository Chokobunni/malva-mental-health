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
	"malva/backend/internal/store"
)

// ============================================================
// KONSOL ADMIN — pengujian endpoint panel admin baru.
//
// Dua kelompok:
//   - Guard (tanpa DB): non-admin/anonim ditolak 401/403 di setiap rute.
//   - Integrasi (butuh Postgres): override pembayaran, refund, reset password,
//     dan harga. Di-skip bila MALVA_TEST_DATABASE_URL tidak disetel, sama
//     seperti test store/server lain.
// ============================================================

// adminConsoleRoutes mendaftar seluruh rute konsol admin baru.
var adminConsoleRoutes = []struct{ method, path string }{
	{"GET", "/v1/admin/overview"},
	{"GET", "/v1/admin/payments"},
	{"GET", "/v1/admin/payments/p1"},
	{"POST", "/v1/admin/payments/p1/override"},
	{"GET", "/v1/admin/pricing"},
	{"PUT", "/v1/admin/pricing/p1"},
	{"GET", "/v1/admin/refunds"},
	{"POST", "/v1/admin/users/u1/reset-password"},
	{"POST", "/v1/admin/users/u1/revoke-sessions"},
}

// TestAdminConsoleRoutesRejectNonAdmin memastikan setiap rute baru di balik
// requireAdmin: tanpa token 401, role patient 403.
func TestAdminConsoleRoutesRejectNonAdmin(t *testing.T) {
	srv, patientToken, _ := newSafetyTestServer()
	handler := srv.Routes()
	for _, tc := range adminConsoleRoutes {
		rec := doAuthed(t, handler, tc.method, tc.path, "", `{"x":1}`)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("%s %s tanpa token: mau 401, dapat %d", tc.method, tc.path, rec.Code)
		}
		rec = doAuthed(t, handler, tc.method, tc.path, patientToken, `{"x":1}`)
		if rec.Code != http.StatusForbidden {
			t.Errorf("%s %s role patient: mau 403, dapat %d", tc.method, tc.path, rec.Code)
		}
	}
}

// adminConsoleFixture menyiapkan pasien + profesional + admin + server.
type adminConsoleFixture struct {
	srv   *Server
	db    *sql.DB
	st    *store.Store
	admin store.User
}

func newAdminConsoleFixture(t *testing.T) adminConsoleFixture {
	t.Helper()
	db, st := openOnboardingTestStore(t)
	// Admin dibuat oleh bootstrap, bukan registrasi publik yang hanya menerima
	// pasien/profesional. Fixture mengikuti promosi role setelah user dibuat.
	admin := createIdentityTestUser(t, db, st, "patient", nil)
	if _, err := db.Exec(`UPDATE users SET role='admin' WHERE id=$1`, admin.ID); err != nil {
		t.Fatal(err)
	}
	admin.Role = "admin"
	return adminConsoleFixture{srv: newOnboardingTestServer(db), db: db, st: st, admin: admin}
}

// adminClaims mengembalikan claims role admin untuk memanggil handler langsung.
func (f adminConsoleFixture) adminClaims() auth.Claims {
	return auth.Claims{Subject: f.admin.ID, Role: "admin"}
}

// callOverride memanggil handler override dengan path value payment_id.
func (f adminConsoleFixture) callOverride(t *testing.T, paymentID, body string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/admin/payments/"+paymentID+"/override", strings.NewReader(body))
	req.Header.Set("Content-Type", "application/json")
	req.SetPathValue("payment_id", paymentID)
	f.srv.overrideAdminPayment(rec, req, f.adminClaims())
	return rec
}

type overrideResponse struct {
	Payment store.AdminPaymentItem `json:"payment"`
	Changed bool                   `json:"changed"`
}

// TestAdminOverridePendingToPaidAndIdempotent mengunci kontrak: pending->paid
// menandai lunas (changed:true), panggilan kedua menjadi no-op (changed:false).
func TestAdminOverridePendingToPaidAndIdempotent(t *testing.T) {
	f := newAdminConsoleFixture(t)
	patient := createIdentityTestUser(t, f.db, f.st, "patient", nil)
	prof := createIdentityTestUser(t, f.db, f.st, "professional", &store.ProfessionalCredential{Specialization: "Sp.KJ"})
	start := time.Now().AddDate(0, 0, 3)
	_, pay := createPendingBookingAt(t, f.db, f.st, patient.ID, prof.ID, "quick_consult", "chat", start)

	rec := f.callOverride(t, pay.ID, `{"status":"paid","reason":"midtrans tidak mengirim webhook"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("override paid: mau 200, dapat %d (%s)", rec.Code, rec.Body.String())
	}
	var first overrideResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &first); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if !first.Changed || first.Payment.Status != "paid" {
		t.Fatalf("harus changed:true & status paid, dapat %+v", first)
	}

	// Panggilan kedua ke status yang sama = no-op.
	rec = f.callOverride(t, pay.ID, `{"status":"paid","reason":"ulang"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("override ulang: mau 200, dapat %d", rec.Code)
	}
	var second overrideResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &second); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if second.Changed {
		t.Fatalf("panggilan idempoten harus changed:false, dapat %+v", second)
	}
	if second.Payment.Status != "paid" {
		t.Fatalf("status harus tetap paid, dapat %q", second.Payment.Status)
	}
}

// TestAdminOverrideInvalidTransition menolak paid->pending dengan 400.
func TestAdminOverrideInvalidTransition(t *testing.T) {
	f := newAdminConsoleFixture(t)
	patient := createIdentityTestUser(t, f.db, f.st, "patient", nil)
	prof := createIdentityTestUser(t, f.db, f.st, "professional", &store.ProfessionalCredential{Specialization: "Sp.KJ"})
	start := time.Now().AddDate(0, 0, 3)
	_, pay := createPendingBookingAt(t, f.db, f.st, patient.ID, prof.ID, "quick_consult", "chat", start)

	if _, err := f.st.MarkPaymentPaid(context.Background(), pay.Reference, "test"); err != nil {
		t.Fatalf("mark paid: %v", err)
	}
	rec := f.callOverride(t, pay.ID, `{"status":"pending","reason":"coba mundur"}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("paid->pending harus 400, dapat %d (%s)", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "gagal") {
		t.Fatalf("pesan harus menjelaskan transisi tidak sah: %s", rec.Body.String())
	}
}

// TestAdminOverrideRefundWritesLedger memastikan refund dari status paid menulis
// baris care_refunds. Di-skip bila tabel care_refunds belum ada di DB uji.
func TestAdminOverrideRefundWritesLedger(t *testing.T) {
	f := newAdminConsoleFixture(t)
	ctx := context.Background()

	var hasLedger bool
	if err := f.db.QueryRowContext(ctx, `SELECT to_regclass('public.care_refunds') IS NOT NULL`).Scan(&hasLedger); err != nil {
		t.Fatalf("cek tabel care_refunds: %v", err)
	}
	if !hasLedger {
		t.Skip("tabel care_refunds belum ada di DB uji")
	}

	patient := createIdentityTestUser(t, f.db, f.st, "patient", nil)
	prof := createIdentityTestUser(t, f.db, f.st, "professional", &store.ProfessionalCredential{Specialization: "Sp.KJ"})
	start := time.Now().AddDate(0, 0, 3)
	_, pay := createPendingBookingAt(t, f.db, f.st, patient.ID, prof.ID, "quick_consult", "chat", start)
	if _, err := f.st.MarkPaymentPaid(ctx, pay.Reference, "test"); err != nil {
		t.Fatalf("mark paid: %v", err)
	}
	key := "admin:payment:" + pay.ID + ":refund"
	t.Cleanup(func() {
		_, _ = f.db.ExecContext(context.Background(), `DELETE FROM care_refunds WHERE idempotency_key = $1`, key)
	})

	rec := f.callOverride(t, pay.ID, `{"status":"refunded","reason":"pasien membatalkan, dana dikembalikan"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("override refunded: mau 200, dapat %d (%s)", rec.Code, rec.Body.String())
	}
	var resp overrideResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if !resp.Changed || resp.Payment.Status != "refunded" {
		t.Fatalf("harus changed:true & status refunded, dapat %+v", resp)
	}

	var amount int64
	var kind, status string
	err := f.db.QueryRowContext(ctx,
		`SELECT amount, kind, status FROM care_refunds WHERE idempotency_key = $1`, key).
		Scan(&amount, &kind, &status)
	if err != nil {
		t.Fatalf("baris ledger refund tidak ditemukan: %v", err)
	}
	if amount != pay.GrossAmount || kind != "refund" || status != "paid" {
		t.Fatalf("ledger tidak sesuai: amount=%d kind=%s status=%s (mau %d/refund/paid)",
			amount, kind, status, pay.GrossAmount)
	}
	second := f.callOverride(t, pay.ID, `{"status":"refunded","reason":"retry"}`)
	if second.Code != http.StatusOK {
		t.Fatalf("refund retry status %d: %s", second.Code, second.Body.String())
	}
	var replay overrideResponse
	if err := json.Unmarshal(second.Body.Bytes(), &replay); err != nil || replay.Changed {
		t.Fatalf("refund retry must not change ledger: %+v, err=%v", replay, err)
	}
	var count int
	if err := f.db.QueryRowContext(ctx, `SELECT count(*) FROM care_refunds WHERE idempotency_key=$1`, key).Scan(&count); err != nil || count != 1 {
		t.Fatalf("refund ledger count=%d err=%v", count, err)
	}
}

// TestAdminResetPasswordRejectsWeakAndRevokesSessions mengunci kebijakan
// password + pencabutan sesi setelah reset.
func TestAdminResetPasswordRejectsWeakAndRevokesSessions(t *testing.T) {
	f := newAdminConsoleFixture(t)
	ctx := context.Background()
	patient := createIdentityTestUser(t, f.db, f.st, "patient", nil)

	// Sesi aktif untuk dibuktikan tercabut.
	if err := f.st.CreateRefreshSession(ctx, patient.ID, "hash-reset-"+patient.ID, "ua", "127.0.0.1", time.Hour); err != nil {
		t.Fatalf("buat sesi: %v", err)
	}

	call := func(body string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/v1/admin/users/"+patient.ID+"/reset-password", strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		req.SetPathValue("user_id", patient.ID)
		f.srv.resetAdminUserPassword(rec, req, f.adminClaims())
		return rec
	}

	// Password lemah ditolak 400.
	rec := call(`{"new_password":"lemah"}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("password lemah: mau 400, dapat %d (%s)", rec.Code, rec.Body.String())
	}
	// Sesi belum tercabut karena reset gagal.
	var active int
	if err := f.db.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM auth_sessions WHERE user_id = $1 AND revoked_at IS NULL`, patient.ID).Scan(&active); err != nil {
		t.Fatalf("hitung sesi: %v", err)
	}
	if active == 0 {
		t.Fatalf("sesi tidak boleh tercabut saat password lemah")
	}

	// Password kuat berhasil dan mencabut sesi.
	rec = call(`{"new_password":"Str0ng!Passw0rd#2026"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("password kuat: mau 200, dapat %d (%s)", rec.Code, rec.Body.String())
	}
	if err := f.db.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM auth_sessions WHERE user_id = $1 AND revoked_at IS NULL`, patient.ID).Scan(&active); err != nil {
		t.Fatalf("hitung sesi: %v", err)
	}
	if active != 0 {
		t.Fatalf("semua sesi harus tercabut setelah reset, sisa aktif=%d", active)
	}
}

// TestAdminUpdatePricingValidation menguji validasi harga admin.
func TestAdminUpdatePricingValidation(t *testing.T) {
	f := newAdminConsoleFixture(t)
	ctx := context.Background()
	patient := createIdentityTestUser(t, f.db, f.st, "patient", nil)
	prof := createIdentityTestUser(t, f.db, f.st, "professional", &store.ProfessionalCredential{Specialization: "Sp.KJ"})
	t.Cleanup(func() {
		_, _ = f.db.ExecContext(context.Background(), `DELETE FROM professional_pricing WHERE professional_id = $1`, prof.ID)
	})

	call := func(professionalID, body string) *httptest.ResponseRecorder {
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPut, "/v1/admin/pricing/"+professionalID, strings.NewReader(body))
		req.Header.Set("Content-Type", "application/json")
		req.SetPathValue("professional_id", professionalID)
		f.srv.updateAdminPricing(rec, req, f.adminClaims())
		return rec
	}

	// Nilai negatif ditolak.
	if rec := call(prof.ID, `{"quick_chat_price":-1}`); rec.Code != http.StatusBadRequest {
		t.Fatalf("harga negatif: mau 400, dapat %d (%s)", rec.Code, rec.Body.String())
	}
	// Melebihi batas atas ditolak.
	if rec := call(prof.ID, fmt.Sprintf(`{"package_price":%d}`, maxAdminPrice+1)); rec.Code != http.StatusBadRequest {
		t.Fatalf("harga di atas batas: mau 400, dapat %d (%s)", rec.Code, rec.Body.String())
	}
	// Target bukan profesional ditolak.
	if rec := call(patient.ID, `{"quick_chat_price":10000}`); rec.Code != http.StatusBadRequest {
		t.Fatalf("target pasien: mau 400, dapat %d (%s)", rec.Code, rec.Body.String())
	}
	// Nilai sah tersimpan.
	if rec := call(prof.ID, `{"quick_chat_price":150000,"quick_video_price":200000,"package_price":600000}`); rec.Code != http.StatusOK {
		t.Fatalf("harga sah: mau 200, dapat %d (%s)", rec.Code, rec.Body.String())
	}
	var chat, video, pkg int64
	if err := f.db.QueryRowContext(ctx,
		`SELECT quick_chat_price, quick_video_price, package_price FROM professional_pricing WHERE professional_id = $1`, prof.ID).
		Scan(&chat, &video, &pkg); err != nil {
		t.Fatalf("baca harga: %v", err)
	}
	if chat != 150000 || video != 200000 || pkg != 600000 {
		t.Fatalf("harga tersimpan salah: %d/%d/%d", chat, video, pkg)
	}
}
