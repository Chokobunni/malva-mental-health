package store

import (
	"context"
	"database/sql"
	"strings"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"

	"malva/backend/internal/clock"
)

// TestCreateCareSessionRejectsVideoWithoutLink membuktikan invarian inti:
// sesi video TIDAK BISA disimpan tanpa link ruang pertemuan.
//
// Pemeriksaan ini sengaja diletakkan sebelum transaksi database, sehingga bisa
// diuji tanpa Postgres. Inilah satu-satunya pintu INSERT care_sessions, jadi
// seluruh jalur pembuatan sesi (aktivasi pembayaran, jadwal profesional) ikut
// tunduk pada aturan yang sama.
func TestCreateCareSessionRejectsVideoWithoutLink(t *testing.T) {
	st := New(nil)
	_, err := st.CreateCareSession(context.Background(), CareSession{
		PatientID:       "00000000-0000-0000-0000-000000000001",
		ProfessionalID:  "00000000-0000-0000-0000-000000000002",
		SessionType:     "video",
		ScheduledAt:     clock.Now().Add(2 * time.Hour),
		DurationMinutes: 30,
	})
	if err == nil {
		t.Fatal("sesi video tanpa link harus ditolak, tetapi berhasil dibuat")
	}
	if !strings.Contains(err.Error(), "wajib memiliki link") {
		t.Fatalf("pesan error = %q, mau memuat \"wajib memiliki link\"", err.Error())
	}
}

// TestCreateCareSessionVideoWithLinkAccepted memastikan penolakan di atas
// bukan sekadar menolak semua sesi video: bila link Google Meet disertakan,
// sesi tersimpan apa adanya.
func TestCreateCareSessionVideoWithLinkAccepted(t *testing.T) {
	dsn := testDatabaseDSN(t)
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Skipf("db unavailable: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		t.Skipf("db unreachable (CI-safe): %v", err)
	}
	s := New(db)

	// care_sessions tidak punya FK ke users (lihat migrasi 012), jadi id acak
	// cukup dan tidak perlu menyemai akun.
	newID := func() string {
		var id string
		if err := db.QueryRowContext(ctx, `SELECT gen_random_uuid()::text`).Scan(&id); err != nil {
			t.Fatalf("gen_random_uuid: %v", err)
		}
		return id
	}
	patientID, profID := newID(), newID()
	const wantURL = "https://meet.google.com/abc-defg-hij"

	cs, err := s.CreateCareSession(ctx, CareSession{
		PatientID:       patientID,
		ProfessionalID:  profID,
		SessionType:     "video",
		ScheduledAt:     clock.Now().Add(48 * time.Hour).Truncate(time.Microsecond),
		DurationMinutes: 30,
		MeetingURL:      wantURL,
		GoogleEventID:   "evt-video-wajib-link",
	})
	if err != nil {
		t.Fatalf("sesi video dengan link harus diterima: %v", err)
	}
	t.Cleanup(func() {
		cctx, ccancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer ccancel()
		_, _ = db.ExecContext(cctx, `DELETE FROM care_sessions WHERE id = $1`, cs.ID)
	})
	if cs.MeetingURL != wantURL {
		t.Errorf("meeting_url tersimpan %q, mau %q", cs.MeetingURL, wantURL)
	}
	if cs.GoogleEventID != "evt-video-wajib-link" {
		t.Errorf("google_event_id tersimpan %q", cs.GoogleEventID)
	}
}
