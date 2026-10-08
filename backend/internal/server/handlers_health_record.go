package server

import (
	"database/sql"
	"errors"
	"net/http"
	"strings"

	"malva/backend/internal/auth"
	"malva/backend/internal/security"
)

// ============================================================
// HEALTH RECORD — diagnosis summary pasien.
//
// Aturan akses:
//   - Pasien: read-only untuk dirinya sendiri (GET).
//   - Profesional terverifikasi: GET pasien terhubung + PUT diagnosis
//     (wajib konsen health_record pasien).
// ============================================================

type healthRecordUpdateRequest struct {
	PatientID        string `json:"patient_id"`
	DiagnosisSummary string `json:"diagnosis_summary"`
}

func (s *Server) getHealthRecord(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	patientID, err := s.authorizePatientAccess(r, claims, r.URL.Query().Get("patient_id"))
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	if claims.Role == "professional" && !s.consentAllows(r, patientID, claims.Subject, "health_record") {
		writeError(w, http.StatusForbidden, errors.New("pasien belum membagikan Health Record"))
		return
	}
	record, err := s.store.GetHealthRecord(r.Context(), patientID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, errors.New("Health record tidak ditemukan."))
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"health_record": record})
}

// updateHealthRecord menulis diagnosis pasien. Hanya profesional
// terverifikasi yang terhubung + mendapat konsen health_record.
func (s *Server) updateHealthRecord(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if !s.requireVerifiedProfessional(w, r, claims) {
		return
	}
	var req healthRecordUpdateRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	patientID, err := s.authorizePatientAccess(r, claims, req.PatientID)
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	if !s.consentAllows(r, patientID, claims.Subject, "health_record") {
		writeError(w, http.StatusForbidden, errors.New("pasien belum membagikan Health Record"))
		return
	}
	diagnosis := security.SanitizeText(strings.TrimSpace(req.DiagnosisSummary))
	if len(diagnosis) > 2000 {
		writeError(w, http.StatusBadRequest, errors.New("diagnosis maksimal 2000 karakter."))
		return
	}
	record, err := s.store.UpdateHealthRecordDiagnosis(r.Context(), claims.Subject, patientID, diagnosis)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, errors.New("Health record tidak ditemukan."))
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	// Beri tahu pasien bahwa diagnosis diperbarui.
	s.notifyPatient(r, patientID, "health_record_updated",
		"Health Record diperbarui",
		"Profesional memperbarui diagnosis di Health Record kamu.",
		map[string]string{"patient_id": patientID})
	writeJSON(w, http.StatusOK, map[string]any{"health_record": record})
}
