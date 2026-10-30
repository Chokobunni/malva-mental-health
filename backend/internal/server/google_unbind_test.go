package server

import (
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
	"malva/backend/internal/store"
)

// callUnbind memanggil handler unbindGoogle secara langsung (tanpa transport
// HTTP nyata). body kosong mensimulasikan permintaan tanpa kredensial.
func callUnbind(srv *Server, userID, role, body string) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	srv.unbindGoogle(rec, httptest.NewRequest("POST", "/v1/auth/unbind-google", strings.NewReader(body)),
		auth.Claims{Subject: userID, Role: role})
	return rec
}

// unbindCode mengekstrak kode mesin dari body JSON respons.
func unbindCode(rec *httptest.ResponseRecorder) string {
	var body map[string]string
	_ = json.Unmarshal(rec.Body.Bytes(), &body)
	return body["code"]
}

func bindTestGoogle(t *testing.T, st *store.Store, userID string) {
	t.Helper()
	if _, err := st.LinkGoogleIdentity(context.Background(), userID, "sub-"+userID,
		"gmail-"+userID+"@example.test", false); err != nil {
		t.Fatalf("bind: %v", err)
	}
}

// 1. Pasien tertaut → unbind tanpa kredensial → 409 perlu_password.
func TestUnbindGoogleRequiresPassword(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	u := createIdentityTestUser(t, db, st, "patient", nil)
	bindTestGoogle(t, st, u.ID)
	srv := newOnboardingTestServer(db)

	rec := callUnbind(srv, u.ID, "patient", "")
	if rec.Code != http.StatusConflict || unbindCode(rec) != googlePasswordRequiredCode {
		t.Fatalf("expected 409 perlu_password, got %d %s", rec.Code, rec.Body.String())
	}
	// Tautan belum berubah.
	ident, err := st.GetGoogleIdentity(context.Background(), u.ID)
	if err != nil || !ident.Linked {
		t.Fatalf("tautan hilang setelah penolakan: %+v %v", ident, err)
	}
}

//  2. Pasien tertaut → unbind dengan password baru valid → 200, SSO NULL,
//     dan login memakai email + password baru berhasil.
func TestUnbindGoogleWithNewPassword(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	ctx := context.Background()
	u := createIdentityTestUser(t, db, st, "patient", nil)
	bindTestGoogle(t, st, u.ID)
	srv := newOnboardingTestServer(db)

	newPassword := "NewPassword123!"
	rec := callUnbind(srv, u.ID, "patient", `{"new_password":"`+newPassword+`"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d %s", rec.Code, rec.Body.String())
	}
	var ident store.GoogleIdentity
	if err := json.Unmarshal(rec.Body.Bytes(), &ident); err != nil || ident.Linked {
		t.Fatalf("respons unbind tidak valid: %s (%v)", rec.Body.String(), err)
	}

	// Kolom SSO harus NULL semua.
	var provider, ssoID, ssoEmail sql.NullString
	var linkedAt sql.NullTime
	if err := db.QueryRow(`SELECT sso_provider, sso_id, sso_email, sso_linked_at FROM users WHERE id=$1`, u.ID).
		Scan(&provider, &ssoID, &ssoEmail, &linkedAt); err != nil {
		t.Fatal(err)
	}
	if provider.Valid || ssoID.Valid || ssoEmail.Valid || linkedAt.Valid {
		t.Fatalf("kolom SSO tidak NULL: %v %v %v %v", provider, ssoID, ssoEmail, linkedAt)
	}

	// Email akun pasien tidak berubah (bukan placeholder).
	finalUser, err := st.GetUserByID(ctx, u.ID)
	if err != nil || finalUser.Email != u.Email {
		t.Fatalf("email pasien berubah: %+v %v", finalUser, err)
	}

	// Login dengan email + password baru berhasil.
	loginBody := fmt.Sprintf(`{"email":%q,"password":%q}`, finalUser.Email, newPassword)
	loginRec := httptest.NewRecorder()
	srv.login(loginRec, httptest.NewRequest("POST", "/v1/auth/login", strings.NewReader(loginBody)))
	if loginRec.Code != http.StatusOK {
		t.Fatalf("login pasca-unbind gagal: %d %s", loginRec.Code, loginRec.Body.String())
	}
}

//  3. Profesional placeholder → bind → unbind → email TETAP Gmail.
//     Ini keputusan sadar (bukan lupa): setelah unbind akun tetap ada dan Gmail
//     itu memang email kontaknya; mengembalikannya ke placeholder fiktif akan
//     merusak data dan memutus notifikasi.
func TestUnbindGoogleKeepsGmailForProfessional(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	ctx := context.Background()
	u := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{Specialization: "Sp.KJ"})
	gmail := "pro-gmail-" + u.ID + "@example.test"
	if _, err := st.LinkGoogleIdentity(ctx, u.ID, "sub-"+u.ID, gmail, false); err != nil {
		t.Fatal(err)
	}
	// Bind meng-upgrade email placeholder ke Gmail.
	if bound, err := st.GetUserByID(ctx, u.ID); err != nil || bound.Email != gmail {
		t.Fatalf("bind tidak meng-upgrade placeholder: %+v %v", bound, err)
	}
	srv := newOnboardingTestServer(db)
	rec := callUnbind(srv, u.ID, "professional", `{"new_password":"NewPassword123!"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d %s", rec.Code, rec.Body.String())
	}
	// Email tetap Gmail (sengaja TIDAK dipulihkan ke placeholder).
	finalUser, err := st.GetUserByID(ctx, u.ID)
	if err != nil || finalUser.Email != gmail {
		t.Fatalf("email berubah saat unbind: got %q want %q (%v)", finalUser.Email, gmail, err)
	}
}

// 4. Token OAuth Google milik user terhapus setelah unbind.
func TestUnbindGoogleDeletesOAuthTokens(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	ctx := context.Background()
	u := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{Specialization: "Sp.KJ"})
	bindTestGoogle(t, st, u.ID)
	if err := st.UpsertGoogleToken(ctx, u.ID, "refresh", "access", time.Now().Add(time.Hour),
		"https://www.googleapis.com/auth/calendar.events", "sub-"+u.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := st.GetGoogleToken(ctx, u.ID); err != nil {
		t.Fatalf("token seharusnya ada sebelum unbind: %v", err)
	}
	srv := newOnboardingTestServer(db)
	rec := callUnbind(srv, u.ID, "professional", `{"new_password":"NewPassword123!"}`)
	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d %s", rec.Code, rec.Body.String())
	}
	if _, err := st.GetGoogleToken(ctx, u.ID); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("token OAuth tidak terhapus: %v", err)
	}
}

