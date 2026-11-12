package store

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"malva/backend/internal/clock"
)

func goalTestDate(s string) time.Time {
	d, err := time.ParseInLocation("2006-01-02", s, clock.Location())
	if err != nil {
		panic(err)
	}
	return d
}

func validGoalDetails() *GoalDetails {
	return &GoalDetails{Method: "yes_no", Target: 1, StartDate: "2026-11-02", Time: "22:30", Recurrence: "daily", Interval: 1, Weekdays: []int{1, 2, 3, 4, 5, 6, 7}, Reminders: []int{0, 30}, AutoFail: true}
}

func TestGoalDetailsValidation(t *testing.T) {
	tests := []struct {
		name   string
		mutate func(*GoalDetails)
		valid  bool
	}{
		{"valid daily", func(*GoalDetails) {}, true},
		{"valid weekly", func(d *GoalDetails) { d.Recurrence = "weekly"; d.Interval = 52; d.Weekdays = []int{1, 7} }, true},
		{"valid numeric maximum", func(d *GoalDetails) { d.Method = "numeric"; d.Target = 1000000; d.Unit = "gelas" }, true},
		{"valid checklist", func(d *GoalDetails) { d.Method = "checklist"; d.Steps = []GoalStep{{ID: "a", Label: "Tarik napas"}} }, true},
		{"invalid method", func(d *GoalDetails) { d.Method = "timer" }, false},
		{"missing start", func(d *GoalDetails) { d.StartDate = "" }, false},
		{"invalid date", func(d *GoalDetails) { d.StartDate = "2026-02-30" }, false},
		{"invalid time", func(d *GoalDetails) { d.Time = "24:00" }, false},
		{"noncanonical time", func(d *GoalDetails) { d.Time = "9:00" }, false},
		{"no timed reminder", func(d *GoalDetails) { d.Time = "" }, true},
		{"invalid recurrence", func(d *GoalDetails) { d.Recurrence = "yearly" }, false},
		{"zero interval", func(d *GoalDetails) { d.Interval = 0 }, false},
		{"daily interval bound", func(d *GoalDetails) { d.Interval = 366 }, false},
		{"weekly interval bound", func(d *GoalDetails) { d.Recurrence = "weekly"; d.Interval = 53 }, false},
		{"weekly no days", func(d *GoalDetails) { d.Recurrence = "weekly"; d.Weekdays = nil }, false},
		{"bad weekday", func(d *GoalDetails) { d.Weekdays = []int{0} }, false},
		{"duplicate weekday", func(d *GoalDetails) { d.Weekdays = []int{1, 1} }, false},
		{"zero numeric target", func(d *GoalDetails) { d.Method = "numeric"; d.Target = 0 }, false},
		{"target overflow", func(d *GoalDetails) { d.Target = 1000001 }, false},
		{"unit unicode bound", func(d *GoalDetails) { d.Unit = strings.Repeat("é", 80) }, true},
		{"long unit", func(d *GoalDetails) { d.Unit = strings.Repeat("a", 81) }, false},
		{"long note", func(d *GoalDetails) { d.Note = strings.Repeat("a", 5001) }, false},
		{"empty checklist", func(d *GoalDetails) { d.Method = "checklist" }, false},
		{"duplicate step", func(d *GoalDetails) { d.Steps = []GoalStep{{ID: "a", Label: "a"}, {ID: "a", Label: "b"}} }, false},
		{"empty step id", func(d *GoalDetails) { d.Steps = []GoalStep{{ID: "", Label: "a"}} }, false},
		{"empty step label", func(d *GoalDetails) { d.Steps = []GoalStep{{ID: "a", Label: " "}} }, false},
		{"step id too long", func(d *GoalDetails) { d.Steps = []GoalStep{{ID: strings.Repeat("a", 65), Label: "a"}} }, false},
		{"step label too long", func(d *GoalDetails) { d.Steps = []GoalStep{{ID: "a", Label: strings.Repeat("a", 501)}} }, false},
		{"too many steps", func(d *GoalDetails) { d.Steps = make([]GoalStep, 101) }, false},
		{"negative reminder", func(d *GoalDetails) { d.Reminders = []int{-1} }, false},
		{"reminder bound", func(d *GoalDetails) { d.Reminders = []int{10081} }, false},
		{"duplicate reminder", func(d *GoalDetails) { d.Reminders = []int{30, 30} }, false},
		{"too many reminders", func(d *GoalDetails) { d.Reminders = make([]int, 11) }, false},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			d := validGoalDetails()
			tt.mutate(d)
			err := ValidateGoalDetails(d)
			if (err == nil) != tt.valid {
				t.Fatalf("valid=%v err=%v", tt.valid, err)
			}
		})
	}
}

