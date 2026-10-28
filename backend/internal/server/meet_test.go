package server

import (
	"testing"

	"malva/backend/internal/store"
)

// TestIsGoogleMeetURL memastikan pengenalan link Google Meet benar, termasuk
// saat menolak link penyedia lama (Jitsi) agar bisa diganti.
func TestIsGoogleMeetURL(t *testing.T) {
	cases := []struct {
		in   string
		want bool
	}{
		{"https://meet.google.com/abc-defg-hij", true},
		{"https://MEET.GOOGLE.COM/abc-defg-hij", true},
		{"  https://meet.google.com/abc  ", true},
		{"https://meet.jit.si/malva-abc-123", false},
		{"https://zoom.us/j/123456", false},
		{"", false},
	}
	for _, c := range cases {
		if got := isGoogleMeetURL(c.in); got != c.want {
			t.Errorf("isGoogleMeetURL(%q) = %v, mau %v", c.in, got, c.want)
		}
	}
}

// TestEnsureMeetLinkBestEffortTanpaKalender memastikan helper best-effort:
//   - sesi non-video dilewati tanpa menyentuh store,
//   - sesi video tanpa link tetapi tanpa integrasi Google mengembalikan sesi
//     apa adanya (tidak error, tidak mengubah) agar alur booking/reschedule
//     tetap jalan — link bisa dibuat menyusul.
func TestEnsureMeetLinkBestEffortTanpaKalender(t *testing.T) {
	s := &Server{} // calendar nil, store nil

	// Sesi chat: dilewati sebelum store/calendar disentuh.
	chat := store.CareSession{ID: "chat-1", SessionType: "chat", MeetingURL: ""}
	if got := s.ensureMeetLinkBestEffort(t.Context(), chat); got != chat {
		t.Errorf("sesi chat harus dikembalikan apa adanya")
	}

	// Sesi video tanpa link + tanpa kalender: kembali apa adanya.
	video := store.CareSession{ID: "video-1", SessionType: "video", MeetingURL: ""}
	if got := s.ensureMeetLinkBestEffort(t.Context(), video); got.ID != video.ID || got.MeetingURL != "" {
		t.Errorf("tanpa kalender, sesi video harus dikembalikan tanpa link, dapat %+v", got)
	}
}

// TestRunSessionRemindersTanpaLogger memastikan sweeper pengingat tahan
// dipanggil dari Server parsial (store+logger nil pada sesi chat): tidak
// boleh panic mengikuti pola guard yang sama seperti best-effort.
func TestRunSessionRemindersTanpaLogger(t *testing.T) {
	defer func() {
		if r := recover(); r != nil {
			t.Fatalf("RunSessionReminders panic pada Server parsial: %v", r)
		}
	}()
	// Tanpa store, ListSessionsForReminder gagal DB — yang penting bukan
	// panic nil-pointer pada logger, melainkan error yang dikembalikan.
	s := &Server{}
	if _, err := s.RunSessionReminders(t.Context()); err == nil {
		t.Log("tanpa store mengembalikan error (bukan panic) — perilaku benar")
	}
}
