package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"reflect"
	"testing"

	"malva/backend/internal/clock"
)

func TestChecklistExtraProgressPersistsWithoutScheduledCredit(t *testing.T) {
	s, db := openGoalTestStore(t)
	ctx := context.Background()
	owner := insertTestUser(t, db, ctx, "patient", "QA checklist", "sync-checklist")
	other := insertTestUser(t, db, ctx, "patient", "QA other", "sync-other")
	t.Cleanup(func() { cleanupTestUsers(t, db, owner, other) })
	now := goalDay(clock.Now())
	today := now.Format("2006-01-02")
	for _, recurrence := range []string{"weekly", "daily", "monthly"} {
		t.Run(recurrence, func(t *testing.T) {
			d := validGoalDetails()
			d.Method = "checklist"
			d.StartDate = now.AddDate(0, 0, -1).Format("2006-01-02")
			d.Recurrence, d.Interval = recurrence, 2
			d.Weekdays = []int{(goalISOWeekday(now) % 7) + 1}
			if recurrence == "monthly" {
				d.Interval = 1
			}
			d.Steps = []GoalStep{{ID: "a", Label: "A"}, {ID: "b", Label: "B"}}
			if goalDue(d, now) {
				t.Fatal("fixture must be outside schedule")
			}
			g, err := s.CreateGoal(ctx, UpsertGoalParams{PatientID: owner, Title: "Checklist", Details: d})
			if err != nil {
				t.Fatal(err)
			}
			for _, ids := range [][]string{{"a"}, {"a", "b"}, {"b"}, {}, {"a"}} {
				l, err := s.LogHabit(ctx, owner, g.ID, today, false, HabitProgressPatch{CompletedStepIDs: &ids})
				if err != nil {
					t.Fatal(err)
				}
				if l.Done != (len(ids) == 2) || !reflect.DeepEqual(l.CompletedStepIDs, ids) {
					t.Fatalf("log=%+v want=%v", l, ids)
				}
				// Inspect the actual row before independently reading the selected-date projection.
				var stored []byte
				var done bool
				if err := db.QueryRow(`SELECT completed_step_ids,done FROM habit_logs WHERE goal_id=$1 AND logged_date=$2::date`, g.ID, today).Scan(&stored, &done); err != nil {
					t.Fatal(err)
				}
				var got []string
				if err := json.Unmarshal(stored, &got); err != nil {
					t.Fatal(err)
				}
				if !reflect.DeepEqual(got, ids) || done != l.Done {
					t.Fatalf("persisted=%s done=%v", stored, done)
				}
				listed, err := s.ListGoals(ctx, owner, false, today)
				if err != nil {
					t.Fatal(err)
				}
				var found *Goal
				for i := range listed {
					if listed[i].ID == g.ID {
						found = &listed[i]
					}
				}
				if found == nil || found.IsDue || found.DoneThisWeek != 0 || len(found.CompletedWeekdays) != 0 || found.StreakDays != 0 || found.FailedToday || !reflect.DeepEqual(found.TodayCompletedStepIDs, ids) {
					t.Fatalf("summary=%+v", found)
				}
			}
			if _, err := s.LogHabit(ctx, other, g.ID, today, false); !errors.Is(err, sql.ErrNoRows) {
				t.Fatalf("foreign err=%v", err)
			}
			bad := []string{"foreign-step"}
			if _, err := s.LogHabit(ctx, owner, g.ID, today, false, HabitProgressPatch{CompletedStepIDs: &bad}); err == nil {
				t.Fatal("accepted foreign step")
			}
			for _, date := range []string{now.AddDate(0, 0, 1).Format("2006-01-02"), now.AddDate(0, 0, -2).Format("2006-01-02")} {
				if _, err := s.LogHabit(ctx, owner, g.ID, date, false); err == nil {
					t.Fatalf("accepted out-of-range %s", date)
				}
			}
		})
	}
}

func TestChecklistExtraProgressRetainsLockedHistoryAndInactiveGuards(t *testing.T) {
	s, db := openGoalTestStore(t)
	ctx := context.Background()
	owner := insertTestUser(t, db, ctx, "patient", "QA guard", "sync-guard")
	t.Cleanup(func() { cleanupTestUsers(t, db, owner) })
	now := goalDay(clock.Now())
	d := validGoalDetails()
	d.Method = "checklist"
	d.StartDate = now.AddDate(0, 0, -10).Format("2006-01-02")
	d.Steps = []GoalStep{{ID: "a", Label: "A"}}
	d.LockPast = true
	g, err := s.CreateGoal(ctx, UpsertGoalParams{PatientID: owner, Title: "Guard", Details: d})
	if err != nil {
		t.Fatal(err)
	}
	ids := []string{"a"}
	if _, err := s.LogHabit(ctx, owner, g.ID, now.AddDate(0, 0, -2).Format("2006-01-02"), false, HabitProgressPatch{CompletedStepIDs: &ids}); err == nil {
		t.Fatal("accepted locked history")
	}
	active := false
	if _, err := s.UpdateGoal(ctx, owner, g.ID, "", "", nil, &active); err != nil {
		t.Fatal(err)
	}
	if _, err := s.LogHabit(ctx, owner, g.ID, now.Format("2006-01-02"), false, HabitProgressPatch{CompletedStepIDs: &ids}); err == nil {
		t.Fatal("accepted inactive goal progress")
	}
}
