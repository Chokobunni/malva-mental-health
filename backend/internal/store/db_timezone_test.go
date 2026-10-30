package store

import (
	"context"
	"database/sql"
	"os"
	"testing"
	"time"
)

// TestOpenSQLDummyDSN memastikan OpenSQL tidak error untuk DSN apa pun dan
// mengembalikan handle *sql.DB (koneksi tetap lazy, tidak menyentuh jaringan).
func TestOpenSQLDummyDSN(t *testing.T) {
	db, err := OpenSQL("postgres://malva:malva@127.0.0.1:5432/malva?sslmode=disable")
	if err != nil {
		t.Fatalf("OpenSQL DSN dummy tidak boleh error: %v", err)
	}
	if db == nil {
		t.Fatal("OpenSQL harus mengembalikan *sql.DB non-nil")
	}
	defer func() { _ = db.Close() }()
}

// TestOpenSQLDecodesTimestamptzInWIB memastikan hasil scan timestamptz berada
// di zona WIB (+7), bukan UTC. Skip bila DB tak tersedia (pola sama dengan
// care_refund_test.go).
func TestOpenSQLDecodesTimestamptzInWIB(t *testing.T) {
	dsn := os.Getenv("MALVA_TEST_DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://malva:malva_dev_password@localhost:5432/malva?sslmode=disable"
	}
	db, err := OpenSQL(dsn)
	if err != nil {
		t.Skipf("db unavailable: %v", err)
	}
	defer func() { _ = db.Close() }()

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		t.Skipf("db unreachable (CI-safe): %v", err)
	}

	var now time.Time
	if err := db.QueryRowContext(ctx, `SELECT now()`).Scan(&now); err != nil {
		t.Fatalf("scan now(): %v", err)
	}
	assertWIB(t, "now()", now)

	var createdAt time.Time
	switch err := db.QueryRowContext(ctx, `SELECT created_at FROM care_sessions LIMIT 1`).Scan(&createdAt); {
	case err == sql.ErrNoRows:
		t.Log("care_sessions kosong — lewati cek created_at")
	case err != nil:
		t.Logf("tabel care_sessions belum ada / tak terbaca: %v", err)
	default:
		assertWIB(t, "care_sessions.created_at", createdAt)
	}
}

// assertWIB memastikan nilai waktu berada di zona WIB (nama "WIB" atau offset +7).
func assertWIB(t *testing.T, label string, got time.Time) {
	t.Helper()
	_, offset := got.Zone()
	if got.Location().String() != "WIB" && offset != 7*3600 {
		t.Fatalf("%s harus WIB (+7 jam), dapat zona %q offset %d", label, got.Location().String(), offset)
	}
}
