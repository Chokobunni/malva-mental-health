package server

import (
	"database/sql"
	"errors"
	"net/http"
	"strings"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
	googlecal "malva/backend/internal/google"
	"malva/backend/internal/store"
)

type completeProfessionalRequest struct {
	STRNumber      string `json:"str_number"`
	SIPNumber      string `json:"sip_number"`
	Specialization string `json:"specialization"`
	DisplayName    string `json:"display_name"`
	// Accepted for old clients, but never used to merge or authorize another account.
	ExistingPassword string `json:"existing_password"`
}

func (s *Server) completeProfessionalProfile(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "professional" {
		writeUserError(w, http.StatusForbidden, "only professionals can complete this profile")
		return
	}
	var req completeProfessionalRequest
	if err := readJSON(r, &req); err != nil {
		writeUserError(w, http.StatusBadRequest, "invalid professional profile request")
		return
	}
	strNumber := strings.TrimSpace(req.STRNumber)
	sipNumber := strings.TrimSpace(req.SIPNumber)
	specialization := strings.TrimSpace(req.Specialization)
	if strNumber == "" || sipNumber == "" {
		writeUserError(w, http.StatusBadRequest, "STR and SIP are required")
		return
	}
	if !validSpecialization(specialization) {
		writeUserError(w, http.StatusBadRequest, "specialization must be Sp.KJ or M.Psi")
		return
	}
	if err := s.rejectTakenProfessionalIdentifier(r, strNumber, sipNumber, claims.Subject); err != nil {
		writeProfessionalError(w, err)
		return
	}
	// Preserve all existing credential details; completion changes only these fields.
	credential, err := s.store.GetProfessionalCredential(r.Context(), claims.Subject)
	if errors.Is(err, sql.ErrNoRows) {
		credential = store.ProfessionalCredential{UserID: claims.Subject}
	} else if err != nil {
		writeProfessionalError(w, err)
		return
	}
	credential.STRNumber = strNumber
	credential.SIPNumber = sipNumber
	credential.Specialization = specialization
	credential, err = s.store.CompleteProfessionalProfile(r.Context(), credential, req.DisplayName)
	if err != nil {
		writeProfessionalError(w, err)
		return
	}
	user, err := s.store.GetUserByID(r.Context(), claims.Subject)
	if err != nil {
		writeProfessionalError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"user": user, "credential": credential})
}

func (s *Server) createQuickMeet(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "professional" {
		writeUserError(w, http.StatusForbidden, "only professionals can create Meet links")
		return
	}
	if s.calendar == nil {
		writeUserError(w, http.StatusNotImplemented, "Google Calendar is not configured")
		return
	}
	now := clock.Now()
	eventID, meetURL, err := s.calendar.CreateMeetEvent(r.Context(), claims.Subject, googlecal.MeetEventOptions{
		Summary: "Sesi Cepat Malva", StartTime: now, EndTime: now.Add(30 * time.Minute),
	})
	if err != nil {
		if errors.Is(err, googlecal.ErrReauthNeeded) {
			writeUserError(w, http.StatusUnauthorized, "authorize Google Calendar for the bound Google account")
			return
		}
		writeUserError(w, http.StatusInternalServerError, "could not create video call link")
		return
	}
	writeJSON(w, http.StatusCreated, map[string]string{"meet_url": meetURL, "event_id": eventID})
}
