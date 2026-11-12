package server

import (
	"encoding/json"
	"testing"

	"malva/backend/internal/clock"
	"malva/backend/internal/store"
)

func TestGoalDetailsHTTPProgressAndSelectedDate(t *testing.T) {
	f := newClinicalFixture(t)
	today := clock.Now().Format("2006-01-02")
	details := map[string]any{"method": "numeric", "target": 5, "unit": "gelas", "steps": []any{map[string]any{"id": "a", "label": "Pagi"}}, "start_date": today, "time": "22:30", "recurrence": "daily", "interval": 1, "weekdays": []int{1, 2, 3, 4, 5, 6, 7}, "reminders": []int{30}, "auto_fail": true, "lock_past": false, "note": "Rutinitas"}
	out := f.call(t, "POST", "/v1/goals", "patient", f.patient.ID, map[string]any{"title": "Minum", "details": details})
	if out.Code != 201 {
		t.Fatalf("create status=%d: %s", out.Code, out.Body)
	}
	var created struct {
		Goal store.Goal `json:"goal"`
	}
	if err := json.Unmarshal(out.Body.Bytes(), &created); err != nil {
		t.Fatal(err)
	}
	if created.Goal.Details == nil || created.Goal.Details.Unit != "gelas" {
		t.Fatalf("lost details: %s", out.Body)
	}
	out = f.call(t, "POST", "/v1/habit-logs", "patient", f.patient.ID, map[string]any{"goal_id": created.Goal.ID, "logged_on": today, "done": false, "value": 5, "completed_step_ids": []string{"a"}})
	if out.Code != 200 {
		t.Fatalf("log status=%d: %s", out.Code, out.Body)
	}
	var logged struct {
		Log store.HabitLog `json:"log"`
	}
	if err := json.Unmarshal(out.Body.Bytes(), &logged); err != nil {
		t.Fatal(err)
	}
	if !logged.Log.Done || logged.Log.Value != 5 || len(logged.Log.CompletedStepIDs) != 1 {
		t.Fatalf("progress: %s", out.Body)
	}
	out = f.call(t, "GET", "/v1/goals?on="+today, "patient", f.patient.ID, nil)
	var listed struct {
		Goals []store.Goal `json:"goals"`
	}
	if err := json.Unmarshal(out.Body.Bytes(), &listed); err != nil {
		t.Fatal(err)
	}
	if out.Code != 200 || len(listed.Goals) != 1 || !listed.Goals[0].DoneToday || listed.Goals[0].TodayValue != 5 || listed.Goals[0].StreakDays != 1 {
		t.Fatalf("selected day: %d %s", out.Code, out.Body)
	}
	for _, date := range []string{"2026-02-30", "tomorrow", "2026-1-01"} {
		out = f.call(t, "GET", "/v1/goals?on="+date, "patient", f.patient.ID, nil)
		if out.Code != 400 {
			t.Fatalf("invalid on=%s status=%d: %s", date, out.Code, out.Body)
		}
	}
	out = f.call(t, "POST", "/v1/habit-logs", "patient", f.patient.ID, map[string]any{"goal_id": created.Goal.ID, "value": -1})
	if out.Code != 400 {
		t.Fatalf("negative value status=%d: %s", out.Code, out.Body)
	}
	out = f.call(t, "POST", "/v1/habit-logs", "patient", f.other.ID, map[string]any{"goal_id": created.Goal.ID, "value": 5})
	if out.Code != 404 {
		t.Fatalf("foreign goal status=%d: %s", out.Code, out.Body)
	}
	details["target"] = 0
	out = f.call(t, "PATCH", "/v1/goals/"+created.Goal.ID, "patient", f.patient.ID, map[string]any{"title": "Uncommitted", "details": details})
	if out.Code != 400 {
		t.Fatalf("invalid details status=%d: %s", out.Code, out.Body)
	}
	out = f.call(t, "PATCH", "/v1/goals/"+created.Goal.ID, "patient", f.patient.ID, map[string]any{"title": "Air"})
	if out.Code != 200 {
		t.Fatalf("unrelated update status=%d: %s", out.Code, out.Body)
	}
	if err := json.Unmarshal(out.Body.Bytes(), &created); err != nil {
		t.Fatal(err)
	}
	if created.Goal.Details == nil || created.Goal.Details.Target != 5 || !created.Goal.DoneToday {
		t.Fatalf("update lost details/progress: %s", out.Body)
	}
}

