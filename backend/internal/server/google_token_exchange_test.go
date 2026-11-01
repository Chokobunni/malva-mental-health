package server

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/store"
)

// ============================================================
// PENUKARAN TOKEN GOOGLE CALENDAR — LEVEL HTTP
//
// Menutup dua bug nyata pada exchangeGoogleToken:
//   1. Error Google ditelan total -> sekarang kode mesin + ErrorCode Google
//      terlihat (google_code_kedaluwarsa / google_error: invalid_grant).
//   2. Kegagalan identitas setelah kode terpakai membalas 401 (memicu klien
//      mengirim ulang kode yang sama) -> sekarang 422 google_identitas_gagal.
//
// Memakai http.DefaultTransport palsu (pola google_identity_test.go) supaya
// tidak ada request jaringan nyata ke Google.
// ============================================================

// installGoogleTokenTransport memasang http.DefaultTransport palsu yang
// melayani token endpoint & userinfo sesuai skenario, lalu memulihkannya saat
// test selesai.
func installGoogleTokenTransport(t *testing.T, tokenStatus int, tokenBody string, userinfoStatus int, userinfoBody string) {
	t.Helper()
	oldTransport := http.DefaultTransport
	http.DefaultTransport = identityTestTransport(func(r *http.Request) (*http.Response, error) {
		switch r.URL.Host {
		case "oauth2.googleapis.com":
			if r.URL.Path != "/token" {
				return nil, errors.New("path token endpoint tak terduga: " + r.URL.Path)
			}
			return &http.Response{
				StatusCode: tokenStatus,
				Header:     http.Header{"Content-Type": []string{"application/json"}},
				Body:       io.NopCloser(strings.NewReader(tokenBody)),
			}, nil
		case "www.googleapis.com":
			if r.URL.Path != "/oauth2/v3/userinfo" {
				return nil, errors.New("path userinfo tak terduga: " + r.URL.Path)
			}
			return &http.Response{
				StatusCode: userinfoStatus,
				Header:     http.Header{"Content-Type": []string{"application/json"}},
				Body:       io.NopCloser(strings.NewReader(userinfoBody)),
			}, nil
		default:
			return nil, errors.New("jaringan dinonaktifkan pada test penukaran token")
		}
	})
	t.Cleanup(func() { http.DefaultTransport = oldTransport })
}

// newTokenExchangeTestServer menyiapkan server + user profesional yang sudah
// menautkan Google (identity.Linked=true) agar handler lolos pengecekan awal.
func newTokenExchangeTestServer(t *testing.T) (*Server, *store.Store, auth.Claims) {
	t.Helper()
	db, st := openOnboardingTestStore(t)
	ctx := context.Background()
	srv := newOnboardingTestServer(db)
	srv.cfg.GoogleClientID = "test-client"
	srv.cfg.GoogleClientSecret = "test-secret"
	u := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{Specialization: "Sp.KJ"})
	suffix := fmt.Sprint(time.Now().UnixNano())
	if _, err := st.LinkGoogleIdentity(ctx, u.ID, "exchange-"+suffix, "exchange-"+suffix+"@example.test", false); err != nil {
		t.Fatalf("tautkan identitas Google: %v", err)
	}
	return srv, st, auth.Claims{Subject: u.ID, Role: "professional"}
}

// TestExchangeGoogleTokenInvalidGrant membuktikan bahwa penolakan Google
// (invalid_grant) dipetakan ke 400 + kode mesin google_code_kedaluwarsa +
// google_error, dan TIDAK ada token yang tersimpan.
func TestExchangeGoogleTokenInvalidGrant(t *testing.T) {
	srv, st, claims := newTokenExchangeTestServer(t)
	installGoogleTokenTransport(t,
		400, `{"error":"invalid_grant","error_description":"Bad Request"}`,
		200, `{"sub":"tidak-dipakai"}`)

	rec := httptest.NewRecorder()
	srv.exchangeGoogleToken(rec,
		httptest.NewRequest("POST", "/v1/auth/google-token-exchange", strings.NewReader(`{"authorization_code":"kode-terpakai"}`)),
		claims)

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, mau 400: %s", rec.Code, rec.Body.String())
	}
	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("respons bukan JSON: %v", err)
	}
	if body["code"] != "google_code_kedaluwarsa" {
		t.Fatalf("code = %q, mau google_code_kedaluwarsa", body["code"])
	}
	if body["google_error"] != "invalid_grant" {
		t.Fatalf("google_error = %q, mau invalid_grant", body["google_error"])
	}
	if _, err := st.GetGoogleToken(context.Background(), claims.Subject); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("token tersimpan padahal penukaran gagal: %v", err)
	}
}

// TestExchangeGoogleTokenUserinfoFailureReturns422 membuktikan bahwa kegagalan
// resolusi identitas SETELAH kode terpakai membalas 422 (BUKAN 401) dengan kode
// mesin google_identitas_gagal — supaya klien tidak me-refresh token lalu
// mengirim ulang kode yang sama.
func TestExchangeGoogleTokenUserinfoFailureReturns422(t *testing.T) {
	srv, _, claims := newTokenExchangeTestServer(t)
	// Exchange sukses (ada refresh token, TANPA id_token) -> handler jatuh ke
	// userinfo, yang kemudian gagal 500.
	installGoogleTokenTransport(t,
		200, `{"access_token":"akses","refresh_token":"refresh","token_type":"Bearer","expires_in":3600}`,
		500, `{"error":"internal"}`)

	rec := httptest.NewRecorder()
	srv.exchangeGoogleToken(rec,
		httptest.NewRequest("POST", "/v1/auth/google-token-exchange", strings.NewReader(`{"authorization_code":"kode-terpakai"}`)),
		claims)

	if rec.Code != http.StatusUnprocessableEntity {
		t.Fatalf("status = %d, mau 422 (BUKAN 401): %s", rec.Code, rec.Body.String())
	}
	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
		t.Fatalf("respons bukan JSON: %v", err)
	}
	if body["code"] != "google_identitas_gagal" {
		t.Fatalf("code = %q, mau google_identitas_gagal", body["code"])
	}
	// Respons 422 kini menyertakan "google_scope" (boleh kosong bila token
	// endpoint tidak mengembalikan scope) agar penyebab bisa didiagnosis dari
	// layar pengguna. Kuncinya HARUS ada walau nilainya kosong.
	if _, ok := body["google_scope"]; !ok {
		t.Fatalf("respons 422 tidak memuat field google_scope: %v", body)
	}
}
