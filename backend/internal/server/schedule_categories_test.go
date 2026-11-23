package server

import (
	"testing"
	"time"

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
