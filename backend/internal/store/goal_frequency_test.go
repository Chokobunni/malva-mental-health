package store

import (
	"context"
	"sync"
	"testing"

	"malva/backend/internal/clock"
)

func TestFrequencySessionActionsResetProgressAndKeepLegacyCounts(t *testing.T) {
	for _, method := range []string{"yes_no", "numeric", "checklist"} {
		t.Run(method, func(t *testing.T) {
			s, db := openGoalTestStore(t)
			ctx := context.Background()
			owner := insertTestUser(t, db, ctx, "patient", "Frequency", "frequency")
			t.Cleanup(func() { cleanupTestUsers(t, db, owner) })
			now := clock.Now()
			today := now.Format("2006-01-02")
			quota := 5
			d := validGoalDetails()
			d.Method, d.Recurrence, d.WeeklyTarget, d.Target = method, "weekly", &quota, 7
			d.StartDate = now.AddDate(0, 0, -30).Format("2006-01-02")
			d.Steps = []GoalStep{{ID: "a", Label: "A"}, {ID: "b", Label: "B"}}
			g, err := s.CreateGoal(ctx, UpsertGoalParams{PatientID: owner, Title: method, Details: d})
			if err != nil {
				t.Fatal(err)
			}
			value, steps := 6, []string{"a"}
			if method == "yes_no" {
				value = 0
			}
			partial, err := s.LogHabit(ctx, owner, g.ID, today, false, HabitProgressPatch{Value: &value, CompletedStepIDs: &steps})
			if err != nil {
				t.Fatal(err)
			}
			if method != "yes_no" && partial.Done {
				t.Fatal("partial progress credited a session")
			}
			if method != "yes_no" {
				full, allSteps := 7, []string{"a", "b"}
				log, err := s.LogHabit(ctx, owner, g.ID, today, false, HabitProgressPatch{Value: &full, CompletedStepIDs: &allSteps})
				if err != nil || log.Done || log.Sessions != 0 {
					t.Fatalf("full progress must wait for Ya: %+v err=%v", log, err)
				}
			}
			for _, key := range []string{"complete-1", "complete-1", "complete-2"} {
				log, err := s.LogHabit(ctx, owner, g.ID, today, true, HabitProgressPatch{SessionAction: "complete", IdempotencyKey: key})
				if err != nil {
					t.Fatal(err)
				}
				if len(log.CompletedStepIDs) != 0 || (method != "yes_no" && log.Value != 0) {
					t.Fatalf("progress not reset: %+v", log)
				}
			}
			goals, err := s.ListGoals(ctx, owner, false, today)
			if err != nil || len(goals) != 1 || goals[0].DoneThisWeek != 2 || goals[0].TodaySessions != 2 {
				t.Fatalf("summary=%+v err=%v", goals, err)
			}
			value = 3
			if method == "yes_no" {
				value = 2
			}
			if _, err := s.LogHabit(ctx, owner, g.ID, today, false, HabitProgressPatch{Value: &value, CompletedStepIDs: &steps}); err != nil {
				t.Fatal(err)
			}
			for _, key := range []string{"undo-1", "undo-1"} {
				if _, err := s.LogHabit(ctx, owner, g.ID, today, false, HabitProgressPatch{SessionAction: "undo", IdempotencyKey: key}); err != nil {
					t.Fatal(err)
				}
			}
			goals, err = s.ListGoals(ctx, owner, false, today)
			if err != nil || goals[0].DoneThisWeek != 1 {
				t.Fatalf("undo summary=%+v err=%v", goals, err)
			}
			if method != "yes_no" && (goals[0].TodayValue != 3 || len(goals[0].TodayCompletedStepIDs) != 1) {
				t.Fatalf("undo destroyed partial: %+v", goals[0])
			}
			logs, err := s.ListHabitLogs(ctx, owner, today, today)
			if err != nil || len(logs) != 1 || logs[0].Sessions != 1 || len(logs[0].CompletedStepIDs) != 1 {
				t.Fatalf("public logs=%+v err=%v", logs, err)
			}
		})
	}
}