func TestGoalRecurrenceUsesStartAndISOWeekAnchor(t *testing.T) {
	d := validGoalDetails()
	d.StartDate = "2026-11-04"
	d.Interval = 3
	for _, tt := range []struct {
		date string
		due  bool
	}{{"2026-11-03", false}, {"2026-11-04", true}, {"2026-11-05", false}, {"2026-11-07", true}} {
		if got := goalDue(d, goalTestDate(tt.date)); got != tt.due {
			t.Errorf("daily %s=%v", tt.date, got)
		}
	}
	d.Recurrence = "weekly"
	d.Interval = 2
	d.Weekdays = []int{1, 3, 7}
	for _, tt := range []struct {
		date string
		due  bool
	}{{"2026-11-02", false}, {"2026-11-04", true}, {"2026-11-08", true}, {"2026-11-09", false}, {"2026-11-15", false}, {"2026-11-16", true}, {"2026-11-18", true}} {
		if got := goalDue(d, goalTestDate(tt.date)); got != tt.due {
			t.Errorf("weekly %s=%v", tt.date, got)
		}
	}
}

func TestHabitProgressDerivesCompletionAndPreservesOtherFields(t *testing.T) {
	d := validGoalDetails()
	d.Method = "numeric"
	d.Target = 5
	d.Steps = []GoalStep{{ID: "a", Label: "A"}, {ID: "b", Label: "B"}}
	value := 4
	got, err := applyHabitProgress(d, HabitLog{CompletedStepIDs: []string{"a"}}, true, HabitProgressPatch{Value: &value})
	if err != nil || got.Done || got.Value != 4 || len(got.CompletedStepIDs) != 1 || got.CompletedStepIDs[0] != "a" {
		t.Fatalf("numeric partial=%+v err=%v", got, err)
	}
	value = 5
	got, err = applyHabitProgress(d, got, false, HabitProgressPatch{Value: &value})
	if err != nil || !got.Done {
		t.Fatalf("numeric target=%+v err=%v", got, err)
	}
	d.Method = "checklist"
	steps := []string{"a", "b"}
	got, err = applyHabitProgress(d, got, false, HabitProgressPatch{CompletedStepIDs: &steps})
	if err != nil || !got.Done || got.Value != 5 {
		t.Fatalf("checklist=%+v err=%v", got, err)
	}
	steps = []string{}
	got, err = applyHabitProgress(d, got, true, HabitProgressPatch{CompletedStepIDs: &steps})
	if err != nil || got.Done || got.Value != 5 {
		t.Fatalf("clear checklist=%+v err=%v", got, err)
	}
	for _, ids := range [][]string{{"unknown"}, {"a", "a"}} {
		if _, err := applyHabitProgress(d, got, true, HabitProgressPatch{CompletedStepIDs: &ids}); err == nil {
			t.Errorf("accepted step ids %v", ids)
		}
	}
	for _, v := range []int{-1, 1000001} {
		if _, err := applyHabitProgress(d, got, true, HabitProgressPatch{Value: &v}); err == nil {
			t.Errorf("accepted value %d", v)
		}
	}
	legacy, err := applyHabitProgress(nil, HabitLog{}, true, HabitProgressPatch{})
	if err != nil || !legacy.Done {
		t.Fatalf("legacy=%+v err=%v", legacy, err)
	}
}

