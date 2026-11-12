package store

import (
	"context"
	"database/sql"
	"errors"
	"os"
	"sync"
	"testing"

	"malva/backend/internal/clock"
)

func openGoalTestStore(t *testing.T) (*Store, *sql.DB) {
	t.Helper()
	dsn := testDatabaseDSN(t)
	db, err := OpenSQL(dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	if err := db.PingContext(context.Background()); err != nil {
		t.Fatal("Postgres QA connection unavailable")
	}
	return New(db), db
}

func TestMigration041IsIdempotentAndPreservesLegacy(t *testing.T) {
	_, db := openGoalTestStore(t)
	tx, err := db.Begin()
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = tx.Rollback() }()
	for _, q := range []string{
		`CREATE TEMP TABLE goals(id text, title text) ON COMMIT DROP`,
		`CREATE TEMP TABLE habit_logs(id text,done boolean) ON COMMIT DROP`,
		`INSERT INTO goals VALUES('g','Legacy')`,
		`INSERT INTO habit_logs VALUES('l',true)`,
	} {
		if _, err := tx.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	migration, err := os.ReadFile("../../migrations/041_goal_details_progress.sql")
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ {
		if _, err := tx.Exec(string(migration)); err != nil {
			t.Fatal(err)
		}
	}
	var details []byte
	var done bool
	var value int
	var steps string
	if err := tx.QueryRow(`SELECT g.details,l.done,l.value,l.completed_step_ids::text FROM goals g CROSS JOIN habit_logs l`).Scan(&details, &done, &value, &steps); err != nil {
		t.Fatal(err)
	}
	if details != nil || !done || value != 0 || steps != "[]" {
		t.Fatalf("legacy changed details=%s done=%v value=%d steps=%s", details, done, value, steps)
	}
}

func TestGoalsPersistProgressVariantsAndOwnedAtomicUpdates(t *testing.T) {
	s, db := openGoalTestStore(t)
	ctx := context.Background()
	owner := insertTestUser(t, db, ctx, "patient", "Goal owner", "goal-owner")
	other := insertTestUser(t, db, ctx, "patient", "Other owner", "goal-other")
	t.Cleanup(func() { cleanupTestUsers(t, db, owner, other) })
	today := clock.Now().Format("2006-01-02")
	d := validGoalDetails()
	d.Method = "numeric"
	d.Target = 3
	d.StartDate = today
	d.Steps = []GoalStep{{ID: "a", Label: "Langkah A"}, {ID: "b", Label: "Langkah B"}}
	g, err := s.CreateGoal(ctx, UpsertGoalParams{PatientID: owner, Title: "Minum", Category: "health", Details: d})
	if err != nil {
		t.Fatal(err)
	}
	retry, err := s.CreateGoal(ctx, UpsertGoalParams{ID: g.ID, PatientID: owner, Title: "Minum", Category: "health", Details: d})
	if err != nil || retry.ID != g.ID {
		t.Fatalf("retry=%+v err=%v", retry, err)
	}
	bad := *d
	bad.Target = 4
	if _, err := s.CreateGoal(ctx, UpsertGoalParams{ID: g.ID, PatientID: owner, Title: "Minum", Category: "health", Details: &bad}); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("retry changed payload err=%v", err)
	}
	steps := []string{"a"}
	value := 2
	l, err := s.LogHabit(ctx, owner, g.ID, today, true, HabitProgressPatch{Value: &value, CompletedStepIDs: &steps})
	if err != nil || l.Done {
		t.Fatalf("partial log=%+v err=%v", l, err)
	}
	value = 3
	l, err = s.LogHabit(ctx, owner, g.ID, today, false, HabitProgressPatch{Value: &value})
	if err != nil || !l.Done || len(l.CompletedStepIDs) != 1 {
		t.Fatalf("target log=%+v err=%v", l, err)
	}
	// Concurrent independent progress patches must retain both fields.
	var wg sync.WaitGroup
	errs := make(chan error, 2)
	steps = []string{"a", "b"}
	value = 4
	wg.Add(2)
	go func() {
		defer wg.Done()
		_, err := s.LogHabit(ctx, owner, g.ID, today, false, HabitProgressPatch{Value: &value})
		errs <- err
	}()
	go func() {
		defer wg.Done()
		_, err := s.LogHabit(ctx, owner, g.ID, today, false, HabitProgressPatch{CompletedStepIDs: &steps})
		errs <- err
	}()
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}
	goals, err := s.ListGoals(ctx, owner, false, today)
	if err != nil || len(goals) != 1 {
		t.Fatalf("goals=%+v err=%v", goals, err)
	}
	if got := goals[0]; !got.DoneToday || got.TodayValue != 4 || len(got.TodayCompletedStepIDs) != 2 || got.StreakDays != 1 || !got.IsDue || got.FailedToday {
		t.Fatalf("summary=%+v", got)
	}
	if _, err := s.LogHabit(ctx, other, g.ID, today, true); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("foreign log err=%v", err)
	}
	active := false
	if _, err := s.UpdateGoal(ctx, other, g.ID, "Stolen", "", nil, &active); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("foreign update err=%v", err)
	}
	invalid := *d
	invalid.Target = 0
	if _, err := s.UpdateGoal(ctx, owner, g.ID, "Changed", "", nil, nil, &invalid); err == nil {
		t.Fatal("accepted invalid atomic update")
	}
	unchanged, err := s.ListGoals(ctx, owner, false, today)
	if err != nil || len(unchanged) != 1 || unchanged[0].Title != "Minum" || unchanged[0].Details.Target != 3 || unchanged[0].TodayValue != 4 {
		t.Fatalf("invalid/foreign write changed goal: %+v err=%v", unchanged, err)
	}
	updated, err := s.UpdateGoal(ctx, owner, g.ID, "Still mine", "", nil, nil)
	if err != nil || updated.Details == nil || updated.Details.Target != 3 {
		t.Fatalf("preserved details=%+v err=%v", updated, err)
	}
	d.Method = "checklist"
	updated, err = s.UpdateGoal(ctx, owner, g.ID, "", "", nil, nil, d)
	if err != nil {
		t.Fatal(err)
	}
	l, err = s.LogHabit(ctx, owner, g.ID, today, false)
	if err != nil || !l.Done || l.Value != 4 {
		t.Fatalf("checklist persisted=%+v err=%v", l, err)
	}
	logs, err := s.ListHabitLogs(ctx, owner, today, today)
	if err != nil || len(logs) != 1 || logs[0].Value != 4 || len(logs[0].CompletedStepIDs) != 2 {
		t.Fatalf("history=%+v err=%v", logs, err)
	}
	if err := s.DeleteGoal(ctx, other, g.ID); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("foreign delete err=%v", err)
	}
	if err := s.DeleteGoal(ctx, owner, g.ID); err != nil {
		t.Fatal(err)
	}
	var count int
	if err := db.QueryRow(`SELECT COUNT(*) FROM habit_logs WHERE goal_id=$1`, g.ID).Scan(&count); err != nil || count != 0 {
		t.Fatalf("delete logs=%d err=%v", count, err)
	}
}

