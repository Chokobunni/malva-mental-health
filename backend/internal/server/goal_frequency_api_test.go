package server

import (
	"bytes"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"malva/backend/internal/clock"
	"malva/backend/internal/store"
)

func TestFrequencySessionActionsThroughHabitAPI(t *testing.T) {
	f := newClinicalFixture(t)
	quota := 5
	goal, err := f.st.CreateGoal(t.Context(), store.UpsertGoalParams{
		PatientID: f.patient.ID, Title: "Baca", Details: &store.GoalDetails{
			Method: "numeric", Target: 7, Unit: "halaman", StartDate: clock.Now().Format("2006-01-02"),
			Recurrence: "weekly", Interval: 1, WeeklyTarget: &quota,
		},
	})
	if err != nil {
		t.Fatal(err)
	}
	today := clock.Now().Format("2006-01-02")
	token, _ := f.srv.auth.Issue(f.patient.ID, "patient")
	handler := f.srv.Routes()
	request := func(key, action string) []byte {
		t.Helper()
		raw, _ := json.Marshal(map[string]any{"goal_id": goal.ID, "logged_on": today, "session_action": action})
		req := httptest.NewRequest(http.MethodPost, "/v1/habit-logs", bytes.NewReader(raw))
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Content-Type", "application/json")
		req.Header.Set("Idempotency-Key", key)
		rec := httptest.NewRecorder()
		handler.ServeHTTP(rec, req)
		if rec.Code != 200 {
			t.Fatalf("action status=%d %s", rec.Code, rec.Body)
		}
		return rec.Body.Bytes()
	}
	for range 2 {
		request("complete-once", "complete")
	}
	body := request("undo-once", "undo")
	var result struct {
		Log store.HabitLog `json:"log"`
	}
	if err = json.Unmarshal(body, &result); err != nil || result.Log.Sessions != 0 || result.Log.Value != 0 || len(result.Log.CompletedStepIDs) != 0 {
		t.Fatalf("unexpected log %s %v", body, err)
	}
	out := f.call(t, "GET", "/v1/goals?on="+today, "patient", f.patient.ID, nil)
	var goals struct {
		Goals []store.Goal `json:"goals"`
	}
	if out.Code != 200 || json.Unmarshal(out.Body.Bytes(), &goals) != nil || len(goals.Goals) != 1 || goals.Goals[0].DoneThisWeek != 0 {
		t.Fatalf("summary %d %s", out.Code, out.Body)
	}
	bad := f.call(t, "POST", "/v1/habit-logs", "patient", f.patient.ID, map[string]any{"goal_id": goal.ID, "session_action": "complete"})
	if bad.Code != 400 {
		t.Fatalf("missing retry key accepted %d %s", bad.Code, bad.Body)
	}
}
