package server

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"testing"
	"time"

	"malva/backend/internal/clock"
	"malva/backend/internal/store"
)

// ============================================================
// BACKFILL LINK MEET PERIODIK (SWEEPER 10 MENIT)
//
// Aturan bisnis yang dikunci:
//   - Sesi video berbayar yang lahir "menunggu link" tidak boleh menunggu
//     server restart atau pengingat 15-25 menit sebelum sesi untuk mendapat
//     link. Backfill dijalankan setiap tick sweeper.
//   - Sesi milik profesional yang Google-nya belum siap DILEWATI tanpa
//     memanggil Google (tidak membanjiri log, tidak memanggil Google sia-sia),
//     tetapi otomatis terisi begitu profesional menyambungkan Google.
//   - Sesi yang gagal dibuatkan link tepat pada tick pengingat tetap dicoba
//     ulang oleh backfill berikutnya (jalur retry nyata, bukan sekali coba).
// ============================================================

// backfillFixture menyiapkan pasien + profesional dan helper membuat sesi
// video "menunggu link" (tanpa meeting_url).
type backfillFixture struct {
	srv     *Server
	db      *sql.DB
	st      *store.Store
	patient store.User
	prof    store.User
	fake    *fakeMeetCalendar
}

func newBackfillFixture(t *testing.T, db *sql.DB, st *store.Store, cal meetCalendar) backfillFixture {
	t.Helper()
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      "STR-BF-" + fmt.Sprint(time.Now().UnixNano()),
		SIPNumber:      "SIP-BF-" + fmt.Sprint(time.Now().UnixNano()),
	})
	// care_sessions tidak punya FK ke users: hapus manual SEBELUM user
	// dihapus (cleanup pengguna didaftarkan lebih dulu oleh
	// createIdentityTestUser, jadi cleanup ini berjalan lebih dulu — LIFO).
	t.Cleanup(func() {
		cctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		_, _ = db.ExecContext(cctx, `DELETE FROM care_sessions WHERE patient_id = $1`, patient.ID)
	})

	srv := newOnboardingTestServer(db)
	srv.calendar = cal
	fake, _ := cal.(*fakeMeetCalendar)
	return backfillFixture{srv: srv, db: db, st: st, patient: patient, prof: prof, fake: fake}
}

// pendingSession membuat sesi video tanpa link yang mulai dalam startIn.
func (f backfillFixture) pendingSession(t *testing.T, startIn time.Duration) store.CareSession {
	t.Helper()
	cs, err := f.st.CreateCareSession(context.Background(), store.CareSession{
		PatientID:        f.patient.ID,
		ProfessionalID:   f.prof.ID,
		SessionType:      "video",
		ScheduledAt:      clock.Now().Add(startIn),
		DurationMinutes:  60,
		Status:           "scheduled",
		AllowPendingMeet: true,
	})
	if err != nil {
		t.Fatalf("buat sesi menunggu link: %v", err)
	}
	return cs
}

// TestRunMeetLinkBackfillSkipsUnreadyProfessionalThenFillsWhenReady mengunci
// dua hal sekaligus: (a) Google tidak dipanggil untuk profesional yang belum
// siap (mencegah log spam & panggilan sia-sia tiap tick), dan (b) begitu
// profesional menyambungkan Google, tick berikutnya mengisi link otomatis
// tanpa aksi manual.
func TestRunMeetLinkBackfillSkipsUnreadyProfessionalThenFillsWhenReady(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	const wantURL = "https://meet.google.com/bfg-hij-klm"
	fake := &fakeMeetCalendar{createEventID: "evt-bf", createMeetURL: wantURL}
	f := newBackfillFixture(t, db, st, fake)
	session := f.pendingSession(t, 72*time.Hour)

	// Profesional belum menyambungkan Google: tidak ada panggilan ke Google.
	created, err := f.srv.RunMeetLinkBackfill(t.Context(), 25)
	if err != nil {
		t.Fatalf("backfill tidak boleh error saat profesional belum siap: %v", err)
	}
	if created != 0 {
		t.Errorf("created = %d, mau 0 saat profesional belum siap", created)
	}
	if fake.createCalls != 0 {
		t.Errorf("Google tidak boleh dipanggil untuk profesional belum siap, dapat %d panggilan", fake.createCalls)
	}

	// Profesional menyambungkan Google Calendar -> tick berikutnya mengisi link.
	linkReadyProfessional(t, st, f.prof.ID)
	created, err = f.srv.RunMeetLinkBackfill(t.Context(), 25)
	if err != nil {
		t.Fatalf("backfill tidak boleh error setelah profesional siap: %v", err)
	}
	if created != 1 {
		t.Fatalf("created = %d, mau 1 setelah profesional siap", created)
	}
	if fake.createCalls != 1 {
		t.Errorf("CreateMeetEvent dipanggil %d kali, mau 1", fake.createCalls)
	}
	saved, err := st.GetCareSession(context.Background(), session.ID)
	if err != nil {
		t.Fatalf("baca sesi: %v", err)
	}
	if saved.MeetingURL != wantURL {
		t.Errorf("meeting_url = %q, mau %q", saved.MeetingURL, wantURL)
	}
}

