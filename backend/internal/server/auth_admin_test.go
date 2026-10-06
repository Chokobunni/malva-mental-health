package server

import (
	"net/http"
	"strings"
	"testing"

	"malva/backend/internal/auth"
)

// Google login tanpa konfigurasi server harus gagal dengan pesan jelas (501),
// bukan error misterius.
func TestGoogleLoginRequiresServerConfig(t *testing.T) {
	srv, _, _ := newSafetyTestServer()
	handler := srv.Routes()
	rec := doAuthed(t, handler, "POST", "/v1/auth/google", "", `{"id_token":"xxx"}`)
	if rec.Code != http.StatusNotImplemented {
		t.Fatalf("mau 501 saat MALVA_GOOGLE_CLIENT_ID kosong, dapat %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "Google") {
		t.Fatalf("pesan harus menyebut Google: %s", rec.Body.String())
	}
}

func TestGoogleLoginRejectsEmptyToken(t *testing.T) {
	srv, _, _ := newSafetyTestServer()
	handler := srv.Routes()
	rec := doAuthed(t, handler, "POST", "/v1/auth/google", "", `{"id_token":""}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("mau 400 untuk id_token kosong, dapat %d", rec.Code)
	}
}

// Endpoint admin wajib menolak non-admin dan anonim.
func TestAdminEndpointsGuard(t *testing.T) {
	srv, patientToken, _ := newSafetyTestServer()
	mgr := auth.NewManager("12345678901234567890123456789012")
	adminToken, _ := mgr.Issue("admin-1", "admin")
	handler := srv.Routes()

	adminPaths := []struct{ method, path string }{
		{"GET", "/v1/admin/users"},
		{"PATCH", "/v1/admin/users/u1"},
		{"DELETE", "/v1/admin/users/u1"},
		{"GET", "/v1/admin/credentials/pending"},
		{"POST", "/v1/admin/credentials/c1/verify"},
		{"POST", "/v1/admin/doctors"},
		{"GET", "/v1/admin/doctors/u1"},
		{"PUT", "/v1/admin/doctors/u1"},
	}
	for _, tc := range adminPaths {
		rec := doAuthed(t, handler, tc.method, tc.path, "", `{"x":1}`)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("%s %s tanpa token: mau 401, dapat %d", tc.method, tc.path, rec.Code)
		}
		rec = doAuthed(t, handler, tc.method, tc.path, patientToken, `{"x":1}`)
		if rec.Code != http.StatusForbidden {
			t.Errorf("%s %s role patient: mau 403, dapat %d", tc.method, tc.path, rec.Code)
		}
		// Token admin lolos guard (boleh gagal di store nil, tapi bukan 401/403).
		rec = doAuthed(t, handler, tc.method, tc.path, adminToken, `{"x":1}`)
		if rec.Code == http.StatusUnauthorized || rec.Code == http.StatusForbidden {
			t.Errorf("%s %s role admin: tidak boleh 401/403, dapat %d", tc.method, tc.path, rec.Code)
		}
	}
}

// Register dengan email duplikat harus 409 berbahasa Indonesia —
// diuji di level helper karena butuh DB untuk alur penuh.
func TestIsDuplicateKeyError(t *testing.T) {
	cases := map[string]bool{
		`pq: duplicate key value violates unique constraint "users_email_key"`: true,
		`ERROR: duplicate key value violates unique constraint`:                true,
		`email or password is invalid`:                                         false,
		``:                                                                     false,
	}
	for msg, want := range cases {
		var err error
		if msg != "" {
			err = testErr(msg)
		}
		if got := isDuplicateKeyError(err); got != want {
			t.Errorf("isDuplicateKeyError(%q) = %v, mau %v", msg, got, want)
		}
	}
}

type testErr string

func (e testErr) Error() string { return string(e) }
