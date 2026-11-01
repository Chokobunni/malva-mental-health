package store

import (
	"context"
	"database/sql"
	"os"
	"testing"
	"time"
)

// ============================================================
// QA — verifikasi independen migrasi 026 & 027.
// Butuh Postgres: di-skip bila MALVA_TEST_DATABASE_URL kosong.
// ============================================================

// openMigrationTestDB membuka DB test dan memastikan tabel inti sudah ada.
func openMigrationTestDB(t *testing.T) (*sql.DB, context.Context) {
	t.Helper()
	dsn := testDatabaseDSN(t)
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Skipf("db unavailable: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })
	ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	t.Cleanup(cancel)
	if err := db.PingContext(ctx); err != nil {
		t.Skipf("db unreachable: %v", err)
	}
	var n int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM information_schema.tables
		WHERE table_schema = current_schema()
		  AND table_name IN ('patient_profiles','patient_professional_links','bookings')`).Scan(&n); err != nil || n < 3 {
		t.Skip("tabel inti belum ada (CI-safe)")
	}
	return db, ctx
}

// TestMigration026UnescapeNamedEntities: entity bernama (&quot; &apos;) di-unescape,
// &amp; PALING AKHIR (literal "&amp;lt;" tetap "&lt;"), baris bersih tak berubah,
// dan aman dijalankan dua kali.
func TestMigration026UnescapeNamedEntities(t *testing.T) {
	db, ctx := openMigrationTestDB(t)

	pEntity := insertTestUser(t, db, ctx, "patient", "P Entity", "m26ent")
	pAmp := insertTestUser(t, db, ctx, "patient", "P Amp", "m26amp")
	pClean := insertTestUser(t, db, ctx, "patient", "P Clean", "m26clean")
	t.Cleanup(func() { cleanupTestUsers(t, db, pEntity, pAmp, pClean) })

	const rawEntity = `Kutip &quot;ganda&quot; dan &apos;tunggal&apos; &amp; selesai`
	const rawAmp = `literal &amp;lt; tetap`
	const rawClean = `F41.1 tanpa entity`
	if _, err := db.ExecContext(ctx, `INSERT INTO patient_profiles (user_id, diagnosis_summary)
		VALUES ($1,$2),($3,$4),($5,$6)`,
		pEntity, rawEntity, pAmp, rawAmp, pClean, rawClean); err != nil {
		t.Fatalf("insert profiles: %v", err)
	}

	content, err := os.ReadFile(migrationFilePath(t, "026_unescape_named_entities.sql"))
	if err != nil {
		t.Fatalf("baca migrasi 026: %v", err)
	}
	if _, err := db.ExecContext(ctx, string(content)); err != nil {
		t.Fatalf("jalankan 026 (iterasi 1): %v", err)
	}

	readDiag := func(id string) string {
		var s sql.NullString
		if err := db.QueryRowContext(ctx,
			`SELECT diagnosis_summary FROM patient_profiles WHERE user_id = $1`, id).Scan(&s); err != nil {
			t.Fatalf("baca diagnosis: %v", err)
		}
		return s.String
	}
	if got, want := readDiag(pEntity), `Kutip "ganda" dan 'tunggal' & selesai`; got != want {
		t.Errorf("entity: dapat %q, mau %q", got, want)
	}
	// &amp; paling akhir: "&amp;lt;" -> "&lt;" (BUKAN "<").
	if got, want := readDiag(pAmp), `literal &lt; tetap`; got != want {
		t.Errorf("amp-order: dapat %q, mau %q", got, want)
	}
	if got := readDiag(pClean); got != rawClean {
		t.Errorf("baris bersih berubah: dapat %q, mau %q", got, rawClean)
	}

	// Iterasi 2: harus tanpa error (idempoten DDL/DML).
	if _, err := db.ExecContext(ctx, string(content)); err != nil {
		t.Fatalf("jalankan 026 (iterasi 2): %v", err)
	}
	// Nilai realistis (sudah bersih) tetap stabil setelah run kedua.
	if got, want := readDiag(pEntity), `Kutip "ganda" dan 'tunggal' & selesai`; got != want {
		t.Errorf("entity setelah run 2: dapat %q, mau %q", got, want)
	}
}

// TestMigration027BackfillLinks: 027 membuat link aktif dari bukti hubungan
// (booking lunas), TIDAK menimpa status link yang sudah ada (ON CONFLICT DO
// NOTHING), dan idempoten (aman dijalankan dua kali, tanpa duplikat).
func TestMigration027BackfillLinks(t *testing.T) {
	db, ctx := openMigrationTestDB(t)

	// Pasangan 1: belum ada link, punya booking lunas -> link harus dibuat.
	p1 := insertTestUser(t, db, ctx, "patient", "Pasien Satu", "m27p1")
	r1 := insertTestUser(t, db, ctx, "professional", "Prof Satu", "m27r1")
	// Pasangan 2: sudah ada link 'inactive', punya booking lunas -> TIDAK ditimpa.
	p2 := insertTestUser(t, db, ctx, "patient", "Pasien Dua", "m27p2")
	r2 := insertTestUser(t, db, ctx, "professional", "Prof Dua", "m27r2")
	t.Cleanup(func() { cleanupTestUsers(t, db, p1, r1, p2, r2) })

	insertPaidBooking := func(pid, rid, tag string) {
		if _, err := db.ExecContext(ctx, `INSERT INTO bookings
			(patient_id, professional_id, service_type, session_type, booking_date,
			 slot_time, price, status)
			VALUES ($1,$2,'quick_consult','video',$3,'10:00',100000,'paid')`,
			pid, rid, "2026-01-02"); err != nil {
			t.Fatalf("insert booking %s: %v", tag, err)
		}
	}
	insertPaidBooking(p1, r1, "p1")
	insertPaidBooking(p2, r2, "p2")

	// Link non-aktif yang sengaja dibuat untuk pasangan 2.
	if _, err := db.ExecContext(ctx, `INSERT INTO patient_professional_links
		(patient_id, professional_id, status) VALUES ($1,$2,'inactive')`, p2, r2); err != nil {
		t.Fatalf("insert link inactive: %v", err)
	}

	content, err := os.ReadFile(migrationFilePath(t, "027_backfill_patient_professional_links.sql"))
	if err != nil {
		t.Fatalf("baca migrasi 027: %v", err)
	}
	if _, err := db.ExecContext(ctx, string(content)); err != nil {
		t.Fatalf("jalankan 027 (iterasi 1): %v", err)
	}

	countLinks := func(pid, rid string) int {
		var c int
		if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM patient_professional_links
			WHERE patient_id=$1 AND professional_id=$2`, pid, rid).Scan(&c); err != nil {
			t.Fatalf("hitung link: %v", err)
		}
		return c
	}
	statusOf := func(pid, rid string) string {
		var s string
		if err := db.QueryRowContext(ctx, `SELECT status FROM patient_professional_links
			WHERE patient_id=$1 AND professional_id=$2`, pid, rid).Scan(&s); err != nil {
			t.Fatalf("baca status: %v", err)
		}
		return s
	}

	// Pasangan 1: link aktif dibuat.
	if c := countLinks(p1, r1); c != 1 {
		t.Fatalf("pasangan 1: jumlah link = %d, mau 1", c)
	}
	if s := statusOf(p1, r1); s != "active" {
		t.Fatalf("pasangan 1: status = %q, mau active", s)
	}
	// Pasangan 2: status 'inactive' TIDAK ditimpa (DO NOTHING).
	if s := statusOf(p2, r2); s != "inactive" {
		t.Fatalf("pasangan 2: status = %q, mau tetap inactive (DO NOTHING)", s)
	}

	// Iterasi 2: idempoten, tanpa duplikat, status tetap.
	if _, err := db.ExecContext(ctx, string(content)); err != nil {
		t.Fatalf("jalankan 027 (iterasi 2): %v", err)
	}
	if c := countLinks(p1, r1); c != 1 {
		t.Fatalf("pasangan 1 setelah run 2: jumlah link = %d, mau 1", c)
	}
	if s := statusOf(p2, r2); s != "inactive" {
		t.Fatalf("pasangan 2 setelah run 2: status = %q, mau tetap inactive", s)
	}
}

