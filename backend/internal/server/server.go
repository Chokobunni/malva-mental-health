package server

import (
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/config"
	"malva/backend/internal/realtime"
	"malva/backend/internal/screening"
	"malva/backend/internal/store"
)

type Server struct {
	cfg    config.Config
	auth   auth.Manager
	store  *store.Store
	hub    *realtime.Hub
	logger *slog.Logger
	limits *rateLimiter
}

type registerRequest struct {
	Email          string `json:"email"`
	Password       string `json:"password"`
	DisplayName    string `json:"display_name"`
	Role           string `json:"role"`
	ProfessionalID string `json:"professional_id"`
}

type loginRequest struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

type refreshTokenRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type deviceTokenRequest struct {
	Platform string `json:"platform"`
	Token    string `json:"token"`
}

type screeningRequest struct {
	PatientID string `json:"patient_id"`
	Source    string `json:"source"`
	IsInitial bool   `json:"is_initial"`
	PHQ9      []int  `json:"phq9"`
	GAD7      []int  `json:"gad7"`
}

type screeningReviewRequest struct {
	Status string `json:"status"`
	Note   string `json:"note"`
}

type linkProfessionalRequest struct {
	ProfessionalID string `json:"professional_id"`
}

type professionalNoteRequest struct {
	PatientID  string `json:"patient_id"`
	Body       string `json:"body"`
	Visibility string `json:"visibility"`
}

type followUpRequest struct {
	PatientID string `json:"patient_id"`
	Body      string `json:"body"`
	Status    string `json:"status"`
}

type moodCheckinRequest struct {
	Mood         string  `json:"mood"`
	SleepHours   float64 `json:"sleep_hours"`
	Energy       int     `json:"energy"`
	Anxiety      int     `json:"anxiety"`
	Irritability int     `json:"irritability"`
	Note         string  `json:"note"`
	OccurredAt   string  `json:"occurred_at"`
}

type diaryEntryRequest struct {
	Mood                    string `json:"mood"`
	Title                   string `json:"title"`
	Note                    string `json:"note"`
	SharedWithProfessionals bool   `json:"shared_with_professionals"`
	OccurredAt              string `json:"occurred_at"`
}

type medicationRequest struct {
	Name           string `json:"name"`
	Dosage         string `json:"dosage"`
	Form           string `json:"form"`
	ReminderTime   string `json:"reminder_time"`
	RelationToMeal string `json:"relation_to_meal"`
	CurrentStock   int    `json:"current_stock"`
	AlertBelow     int    `json:"alert_below"`
	Source         string `json:"source"`
}

type medicationLogRequest struct {
	MedicationID   string `json:"medication_id"`
	MedicationName string `json:"medication_name"`
	Status         string `json:"status"`
	TakenAt        string `json:"taken_at"`
}

type privacyConsentRequest struct {
	ProfessionalID   string `json:"professional_id"`
	ShareScreenings  bool   `json:"share_screenings"`
	ShareMoodDiary   bool   `json:"share_mood_diary"`
	ShareMedications bool   `json:"share_medications"`
	ShareTimeline    bool   `json:"share_timeline"`
}

type diaryFeedbackRequest struct {
	PatientID string `json:"patient_id"`
	Feedback  string `json:"feedback"`
}

const refreshSessionTTL = 30 * 24 * time.Hour

func New(cfg config.Config, authManager auth.Manager, st *store.Store, hub *realtime.Hub, logger *slog.Logger) *Server {
	return &Server{
		cfg:    cfg,
		auth:   authManager,
		store:  st,
		hub:    hub,
		logger: logger,
		limits: newRateLimiter(20, time.Minute),
	}
}