func TestGoalLogDateGuardsAllowYesterdayThroughEndOfToday(t *testing.T) {
	d := validGoalDetails()
	d.LockPast = true
	now := goalTestDate("2026-11-12").Add(23*time.Hour + 59*time.Minute)
	for _, tt := range []struct {
		date  string
		valid bool
	}{{"2026-11-10", false}, {"2026-11-11", true}, {"2026-11-12", true}, {"2026-11-13", false}} {
		if err := validateHabitDate(d, goalTestDate(tt.date), now); (err == nil) != tt.valid {
			t.Errorf("%s valid=%v err=%v", tt.date, tt.valid, err)
		}
	}
	d.LockPast = false
	d.Interval = 2
	if err := validateHabitDate(d, goalTestDate("2026-11-11"), now); err == nil {
		t.Fatal("accepted unscheduled date")
	}
	if err := validateHabitDate(nil, goalTestDate("2026-11-13"), now); err != nil {
		t.Fatalf("legacy compatibility: %v", err)
	}
}

func TestGoalStreakCountsOccurrencesAndAllowsPendingToday(t *testing.T) {
	d := validGoalDetails()
	d.Recurrence = "weekly"
	d.Weekdays = []int{1, 3, 5}
	logs := []HabitLog{{LoggedOn: "2026-11-02", Done: true}, {LoggedOn: "2026-11-04", Done: true}, {LoggedOn: "2026-11-06", Done: true}}
	if got := goalStreak(d, logs, goalTestDate("2026-11-09"), goalTestDate("2026-11-09")); got != 3 {
		t.Fatalf("pending today streak=%d want 3", got)
	}
	if got := goalStreak(d, logs, goalTestDate("2026-11-10"), goalTestDate("2026-11-10")); got != 0 {
		t.Fatalf("elapsed missing streak=%d want 0", got)
	}
	d.AutoFail = false
	if got := goalStreak(d, logs, goalTestDate("2026-11-10"), goalTestDate("2026-11-10")); got != 3 {
		t.Fatalf("missing without auto-fail streak=%d want 3", got)
	}
	logs = append(logs, HabitLog{LoggedOn: "2026-11-09", Done: false}, HabitLog{LoggedOn: "2026-11-11", Done: true})
	if got := goalStreak(d, logs, goalTestDate("2026-11-11"), goalTestDate("2026-11-11")); got != 1 {
		t.Fatalf("explicit failure streak=%d want 1", got)
	}
	if got := goalStreak(d, logs, goalTestDate("2026-11-04"), goalTestDate("2026-11-11")); got != 2 {
		t.Fatalf("selected-date streak=%d want 2", got)
	}
}

func TestGoalMonthlyAnchorAndPrevious(t *testing.T) {
	d := validGoalDetails()
	d.Recurrence = "monthly"
	d.StartDate = "2024-01-31"
	if err := ValidateGoalDetails(d); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		on       string
		due      bool
		previous string
	}{
		{"2024-02-28", false, "2024-01-31"}, {"2024-02-29", true, "2024-02-29"}, {"2024-03-30", false, "2024-02-29"}, {"2024-03-31", true, "2024-03-31"},
	} {
		if got := goalDue(d, goalTestDate(tc.on)); got != tc.due {
			t.Errorf("due %s=%v", tc.on, got)
		}
		got, ok := previousGoalDue(d, goalTestDate(tc.on))
		if !ok || got.Format("2006-01-02") != tc.previous {
			t.Errorf("previous %s=%v %v", tc.on, got, ok)
		}
	}
	d.Interval = 2
	if goalDue(d, goalTestDate("2024-02-29")) || !goalDue(d, goalTestDate("2024-03-31")) {
		t.Fatal("monthly interval ignored")
	}
	d.Interval = 13
	if ValidateGoalDetails(d) == nil {
		t.Fatal("accepted monthly interval13")
	}
}