func TestFrequencyConcurrentCompletionAndLegacyEncoding(t *testing.T) {
	s, db := openGoalTestStore(t)
	ctx := context.Background()
	owner := insertTestUser(t, db, ctx, "patient", "Concurrent", "frequency-concurrent")
	t.Cleanup(func() { cleanupTestUsers(t, db, owner) })
	today := clock.Now().Format("2006-01-02")
	quota := 5
	d := validGoalDetails()
	d.Method, d.Recurrence, d.WeeklyTarget, d.Target = "yes_no", "weekly", &quota, 7
	d.StartDate = today
	g, err := s.CreateGoal(ctx, UpsertGoalParams{PatientID: owner, Title: "legacy", Details: d})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = db.Exec(`INSERT INTO habit_logs(goal_id,patient_id,logged_date,done,value) VALUES($1,$2,$3,true,-4)`, g.ID, owner, today); err != nil {
		t.Fatal(err)
	}
	var group sync.WaitGroup
	errors := make(chan error, 8)
	for range 8 {
		group.Add(1)
		go func() {
			defer group.Done()
			_, err := s.LogHabit(ctx, owner, g.ID, today, true, HabitProgressPatch{SessionAction: "complete", IdempotencyKey: "shared-intent"})
			errors <- err
		}()
	}
	group.Wait()
	close(errors)
	for err := range errors {
		if err != nil {
			t.Fatal(err)
		}
	}
	goals, err := s.ListGoals(ctx, owner, false, today)
	if err != nil || goals[0].DoneThisWeek != 4 {
		t.Fatalf("duplicate or lost session: %+v %v", goals, err)
	}
	if _, err = s.LogHabit(ctx, owner, g.ID, today, false, HabitProgressPatch{SessionAction: "undo", IdempotencyKey: "shared-intent"}); err == nil {
		t.Fatal("key reused for a different action")
	}
	d.Method = "numeric"
	if _, err = s.UpdateGoal(ctx, owner, g.ID, "", "", nil, nil, d); err != nil {
		t.Fatal(err)
	}
	goals, err = s.ListGoals(ctx, owner, false, today)
	if err != nil || goals[0].DoneThisWeek != 4 || goals[0].TodayValue != 0 {
		t.Fatalf("legacy count reinterpreted as numeric amount: %+v %v", goals, err)
	}
	if _, err = s.LogHabit(ctx, owner, g.ID, today, false, HabitProgressPatch{SessionAction: "undo", IdempotencyKey: "undo-after-edit"}); err != nil {
		t.Fatal(err)
	}
	goals, err = s.ListGoals(ctx, owner, false, today)
	if err != nil || goals[0].DoneThisWeek != 3 || goals[0].TodayValue != 0 {
		t.Fatalf("method edit lost count: %+v %v", goals, err)
	}
	d.Method = "yes_no"
	if _, err = s.UpdateGoal(ctx, owner, g.ID, "", "", nil, nil, d); err != nil {
		t.Fatal(err)
	}
	goals, err = s.ListGoals(ctx, owner, false, today)
	if err != nil || goals[0].DoneThisWeek != 3 || goals[0].TodayValue != 3 || goals[0].TodaySessions != 3 {
		t.Fatalf("reverse method edit collapsed count: %+v %v", goals, err)
	}
}

func TestFrequencyUndoFindsLatestDayAndStopsAtWIBWeek(t *testing.T) {
	s, db := openGoalTestStore(t)
	ctx := context.Background()
	owner := insertTestUser(t, db, ctx, "patient", "Undo", "frequency-undo")
	t.Cleanup(func() { cleanupTestUsers(t, db, owner) })
	now := clock.Now()
	monday := goalDay(now).AddDate(0, 0, 1-goalISOWeekday(now))
	quota := 5
	d := validGoalDetails()
	d.Method, d.Recurrence, d.WeeklyTarget, d.Target = "numeric", "weekly", &quota, 7
	d.StartDate = monday.AddDate(0, 0, -14).Format("2006-01-02")
	d.LockPast = false
	g, err := s.CreateGoal(ctx, UpsertGoalParams{PatientID: owner, Title: "Read", Details: d})
	if err != nil {
		t.Fatal(err)
	}
	priorWeek := monday.AddDate(0, 0, -1).Format("2006-01-02")
	first := monday.Format("2006-01-02")
	for _, date := range []string{priorWeek, first} {
		if _, err := db.Exec(`INSERT INTO habit_logs(goal_id,patient_id,logged_date,done,value,completed_step_ids) VALUES($1,$2,$3,true,7,'[]')`, g.ID, owner, date); err != nil {
			t.Fatal(err)
		}
	}
	today := now.Format("2006-01-02")
	log, err := s.LogHabit(ctx, owner, g.ID, today, false, HabitProgressPatch{SessionAction: "undo", IdempotencyKey: "undo-week"})
	if err != nil || log.LoggedOn != first || log.Sessions != 0 {
		t.Fatalf("undo=%+v err=%v", log, err)
	}
	if _, err = s.LogHabit(ctx, owner, g.ID, today, false, HabitProgressPatch{SessionAction: "undo", IdempotencyKey: "undo-empty"}); err == nil {
		t.Fatal("undo crossed week boundary")
	}
	var amount int
	if err = db.QueryRow(`SELECT value FROM habit_logs WHERE goal_id=$1 AND logged_date=$2`, g.ID, priorWeek).Scan(&amount); err != nil || amount != 7 {
		t.Fatalf("prior week value=%d err=%v", amount, err)
	}
}