func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /", s.root)
	mux.HandleFunc("GET /healthz", s.health)
	mux.HandleFunc("POST /v1/auth/register", s.rateLimit(s.register))
	mux.HandleFunc("POST /v1/auth/login", s.rateLimit(s.login))
	mux.HandleFunc("POST /v1/auth/refresh", s.rateLimit(s.refresh))
	mux.HandleFunc("POST /v1/auth/logout", s.rateLimit(s.logout))
	mux.HandleFunc("GET /v1/me", s.requireAuth(s.me))
	mux.HandleFunc("POST /v1/device-tokens", s.requireAuth(s.upsertDeviceToken))
	mux.HandleFunc("POST /v1/screenings", s.requireAuth(s.createScreening))
	mux.HandleFunc("GET /v1/screenings", s.requireAuth(s.listScreenings))
	mux.HandleFunc("POST /v1/screenings/{screening_id}/review", s.requireAuth(s.reviewScreening))
	mux.HandleFunc("GET /v1/screening-reviews", s.requireAuth(s.listScreeningReviews))
	mux.HandleFunc("GET /v1/patient-professional-links", s.requireAuth(s.listPatientProfessionalLinks))
	mux.HandleFunc("POST /v1/patient-professional-links", s.requireAuth(s.linkPatientToProfessional))
	mux.HandleFunc("GET /v1/professional-notes", s.requireAuth(s.listProfessionalNotes))
	mux.HandleFunc("POST /v1/professional-notes", s.requireAuth(s.createProfessionalNote))
	mux.HandleFunc("GET /v1/follow-ups", s.requireAuth(s.listFollowUps))
	mux.HandleFunc("POST /v1/follow-ups", s.requireAuth(s.createFollowUp))
	mux.HandleFunc("PATCH /v1/follow-ups/{follow_up_id}/read", s.requireAuth(s.markFollowUpRead))
	mux.HandleFunc("GET /v1/mood-checkins", s.requireAuth(s.listMoodCheckins))
	mux.HandleFunc("POST /v1/mood-checkins", s.requireAuth(s.createMoodCheckin))
	mux.HandleFunc("GET /v1/diary-entries", s.requireAuth(s.listDiaryEntries))
	mux.HandleFunc("POST /v1/diary-entries", s.requireAuth(s.createDiaryEntry))
	mux.HandleFunc("PATCH /v1/diary-entries/{diary_id}/feedback", s.requireAuth(s.updateDiaryFeedback))
	mux.HandleFunc("GET /v1/medications", s.requireAuth(s.listMedications))
	mux.HandleFunc("POST /v1/medications", s.requireAuth(s.createMedication))
	mux.HandleFunc("GET /v1/medication-logs", s.requireAuth(s.listMedicationLogs))
	mux.HandleFunc("POST /v1/medication-logs", s.requireAuth(s.createMedicationLog))
	mux.HandleFunc("GET /v1/timeline", s.requireAuth(s.timeline))
	mux.HandleFunc("GET /v1/audit-logs", s.requireAuth(s.auditLogs))
	mux.HandleFunc("GET /v1/privacy/consents", s.requireAuth(s.getPrivacyConsent))
	mux.HandleFunc("PUT /v1/privacy/consents", s.requireAuth(s.updatePrivacyConsent))
	mux.HandleFunc("GET /v1/notifications", s.requireAuth(s.listNotifications))
	mux.HandleFunc("PATCH /v1/notifications/read-all", s.requireAuth(s.markAllNotificationsRead))
	mux.HandleFunc("PATCH /v1/notifications/{notification_id}/read", s.requireAuth(s.markNotificationRead))
	mux.HandleFunc("POST /v1/notifications/test", s.requireAuth(s.testNotification))
	mux.HandleFunc("GET /v1/realtime/ws", s.realtimeWS)
	mux.HandleFunc("POST /v1/crisis-alerts", s.requireAuth(s.handleCrisisAlert))
	return s.recover(s.securityHeaders(s.cors(mux)))
}

func (s *Server) root(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write([]byte(`<!doctype html>
<html lang="id">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Malva Backend</title>
  <style>
    body {
      margin: 0;
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      color: #13201c;
      background: #f6faf8;
    }
    main {
      max-width: 760px;
      margin: 0 auto;
      padding: 40px 20px;
    }
    h1 { margin: 0 0 8px; font-size: 32px; }
    p { line-height: 1.55; }
    code {
      padding: 2px 6px;
      border-radius: 6px;
      background: #e7f3ee;
    }
    .panel {
      margin-top: 24px;
      padding: 18px;
      border: 1px solid #d8e8e0;
      border-radius: 8px;
      background: #fff;
    }
    .status {
      display: inline-flex;
      align-items: center;
      gap: 8px;
      padding: 6px 10px;
      border-radius: 999px;
      background: #dff7ec;
      color: #0f6b46;
      font-weight: 700;
    }
    ul { padding-left: 20px; }
    a { color: #0f6b46; }
  </style>
</head>
<body>
  <main>
    <span class="status">Backend aktif</span>
    <h1>Malva Go Backend</h1>
    <p>API lokal Malva sedang berjalan. Halaman ini hanya status ringkas; aplikasi Flutter akan memakai endpoint API dan WebSocket di bawah ini.</p>
    <section class="panel">
      <h2>Endpoint utama</h2>
      <ul>
        <li><a href="/healthz"><code>GET /healthz</code></a></li>
        <li><code>POST /v1/auth/register</code></li>
        <li><code>POST /v1/auth/login</code></li>
        <li><code>POST /v1/auth/refresh</code></li>
        <li><code>POST /v1/screenings</code></li>
        <li><code>GET /v1/screenings</code></li>
        <li><code>POST /v1/patient-professional-links</code></li>
        <li><code>GET /v1/realtime/ws</code></li>
      </ul>
    </section>
  </main>
</body>
</html>`))
}

func (s *Server) health(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) register(w http.ResponseWriter, r *http.Request) {
	var req registerRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	role, err := auth.NormalizeRole(req.Role)
	if err != nil || role == "admin" {
		writeError(w, http.StatusBadRequest, errors.New("role must be patient or professional"))
		return
	}
	if len(req.Password) < 8 {
		writeError(w, http.StatusBadRequest, errors.New("password must be at least 8 characters"))
		return
	}
	hash, err := auth.HashPassword(req.Password)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	user, err := s.store.CreateUser(r.Context(), store.CreateUserParams{
		Email:          req.Email,
		PasswordHash:   hash,
		Role:           role,
		DisplayName:    req.DisplayName,
		ProfessionalID: req.ProfessionalID,
	})
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	s.writeAuthResponse(w, r, http.StatusCreated, user)
}

