package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"sort"
	"strings"
	"time"

	"malva/backend/internal/clock"
)

type UpsertGoalParams struct {
	ID            string
	PatientID     string
	Title         string
	Category      string
	TargetPerWeek int
	IsActive      *bool
	SortOrder     *int
	Details       *GoalDetails
}

const goalColumns = `id, patient_id, title, category, target_per_week,
 is_active, sort_order, created_at, updated_at, details`

type goalScanner interface{ Scan(...any) error }

func scanGoal(row goalScanner) (Goal, error) {
	var g Goal
	var raw []byte
	err := row.Scan(&g.ID, &g.PatientID, &g.Title, &g.Category, &g.TargetPerWeek, &g.IsActive, &g.SortOrder, &g.CreatedAt, &g.UpdatedAt, &raw)
	if err != nil {
		return g, err
	}
	if len(raw) > 0 {
		if err := json.Unmarshal(raw, &g.Details); err != nil {
			return Goal{}, err
		}
	}
	g.TodayCompletedStepIDs = []string{}
	g.CompletedWeekdays = []int{}
	return g, nil
}

func goalDetailsJSON(d *GoalDetails) (any, error) {
	if err := ValidateGoalDetails(d); err != nil {
		return nil, err
	}
	if d == nil {
		return nil, nil
	}
	// Keep arrays stable in persisted/API JSON instead of emitting null.
	normalized := *d
	if normalized.Steps == nil {
		normalized.Steps = []GoalStep{}
	}
	// Older clients must not infer weekday reminders for schedules they cannot read.
	if normalized.Weekdays == nil || normalized.Recurrence == "monthly" || normalized.WeeklyTarget != nil {
		normalized.Weekdays = []int{}
	}
	if normalized.Reminders == nil {
		normalized.Reminders = []int{}
	}
	raw, err := json.Marshal(normalized)
	if err != nil {
		return nil, err
	}
	return string(raw), nil
}

func summarizeGoal(g *Goal, logs []HabitLog, on, today time.Time) {
	g.IsDue = goalDue(g.Details, on)
	g.TodayCompletedStepIDs = []string{}
	g.CompletedWeekdays = []int{}
	selected := on.Format("2006-01-02")
	monday := on.AddDate(0, 0, 1-goalISOWeekday(on)).Format("2006-01-02")
	found := false
	for _, l := range logs {
		done := goalLogDone(g.Details, l)
		date, err := goalDate(l.LoggedOn)
		if done && err == nil && goalDue(g.Details, date) && l.LoggedOn >= monday && l.LoggedOn <= selected {
			g.CompletedWeekdays = append(g.CompletedWeekdays, goalISOWeekday(date))
			g.DoneThisWeek++
			date := l.LoggedOn
			if g.LastLoggedOn == nil || date > *g.LastLoggedOn {
				g.LastLoggedOn = &date
			}
		}
		if l.LoggedOn == selected {
			found = true
			g.DoneToday = done
			g.TodayValue = l.Value
			g.TodayCompletedStepIDs = append([]string{}, l.CompletedStepIDs...)
		}
	}
	sort.Ints(g.CompletedWeekdays)
	if g.IsDue {
		g.FailedToday = (found && !g.DoneToday) || (!found && g.Details != nil && g.Details.AutoFail && (g.Details.Recurrence != "weekly" || g.Details.WeeklyTarget == nil) && on.Before(goalDay(today)))
	}
	g.StreakDays = goalStreak(g.Details, logs, on, today)
}

