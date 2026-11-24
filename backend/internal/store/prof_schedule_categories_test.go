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
		{"package", ""},
		{ScheduleShared, "shared"},
	} {
		t.Run(test.category, func(t *testing.T) {
			got := activeSchedulesForCategories(rows, nil, test.category)
			if test.want == "" {
				if len(got) != 0 {
					t.Fatalf("inactive override fell back: %+v", got)
				}
			} else if len(got) != 1 || got[0].ID != test.want {
				t.Fatalf("got %+v, want %q", got, test.want)
			}
		})
	}
	got := activeSchedulesForCategories(rows, map[string]bool{
		"quick_chat": true, "quick_video": false, "package": true,
	})
	if len(got) != 2 || got[0].ID != "shared" || got[1].ID != "video" {
		t.Fatalf("explicit preferences must deduplicate shared schedules: %+v", got)
	}
	got = activeSchedulesForCategories(rows, map[string]bool{"quick_chat": false}, "quick_chat")
	if len(got) != 0 {
		t.Fatalf("custom mode must keep inactive rows inactive: %+v", got)
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

func TestSchedulePreferenceRestoresStoredCategoryRows(t *testing.T) {
	s, db := openGoalTestStore(t)
	ctx := t.Context()
	prof := insertTestUser(t, db, ctx, "professional", "Schedule preference", "schedule-preference")
	schedules := []ProfessionalSchedule{
		{ServiceCategory: ScheduleShared, DayOfWeek: 1, StartTime: "10:00", EndTime: "12:00", IsActive: true},
		{ServiceCategory: "quick_chat", DayOfWeek: 2, StartTime: "10:00", EndTime: "12:00", IsActive: true},
	}
	if err := s.UpsertSchedules(ctx, prof, schedules); err != nil {
		t.Fatal(err)
	}
	for _, step := range []struct {
		preferences map[string]bool
		category    string
		want        string
	}{
		{nil, "package", ""},
		{map[string]bool{"package": true, "quick_chat": true}, "quick_chat", ScheduleShared},
		{nil, "package", ScheduleShared},
		{map[string]bool{"quick_chat": false}, "quick_chat", "quick_chat"},
	} {
		if err := s.UpsertScheduleSettings(ctx, prof, nil, step.preferences); err != nil {
			t.Fatal(err)
		}
		active, err := s.ListActiveSchedulesForProfessional(ctx, prof, step.category)
		if err != nil {
			t.Fatal(err)
		}
		if step.want == "" {
			if len(active) != 0 {
				t.Fatalf("new package should start in custom mode: %+v", active)
			}
		} else if len(active) != 1 || active[0].ServiceCategory != step.want {
			t.Fatalf("%s selected %+v, want %s", step.category, active, step.want)
		}
	}
	settings, err := s.GetProfessionalScheduleSettings(ctx, prof)
	if err != nil || len(settings.Schedules) != 2 || !settings.UsePrimarySchedule["package"] {
		t.Fatalf("partial preference update discarded settings: %+v, error %v", settings, err)
	}
}

func TestLegacyScheduleWriteCanOverrideMigratedFallback(t *testing.T) {
	s, db := openGoalTestStore(t)
	ctx := t.Context()
	prof := insertTestUser(t, db, ctx, "professional", "Legacy schedule preference", "legacy-schedule-preference")
	if _, err := db.ExecContext(ctx, `INSERT INTO professional_schedule_preferences
		(professional_id, service_category, use_primary_schedule, is_explicit)
		VALUES ($1, 'package', true, false), ($1, 'quick_chat', true, true)`, prof); err != nil {
		t.Fatal(err)
	}
	slot := ProfessionalSchedule{DayOfWeek: 1, StartTime: "10:00", EndTime: "12:00", IsActive: true}
	packageSlot, chatSlot := slot, slot
	packageSlot.ServiceCategory = "package"
	chatSlot.ServiceCategory = "quick_chat"
	if err := s.UpsertSchedules(ctx, prof, []ProfessionalSchedule{slot, packageSlot, chatSlot}); err != nil {
		t.Fatal(err)
	}
	for category, want := range map[string]string{"package": "package", "quick_chat": ScheduleShared} {
		got, err := s.ListActiveSchedulesForProfessional(ctx, prof, category)
		if err != nil || len(got) != 1 || got[0].ServiceCategory != want {
			t.Fatalf("%s selected %+v, err %v, want %s", category, got, err, want)
		}
	}
}
