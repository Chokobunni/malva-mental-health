package server

import (
	"net/http"
	"testing"
)

// ============================================================
// QA — W6: endpoint GET /v1/crisis-incident-log hanya untuk profesional.
// Pasien (dan tanpa token) tidak boleh mengakses feed gabungan SOS + screening
// krisis milik semua pasien terhubung.
//
// Catatan: test ini TIDAK butuh database — penolakan 403/401 terjadi SEBELUM
// lapisan store disentuh.
// ============================================================

// TestCrisisIncidentLogPatientForbidden: pasien memanggil endpoint -> 403.
func TestCrisisIncidentLogPatientForbidden(t *testing.T) {
	srv, patientToken, _ := newSafetyTestServer()
	handler := srv.Routes()

	rec := doAuthed(t, handler, "GET", "/v1/crisis-incident-log", patientToken, "")
	if rec.Code != http.StatusForbidden {
		t.Fatalf("pasien harus 403, dapat %d: %s", rec.Code, rec.Body.String())
	}
}

// TestCrisisIncidentLogRequiresAuth: tanpa token -> 401.
func TestCrisisIncidentLogRequiresAuth(t *testing.T) {
	srv, _, _ := newSafetyTestServer()
	handler := srv.Routes()

	rec := doAuthed(t, handler, "GET", "/v1/crisis-incident-log", "", "")
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("tanpa token harus 401, dapat %d: %s", rec.Code, rec.Body.String())
	}
}
