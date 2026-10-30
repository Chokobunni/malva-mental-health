package store

import (
	"context"
	"database/sql"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

// TestMergePackageTotals menguji aritmetika penggabungan paket tanpa DB.
func TestMergePackageTotals(t *testing.T) {
	cases := []struct {
		name               string
		oldTotal, newTotal int
		oldPrice, newPrice int64
		wantTotal          int
		wantPrice          int64
	}{
		{"dua paket 4 sesi", 4, 4, 200_000, 200_000, 8, 400_000},
		{"harga berbeda", 4, 4, 200_000, 250_000, 8, 450_000},
		{"target kosong", 0, 4, 0, 200_000, 4, 200_000},
		{"paket lebih besar", 8, 4, 400_000, 200_000, 12, 600_000},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			gotTotal, gotPrice := mergePackageTotals(tc.oldTotal, tc.newTotal, tc.oldPrice, tc.newPrice)
			if gotTotal != tc.wantTotal {
				t.Fatalf("total sesi: dapat %d, mau %d", gotTotal, tc.wantTotal)
			}
			if gotPrice != tc.wantPrice {
				t.Fatalf("harga: dapat %d, mau %d", gotPrice, tc.wantPrice)
			}
		})
	}
}

// openCareMergeTestStore membuka store untuk test penggabungan paket.
// Skip bila DB tak tersedia atau tabel/migrasi care belum ada (CI-safe).
func openCareMergeTestStore(t *testing.T) (*Store, *sql.DB) {
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
		WHERE table_schema = 'public' AND table_name = 'care_packages'
		  AND column_name IN ('merged_into','merged_at')`).Scan(&n); err != nil || n < 2 {
		_ = db.Close()
		t.Skip("migrasi 022 belum diterapkan (CI-safe)")
	}
	return New(db), db
}

// TestActivatePendingPackageMerges: paket 4+4 digabung jadi 8, sesi lama tetap
// menunjuk paket target, dan paket pending ditandai merged.
func TestActivatePendingPackageMerges(t *testing.T) {
	s, db := openCareMergeTestStore(t)
	defer func() { _ = db.Close() }()
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	patient := randomUUID(t, db, ctx)
	prof := randomUUID(t, db, ctx)
	defer func() {
		_, _ = db.ExecContext(ctx, `DELETE FROM care_sessions WHERE patient_id = $1`, patient)
		_, _ = db.ExecContext(ctx, `DELETE FROM care_packages WHERE patient_id = $1`, patient)
	}()

	var targetID string
	if err := db.QueryRowContext(ctx, `INSERT INTO care_packages
		(patient_id, professional_id, total_sessions, validity_days, price, status, expires_at)
		VALUES ($1, $2, 4, 42, 200000, 'active', now() + interval '30 days')
		RETURNING id`, patient, prof).Scan(&targetID); err != nil {
		t.Fatalf("insert paket target: %v", err)
	}
	// Sesi lama pada paket target.
	if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions
		(package_id, patient_id, professional_id, session_type, scheduled_at, duration_minutes, status)
		VALUES ($1, $2, $3, 'chat', now() - interval '1 day', 30, 'completed')`,
		targetID, patient, prof); err != nil {
		t.Fatalf("insert sesi lama: %v", err)
	}
	// Paket pending baru (pembelian kedua).
	if _, err := db.ExecContext(ctx, `INSERT INTO care_packages
		(patient_id, professional_id, total_sessions, validity_days, price, status, expires_at)
		VALUES ($1, $2, 4, 42, 200000, 'pending_payment', now() + interval '42 days')`,
		patient, prof); err != nil {
		t.Fatalf("insert paket pending: %v", err)
	}
	bookingID := randomUUID(t, db, ctx)

	pkg, merged, err := s.ActivatePendingPackage(ctx, patient, prof, bookingID)
	if err != nil {
		t.Fatalf("activate: %v", err)
	}
	if !merged {
		t.Fatal("harus terjadi penggabungan (merged=true)")
	}
	if pkg.ID != targetID {
		t.Fatalf("paket hasil harus target %s, dapat %s", targetID, pkg.ID)
	}
	if pkg.TotalSessions != 8 {
		t.Fatalf("total sesi gabungan harus 8, dapat %d", pkg.TotalSessions)
	}
	if pkg.Price != 400000 {
		t.Fatalf("harga gabungan harus 400000, dapat %d", pkg.Price)
	}
	// Sesi lama tetap menunjuk paket target.
	var sessionPkg string
	if err := db.QueryRowContext(ctx, `SELECT package_id FROM care_sessions WHERE patient_id = $1`, patient).
		Scan(&sessionPkg); err != nil {
		t.Fatalf("baca sesi: %v", err)
	}
	if sessionPkg != targetID {
		t.Fatalf("sesi lama harus menunjuk target %s, dapat %s", targetID, sessionPkg)
	}
	// Paket pending harus ditandai merged -> target.
	var mergedInto sql.NullString
	if err := db.QueryRowContext(ctx, `SELECT merged_into FROM care_packages
		WHERE patient_id = $1 AND status = 'merged'`, patient).Scan(&mergedInto); err != nil {
		t.Fatalf("baca paket merged: %v", err)
	}
	if !mergedInto.Valid || mergedInto.String != targetID {
		t.Fatalf("merged_into harus %s, dapat %v", targetID, mergedInto)
	}
}
