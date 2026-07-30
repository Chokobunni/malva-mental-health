package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	"malva/backend/internal/screening"
)

type Store struct {
	db *sql.DB
}

type User struct {
	ID           string `json:"id"`
	Email        string `json:"email"`
	Role         string `json:"role"`
	DisplayName  string `json:"display_name"`
	PasswordHash string `json:"-"`
}

type CreateUserParams struct {
	Email          string
	PasswordHash   string
	Role           string
	DisplayName    string
	ProfessionalID string
}

type PatientProfessionalLink struct {
	PatientID               string    `json:"patient_id"`
	ProfessionalID          string    `json:"professional_user_id"`
	ProfessionalCode        string    `json:"professional_id"`
	PatientDisplayName      string    `json:"patient_display_name"`
	ProfessionalDisplayName string    `json:"professional_display_name"`
	Status                  string    `json:"status"`
	CreatedAt               time.Time `json:"created_at"`
}

type ScreeningSession struct {
	ID           string           `json:"id"`
	PatientID    string           `json:"patient_id"`
	SubmittedBy  string           `json:"submitted_by"`
	Source       string           `json:"source"`
	IsInitial    bool             `json:"is_initial"`
	RuleVersion  string           `json:"rule_version"`
	OverallLevel string           `json:"overall_level"`
	CrisisFlag   bool             `json:"crisis_flag"`
	CreatedAt    time.Time        `json:"created_at"`
	Bundle       screening.Bundle `json:"bundle"`
}

type CreateScreeningParams struct {
	PatientID   string
	SubmittedBy string
	Source      string
	IsInitial   bool
	Bundle      screening.Bundle
}

type Notification struct {
	ID        string            `json:"id"`
	UserID    string            `json:"user_id"`
	Type      string            `json:"type"`
	Title     string            `json:"title"`
	Body      string            `json:"body"`
	Data      map[string]string `json:"data"`
	Status    string            `json:"status"`
	CreatedAt time.Time         `json:"created_at"`
	SentAt    *time.Time        `json:"sent_at,omitempty"`
	ReadAt    *time.Time        `json:"read_at,omitempty"`
}

type OutboxJob struct {
	ID             string
	NotificationID string
	UserID         string
	Title          string
	Body           string
	Data           map[string]string
	Attempts       int
}

type ScreeningReview struct {
	ID                 string    `json:"id"`
	ScreeningSessionID string    `json:"screening_session_id"`
	PatientID          string    `json:"patient_id"`
	ProfessionalID     string    `json:"professional_id"`
	Status             string    `json:"status"`
	Note               string    `json:"note"`
	CreatedAt          time.Time `json:"created_at"`
	UpdatedAt          time.Time `json:"updated_at"`
}