func TestGoalsConfiguredDateGuardsAndLegacyCompatibility(t *testing.T) {
	s, db := openGoalTestStore(t)
	ctx := context.Background()
	owner := insertTestUser(t, db, ctx, "patient", "Goal dates", "goal-dates")
	t.Cleanup(func() { cleanupTestUsers(t, db, owner) })
	today := goalDay(clock.Now())
	yesterday := today.AddDate(0, 0, -1).Format("2006-01-02")
	older := today.AddDate(0, 0, -2).Format("2006-01-02")
	tomorrow := today.AddDate(0, 0, 1).Format("2006-01-02")
	d := validGoalDetails()
	d.StartDate = older
	d.LockPast = true
	g, err := s.CreateGoal(ctx, UpsertGoalParams{PatientID: owner, Title: "Dated", Details: d})
	if err != nil {
		t.Fatal(err)
	}
	for _, date := range []string{older, tomorrow} {
		if _, err := s.LogHabit(ctx, owner, g.ID, date, true); err == nil {
			t.Fatalf("accepted locked/future date %s", date)
		}
	}
	if _, err := s.LogHabit(ctx, owner, g.ID, yesterday, true); err != nil {
		t.Fatalf("yesterday grace: %v", err)
	}
	goals, err := s.ListGoals(ctx, owner, false, older)
	if err != nil || len(goals) != 1 || !goals[0].FailedToday {
		t.Fatalf("past missing failure=%+v err=%v", goals, err)
	}
	d.Interval = 2
	d.LockPast = false
	if _, err := s.UpdateGoal(ctx, owner, g.ID, "", "", nil, nil, d); err != nil {
		t.Fatal(err)
	}
	if _, err := s.LogHabit(ctx, owner, g.ID, yesterday, true); err == nil {
		t.Fatal("accepted unscheduled configured log")
	}
	legacy, err := s.CreateGoal(ctx, UpsertGoalParams{PatientID: owner, Title: "Legacy", Category: "custom", TargetPerWeek: 6})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.LogHabit(ctx, owner, legacy.ID, tomorrow, true); err != nil {
		t.Fatalf("old call incompatible: %v", err)
	}
	legacy, err = s.UpdateGoal(ctx, owner, legacy.ID, "Renamed", "", nil, nil)
	if err != nil || legacy.Details != nil || legacy.Category != "custom" || legacy.TargetPerWeek != 6 {
		t.Fatalf("legacy=%+v err=%v", legacy, err)
	}
	if _, err := s.ListGoals(ctx, owner, false, "2026-02-30"); err == nil {
		t.Fatal("accepted invalid selected date")
	}
}

