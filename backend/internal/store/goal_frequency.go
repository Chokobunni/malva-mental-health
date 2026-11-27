package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"time"
)

func publicHabitLog(d *GoalDetails, log HabitLog) HabitLog {
	log.Sessions = goalLogSessions(d, log)
	log.Done = goalLogDone(d, log)
	log.Value = goalPublicValue(d, log)
	log.CompletedStepIDs = goalPublicSteps(log.CompletedStepIDs)
	return log
}

// The caller owns the goal lock, serializing replay checks and session actions.
func applyGoalSessionAction(ctx context.Context, tx *sql.Tx, goal Goal, on time.Time,
	current HabitLog, patch HabitProgressPatch) (HabitLog, error) {
	if !frequencyGoal(goal.Details) {
		return HabitLog{}, errors.New("aksi sesi hanya untuk Target Frekuensi")
	}
	if patch.SessionAction != "complete" && patch.SessionAction != "undo" {
		return HabitLog{}, errors.New("session_action harus complete atau undo")
	}
	if patch.Value != nil || patch.CompletedStepIDs != nil {
		return HabitLog{}, errors.New("aksi sesi tidak dapat digabung dengan perubahan progres")
	}
	if len(patch.IdempotencyKey) == 0 || len(patch.IdempotencyKey) > 128 {
		return HabitLog{}, errors.New("aksi sesi memerlukan Idempotency-Key maksimal 128 karakter")
	}
	if !goalDue(goal.Details, on) {
		return HabitLog{}, errors.New("aksi sesi memerlukan tanggal terjadwal")
	}
	if patch.SessionAction == "undo" {
		monday := on.AddDate(0, 0, 1-goalISOWeekday(on))
		rows, err := tx.QueryContext(ctx, `SELECT id,goal_id,patient_id,logged_date::text,done,created_at,value,completed_step_ids
			FROM habit_logs WHERE goal_id=$1 AND patient_id=$2 AND logged_date >= $3::date AND logged_date <= $4::date
			ORDER BY logged_date DESC`, goal.ID, goal.PatientID, monday.Format("2006-01-02"), on.Format("2006-01-02"))
		if err != nil {
			return HabitLog{}, err
		}
		var found bool
		for rows.Next() {
			log, err := scanHabitLog(rows)
			if err != nil {
				_ = rows.Close()
				return HabitLog{}, err
			}
			date, err := goalDate(log.LoggedOn)
			if err == nil && goalDue(goal.Details, date) && goalLogSessions(goal.Details, log) > 0 {
				current, found = log, true
				break
			}
		}
		err = rows.Err()
		_ = rows.Close()
		if err != nil {
			return HabitLog{}, err
		}
		if !found {
			return HabitLog{}, errors.New("belum ada sesi pada minggu ini untuk dibatalkan")
		}
	}
	count := goalLogSessions(goal.Details, current)
	if patch.SessionAction == "complete" {
		if count >= 1000000 {
			return HabitLog{}, errors.New("maksimal 1000000 sesi per hari")
		}
		count++
		current.Value, current.CompletedStepIDs = 0, []string{}
	} else {
		count--
	}
	current.Done = count > 0
	if countedWeeklyGoal(goal.Details) {
		current.Value = -count - 1
		current.CompletedStepIDs = goalPublicSteps(current.CompletedStepIDs)
	} else {
		current.CompletedStepIDs = withGoalSessions(current.CompletedStepIDs, count)
	}
	return current, nil
}

type habitSessionReceipt struct {
	GoalID string   `json:"goal_id"`
	Date   string   `json:"date"`
	Action string   `json:"session_action"`
	Log    HabitLog `json:"log"`
}

func readHabitSessionReceipt(ctx context.Context, tx *sql.Tx, goal Goal, date string, patch HabitProgressPatch) (*HabitLog, error) {
	if patch.SessionAction == "" || patch.IdempotencyKey == "" {
		return nil, nil
	}
	id := ClinicalRetryID("habit-session", goal.PatientID, patch.IdempotencyKey)
	var raw []byte
	err := tx.QueryRowContext(ctx, `SELECT metadata FROM audit_logs WHERE id=$1 AND actor_id=$2 AND action='habit.session'`, id, goal.PatientID).Scan(&raw)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	var receipt habitSessionReceipt
	if err = json.Unmarshal(raw, &receipt); err != nil {
		return nil, err
	}
	if receipt.GoalID != goal.ID || receipt.Date != date || receipt.Action != patch.SessionAction || patch.Value != nil || patch.CompletedStepIDs != nil {
		return nil, errors.New("Idempotency-Key telah digunakan untuk aksi sesi lain")
	}
	return &receipt.Log, nil
}

func saveHabitSessionReceipt(ctx context.Context, tx *sql.Tx, goal Goal, date string, patch HabitProgressPatch, log HabitLog) error {
	if patch.SessionAction == "" {
		return nil
	}
	raw, err := json.Marshal(habitSessionReceipt{GoalID: goal.ID, Date: date, Action: patch.SessionAction, Log: log})
	if err != nil {
		return err
	}
	_, err = tx.ExecContext(ctx, `INSERT INTO audit_logs(id,actor_id,patient_id,action,entity_type,entity_id,metadata)
		VALUES($1,$2,$2,'habit.session','goal',$3,$4::jsonb)`,
		ClinicalRetryID("habit-session", goal.PatientID, patch.IdempotencyKey), goal.PatientID, goal.ID, string(raw))
	return err
}
