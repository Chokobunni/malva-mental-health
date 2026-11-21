package server

import (
	"database/sql"
	"errors"
	"net/http"

	"malva/backend/internal/auth"
	"malva/backend/internal/realtime"
)

func (s *Server) deleteChatMessage(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "patient" && claims.Role != "professional" {
		writeError(w, http.StatusForbidden, errors.New("peran tidak diizinkan menghapus pesan"))
		return
	}
	id := r.PathValue("message_id")
	patientID, professionalID, err := s.store.DeleteOwnChatMessage(r.Context(), id, claims.Subject, claims.Role)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, errors.New("pesan tidak ditemukan"))
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	_ = s.store.AddAuditLog(r.Context(), claims.Subject, patientID, "chat_message.deleted", "chat_message", id, nil)
	if s.hub != nil {
		event := realtime.Event{Type: "chat_message_deleted", Data: map[string]string{
			"id": id, "patient_id": patientID, "professional_id": professionalID,
		}}
		s.hub.Publish(patientID, event)
		s.hub.Publish(professionalID, event)
	}
	w.WriteHeader(http.StatusNoContent)
}
