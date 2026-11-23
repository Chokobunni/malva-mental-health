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
