package store

import (
	"context"
	"database/sql"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

// ============================================================
// "Hadir" hanya menandai kehadiran — bukan menyelesaikan sesi.
//
// Invariant yang dijaga:
//   - UpdateCareSessionStatus("attended") TIDAK mengubah status (tetap
//     scheduled), mengisi attended_marked_at, dan TIDAK membuat baris earnings.
//   - completeAttendedSessions menyelesaikan sesi yang sudah hadir & lewat
//     durasi (status -> completed) dan mencatat earnings bila ada pembayaran.
//
// Test ini butuh Postgres nyata; di-SKIP tanpa MALVA_TEST_DATABASE_URL.
// ============================================================

func attendedTestStore(t *testing.T) (*Store, *sql.DB, context.Context) {
	t.Helper()
	dsn := testDatabaseDSN(t)
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Skipf("db unavailable: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	t.Cleanup(cancel)
	if err := db.PingContext(ctx); err != nil {
		t.Skipf("db unreachable (CI-safe): %v", err)
	}
	return New(db), db, ctx
}

func mustUUID(t *testing.T, db *sql.DB, ctx context.Context) string {
	t.Helper()
	var id string
	if err := db.QueryRowContext(ctx, `SELECT gen_random_uuid()::text`).Scan(&id); err != nil {
		t.Fatalf("gen_random_uuid: %v", err)
	}
	return id
}

func TestUpdateCareSessionStatusAttended(t *testing.T) {
	s, db, ctx := attendedTestStore(t)

	sessionID := mustUUID(t, db, ctx)
	patientID := mustUUID(t, db, ctx)
	profID := mustUUID(t, db, ctx)
	if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions
		(id, patient_id, professional_id, session_type, scheduled_at, duration_minutes, status)
		VALUES ($1,$2,$3,'chat',now(),30,'scheduled')`, sessionID, patientID, profID); err != nil {
		t.Fatalf("seed care_session: %v", err)
	}
	t.Cleanup(func() {
		cctx, ccancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer ccancel()
		_, _ = db.ExecContext(cctx, `DELETE FROM care_sessions WHERE id = $1`, sessionID)
	})

	updated, err := s.UpdateCareSessionStatus(ctx, sessionID, "attended", "", "")
	if err != nil {
		t.Fatalf("UpdateCareSessionStatus(attended): %v", err)
	}
	if updated.Status != "scheduled" {
		t.Errorf("status setelah attended = %q, mau tetap %q", updated.Status, "scheduled")
	}
	if updated.AttendedMarkedAt == nil {
		t.Errorf("attended_marked_at harus terisi setelah attended")
	}
	// Tidak boleh ada earnings baru: attended bukan penyelesaian sesi.
	var n int
	if err := db.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM earnings WHERE session_id = $1`, sessionID).Scan(&n); err != nil {
		t.Fatalf("count earnings: %v", err)
	}
	if n != 0 {
		t.Errorf("baris earnings untuk sesi attended = %d, mau 0", n)
	}
}

func TestCompleteAttendedSessions(t *testing.T) {
	s, db, ctx := attendedTestStore(t)

	// Seed rantai pembayaran agar earnings bisa dicatat saat sesi diselesaikan.
	patientID := mustUUID(t, db, ctx)
	profID := mustUUID(t, db, ctx)
	if _, err := db.ExecContext(ctx, `INSERT INTO users (id,email,password_hash,role,display_name)
		VALUES ($1,$2,'x','patient','Pasien Uji'), ($3,$4,'x','professional','Prof Uji')`,
		patientID, patientID+"@attended.test", profID, profID+"@attended.test"); err != nil {
		t.Fatalf("seed users: %v", err)
	}

	var bookingID string
	if err := db.QueryRowContext(ctx, `INSERT INTO bookings
		(patient_id, professional_id, service_type, session_type, booking_date, slot_time, price, status)
		VALUES ($1,$2,'quick_consult','chat', CURRENT_DATE, '10:00', 100000, 'paid')
		RETURNING id::text`, patientID, profID).Scan(&bookingID); err != nil {
		t.Fatalf("seed booking: %v", err)
	}
	var paymentID string
	if err := db.QueryRowContext(ctx, `INSERT INTO payments
		(booking_id, payment_method, gross_amount, platform_fee_amount, net_amount, reference, status)
		VALUES ($1,'qris',100000,10000,90000, 'attended-' || gen_random_uuid()::text, 'paid')
		RETURNING id::text`, bookingID).Scan(&paymentID); err != nil {
		t.Fatalf("seed payment: %v", err)
	}

	// Sesi scheduled yang sudah hadir & lewat durasi (mulai 60 menit lalu, 30
	// menit) -> scheduled_at + 30m <= now().
	var sessionID string
	if err := db.QueryRowContext(ctx, `INSERT INTO care_sessions
		(booking_id, patient_id, professional_id, session_type, scheduled_at, duration_minutes, status, attended_marked_at)
		VALUES ($1,$2,$3,'chat', now() - interval '60 minutes', 30, 'scheduled', now())
		RETURNING id::text`, bookingID, patientID, profID).Scan(&sessionID); err != nil {
		t.Fatalf("seed care_session: %v", err)
	}

	t.Cleanup(func() {
		cctx, ccancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer ccancel()
		_, _ = db.ExecContext(cctx, `DELETE FROM earnings WHERE payment_id = $1`, paymentID)
		_, _ = db.ExecContext(cctx, `DELETE FROM care_sessions WHERE id = $1`, sessionID)
		_, _ = db.ExecContext(cctx, `DELETE FROM payments WHERE id = $1`, paymentID)
		_, _ = db.ExecContext(cctx, `DELETE FROM bookings WHERE id = $1`, bookingID)
		_, _ = db.ExecContext(cctx, `DELETE FROM users WHERE id IN ($1,$2)`, patientID, profID)
	})

	if _, err := s.completeAttendedSessions(ctx); err != nil {
		t.Fatalf("completeAttendedSessions: %v", err)
	}

	var status string
	if err := db.QueryRowContext(ctx,
		`SELECT status FROM care_sessions WHERE id = $1`, sessionID).Scan(&status); err != nil {
		t.Fatalf("read status: %v", err)
	}
	if status != "completed" {
		t.Errorf("status setelah auto-selesai = %q, mau %q", status, "completed")
	}

	var earnings int
	if err := db.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM earnings WHERE payment_id = $1 AND session_id = $2`,
		paymentID, sessionID).Scan(&earnings); err != nil {
		t.Fatalf("count earnings: %v", err)
	}
	if earnings != 1 {
		t.Errorf("baris earnings untuk sesi yang auto-selesai = %d, mau 1", earnings)
	}
}
