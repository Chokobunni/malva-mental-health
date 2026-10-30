package store

import (
	"context"
	"database/sql"
	"fmt"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"

	"malva/backend/internal/clock"
)

// openCareRescheduleTestStore membuka store untuk test reschedule sesi.
// Skip bila DB tidak tersedia atau migrasi 018 (care_sessions.reminder_sent_at)
// belum diterapkan (CI-safe). Pola sama dengan openLedgerTestStore.
//
// Koneksi ditutup lewat `t.Cleanup` (LIFO) supaya cleanup data yang
// didaftarkan setelah ini berjalan lebih dulu dan tidak memakai koneksi
// yang sudah tertutup.
func openCareRescheduleTestStore(t *testing.T) (*Store, *sql.DB) {
	t.Helper()
	dsn := testDatabaseDSN(t)
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Skipf("db unavailable: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		_ = db.Close()
		t.Skipf("db unreachable (CI-safe): %v", err)
	}
	var n int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM information_schema.columns
		WHERE table_schema = 'public' AND table_name = 'care_sessions'
		  AND column_name = 'reminder_sent_at'`).Scan(&n); err != nil || n < 1 {
		_ = db.Close()
		t.Skip("migrasi 018 (care_sessions.reminder_sent_at) belum diterapkan (CI-safe)")
	}
	t.Cleanup(func() { _ = db.Close() })
	return New(db), db
}

// TestRescheduleResetsReminder membuktikan RescheduleCareSession mengosongkan
// reminder_sent_at. Tanpa reset, sweeper pengingat menganggap pengingat untuk
// jadwal lama sudah terkirim sehingga pasien tidak pernah diingatkan pada
// jadwal baru.
func TestRescheduleResetsReminder(t *testing.T) {
	s, db := openCareRescheduleTestStore(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	suffix := fmt.Sprintf("%d", clock.Now().UnixNano())
	insertUser := func(email, role, displayName string) string {
		var id string
		if err := db.QueryRowContext(ctx, `INSERT INTO users (email, password_hash, role, display_name)
			VALUES ($1,'test-hash',$2,$3) RETURNING id::text`,
			email, role, displayName).Scan(&id); err != nil {
			t.Fatalf("insert user %s: %v", email, err)
		}
		return id
	}
	patientID := insertUser("reschedule-pasien-"+suffix+"@malva.test", "patient", "Pasien "+suffix)
	profID := insertUser("reschedule-prof-"+suffix+"@malva.test", "professional", "Profesional "+suffix)

	var packageID string
	if err := db.QueryRowContext(ctx, `INSERT INTO care_packages
		(patient_id, professional_id, total_sessions, validity_days, price, status, expires_at)
		VALUES ($1,$2,4,42,200000,'active', now() + interval '30 days')
		RETURNING id::text`, patientID, profID).Scan(&packageID); err != nil {
		t.Fatalf("insert paket: %v", err)
	}

	// Jadwal lama di masa depan (validasi reschedule menolak jadwal lampau)
	// dengan reminder_sent_at sudah terisi. Truncate ke mikrodetik agar nilai
	// yang dibaca balik dari Postgres identik dengan yang dikirim.
	oldTime := clock.Now().Add(48 * time.Hour).Truncate(time.Microsecond)
	newTime := clock.Now().Add(96 * time.Hour).Truncate(time.Microsecond)
	reminderAt := clock.Now().Truncate(time.Microsecond)

	var sessionID string
	if err := db.QueryRowContext(ctx, `INSERT INTO care_sessions
		(package_id, patient_id, professional_id, session_type, scheduled_at,
		 duration_minutes, status, reminder_sent_at)
		VALUES ($1,$2,$3,'video',$4,30,'scheduled',$5)
		RETURNING id::text`,
		packageID, patientID, profID, oldTime, reminderAt).Scan(&sessionID); err != nil {
		t.Fatalf("insert sesi: %v", err)
	}

	t.Cleanup(func() {
		cctx, ccancel := context.WithTimeout(context.Background(), 30*time.Second)
		defer ccancel()
		// care_sessions/care_packages sengaja tanpa FK ke users (lihat 012),
		// jadi barisnya harus dibersihkan eksplisit sebelum users dihapus.
		_, _ = db.ExecContext(cctx, `DELETE FROM care_sessions WHERE patient_id = $1`, patientID)
		_, _ = db.ExecContext(cctx, `DELETE FROM care_packages WHERE patient_id = $1`, patientID)
		cleanupTestUsers(t, db, patientID, profID)
	})

	// Prasyarat: reminder pada jadwal lama memang sudah terisi.
	var reminderBefore sql.NullTime
	if err := db.QueryRowContext(ctx,
		`SELECT reminder_sent_at FROM care_sessions WHERE id = $1`, sessionID).Scan(&reminderBefore); err != nil {
		t.Fatalf("baca reminder sebelum reschedule: %v", err)
	}
	if !reminderBefore.Valid {
		t.Fatalf("prasyarat gagal: reminder_sent_at harus terisi sebelum reschedule")
	}

	got, err := s.RescheduleCareSession(ctx, sessionID, newTime)
	if err != nil {
		t.Fatalf("reschedule: %v", err)
	}
	if got.ID != sessionID {
		t.Fatalf("sesi hasil harus %s, dapat %s", sessionID, got.ID)
	}
	if got.Status != "scheduled" {
		t.Fatalf("status setelah reschedule harus 'scheduled', dapat %q", got.Status)
	}
	if got.RescheduleCount != 1 {
		t.Fatalf("reschedule_count harus 1, dapat %d", got.RescheduleCount)
	}
	if got.ScheduledAt.Unix() != newTime.Unix() {
		t.Fatalf("scheduled_at DTO harus %s, dapat %s", newTime, got.ScheduledAt)
	}

	// Bukti utama: reminder_sent_at kembali NULL di DB.
	var reminderAfter sql.NullTime
	var scheduledAt time.Time
	if err := db.QueryRowContext(ctx,
		`SELECT reminder_sent_at, scheduled_at FROM care_sessions WHERE id = $1`,
		sessionID).Scan(&reminderAfter, &scheduledAt); err != nil {
		t.Fatalf("baca sesi setelah reschedule: %v", err)
	}
	if reminderAfter.Valid {
		t.Fatalf("reminder_sent_at harus NULL setelah reschedule, dapat %s", reminderAfter.Time)
	}
	if scheduledAt.Unix() != newTime.Unix() {
		t.Fatalf("scheduled_at di DB harus %s, dapat %s", newTime, scheduledAt)
	}
	if scheduledAt.Unix() == oldTime.Unix() {
		t.Fatalf("scheduled_at tidak boleh tetap di jadwal lama %s", oldTime)
	}
}
