package server

import (
	"database/sql"
	"errors"
	"net/http"
	"strings"

	"malva/backend/internal/auth"
	"malva/backend/internal/realtime"
	"malva/backend/internal/store"
)

var errDiaryNotFound = errors.New("diary tidak ditemukan")

func (s *Server) getDiaryEntry(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	w.Header().Set("Cache-Control", "private, no-store")
	diaryID := strings.ToLower(r.PathValue("diary_id"))
	if !store.ValidClinicalClientID(diaryID) {
		writeError(w, http.StatusNotFound, errDiaryNotFound)
		return
	}
	var diary store.DiaryEntry
	var err error
	switch claims.Role {
	case "patient":
		diary, err = s.store.GetDiaryEntry(r.Context(), claims.Subject, diaryID)
	case "professional":
		diary, err = s.store.GetDiaryEntryForProfessional(r.Context(), claims.Subject, diaryID)
	default:
		writeError(w, http.StatusForbidden, errors.New("tidak diizinkan membaca diary"))
		return
	}
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, errDiaryNotFound)
			return
		}
		writeError(w, http.StatusInternalServerError, errors.New("gagal membaca diary"))
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"diary": diary})
}

func (s *Server) getDiaryAccess(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	w.Header().Set("Cache-Control", "private, no-store")
	if claims.Role != "patient" {
		writeError(w, http.StatusForbidden, errors.New("hanya pasien yang dapat mengatur akses diary"))
		return
	}
	diaryID := strings.ToLower(r.PathValue("diary_id"))
	if !store.ValidClinicalClientID(diaryID) {
		writeError(w, http.StatusNotFound, errDiaryNotFound)
		return
	}
	access, err := s.store.GetDiaryAccess(r.Context(), claims.Subject, diaryID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, errDiaryNotFound)
			return
		}
		writeError(w, http.StatusInternalServerError, errors.New("gagal membaca akses diary"))
		return
	}
	writeJSON(w, http.StatusOK, access)
}

func (s *Server) setDiaryRecipient(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	w.Header().Set("Cache-Control", "private, no-store")
	if claims.Role != "patient" {
		writeError(w, http.StatusForbidden, errors.New("hanya pasien yang dapat mengatur akses diary"))
		return
	}
	diaryID := strings.ToLower(r.PathValue("diary_id"))
	professionalID := strings.ToLower(r.PathValue("professional_id"))
	if !store.ValidClinicalClientID(diaryID) {
		writeError(w, http.StatusNotFound, errDiaryNotFound)
		return
	}
	if !store.ValidClinicalClientID(professionalID) {
		writeError(w, http.StatusBadRequest, errors.New("ID profesional tidak valid"))
		return
	}
	access, changed, err := s.store.SetDiaryRecipient(r.Context(), claims.Subject, diaryID, professionalID, r.Method == http.MethodPut)
	if err != nil {
		switch {
		case errors.Is(err, sql.ErrNoRows):
			writeError(w, http.StatusNotFound, errDiaryNotFound)
		case errors.Is(err, store.ErrDiaryRecipientIneligible):
			writeError(w, http.StatusForbidden, err)
		default:
			writeError(w, http.StatusInternalServerError, errors.New("gagal menyimpan akses diary"))
		}
		return
	}
	if changed && s.hub != nil {
		s.hub.Publish(professionalID, realtime.Event{Type: "diary_access_changed", Data: map[string]string{
			"diary_id": diaryID, "patient_id": claims.Subject, "professional_id": professionalID,
		}})
	}
	writeJSON(w, http.StatusOK, access)
}
