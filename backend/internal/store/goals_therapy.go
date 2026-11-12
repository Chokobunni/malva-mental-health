package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"strings"
	"time"
)

// ============================================================
// Goals & Habits — tersimpan di server (tidak hilang saat app ditutup)
// ============================================================

type Goal struct {
	ID                    string       `json:"id"`
	PatientID             string       `json:"patient_id"`
	Title                 string       `json:"title"`
	Category              string       `json:"category"`
	TargetPerWeek         int          `json:"target_per_week"`
	IsActive              bool         `json:"is_active"`
	SortOrder             int          `json:"sort_order"`
	CreatedAt             time.Time    `json:"created_at"`
	UpdatedAt             time.Time    `json:"updated_at"`
	Details               *GoalDetails `json:"details,omitempty"`
	DoneToday             bool         `json:"done_today"`
	TodayValue            int          `json:"today_value"`
	TodayCompletedStepIDs []string     `json:"today_completed_step_ids"`
	StreakDays            int          `json:"streak_days"`
	IsDue                 bool         `json:"is_due"`
	FailedToday           bool         `json:"failed_today"`

	// Terhitung dari habit_logs untuk minggu berjalan.
	DoneThisWeek int     `json:"done_this_week"`
	LastLoggedOn *string `json:"last_logged_on,omitempty"`
}

type HabitLog struct {
	ID               string    `json:"id"`
	GoalID           string    `json:"goal_id"`
	PatientID        string    `json:"patient_id"`
	LoggedOn         string    `json:"logged_on"` // YYYY-MM-DD
	Done             bool      `json:"done"`
	CreatedAt        time.Time `json:"created_at"`
	Value            int       `json:"value"`
	CompletedStepIDs []string  `json:"completed_step_ids"`
}

// ============================================================
// Therapy submissions — worksheet pasien (bisa dibagikan & diunduh)
// ============================================================

type TherapySubmission struct {
	ID                       string          `json:"id"`
	PatientID                string          `json:"patient_id"`
	ModuleID                 string          `json:"module_id"`
	Title                    string          `json:"title"`
	Answers                  json.RawMessage `json:"answers"`
	Summary                  string          `json:"summary"`
	SharedWithProfessionalID *string         `json:"shared_with_professional_id,omitempty"`
	SharedAt                 *time.Time      `json:"shared_at,omitempty"`
	CreatedAt                time.Time       `json:"created_at"`
	UpdatedAt                time.Time       `json:"updated_at"`
}

func (s *Store) CreateTherapySubmission(ctx context.Context, patientID, moduleID, title string,
	answers json.RawMessage, summary string, sharedWith *string) (TherapySubmission, error) {

	patientID = strings.TrimSpace(patientID)
	moduleID = strings.TrimSpace(moduleID)
	if patientID == "" || moduleID == "" {
		return TherapySubmission{}, errors.New("patient_id and module_id are required")
	}
	title = strings.TrimSpace(title)
	if len(answers) == 0 {
		answers = json.RawMessage(`{}`)
	}
	if len(title) > 200 {
		title = title[:200]
	}
	var sub TherapySubmission
	var sharedArg *string
	if sharedWith != nil {
		value := strings.TrimSpace(*sharedWith)
		if value != "" {
			sharedArg = &value
		}
	}
	err := s.db.QueryRowContext(ctx, `
		INSERT INTO therapy_submissions (patient_id, module_id, title, answers, summary, shared_with_professional_id, shared_at)
		VALUES ($1, $2, $3, $4::jsonb, $5, $6, CASE WHEN $6::uuid IS NULL THEN NULL ELSE now() END)
		RETURNING id, patient_id, module_id, title, answers, summary,
		          shared_with_professional_id, shared_at, created_at, updated_at
	`, patientID, moduleID, title, string(answers), strings.TrimSpace(summary), sharedArg).
		Scan(&sub.ID, &sub.PatientID, &sub.ModuleID, &sub.Title, &sub.Answers, &sub.Summary,
			&sub.SharedWithProfessionalID, &sub.SharedAt, &sub.CreatedAt, &sub.UpdatedAt)
	return sub, err
}

