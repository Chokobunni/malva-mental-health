package server

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/store"
)

func TestScheduleSlotStartsDeduplicatesServiceUnion(t *testing.T) {
	day := time.Date(2026, 11, 23, 0, 0, 0, 0, wibLoc)
	schedules := []store.ProfessionalSchedule{
		{ServiceCategory: "package", DayOfWeek: 1, StartTime: "10:00:00",
			EndTime: "12:00:00", SlotDurationMinutes: 120},
		{ServiceCategory: "quick_chat", DayOfWeek: 1, StartTime: "10:00",
			EndTime: "12:00", SlotDurationMinutes: 60},
		{ServiceCategory: "quick_video", DayOfWeek: 2, StartTime: "10:00",
			EndTime: "12:00", SlotDurationMinutes: 60},
	}
	starts, durations := scheduleSlotStarts(schedules, day, true)
	if len(starts) != 2 || starts[0].Hour() != 10 || starts[1].Hour() != 11 ||
		durations[0] != 60 || durations[1] != 60 {
		t.Fatalf("got starts=%+v durations=%+v", starts, durations)
	}
	starts, durations = scheduleSlotStarts(schedules[:1], day, false)
	if len(starts) != 1 || starts[0].Hour() != 10 || durations[0] != 120 {
		t.Fatalf("package duration was lost: starts=%+v durations=%+v", starts, durations)
	}
}

func TestUpdateMySchedulesLegacyTimingIsOwnerBoundAndUnchanged(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	prof := createIdentityTestUser(t, db, st, "professional", nil)
	var id string
	if err := db.QueryRowContext(context.Background(), `INSERT INTO professional_schedules
		(professional_id,service_category,day_of_week,start_time,end_time,slot_duration_minutes,is_active)
		VALUES($1,'shared',1,'09:00','09:30',30,true) RETURNING id`, prof.ID).Scan(&id); err != nil {
		t.Fatal(err)
	}
	srv := &Server{store: st}
	input := scheduleInput{ID: id, ServiceCategory: "shared", DayOfWeek: 1, StartTime: "09:00", EndTime: "09:30", SlotDurationMinutes: 30}
	other := createIdentityTestUser(t, db, st, "professional", nil)
	body, err := json.Marshal(updateSchedulesRequest{Schedules: []scheduleInput{input}})
	if err != nil {
		t.Fatal(err)
	}
	otherResult := httptest.NewRecorder()
	srv.updateMySchedules(otherResult, httptest.NewRequest(http.MethodPut, "/v1/professional/schedules", strings.NewReader(string(body))), auth.Claims{Subject: other.ID, Role: "professional"})
	if otherResult.Code != http.StatusBadRequest {
		t.Fatalf("other owner reused legacy ID: status=%d", otherResult.Code)
	}
	for _, test := range []struct {
		name   string
		change func(*scheduleInput)
		want   int
	}{
		{"unchanged legacy snapshot", func(*scheduleInput) {}, http.StatusOK},
		{"new short schedule", func(s *scheduleInput) { s.ID = "" }, http.StatusBadRequest},
		{"changed legacy day", func(s *scheduleInput) { s.DayOfWeek = 2 }, http.StatusBadRequest},
		{"changed legacy category", func(s *scheduleInput) { s.ServiceCategory = "package" }, http.StatusBadRequest},
		{"short window", func(s *scheduleInput) { s.SlotDurationMinutes = 60 }, http.StatusBadRequest},
		{"full hour upgrade", func(s *scheduleInput) { s.SlotDurationMinutes = 60; s.EndTime = "10:00" }, http.StatusOK},
	} {
		t.Run(test.name, func(t *testing.T) {
			sch := input
			test.change(&sch)
			body, err := json.Marshal(updateSchedulesRequest{Schedules: []scheduleInput{sch}})
			if err != nil {
				t.Fatal(err)
			}
			recorder := httptest.NewRecorder()
			srv.updateMySchedules(recorder, httptest.NewRequest(http.MethodPut, "/v1/professional/schedules", strings.NewReader(string(body))), auth.Claims{Subject: prof.ID, Role: "professional"})
			if recorder.Code != test.want {
				t.Fatalf("status=%d body=%s", recorder.Code, recorder.Body.String())
			}
		})
	}
}
