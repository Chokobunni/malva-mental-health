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
	ID            string    `json:"id"`
	PatientID     string    `json:"patient_id"`
	Title         string    `json:"title"`
	Category      string    `json:"category"`
	TargetPerWeek int       `json:"target_per_week"`
	IsActive      bool      `json:"is_active"`
	SortOrder     int       `json:"sort_order"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`

	// Terhitung dari habit_logs untuk minggu berjalan.
	DoneThisWeek int     `json:"done_this_week"`
	LastLoggedOn *string `json:"last_logged_on,omitempty"`
}

type HabitLog struct {
	ID        string    `json:"id"`
	GoalID    string    `json:"goal_id"`
	PatientID string    `json:"patient_id"`
	LoggedOn  string    `json:"logged_on"` // YYYY-MM-DD
	Done      bool      `json:"done"`
	CreatedAt time.Time `json:"created_at"`
}

func (s *Store) ListGoals(ctx context.Context, patientID string, includeInactive bool) ([]Goal, error) {
	patientID = strings.TrimSpace(patientID)
	if patientID == "" {
		return nil, errors.New("patient_id is required")
	}
	rows, err := s.db.QueryContext(ctx, `
		SELECT g.id, g.patient_id, g.title, g.category, g.target_per_week,
		       g.is_active, g.sort_order, g.created_at, g.updated_at,
		       COALESCE(w.done_this_week, 0),
		       w.last_logged_on::text
		FROM goals g
		LEFT JOIN (
			SELECT goal_id,
			       COUNT(*) FILTER (WHERE done) AS done_this_week,
			       MAX(logged_date) AS last_logged_on
			FROM habit_logs
			WHERE logged_date >= date_trunc('week', CURRENT_DATE)::date
			GROUP BY goal_id
		) w ON w.goal_id = g.id
		WHERE g.patient_id = $1
		  AND ($2 OR g.is_active)
		ORDER BY g.sort_order, g.created_at
	`, patientID, includeInactive)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var out []Goal
	for rows.Next() {
		var g Goal
		if err := rows.Scan(&g.ID, &g.PatientID, &g.Title, &g.Category, &g.TargetPerWeek,
			&g.IsActive, &g.SortOrder, &g.CreatedAt, &g.UpdatedAt,
			&g.DoneThisWeek, &g.LastLoggedOn); err != nil {
			return nil, err
		}
		out = append(out, g)
	}
	return out, rows.Err()
}

type UpsertGoalParams struct {
	PatientID     string
	Title         string
	Category      string
	TargetPerWeek int
	IsActive      *bool
	SortOrder     *int
}

func (s *Store) CreateGoal(ctx context.Context, p UpsertGoalParams) (Goal, error) {
	p.PatientID = strings.TrimSpace(p.PatientID)
	p.Title = strings.TrimSpace(p.Title)
	p.Category = strings.TrimSpace(p.Category)
	if p.PatientID == "" || p.Title == "" {
		return Goal{}, errors.New("patient_id and title are required")
	}
	if p.Category == "" {
		p.Category = "general"
	}
	if p.TargetPerWeek <= 0 {
		p.TargetPerWeek = 3
	}
	if p.TargetPerWeek > 7 {
		p.TargetPerWeek = 7
	}
	var g Goal
	err := s.db.QueryRowContext(ctx, `
		INSERT INTO goals (patient_id, title, category, target_per_week)
		VALUES ($1, $2, $3, $4)
		RETURNING id, patient_id, title, category, target_per_week, is_active, sort_order, created_at, updated_at
	`, p.PatientID, p.Title, p.Category, p.TargetPerWeek).
		Scan(&g.ID, &g.PatientID, &g.Title, &g.Category, &g.TargetPerWeek, &g.IsActive,
			&g.SortOrder, &g.CreatedAt, &g.UpdatedAt)
	return g, err
}

func (s *Store) UpdateGoal(ctx context.Context, patientID, goalID, title, category string,
	targetPerWeek *int, isActive *bool) (Goal, error) {

	patientID = strings.TrimSpace(patientID)
	goalID = strings.TrimSpace(goalID)
	if patientID == "" || goalID == "" {
		return Goal{}, errors.New("patient_id and goal_id are required")
	}
	title = strings.TrimSpace(title)
	category = strings.TrimSpace(category)
	if title != "" {
		if _, err := s.db.ExecContext(ctx, `
			UPDATE goals SET title = $3, updated_at = now()
			WHERE id = $1 AND patient_id = $2
		`, goalID, patientID, title); err != nil {
			return Goal{}, err
		}
	}
	if category != "" {
		if _, err := s.db.ExecContext(ctx, `
			UPDATE goals SET category = $3, updated_at = now()
			WHERE id = $1 AND patient_id = $2
		`, goalID, patientID, category); err != nil {
			return Goal{}, err
		}
	}
	if targetPerWeek != nil {
		value := *targetPerWeek
		if value <= 0 {
			value = 1
		}
		if value > 7 {
			value = 7
		}
		if _, err := s.db.ExecContext(ctx, `
			UPDATE goals SET target_per_week = $3, updated_at = now()
			WHERE id = $1 AND patient_id = $2
		`, goalID, patientID, value); err != nil {
			return Goal{}, err
		}
	}
	if isActive != nil {
		if _, err := s.db.ExecContext(ctx, `
			UPDATE goals SET is_active = $3, updated_at = now()
			WHERE id = $1 AND patient_id = $2
		`, goalID, patientID, *isActive); err != nil {
			return Goal{}, err
		}
	}
	// Ambil ulang hasil akhir.
	rows, err := s.ListGoals(ctx, patientID, true)
	if err != nil {
		return Goal{}, err
	}
	for _, g := range rows {
		if g.ID == goalID {
			return g, nil
		}
	}
	return Goal{}, sql.ErrNoRows
}

