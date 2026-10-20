package notify

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestNormalisasiNomorWA(t *testing.T) {
	cases := map[string]string{
		"081234567890":     "6281234567890",
		"0812-3456-7890":   "6281234567890",
		"+62 812 3456 789": "628123456789",
		"81234567890":      "6281234567890",
		"6281234567890":    "6281234567890",
		"":                 "",
		"123":              "",
	}
	for in, want := range cases {
		if got := normalisasiNomorWA(in); got != want {
			t.Errorf("normalisasiNomorWA(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestNewFonnteSenderTanpaToken(t *testing.T) {
	if s := NewFonnteSender("   ", "https://api.fonnte.com"); s != nil {
		t.Fatalf("token kosong harus menghasilkan nil, dapat %#v", s)
	}
}

func TestFonnteSendSukses(t *testing.T) {
	var gotAuth, gotTarget, gotMessage, gotCountry string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			t.Errorf("method = %s, want POST", r.Method)
		}
		if r.URL.Path != "/send" {
			t.Errorf("path = %s, want /send", r.URL.Path)
		}
		gotAuth = r.Header.Get("Authorization")
		if err := r.ParseForm(); err != nil {
			t.Fatalf("parse form: %v", err)
		}
		gotTarget = r.PostForm.Get("target")
		gotMessage = r.PostForm.Get("message")
		gotCountry = r.PostForm.Get("countryCode")
		_, _ = w.Write([]byte(`{"detail":"success! message in queue","id":["80367170"],"process":"pending","requestid":2937124,"status":true,"target":["6281234567890"]}`))
	}))
	defer srv.Close()

	s := NewFonnteSender("tok123", srv.URL)
	id, err := s.Send(context.Background(), "0812-3456-7890", "halo")
	if err != nil {
		t.Fatalf("Send error: %v", err)
	}
	if id != "80367170" {
		t.Errorf("id = %q, want 80367170", id)
	}
	if gotAuth != "tok123" {
		t.Errorf("Authorization = %q, want token apa adanya tanpa Bearer", gotAuth)
	}
	if gotTarget != "6281234567890" {
		t.Errorf("target = %q, want 6281234567890", gotTarget)
	}
	if gotCountry != "62" {
		t.Errorf("countryCode = %q, want 62", gotCountry)
	}
	if gotMessage != "halo" {
		t.Errorf("message = %q, want halo", gotMessage)
	}
}

func TestFonnteSendDitolakGateway(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, _ = w.Write([]byte(`{"status":false,"reason":"insufficient quota","requestid":7}`))
	}))
	defer srv.Close()

	s := NewFonnteSender("tok123", srv.URL)
	if _, err := s.Send(context.Background(), "081234567890", "halo"); err == nil {
		t.Fatal("harus error saat gateway menolak")
	} else if !strings.Contains(err.Error(), "insufficient quota") {
		t.Fatalf("error harus memuat alasan gateway, dapat %q", err.Error())
	}
}

func TestFonnteSendResponsBukanJSON(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusBadGateway)
		_, _ = w.Write([]byte("<html>bad gateway</html>"))
	}))
	defer srv.Close()

	s := NewFonnteSender("tok123", srv.URL)
	if _, err := s.Send(context.Background(), "081234567890", "halo"); err == nil {
		t.Fatal("harus error saat respons bukan JSON")
	}
}

func TestFonnteSendTanpaNomorValid(t *testing.T) {
	s := NewFonnteSender("tok123", "https://api.fonnte.com")
	if _, err := s.Send(context.Background(), "abc", "halo"); err == nil {
		t.Fatal("harus error saat nomor tidak valid")
	}
}

func TestFonnteSenderNil(t *testing.T) {
	var s *FonnteSender
	if _, err := s.Send(context.Background(), "081234567890", "halo"); err == nil {
		t.Fatal("sender nil harus error, bukan panic")
	}
}
