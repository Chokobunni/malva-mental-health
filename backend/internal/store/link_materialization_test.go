package store

import (
	"context"
	"database/sql"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

// openLinkTestStore membuka store untuk test materialisasi relasi
// pasien–profesional. Skip bila DB tidak tersedia (CI-safe).
func openLinkTestStore(t *testing.T) (*Store, *sql.DB) {
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
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM information_schema.tables
		WHERE table_schema = current_schema()
		  AND table_name IN ('patient_professional_links','users')`).Scan(&n); err != nil || n < 2 {
		_ = db.Close()
		t.Skip("tabel inti relasi belum ada (CI-safe)")
	}
	t.Cleanup(func() { _ = db.Close() })
	return New(db), db
}

// TestEnsurePatientProfessionalLinkIdempoten mengunci perbaikan Bug 4:
// materialisasi relasi pasien–profesional harus idempoten dan TIDAK menimpa
// status baris yang sudah ada (link yang sengaja diputus tidak dihidupkan
// kembali), sehingga profesional yang dibayar pasiennya tidak kehilangan akses
// walau webhook pembayaran dikirim berulang — tanpa membalik keputusan pasien.
func TestEnsurePatientProfessionalLinkIdempoten(t *testing.T) {
	s, db := openLinkTestStore(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	patientID := insertTestUser(t, db, ctx, "patient", "Ami", "patient")
	profID := insertTestUser(t, db, ctx, "professional", "Rina Prasetyo, M.Psi", "rina")
	t.Cleanup(func() { cleanupTestUsers(t, db, patientID, profID) })

	// Panggil dua kali: harus idempoten (tidak error, hanya satu baris).
	for i := 0; i < 2; i++ {
		if err := s.EnsurePatientProfessionalLink(ctx, patientID, profID); err != nil {
			t.Fatalf("panggilan ke-%d: EnsurePatientProfessionalLink: %v", i+1, err)
		}
	}
	var count int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM patient_professional_links
		WHERE patient_id = $1 AND professional_id = $2 AND status = 'active'`,
		patientID, profID).Scan(&count); err != nil {
		t.Fatalf("hitung link: %v", err)
	}
	if count != 1 {
		t.Fatalf("baris link aktif = %d, mau 1", count)
	}

	// Profesional sekarang dianggap terhubung ke pasien.
	linked, err := s.ProfessionalLinkedToPatient(ctx, profID, patientID)
	if err != nil {
		t.Fatalf("ProfessionalLinkedToPatient: %v", err)
	}
	if !linked {
		t.Fatal("profesional seharusnya terhubung ke pasien setelah materialisasi")
	}

	// Non-aktifkan lalu materialisasi ulang: status yang ada TIDAK boleh ditimpa
	// (link yang sengaja diputus tidak dihidupkan kembali). Ini mengunci
	// keputusan ON CONFLICT DO NOTHING sesuai instruksi team-lead + migrasi 027.
	if _, err := db.ExecContext(ctx, `UPDATE patient_professional_links
		SET status = 'inactive' WHERE patient_id = $1 AND professional_id = $2`,
		patientID, profID); err != nil {
		t.Fatalf("nonaktifkan link: %v", err)
	}
	if err := s.EnsurePatientProfessionalLink(ctx, patientID, profID); err != nil {
		t.Fatalf("materialisasi ulang: %v", err)
	}
	var status string
	if err := db.QueryRowContext(ctx, `SELECT status FROM patient_professional_links
		WHERE patient_id = $1 AND professional_id = $2`,
		patientID, profID).Scan(&status); err != nil {
		t.Fatalf("baca status: %v", err)
	}
	if status != "inactive" {
		t.Fatalf("status link yang ada tidak boleh ditimpa: dapat %q, mau %q", status, "inactive")
	}
}
