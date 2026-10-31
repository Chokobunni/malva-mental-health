package server

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/store"
)

// TestCompleteProfessionalSetsPassword memastikan password opsional pada
// pelengkapan profil profesional:
//
//   - password lemah -> 400 dan profil TIDAK berubah (validasi lebih dulu),
//   - password valid -> password_hash berubah sehingga akun bisa login dengan
//     nomor STR + password (bukan lagi hash acak dari jalur Google).
//
// Butuh Postgres nyata (MALVA_TEST_DATABASE_URL); di lokal tanpa DB test ini
// dilewati, sama seperti test onboarding lain di paket ini.
func TestCompleteProfessionalSetsPassword(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	ctx := context.Background()
	suffix := fmt.Sprint(time.Now().UnixNano())
	u := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{Specialization: "M.Psi"})
	srv := newOnboardingTestServer(db)
	before, err := st.GetUserByID(ctx, u.ID)
	if err != nil {
		t.Fatal(err)
	}
	call := func(password string) *httptest.ResponseRecorder {
		t.Helper()
		raw, _ := json.Marshal(completeProfessionalRequest{
			STRNumber:      "STR-" + suffix,
			SIPNumber:      "SIP-" + suffix,
			Specialization: "Sp.KJ",
			Password:       password,
		})
		rec := httptest.NewRecorder()
		srv.completeProfessionalProfile(rec,
			httptest.NewRequest("POST", "/v1/auth/complete-professional", bytes.NewReader(raw)),
			auth.Claims{Subject: u.ID, Role: "professional"})
		return rec
	}

	// 1. Password lemah -> 400, profil & hash tidak berubah.
	if rec := call("lemah"); rec.Code != http.StatusBadRequest {
		t.Fatalf("password lemah harus 400, dapat %d %s", rec.Code, rec.Body.String())
	}
	cred, err := st.GetProfessionalCredential(ctx, u.ID)
	if err != nil {
		t.Fatal(err)
	}
	if cred.STRNumber != "" || cred.SIPNumber != "" {
		t.Fatalf("profil berubah walau password lemah: %+v", cred)
	}
	afterWeak, err := st.GetUserByID(ctx, u.ID)
	if err != nil {
		t.Fatal(err)
	}
	if afterWeak.PasswordHash != before.PasswordHash {
		t.Fatal("password_hash berubah walau validasi gagal")
	}

	// 2. Password valid -> 200, hash berubah dan bisa dipakai verifikasi.
	const password = "RahasiaKlinik123!"
	if rec := call(password); rec.Code != http.StatusOK {
		t.Fatalf("password valid harus 200, dapat %d %s", rec.Code, rec.Body.String())
	}
	after, err := st.GetUserByID(ctx, u.ID)
	if err != nil {
		t.Fatal(err)
	}
	if after.PasswordHash == before.PasswordHash {
		t.Fatal("password_hash tidak berubah setelah password valid")
	}
	if !auth.CheckPassword(after.PasswordHash, password) {
		t.Fatal("password baru tidak lolos verifikasi login")
	}
	cred, err = st.GetProfessionalCredential(ctx, u.ID)
	if err != nil {
		t.Fatal(err)
	}
	if cred.STRNumber != "STR-"+suffix || cred.SIPNumber != "SIP-"+suffix {
		t.Fatalf("profil tidak tersimpan: %+v", cred)
	}
}

// TestChangePasswordAllowsGoogleOnlyAccount mengunci aturan ubah password:
// akun yang tertaut Google boleh mengirim current_password kosong (akun
// Google-only tidak punya password yang diketahui), sedangkan akun non-Google
// tetap ditolak 401.
func TestChangePasswordAllowsGoogleOnlyAccount(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	ctx := context.Background()
	srv := newOnboardingTestServer(db)
	suffix := fmt.Sprint(time.Now().UnixNano())

	googleUser := createIdentityTestUser(t, db, st, "patient", nil)
	if _, err := st.LinkGoogleIdentity(ctx, googleUser.ID, "sub-"+suffix, "google-"+suffix+"@example.test", false); err != nil {
		t.Fatal(err)
	}
	call := func(userID, current, next string) *httptest.ResponseRecorder {
		t.Helper()
		raw, _ := json.Marshal(passwordChangeRequest{CurrentPassword: current, NewPassword: next})
		rec := httptest.NewRecorder()
		srv.changePassword(rec,
			httptest.NewRequest("POST", "/v1/auth/change-password", bytes.NewReader(raw)),
			auth.Claims{Subject: userID, Role: "patient"})
		return rec
	}

	// Akun tertaut Google + current_password kosong -> 200 & password berlaku.
	const newPassword = "PasswordGoogle123!"
	if rec := call(googleUser.ID, "", newPassword); rec.Code != http.StatusOK {
		t.Fatalf("akun Google-only harus 200, dapat %d %s", rec.Code, rec.Body.String())
	}
	updated, err := st.GetUserByID(ctx, googleUser.ID)
	if err != nil {
		t.Fatal(err)
	}
	if !auth.CheckPassword(updated.PasswordHash, newPassword) {
		t.Fatal("password baru akun Google-only tidak tersimpan")
	}

	// Akun tanpa tautan Google + current_password kosong -> 401.
	plain := createIdentityTestUser(t, db, st, "patient", nil)
	if rec := call(plain.ID, "", "PasswordLain123!"); rec.Code != http.StatusUnauthorized {
		t.Fatalf("akun non-Google harus 401, dapat %d %s", rec.Code, rec.Body.String())
	}

	// KASUS KEAMANAN (2c): akun tertaut Google + current_password SALAH (tidak
	// kosong) HARUS tetap 401. Pelonggaran "current_password boleh kosong"
	// tidak boleh berubah menjadi "password lama apa pun diterima" — kalau
	// ini lolos, siapa pun yang memegang sesi bisa mengganti password tanpa
	// tahu password lama. Password akun di-set eksplisit agar ada hash nyata.
	const googleOldPassword = "PasswordGoogle123!" // dari langkah (a) di atas
	beforeWrong, err := st.GetUserByID(ctx, googleUser.ID)
	if err != nil {
		t.Fatal(err)
	}
	if rec := call(googleUser.ID, "PasswordSalahTotal999!", "PasswordBaru456!"); rec.Code != http.StatusUnauthorized {
		t.Fatalf("akun Google + password lama salah harus 401, dapat %d %s", rec.Code, rec.Body.String())
	}
	afterWrong, err := st.GetUserByID(ctx, googleUser.ID)
	if err != nil {
		t.Fatal(err)
	}
	if afterWrong.PasswordHash != beforeWrong.PasswordHash {
		t.Fatal("password berubah walau current_password salah (celah keamanan)")
	}
	if !auth.CheckPassword(afterWrong.PasswordHash, googleOldPassword) {
		t.Fatal("password lama harus tetap berlaku setelah percobaan gagal")
	}
}
