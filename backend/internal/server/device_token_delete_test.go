package server

import (
	"net/http"
	"testing"
)

// ============================================================
// QA — DELETE /v1/device-tokens (cabut token FCM saat logout).
//
// Test ini TIDAK butuh database: jalur yang diuji (401 tanpa token, 400 bila
// body tanpa token) terjadi SEBELUM lapisan store disentuh. Server uji dibuat
// dengan store nil (lihat newSafetyTestServer).
// ============================================================

// TestDeleteDeviceTokenRequiresAuth: tanpa token -> 401.
func TestDeleteDeviceTokenRequiresAuth(t *testing.T) {
	srv, _, _ := newSafetyTestServer()
	handler := srv.Routes()

	rec := doAuthed(t, handler, "DELETE", "/v1/device-tokens", "", `{"token":"abc"}`)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("tanpa token harus 401, dapat %d: %s", rec.Code, rec.Body.String())
	}
}

// TestDeleteDeviceTokenEmptyTokenBadRequest: token kosong -> 400, bukan 500.
func TestDeleteDeviceTokenEmptyTokenBadRequest(t *testing.T) {
	srv, patientToken, _ := newSafetyTestServer()
	handler := srv.Routes()

	rec := doAuthed(t, handler, "DELETE", "/v1/device-tokens", patientToken, `{"token":"   "}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("token kosong harus 400, dapat %d: %s", rec.Code, rec.Body.String())
	}
}

// TestDeleteDeviceTokenMalformedBody: body bukan JSON -> 400.
func TestDeleteDeviceTokenMalformedBody(t *testing.T) {
	srv, patientToken, _ := newSafetyTestServer()
	handler := srv.Routes()

	rec := doAuthed(t, handler, "DELETE", "/v1/device-tokens", patientToken, `not-json`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("body rusak harus 400, dapat %d: %s", rec.Code, rec.Body.String())
	}
}