func (s *Server) login(w http.ResponseWriter, r *http.Request) {
	var req loginRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	user, err := s.store.GetUserByEmail(r.Context(), req.Email)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusUnauthorized, errors.New("email or password is invalid"))
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if !auth.CheckPassword(user.PasswordHash, req.Password) {
		writeError(w, http.StatusUnauthorized, errors.New("email or password is invalid"))
		return
	}
	s.writeAuthResponse(w, r, http.StatusOK, user)
}

func (s *Server) refresh(w http.ResponseWriter, r *http.Request) {
	var req refreshTokenRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	oldHash := auth.HashRefreshToken(strings.TrimSpace(req.RefreshToken))
	newRefreshToken, err := auth.GenerateRefreshToken()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	user, err := s.store.RotateRefreshSession(
		r.Context(),
		oldHash,
		auth.HashRefreshToken(newRefreshToken),
		r.UserAgent(),
		clientIP(r),
		refreshSessionTTL,
	)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusUnauthorized, errors.New("refresh token is invalid or expired"))
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	s.writeAuthResponseWithRefreshToken(w, http.StatusOK, user, newRefreshToken)
}

func (s *Server) logout(w http.ResponseWriter, r *http.Request) {
	var req refreshTokenRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := s.store.RevokeRefreshSession(r.Context(), auth.HashRefreshToken(strings.TrimSpace(req.RefreshToken))); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "logged_out"})
}

func (s *Server) me(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	user, err := s.store.GetUserByID(r.Context(), claims.Subject)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusUnauthorized, errors.New("user not found"))
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"user": user})
}

func (s *Server) upsertDeviceToken(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	var req deviceTokenRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := s.store.UpsertDeviceToken(r.Context(), claims.Subject, req.Platform, req.Token); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "saved"})
}

