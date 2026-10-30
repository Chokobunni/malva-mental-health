package server

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"malva/backend/internal/clock"
	googlecal "malva/backend/internal/google"
)

// fakeMeetCalendar adalah implementasi meetCalendar in-memory: mencatat
// pemanggilan dan mengembalikan nilai/error yang sudah disiapkan test.
// Dipakai agar alur Meet bisa diuji tanpa memanggil Google atau Postgres.
type fakeMeetCalendar struct {
	// CreateMeetEvent
	createCalls   int
	createForUser string
	createOpts    []googlecal.MeetEventOptions
	createEventID string
	createMeetURL string
	// UpdateMeetEvent
	updateCalls []fakeUpdateCall
	updateErr   error
	// CancelMeetEvent
	cancelOnlyCalls []fakeCancelCall
	cancelErr       error
}

type fakeUpdateCall struct {
	professionalUserID string
	eventID            string
	start              time.Time
	end                time.Time
}

type fakeCancelCall struct {
	professionalUserID string
	eventID            string
}

func (f *fakeMeetCalendar) CreateMeetEvent(_ context.Context, professionalUserID string, opts googlecal.MeetEventOptions) (string, string, error) {
	f.createCalls++
	f.createForUser = professionalUserID
	f.createOpts = append(f.createOpts, opts)
	return f.createEventID, f.createMeetURL, nil
}

func (f *fakeMeetCalendar) UpdateMeetEvent(_ context.Context, professionalUserID, eventID string, newStart, newEnd time.Time) error {
	f.updateCalls = append(f.updateCalls, fakeUpdateCall{
		professionalUserID: professionalUserID,
		eventID:            eventID,
		start:              newStart,
		end:                newEnd,
	})
	return f.updateErr
}

func (f *fakeMeetCalendar) CancelMeetEvent(_ context.Context, professionalUserID, eventID string) error {
	f.cancelOnlyCalls = append(f.cancelOnlyCalls, fakeCancelCall{professionalUserID: professionalUserID, eventID: eventID})
	return f.cancelErr
}

// TestScheduleVideoSessionCreatesMeetLink membuktikan jalur "jadwalkan sesi
// video tanpa meeting_url" memanggil pembuatan event Meet dan memakai link
// yang dikembalikan (nilai inilah yang disimpan handler ke care_sessions).
//
// Catatan: penyimpanan baris sesi itu sendiri ada di handler scheduleSession
// yang membutuhkan Postgres; di sini diuji kontrak helper yang menghasilkan
// (eventID, meetingURL) — bagian yang menentukan link tersimpan atau tidak.
func TestScheduleVideoSessionCreatesMeetLink(t *testing.T) {
	fake := &fakeMeetCalendar{
		createEventID: "evt-1",
		createMeetURL: "https://meet.google.com/abc-defg-hij",
	}
	srv := &Server{calendar: fake}
	start := time.Date(2026, 11, 1, 10, 0, 0, 0, clock.Location())
	opts := googlecal.MeetEventOptions{
		Summary:   "Sesi Malva - Pasien Uji",
		StartTime: start,
		EndTime:   start.Add(30 * time.Minute),
	}

	eventID, meetURL, err := srv.createScheduledMeet(t.Context(), srv.calendar, "prof-1", opts)
	if err != nil {
		t.Fatalf("createScheduledMeet error: %v", err)
	}
	if fake.createCalls != 1 {
		t.Fatalf("CreateMeetEvent dipanggil %d kali, mau 1", fake.createCalls)
	}
	if fake.createForUser != "prof-1" {
		t.Errorf("event dibuat untuk %q, mau %q", fake.createForUser, "prof-1")
	}
	if eventID != "evt-1" || meetURL != "https://meet.google.com/abc-defg-hij" {
		t.Errorf("hasil = (%q, %q), mau (%q, %q)", eventID, meetURL, "evt-1", "https://meet.google.com/abc-defg-hij")
	}
	if len(fake.createOpts) != 1 || !fake.createOpts[0].StartTime.Equal(start) {
		t.Errorf("opsi event tidak membawa jam mulai sesi: %+v", fake.createOpts)
	}
	// Tidak boleh ada event yatim yang dibatalkan saat pembuatan berhasil.
	if len(fake.cancelOnlyCalls) != 0 {
		t.Errorf("tidak diharapkan CancelMeetEvent, dapat %+v", fake.cancelOnlyCalls)
	}
}