// ListTherapySubmissions: untuk pasien (miliknya sendiri) atau profesional
// (hanya yang dibagikan ke dia bila sharedOnly=true).
func (s *Store) ListTherapySubmissions(ctx context.Context, userID string, sharedOnly bool, limits ...int) ([]TherapySubmission, error) {
	userID = strings.TrimSpace(userID)
	if userID == "" {
		return nil, errors.New("user_id is required")
	}
	var sqlLimit any = 100
	if len(limits) > 0 {
		if limits[0] == 0 {
			sqlLimit = nil
		} else {
			sqlLimit = normalizeLimit(limits[0], 100, 100)
		}
	}
	query := `
		SELECT id, patient_id, module_id, title, answers, summary,
		       shared_with_professional_id, shared_at, created_at, updated_at
		FROM therapy_submissions
		WHERE patient_id = $1
		ORDER BY created_at DESC
		LIMIT $2
	`
	if sharedOnly {
		query = `
			SELECT id, patient_id, module_id, title, answers, summary,
			       shared_with_professional_id, shared_at, created_at, updated_at
			FROM therapy_submissions
			WHERE shared_with_professional_id = $1
              AND (EXISTS (SELECT 1 FROM care_packages cp WHERE cp.patient_id=therapy_submissions.patient_id
                   AND cp.professional_id=$1 AND cp.status='active' AND cp.expires_at>now())
                OR EXISTS (SELECT 1 FROM care_sessions cs WHERE cs.patient_id=therapy_submissions.patient_id
                   AND cs.professional_id=$1 AND cs.status='scheduled' AND cs.scheduled_at<=now()
                   AND cs.scheduled_at + make_interval(mins=>cs.duration_minutes)>now()))
			ORDER BY created_at DESC
			LIMIT $2
		`
	}
	rows, err := s.db.QueryContext(ctx, query, userID, sqlLimit)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var out []TherapySubmission
	for rows.Next() {
		var sub TherapySubmission
		if err := rows.Scan(&sub.ID, &sub.PatientID, &sub.ModuleID, &sub.Title, &sub.Answers,
			&sub.Summary, &sub.SharedWithProfessionalID, &sub.SharedAt,
			&sub.CreatedAt, &sub.UpdatedAt); err != nil {
			return nil, err
		}
		out = append(out, sub)
	}
	return out, rows.Err()
}

func (s *Store) GetTherapySubmission(ctx context.Context, userID, submissionID string, professionalView bool) (TherapySubmission, error) {
	var sub TherapySubmission
	query := `
		SELECT id, patient_id, module_id, title, answers, summary,
		       shared_with_professional_id, shared_at, created_at, updated_at
		FROM therapy_submissions
		WHERE id = $1 AND patient_id = $2
	`
	args := []any{submissionID, userID}
	if professionalView {
		query = `
			SELECT id, patient_id, module_id, title, answers, summary,
			       shared_with_professional_id, shared_at, created_at, updated_at
			FROM therapy_submissions
			WHERE id = $1 AND (shared_with_professional_id = $2
                OR EXISTS (SELECT 1 FROM patient_data_consents pc
                    WHERE pc.patient_id=therapy_submissions.patient_id
                    AND pc.professional_id=$2 AND pc.share_therapy_records))
		`
	}
	err := s.db.QueryRowContext(ctx, query, args...).
		Scan(&sub.ID, &sub.PatientID, &sub.ModuleID, &sub.Title, &sub.Answers, &sub.Summary,
			&sub.SharedWithProfessionalID, &sub.SharedAt, &sub.CreatedAt, &sub.UpdatedAt)
	return sub, err
}

// ShareTherapySubmission membagikan worksheet ke profesional (atau menarik
// izin bila professionalID kosong).
func (s *Store) ShareTherapySubmission(ctx context.Context, patientID, submissionID, professionalID string) (TherapySubmission, error) {
	patientID = strings.TrimSpace(patientID)
	submissionID = strings.TrimSpace(submissionID)
	professionalID = strings.TrimSpace(professionalID)
	if patientID == "" || submissionID == "" {
		return TherapySubmission{}, errors.New("patient_id and submission_id are required")
	}
	var sharedArg *string
	if professionalID != "" {
		sharedArg = &professionalID
	}
	_, err := s.db.ExecContext(ctx, `
		UPDATE therapy_submissions
		SET shared_with_professional_id = $3,
		    shared_at = CASE WHEN $3::uuid IS NULL THEN NULL ELSE now() END,
		    updated_at = now()
		WHERE id = $1 AND patient_id = $2
	`, submissionID, patientID, sharedArg)
	if err != nil {
		return TherapySubmission{}, err
	}
	return s.GetTherapySubmission(ctx, patientID, submissionID, false)
}

func (s *Store) DeleteTherapySubmission(ctx context.Context, patientID, submissionID string) error {
	res, err := s.db.ExecContext(ctx, `
		DELETE FROM therapy_submissions WHERE id = $1 AND patient_id = $2
	`, strings.TrimSpace(submissionID), strings.TrimSpace(patientID))
	if err != nil {
		return err
	}
	aff, _ := res.RowsAffected()
	if aff == 0 {
		return sql.ErrNoRows
	}
	return nil
}
