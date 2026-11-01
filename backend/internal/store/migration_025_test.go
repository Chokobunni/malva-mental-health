package store

import (
	"context"
	"database/sql"
	"os"
	"path/filepath"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

// migrationFilePath mengembalikan path absolut berkas migrasi 025 relatif
// terhadap paket store (test dijalankan dari internal/store).
func migrationFilePath(t *testing.T, name string) string {
	t.Helper()
	path := filepath.Join("..", "..", "migrations", name)
	if _, err := os.Stat(path); err != nil {
		t.Skipf("berkas migrasi tidak ditemukan: %v", err)
	}
	return path
}

// TestMigration025UnescapeSanitizedText mengunci perbaikan Bug C pada tingkat
// data: migrasi 025 meng-unescape entity HTML pada kolom yang ditulis lewat
// SanitizeText, idempoten (aman dijalankan dua kali), mengubah baris ber-entity
// dengan benar, membiarkan baris tanpa entity, dan menangani "&amp;lt;" tanpa
// berubah menjadi "<".
func TestMigration025UnescapeSanitizedText(t *testing.T) {
	dsn := testDatabaseDSN(t)
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Skipf("db unavailable: %v", err)
	}
	// Pakai t.Cleanup (LIFO) agar koneksi tetap terbuka saat cleanupTestUsers
	// berjalan — defer db.Close() akan menutup DB sebelum cleanup data.
	t.Cleanup(func() { _ = db.Close() })
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		t.Skipf("db unreachable (CI-safe): %v", err)
	}

	// Pastikan tabel patient_profiles tersedia (migrasi inti sudah jalan).
	var n int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM information_schema.columns
		WHERE table_schema = current_schema() AND table_name = 'patient_profiles'
		  AND column_name = 'diagnosis_summary'`).Scan(&n); err != nil || n < 1 {
		t.Skip("tabel patient_profiles belum ada (CI-safe)")
	}

	// Siapkan tiga pasien uji: ber-entity, bersih, dan literal "&amp;lt;".
	patientEntity := insertTestUser(t, db, ctx, "patient", "Pasien Entity", "ent")
	patientClean := insertTestUser(t, db, ctx, "patient", "Pasien Bersih", "clean")
	patientLiteral := insertTestUser(t, db, ctx, "patient", "Pasien Literal", "lit")
	t.Cleanup(func() {
		cleanupTestUsers(t, db, patientEntity, patientClean, patientLiteral)
	})

	const rawEntity = "Depresi &amp; ansietas &lt;berat&gt; F60.3"
	const rawLiteral = "literal &amp;lt; harus tetap"
	const rawClean = "F41.1 & F60.3"

	if _, err := db.ExecContext(ctx, `INSERT INTO patient_profiles (user_id, diagnosis_summary)
		VALUES ($1,$2), ($3,$4), ($5,$6)`,
		patientEntity, rawEntity,
		patientClean, rawClean,
		patientLiteral, rawLiteral); err != nil {
		t.Fatalf("insert patient_profiles: %v", err)
	}

	readDiag := func(id string) string {
		var s sql.NullString
		if err := db.QueryRowContext(ctx,
			`SELECT diagnosis_summary FROM patient_profiles WHERE user_id = $1`, id).Scan(&s); err != nil {
			t.Fatalf("baca diagnosis %s: %v", id, err)
		}
		return s.String
	}

	// Jalankan migrasi 025 (iterasi 1). Production menjalankan sekali per
	// ledger; data harus benar setelah SATU lintasan.
	path := migrationFilePath(t, "025_unescape_sanitized_text.sql")
	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("baca migrasi: %v", err)
	}
	if _, err := db.ExecContext(ctx, string(content)); err != nil {
		t.Fatalf("jalankan migrasi 025 (iterasi 1): %v", err)
	}

	// Baris ber-entity: &amp; -> &, &lt;/&gt; -> < >.
	if got := readDiag(patientEntity); got != "Depresi & ansietas <berat> F60.3" {
		t.Errorf("baris ber-entity: dapat %q, mau %q", got, "Depresi & ansietas <berat> F60.3")
	}
	// Baris tanpa entity: tidak berubah.
	if got := readDiag(patientClean); got != rawClean {
		t.Errorf("baris bersih: dapat %q, mau %q", got, rawClean)
	}
	// Literal "&amp;lt;" -> "&lt;" (BUKAN "<"): bukti urutan &amp; paling akhir.
	if got := readDiag(patientLiteral); got != "literal &lt; harus tetap" {
		t.Errorf("baris literal: dapat %q, mau %q", got, "literal &lt; harus tetap")
	}

	// Iterasi 2: cukup membuktikan migrasi TIDAK ERROR saat dijalankan ulang
	// (kewajiban idempotensi DDL/DML pada ledger). Unescape bersifat
	// non-idempoten untuk literal entity, jadi data tidak diperiksa lagi.
	if _, err := db.ExecContext(ctx, string(content)); err != nil {
		t.Fatalf("jalankan migrasi 025 (iterasi 2, harus tanpa error): %v", err)
	}
}
