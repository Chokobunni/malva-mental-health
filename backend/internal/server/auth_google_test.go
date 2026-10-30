package server

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

// TestGoogleSubjectFromUserinfo membuktikan fallback identitas Google bekerja:
// access token dikirim sebagai Bearer, dan `sub` dari respons UserInfo dipakai
// sebagai identitas akun.
//
// Ini penutup bug "Aktifkan Google Meet selalu gagal": klien Flutter hanya
// meminta scope calendar.events, sehingga token endpoint tidak mengembalikan
// id_token dan identitas harus diambil dari UserInfo.
func TestGoogleSubjectFromUserinfo(t *testing.T) {
	var gotAuth string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotAuth = r.Header.Get("Authorization")
		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(`{"sub":"123","email":"prof@example.test","email_verified":true}`))
	}))
	defer srv.Close()

	subject, err := googleSubjectFromUserinfo(t.Context(), "access-token-uji", srv.URL)
	if err != nil {
		t.Fatalf("googleSubjectFromUserinfo error: %v", err)
	}
	if subject != "123" {
		t.Errorf("sub = %q, mau %q", subject, "123")
	}
	if gotAuth != "Bearer access-token-uji" {
		t.Errorf("Authorization = %q, mau %q", gotAuth, "Bearer access-token-uji")
	}
}

// TestGoogleSubjectFromUserinfoRejectsError membuktikan kegagalan UserInfo
// (mis. token tidak valid) dikembalikan sebagai error — bukan sub kosong yang
// diam-diam dianggap sah.
func TestGoogleSubjectFromUserinfoRejectsError(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusUnauthorized)
		_, _ = w.Write([]byte(`{"error":"invalid_token"}`))
	}))
	defer srv.Close()

	subject, err := googleSubjectFromUserinfo(t.Context(), "access-token-kedaluwarsa", srv.URL)
	if err == nil {
		t.Fatalf("status 401 harus menghasilkan error, dapat sub %q", subject)
	}
	if subject != "" {
		t.Errorf("sub harus kosong saat error, dapat %q", subject)
	}
}

// TestGoogleSubjectFromUserinfoRejectsEmptyInput memastikan input tidak masuk
// akal ditolak lebih awal tanpa memanggil jaringan.
func TestGoogleSubjectFromUserinfoRejectsEmptyInput(t *testing.T) {
	if _, err := googleSubjectFromUserinfo(t.Context(), "   ", "https://example.test/userinfo"); err == nil {
		t.Fatal("access token kosong harus menghasilkan error")
	}
	if _, err := googleSubjectFromUserinfo(t.Context(), "token", ""); err == nil {
		t.Fatal("endpoint kosong harus menghasilkan error")
	}
}