// ListGoals accepts an optional selected WIB calendar date. The read snapshot
// keeps configuration and derived progress consistent during concurrent edits.
func (s *Store) ListGoals(ctx context.Context, patientID string, includeInactive bool, selected ...string) ([]Goal, error) {
	patientID = strings.TrimSpace(patientID)
	if patientID == "" {
		return nil, errors.New("patient_id is required")
	}
	today := clock.Now()
	on := goalDay(today)
	if len(selected) > 0 && strings.TrimSpace(selected[0]) != "" {
		var err error
		on, err = goalDate(strings.TrimSpace(selected[0]))
		if err != nil {
			return nil, err
		}
	}
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelRepeatableRead, ReadOnly: true})
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }()
	rows, err := tx.QueryContext(ctx, `SELECT `+goalColumns+` FROM goals WHERE patient_id=$1 AND ($2 OR is_active) ORDER BY sort_order,created_at`, patientID, includeInactive)
	if err != nil {
		return nil, err
	}
	out := []Goal{}
	for rows.Next() {
		g, err := scanGoal(rows)
		if err != nil {
			_ = rows.Close()
			return nil, err
		}
		out = append(out, g)
	}
	err = rows.Err()
	_ = rows.Close()
	if err != nil {
		return nil, err
	}
	logs := map[string][]HabitLog{}
	if len(out) > 0 {
		history, err := tx.QueryContext(ctx, `SELECT id,goal_id,patient_id,logged_date::text,done,created_at,value,completed_step_ids FROM habit_logs WHERE patient_id=$1 AND logged_date <= $2::date ORDER BY logged_date DESC`, patientID, on.Format("2006-01-02"))
		if err != nil {
			return nil, err
		}
		for history.Next() {
			l, err := scanHabitLog(history)
			if err != nil {
				_ = history.Close()
				return nil, err
			}
			logs[l.GoalID] = append(logs[l.GoalID], l)
		}
		err = history.Err()
		_ = history.Close()
		if err != nil {
			return nil, err
		}
	}
	for i := range out {
		summarizeGoal(&out[i], logs[out[i].ID], on, today)
	}
	if err := tx.Commit(); err != nil {
		return nil, err
	}
	return out, nil
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
	details, err := goalDetailsJSON(p.Details)
	if err != nil {
		return Goal{}, err
	}
	active := true
	if p.IsActive != nil {
		active = *p.IsActive
	}
	order := 0
	if p.SortOrder != nil {
		order = *p.SortOrder
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Goal{}, err
	}
	defer func() { _ = tx.Rollback() }()
	g, err := scanGoal(tx.QueryRowContext(ctx, `
 INSERT INTO goals(patient_id,title,category,target_per_week,id,details,is_active,sort_order)
 VALUES($1,$2,$3,$4,COALESCE(NULLIF($5,'')::uuid,gen_random_uuid()),$6::jsonb,$7,$8)
 ON CONFLICT(id) DO UPDATE SET id=goals.id
 WHERE goals.patient_id=EXCLUDED.patient_id AND goals.title=EXCLUDED.title
 AND goals.category=EXCLUDED.category AND goals.target_per_week=EXCLUDED.target_per_week
 AND goals.details IS NOT DISTINCT FROM EXCLUDED.details
 AND goals.is_active=EXCLUDED.is_active AND goals.sort_order=EXCLUDED.sort_order
 RETURNING `+goalColumns, p.PatientID, p.Title, p.Category, p.TargetPerWeek, p.ID, details, active, order))
	if err != nil {
		return Goal{}, err
	}
	return completeGoalWrite(ctx, tx, g)
}

// One owned UPDATE makes all fields atomic. A nil extension preserves details
// for older clients and for unrelated partial updates.
func (s *Store) UpdateGoal(ctx context.Context, patientID, goalID, title, category string, targetPerWeek *int, isActive *bool, details ...*GoalDetails) (Goal, error) {
	patientID = strings.TrimSpace(patientID)
	goalID = strings.TrimSpace(goalID)
	if patientID == "" || goalID == "" {
		return Goal{}, errors.New("patient_id and goal_id are required")
	}
	var raw any
	var err error
	if len(details) > 0 && details[0] != nil {
		raw, err = goalDetailsJSON(details[0])
		if err != nil {
			return Goal{}, err
		}
	}
	if targetPerWeek != nil {
		value := *targetPerWeek
		if value < 1 {
			value = 1
		}
		if value > 7 {
			value = 7
		}
		targetPerWeek = &value
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Goal{}, err
	}
	defer func() { _ = tx.Rollback() }()
	g, err := scanGoal(tx.QueryRowContext(ctx, `
 UPDATE goals SET title=COALESCE(NULLIF($3,''),title),category=COALESCE(NULLIF($4,''),category),
 target_per_week=COALESCE($5,target_per_week),is_active=COALESCE($6,is_active),
 details=COALESCE($7::jsonb,details),updated_at=$8
 WHERE id=$1 AND patient_id=$2 RETURNING `+goalColumns, goalID, patientID, strings.TrimSpace(title), strings.TrimSpace(category), targetPerWeek, isActive, raw, clock.Now()))
	if err != nil {
		return Goal{}, err
	}
	return completeGoalWrite(ctx, tx, g)
}

// The write still owns the goal row while its actual history is projected.
// Returning a zero summary after an edit would hide progress in the client.
func completeGoalWrite(ctx context.Context, tx *sql.Tx, g Goal) (Goal, error) {
	now := clock.Now()
	rows, err := tx.QueryContext(ctx, `SELECT id,goal_id,patient_id,logged_date::text,done,created_at,value,completed_step_ids FROM habit_logs WHERE goal_id=$1 AND patient_id=$2 AND logged_date <= $3::date ORDER BY logged_date DESC`, g.ID, g.PatientID, now.Format("2006-01-02"))
	if err != nil {
		return Goal{}, err
	}
	logs := []HabitLog{}
	for rows.Next() {
		l, err := scanHabitLog(rows)
		if err != nil {
			_ = rows.Close()
			return Goal{}, err
		}
		logs = append(logs, l)
	}
	err = rows.Err()
	_ = rows.Close()
	if err != nil {
		return Goal{}, err
	}
	summarizeGoal(&g, logs, goalDay(now), now)
	if err := tx.Commit(); err != nil {
		return Goal{}, err
	}
	return g, nil
}