func (s *Server) createScreening(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	var req screeningRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	patientID, err := s.authorizeScreeningPatient(r, claims, req.PatientID)
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	bundle, err := screening.ScoreBundle(req.PHQ9, req.GAD7)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	session, err := s.store.CreateScreeningBundle(r.Context(), store.CreateScreeningParams{
		PatientID:   patientID,
		SubmittedBy: claims.Subject,
		Source:      req.Source,
		IsInitial:   req.IsInitial,
		Bundle:      bundle,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	s.hub.Publish(patientID, realtime.Event{
		Type: "screening.created",
		Data: session,
	})
	if session.CrisisFlag {
		s.notifyProfessionalsForCrisis(r, session)
	}
	writeJSON(w, http.StatusCreated, map[string]any{"screening": session})
}

func (s *Server) listScreenings(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	patientID, err := s.authorizeScreeningPatient(r, claims, r.URL.Query().Get("patient_id"))
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	if claims.Role == "professional" && !s.consentAllows(r, patientID, claims.Subject, "screenings") {
		writeError(w, http.StatusForbidden, errors.New("patient has not shared screening data"))
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	sessions, err := s.store.ListScreeningSessions(r.Context(), patientID, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"screenings": sessions})
}

func (s *Server) reviewScreening(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "professional" {
		writeError(w, http.StatusForbidden, errors.New("only professionals can review screenings"))
		return
	}
	var req screeningReviewRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	req.Status = strings.ToLower(strings.TrimSpace(req.Status))
	if req.Status == "" {
		req.Status = "reviewed"
	}
	req.Note = trimMax(req.Note, 2000)
	if !oneOf(req.Status, "reviewed", "needs_follow_up", "escalated") {
		writeError(w, http.StatusBadRequest, errors.New("invalid review status"))
		return
	}
	review, err := s.store.UpsertScreeningReview(r.Context(), claims.Subject, r.PathValue("screening_id"), req.Status, req.Note)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	s.notifyPatient(r, review.PatientID, "screening_reviewed", "Screening sudah direview", "Profesional Anda sudah mereview screening terbaru.", map[string]string{
		"screening_id": review.ScreeningSessionID,
		"review_id":    review.ID,
	})
	writeJSON(w, http.StatusOK, map[string]any{"review": review})
}

func (s *Server) listScreeningReviews(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	patientID, err := s.authorizePatientAccess(r, claims, r.URL.Query().Get("patient_id"))
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	professionalID := ""
	if claims.Role == "professional" {
		professionalID = claims.Subject
	}
	reviews, err := s.store.ListScreeningReviews(r.Context(), patientID, professionalID, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	_ = s.store.AddAuditLog(r.Context(), claims.Subject, patientID, "screening_reviews.viewed", "screening_review", "", nil)
	writeJSON(w, http.StatusOK, map[string]any{"reviews": reviews})
}

func (s *Server) linkPatientToProfessional(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "patient" {
		writeError(w, http.StatusForbidden, errors.New("only patients can link a professional"))
		return
	}
	var req linkProfessionalRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	link, err := s.store.LinkPatientToProfessional(r.Context(), claims.Subject, req.ProfessionalID)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	notification, err := s.store.CreateNotification(r.Context(), store.Notification{
		UserID: link.ProfessionalID,
		Type:   "patient_linked",
		Title:  "Pasien baru terhubung",
		Body:   "Seorang pasien telah menghubungkan akun Malva dengan Anda.",
		Data: map[string]string{
			"patient_id": claims.Subject,
		},
	})
	if err != nil {
		s.logger.Warn("create link notification failed", "error", err)
	} else if s.hub != nil {
		s.hub.Publish(link.ProfessionalID, realtime.Event{
			Type: "notification.created",
			Data: notification,
		})
	}

	writeJSON(w, http.StatusCreated, map[string]any{"link": link})
}

func (s *Server) listPatientProfessionalLinks(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	links, err := s.store.ListPatientProfessionalLinks(r.Context(), claims.Subject, claims.Role)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"links": links})
}

func (s *Server) createProfessionalNote(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "professional" {
		writeError(w, http.StatusForbidden, errors.New("only professionals can create notes"))
		return
	}
	var req professionalNoteRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	req.Body = trimMax(req.Body, 4000)
	req.Visibility = strings.ToLower(strings.TrimSpace(req.Visibility))
	if req.Visibility == "" {
		req.Visibility = "private"
	}
	if !oneOf(req.Visibility, "private", "shared_with_patient") {
		writeError(w, http.StatusBadRequest, errors.New("invalid note visibility"))
		return
	}
	note, err := s.store.CreateProfessionalNote(r.Context(), claims.Subject, req.PatientID, req.Body, req.Visibility)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if note.Visibility == "shared_with_patient" {
		s.notifyPatient(r, note.PatientID, "professional_note_shared", "Ada catatan profesional", "Profesional Anda membagikan catatan baru di Malva.", map[string]string{"note_id": note.ID})
	}
	writeJSON(w, http.StatusCreated, map[string]any{"note": note})
}

func (s *Server) listProfessionalNotes(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	patientID, err := s.authorizePatientAccess(r, claims, r.URL.Query().Get("patient_id"))
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	professionalID := r.URL.Query().Get("professional_id")
	if claims.Role == "professional" {
		professionalID = claims.Subject
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	notes, err := s.store.ListProfessionalNotes(r.Context(), patientID, professionalID, claims.Role, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	_ = s.store.AddAuditLog(r.Context(), claims.Subject, patientID, "professional_notes.viewed", "professional_note", "", nil)
	writeJSON(w, http.StatusOK, map[string]any{"notes": notes})
}

func (s *Server) createFollowUp(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "professional" {
		writeError(w, http.StatusForbidden, errors.New("only professionals can create follow-up messages"))
		return
	}
	var req followUpRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	req.Body = trimMax(req.Body, 2500)
	req.Status = strings.ToLower(strings.TrimSpace(req.Status))
	if req.Status == "" {
		req.Status = "sent"
	}
	if !oneOf(req.Status, "draft", "sent") {
		writeError(w, http.StatusBadRequest, errors.New("invalid follow-up status"))
		return
	}
	message, err := s.store.CreateFollowUpMessage(r.Context(), claims.Subject, req.PatientID, req.Body, req.Status)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if message.Status == "sent" {
		s.notifyPatient(r, message.PatientID, "follow_up_created", "Ada follow-up dari profesional", "Buka Malva untuk membaca arahan terbaru.", map[string]string{"follow_up_id": message.ID})
	}
	writeJSON(w, http.StatusCreated, map[string]any{"follow_up": message})
}

func (s *Server) listFollowUps(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	patientID, err := s.authorizePatientAccess(r, claims, r.URL.Query().Get("patient_id"))
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	professionalID := ""
	if claims.Role == "professional" {
		professionalID = claims.Subject
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	messages, err := s.store.ListFollowUpMessages(r.Context(), patientID, professionalID, claims.Role, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, fmt.Errorf("list follow-ups failed: %w", err))
		return
	}
	_ = s.store.AddAuditLog(r.Context(), claims.Subject, patientID, "follow_ups.viewed", "follow_up_message", "", nil)
	writeJSON(w, http.StatusOK, map[string]any{"follow_ups": messages})
}

func (s *Server) markFollowUpRead(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "patient" {
		writeError(w, http.StatusForbidden, errors.New("only patients can mark follow-ups as read"))
		return
	}
	message, err := s.store.MarkFollowUpRead(r.Context(), claims.Subject, r.PathValue("follow_up_id"))
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"follow_up": message})
}

func (s *Server) createMoodCheckin(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "patient" {
		writeError(w, http.StatusForbidden, errors.New("only patients can create mood check-ins"))
		return
	}
	var req moodCheckinRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	req.Mood = strings.ToLower(strings.TrimSpace(req.Mood))
	req.Note = trimMax(req.Note, 2000)
	if !oneOf(req.Mood, "great", "good", "okay", "sad", "awful") {
		writeError(w, http.StatusBadRequest, errors.New("invalid mood value"))
		return
	}
	if req.SleepHours < 0 || req.SleepHours > 24 ||
		req.Energy < 0 || req.Energy > 10 ||
		req.Anxiety < 0 || req.Anxiety > 10 ||
		req.Irritability < 0 || req.Irritability > 10 {
		writeError(w, http.StatusBadRequest, errors.New("mood metric is out of range"))
		return
	}
	item, err := s.store.UpsertMoodCheckin(r.Context(), store.MoodCheckin{
		PatientID:    claims.Subject,
		Mood:         req.Mood,
		SleepHours:   req.SleepHours,
		Energy:       req.Energy,
		Anxiety:      req.Anxiety,
		Irritability: req.Irritability,
		Note:         req.Note,
		OccurredAt:   parseOptionalTime(req.OccurredAt),
	})
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"mood": item})
}

