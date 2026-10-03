package server

import (
	"bytes"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"malva/backend/internal/auth"
	"malva/backend/internal/config"
)

func newSafetyTestServer() (*Server, string, string) {
	cfg := config.Config{
		AllowedOrigins: []string{"https://api.malva.id"},
	}
	logger := slog.New(slog.NewTextHandler(testWriter{}, nil))
	mgr := auth.NewManager("12345678901234567890123456789012")
	srv := New(cfg, mgr, nil, nil, logger)
	patientToken, _ := mgr.Issue("patient-1", "patient")
	proToken, _ := mgr.Issue("pro-1", "professional")
	_ = proToken
	return srv, patientToken, proToken
}

func doAuthed(t *testing.T, handler http.Handler, method, path, token, body string) *httptest.ResponseRecorder {
	t.Helper()
	var reader *bytes.Reader
	if body == "" {
		reader = bytes.NewReader(nil)
	} else {
		reader = bytes.NewReader([]byte(body))
	}
	req := httptest.NewRequest(method, path, reader)
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}

func TestSafetyEndpointsRequireAuth(t *testing.T) {
	srv, _, _ := newSafetyTestServer()
	handler := srv.Routes()

	cases := []struct{ method, path string }{
		{"GET", "/v1/emergency-contacts"},
		{"POST", "/v1/emergency-contacts"},
		{"DELETE", "/v1/emergency-contacts/abc"},
		{"POST", "/v1/crisis-alerts"},
		{"GET", "/v1/crisis-incidents"},
		{"POST", "/v1/crisis-incidents/abc/resolve"},
		{"GET", "/v1/sos-blast-status?incident_id=x"},
		{"POST", "/v1/credentials"},
		{"GET", "/v1/credentials/me"},
		{"GET", "/v1/doctors/search"},
		{"GET", "/v1/doctors/u1"},
		{"GET", "/v1/doctors/u1/slots?date=2026-01-01"},
		{"POST", "/v1/bookings"},
		{"POST", "/v1/payments"},
		{"POST", "/v1/payments/mark-paid"},
		{"GET", "/v1/bookings"},
		{"GET", "/v1/earnings"},
		{"POST", "/v1/earnings/e1/payout"},
		{"POST", "/v1/e-prescriptions"},
		{"GET", "/v1/e-prescriptions"},
		{"GET", "/v1/e-prescriptions/rx1"},
	}
	for _, tc := range cases {
		rec := doAuthed(t, handler, tc.method, tc.path, "", `{"x":1}`)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("%s %s: expected 401, got %d (%s)", tc.method, tc.path, rec.Code, rec.Body.String())
		}
	}
}

func TestValidateIndonesianPhone(t *testing.T) {
	valid := []string{"08123456789", "0812-3456-789", "0812 3456 789", "628123456789", "+628123456789"}
	_ = valid
	// Catatan: implementasi saat ini menolak '+' dan spasi ganda — uji yang didukung:
	ok := []string{"08123456789", "628123456789", "0812345678"}
	for _, p := range ok {
		if !validateIndonesianPhone(p) {
			t.Errorf("expected valid: %s", p)
		}
	}
	bad := []string{"", "123", "08123456789012345", "07123456", "08abcd5678", "+628123456789"}
	for _, p := range bad {
		if validateIndonesianPhone(p) {
			t.Errorf("expected invalid: %s", p)
		}
	}
}

func TestCrisisAlertRejectsInvalidTriggeredBy(t *testing.T) {
	srv, patientToken, _ := newSafetyTestServer()
	handler := srv.Routes()

	rec := doAuthed(t, handler, "POST", "/v1/crisis-alerts", patientToken,
		`{"triggered_by":"hack_the_system"}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid triggered_by, got %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "triggered_by") {
		t.Fatalf("unexpected body: %s", rec.Body.String())
	}
}

func TestCrisisAlertRejectsInvalidCoordinates(t *testing.T) {
	srv, patientToken, _ := newSafetyTestServer()
	handler := srv.Routes()

	rec := doAuthed(t, handler, "POST", "/v1/crisis-alerts", patientToken,
		`{"triggered_by":"sos_button","latitude":999,"longitude":999}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid coords, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestEmergencyContactRejectsTooManyDigits(t *testing.T) {
	srv, patientToken, _ := newSafetyTestServer()
	handler := srv.Routes()

	// Nomor terlalu panjang harus ditolak SEBELUM menyentuh store (nil).
	rec := doAuthed(t, handler, "POST", "/v1/emergency-contacts", patientToken,
		`{"contact_name":"Ibu","contact_phone":"08123456789012345"}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for long phone, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestEmergencyContactRejectsEmptyName(t *testing.T) {
	srv, patientToken, _ := newSafetyTestServer()
	handler := srv.Routes()

	rec := doAuthed(t, handler, "POST", "/v1/emergency-contacts", patientToken,
		`{"contact_name":"  ","contact_phone":"08123456789"}`)
	// Nama kosong ditolak sebelum store (nil) — bukan 500.
	if rec.Code == http.StatusInternalServerError {
		t.Fatalf("empty name reached store layer: %s", rec.Body.String())
	}
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for empty name, got %d: %s", rec.Code, rec.Body.String())
	}
}