// TestScheduleVideoSessionWithoutMeetEntryPoint membuktikan event tanpa entry
// point Meet dibatalkan dan tidak ada link yang disimpan — sesi video tidak
// boleh dibuat tanpa ruang pertemuan.
func TestScheduleVideoSessionWithoutMeetEntryPoint(t *testing.T) {
	fake := &fakeMeetCalendar{createEventID: "evt-yatim", createMeetURL: "   "}
	srv := &Server{calendar: fake}
	start := time.Date(2026, 11, 1, 10, 0, 0, 0, clock.Location())

	_, _, err := srv.createScheduledMeet(t.Context(), srv.calendar, "prof-1",
		googlecal.MeetEventOptions{StartTime: start, EndTime: start.Add(30 * time.Minute)})
	if !errors.Is(err, errMeetNoLink) {
		t.Fatalf("error = %v, mau errMeetNoLink", err)
	}
	if len(fake.cancelOnlyCalls) != 1 || fake.cancelOnlyCalls[0].eventID != "evt-yatim" {
		t.Errorf("event tanpa link harus dibatalkan, dapat %+v", fake.cancelOnlyCalls)
	}
}

// TestRescheduleUpdatesMeetEvent membuktikan reschedule memindahkan event Meet
// dengan jam mulai baru dan jam selesai = mulai + durasi lama sesi.
func TestRescheduleUpdatesMeetEvent(t *testing.T) {
	fake := &fakeMeetCalendar{}
	srv := &Server{calendar: fake}
	newStart := time.Date(2026, 11, 2, 14, 30, 0, 0, clock.Location())

	warnings := srv.updateMeetEventOnReschedule(t.Context(), srv.calendar, "prof-1", "evt-1", newStart, 45)
	if len(warnings) != 0 {
		t.Fatalf("tidak diharapkan warning, dapat %+v", warnings)
	}
	if len(fake.updateCalls) != 1 {
		t.Fatalf("UpdateMeetEvent dipanggil %d kali, mau 1", len(fake.updateCalls))
	}
	call := fake.updateCalls[0]
	if call.professionalUserID != "prof-1" || call.eventID != "evt-1" {
		t.Errorf("panggilan update salah sasaran: %+v", call)
	}
	if !call.start.Equal(newStart) {
		t.Errorf("start = %v, mau %v", call.start, newStart)
	}
	wantEnd := newStart.Add(45 * time.Minute)
	if !call.end.Equal(wantEnd) {
		t.Errorf("end = %v, mau %v (mulai + durasi lama 45 menit)", call.end, wantEnd)
	}
}

// TestRescheduleMeetUpdateFailureReturnsWarning membuktikan kegagalan Google
// saat reschedule TIDAK menggagalkan alur (tidak ada error dikembalikan),
// tetapi menghasilkan warning yang bisa ditampilkan ke pengguna.
//
// Catatan: status HTTP 200 beserta field "warnings" dirakit di handler
// rescheduleCareSession yang butuh Postgres; di sini diuji sumber datanya —
// helper ini tidak mengembalikan error sehingga handler tetap menulis 200.
func TestRescheduleMeetUpdateFailureReturnsWarning(t *testing.T) {
	fake := &fakeMeetCalendar{updateErr: errors.New("google calendar 500")}
	srv := &Server{calendar: fake} // logger nil: helper harus tahan Server parsial
	newStart := time.Date(2026, 11, 2, 14, 30, 0, 0, clock.Location())

	warnings := srv.updateMeetEventOnReschedule(t.Context(), srv.calendar, "prof-1", "evt-1", newStart, 30)
	if len(warnings) == 0 {
		t.Fatalf("kegagalan update event harus menghasilkan warning")
	}
	if !strings.Contains(warnings[0], "Google Calendar") {
		t.Errorf("warning = %q, harus menyebut Google Calendar", warnings[0])
	}
	if len(fake.updateCalls) != 1 {
		t.Errorf("UpdateMeetEvent dipanggil %d kali, mau 1", len(fake.updateCalls))
	}
}

// TestCancelByProfessionalDeletesMeetEvent membuktikan pembatalan sesi oleh
// profesional memanggil CancelMeetEvent untuk event milik profesional itu.
func TestCancelByProfessionalDeletesMeetEvent(t *testing.T) {
	fake := &fakeMeetCalendar{}
	srv := &Server{calendar: fake}

	srv.cancelMeetEventBestEffort(t.Context(), srv.calendar, "prof-1", "evt-1")
	if len(fake.cancelOnlyCalls) != 1 {
		t.Fatalf("CancelMeetEvent dipanggil %d kali, mau 1", len(fake.cancelOnlyCalls))
	}
	if got := fake.cancelOnlyCalls[0]; got.professionalUserID != "prof-1" || got.eventID != "evt-1" {
		t.Errorf("panggilan cancel salah sasaran: %+v", got)
	}

	// Sesi tanpa event Google: tidak ada panggilan, tidak panic.
	srv.cancelMeetEventBestEffort(t.Context(), srv.calendar, "prof-1", "")
	if len(fake.cancelOnlyCalls) != 1 {
		t.Errorf("event kosong tidak boleh memanggil CancelMeetEvent, dapat %+v", fake.cancelOnlyCalls)
	}
}