func TestGoalYesNoConfigurationRoundTripsAllControls(t *testing.T) {
	s, db := openGoalTestStore(t)
	ctx := context.Background()
	owner := insertTestUser(t, db, ctx, "patient", "Goal controls", "goal-controls")
	t.Cleanup(func() { cleanupTestUsers(t, db, owner) })
	d := &GoalDetails{
		Note: "Catatan pribadi", Method: "yes_no", Target: 1, Unit: "latihan",
		Steps:     []GoalStep{{ID: "stable-a", Label: "Tarik napas"}},
		StartDate: "2026-01-05", Time: "06:30", Recurrence: "weekly", Interval: 2,
		Weekdays: []int{1, 3, 7}, Reminders: []int{0, 30, 10080}, AutoFail: false, LockPast: true,
	}
	g, err := s.CreateGoal(ctx, UpsertGoalParams{PatientID: owner, Title: "Latihan", Details: d})
	if err != nil {
		t.Fatal(err)
	}
	goals, err := s.ListGoals(ctx, owner, false, "2026-01-07")
	if err != nil || len(goals) != 1 {
		t.Fatalf("goals=%+v err=%v", goals, err)
	}
	actual := goals[0].Details
	if actual == nil || actual.Note != "Catatan pribadi" || actual.Method != "yes_no" || actual.Target != 1 || actual.Unit != "latihan" || len(actual.Steps) != 1 || actual.Steps[0].ID != "stable-a" || actual.Steps[0].Label != "Tarik napas" || actual.StartDate != "2026-01-05" || actual.Time != "06:30" || actual.Recurrence != "weekly" || actual.Interval != 2 || len(actual.Weekdays) != 3 || actual.Weekdays[2] != 7 || len(actual.Reminders) != 3 || actual.Reminders[2] != 10080 || actual.AutoFail || !actual.LockPast || !goals[0].IsDue || goals[0].FailedToday {
		t.Fatalf("lost persisted controls: %+v goal=%+v", actual, goals[0])
	}
	steps := []string{"stable-a"}
	// An independently patched step must not change an explicit yes/no answer.
	d.LockPast = false
	if _, err := s.UpdateGoal(ctx, owner, g.ID, "", "", nil, nil, d); err != nil {
		t.Fatal(err)
	}
	l, err := s.LogHabit(ctx, owner, g.ID, "2026-01-07", false, HabitProgressPatch{CompletedStepIDs: &steps})
	if err != nil || l.Done || len(l.CompletedStepIDs) != 1 {
		t.Fatalf("yes/no log=%+v err=%v", l, err)
	}
	all, err := s.ListHabitLogs(ctx, owner, "", "")
	if err != nil || len(all) != 1 || all[0].LoggedOn != "2026-01-07" {
		t.Fatalf("unbounded dates history=%+v err=%v", all, err)
	}
}

func TestGoalDetailsPersistCanonicalIrrelevantWeekdays(t *testing.T) {
	s, db := openGoalTestStore(t)
	ctx := context.Background()
	owner := insertTestUser(t, db, ctx, "patient", "Canonical owner", "canonical-owner")
	t.Cleanup(func() { cleanupTestUsers(t, db, owner) })
	quota := 2
	for _, tc := range []struct {
		name         string
		recurrence   string
		weeklyTarget *int
	}{{"monthly", "monthly", nil}, {"flexible", "weekly", &quota}} {
		t.Run(tc.name, func(t *testing.T) {
			d := validGoalDetails()
			d.Recurrence = tc.recurrence
			d.WeeklyTarget = tc.weeklyTarget
			g, err := s.CreateGoal(ctx, UpsertGoalParams{PatientID: owner, Title: tc.name, Details: d})
			if err != nil {
				t.Fatal(err)
			}
			if g.Details.Weekdays == nil || len(g.Details.Weekdays) != 0 {
				t.Fatalf("returned irrelevant weekdays=%v", g.Details.Weekdays)
			}
			var stored string
			if err := db.QueryRow(`SELECT details->'weekdays' FROM goals WHERE id=$1`, g.ID).Scan(&stored); err != nil {
				t.Fatal(err)
			}
			if stored != "[]" {
				t.Fatalf("stored irrelevant weekdays=%s", stored)
			}
			if len(d.Weekdays) != 7 {
				t.Fatal("normalization mutated caller")
			}
			d.Weekdays = []int{0}
			if _, err := goalDetailsJSON(d); err == nil {
				t.Fatal("invalid caller weekdays bypassed validation")
			}
		})
	}
}