func (s *Server) listMoodCheckins(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	patientID, err := s.authorizePatientAccess(r, claims, r.URL.Query().Get("patient_id"))
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	if claims.Role == "professional" && !s.consentAllows(r, patientID, claims.Subject, "mood_diary") {
		writeError(w, http.StatusForbidden, errors.New("patient has not shared mood/diary data"))
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	items, err := s.store.ListMoodCheckins(r.Context(), patientID, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"moods": items})
}

func (s *Server) createDiaryEntry(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "patient" {
		writeError(w, http.StatusForbidden, errors.New("only patients can create diary entries"))
		return
	}
	var req diaryEntryRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	req.Mood = strings.ToLower(strings.TrimSpace(req.Mood))
	req.Title = trimMax(req.Title, 160)
	req.Note = trimMax(req.Note, 6000)
	if req.Mood != "" && !oneOf(req.Mood, "great", "good", "okay", "sad", "awful") {
		writeError(w, http.StatusBadRequest, errors.New("invalid diary mood value"))
		return
	}
	item, err := s.store.UpsertDiaryEntry(r.Context(), store.DiaryEntry{
		PatientID:               claims.Subject,
		Mood:                    req.Mood,
		Title:                   req.Title,
		Note:                    req.Note,
		SharedWithProfessionals: req.SharedWithProfessionals,
		OccurredAt:              parseOptionalTime(req.OccurredAt),
	})
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"diary": item})
}

func (s *Server) listDiaryEntries(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	patientID, err := s.authorizePatientAccess(r, claims, r.URL.Query().Get("patient_id"))
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	if claims.Role == "professional" && !s.consentAllows(r, patientID, claims.Subject, "mood_diary") {
		writeError(w, http.StatusForbidden, errors.New("patient has not shared mood/diary data"))
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	items, err := s.store.ListDiaryEntries(r.Context(), patientID, claims.Role == "professional", limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"diaries": items})
}

func (s *Server) updateDiaryFeedback(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "professional" {
		writeError(w, http.StatusForbidden, errors.New("only professionals can update diary feedback"))
		return
	}
	var req diaryFeedbackRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	req.Feedback = trimMax(req.Feedback, 2000)
	patientID, err := s.authorizePatientAccess(r, claims, req.PatientID)
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	if !s.consentAllows(r, patientID, claims.Subject, "mood_diary") {
		writeError(w, http.StatusForbidden, errors.New("patient has not shared mood/diary data"))
		return
	}
	entry, err := s.store.UpdateDiaryFeedback(r.Context(), claims.Subject, patientID, r.PathValue("diary_id"), req.Feedback)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	s.notifyPatient(r, patientID, "diary_feedback_updated", "Diary sudah direview", "Profesional Anda memberikan feedback pada diary.", map[string]string{"diary_id": entry.ID})
	writeJSON(w, http.StatusOK, map[string]any{"diary": entry})
}

func (s *Server) createMedication(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "patient" {
		writeError(w, http.StatusForbidden, errors.New("only patients can create medications"))
		return
	}
	var req medicationRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	req.Name = trimMax(req.Name, 160)
	req.Dosage = trimMax(req.Dosage, 80)
	req.Form = trimMax(req.Form, 80)
	req.ReminderTime = trimMax(req.ReminderTime, 16)
	req.RelationToMeal = trimMax(req.RelationToMeal, 80)
	req.Source = trimMax(req.Source, 80)
	if req.CurrentStock < 0 || req.AlertBelow < 0 {
		writeError(w, http.StatusBadRequest, errors.New("medication stock values cannot be negative"))
		return
	}
	item, err := s.store.UpsertMedication(r.Context(), store.Medication{
		PatientID:      claims.Subject,
		Name:           req.Name,
		Dosage:         req.Dosage,
		Form:           req.Form,
		ReminderTime:   req.ReminderTime,
		RelationToMeal: req.RelationToMeal,
		CurrentStock:   req.CurrentStock,
		AlertBelow:     req.AlertBelow,
		Source:         req.Source,
	})
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"medication": item})
}

