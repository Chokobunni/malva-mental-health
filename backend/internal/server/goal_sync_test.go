package server

import (
	"encoding/json"
	"reflect"
	"testing"

	"malva/backend/internal/clock"
	"malva/backend/internal/store"
)

func TestGoalScheduleEditsHTTPRoundTrip(t *testing.T) {
	f := newClinicalFixture(t)
	for _, method := range []string{"yes_no", "numeric", "checklist"} {
		t.Run(method, func(t *testing.T) {
			out := f.call(t, "POST", "/v1/goals", "patient", f.patient.ID, map[string]any{"title": method, "target_per_week": 4})
			var body struct {
				Goal store.Goal `json:"goal"`
			}
			if out.Code != 201 {
				t.Fatalf("create: %d %s", out.Code, out.Body)
			}
			if err := json.Unmarshal(out.Body.Bytes(), &body); err != nil {
				t.Fatal(err)
			}
			id := body.Goal.ID
			for _, schedule := range []map[string]any{
				{"recurrence": "daily", "interval": 1, "weekdays": []int{1, 2, 3, 4, 5, 6, 7}},
				{"recurrence": "daily", "interval": 3, "weekdays": []int{1, 2, 3, 4, 5, 6, 7}},
				{"recurrence": "weekly", "interval": 1, "weekdays": []int{5, 6, 7}},
				{"recurrence": "weekly", "interval": 2, "weekdays": []int{1, 3}},
				{"recurrence": "weekly", "interval": 1, "weekdays": []int{}, "weekly_target": 4},
				{"recurrence": "weekly", "interval": 2, "weekdays": []int{}, "weekly_target": 0},
				{"recurrence": "monthly", "interval": 2, "weekdays": []int{}},
			} {
				details := map[string]any{"method": method, "target": 20, "unit": "halaman", "start_date": "2024-01-31", "time": "06:30", "reminders": []int{0, 30}, "auto_fail": false, "lock_past": true, "note": "Catatan asli", "steps": []map[string]string{{"id": "stable", "label": "Aktivitas asli"}}}
				for k, v := range schedule {
					details[k] = v
				}
				raw, _ := json.Marshal(details)
				var want store.GoalDetails
				if err := json.Unmarshal(raw, &want); err != nil {
					t.Fatal(err)
				}
				out = f.call(t, "PATCH", "/v1/goals/"+id, "patient", f.patient.ID, map[string]any{"details": details})
				if out.Code != 200 {
					t.Fatalf("edit: %d %s", out.Code, out.Body)
				}
				body.Goal = store.Goal{}
				if err := json.Unmarshal(out.Body.Bytes(), &body); err != nil {
					t.Fatal(err)
				}
				if !reflect.DeepEqual(body.Goal.Details, &want) {
					t.Fatalf("edit lost fields: got=%+v want=%+v", body.Goal.Details, want)
				}
				out = f.call(t, "GET", "/v1/goals?on=2026-11-13", "patient", f.patient.ID, nil)
				var listed struct {
					Goals []store.Goal `json:"goals"`
				}
				if err := json.Unmarshal(out.Body.Bytes(), &listed); err != nil {
					t.Fatal(err)
				}
				found := false
				for _, g := range listed.Goals {
					if g.ID == id {
						found = reflect.DeepEqual(g.Details, &want)
					}
				}
				if out.Code != 200 || !found {
					t.Fatalf("reload lost fields: %d %s", out.Code, out.Body)
				}
			}
		})
	}
}

func TestChecklistExtraProgressHTTPEmptyIDs(t *testing.T) {
	f := newClinicalFixture(t)
	now := clock.Now()
	today := now.Format("2006-01-02")
	d := map[string]any{"method": "checklist", "start_date": now.AddDate(0, 0, -1).Format("2006-01-02"), "recurrence": "daily", "interval": 2, "steps": []map[string]string{{"id": "a", "label": "A"}}}
	out := f.call(t, "POST", "/v1/goals", "patient", f.patient.ID, map[string]any{"title": "Checklist", "details": d})
	var created struct {
		Goal store.Goal `json:"goal"`
	}
	if out.Code != 201 {
		t.Fatalf("create: %d %s", out.Code, out.Body)
	}
	if err := json.Unmarshal(out.Body.Bytes(), &created); err != nil {
		t.Fatal(err)
	}
	for _, ids := range [][]string{{"a"}, {}, {"a"}} {
		out = f.call(t, "POST", "/v1/habit-logs", "patient", f.patient.ID, map[string]any{"goal_id": created.Goal.ID, "logged_on": today, "completed_step_ids": ids})
		if out.Code != 200 {
			t.Fatalf("write: %d %s", out.Code, out.Body)
		}
		out = f.call(t, "GET", "/v1/goals?on="+today, "patient", f.patient.ID, nil)
		var listed struct {
			Goals []store.Goal `json:"goals"`
		}
		if err := json.Unmarshal(out.Body.Bytes(), &listed); err != nil {
			t.Fatal(err)
		}
		if out.Code != 200 || len(listed.Goals) != 1 {
			t.Fatalf("reload: %d %s", out.Code, out.Body)
		}
		g := listed.Goals[0]
		if !reflect.DeepEqual(g.TodayCompletedStepIDs, ids) || g.DoneToday != (len(ids) == 1) || g.IsDue || g.DoneThisWeek != 0 || g.StreakDays != 0 {
			t.Fatalf("wrong progress: %s", out.Body)
		}
	}
}