func (s *Store) DeleteGoal(ctx context.Context, patientID, goalID string) error {
	patientID = strings.TrimSpace(patientID)
	goalID = strings.TrimSpace(goalID)
	if patientID == "" || goalID == "" {
		return errors.New("patient_id and goal_id are required")
	}
	res, err := s.db.ExecContext(ctx, `
		DELETE FROM goals WHERE id = $1 AND patient_id = $2
	`, goalID, patientID)
	if err != nil {
		return err
	}
	aff, _ := res.RowsAffected()
	if aff == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// LogHabit mencatat (upsert) satu habit untuk tanggal tertentu.
// done=false menghapus centang hari itu (tetap tersimpan sebagai log).
func (s *Store) LogHabit(ctx context.Context, patientID, goalID, loggedOn string, done bool) (HabitLog, error) {
	patientID = strings.TrimSpace(patientID)
	goalID = strings.TrimSpace(goalID)
	if patientID == "" || goalID == "" {
		return HabitLog{}, errors.New("patient_id and goal_id are required")
	}
	if strings.TrimSpace(loggedOn) == "" {
		loggedOn = time.Now().Format("2006-01-02")
	}
	if _, err := time.Parse("2006-01-02", loggedOn); err != nil {
		return HabitLog{}, errors.New("logged_on must be YYYY-MM-DD")
	}
	// Pastikan goal milik pasien ini.
	var owner string
	if err := s.db.QueryRowContext(ctx, `SELECT patient_id FROM goals WHERE id = $1`, goalID).Scan(&owner); err != nil {
		return HabitLog{}, err
	}
	if owner != patientID {
		return HabitLog{}, sql.ErrNoRows
	}
	var log HabitLog
	err := s.db.QueryRowContext(ctx, `
		INSERT INTO habit_logs (goal_id, patient_id, logged_date, done)
		VALUES ($1, $2, $3::date, $4)
		ON CONFLICT (goal_id, logged_date)
		DO UPDATE SET done = EXCLUDED.done
		RETURNING id, goal_id, patient_id, logged_date::text, done, created_at
	`, goalID, patientID, loggedOn, done).
		Scan(&log.ID, &log.GoalID, &log.PatientID, &log.LoggedOn, &log.Done, &log.CreatedAt)
	return log, err
}

// ListHabitLogs mengembalikan riwayat log habit pasien pada rentang tanggal.
func (s *Store) ListHabitLogs(ctx context.Context, patientID, from, to string) ([]HabitLog, error) {
	patientID = strings.TrimSpace(patientID)
	if patientID == "" {
		return nil, errors.New("patient_id is required")
	}
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, goal_id, patient_id, logged_date::text, done, created_at
		FROM habit_logs
		WHERE patient_id = $1
		  AND ($2 = '' OR logged_date >= $2::date)
		  AND ($3 = '' OR logged_date <= $3::date)
		ORDER BY logged_date DESC
		LIMIT 400
	`, patientID, strings.TrimSpace(from), strings.TrimSpace(to))
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var out []HabitLog
	for rows.Next() {
		var l HabitLog
		if err := rows.Scan(&l.ID, &l.GoalID, &l.PatientID, &l.LoggedOn, &l.Done, &l.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, rows.Err()
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
func (s *Store) ListTherapySubmissions(ctx context.Context, userID string, sharedOnly bool) ([]TherapySubmission, error) {
	userID = strings.TrimSpace(userID)
	if userID == "" {
		return nil, errors.New("user_id is required")
	}
	query := `
		SELECT id, patient_id, module_id, title, answers, summary,
		       shared_with_professional_id, shared_at, created_at, updated_at
		FROM therapy_submissions
		WHERE patient_id = $1
		ORDER BY created_at DESC
		LIMIT 100
	`
	if sharedOnly {
		query = `
			SELECT id, patient_id, module_id, title, answers, summary,
			       shared_with_professional_id, shared_at, created_at, updated_at
			FROM therapy_submissions
			WHERE shared_with_professional_id = $1
			ORDER BY created_at DESC
			LIMIT 100
		`
	}
	rows, err := s.db.QueryContext(ctx, query, userID)
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
			WHERE id = $1 AND shared_with_professional_id = $2
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
