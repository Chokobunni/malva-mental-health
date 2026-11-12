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