func (s *Server) listMedications(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	patientID, err := s.authorizePatientAccess(r, claims, r.URL.Query().Get("patient_id"))
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	if claims.Role == "professional" && !s.consentAllows(r, patientID, claims.Subject, "medications") {
		writeError(w, http.StatusForbidden, errors.New("patient has not shared medication data"))
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	items, err := s.store.ListMedications(r.Context(), patientID, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"medications": items})
}

func (s *Server) createMedicationLog(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "patient" {
		writeError(w, http.StatusForbidden, errors.New("only patients can create medication logs"))
		return
	}
	var req medicationLogRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	req.MedicationName = trimMax(req.MedicationName, 160)
	req.Status = strings.ToLower(strings.TrimSpace(req.Status))
	if req.Status == "" {
		req.Status = "taken"
	}
	if !oneOf(req.Status, "taken", "skipped", "missed") {
		writeError(w, http.StatusBadRequest, errors.New("invalid medication log status"))
		return
	}
	item, err := s.store.CreateMedicationLog(r.Context(), store.MedicationLog{
		PatientID:      claims.Subject,
		MedicationID:   req.MedicationID,
		MedicationName: req.MedicationName,
		Status:         req.Status,
		TakenAt:        parseOptionalTime(req.TakenAt),
	})
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"medication_log": item})
}

func (s *Server) listMedicationLogs(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	patientID, err := s.authorizePatientAccess(r, claims, r.URL.Query().Get("patient_id"))
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	if claims.Role == "professional" && !s.consentAllows(r, patientID, claims.Subject, "medications") {
		writeError(w, http.StatusForbidden, errors.New("patient has not shared medication data"))
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	items, err := s.store.ListMedicationLogs(r.Context(), patientID, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"medication_logs": items})
}

func (s *Server) timeline(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	patientID, err := s.authorizePatientAccess(r, claims, r.URL.Query().Get("patient_id"))
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	if claims.Role == "professional" && !s.consentAllows(r, patientID, claims.Subject, "timeline") {
		writeError(w, http.StatusForbidden, errors.New("patient has not shared timeline data"))
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	events, err := s.store.ListTimelineEvents(r.Context(), patientID, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	_ = s.store.AddAuditLog(r.Context(), claims.Subject, patientID, "timeline.viewed", "timeline", "", nil)
	writeJSON(w, http.StatusOK, map[string]any{"events": events})
}

func (s *Server) auditLogs(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	patientID, err := s.authorizePatientAccess(r, claims, r.URL.Query().Get("patient_id"))
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	logs, err := s.store.ListAuditLogs(r.Context(), patientID, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"audit_logs": logs})
}

func (s *Server) getPrivacyConsent(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "patient" {
		writeError(w, http.StatusForbidden, errors.New("only patients can view privacy consent settings"))
		return
	}
	professionalID := r.URL.Query().Get("professional_id")
	if professionalID == "" {
		writeError(w, http.StatusBadRequest, errors.New("professional_id is required"))
		return
	}
	consent, err := s.store.GetPatientDataConsent(r.Context(), claims.Subject, professionalID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"consent": consent})
}

func (s *Server) updatePrivacyConsent(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "patient" {
		writeError(w, http.StatusForbidden, errors.New("only patients can update privacy consent settings"))
		return
	}
	var req privacyConsentRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	consent, err := s.store.UpdatePatientDataConsent(r.Context(), store.PatientDataConsent{
		PatientID:        claims.Subject,
		ProfessionalID:   req.ProfessionalID,
		ShareScreenings:  req.ShareScreenings,
		ShareMoodDiary:   req.ShareMoodDiary,
		ShareMedications: req.ShareMedications,
		ShareTimeline:    req.ShareTimeline,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"consent": consent})
}

func (s *Server) listNotifications(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	limit, _ := strconv.Atoi(r.URL.Query().Get("limit"))
	items, err := s.store.ListNotifications(r.Context(), claims.Subject, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"notifications": items})
}

func (s *Server) markNotificationRead(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	item, err := s.store.MarkNotificationRead(r.Context(), claims.Subject, r.PathValue("notification_id"))
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"notification": item})
}

func (s *Server) markAllNotificationsRead(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	count, err := s.store.MarkAllNotificationsRead(r.Context(), claims.Subject)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"updated": count})
}

