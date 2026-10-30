package google

import (
	"strings"
	"testing"
	"time"

	"malva/backend/internal/clock"
)

// TestBuildMeetEventUsesJakartaTimezone memastikan payload event Calendar
// memakai zona Asia/Jakarta dan mengirim offset +07:00 (bukan Z), serta
// meminta konferensi Google Meet. Ini yang membuat jam sesi benar di kalender
// profesional — kesalahan di sini membuat sesi tampil bergeser 7 jam.
func TestBuildMeetEventUsesJakartaTimezone(t *testing.T) {
	// Instant WIB: 1 Nov 2026 10:00 WIB.
	start := time.Date(2026, 11, 1, 10, 0, 0, 0, clock.Location())
	end := start.Add(45 * time.Minute)

	event := buildMeetEvent(MeetEventOptions{
		Summary:     "Sesi Malva - Pasien Uji",
		Description: "Sesi video konsultasi Malva.",
		StartTime:   start,
		EndTime:     end,
	}, "malva-request-1")

	if event.Start == nil || event.End == nil {
		t.Fatalf("event Start/End tidak boleh nil: %+v", event)
	}
	if event.Start.TimeZone != "Asia/Jakarta" {
		t.Errorf("Start.TimeZone = %q, mau %q", event.Start.TimeZone, "Asia/Jakarta")
	}
	if event.End.TimeZone != "Asia/Jakarta" {
		t.Errorf("End.TimeZone = %q, mau %q", event.End.TimeZone, "Asia/Jakarta")
	}
	if !strings.HasSuffix(event.Start.DateTime, "+07:00") {
		t.Errorf("Start.DateTime = %q, harus berakhiran +07:00", event.Start.DateTime)
	}
	if !strings.HasSuffix(event.End.DateTime, "+07:00") {
		t.Errorf("End.DateTime = %q, harus berakhiran +07:00", event.End.DateTime)
	}

	// Instant yang sama dalam representasi lain tetap dikirim sebagai WIB.
	utcStart := start.In(time.UTC)
	utcEvent := buildMeetEvent(MeetEventOptions{StartTime: utcStart, EndTime: utcStart.Add(30 * time.Minute)}, "malva-request-2")
	if !strings.HasSuffix(utcEvent.Start.DateTime, "+07:00") {
		t.Errorf("Start.DateTime (dari instant UTC) = %q, harus dinormalkan ke +07:00", utcEvent.Start.DateTime)
	}

	if event.ConferenceData == nil || event.ConferenceData.CreateRequest == nil ||
		event.ConferenceData.CreateRequest.ConferenceSolutionKey == nil {
		t.Fatalf("ConferenceData/CreateRequest/ConferenceSolutionKey tidak boleh nil: %+v", event.ConferenceData)
	}
	if got := event.ConferenceData.CreateRequest.ConferenceSolutionKey.Type; got != "hangoutsMeet" {
		t.Errorf("ConferenceSolutionKey.Type = %q, mau %q", got, "hangoutsMeet")
	}
	if got := event.ConferenceData.CreateRequest.RequestId; got != "malva-request-1" {
		t.Errorf("RequestId = %q, mau %q", got, "malva-request-1")
	}
	if event.Summary != "Sesi Malva - Pasien Uji" {
		t.Errorf("Summary = %q tidak sesuai", event.Summary)
	}
}

// TestBuildMeetEventInvitesAttendees memastikan email pasien masuk daftar
// Attendees agar Google mengirim undangan + pengingat, sedangkan email kosong
// atau hanya spasi diabaikan.
func TestBuildMeetEventInvitesAttendees(t *testing.T) {
	start := time.Date(2026, 11, 1, 10, 0, 0, 0, clock.Location())
	event := buildMeetEvent(MeetEventOptions{
		Summary:        "Sesi Malva",
		StartTime:      start,
		EndTime:        start.Add(30 * time.Minute),
		AttendeeEmails: []string{"  pasien@example.test  ", "", "   "},
	}, "malva-request-3")

	if len(event.Attendees) != 1 {
		t.Fatalf("jumlah Attendees = %d, mau 1 (email kosong/spasi diabaikan): %+v", len(event.Attendees), event.Attendees)
	}
	if got := event.Attendees[0].Email; got != "pasien@example.test" {
		t.Errorf("Attendees[0].Email = %q, mau %q (harus di-trim)", got, "pasien@example.test")
	}
}

// TestBuildMeetEventWithoutAttendees memastikan event tanpa email peserta
// tetap valid (event hanya milik profesional).
func TestBuildMeetEventWithoutAttendees(t *testing.T) {
	start := time.Date(2026, 11, 1, 10, 0, 0, 0, clock.Location())
	event := buildMeetEvent(MeetEventOptions{
		Summary:   "Sesi Malva",
		StartTime: start,
		EndTime:   start.Add(30 * time.Minute),
	}, "malva-request-4")
	if len(event.Attendees) != 0 {
		t.Errorf("Attendees harus kosong, dapat %+v", event.Attendees)
	}
}
