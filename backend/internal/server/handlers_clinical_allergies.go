package server

import (
	"database/sql"
	"errors"
	"net/http"
	"strings"

	"malva/backend/internal/auth"
	"malva/backend/internal/security"
	"malva/backend/internal/store"
)

type clinicalAllergyFields struct {
	ReactionType string `json:"reaction_type"`
	Substance    string `json:"substance"`
	Symptoms     string `json:"symptoms"`
	Severity     string `json:"severity"`
}

type createClinicalAllergyRequest struct {
	clinicalAllergyFields
	ClientID     string `json:"client_id"`
	OccurredWhen string `json:"occurred_when"`
}

func (s *Server) listHealthRecordAllergies(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	patientID, err := s.authorizePatientAccess(r, claims, r.URL.Query().Get("patient_id"))
	if err != nil || (claims.Role == "professional" && !s.consentAllows(r, patientID, claims.Subject, "health_record")) {
		writeUserError(w, http.StatusForbidden, "Profil Klinis tidak dibagikan.")
		return
	}
	items, err := s.store.ListClinicalAllergies(r.Context(), patientID)
	if err != nil {
		writeUserError(w, http.StatusInternalServerError, "Gagal memuat catatan alergi.")
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

func (s *Server) createHealthRecordAllergy(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "patient" {
		writeUserError(w, http.StatusForbidden, "Hanya pasien yang dapat menambahkan catatan pada profilnya.")
		return
	}
	var req createClinicalAllergyRequest
	if err := readJSON(r, &req); err != nil {
		writeUserError(w, http.StatusBadRequest, "Catatan alergi tidak valid.")
		return
	}
	item, valid := req.clinicalAllergyFields.validated()
	item.OccurredWhen = strings.TrimSpace(security.SanitizeText(req.OccurredWhen))
	if !valid || len(item.OccurredWhen) > 240 {
		writeUserError(w, http.StatusBadRequest, "Periksa jenis reaksi, nama pemicu, gejala, dan tingkat keparahan.")
		return
	}
	if req.ClientID != "" {
		if !store.ValidClinicalClientID(req.ClientID) {
			writeUserError(w, http.StatusBadRequest, "ID catatan tidak valid.")
			return
		}
		item.ID = store.ClinicalRetryID("clinical_allergy", claims.Subject, strings.ToLower(req.ClientID))
	}
	created, err := s.store.CreateClinicalAllergy(r.Context(), claims.Subject, item)
	if errors.Is(err, store.ErrClinicalAllergyRetryConflict) {
		writeUserError(w, http.StatusConflict, "Catatan berbeda untuk permintaan yang sama.")
		return
	}
	if err != nil {
		writeUserError(w, http.StatusInternalServerError, "Gagal menyimpan catatan alergi.")
		return
	}
	s.publishClinicalChange(claims.Subject, "health_record")
	writeJSON(w, http.StatusOK, map[string]any{"item": created})
}

func (req clinicalAllergyFields) validated() (store.ClinicalAllergy, bool) {
	item := store.ClinicalAllergy{
		ReactionType: req.ReactionType, Severity: req.Severity,
		Substance: strings.TrimSpace(security.SanitizeText(req.Substance)),
		Symptoms:  strings.TrimSpace(security.SanitizeText(req.Symptoms)),
	}
	return item, (item.ReactionType == "allergy" || item.ReactionType == "side_effect") &&
		(item.Severity == "mild" || item.Severity == "moderate" || item.Severity == "high") &&
		item.Substance != "" && len(item.Substance) <= 240 &&
		item.Symptoms != "" && len(item.Symptoms) <= 2000
}

func allergyMutationID(w http.ResponseWriter, r *http.Request, claims auth.Claims) (string, bool) {
	if claims.Role != "patient" {
		writeUserError(w, http.StatusForbidden, "Hanya pasien yang dapat mengubah catatan pada profilnya.")
		return "", false
	}
	id := r.PathValue("allergy_id")
	if !store.ValidClinicalClientID(id) {
		writeUserError(w, http.StatusNotFound, "Catatan alergi tidak ditemukan.")
		return "", false
	}
	return id, true
}

func (s *Server) updateHealthRecordAllergy(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	id, ok := allergyMutationID(w, r, claims)
	if !ok {
		return
	}
	var req clinicalAllergyFields
	if err := readJSON(r, &req); err != nil {
		writeUserError(w, http.StatusBadRequest, "Catatan alergi tidak valid.")
		return
	}
	item, valid := req.validated()
	if !valid {
		writeUserError(w, http.StatusBadRequest, "Periksa jenis reaksi, nama pemicu, gejala, dan tingkat keparahan.")
		return
	}
	item.ID = id
	saved, err := s.store.UpdateClinicalAllergy(r.Context(), claims.Subject, item)
	if errors.Is(err, sql.ErrNoRows) {
		writeUserError(w, http.StatusNotFound, "Catatan alergi tidak ditemukan.")
		return
	}
	if err != nil {
		writeUserError(w, http.StatusInternalServerError, "Gagal memperbarui catatan alergi.")
		return
	}
	s.publishClinicalChange(claims.Subject, "health_record")
	writeJSON(w, http.StatusOK, map[string]any{"item": saved})
}

func (s *Server) deleteHealthRecordAllergy(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	id, ok := allergyMutationID(w, r, claims)
	if !ok {
		return
	}
	err := s.store.DeleteClinicalAllergy(r.Context(), claims.Subject, id)
	if errors.Is(err, sql.ErrNoRows) {
		writeUserError(w, http.StatusNotFound, "Catatan alergi tidak ditemukan.")
		return
	}
	if err != nil {
		writeUserError(w, http.StatusInternalServerError, "Gagal menghapus catatan alergi.")
		return
	}
	s.publishClinicalChange(claims.Subject, "health_record")
	writeJSON(w, http.StatusOK, map[string]bool{"deleted": true})
}