func TestGoalWeeklyQuotaHTTPPersistenceAndMonthly(t *testing.T) {
	f := newClinicalFixture(t)
	details := map[string]any{"method": "yes_no", "target": 1, "start_date": "2024-01-31", "recurrence": "weekly", "interval": 1, "weekly_target": 0, "weekdays": []int{}, "auto_fail": true}
	out := f.call(t, "POST", "/v1/goals", "patient", f.patient.ID, map[string]any{"title": "Flexible", "target_per_week": 5, "details": details})
	if out.Code != 201 {
		t.Fatalf("create %d %s", out.Code, out.Body)
	}
	var body struct {
		Goal store.Goal `json:"goal"`
	}
	if err := json.Unmarshal(out.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	id := body.Goal.ID
	if body.Goal.Details.WeeklyTarget == nil || *body.Goal.Details.WeeklyTarget != 0 || body.Goal.TargetPerWeek != 5 {
		t.Fatalf("roundtrip %s", out.Body)
	}
	out = f.call(t, "POST", "/v1/habit-logs", "patient", f.patient.ID, map[string]any{"goal_id": id, "logged_on": "2026-11-02", "done": true})
	if out.Code != 200 {
		t.Fatalf("log %d %s", out.Code, out.Body)
	}
	out = f.call(t, "GET", "/v1/goals?on=2026-11-04", "patient", f.patient.ID, nil)
	var listed struct {
		Goals []store.Goal `json:"goals"`
	}
	_ = json.Unmarshal(out.Body.Bytes(), &listed)
	if out.Code != 200 || len(listed.Goals) != 1 || len(listed.Goals[0].CompletedWeekdays) != 1 || listed.Goals[0].CompletedWeekdays[0] != 1 || listed.Goals[0].FailedToday {
		t.Fatalf("actual days %d %s", out.Code, out.Body)
	}
	for _, quota := range []any{-1, 8, 1.5} {
		details["weekly_target"] = quota
		out = f.call(t, "PATCH", "/v1/goals/"+id, "patient", f.patient.ID, map[string]any{"details": details})
		if out.Code != 400 {
			t.Fatalf("invalid quota %v: %d %s", quota, out.Code, out.Body)
		}
	}
	delete(details, "weekly_target")
	details["weekdays"] = []int{2}
	out = f.call(t, "PATCH", "/v1/goals/"+id, "patient", f.patient.ID, map[string]any{"details": details})
	if out.Code != 200 {
		t.Fatalf("reset %d %s", out.Code, out.Body)
	}
	body.Goal = store.Goal{}
	_ = json.Unmarshal(out.Body.Bytes(), &body)
	if body.Goal.Details.WeeklyTarget != nil || body.Goal.TargetPerWeek != 5 {
		t.Fatalf("reset persisted %s", out.Body)
	}
	details["recurrence"] = "monthly"
	details["interval"] = 1
	out = f.call(t, "PATCH", "/v1/goals/"+id, "patient", f.other.ID, map[string]any{"details": details})
	if out.Code != 404 {
		t.Fatalf("ownership %d %s", out.Code, out.Body)
	}
	out = f.call(t, "PATCH", "/v1/goals/"+id, "patient", f.patient.ID, map[string]any{"details": details})
	if out.Code != 200 {
		t.Fatalf("monthly %d %s", out.Code, out.Body)
	}
	for _, tc := range []struct {
		date string
		code int
	}{{"2024-02-28", 400}, {"2024-02-29", 200}, {"2024-03-30", 400}, {"2024-03-31", 200}} {
		out = f.call(t, "POST", "/v1/habit-logs", "patient", f.patient.ID, map[string]any{"goal_id": id, "logged_on": tc.date, "done": true})
		if out.Code != tc.code {
			t.Fatalf("monthly log %s: %d %s", tc.date, out.Code, out.Body)
		}
	}
	out = f.call(t, "GET", "/v1/goals?on=2024-03-31", "patient", f.patient.ID, nil)
	listed.Goals = nil
	_ = json.Unmarshal(out.Body.Bytes(), &listed)
	if out.Code != 200 || len(listed.Goals) != 1 || listed.Goals[0].StreakDays != 2 {
		t.Fatalf("monthly streak %d %s", out.Code, out.Body)
	}
}