// TestMigration027ExcludesPendingPayment mengunci pengetatan 027: status
// 'pending_payment' (pasien BELUM bayar) TIDAK boleh menjadi bukti hubungan.
// Bila pending_payment dimasukkan lagi ke 027, test ini GAGAL karena link
// tercipta dari niat bayar yang tidak pernah selesai (pelonggaran otorisasi).
func TestMigration027ExcludesPendingPayment(t *testing.T) {
	db, ctx := openMigrationTestDB(t)

	// Pasangan "niat bayar": hanya punya sesi & paket berstatus pending_payment.
	pPending := insertTestUser(t, db, ctx, "patient", "Pasien Niat Bayar", "m27pend")
	rPending := insertTestUser(t, db, ctx, "professional", "Prof Niat Bayar", "m27rpend")
	// Pasangan "sesi terjadwal": punya sesi scheduled (sudah dibayar) -> link dibuat.
	pSched := insertTestUser(t, db, ctx, "patient", "Pasien Terjadwal", "m27sched")
	rSched := insertTestUser(t, db, ctx, "professional", "Prof Terjadwal", "m27rsched")
	t.Cleanup(func() { cleanupTestUsers(t, db, pPending, rPending, pSched, rSched) })

	// Sesi pending_payment (belum dibayar) untuk pasangan niat-bayar.
	if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions
		(patient_id, professional_id, session_type, scheduled_at, duration_minutes, status)
		VALUES ($1,$2,'video',$3,30,'pending_payment')`,
		pPending, rPending, time.Now().Add(2*time.Hour)); err != nil {
		t.Fatalf("insert care_session pending_payment: %v", err)
	}
	// Paket pending_payment (belum dibayar) untuk pasangan yang sama.
	if _, err := db.ExecContext(ctx, `INSERT INTO care_packages
		(patient_id, professional_id, status, expires_at)
		VALUES ($1,$2,'pending_payment',$3)`,
		pPending, rPending, time.Now().Add(42*24*time.Hour)); err != nil {
		t.Fatalf("insert care_package pending_payment: %v", err)
	}

	// Sesi scheduled (sudah dibayar) untuk pasangan terjadwal.
	if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions
		(patient_id, professional_id, session_type, scheduled_at, duration_minutes, status)
		VALUES ($1,$2,'chat',$3,30,'scheduled')`,
		pSched, rSched, time.Now().Add(3*time.Hour)); err != nil {
		t.Fatalf("insert care_session scheduled: %v", err)
	}

	content, err := os.ReadFile(migrationFilePath(t, "027_backfill_patient_professional_links.sql"))
	if err != nil {
		t.Fatalf("baca migrasi 027: %v", err)
	}
	if _, err := db.ExecContext(ctx, string(content)); err != nil {
		t.Fatalf("jalankan 027: %v", err)
	}

	countLinks := func(pid, rid string) int {
		var c int
		if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM patient_professional_links
			WHERE patient_id=$1 AND professional_id=$2`, pid, rid).Scan(&c); err != nil {
			t.Fatalf("hitung link: %v", err)
		}
		return c
	}

	// pending_payment TIDAK boleh menghasilkan link.
	if c := countLinks(pPending, rPending); c != 0 {
		t.Fatalf("pending_payment menghasilkan %d link, mau 0 (pelonggaran otorisasi!)", c)
	}
	// scheduled (sudah dibayar) HARUS menghasilkan link aktif.
	if c := countLinks(pSched, rSched); c != 1 {
		t.Fatalf("sesi scheduled menghasilkan %d link, mau 1", c)
	}
}
