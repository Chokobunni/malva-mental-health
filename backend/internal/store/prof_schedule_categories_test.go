package store

import (
	"testing"
)

func TestActiveSchedulesForCategories(t *testing.T) {
	rows := []ProfessionalSchedule{
		{ID: "shared", ServiceCategory: ScheduleShared, IsActive: true},
		{ID: "inactive-chat", ServiceCategory: "quick_chat"},
		{ID: "video", ServiceCategory: "quick_video", IsActive: true},
	}
	for _, test := range []struct {
		category string
		want     string
	}{
		{"quick_chat", ""},
		{"quick_video", "video"},
		{"package", "shared"},
		{ScheduleShared, "shared"},
	} {
		t.Run(test.category, func(t *testing.T) {
			got := activeSchedulesForCategories(rows, test.category)
			if test.want == "" {
				if len(got) != 0 {
					t.Fatalf("inactive override fell back: %+v", got)
				}
			} else if len(got) != 1 || got[0].ID != test.want {
				t.Fatalf("got %+v, want %q", got, test.want)
			}
		})
	}
}

func TestScheduleCategorySnapshotAndMove(t *testing.T) {
	s, db := openGoalTestStore(t)
	ctx := t.Context()
	prof := insertTestUser(t, db, ctx, "professional", "Schedule categories", "schedule-categories")
	shared := ProfessionalSchedule{DayOfWeek: 1, StartTime: "10:00", EndTime: "12:00", IsActive: true}
	chat := shared
	chat.ServiceCategory = "quick_chat"
	chat.IsActive = false
	video := shared
	video.ServiceCategory = "quick_video"
	if err := s.UpsertSchedules(ctx, prof, []ProfessionalSchedule{shared, chat, video}); err != nil {
		t.Fatal(err)
	}
	if err := s.UpsertSchedules(ctx, prof, []ProfessionalSchedule{shared}); err != nil {
		t.Fatal(err)
	}
	rows, err := s.ListSchedulesForProfessional(ctx, prof)
	if err != nil || len(rows) != 3 {
		t.Fatalf("all categories need independent rows, got %+v, err %v", rows, err)
	}
	for _, row := range rows {
		if row.ServiceCategory == "quick_chat" {
			chat.ID = row.ID
		}
	}
	got, err := s.ListActiveSchedulesForProfessional(ctx, prof, "quick_video")
	if err != nil || len(got) != 1 || got[0].ServiceCategory != "quick_video" {
		t.Fatalf("legacy snapshot changed video: %+v, err %v", got, err)
	}
	got, err = s.ListActiveSchedulesForProfessional(ctx, prof, "quick_chat")
	if err != nil || len(got) != 0 {
		t.Fatalf("inactive chat should not fall back: %+v, err %v", got, err)
	}
	chat.ServiceCategory = "package"
	chat.IsActive = true
	if err = s.UpsertSchedules(ctx, prof, []ProfessionalSchedule{chat}); err != nil {
		t.Fatal(err)
	}
	got, err = s.ListActiveSchedulesForProfessional(ctx, prof, "quick_chat")
	if err != nil || len(got) != 1 || got[0].ServiceCategory != ScheduleShared {
		t.Fatalf("moving chat should restore shared fallback: %+v, err %v", got, err)
	}
	got, err = s.ListActiveSchedulesForProfessional(ctx, prof, "package")
	if err != nil || len(got) != 1 || got[0].ID != chat.ID {
		t.Fatalf("moving row should preserve id: %+v, err %v", got, err)
	}
}

func TestScheduleSnapshotPreservesLegacyTimingButRejectsNewShortSlots(t *testing.T) {
	s, db := openGoalTestStore(t)
	ctx := t.Context()
	prof := insertTestUser(t, db, ctx, "professional", "Legacy schedule", "legacy-schedule")
	var id string
	if err := db.QueryRowContext(ctx, `INSERT INTO professional_schedules
		(professional_id,service_category,day_of_week,start_time,end_time,slot_duration_minutes,is_active)
		VALUES($1,'shared',1,'09:00','09:30',30,true) RETURNING id`, prof).Scan(&id); err != nil {
		t.Fatal(err)
	}
	legacy := ProfessionalSchedule{ID: id, ServiceCategory: ScheduleShared, DayOfWeek: 1, StartTime: "09:00", EndTime: "09:30", SlotDurationMinutes: 30, IsActive: false}
	valid := ProfessionalSchedule{ServiceCategory: "quick_chat", DayOfWeek: 2, StartTime: "09:00", EndTime: "11:00", SlotDurationMinutes: 60, IsActive: true}
	if err := s.UpsertSchedules(ctx, prof, []ProfessionalSchedule{legacy, valid}); err != nil {
		t.Fatalf("unchanged legacy timing should not block adding another service or toggling its state: %v", err)
	}
	rows, err := s.ListSchedulesForProfessional(ctx, prof)
	if err != nil || len(rows) != 2 {
		t.Fatalf("rows=%+v err=%v", rows, err)
	}
	for _, row := range rows {
		if row.ID == id && (row.IsActive || row.SlotDurationMinutes != 30) {
			t.Fatalf("legacy history changed: %+v", row)
		}
	}
	legacy.DayOfWeek = 3
	if err := s.UpsertSchedules(ctx, prof, []ProfessionalSchedule{legacy}); err == nil {
		t.Fatal("editing legacy timing below60 accepted")
	}
	legacy.ID = ""
	if err := s.UpsertSchedules(ctx, prof, []ProfessionalSchedule{legacy}); err == nil {
		t.Fatal("new below60 schedule accepted")
	}
	legacy.ID = id
	legacy.DayOfWeek = 1
	legacy.SlotDurationMinutes = 60
	legacy.EndTime = "10:00"
	if err := s.UpsertSchedules(ctx, prof, []ProfessionalSchedule{legacy}); err != nil {
		t.Fatalf("upgrading legacy schedule: %v", err)
	}
}