func TestGoalFlexibleWeeklyQuota(t *testing.T) {
	d := validGoalDetails()
	d.Recurrence = "weekly"
	d.Weekdays = nil
	if err := json.Unmarshal([]byte(`{"weekly_target":2}`), d); err != nil {
		t.Fatal(err)
	}
	if err := ValidateGoalDetails(d); err != nil {
		t.Fatal(err)
	}
	logs := []HabitLog{{LoggedOn: "2026-11-02", Done: true}, {LoggedOn: "2026-11-04", Done: true}, {LoggedOn: "2026-11-09", Done: true}}
	for _, tc := range []struct {
		on   string
		want int
	}{{"2026-11-08", 2}, {"2026-11-09", 3}, {"2026-11-15", 3}, {"2026-11-16", 0}} {
		if got := goalStreak(d, logs, goalTestDate(tc.on), goalTestDate(tc.on)); got != tc.want {
			t.Errorf("streak %s=%d want%d", tc.on, got, tc.want)
		}
	}
	var g Goal
	g.Details = d
	summarizeGoal(&g, logs, goalTestDate("2026-11-05"), goalTestDate("2026-11-09"))
	raw, _ := json.Marshal(g)
	var out map[string]any
	_ = json.Unmarshal(raw, &out)
	days, ok := out["completed_weekdays"].([]any)
	if !ok || len(days) != 2 || days[0] != float64(1) || days[1] != float64(3) {
		t.Fatalf("actual weekdays: %s", raw)
	}
	if g.FailedToday {
		t.Fatal("rest day auto-failed")
	}
	logs = append(logs, HabitLog{LoggedOn: "2026-11-10", Done: false})
	if got := goalStreak(d, logs, goalTestDate("2026-11-10"), goalTestDate("2026-11-10")); got != 0 {
		t.Fatalf("explicit fail streak=%d", got)
	}
	_ = json.Unmarshal([]byte(`{"weekly_target":0}`), d)
	if got := goalStreak(d, logs[:3], goalTestDate("2026-12-01"), goalTestDate("2026-12-01")); got != 3 {
		t.Fatalf("zero quota=%d", got)
	}
	for _, raw := range []string{`{"weekly_target":-1}`, `{"weekly_target":8}`} {
		_ = json.Unmarshal([]byte(raw), d)
		if ValidateGoalDetails(d) == nil {
			t.Fatal("invalid quota accepted", raw)
		}
	}
	_ = json.Unmarshal([]byte(`{"weekly_target":1}`), d)
	d.Recurrence = "daily"
	if ValidateGoalDetails(d) == nil {
		t.Fatal("daily quota accepted")
	}
}

func TestGoalFlexibleWeeklyInactiveIntervalsAndProjection(t *testing.T) {
	quota := 2
	d := validGoalDetails()
	d.Recurrence = "weekly"
	d.Interval = 2
	d.WeeklyTarget = &quota
	d.Weekdays = []int{1}
	logs := []HabitLog{{LoggedOn: "2026-11-02", Done: true}, {LoggedOn: "2026-11-04", Done: true}, {LoggedOn: "2026-11-09", Done: true}, {LoggedOn: "2026-11-16", Done: true}}
	if goalDue(d, goalTestDate("2026-11-09")) || !goalDue(d, goalTestDate("2026-11-04")) {
		t.Fatal("flexible interval/day filter")
	}
	if got := goalStreak(d, logs, goalTestDate("2026-11-16"), goalTestDate("2026-11-16")); got != 3 {
		t.Fatalf("inactive rest week broke streak=%d", got)
	}
	if got := goalStreak(d, logs, goalTestDate("2026-11-23"), goalTestDate("2026-11-23")); got != 0 {
		t.Fatalf("missing active quota streak=%d", got)
	}
	for _, tc := range []struct {
		details *GoalDetails
		on      string
		want    []int
	}{{nil, "2026-11-03", []int{1}}, {d, "2026-11-10", []int{}}} {
		g := Goal{Details: tc.details}
		summarizeGoal(&g, logs, goalTestDate(tc.on), goalTestDate("2026-11-23"))
		if len(g.CompletedWeekdays) != len(tc.want) {
			t.Fatalf("projected %+v want %+v", g.CompletedWeekdays, tc.want)
		}
		for i := range tc.want {
			if g.CompletedWeekdays[i] != tc.want[i] {
				t.Fatalf("projected %+v", g.CompletedWeekdays)
			}
		}
	}
	d.AutoFail = false
	if got := goalStreak(d, logs, goalTestDate("2026-12-01"), goalTestDate("2026-12-01")); got != 3 {
		t.Fatalf("auto-fail disabled=%d", got)
	}
}

func TestGoalFlexibleFirstMondayIsPending(t *testing.T) {
	quota := 2
	d := validGoalDetails()
	d.Recurrence = "weekly"
	d.WeeklyTarget = &quota
	logs := []HabitLog{{LoggedOn: "2026-11-02", Done: true}}
	if got := goalStreak(d, logs, goalTestDate("2026-11-02"), goalTestDate("2026-11-02")); got != 1 {
		t.Fatalf("first Monday streak=%d want1", got)
	}
}
