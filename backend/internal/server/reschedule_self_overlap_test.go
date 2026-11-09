package server

import (
	"context"
	"encoding/json"
	"malva/backend/internal/clock"
	"malva/backend/internal/store"
	"testing"
	"time"
)

func TestRescheduleIgnoresOwnOldIntervalButRejectsOtherSessions(t *testing.T) {
	for _, role := range []string{"patient", "professional"} {
		t.Run(role, func(t *testing.T) {
			f := newClinicalFixture(t)
			d := clock.Now().Add(96 * time.Hour)
			start := time.Date(d.Year(), d.Month(), d.Day(), 9, 0, 0, 0, clock.Location())
			if _, err := f.db.Exec(`UPDATE care_sessions SET scheduled_at=$2,duration_minutes=60 WHERE id=$1`, f.sessionID, start); err != nil {
				t.Fatal(err)
			}
			if err := f.st.UpsertSchedules(context.Background(), f.prof.ID, []store.ProfessionalSchedule{{DayOfWeek: int(start.Weekday()), StartTime: "09:00", EndTime: "15:00", SlotDurationMinutes: 60, IsActive: true}}); err != nil {
				t.Fatal(err)
			}
			actor := f.prof.ID
			if role == "patient" {
				actor = f.patient.ID
			}
			moved := start.Add(30 * time.Minute)
			out := f.call(t, "POST", "/v1/care-sessions/"+f.sessionID+"/reschedule", role, actor, map[string]any{"scheduled_at": moved.Format(time.RFC3339)})
			if out.Code != 200 {
				t.Fatalf("self overlap blocked %d %s", out.Code, out.Body)
			}
			var response struct {
				Session store.CareSession `json:"session"`
			}
			_ = json.Unmarshal(out.Body.Bytes(), &response)
			if !response.Session.ScheduledAt.Equal(moved) {
				t.Fatalf("did not move %+v", response.Session)
			}
			if _, err := f.st.CreateCareSession(context.Background(), store.CareSession{PatientID: f.patient.ID, ProfessionalID: f.prof.ID, SessionType: "chat", ScheduledAt: start.Add(90 * time.Minute), DurationMinutes: 60}); err != nil {
				t.Fatal(err)
			}
			out = f.call(t, "POST", "/v1/care-sessions/"+f.sessionID+"/reschedule", role, actor, map[string]any{"scheduled_at": start.Add(75 * time.Minute).Format(time.RFC3339)})
			if out.Code != 400 {
				t.Fatalf("another session overlap accepted %d %s", out.Code, out.Body)
			}
		})
	}
}
