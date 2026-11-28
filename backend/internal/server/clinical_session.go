package server

import (
	"errors"
	"net/http"
	"strings"

	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
	"malva/backend/internal/realtime"
	"malva/backend/internal/store"
)

// The selected notes session extends only this editor's clinical mutations.
func (s *Server) requireSessionNoteMutation(w http.ResponseWriter, r *http.Request, claims auth.Claims, patientID, scope string) bool {
	sessionID := strings.TrimSpace(r.URL.Query().Get("session_id"))
	if r.Method == http.MethodDelete {
		sessionID = ""
	}
	if sessionID == "" {
		if !s.consentAllows(r, patientID, claims.Subject, scope) {
			writeUserError(w, http.StatusForbidden, "Pasien belum membagikan data ini.")
			return false
		}
		_, ok := s.requireClinicalSession(w, r, claims, patientID)
		return ok
	}
	cs, err := s.store.GetCareSession(r.Context(), sessionID)
	if err != nil || claims.Role != "professional" || cs.ProfessionalID != claims.Subject || cs.PatientID != patientID || !cs.CanManageNoteResourcesAt(clock.Now()) {
		writeUserError(w, http.StatusForbidden, "Sesi tidak tersedia untuk pengisian catatan.")
		return false
	}
	if cs.Status == "scheduled" {
		access, err := s.store.ChatAccessFor(r.Context(), patientID, claims.Subject, "professional")
		if err != nil || !access.InSession || access.SessionID != cs.ID {
			writeUserError(w, http.StatusForbidden, "Sesi klinis tidak aktif.")
			return false
		}
	}
	consent, err := s.store.GetPatientDataConsent(r.Context(), patientID, claims.Subject)
	if err != nil || (scope == "goals" && !consent.ShareGoals) || (scope == "medications" && !consent.ShareMedications) {
		writeUserError(w, http.StatusForbidden, "Pasien belum membagikan data ini.")
		return false
	}
	return true
}

func (s *Server) requireClinicalSession(w http.ResponseWriter, r *http.Request, claims auth.Claims, patientID string) (store.ChatAccess, bool) {
	access, err := s.store.ChatAccessFor(r.Context(), patientID, claims.Subject, "professional")
	if err != nil || !access.InSession || access.SessionID == "" {
		writeError(w, http.StatusForbidden, errors.New("perubahan klinis hanya tersedia selama sesi aktif"))
		return store.ChatAccess{}, false
	}
	return access, true
}

func (s *Server) publishClinicalChange(patientID, resource string) {
	if s.hub != nil {
		s.hub.Publish(patientID, realtime.Event{Type: "clinical_data_changed", Data: map[string]string{"patient_id": patientID, "resource": resource}})
	}
}
