package store

import (
	"context"
	"database/sql"
	"fmt"
	"strings"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

// ============================================================
// Regresi BUG C2 — direktori "Cari Profesional" tidak boleh
// menyembunyikan profesional yang belum punya koordinat faskes.
//
// Sebelum perbaikan, bila pasien mengirim patient_lat/lng (aplikasi selalu
// mengirimnya ketika izin lokasi aktif), query SELALU menambahkan
// `pc.hospital_lat IS NOT NULL AND pc.hospital_lng IS NOT NULL`, sehingga
// profesional tanpa koordinat hilang dari daftar.
// ============================================================

// openDoctorSearchTestStore membuka store untuk test direktori.
// Skip bila DB tidak tersedia (CI-safe), mengikuti pola care_refund_test.go.
//
// PENTING: koneksi ditutup lewat `t.Cleanup` (LIFO), BUKAN `defer` di badan
// test — supaya cleanup data yang didaftarkan setelah ini berjalan lebih dulu
// dan tidak mengenai koneksi yang sudah tertutup.
func openDoctorSearchTestStore(t *testing.T) (*Store, *sql.DB) {
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
		WHERE table_schema = 'public'
		  AND table_name IN ('users','professional_profiles','professional_credentials')`).Scan(&n); err != nil || n < 3 {
		_ = db.Close()
		t.Skip("skema dasar belum diterapkan (CI-safe)")
	}
	// Didaftarkan lebih dulu = dijalankan paling akhir (LIFO).
	t.Cleanup(func() { _ = db.Close() })
	return New(db), db
}

// TestSearchDoctorsKeepsProfessionalsWithoutCoordinates memastikan:
//   - tanpa filter jarak eksplisit, profesional TANPA koordinat tetap tampil
//     (distance_km NULL);
//   - dengan MaxKM, filter koordinat aktif sehingga hanya yang punya
//     koordinat dalam radius yang tampil.
func TestSearchDoctorsKeepsProfessionalsWithoutCoordinates(t *testing.T) {
	s, db := openDoctorSearchTestStore(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	emailWith := "cari-ada-koordinat-" + suffix + "@malva.test"
	emailWithout := "cari-tanpa-koordinat-" + suffix + "@malva.test"
	// Spesialisasi unik per run agar hasil query TIDAK bergantung pada jumlah
	// baris di tabel (LIMIT bisa memotong baris uji bila DB berisi banyak data).
	spec := "UJI-CARI-" + suffix

	insertProfessional := func(email, professionalID string, lat, lng *float64) string {
		var id string
		if err := db.QueryRowContext(ctx, `INSERT INTO users (email, password_hash, role, display_name)
			VALUES ($1,'test-hash','professional',$2) RETURNING id::text`,
			email, "Profesional "+suffix).Scan(&id); err != nil {
			t.Fatalf("insert user %s: %v", email, err)
		}
		if _, err := db.ExecContext(ctx, `INSERT INTO professional_profiles (user_id, professional_id)
			VALUES ($1,$2)`, id, professionalID); err != nil {
			t.Fatalf("insert professional_profiles %s: %v", email, err)
		}
		if _, err := db.ExecContext(ctx, `INSERT INTO professional_credentials
			(user_id, str_number, sip_number, specialization, hospital_lat, hospital_lng, verification_status)
			VALUES ($1,$2,$3,$6,$4,$5,'VERIFIED')`,
			id, professionalID, professionalID, lat, lng, spec); err != nil {
			t.Fatalf("insert credentials %s: %v", email, err)
		}
		return id
	}

	lat, lng := -6.2000, 106.8166 // Jakarta
	withCoordsID := insertProfessional(emailWith, "STR-CARI-A-"+suffix, &lat, &lng)
	withoutCoordsID := insertProfessional(emailWithout, "STR-CARI-B-"+suffix, nil, nil)

	t.Cleanup(func() { cleanupTestUsers(t, db, withCoordsID, withoutCoordsID) })

	// 1) Pasien mengirim koordinat, TANPA filter jarak: keduanya harus tampil.
	results, err := s.SearchDoctors(ctx, DoctorSearchParams{
		PatientLat:     &lat,
		PatientLng:     &lng,
		Specialization: spec,
		SortBy:         "distance",
		Limit:          100,
	})
	if err != nil {
		t.Fatalf("SearchDoctors tanpa MaxKM: %v", err)
	}
	foundWith, foundWithout := false, false
	for _, r := range results {
		switch r.UserID {
		case withCoordsID:
			foundWith = true
			if r.DistanceKM == nil {
				t.Errorf("profesional dengan koordinat harus punya distance_km")
			}
		case withoutCoordsID:
			foundWithout = true
			if r.DistanceKM != nil {
				t.Errorf("profesional tanpa koordinat harus punya distance_km NULL")
			}
		}
	}
	if !foundWith {
		t.Errorf("profesional dengan koordinat hilang dari hasil")
	}
	if !foundWithout {
		t.Errorf("profesional TANPA koordinat hilang dari hasil padahal tidak ada filter jarak")
	}

	// 2) Dengan filter jarak eksplisit: hanya yang punya koordinat & dalam radius.
	maxKM := 5.0
	results, err = s.SearchDoctors(ctx, DoctorSearchParams{
		PatientLat:     &lat,
		PatientLng:     &lng,
		MaxKM:          &maxKM,
		Specialization: spec,
		SortBy:         "distance",
		Limit:          100,
	})
	if err != nil {
		t.Fatalf("SearchDoctors dengan MaxKM: %v", err)
	}
	for _, r := range results {
		if r.UserID == withoutCoordsID {
			t.Errorf("dengan filter jarak, profesional tanpa koordinat tidak boleh ikut")
		}
	}
}

// userChildRef adalah satu kolom FK yang menunjuk ke users(id).
type userChildRef struct {
	table  string
	column string
}

// discoverUserChildRefs menemukan SEMUA kolom FK yang menunjuk ke users(id)
// lewat information_schema — tidak menebak nama tabel/kolom.
func discoverUserChildRefs(t *testing.T, db *sql.DB) []userChildRef {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	const q = `
		SELECT tc.table_name, kcu.column_name
		FROM information_schema.table_constraints tc
		JOIN information_schema.key_column_usage kcu
		  ON kcu.constraint_name = tc.constraint_name
		 AND kcu.table_schema = tc.table_schema
		JOIN information_schema.constraint_column_usage ccu
		  ON ccu.constraint_name = tc.constraint_name
		 AND ccu.table_schema = tc.table_schema
		WHERE tc.constraint_type = 'FOREIGN KEY'
		  AND ccu.table_name = 'users'
		  AND tc.table_schema = 'public'
		ORDER BY tc.table_name, kcu.column_name`
	rows, err := db.QueryContext(ctx, q)
	if err != nil {
		t.Errorf("gagal membaca daftar FK ke users: %v", err)
		return nil
	}
	defer func() { _ = rows.Close() }()
	var refs []userChildRef
	for rows.Next() {
		var r userChildRef
		if err := rows.Scan(&r.table, &r.column); err != nil {
			t.Errorf("scan FK users: %v", err)
			return refs
		}
		refs = append(refs, r)
	}
	if err := rows.Err(); err != nil {
		t.Errorf("iterasi FK users: %v", err)
	}
	return refs
}

// isForeignKeyViolation mendeteksi pelanggaran FK Postgres (SQLSTATE 23503).
func isForeignKeyViolation(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	return strings.Contains(msg, "23503") || strings.Contains(msg, "foreign key constraint")
}

// cleanupTestUsers menghapus user uji beserta SELURUH baris anak yang
// menahannya, lalu MEMVERIFIKASI tidak ada sisa.
//
// audit_logs.actor_id / patient_id TIDAK memakai ON DELETE CASCADE, sehingga
// `DELETE FROM users` gagal bila baris audit sudah ada. Kegagalan itu dulu
// ditelan diam-diam dan membuat data uji MENUMPUK di DB bersama. Koneksi
// dijamin masih terbuka karena opener memakai t.Cleanup (LIFO), bukan defer.
func cleanupTestUsers(t *testing.T, db *sql.DB, ids ...string) {
	t.Helper()
	if len(ids) == 0 {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	arr := "{" + strings.Join(ids, ",") + "}"

	if _, err := db.ExecContext(ctx,
		`DELETE FROM audit_logs WHERE actor_id = ANY($1::uuid[]) OR patient_id = ANY($1::uuid[])`, arr); err != nil {
		t.Logf("cleanup audit_logs gagal: %v", err)
	}
	if _, err := db.ExecContext(ctx, `DELETE FROM auth_sessions WHERE user_id = ANY($1::uuid[])`, arr); err != nil {
		t.Logf("cleanup auth_sessions gagal: %v", err)
	}

	pending := discoverUserChildRefs(t, db)
	for pass := 0; pass < 5 && len(pending) > 0; pass++ {
		var next []userChildRef
		progress := false
		for _, ref := range pending {
			stmt := fmt.Sprintf(`DELETE FROM "%s" WHERE "%s" = ANY($1::uuid[])`, ref.table, ref.column)
			if _, err := db.ExecContext(ctx, stmt, arr); err != nil {
				if isForeignKeyViolation(err) {
					next = append(next, ref)
					continue
				}
				t.Errorf("cleanup %s.%s gagal: %v", ref.table, ref.column, err)
				continue
			}
			progress = true
		}
		pending = next
		if !progress {
			break
		}
	}
	for _, ref := range pending {
		t.Errorf("cleanup tidak selesai untuk %s.%s (masih ditahan FK lain)", ref.table, ref.column)
	}

	if _, err := db.ExecContext(ctx, `DELETE FROM users WHERE id = ANY($1::uuid[])`, arr); err != nil {
		t.Errorf("cleanup users gagal: %v", err)
	}

	var remaining int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM users WHERE id = ANY($1::uuid[])`, arr).Scan(&remaining); err != nil {
		t.Errorf("verifikasi cleanup tidak bisa dijalankan: %v", err)
		return
	}
	if remaining != 0 {
		t.Errorf("cleanup: %d user uji masih tersisa di DB", remaining)
	}
}