func (s *Store) DeleteGoal(ctx context.Context, patientID, goalID string) error {
	patientID = strings.TrimSpace(patientID)
	goalID = strings.TrimSpace(goalID)
	if patientID == "" || goalID == "" {
		return errors.New("patient_id and goal_id are required")
	}
	result, err := s.db.ExecContext(ctx, `DELETE FROM goals WHERE id=$1 AND patient_id=$2`, goalID, patientID)
	if err != nil {
		return err
	}
	count, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if count == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func scanHabitLog(row goalScanner) (HabitLog, error) {
	var l HabitLog
	var raw []byte
	err := row.Scan(&l.ID, &l.GoalID, &l.PatientID, &l.LoggedOn, &l.Done, &l.CreatedAt, &l.Value, &raw)
	if err != nil {
		return l, err
	}
	if len(raw) > 0 {
		if err := json.Unmarshal(raw, &l.CompletedStepIDs); err != nil {
			return HabitLog{}, err
		}
	}
	if l.CompletedStepIDs == nil {
		l.CompletedStepIDs = []string{}
	}
	return l, nil
}

func (s *Store) LogHabit(ctx context.Context, patientID, goalID, loggedOn string, done bool, progress ...HabitProgressPatch) (HabitLog, error) {
	patientID = strings.TrimSpace(patientID)
	goalID = strings.TrimSpace(goalID)
	if patientID == "" || goalID == "" {
		return HabitLog{}, errors.New("patient_id and goal_id are required")
	}
	now := clock.Now()
	loggedOn = strings.TrimSpace(loggedOn)
	if loggedOn == "" {
		loggedOn = now.Format("2006-01-02")
	}
	on, err := goalDate(loggedOn)
	if err != nil {
		return HabitLog{}, err
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return HabitLog{}, err
	}
	defer func() { _ = tx.Rollback() }()
	// This lock serializes log patches with goal edits/deletes and with each other,
	// so ownership, schedule checks and independent progress fields cannot race.
	g, err := scanGoal(tx.QueryRowContext(ctx, `SELECT `+goalColumns+` FROM goals WHERE id=$1 AND patient_id=$2 FOR UPDATE`, goalID, patientID))
	if err != nil {
		return HabitLog{}, err
	}
	if !g.IsActive {
		return HabitLog{}, errors.New("habit nonaktif tidak dapat dicatat")
	}
	if err := validateHabitDate(g.Details, on, now); err != nil {
		return HabitLog{}, err
	}
	current, err := scanHabitLog(tx.QueryRowContext(ctx, `SELECT id,goal_id,patient_id,logged_date::text,done,created_at,value,completed_step_ids FROM habit_logs WHERE goal_id=$1 AND patient_id=$2 AND logged_date=$3::date`, goalID, patientID, loggedOn))
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return HabitLog{}, err
	}
	patch := HabitProgressPatch{}
	if len(progress) > 0 {
		patch = progress[0]
	}
	current, err = applyHabitProgress(g.Details, current, done, patch)
	if err != nil {
		return HabitLog{}, err
	}
	ids, err := json.Marshal(current.CompletedStepIDs)
	if err != nil {
		return HabitLog{}, err
	}
	l, err := scanHabitLog(tx.QueryRowContext(ctx, `
 INSERT INTO habit_logs(goal_id,patient_id,logged_date,done,value,completed_step_ids)
 VALUES($1,$2,$3::date,$4,$5,$6::jsonb)
 ON CONFLICT(goal_id,logged_date) DO UPDATE SET done=EXCLUDED.done,value=EXCLUDED.value,completed_step_ids=EXCLUDED.completed_step_ids
 WHERE habit_logs.patient_id=EXCLUDED.patient_id
 RETURNING id,goal_id,patient_id,logged_date::text,done,created_at,value,completed_step_ids`, goalID, patientID, loggedOn, current.Done, current.Value, string(ids)))
	if err != nil {
		return HabitLog{}, err
	}
	if err := tx.Commit(); err != nil {
		return HabitLog{}, err
	}
	return l, nil
}

func (s *Store) ListHabitLogs(ctx context.Context, patientID, from, to string) ([]HabitLog, error) {
	patientID = strings.TrimSpace(patientID)
	from = strings.TrimSpace(from)
	to = strings.TrimSpace(to)
	if patientID == "" {
		return nil, errors.New("patient_id is required")
	}
	for _, date := range []string{from, to} {
		if date != "" {
			if _, err := goalDate(date); err != nil {
				return nil, err
			}
		}
	}
	// NULLIF avoids trying to cast an empty bound before PostgreSQL evaluates OR.
	rows, err := s.db.QueryContext(ctx, `
 SELECT l.id,l.goal_id,l.patient_id,l.logged_date::text,l.done,l.created_at,l.value,l.completed_step_ids
 FROM habit_logs l JOIN goals g ON g.id=l.goal_id AND g.patient_id=l.patient_id
 WHERE l.patient_id=$1 AND (NULLIF($2,'')::date IS NULL OR l.logged_date>=NULLIF($2,'')::date)
 AND (NULLIF($3,'')::date IS NULL OR l.logged_date<=NULLIF($3,'')::date)
 ORDER BY l.logged_date DESC LIMIT 400`, patientID, from, to)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	out := []HabitLog{}
	for rows.Next() {
		l, err := scanHabitLog(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, l)
	}
	return out, rows.Err()
}