type ProfessionalNote struct {
	ID             string    `json:"id"`
	PatientID      string    `json:"patient_id"`
	ProfessionalID string    `json:"professional_id"`
	Body           string    `json:"body"`
	Visibility     string    `json:"visibility"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

type FollowUpMessage struct {
	ID             string     `json:"id"`
	PatientID      string     `json:"patient_id"`
	ProfessionalID string     `json:"professional_id"`
	Body           string     `json:"body"`
	Status         string     `json:"status"`
	CreatedAt      time.Time  `json:"created_at"`
	UpdatedAt      time.Time  `json:"updated_at"`
	ReadAt         *time.Time `json:"read_at,omitempty"`
}

type MoodCheckin struct {
	ID           string    `json:"id"`
	PatientID    string    `json:"patient_id"`
	Mood         string    `json:"mood"`
	SleepHours   float64   `json:"sleep_hours"`
	Energy       int       `json:"energy"`
	Anxiety      int       `json:"anxiety"`
	Irritability int       `json:"irritability"`
	Note         string    `json:"note"`
	OccurredAt   time.Time `json:"occurred_at"`
	CreatedAt    time.Time `json:"created_at"`
}

type DiaryEntry struct {
	ID                      string    `json:"id"`
	PatientID               string    `json:"patient_id"`
	Mood                    string    `json:"mood"`
	Title                   string    `json:"title"`
	Note                    string    `json:"note"`
	SharedWithProfessionals bool      `json:"shared_with_professionals"`
	ProfessionalFeedback    string    `json:"professional_feedback,omitempty"`
	OccurredAt              time.Time `json:"occurred_at"`
	CreatedAt               time.Time `json:"created_at"`
	UpdatedAt               time.Time `json:"updated_at"`
}

type Medication struct {
	ID             string    `json:"id"`
	PatientID      string    `json:"patient_id"`
	Name           string    `json:"name"`
	Dosage         string    `json:"dosage"`
	Form           string    `json:"form"`
	ReminderTime   string    `json:"reminder_time"`
	RelationToMeal string    `json:"relation_to_meal"`
	CurrentStock   int       `json:"current_stock"`
	AlertBelow     int       `json:"alert_below"`
	Source         string    `json:"source"`
	Active         bool      `json:"active"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

type MedicationLog struct {
	ID             string    `json:"id"`
	PatientID      string    `json:"patient_id"`
	MedicationID   string    `json:"medication_id,omitempty"`
	MedicationName string    `json:"medication_name"`
	Status         string    `json:"status"`
	TakenAt        time.Time `json:"taken_at"`
	CreatedAt      time.Time `json:"created_at"`
}

type PatientDataConsent struct {
	PatientID        string    `json:"patient_id"`
	ProfessionalID   string    `json:"professional_id"`
	ShareScreenings  bool      `json:"share_screenings"`
	ShareMoodDiary   bool      `json:"share_mood_diary"`
	ShareMedications bool      `json:"share_medications"`
	ShareTimeline    bool      `json:"share_timeline"`
	UpdatedAt        time.Time `json:"updated_at"`
}

type TimelineEvent struct {
	ID        string         `json:"id"`
	PatientID string         `json:"patient_id"`
	Type      string         `json:"type"`
	Title     string         `json:"title"`
	Body      string         `json:"body"`
	Metadata  map[string]any `json:"metadata"`
	CreatedAt time.Time      `json:"created_at"`
}

type AuditLog struct {
	ID         string         `json:"id"`
	ActorID    string         `json:"actor_id,omitempty"`
	PatientID  string         `json:"patient_id,omitempty"`
	Action     string         `json:"action"`
	EntityType string         `json:"entity_type"`
	EntityID   string         `json:"entity_id,omitempty"`
	Metadata   map[string]any `json:"metadata"`
	CreatedAt  time.Time      `json:"created_at"`
}

func New(db *sql.DB) *Store {
	return &Store{db: db}
}

func (s *Store) CreateUser(ctx context.Context, params CreateUserParams) (User, error) {
	role := strings.ToLower(strings.TrimSpace(params.Role))
	email := strings.ToLower(strings.TrimSpace(params.Email))
	displayName := strings.TrimSpace(params.DisplayName)
	if email == "" || displayName == "" || params.PasswordHash == "" {
		return User{}, errors.New("email, display_name, and password_hash are required")
	}
	if role != "patient" && role != "professional" {
		return User{}, errors.New("role must be patient or professional")
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return User{}, err
	}
	defer tx.Rollback()

	var user User
	err = tx.QueryRowContext(ctx, `
		INSERT INTO users (email, password_hash, role, display_name)
		VALUES ($1, $2, $3::user_role, $4)
		RETURNING id, email, role::text, display_name, password_hash
	`, email, params.PasswordHash, role, displayName).
		Scan(&user.ID, &user.Email, &user.Role, &user.DisplayName, &user.PasswordHash)
	if err != nil {
		return User{}, err
	}

	switch role {
	case "patient":
		_, err = tx.ExecContext(ctx, `INSERT INTO patient_profiles (user_id) VALUES ($1)`, user.ID)
	case "professional":
		professionalID := strings.TrimSpace(params.ProfessionalID)
		if professionalID == "" {
			return User{}, errors.New("professional_id is required for professional accounts")
		}
		_, err = tx.ExecContext(ctx, `
			INSERT INTO professional_profiles (user_id, professional_id)
			VALUES ($1, $2)
		`, user.ID, professionalID)
	}
	if err != nil {
		return User{}, err
	}

	_, err = tx.ExecContext(ctx, `
		INSERT INTO audit_logs (actor_id, action, entity_type, entity_id)
		VALUES ($1, 'user.registered', 'user', $1)
	`, user.ID)
	if err != nil {
		return User{}, err
	}

	if err := tx.Commit(); err != nil {
		return User{}, err
	}
	return user, nil
}

func (s *Store) GetUserByEmail(ctx context.Context, email string) (User, error) {
	var user User
	err := s.db.QueryRowContext(ctx, `
		SELECT id, email, role::text, display_name, password_hash
		FROM users
		WHERE email = $1 AND disabled_at IS NULL
	`, strings.ToLower(strings.TrimSpace(email))).
		Scan(&user.ID, &user.Email, &user.Role, &user.DisplayName, &user.PasswordHash)
	return user, err
}

func (s *Store) GetUserByID(ctx context.Context, id string) (User, error) {
	var user User
	err := s.db.QueryRowContext(ctx, `
		SELECT id, email, role::text, display_name, password_hash
		FROM users
		WHERE id = $1 AND disabled_at IS NULL
	`, id).Scan(&user.ID, &user.Email, &user.Role, &user.DisplayName, &user.PasswordHash)
	return user, err
}

func (s *Store) UpdatePassword(ctx context.Context, userID, passwordHash string) error {
	if userID == "" || passwordHash == "" {
		return errors.New("user_id and password_hash are required")
	}
	_, err := s.db.ExecContext(ctx, `
		UPDATE users
		SET password_hash = $1, updated_at = now()
		WHERE id = $2 AND disabled_at IS NULL
	`, passwordHash, userID)
	return err
}

func (s *Store) CreateRefreshSession(ctx context.Context, userID, refreshTokenHash, userAgent, ipAddress string, ttl time.Duration) error {
	if userID == "" || refreshTokenHash == "" {
		return errors.New("user_id and refresh_token_hash are required")
	}
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO auth_sessions (
			user_id, refresh_token_hash, user_agent, ip_address, expires_at
		)
		VALUES ($1, $2, $3, $4, now() + $5::interval)
	`, userID, refreshTokenHash, strings.TrimSpace(userAgent), strings.TrimSpace(ipAddress), durationInterval(ttl))
	return err
}

func (s *Store) RotateRefreshSession(ctx context.Context, oldHash, newHash, userAgent, ipAddress string, ttl time.Duration) (User, error) {
	if oldHash == "" || newHash == "" {
		return User{}, errors.New("refresh token is required")
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return User{}, err
	}
	defer tx.Rollback()

	var user User
	var sessionID string
	err = tx.QueryRowContext(ctx, `
		SELECT s.id, u.id, u.email, u.role::text, u.display_name, u.password_hash
		FROM auth_sessions s
		JOIN users u ON u.id = s.user_id
		WHERE s.refresh_token_hash = $1
		  AND s.revoked_at IS NULL
		  AND s.expires_at > now()
		  AND u.disabled_at IS NULL
		FOR UPDATE OF s
	`, oldHash).Scan(&sessionID, &user.ID, &user.Email, &user.Role, &user.DisplayName, &user.PasswordHash)
	if err != nil {
		return User{}, err
	}

	_, err = tx.ExecContext(ctx, `
		UPDATE auth_sessions
		SET refresh_token_hash = $2,
		    user_agent = $3,
		    ip_address = $4,
		    last_used_at = now(),
		    expires_at = now() + $5::interval
		WHERE id = $1
	`, sessionID, newHash, strings.TrimSpace(userAgent), strings.TrimSpace(ipAddress), durationInterval(ttl))
	if err != nil {
		return User{}, err
	}

	_, err = tx.ExecContext(ctx, `
		INSERT INTO audit_logs (actor_id, action, entity_type, entity_id)
		VALUES ($1, 'auth.refresh', 'auth_session', $2)
	`, user.ID, sessionID)
	if err != nil {
		return User{}, err
	}

	if err := tx.Commit(); err != nil {
		return User{}, err
	}
	return user, nil
}

func (s *Store) RevokeRefreshSession(ctx context.Context, refreshTokenHash string) error {
	if refreshTokenHash == "" {
		return errors.New("refresh token is required")
	}
	_, err := s.db.ExecContext(ctx, `
		UPDATE auth_sessions
		SET revoked_at = COALESCE(revoked_at, now())
		WHERE refresh_token_hash = $1
	`, refreshTokenHash)
	return err
}

func (s *Store) ProfessionalLinkedToPatient(ctx context.Context, professionalID, patientID string) (bool, error) {
	var exists bool
	err := s.db.QueryRowContext(ctx, `
		SELECT EXISTS (
			SELECT 1
			FROM patient_professional_links
			WHERE professional_id = $1 AND patient_id = $2 AND status = 'active'
		)
	`, professionalID, patientID).Scan(&exists)
	return exists, err
}

func (s *Store) ListProfessionalsForPatient(ctx context.Context, patientID string) ([]string, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT professional_id
		FROM patient_professional_links
		WHERE patient_id = $1 AND status = 'active'
	`, patientID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

func (s *Store) LinkPatientToProfessional(ctx context.Context, patientID, professionalCode string) (PatientProfessionalLink, error) {
	patientID = strings.TrimSpace(patientID)
	professionalCode = strings.TrimSpace(professionalCode)
	if patientID == "" || professionalCode == "" {
		return PatientProfessionalLink{}, errors.New("patient_id and professional_id are required")
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return PatientProfessionalLink{}, err
	}
	defer tx.Rollback()

	var link PatientProfessionalLink
	err = tx.QueryRowContext(ctx, `
		SELECT u.id, u.display_name, pp.professional_id
		FROM users u
		JOIN professional_profiles pp ON pp.user_id = u.id
		WHERE pp.professional_id = $1
		  AND u.role = 'professional'
		  AND u.disabled_at IS NULL
	`, professionalCode).Scan(&link.ProfessionalID, &link.ProfessionalDisplayName, &link.ProfessionalCode)
	if errors.Is(err, sql.ErrNoRows) {
		return PatientProfessionalLink{}, errors.New("professional_id tidak ditemukan")
	}
	if err != nil {
		return PatientProfessionalLink{}, err
	}

	err = tx.QueryRowContext(ctx, `
		SELECT display_name
		FROM users
		WHERE id = $1 AND role = 'patient' AND disabled_at IS NULL
	`, patientID).Scan(&link.PatientDisplayName)
	if errors.Is(err, sql.ErrNoRows) {
		return PatientProfessionalLink{}, errors.New("patient tidak ditemukan")
	}
	if err != nil {
		return PatientProfessionalLink{}, err
	}
	link.PatientID = patientID

	err = tx.QueryRowContext(ctx, `
		INSERT INTO patient_professional_links (patient_id, professional_id, status)
		VALUES ($1, $2, 'active')
		ON CONFLICT (patient_id, professional_id) DO UPDATE
		SET status = 'active'
		RETURNING status, created_at
	`, patientID, link.ProfessionalID).Scan(&link.Status, &link.CreatedAt)
	if err != nil {
		return PatientProfessionalLink{}, err
	}

	metadata, _ := json.Marshal(map[string]any{
		"professional_id":      link.ProfessionalID,
		"professional_code":    link.ProfessionalCode,
		"professional_display": link.ProfessionalDisplayName,
	})
	_, err = tx.ExecContext(ctx, `
		INSERT INTO audit_logs (actor_id, patient_id, action, entity_type, entity_id, metadata)
		VALUES ($1, $1, 'patient_professional.linked', 'professional', $2, $3)
	`, patientID, link.ProfessionalID, metadata)
	if err != nil {
		return PatientProfessionalLink{}, err
	}

	if err := tx.Commit(); err != nil {
		return PatientProfessionalLink{}, err
	}
	return link, nil
}

func (s *Store) ListPatientProfessionalLinks(ctx context.Context, userID, role string) ([]PatientProfessionalLink, error) {
	userID = strings.TrimSpace(userID)
	role = strings.TrimSpace(role)
	if userID == "" {
		return nil, errors.New("user_id is required")
	}

	where := "l.patient_id = $1"
	if role == "professional" {
		where = "l.professional_id = $1"
	} else if role != "patient" {
		return nil, errors.New("role must be patient or professional")
	}

	rows, err := s.db.QueryContext(ctx, `
		SELECT l.patient_id,
		       l.professional_id,
		       pp.professional_id,
		       patient.display_name,
		       professional.display_name,
		       l.status,
		       l.created_at
		FROM patient_professional_links l
		JOIN users patient ON patient.id = l.patient_id
		JOIN users professional ON professional.id = l.professional_id
		JOIN professional_profiles pp ON pp.user_id = l.professional_id
		WHERE `+where+`
		  AND l.status = 'active'
		ORDER BY l.created_at DESC
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	links := make([]PatientProfessionalLink, 0)
	for rows.Next() {
		var link PatientProfessionalLink
		if err := rows.Scan(
			&link.PatientID,
			&link.ProfessionalID,
			&link.ProfessionalCode,
			&link.PatientDisplayName,
			&link.ProfessionalDisplayName,
			&link.Status,
			&link.CreatedAt,
		); err != nil {
			return nil, err
		}
		links = append(links, link)
	}
	return links, rows.Err()
}

func (s *Store) UpsertDeviceToken(ctx context.Context, userID, platform, token string) error {
	platform = strings.ToLower(strings.TrimSpace(platform))
	token = strings.TrimSpace(token)
	if platform == "" || token == "" {
		return errors.New("platform and token are required")
	}
	_, err := s.db.ExecContext(ctx, `
		INSERT INTO device_tokens (user_id, platform, token)
		VALUES ($1, $2, $3)
		ON CONFLICT (token) DO UPDATE
		SET user_id = EXCLUDED.user_id,
		    platform = EXCLUDED.platform,
		    enabled = true,
		    last_seen_at = now()
	`, userID, platform, token)
	return err
}

func (s *Store) CreateScreeningBundle(ctx context.Context, params CreateScreeningParams) (ScreeningSession, error) {
	source := strings.TrimSpace(params.Source)
	if source == "" {
		source = "patient_app"
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return ScreeningSession{}, err
	}
	defer tx.Rollback()

	session := ScreeningSession{
		PatientID:    params.PatientID,
		SubmittedBy:  params.SubmittedBy,
		Source:       source,
		IsInitial:    params.IsInitial,
		RuleVersion:  params.Bundle.RuleVersion,
		OverallLevel: params.Bundle.Overall,
		CrisisFlag:   params.Bundle.CrisisFlag,
		Bundle:       params.Bundle,
	}
	err = tx.QueryRowContext(ctx, `
		INSERT INTO screening_sessions (
			patient_id, submitted_by, source, is_initial, rule_version,
			overall_level, crisis_flag
		)
		VALUES ($1, $2, $3, $4, $5, $6::risk_level, $7)
		RETURNING id, created_at
	`, params.PatientID, params.SubmittedBy, source, params.IsInitial,
		params.Bundle.RuleVersion, params.Bundle.Overall, params.Bundle.CrisisFlag).
		Scan(&session.ID, &session.CreatedAt)
	if err != nil {
		return ScreeningSession{}, err
	}

	if err := insertScreeningResult(ctx, tx, session.ID, params.Bundle.PHQ9); err != nil {
		return ScreeningSession{}, err
	}
	if err := insertScreeningResult(ctx, tx, session.ID, params.Bundle.GAD7); err != nil {
		return ScreeningSession{}, err
	}

	metadata, _ := json.Marshal(map[string]any{
		"overall_level": params.Bundle.Overall,
		"crisis_flag":   params.Bundle.CrisisFlag,
	})
	_, err = tx.ExecContext(ctx, `
		INSERT INTO audit_logs (actor_id, patient_id, action, entity_type, entity_id, metadata)
		VALUES ($1, $2, 'screening.submitted', 'screening_session', $3, $4)
	`, params.SubmittedBy, params.PatientID, session.ID, metadata)
	if err != nil {
		return ScreeningSession{}, err
	}

	if err := tx.Commit(); err != nil {
		return ScreeningSession{}, err
	}
	return session, nil
}

func (s *Store) ListScreeningSessions(ctx context.Context, patientID string, limit int) ([]ScreeningSession, error) {
	patientID = strings.TrimSpace(patientID)
	if patientID == "" {
		return nil, errors.New("patient_id is required")
	}
	limit = normalizeLimit(limit, 20, 100)

	rows, err := s.db.QueryContext(ctx, `
		SELECT id, patient_id, submitted_by, source, is_initial,
		       rule_version, overall_level::text, crisis_flag, created_at
		FROM screening_sessions
		WHERE patient_id = $1
		ORDER BY created_at DESC
		LIMIT $2
	`, patientID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	sessions := make([]ScreeningSession, 0)
	for rows.Next() {
		var session ScreeningSession
		if err := rows.Scan(
			&session.ID,
			&session.PatientID,
			&session.SubmittedBy,
			&session.Source,
			&session.IsInitial,
			&session.RuleVersion,
			&session.OverallLevel,
			&session.CrisisFlag,
			&session.CreatedAt,
		); err != nil {
			return nil, err
		}
		session.Bundle = screening.Bundle{
			Overall:     session.OverallLevel,
			CrisisFlag:  session.CrisisFlag,
			RuleVersion: session.RuleVersion,
		}
		if err := s.loadScreeningResults(ctx, &session); err != nil {
			return nil, err
		}
		sessions = append(sessions, session)
	}
	return sessions, rows.Err()
}

func (s *Store) loadScreeningResults(ctx context.Context, session *ScreeningSession) error {
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, type::text, score, max_score, level::text, summary, crisis_flag
		FROM screening_results
		WHERE session_id = $1
		ORDER BY type
	`, session.ID)
	if err != nil {
		return err
	}
	defer rows.Close()

	for rows.Next() {
		var resultID string
		var result screening.Result
		if err := rows.Scan(
			&resultID,
			&result.Type,
			&result.Score,
			&result.MaxScore,
			&result.Level,
			&result.Summary,
			&result.CrisisFlag,
		); err != nil {
			return err
		}
		answers, err := s.listScreeningAnswers(ctx, resultID)
		if err != nil {
			return err
		}
		result.Answers = answers
		switch result.Type {
		case "phq9":
			session.Bundle.PHQ9 = result
		case "gad7":
			session.Bundle.GAD7 = result
		}
	}
	return rows.Err()
}

func (s *Store) listScreeningAnswers(ctx context.Context, resultID string) ([]screening.Answer, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT question_id, score, position
		FROM screening_answers
		WHERE result_id = $1
		ORDER BY position
	`, resultID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	answers := make([]screening.Answer, 0)
	for rows.Next() {
		var answer screening.Answer
		if err := rows.Scan(&answer.QuestionID, &answer.Score, &answer.Position); err != nil {
			return nil, err
		}
		answers = append(answers, answer)
	}
	return answers, rows.Err()
}

func insertScreeningResult(ctx context.Context, tx *sql.Tx, sessionID string, result screening.Result) error {
	var resultID string
	err := tx.QueryRowContext(ctx, `
		INSERT INTO screening_results (
			session_id, type, score, max_score, level, summary, crisis_flag
		)
		VALUES ($1, $2::assessment_type, $3, $4, $5::risk_level, $6, $7)
		RETURNING id
	`, sessionID, result.Type, result.Score, result.MaxScore, result.Level, result.Summary, result.CrisisFlag).
		Scan(&resultID)
	if err != nil {
		return err
	}
	for _, answer := range result.Answers {
		_, err = tx.ExecContext(ctx, `
			INSERT INTO screening_answers (result_id, question_id, score, position)
			VALUES ($1, $2, $3, $4)
		`, resultID, answer.QuestionID, answer.Score, answer.Position)
		if err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) UpsertScreeningReview(ctx context.Context, professionalID, screeningSessionID, status, note string) (ScreeningReview, error) {
	professionalID = strings.TrimSpace(professionalID)
	screeningSessionID = strings.TrimSpace(screeningSessionID)
	status = strings.TrimSpace(status)
	if status == "" {
		status = "reviewed"
	}
	note = strings.TrimSpace(note)
	if professionalID == "" || screeningSessionID == "" {
		return ScreeningReview{}, errors.New("professional_id and screening_session_id are required")
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return ScreeningReview{}, err
	}
	defer tx.Rollback()

	var patientID string
	err = tx.QueryRowContext(ctx, `
		SELECT ss.patient_id
		FROM screening_sessions ss
		JOIN patient_professional_links l
		  ON l.patient_id = ss.patient_id
		 AND l.professional_id = $2
		 AND l.status = 'active'
		WHERE ss.id = $1
	`, screeningSessionID, professionalID).Scan(&patientID)
	if errors.Is(err, sql.ErrNoRows) {
		return ScreeningReview{}, errors.New("professional is not linked to this patient or screening not found")
	}
	if err != nil {
		return ScreeningReview{}, err
	}

	var review ScreeningReview
	err = tx.QueryRowContext(ctx, `
		INSERT INTO screening_reviews (
			screening_session_id, patient_id, professional_id, status, note
		)
		VALUES ($1, $2, $3, $4, $5)
		ON CONFLICT (screening_session_id, professional_id) DO UPDATE
		SET status = EXCLUDED.status,
		    note = EXCLUDED.note,
		    updated_at = now()
		RETURNING id, screening_session_id, patient_id, professional_id,
		          status, note, created_at, updated_at
	`, screeningSessionID, patientID, professionalID, status, note).
		Scan(&review.ID, &review.ScreeningSessionID, &review.PatientID,
			&review.ProfessionalID, &review.Status, &review.Note,
			&review.CreatedAt, &review.UpdatedAt)
	if err != nil {
		return ScreeningReview{}, err
	}

	metadata, _ := json.Marshal(map[string]any{"status": status})
	_, err = tx.ExecContext(ctx, `
		INSERT INTO audit_logs (actor_id, patient_id, action, entity_type, entity_id, metadata)
		VALUES ($1, $2, 'screening.reviewed', 'screening_session', $3, $4)
	`, professionalID, patientID, screeningSessionID, metadata)
	if err != nil {
		return ScreeningReview{}, err
	}

	if err := tx.Commit(); err != nil {
		return ScreeningReview{}, err
	}
	return review, nil
}

func (s *Store) ListScreeningReviews(ctx context.Context, patientID, professionalID string, limit int) ([]ScreeningReview, error) {
	limit = normalizeLimit(limit, 20, 100)
	query := `
		SELECT id, screening_session_id, patient_id, professional_id,
		       status, note, created_at, updated_at
		FROM screening_reviews
		WHERE patient_id = $1
	`
	args := []any{patientID}
	if strings.TrimSpace(professionalID) != "" {
		query += " AND professional_id = $2"
		args = append(args, strings.TrimSpace(professionalID))
	}
	query += `
		ORDER BY updated_at DESC
		LIMIT $` + strconv.Itoa(len(args)+1) + `
	`
	args = append(args, limit)
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var reviews []ScreeningReview
	for rows.Next() {
		var review ScreeningReview
		if err := rows.Scan(&review.ID, &review.ScreeningSessionID,
			&review.PatientID, &review.ProfessionalID, &review.Status,
			&review.Note, &review.CreatedAt, &review.UpdatedAt); err != nil {
			return nil, err
		}
		reviews = append(reviews, review)
	}
	return reviews, rows.Err()
}

func (s *Store) CreateProfessionalNote(ctx context.Context, professionalID, patientID, body, visibility string) (ProfessionalNote, error) {
	body = strings.TrimSpace(body)
	visibility = strings.TrimSpace(visibility)
	if visibility == "" {
		visibility = "private"
	}
	if body == "" {
		return ProfessionalNote{}, errors.New("body is required")
	}
	linked, err := s.ProfessionalLinkedToPatient(ctx, professionalID, patientID)
	if err != nil {
		return ProfessionalNote{}, err
	}
	if !linked {
		return ProfessionalNote{}, errors.New("professional is not linked to this patient")
	}

	var note ProfessionalNote
	err = s.db.QueryRowContext(ctx, `
		INSERT INTO professional_notes (patient_id, professional_id, body, visibility)
		VALUES ($1, $2, $3, $4)
		RETURNING id, patient_id, professional_id, body, visibility, created_at, updated_at
	`, patientID, professionalID, body, visibility).
		Scan(&note.ID, &note.PatientID, &note.ProfessionalID, &note.Body,
			&note.Visibility, &note.CreatedAt, &note.UpdatedAt)
	if err != nil {
		return ProfessionalNote{}, err
	}
	_ = s.AddAuditLog(ctx, professionalID, patientID, "professional_note.created", "professional_note", note.ID, map[string]any{"visibility": visibility})
	return note, nil
}

func (s *Store) ListProfessionalNotes(ctx context.Context, patientID, professionalID, requesterRole string, limit int) ([]ProfessionalNote, error) {
	limit = normalizeLimit(limit, 20, 100)
	query := `
		SELECT id, patient_id, professional_id, body, visibility, created_at, updated_at
		FROM professional_notes
		WHERE patient_id = $1
		  AND archived_at IS NULL
	`
	args := []any{patientID}
	if requesterRole == "professional" {
		query += " AND professional_id = $2"
		args = append(args, strings.TrimSpace(professionalID))
	} else {
		query += " AND visibility = 'shared_with_patient'"
	}
	query += `
		ORDER BY updated_at DESC
		LIMIT $` + strconv.Itoa(len(args)+1) + `
	`
	args = append(args, limit)
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var notes []ProfessionalNote
	for rows.Next() {
		var note ProfessionalNote
		if err := rows.Scan(&note.ID, &note.PatientID, &note.ProfessionalID,
			&note.Body, &note.Visibility, &note.CreatedAt, &note.UpdatedAt); err != nil {
			return nil, err
		}
		notes = append(notes, note)
	}
	return notes, rows.Err()
}

func (s *Store) CreateFollowUpMessage(ctx context.Context, professionalID, patientID, body, status string) (FollowUpMessage, error) {
	body = strings.TrimSpace(body)
	status = strings.TrimSpace(status)
	if status == "" {
		status = "sent"
	}
	if body == "" {
		return FollowUpMessage{}, errors.New("body is required")
	}
	linked, err := s.ProfessionalLinkedToPatient(ctx, professionalID, patientID)
	if err != nil {
		return FollowUpMessage{}, err
	}
	if !linked {
		return FollowUpMessage{}, errors.New("professional is not linked to this patient")
	}

	var message FollowUpMessage
	var readAt sql.NullTime
	err = s.db.QueryRowContext(ctx, `
		INSERT INTO follow_up_messages (patient_id, professional_id, body, status)
		VALUES ($1, $2, $3, $4)
		RETURNING id, patient_id, professional_id, body, status, created_at, updated_at, read_at
	`, patientID, professionalID, body, status).
		Scan(&message.ID, &message.PatientID, &message.ProfessionalID,
			&message.Body, &message.Status, &message.CreatedAt,
			&message.UpdatedAt, &readAt)
	if err != nil {
		return FollowUpMessage{}, err
	}
	if readAt.Valid {
		message.ReadAt = &readAt.Time
	}
	_ = s.AddAuditLog(ctx, professionalID, patientID, "follow_up.sent", "follow_up_message", message.ID, map[string]any{"status": status})
	return message, nil
}

func (s *Store) ListFollowUpMessages(ctx context.Context, patientID, professionalID, requesterRole string, limit int) ([]FollowUpMessage, error) {
	limit = normalizeLimit(limit, 20, 100)
	query := `
		SELECT id, patient_id, professional_id, body, status, created_at, updated_at, read_at
		FROM follow_up_messages
		WHERE patient_id = $1
		  AND archived_at IS NULL
	`
	args := []any{patientID}
	if requesterRole == "professional" {
		query += " AND professional_id = $2"
		args = append(args, strings.TrimSpace(professionalID))
	}
	query += `
		ORDER BY created_at DESC
		LIMIT $` + strconv.Itoa(len(args)+1) + `
	`
	args = append(args, limit)
	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var messages []FollowUpMessage
	for rows.Next() {
		var message FollowUpMessage
		var readAt sql.NullTime
		if err := rows.Scan(&message.ID, &message.PatientID,
			&message.ProfessionalID, &message.Body, &message.Status,
			&message.CreatedAt, &message.UpdatedAt, &readAt); err != nil {
			return nil, err
		}
		if readAt.Valid {
			message.ReadAt = &readAt.Time
		}
		messages = append(messages, message)
	}
	return messages, rows.Err()
}

func (s *Store) MarkFollowUpRead(ctx context.Context, patientID, followUpID string) (FollowUpMessage, error) {
	var message FollowUpMessage
	var readAt sql.NullTime
	err := s.db.QueryRowContext(ctx, `
		UPDATE follow_up_messages
		SET read_at = COALESCE(read_at, now()), updated_at = now()
		WHERE id = $1 AND patient_id = $2 AND status = 'sent' AND archived_at IS NULL
		RETURNING id, patient_id, professional_id, body, status, created_at, updated_at, read_at
	`, followUpID, patientID).Scan(&message.ID, &message.PatientID,
		&message.ProfessionalID, &message.Body, &message.Status,
		&message.CreatedAt, &message.UpdatedAt, &readAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return FollowUpMessage{}, errors.New("follow-up was not found")
		}
		return FollowUpMessage{}, err
	}
	if readAt.Valid {
		message.ReadAt = &readAt.Time
	}
	_ = s.AddAuditLog(ctx, patientID, patientID, "follow_up.read", "follow_up_message", message.ID, nil)
	return message, nil
}

func (s *Store) UpsertMoodCheckin(ctx context.Context, input MoodCheckin) (MoodCheckin, error) {
	if input.PatientID == "" || input.Mood == "" {
		return MoodCheckin{}, errors.New("patient_id and mood are required")
	}
	if input.OccurredAt.IsZero() {
		input.OccurredAt = time.Now()
	}
	var saved MoodCheckin
	err := s.db.QueryRowContext(ctx, `
		INSERT INTO mood_checkins (
			patient_id, mood, sleep_hours, energy, anxiety, irritability, note, occurred_at
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
		RETURNING id, patient_id, mood, sleep_hours, energy, anxiety, irritability, note, occurred_at, created_at
	`, input.PatientID, input.Mood, input.SleepHours, input.Energy,
		input.Anxiety, input.Irritability, input.Note, input.OccurredAt).
		Scan(&saved.ID, &saved.PatientID, &saved.Mood, &saved.SleepHours,
			&saved.Energy, &saved.Anxiety, &saved.Irritability,
			&saved.Note, &saved.OccurredAt, &saved.CreatedAt)
	if err != nil {
		return MoodCheckin{}, err
	}
	_ = s.AddAuditLog(ctx, input.PatientID, input.PatientID, "mood.created", "mood_checkin", saved.ID, nil)
	return saved, nil
}

func (s *Store) ListMoodCheckins(ctx context.Context, patientID string, limit int) ([]MoodCheckin, error) {
	limit = normalizeLimit(limit, 20, 100)
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, patient_id, mood, sleep_hours, energy, anxiety, irritability, note, occurred_at, created_at
		FROM mood_checkins
		WHERE patient_id = $1
		ORDER BY occurred_at DESC
		LIMIT $2
	`, patientID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var items []MoodCheckin
	for rows.Next() {
		var item MoodCheckin
		if err := rows.Scan(&item.ID, &item.PatientID, &item.Mood,
			&item.SleepHours, &item.Energy, &item.Anxiety,
			&item.Irritability, &item.Note, &item.OccurredAt,
			&item.CreatedAt); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Store) UpsertDiaryEntry(ctx context.Context, input DiaryEntry) (DiaryEntry, error) {
	if input.PatientID == "" || input.Title == "" || input.Note == "" {
		return DiaryEntry{}, errors.New("patient_id, title, and note are required")
	}
	if input.Mood == "" {
		input.Mood = "okay"
	}
	if input.OccurredAt.IsZero() {
		input.OccurredAt = time.Now()
	}
	var saved DiaryEntry
	var feedback sql.NullString
	err := s.db.QueryRowContext(ctx, `
		INSERT INTO diary_entries (
			patient_id, mood, title, note, shared_with_professionals, occurred_at
		)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, patient_id, mood, title, note, shared_with_professionals,
		          professional_feedback, occurred_at, created_at, updated_at
	`, input.PatientID, input.Mood, input.Title, input.Note,
		input.SharedWithProfessionals, input.OccurredAt).
		Scan(&saved.ID, &saved.PatientID, &saved.Mood, &saved.Title,
			&saved.Note, &saved.SharedWithProfessionals, &feedback,
			&saved.OccurredAt, &saved.CreatedAt, &saved.UpdatedAt)
	if err != nil {
		return DiaryEntry{}, err
	}
	if feedback.Valid {
		saved.ProfessionalFeedback = feedback.String
	}
	_ = s.AddAuditLog(ctx, input.PatientID, input.PatientID, "diary.created", "diary_entry", saved.ID, map[string]any{"shared": input.SharedWithProfessionals})
	return saved, nil
}

func (s *Store) ListDiaryEntries(ctx context.Context, patientID string, sharedOnly bool, limit int) ([]DiaryEntry, error) {
	limit = normalizeLimit(limit, 20, 100)
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, patient_id, mood, title, note, shared_with_professionals,
		       professional_feedback, occurred_at, created_at, updated_at
		FROM diary_entries
		WHERE patient_id = $1
		  AND deleted_at IS NULL
		  AND ($2 = false OR shared_with_professionals = true)
		ORDER BY occurred_at DESC
		LIMIT $3
	`, patientID, sharedOnly, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var items []DiaryEntry
	for rows.Next() {
		var item DiaryEntry
		var feedback sql.NullString
		if err := rows.Scan(&item.ID, &item.PatientID, &item.Mood,
			&item.Title, &item.Note, &item.SharedWithProfessionals,
			&feedback, &item.OccurredAt, &item.CreatedAt,
			&item.UpdatedAt); err != nil {
			return nil, err
		}
		if feedback.Valid {
			item.ProfessionalFeedback = feedback.String
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Store) UpdateDiaryFeedback(ctx context.Context, professionalID, patientID, diaryID, feedback string) (DiaryEntry, error) {
	feedback = strings.TrimSpace(feedback)
	if feedback == "" {
		return DiaryEntry{}, errors.New("feedback is required")
	}
	linked, err := s.ProfessionalLinkedToPatient(ctx, professionalID, patientID)
	if err != nil {
		return DiaryEntry{}, err
	}
	if !linked {
		return DiaryEntry{}, errors.New("professional is not linked to this patient")
	}

	var item DiaryEntry
	var savedFeedback sql.NullString
	err = s.db.QueryRowContext(ctx, `
		UPDATE diary_entries
		SET professional_feedback = $1, updated_at = now()
		WHERE id = $2 AND patient_id = $3
		  AND shared_with_professionals = true AND deleted_at IS NULL
		RETURNING id, patient_id, mood, title, note, shared_with_professionals,
		          professional_feedback, occurred_at, created_at, updated_at
	`, feedback, diaryID, patientID).Scan(&item.ID, &item.PatientID, &item.Mood,
		&item.Title, &item.Note, &item.SharedWithProfessionals, &savedFeedback,
		&item.OccurredAt, &item.CreatedAt, &item.UpdatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return DiaryEntry{}, errors.New("shared diary entry was not found")
		}
		return DiaryEntry{}, err
	}
	if savedFeedback.Valid {
		item.ProfessionalFeedback = savedFeedback.String
	}
	_ = s.AddAuditLog(ctx, professionalID, patientID, "diary.feedback_updated", "diary_entry", item.ID, nil)
	return item, nil
}

func (s *Store) UpsertMedication(ctx context.Context, input Medication) (Medication, error) {
	if input.PatientID == "" || input.Name == "" {
		return Medication{}, errors.New("patient_id and name are required")
	}
	if input.Dosage == "" {
		input.Dosage = "0 mg"
	}
	if input.Form == "" {
		input.Form = "Tablet"
	}
	if input.Source == "" {
		input.Source = "patient"
	}
	var saved Medication
	err := s.db.QueryRowContext(ctx, `
		INSERT INTO medications (
			patient_id, name, dosage, form, reminder_time, relation_to_meal,
			current_stock, alert_below, source
		)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		RETURNING id, patient_id, name, dosage, form, reminder_time, relation_to_meal,
		          current_stock, alert_below, source, active, created_at, updated_at
	`, input.PatientID, input.Name, input.Dosage, input.Form,
		input.ReminderTime, input.RelationToMeal, input.CurrentStock,
		input.AlertBelow, input.Source).
		Scan(&saved.ID, &saved.PatientID, &saved.Name, &saved.Dosage,
			&saved.Form, &saved.ReminderTime, &saved.RelationToMeal,
			&saved.CurrentStock, &saved.AlertBelow, &saved.Source,
			&saved.Active, &saved.CreatedAt, &saved.UpdatedAt)
	if err != nil {
		return Medication{}, err
	}
	_ = s.AddAuditLog(ctx, input.PatientID, input.PatientID, "medication.upserted", "medication", saved.ID, nil)
	return saved, nil
}

func (s *Store) ListMedications(ctx context.Context, patientID string, limit int) ([]Medication, error) {
	limit = normalizeLimit(limit, 50, 100)
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, patient_id, name, dosage, form, reminder_time, relation_to_meal,
		       current_stock, alert_below, source, active, created_at, updated_at
		FROM medications
		WHERE patient_id = $1 AND active
		ORDER BY updated_at DESC
		LIMIT $2
	`, patientID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var items []Medication
	for rows.Next() {
		var item Medication
		if err := rows.Scan(&item.ID, &item.PatientID, &item.Name,
			&item.Dosage, &item.Form, &item.ReminderTime,
			&item.RelationToMeal, &item.CurrentStock, &item.AlertBelow,
			&item.Source, &item.Active, &item.CreatedAt, &item.UpdatedAt); err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Store) CreateMedicationLog(ctx context.Context, input MedicationLog) (MedicationLog, error) {
	if input.PatientID == "" || input.MedicationName == "" {
		return MedicationLog{}, errors.New("patient_id and medication_name are required")
	}
	if input.Status == "" {
		input.Status = "taken"
	}
	if input.TakenAt.IsZero() {
		input.TakenAt = time.Now()
	}
	var medicationID any
	if input.MedicationID != "" {
		medicationID = input.MedicationID
	}
	var saved MedicationLog
	var medicationIDOut sql.NullString
	err := s.db.QueryRowContext(ctx, `
		INSERT INTO medication_logs (
			patient_id, medication_id, medication_name, status, taken_at
		)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, patient_id, medication_id, medication_name, status, taken_at, created_at
	`, input.PatientID, medicationID, input.MedicationName, input.Status, input.TakenAt).
		Scan(&saved.ID, &saved.PatientID, &medicationIDOut,
			&saved.MedicationName, &saved.Status, &saved.TakenAt,
			&saved.CreatedAt)
	if err != nil {
		return MedicationLog{}, err
	}
	if medicationIDOut.Valid {
		saved.MedicationID = medicationIDOut.String
	}
	_ = s.AddAuditLog(ctx, input.PatientID, input.PatientID, "medication_log.created", "medication_log", saved.ID, nil)
	return saved, nil
}

func (s *Store) ListMedicationLogs(ctx context.Context, patientID string, limit int) ([]MedicationLog, error) {
	limit = normalizeLimit(limit, 20, 100)
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, patient_id, medication_id, medication_name, status, taken_at, created_at
		FROM medication_logs
		WHERE patient_id = $1
		ORDER BY taken_at DESC
		LIMIT $2
	`, patientID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var items []MedicationLog
	for rows.Next() {
		var item MedicationLog
		var medicationID sql.NullString
		if err := rows.Scan(&item.ID, &item.PatientID, &medicationID,
			&item.MedicationName, &item.Status, &item.TakenAt,
			&item.CreatedAt); err != nil {
			return nil, err
		}
		if medicationID.Valid {
			item.MedicationID = medicationID.String
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Store) GetPatientDataConsent(ctx context.Context, patientID, professionalID string) (PatientDataConsent, error) {
	var consent PatientDataConsent
	err := s.db.QueryRowContext(ctx, `
		INSERT INTO patient_data_consents (patient_id, professional_id)
		VALUES ($1, $2)
		ON CONFLICT (patient_id, professional_id) DO UPDATE
		SET updated_at = patient_data_consents.updated_at
		RETURNING patient_id, professional_id, share_screenings, share_mood_diary,
		          share_medications, share_timeline, updated_at
	`, patientID, professionalID).Scan(&consent.PatientID, &consent.ProfessionalID,
		&consent.ShareScreenings, &consent.ShareMoodDiary,
		&consent.ShareMedications, &consent.ShareTimeline, &consent.UpdatedAt)
	return consent, err
}

func (s *Store) UpdatePatientDataConsent(ctx context.Context, consent PatientDataConsent) (PatientDataConsent, error) {
	var saved PatientDataConsent
	err := s.db.QueryRowContext(ctx, `
		INSERT INTO patient_data_consents (
			patient_id, professional_id, share_screenings, share_mood_diary,
			share_medications, share_timeline
		)
		VALUES ($1, $2, $3, $4, $5, $6)
		ON CONFLICT (patient_id, professional_id) DO UPDATE
		SET share_screenings = EXCLUDED.share_screenings,
		    share_mood_diary = EXCLUDED.share_mood_diary,
		    share_medications = EXCLUDED.share_medications,
		    share_timeline = EXCLUDED.share_timeline,
		    updated_at = now()
		RETURNING patient_id, professional_id, share_screenings, share_mood_diary,
		          share_medications, share_timeline, updated_at
	`, consent.PatientID, consent.ProfessionalID, consent.ShareScreenings,
		consent.ShareMoodDiary, consent.ShareMedications, consent.ShareTimeline).
		Scan(&saved.PatientID, &saved.ProfessionalID, &saved.ShareScreenings,
			&saved.ShareMoodDiary, &saved.ShareMedications,
			&saved.ShareTimeline, &saved.UpdatedAt)
	if err != nil {
		return PatientDataConsent{}, err
	}
	_ = s.AddAuditLog(ctx, consent.PatientID, consent.PatientID, "privacy_consent.updated", "patient_data_consent", consent.ProfessionalID, nil)
	return saved, nil
}

func (s *Store) ListTimelineEvents(ctx context.Context, patientID string, limit int) ([]TimelineEvent, error) {
	limit = normalizeLimit(limit, 30, 100)
	events := make([]TimelineEvent, 0)

	screenings, err := s.ListScreeningSessions(ctx, patientID, limit)
	if err != nil {
		return nil, err
	}
	for _, item := range screenings {
		events = append(events, TimelineEvent{
			ID:        item.ID,
			PatientID: item.PatientID,
			Type:      "screening",
			Title:     "Screening " + item.OverallLevel,
			Body:      fmt.Sprintf("PHQ-9 %d, GAD-7 %d", item.Bundle.PHQ9.Score, item.Bundle.GAD7.Score),
			Metadata: map[string]any{
				"overall_level": item.OverallLevel,
				"crisis_flag":   item.CrisisFlag,
			},
			CreatedAt: item.CreatedAt,
		})
	}

	moods, err := s.ListMoodCheckins(ctx, patientID, limit)
	if err != nil {
		return nil, err
	}
	for _, item := range moods {
		events = append(events, TimelineEvent{ID: item.ID, PatientID: item.PatientID, Type: "mood", Title: "Mood " + item.Mood, Body: item.Note, Metadata: map[string]any{"energy": item.Energy, "anxiety": item.Anxiety}, CreatedAt: item.OccurredAt})
	}

	diaries, err := s.ListDiaryEntries(ctx, patientID, false, limit)
	if err != nil {
		return nil, err
	}
	for _, item := range diaries {
		events = append(events, TimelineEvent{ID: item.ID, PatientID: item.PatientID, Type: "diary", Title: item.Title, Body: item.Note, Metadata: map[string]any{"mood": item.Mood}, CreatedAt: item.OccurredAt})
	}

	followUps, err := s.ListFollowUpMessages(ctx, patientID, "", "patient", limit)
	if err != nil {
		return nil, err
	}
	for _, item := range followUps {
		events = append(events, TimelineEvent{ID: item.ID, PatientID: item.PatientID, Type: "follow_up", Title: "Follow-up profesional", Body: item.Body, Metadata: map[string]any{"professional_id": item.ProfessionalID}, CreatedAt: item.CreatedAt})
	}

	logs, err := s.ListMedicationLogs(ctx, patientID, limit)
	if err != nil {
		return nil, err
	}
	for _, item := range logs {
		events = append(events, TimelineEvent{ID: item.ID, PatientID: item.PatientID, Type: "medication_log", Title: "Obat " + item.Status, Body: item.MedicationName, Metadata: map[string]any{"status": item.Status}, CreatedAt: item.TakenAt})
	}

	sort.Slice(events, func(i, j int) bool {
		return events[i].CreatedAt.After(events[j].CreatedAt)
	})
	if len(events) > limit {
		events = events[:limit]
	}
	return events, nil
}

func (s *Store) AddAuditLog(ctx context.Context, actorID, patientID, action, entityType, entityID string, metadata map[string]any) error {
	if action == "" || entityType == "" {
		return errors.New("action and entity_type are required")
	}
	if metadata == nil {
		metadata = map[string]any{}
	}
	raw, err := json.Marshal(metadata)
	if err != nil {
		return err
	}
	var actor any
	if strings.TrimSpace(actorID) != "" {
		actor = strings.TrimSpace(actorID)
	}
	var patient any
	if strings.TrimSpace(patientID) != "" {
		patient = strings.TrimSpace(patientID)
	}
	var entity any
	if strings.TrimSpace(entityID) != "" {
		entity = strings.TrimSpace(entityID)
	}
	_, err = s.db.ExecContext(ctx, `
		INSERT INTO audit_logs (actor_id, patient_id, action, entity_type, entity_id, metadata)
		VALUES ($1, $2, $3, $4, $5, $6)
	`, actor, patient, action, entityType, entity, raw)
	return err
}

func (s *Store) ListAuditLogs(ctx context.Context, patientID string, limit int) ([]AuditLog, error) {
	limit = normalizeLimit(limit, 50, 200)
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, actor_id, patient_id, action, entity_type, entity_id, metadata::text, created_at
		FROM audit_logs
		WHERE patient_id = $1
		ORDER BY created_at DESC
		LIMIT $2
	`, patientID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var logs []AuditLog
	for rows.Next() {
		var log AuditLog
		var actorID, patientIDValue, entityID sql.NullString
		var metadata string
		if err := rows.Scan(&log.ID, &actorID, &patientIDValue, &log.Action,
			&log.EntityType, &entityID, &metadata, &log.CreatedAt); err != nil {
			return nil, err
		}
		if actorID.Valid {
			log.ActorID = actorID.String
		}
		if patientIDValue.Valid {
			log.PatientID = patientIDValue.String
		}
		if entityID.Valid {
			log.EntityID = entityID.String
		}
		_ = json.Unmarshal([]byte(metadata), &log.Metadata)
		if log.Metadata == nil {
			log.Metadata = map[string]any{}
		}
		logs = append(logs, log)
	}
	return logs, rows.Err()
}

func (s *Store) CreateNotification(ctx context.Context, input Notification) (Notification, error) {
	if input.UserID == "" || input.Type == "" || input.Title == "" || input.Body == "" {
		return Notification{}, errors.New("user_id, type, title, and body are required")
	}
	if input.Data == nil {
		input.Data = map[string]string{}
	}
	data, err := json.Marshal(input.Data)
	if err != nil {
		return Notification{}, err
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Notification{}, err
	}
	defer tx.Rollback()

	var notification Notification
	err = tx.QueryRowContext(ctx, `
		INSERT INTO notifications (user_id, type, title, body, data)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, user_id, type, title, body, status, created_at, sent_at, read_at
	`, input.UserID, input.Type, input.Title, input.Body, data).
		Scan(&notification.ID, &notification.UserID, &notification.Type,
			&notification.Title, &notification.Body, &notification.Status,
			&notification.CreatedAt, &notification.SentAt, &notification.ReadAt)
	if err != nil {
		return Notification{}, err
	}
	notification.Data = input.Data

	_, err = tx.ExecContext(ctx, `
		INSERT INTO notification_outbox (notification_id, provider)
		VALUES ($1, 'fcm')
	`, notification.ID)
	if err != nil {
		return Notification{}, err
	}

	if err := tx.Commit(); err != nil {
		return Notification{}, err
	}
	return notification, nil
}

func (s *Store) ListNotifications(ctx context.Context, userID string, limit int) ([]Notification, error) {
	limit = normalizeLimit(limit, 30, 100)
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, user_id, type, title, body, data::text, status,
		       created_at, sent_at, read_at
		FROM notifications
		WHERE user_id = $1
		ORDER BY created_at DESC
		LIMIT $2
	`, userID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	items := make([]Notification, 0)
	for rows.Next() {
		var item Notification
		var rawData string
		var sentAt, readAt sql.NullTime
		if err := rows.Scan(&item.ID, &item.UserID, &item.Type, &item.Title,
			&item.Body, &rawData, &item.Status, &item.CreatedAt, &sentAt,
			&readAt); err != nil {
			return nil, err
		}
		if err := json.Unmarshal([]byte(rawData), &item.Data); err != nil {
			return nil, err
		}
		if item.Data == nil {
			item.Data = map[string]string{}
		}
		if sentAt.Valid {
			item.SentAt = &sentAt.Time
		}
		if readAt.Valid {
			item.ReadAt = &readAt.Time
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

func (s *Store) MarkNotificationRead(ctx context.Context, userID, notificationID string) (Notification, error) {
	var item Notification
	var rawData string
	var sentAt, readAt sql.NullTime
	err := s.db.QueryRowContext(ctx, `
		UPDATE notifications
		SET read_at = COALESCE(read_at, now())
		WHERE id = $1 AND user_id = $2
		RETURNING id, user_id, type, title, body, data::text, status,
		          created_at, sent_at, read_at
	`, notificationID, userID).Scan(&item.ID, &item.UserID, &item.Type,
		&item.Title, &item.Body, &rawData, &item.Status, &item.CreatedAt,
		&sentAt, &readAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return Notification{}, errors.New("notification was not found")
		}
		return Notification{}, err
	}
	if err := json.Unmarshal([]byte(rawData), &item.Data); err != nil {
		return Notification{}, err
	}
	if sentAt.Valid {
		item.SentAt = &sentAt.Time
	}
	if readAt.Valid {
		item.ReadAt = &readAt.Time
	}
	return item, nil
}

func (s *Store) MarkAllNotificationsRead(ctx context.Context, userID string) (int64, error) {
	result, err := s.db.ExecContext(ctx, `
		UPDATE notifications
		SET read_at = now()
		WHERE user_id = $1 AND read_at IS NULL
	`, userID)
	if err != nil {
		return 0, err
	}
	return result.RowsAffected()
}

func (s *Store) EnabledDeviceTokens(ctx context.Context, userID string) ([]string, error) {
	rows, err := s.db.QueryContext(ctx, `
		SELECT token
		FROM device_tokens
		WHERE user_id = $1 AND enabled
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var tokens []string
	for rows.Next() {
		var token string
		if err := rows.Scan(&token); err != nil {
			return nil, err
		}
		tokens = append(tokens, token)
	}
	return tokens, rows.Err()
}

func (s *Store) AcquireOutboxJobs(ctx context.Context, limit int) ([]OutboxJob, error) {
	rows, err := s.db.QueryContext(ctx, `
		WITH next_jobs AS (
			SELECT id
			FROM notification_outbox
			WHERE delivered_at IS NULL
			  AND next_attempt_at <= now()
			  AND (locked_at IS NULL OR locked_at < now() - interval '2 minutes')
			ORDER BY next_attempt_at
			LIMIT $1
			FOR UPDATE SKIP LOCKED
		),
		locked AS (
			UPDATE notification_outbox o
			SET locked_at = now(), attempts = o.attempts + 1
			FROM next_jobs
			WHERE o.id = next_jobs.id
			RETURNING o.id, o.notification_id, o.attempts
		)
		SELECT locked.id, locked.notification_id, locked.attempts,
		       n.user_id, n.title, n.body, n.data::text
		FROM locked
		JOIN notifications n ON n.id = locked.notification_id
	`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var jobs []OutboxJob
	for rows.Next() {
		var job OutboxJob
		var rawData string
		if err := rows.Scan(&job.ID, &job.NotificationID, &job.Attempts, &job.UserID, &job.Title, &job.Body, &rawData); err != nil {
			return nil, err
		}
		if err := json.Unmarshal([]byte(rawData), &job.Data); err != nil {
			return nil, err
		}
		jobs = append(jobs, job)
	}
	return jobs, rows.Err()
}

func (s *Store) MarkOutboxDelivered(ctx context.Context, jobID string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	var notificationID string
	err = tx.QueryRowContext(ctx, `
		UPDATE notification_outbox
		SET delivered_at = now(), locked_at = NULL, last_error = NULL
		WHERE id = $1
		RETURNING notification_id
	`, jobID).Scan(&notificationID)
	if err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `
		UPDATE notifications
		SET status = 'sent', sent_at = now()
		WHERE id = $1
	`, notificationID)
	if err != nil {
		return err
	}
	return tx.Commit()
}

func (s *Store) MarkOutboxFailed(ctx context.Context, jobID, message string, retryAt time.Time, terminal bool) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer tx.Rollback()

	var notificationID string
	err = tx.QueryRowContext(ctx, `
		UPDATE notification_outbox
		SET locked_at = NULL, last_error = $2, next_attempt_at = $3
		WHERE id = $1
		RETURNING notification_id
	`, jobID, message, retryAt).Scan(&notificationID)
	if err != nil {
		return err
	}
	if terminal {
		_, err = tx.ExecContext(ctx, `
			UPDATE notifications
			SET status = 'failed'
			WHERE id = $1
		`, notificationID)
		if err != nil {
			return err
		}
	}
	return tx.Commit()
}

func durationInterval(duration time.Duration) string {
	seconds := int64(duration.Seconds())
	if seconds < 1 {
		seconds = 1
	}
	return fmt.Sprintf("%d seconds", seconds)
}

func normalizeLimit(value, fallback, max int) int {
	if value <= 0 {
		return fallback
	}
	if value > max {
		return max
	}
	return value
}

type ChatMessage struct {
	ID             string    `json:"id"`
	PatientID      string    `json:"patient_id"`
	ProfessionalID string    `json:"professional_id"`
	SenderID       string    `json:"sender_id"`
	SenderName     string    `json:"sender_name"`
	Text           string    `json:"text"`
	CreatedAt      time.Time `json:"created_at"`
}

func (s *Store) CreateChatMessage(ctx context.Context, msg ChatMessage) (ChatMessage, error) {
	msg.Text = strings.TrimSpace(msg.Text)
	msg.SenderName = strings.TrimSpace(msg.SenderName)
	if msg.ID == "" || msg.PatientID == "" || msg.ProfessionalID == "" || msg.SenderID == "" || msg.Text == "" {
		return ChatMessage{}, errors.New("id, patient_id, professional_id, sender_id, and text are required")
	}
	var saved ChatMessage
	err := s.db.QueryRowContext(ctx, `
		INSERT INTO chat_messages (id, patient_id, professional_id, sender_id, sender_name, text)
		VALUES ($1, $2, $3, $4, $5, $6)
		RETURNING id, patient_id, professional_id, sender_id, sender_name, text, created_at
	`, msg.ID, msg.PatientID, msg.ProfessionalID, msg.SenderID, msg.SenderName, msg.Text).
		Scan(&saved.ID, &saved.PatientID, &saved.ProfessionalID, &saved.SenderID,
			&saved.SenderName, &saved.Text, &saved.CreatedAt)
	if err != nil {
		return ChatMessage{}, err
	}
	_ = s.AddAuditLog(ctx, msg.SenderID, msg.PatientID, "chat_message.sent", "chat_message", saved.ID, nil)
	return saved, nil
}

func (s *Store) ListChatMessages(ctx context.Context, patientID, professionalID string, limit int) ([]ChatMessage, error) {
	patientID = strings.TrimSpace(patientID)
	professionalID = strings.TrimSpace(professionalID)
	if patientID == "" || professionalID == "" {
		return nil, errors.New("patient_id and professional_id are required")
	}
	limit = normalizeLimit(limit, 50, 200)
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, patient_id, professional_id, sender_id, sender_name, text, created_at
		FROM chat_messages
		WHERE patient_id = $1 AND professional_id = $2
		ORDER BY created_at DESC
		LIMIT $3
	`, patientID, professionalID, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var messages []ChatMessage
	for rows.Next() {
		var msg ChatMessage
		if err := rows.Scan(&msg.ID, &msg.PatientID, &msg.ProfessionalID,
			&msg.SenderID, &msg.SenderName, &msg.Text, &msg.CreatedAt); err != nil {
			return nil, err
		}
		messages = append(messages, msg)
	}
	return messages, rows.Err()
}

func (s *Store) AreUsersLinked(ctx context.Context, userID1, userID2 string) (patientID, professionalID string, linked bool, err error) {
	err = s.db.QueryRowContext(ctx, `
		SELECT patient_id, professional_id
		FROM patient_professional_links
		WHERE ((patient_id = $1 AND professional_id = $2)
		    OR (patient_id = $2 AND professional_id = $1))
		  AND status = 'active'
		LIMIT 1
	`, userID1, userID2).Scan(&patientID, &professionalID)
	if errors.Is(err, sql.ErrNoRows) {
		return "", "", false, nil
	}
	if err != nil {
		return "", "", false, err
	}
	return patientID, professionalID, true, nil
}

func (s *Store) ListLinkedUsers(ctx context.Context, userID string) ([]string, error) {
	userID = strings.TrimSpace(userID)
	if userID == "" {
		return nil, errors.New("user_id is required")
	}
	rows, err := s.db.QueryContext(ctx, `
		SELECT CASE WHEN patient_id = $1 THEN professional_id ELSE patient_id END
		FROM patient_professional_links
		WHERE (patient_id = $1 OR professional_id = $1)
		  AND status = 'active'
	`, userID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}