//  5. Akun tanpa tautan → 409 google_belum_tertaut (kredensial valid tetap
//     dikirim agar lolos gerbang kredensial lebih dulu).
func TestUnbindGoogleNotLinked(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	u := createIdentityTestUser(t, db, st, "patient", nil)
	srv := newOnboardingTestServer(db)
	rec := callUnbind(srv, u.ID, "patient", `{"new_password":"NewPassword123!"}`)
	if rec.Code != http.StatusConflict || unbindCode(rec) != googleNotLinkedCode {
		t.Fatalf("expected 409 google_belum_tertaut, got %d %s", rec.Code, rec.Body.String())
	}
}

// 6. current_password salah → 401 password_salah, tautan tetap ada.
func TestUnbindGoogleWrongCurrentPassword(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	ctx := context.Background()
	u := createIdentityTestUser(t, db, st, "patient", nil)
	hash, err := auth.HashPassword("CorrectPassword123!")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`UPDATE users SET password_hash=$2 WHERE id=$1`, u.ID, hash); err != nil {
		t.Fatal(err)
	}
	bindTestGoogle(t, st, u.ID)
	srv := newOnboardingTestServer(db)
	rec := callUnbind(srv, u.ID, "patient", `{"current_password":"WrongPassword123!"}`)
	if rec.Code != http.StatusUnauthorized || unbindCode(rec) != googlePasswordWrongCode {
		t.Fatalf("expected 401 password_salah, got %d %s", rec.Code, rec.Body.String())
	}
	ident, err := st.GetGoogleIdentity(ctx, u.ID)
	if err != nil || !ident.Linked {
		t.Fatalf("tautan hilang padahal password salah: %+v %v", ident, err)
	}
}

// 7. Role admin → 403.
func TestUnbindGoogleRejectsAdmin(t *testing.T) {
	db, _ := openOnboardingTestStore(t)
	srv := newOnboardingTestServer(db)
	rec := callUnbind(srv, "00000000-0000-0000-0000-000000000000", "admin", "")
	if rec.Code != http.StatusForbidden {
		t.Fatalf("expected 403, got %d %s", rec.Code, rec.Body.String())
	}
}
