package store

import (
	"context"
	"database/sql"
	"os"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

// openLedgerTestStore membuka store untuk test ledger refund/payment_events.
// Skip bila DB tak tersedia atau migrasi 013 belum diterapkan (CI-safe).
func openLedgerTestStore(t *testing.T) (*Store, *sql.DB) {
	t.Helper()
	dsn := os.Getenv("MALVA_TEST_DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://malva:malva_dev_password@localhost:5432/malva?sslmode=disable"
	}
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
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM information_schema.tables
		WHERE table_schema = 'public' AND table_name IN ('care_refunds','payment_events')`).Scan(&n); err != nil || n < 2 {
		_ = db.Close()
		t.Skip("migrasi 013 belum diterapkan (CI-safe)")
	}
	return New(db), db
}

func randomUUID(t *testing.T, db *sql.DB, ctx context.Context) string {
	t.Helper()
	var id string
	if err := db.QueryRowContext(ctx, `SELECT gen_random_uuid()::text`).Scan(&id); err != nil {
		t.Fatalf("gen uuid: %v", err)
	}
	return id
}

// TestRecordRefundIdempotent: idempotency_key yang sama -> satu baris.
func TestRecordRefundIdempotent(t *testing.T) {
	s, db := openLedgerTestStore(t)
	defer func() { _ = db.Close() }()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	pid := randomUUID(t, db, ctx)
	prof := randomUUID(t, db, ctx)
	key := "test:refund:" + pid
	defer func() { _, _ = db.ExecContext(ctx, `DELETE FROM care_refunds WHERE idempotency_key = $1`, key) }()

	r1, err := s.RecordRefund(ctx, CareRefund{
		PatientID: pid, ProfessionalID: prof, Amount: 1000, Kind: "credit",
		IdempotencyKey: key, Reason: "awal",
	})
	if err != nil {
		t.Fatalf("record 1: %v", err)
	}
	if r1.Kind != "credit" || r1.Status != "recorded" || r1.Amount != 1000 {
		t.Fatalf("baris pertama tidak sesuai: %+v", r1)
	}
	// Replay dengan payload berbeda -> harus mengembalikan baris yang sama.
	r2, err := s.RecordRefund(ctx, CareRefund{
		PatientID: pid, ProfessionalID: prof, Amount: 9999, Kind: "credit",
		IdempotencyKey: key, Reason: "retry",
	})
	if err != nil {
		t.Fatalf("record 2: %v", err)
	}
	if r1.ID != r2.ID {
		t.Fatalf("idempotensi gagal: %s != %s", r1.ID, r2.ID)
	}
	if r2.Amount != 1000 {
		t.Fatalf("baris idempoten harus mempertahankan amount awal, dapat %d", r2.Amount)
	}
	var count int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM care_refunds WHERE idempotency_key = $1`, key).Scan(&count); err != nil {
		t.Fatalf("count: %v", err)
	}
	if count != 1 {
		t.Fatalf("harus tepat 1 baris, dapat %d", count)
	}
}

// TestRecordPaymentEventIdempotent: replay event -> inserted=false.
func TestRecordPaymentEventIdempotent(t *testing.T) {
	s, db := openLedgerTestStore(t)
	defer func() { _ = db.Close() }()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	ext := "test-order-" + randomUUID(t, db, ctx)
	defer func() { _, _ = db.ExecContext(ctx, `DELETE FROM payment_events WHERE external_id = $1`, ext) }()

	evt := PaymentEvent{Gateway: "midtrans", ExternalID: ext, EventType: "settlement", GrossAmount: 150000}
	first, err := s.RecordPaymentEvent(ctx, evt)
	if err != nil {
		t.Fatalf("record 1: %v", err)
	}
	if !first {
		t.Fatal("event pertama harus inserted=true")
	}
	second, err := s.RecordPaymentEvent(ctx, evt)
	if err != nil {
		t.Fatalf("record 2: %v", err)
	}
	if second {
		t.Fatal("replay harus inserted=false")
	}
	if err := s.UpdatePaymentEventStatus(ctx, "midtrans", ext, "settlement", "processed", "", ""); err != nil {
		t.Fatalf("update status: %v", err)
	}
}