// TestRunMeetLinkBackfillServerNotConfigured memastikan server tanpa integrasi
// Google tidak panic dan melaporkan ErrMeetUnavailable (dipakai sweeper untuk
// tetap diam, bukan Warn tiap 10 menit).
func TestRunMeetLinkBackfillServerNotConfigured(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	f := newBackfillFixture(t, db, st, nil) // calendar nil = server belum dikonfigurasi
	f.pendingSession(t, 48*time.Hour)

	created, err := f.srv.RunMeetLinkBackfill(t.Context(), 25)
	if !errors.Is(err, ErrMeetUnavailable) {
		t.Fatalf("error = %v, mau ErrMeetUnavailable", err)
	}
	if created != 0 {
		t.Errorf("created = %d, mau 0", created)
	}
}

// TestRunMeetLinkBackfillRetriesAfterReminderTickFailure adalah bukti retry
// (celah C2): sesi yang gagal dibuatkan link TEPAT pada tick pengingat tidak
// boleh berakhir tanpa link selamanya. Setelah MarkSessionReminderSent
// mengunci sesi (tidak diproses pengingat lagi), backfill periodik berikutnya
// harus mencoba lagi dan berhasil saat Google pulih.
func TestRunMeetLinkBackfillRetriesAfterReminderTickFailure(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	fake := &fakeMeetCalendar{createErr: errors.New("google calendar 503")}
	f := newBackfillFixture(t, db, st, fake)
	linkReadyProfessional(t, st, f.prof.ID)
	// Mulai 20 menit lagi: masuk jendela pengingat 15-25 menit.
	session := f.pendingSession(t, 20*time.Minute)

	ctx := context.Background()
	// Prasyarat: sesi memang masuk jendela pengingat.
	if !sessionInReminderWindow(t, st, session.ID) {
		t.Fatal("prasyarat gagal: sesi tidak masuk jendela pengingat 15-25 menit")
	}

	if _, err := f.srv.RunSessionReminders(t.Context()); err != nil {
		t.Fatalf("pengingat sesi gagal: %v", err)
	}

	// Google gagal pada tick itu: sesi tetap tanpa link, dan pengingat sudah
	// terkunci sehingga RunSessionReminders tidak akan memprosesnya lagi.
	after, err := st.GetCareSession(ctx, session.ID)
	if err != nil {
		t.Fatalf("baca sesi setelah pengingat: %v", err)
	}
	if strings.TrimSpace(after.MeetingURL) != "" {
		t.Fatalf("meeting_url = %q, mau kosong saat Google gagal", after.MeetingURL)
	}
	if sessionInReminderWindow(t, st, session.ID) {
		t.Fatal("pengingat harus sudah terkunci (reminder_sent_at) agar retry terbukti datang dari backfill")
	}

	// Google pulih: backfill berikutnya (tick 10 menit) mencoba lagi.
	const wantURL = "https://meet.google.com/ret-ry2-ok"
	fake.createErr = nil
	fake.createEventID = "evt-retry"
	fake.createMeetURL = wantURL

	created, err := f.srv.RunMeetLinkBackfill(t.Context(), 25)
	if err != nil {
		t.Fatalf("backfill tidak boleh error: %v", err)
	}
	if created != 1 {
		t.Fatalf("created = %d, mau 1 (sesi yang gagal di tick pengingat harus dicoba ulang)", created)
	}
	saved, err := st.GetCareSession(ctx, session.ID)
	if err != nil {
		t.Fatalf("baca sesi setelah backfill: %v", err)
	}
	if saved.MeetingURL != wantURL {
		t.Errorf("meeting_url = %q, mau %q", saved.MeetingURL, wantURL)
	}
}

// sessionInReminderWindow melaporkan apakah sesi masih muncul di daftar
// pengingat yang belum terkirim (yaitu reminder_sent_at masih NULL).
func sessionInReminderWindow(t *testing.T, st *store.Store, sessionID string) bool {
	t.Helper()
	now := clock.Now()
	sessions, err := st.ListSessionsForReminder(context.Background(),
		now.Add(15*time.Minute), now.Add(25*time.Minute))
	if err != nil {
		t.Fatalf("baca daftar pengingat: %v", err)
	}
	for _, cs := range sessions {
		if cs.ID == sessionID {
			return true
		}
	}
	return false
}
