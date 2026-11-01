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

// openHealthRecordTestStore membuka store untuk test atribusi penulis
// diagnosis. Skip bila DB tidak tersedia atau tabel inti belum ada (CI-safe).
func openHealthRecordTestStore(t *testing.T) (*Store, *sql.DB) {
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
		  AND table_name IN ('audit_logs','patient_profiles','patient_professional_links')`).Scan(&n); err != nil || n < 3 {
		_ = db.Close()
		t.Skip("tabel inti health record belum ada (CI-safe)")
	}
	t.Cleanup(func() { _ = db.Close() })
	return New(db), db
}

// insertTestUser membuat user uji dengan peran tertentu dan mengembalikan id.
func insertTestUser(t *testing.T, db *sql.DB, ctx context.Context, role, displayName, emailPrefix string) string {
	t.Helper()
	suffix := fmt.Sprintf("%d-%s", clock.Now().UnixNano(), emailPrefix)
	var id string
	if err := db.QueryRowContext(ctx, `INSERT INTO users (email, password_hash, role, display_name)
		VALUES ($1,'test-hash',$2,$3) RETURNING id::text`,
		emailPrefix+"-"+suffix+"@malva.test", role, displayName).Scan(&id); err != nil {
		t.Fatalf("insert user %s: %v", displayName, err)
	}
	return id
}

// TestGetHealthRecordUpdatedByAdalahPenulisDiagnosis mengunci perbaikan Bug A:
// `updated_by` pada respons health record harus berisi display_name actor
// audit terakhir (penulis diagnosis sebenarnya), BUKAN nama profesional utama
// (link aktif pertama). Skenario meniru data produksi: profesional "Andi"
// terhubung lebih dulu, lalu "dr. Hafid" mengubah diagnosis belakangan.
func TestGetHealthRecordUpdatedByAdalahPenulisDiagnosis(t *testing.T) {
	s, db := openHealthRecordTestStore(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	patientID := insertTestUser(t, db, ctx, "patient", "Ami", "patient")
	andiID := insertTestUser(t, db, ctx, "professional", "Andi Wijaya, M.Psi", "andi")
	hafidID := insertTestUser(t, db, ctx, "professional", "dr. Hafid Algistian", "hafid")
	t.Cleanup(func() { cleanupTestUsers(t, db, patientID, andiID, hafidID) })

	// Profil pasien dengan diagnosis.
	if _, err := db.ExecContext(ctx, `INSERT INTO patient_profiles (user_id, diagnosis_summary)
		VALUES ($1, $2)`, patientID, "F41.1 & F60.3"); err != nil {
		t.Fatalf("insert patient_profile: %v", err)
	}

	// Andi terhubung LEBIH DULU (created_at lebih awal) -> primary professional.
	// Hafid terhubung belakangan tetapi yang menulis diagnosis.
	earlier := clock.Now().Add(-2 * time.Hour)
	later := clock.Now().Add(-1 * time.Hour)
	if _, err := db.ExecContext(ctx, `INSERT INTO patient_professional_links
		(patient_id, professional_id, status, created_at) VALUES ($1,$2,'active',$3)`,
		patientID, andiID, earlier); err != nil {
		t.Fatalf("insert link andi: %v", err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO patient_professional_links
		(patient_id, professional_id, status, created_at) VALUES ($1,$2,'active',$3)`,
		patientID, hafidID, later); err != nil {
		t.Fatalf("insert link hafid: %v", err)
	}

	// Jejak audit: diagnosis diubah oleh Hafid.
	if err := s.AddAuditLog(ctx, hafidID, patientID, "health_record.diagnosis_updated",
		"patient_profile", patientID, nil); err != nil {
		t.Fatalf("add audit log: %v", err)
	}

	rec, err := s.GetHealthRecord(ctx, patientID)
	if err != nil {
		t.Fatalf("GetHealthRecord: %v", err)
	}

	// primary_professional tetap Andi (link aktif pertama) — perilaku lama.
	if rec.PrimaryProfessional != "Andi Wijaya, M.Psi" {
		t.Errorf("primary_professional: dapat %q, mau %q",
			rec.PrimaryProfessional, "Andi Wijaya, M.Psi")
	}
	// updated_by HARUS Hafid (penulis diagnosis sebenarnya), bukan Andi.
	if rec.UpdatedBy == nil || *rec.UpdatedBy != "dr. Hafid Algistian" {
		got := "<nil>"
		if rec.UpdatedBy != nil {
			got = *rec.UpdatedBy
		}
		t.Fatalf("updated_by: dapat %q, mau %q", got, "dr. Hafid Algistian")
	}
}

// TestGetHealthRecordTanpaAuditTidakMeminjamNamaProfesional mengunci
// invariant: bila belum ada jejak audit diagnosis, `updated_by` HARUS kosong
// meskipun ada profesional aktif terhubung. Backend tidak boleh memakai
// primary_professional sebagai atribusi (fabrikasi penulis).
func TestGetHealthRecordTanpaAuditTidakMeminjamNamaProfesional(t *testing.T) {
	s, db := openHealthRecordTestStore(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	patientID := insertTestUser(t, db, ctx, "patient", "Ami", "patient")
	andiID := insertTestUser(t, db, ctx, "professional", "Andi Wijaya, M.Psi", "andi")
	t.Cleanup(func() { cleanupTestUsers(t, db, patientID, andiID) })

	if _, err := db.ExecContext(ctx, `INSERT INTO patient_profiles (user_id, diagnosis_summary)
		VALUES ($1, $2)`, patientID, "F41.1"); err != nil {
		t.Fatalf("insert patient_profile: %v", err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO patient_professional_links
		(patient_id, professional_id, status, created_at) VALUES ($1,$2,'active',$3)`,
		patientID, andiID, clock.Now()); err != nil {
		t.Fatalf("insert link andi: %v", err)
	}
	// Sengaja TANPA audit log diagnosis.

	rec, err := s.GetHealthRecord(ctx, patientID)
	if err != nil {
		t.Fatalf("GetHealthRecord: %v", err)
	}
	if rec.PrimaryProfessional != "Andi Wijaya, M.Psi" {
		t.Errorf("primary_professional: dapat %q, mau %q",
			rec.PrimaryProfessional, "Andi Wijaya, M.Psi")
	}
	if rec.UpdatedBy != nil {
		t.Fatalf("updated_by harus kosong tanpa jejak audit, dapat %q", *rec.UpdatedBy)
	}
}
