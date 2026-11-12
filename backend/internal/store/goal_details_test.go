package store

import (
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
		{"invalid recurrence", func(d *GoalDetails) { d.Recurrence = "monthly" }, false},
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
