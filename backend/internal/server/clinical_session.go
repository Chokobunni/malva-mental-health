package server

import (
	"errors"
	"net/http"

	"malva/backend/internal/auth"
	"malva/backend/internal/realtime"
	"malva/backend/internal/store"
)

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