func (s *Server) testNotification(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	notification, err := s.store.CreateNotification(r.Context(), store.Notification{
		UserID: claims.Subject,
		Type:   "test",
		Title:  "Malva",
		Body:   "Ada pembaruan di Malva. Buka aplikasi untuk melihat detail.",
		Data: map[string]string{
			"kind": "test",
		},
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	s.hub.Publish(claims.Subject, realtime.Event{
		Type: "notification.created",
		Data: notification,
	})
	writeJSON(w, http.StatusCreated, map[string]any{"notification": notification})
}

func (s *Server) handleCrisisAlert(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	var req struct {
		PatientName string `json:"patient_name"`
		Message     string `json:"message"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	crisisEvent := map[string]interface{}{
		"type": "crisis_alert",
		"data": map[string]interface{}{
			"patient_name": req.PatientName,
			"message":      req.Message,
			"timestamp":    time.Now().UTC().Format(time.RFC3339),
		},
	}

	s.hub.Broadcast(crisisEvent)

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"status":  "sent",
		"message": "Crisis alert dikirim ke profesional",
	})
}

func (s *Server) realtimeWS(w http.ResponseWriter, r *http.Request) {
	claims, err := s.claimsFromRequest(r)
	if err != nil {
		writeError(w, http.StatusUnauthorized, err)
		return
	}
	s.hub.ServeWS(w, r, claims.Subject)
}

func (s *Server) authorizeScreeningPatient(r *http.Request, claims auth.Claims, requestedPatientID string) (string, error) {
	switch claims.Role {
	case "patient":
		if requestedPatientID != "" && requestedPatientID != claims.Subject {
			return "", errors.New("patients can only submit their own screening")
		}
		return claims.Subject, nil
	case "professional":
		if requestedPatientID == "" {
			return "", errors.New("patient_id is required for professional submissions")
		}
		linked, err := s.store.ProfessionalLinkedToPatient(r.Context(), claims.Subject, requestedPatientID)
		if err != nil {
			return "", err
		}
		if !linked {
			return "", errors.New("professional is not linked to this patient")
		}
		return requestedPatientID, nil
	case "admin":
		if requestedPatientID == "" {
			return "", errors.New("patient_id is required")
		}
		return requestedPatientID, nil
	default:
		return "", errors.New("role is not allowed")
	}
}

func (s *Server) authorizePatientAccess(r *http.Request, claims auth.Claims, requestedPatientID string) (string, error) {
	switch claims.Role {
	case "patient":
		if requestedPatientID != "" && requestedPatientID != claims.Subject {
			return "", errors.New("patients can only access their own data")
		}
		return claims.Subject, nil
	case "professional":
		if requestedPatientID == "" {
			return "", errors.New("patient_id is required for professional access")
		}
		linked, err := s.store.ProfessionalLinkedToPatient(r.Context(), claims.Subject, requestedPatientID)
		if err != nil {
			return "", err
		}
		if !linked {
			return "", errors.New("professional is not linked to this patient")
		}
		return requestedPatientID, nil
	default:
		return "", errors.New("role is not allowed")
	}
}

func (s *Server) consentAllows(r *http.Request, patientID, professionalID, scope string) bool {
	consent, err := s.store.GetPatientDataConsent(r.Context(), patientID, professionalID)
	if err != nil {
		s.logger.Warn("load patient consent failed", "error", err)
		return false
	}
	switch scope {
	case "screenings":
		return consent.ShareScreenings
	case "mood_diary":
		return consent.ShareMoodDiary
	case "medications":
		return consent.ShareMedications
	case "timeline":
		return consent.ShareTimeline
	default:
		return false
	}
}

func (s *Server) notifyProfessionalsForCrisis(r *http.Request, session store.ScreeningSession) {
	professionalIDs, err := s.store.ListProfessionalsForPatient(r.Context(), session.PatientID)
	if err != nil {
		s.logger.Warn("list professionals for crisis notification failed", "error", err)
		return
	}
	for _, professionalID := range professionalIDs {
		notification, err := s.store.CreateNotification(r.Context(), store.Notification{
			UserID: professionalID,
			Type:   "screening_crisis",
			Title:  "Ada hasil screening prioritas",
			Body:   "Buka Malva untuk meninjau pembaruan pasien.",
			Data: map[string]string{
				"screening_id": session.ID,
				"patient_id":   session.PatientID,
			},
		})
		if err != nil {
			s.logger.Warn("create crisis notification failed", "error", err)
			continue
		}
		s.hub.Publish(professionalID, realtime.Event{
			Type: "notification.created",
			Data: notification,
		})
	}
}

func (s *Server) notifyPatient(r *http.Request, patientID, kind, title, body string, data map[string]string) {
	if data == nil {
		data = map[string]string{}
	}
	data["kind"] = kind
	notification, err := s.store.CreateNotification(r.Context(), store.Notification{
		UserID: patientID,
		Type:   kind,
		Title:  title,
		Body:   body,
		Data:   data,
	})
	if err != nil {
		s.logger.Warn("create patient notification failed", "error", err, "kind", kind)
		return
	}
	if s.hub != nil {
		s.hub.Publish(patientID, realtime.Event{
			Type: "notification.created",
			Data: notification,
		})
	}
}

func (s *Server) writeAuthResponse(w http.ResponseWriter, r *http.Request, status int, user store.User) {
	refreshToken, err := auth.GenerateRefreshToken()
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if err := s.store.CreateRefreshSession(
		r.Context(),
		user.ID,
		auth.HashRefreshToken(refreshToken),
		r.UserAgent(),
		clientIP(r),
		refreshSessionTTL,
	); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	s.writeAuthResponseWithRefreshToken(w, status, user, refreshToken)
}

func (s *Server) writeAuthResponseWithRefreshToken(w http.ResponseWriter, status int, user store.User, refreshToken string) {
	token, err := s.auth.Issue(user.ID, user.Role)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, status, map[string]any{
		"user":          user,
		"access_token":  token,
		"refresh_token": refreshToken,
		"token_type":    "Bearer",
		"expires_in":    int((24 * time.Hour).Seconds()),
	})
}

type authedHandler func(http.ResponseWriter, *http.Request, auth.Claims)

func (s *Server) requireAuth(next authedHandler) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		claims, err := s.claimsFromRequest(r)
		if err != nil {
			writeError(w, http.StatusUnauthorized, err)
			return
		}
		next(w, r, claims)
	}
}

func (s *Server) claimsFromRequest(r *http.Request) (auth.Claims, error) {
	if token := r.URL.Query().Get("access_token"); token != "" {
		return s.auth.Verify(token)
	}
	return s.auth.BearerClaims(r.Header.Get("Authorization"))
}

func (s *Server) cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if s.cfg.OriginAllowed(origin) {
			w.Header().Set("Vary", "Origin")
			w.Header().Set("Access-Control-Allow-Origin", origin)
			w.Header().Set("Access-Control-Allow-Headers", "Authorization, Content-Type")
			w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, OPTIONS")
		}
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func (s *Server) securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("X-Content-Type-Options", "nosniff")
		w.Header().Set("X-Frame-Options", "DENY")
		w.Header().Set("Referrer-Policy", "no-referrer")
		w.Header().Set("Content-Security-Policy", "default-src 'self'; style-src 'self' 'unsafe-inline'")
		next.ServeHTTP(w, r)
	})
}

func (s *Server) rateLimit(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		key := clientIP(r) + ":" + r.URL.Path
		if !s.limits.allow(key) {
			writeError(w, http.StatusTooManyRequests, errors.New("terlalu banyak percobaan, coba lagi sebentar"))
			return
		}
		next(w, r)
	}
}

func (s *Server) recover(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if recovered := recover(); recovered != nil {
				s.logger.Error("panic recovered", "value", recovered)
				writeError(w, http.StatusInternalServerError, errors.New("internal server error"))
			}
		}()
		next.ServeHTTP(w, r)
	})
}

type rateLimiter struct {
	mu     sync.Mutex
	limit  int
	window time.Duration
	hits   map[string]rateWindow
}

type rateWindow struct {
	start time.Time
	count int
}

func newRateLimiter(limit int, window time.Duration) *rateLimiter {
	return &rateLimiter{
		limit:  limit,
		window: window,
		hits:   map[string]rateWindow{},
	}
}

func (l *rateLimiter) allow(key string) bool {
	now := time.Now()
	l.mu.Lock()
	defer l.mu.Unlock()

	current := l.hits[key]
	if current.start.IsZero() || now.Sub(current.start) > l.window {
		l.hits[key] = rateWindow{start: now, count: 1}
		l.prune(now)
		return true
	}
	if current.count >= l.limit {
		return false
	}
	current.count++
	l.hits[key] = current
	return true
}

func (l *rateLimiter) prune(now time.Time) {
	for key, window := range l.hits {
		if now.Sub(window.start) > 2*l.window {
			delete(l.hits, key)
		}
	}
}

func clientIP(r *http.Request) string {
	if forwarded := r.Header.Get("X-Forwarded-For"); forwarded != "" {
		first, _, _ := strings.Cut(forwarded, ",")
		return strings.TrimSpace(first)
	}
	host, _, err := net.SplitHostPort(r.RemoteAddr)
	if err != nil {
		return r.RemoteAddr
	}
	return host
}

func parseOptionalTime(value string) time.Time {
	value = strings.TrimSpace(value)
	if value == "" {
		return time.Time{}
	}
	parsed, err := time.Parse(time.RFC3339, value)
	if err != nil {
		return time.Time{}
	}
	return parsed
}

func trimMax(value string, max int) string {
	value = strings.TrimSpace(value)
	if len(value) <= max {
		return value
	}
	return value[:max]
}

func oneOf(value string, allowed ...string) bool {
	for _, item := range allowed {
		if value == item {
			return true
		}
	}
	return false
}

func readJSON(r *http.Request, target any) error {
	defer r.Body.Close()
	decoder := json.NewDecoder(http.MaxBytesReader(nil, r.Body, 1<<20))
	decoder.DisallowUnknownFields()
	return decoder.Decode(target)
}

func writeJSON(w http.ResponseWriter, status int, value any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(value)
}

func writeError(w http.ResponseWriter, status int, err error) {
	message := strings.TrimSpace(err.Error())
	if message == "" {
		message = http.StatusText(status)
	}
	writeJSON(w, status, map[string]string{"error": message})
}
