package store

import (
	"context"
	"database/sql"
	"fmt"
	"net/url"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"
	"time"
)

const (
	qaPreviewPatientID = "b0000000-0000-4000-8000-000000000000"
	qaRealPatientID    = "c0000000-0000-4000-8000-000000000001"
	qaProfessionalID   = "a1111111-1111-4111-8111-111111111111"
)

// qaMigrationSchema menerapkan skema asli pada schema lokal terisolasi. Tidak
// menggunakan tabel publik atau menjalankan migrasi destruktif ke data nyata.
func qaMigrationSchema(t *testing.T) (*sql.Conn, context.Context) {
	t.Helper()
	dsn := os.Getenv("MALVA_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("MALVA_TEST_DATABASE_URL belum dikonfigurasi")
	}
	u, err := url.Parse(dsn)
	if err != nil || (u.Hostname() != "localhost" && u.Hostname() != "127.0.0.1" && u.Hostname() != "::1") {
		t.Fatal("QA migrasi wajib memakai database test lokal")
	}
	db, err := OpenSQL(dsn)
	if err != nil {
		t.Fatalf("buka database test: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	t.Cleanup(cancel)
	conn, err := db.Conn(ctx)
	if err != nil {
		t.Fatalf("ambil koneksi test: %v", err)
	}
	schema := fmt.Sprintf("qa_preview_%d", time.Now().UnixNano())
	if _, err := conn.ExecContext(ctx, "CREATE SCHEMA "+schema); err != nil {
		_ = conn.Close()
		t.Fatalf("buat schema test: %v", err)
	}
	t.Cleanup(func() {
		cleanupCtx, cleanupCancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cleanupCancel()
		if _, err := conn.ExecContext(cleanupCtx, "DROP SCHEMA "+schema+" CASCADE"); err != nil {
			t.Errorf("hapus schema test %s: %v", schema, err)
		}
		_ = conn.Close()
	})
	if _, err := conn.ExecContext(ctx, "SET search_path TO "+schema); err != nil {
		t.Fatalf("atur schema test: %v", err)
	}
	files, err := filepath.Glob(filepath.Join("..", "..", "migrations", "*.sql"))
	if err != nil || len(files) == 0 {
		t.Fatalf("cari migrasi asli: %v (jumlah %d)", err, len(files))
	}
	sort.Strings(files)
	for _, file := range files {
		base := filepath.Base(file)
		if base[:3] >= "029" {
			continue
		}
		qaApplyMigration(t, conn, ctx, file)
		if strings.HasPrefix(base, "001") {
			// Akomodasi harness (bukan mengubah migrasi asli): migrasi 006 memeriksa
			// keberadaan kolom `users.phone` lewat information_schema TANPA filter
			// table_schema. Di schema terisolasi yang berdampingan dengan `public`
			// yang SUDAH menjalankan migrasi (kondisi CI: migrasi diterapkan ke
			// public lebih dulu), guard 006 akan bernilai benar karena melihat
			// public.users.phone, lalu mencoba ALTER `users.phone` pada schema
			// terisolasi yang belum punya kolom itu -> error. Kolom phone memang
			// baru ditambahkan migrasi 011; menambahkannya lebih awal (nullable)
			// membuat guard 006 aman dan tidak mengubah perilaku akhir skema.
			if _, err := conn.ExecContext(ctx,
				`ALTER TABLE users ADD COLUMN IF NOT EXISTS phone VARCHAR(32)`); err != nil {
				t.Fatalf("akomodasi kolom phone (schema terisolasi): %v", err)
			}
		}
	}
	return conn, ctx
}

func qaApplyMigration(t *testing.T, conn *sql.Conn, ctx context.Context, path string) {
	t.Helper()
	content, err := os.ReadFile(path)
	if err != nil {
		t.Fatalf("baca migrasi %s: %v", filepath.Base(path), err)
	}
	if _, err := conn.ExecContext(ctx, string(content)); err != nil {
		t.Fatalf("jalankan migrasi %s: %v", filepath.Base(path), err)
	}
}

func qaCount(t *testing.T, conn *sql.Conn, ctx context.Context, query string, args ...any) int {
	t.Helper()
	var count int
	if err := conn.QueryRowContext(ctx, query, args...).Scan(&count); err != nil {
		t.Fatalf("hitung fixture: %v", err)
	}
	return count
}

func TestQAPreviewCleanupSeedTidakMembuatPasien(t *testing.T) {
	conn, ctx := qaMigrationSchema(t)
	if got := qaCount(t, conn, ctx, `SELECT count(*) FROM users WHERE role = 'patient'`); got != 0 {
		t.Fatalf("seed baru membuat %d pasien, mau 0", got)
	}
	qaApplyMigration(t, conn, ctx, filepath.Join("..", "..", "migrations", "007_seed_professionals.sql"))
	if got := qaCount(t, conn, ctx, `SELECT count(*) FROM users WHERE role = 'patient'`); got != 0 {
		t.Fatalf("seed ulang membuat %d pasien, mau 0", got)
	}
}

func TestQAPreviewCleanupAmanFKDanIdempoten(t *testing.T) {
	conn, ctx := qaMigrationSchema(t)
	// Arrange: preview dan pasien nyata punya dependensi yang sama. Booking
	// preview juga direferensikan review; chat dan audit memakai FK non-CASCADE.
	fixtures := []string{
		`INSERT INTO users (id,email,password_hash,role,display_name) VALUES
		 ($1,'preview_pasien@malva.app','test','patient','Pasien Preview'),
		 ($2,'pasien.nyata@example.test','test','patient','Pasien Nyata')`,
		`INSERT INTO patient_profiles (user_id) VALUES ($1),($2)`,
		`INSERT INTO patient_professional_links (patient_id,professional_id) VALUES ($1,$3),($2,$3)`,
		`INSERT INTO patient_data_consents (patient_id,professional_id) VALUES ($1,$3),($2,$3)`,
		`INSERT INTO diary_entries (patient_id,mood,title,note) VALUES
		 ($1,'baik','Preview','demo'),($2,'baik','Nyata','tetap')`,
		`INSERT INTO chat_messages (id,patient_id,professional_id,sender_id,text) VALUES
		 ('qa-preview',$1,$3,$1,'demo'),('qa-real',$2,$3,$2,'tetap')`,
		`INSERT INTO screening_sessions (patient_id,submitted_by,rule_version,overall_level) VALUES
		 ($1,$1,'qa','minimal'),($2,$2,'qa','minimal')`,
		`INSERT INTO audit_logs (actor_id,patient_id,action,entity_type) VALUES
		 ($1,$1,'qa','patient'),($3,$2,'qa','patient')`,
		`INSERT INTO crisis_incidents (patient_id,triggered_by) VALUES ($1,'manual'),($2,'manual')`,
		`INSERT INTO bookings (patient_id,professional_id,service_type,session_type,booking_date,slot_time,price)
		 VALUES ($1,$3,'quick_consult','video','2026-01-02','10:00',100000),
		 ($2,$3,'quick_consult','video','2026-01-02','11:00',100000)`,
		`INSERT INTO payments (booking_id,payment_method,gross_amount,platform_fee_amount,net_amount,reference)
		 SELECT id,'qris',100000,10000,90000,'qa-' || patient_id::text FROM bookings WHERE patient_id IN ($1,$2)`,
		`INSERT INTO earnings (professional_id,payment_id,gross,platform_fee,net)
		 SELECT $3,p.id,100000,10000,90000 FROM payments p JOIN bookings b ON b.id=p.booking_id WHERE b.patient_id IN ($1,$2)`,
		`INSERT INTO care_packages (patient_id,professional_id,expires_at)
		 VALUES ($1,$3,now()+interval '42 days'),($2,$3,now()+interval '42 days')`,
		`INSERT INTO care_sessions (patient_id,professional_id,scheduled_at)
		 VALUES ($1,$3,now()+interval '1 day'),($2,$3,now()+interval '2 days')`,
		`INSERT INTO care_refunds (patient_id,professional_id,idempotency_key)
		 VALUES ($1,$3,'qa-preview-refund'),($2,$3,'qa-real-refund')`,
		`INSERT INTO doctor_reviews (professional_id,patient_id,booking_id,helpfulness_percent,helpful)
		 SELECT $3,patient_id,id,90,true FROM bookings WHERE patient_id IN ($1,$2)`,
		`UPDATE professional_credentials SET review_count=2,helpfulness_count=2 WHERE user_id='a1111111-1111-4111-8111-111111111111'`,
		`INSERT INTO notifications (user_id,type,title,body) VALUES
		 ($1,'booking_confirmed','Preview','demo'),($2,'booking_confirmed','Nyata','tetap')`,
		`INSERT INTO notification_outbox (notification_id) SELECT id FROM notifications WHERE user_id IN ($1,$2)`,
	}
	for _, query := range fixtures {
		// pgx mensyaratkan jumlah argumen tepat sesuai placeholder. Sebagian
		// fixture hanya membutuhkan kedua pasien, lainnya juga profesional.
		var args []any
		if strings.Contains(query, "$1") {
			args = []any{qaPreviewPatientID, qaRealPatientID}
		}
		if strings.Contains(query, "$3") {
			args = append(args, qaProfessionalID)
		}
		if _, err := conn.ExecContext(ctx, query, args...); err != nil {
			t.Fatalf("siapkan fixture: %v", err)
		}
	}

	// Act + Assert: jalankan berkas SQL sebenarnya dua kali, bukan salinan
	// logikanya. Penghapusan harus selesai tanpa FK error dan tanpa pasien lain.
	for run := 1; run <= 2; run++ {
		qaApplyMigration(t, conn, ctx, filepath.Join("..", "..", "migrations", "029_hapus_pasien_preview.sql"))
		if got := qaCount(t, conn, ctx, `SELECT count(*) FROM users WHERE id=$1`, qaPreviewPatientID); got != 0 {
			t.Errorf("iterasi %d: pasien preview masih ada", run)
		}
		for _, table := range []string{"users", "patient_profiles", "patient_professional_links", "patient_data_consents", "diary_entries", "chat_messages", "screening_sessions", "audit_logs", "crisis_incidents", "bookings", "care_packages", "care_sessions", "care_refunds", "doctor_reviews", "notifications"} {
			column := "patient_id"
			switch table {
			case "users":
				column = "id"
			case "patient_profiles", "notifications":
				column = "user_id"
			}
			if got := qaCount(t, conn, ctx, "SELECT count(*) FROM "+table+" WHERE "+column+"=$1", qaRealPatientID); got != 1 {
				t.Errorf("iterasi %d: %s pasien nyata berjumlah %d, mau 1", run, table, got)
			}
			if got := qaCount(t, conn, ctx, "SELECT count(*) FROM "+table+" WHERE "+column+"=$1", qaPreviewPatientID); got != 0 {
				t.Errorf("iterasi %d: %s masih memiliki %d baris preview, mau 0", run, table, got)
			}
		}
		for _, table := range []string{"payments", "earnings", "notification_outbox"} {
			if got := qaCount(t, conn, ctx, "SELECT count(*) FROM "+table); got != 1 {
				t.Errorf("iterasi %d: %s berjumlah %d, mau 1 milik pasien nyata", run, table, got)
			}
		}
		var reviews, helpful int
		if err := conn.QueryRowContext(ctx, `SELECT review_count,helpfulness_count FROM professional_credentials WHERE user_id=$1`, qaProfessionalID).Scan(&reviews, &helpful); err != nil {
			t.Fatal(err)
		}
		if reviews != 1 || helpful != 1 {
			t.Errorf("iterasi %d: cache review=(%d,%d), mau (1,1)", run, reviews, helpful)
		}
	}
}

func TestQAPreviewCleanupTidakMenghapusIdentitasLain(t *testing.T) {
	for _, fixture := range []struct {
		name, id, email, role string
	}{
		{"UUID_sama_email_berbeda", qaPreviewPatientID, "pasien.nyata@example.test", "patient"},
		{"email_sama_UUID_berbeda", qaRealPatientID, "preview_pasien@malva.app", "patient"},
		{"identitas_sama_role_berbeda", qaPreviewPatientID, "preview_pasien@malva.app", "professional"},
	} {
		t.Run(fixture.name, func(t *testing.T) {
			conn, ctx := qaMigrationSchema(t)
			if _, err := conn.ExecContext(ctx, `INSERT INTO users (id,email,password_hash,role,display_name)
			 VALUES ($1,$2,'test',$3,'Pasien Preview')`, fixture.id, fixture.email, fixture.role); err != nil {
				t.Fatal(err)
			}
			qaApplyMigration(t, conn, ctx, filepath.Join("..", "..", "migrations", "029_hapus_pasien_preview.sql"))
			if got := qaCount(t, conn, ctx, `SELECT count(*) FROM users WHERE id=$1 AND email=$2`, fixture.id, fixture.email); got != 1 {
				t.Fatal("migrasi menghapus identitas selain kombinasi UUID/email/role preview yang diketahui")
			}
		})
	}
}

// TestQAPreviewCleanupClearsResolvedByOnOtherIncident menjaga celah FK NO ACTION
// pada crisis_incidents.resolved_by. Bila pasien preview pernah menjadi pelaku
// (resolved_by) pada insiden milik pasien LAIN, kolom itu menghalangi DELETE
// users sehingga migrasi 029 gagal 23503. Perilaku yang benar: resolved_by
// di-NULL-kan (bukan insidennya dihapus) sehingga migrasi selesai, pasien
// preview hilang, dan insiden pasien sungguhan tetap utuh dengan pelaku NULL.
func TestQAPreviewCleanupClearsResolvedByOnOtherIncident(t *testing.T) {
	conn, ctx := qaMigrationSchema(t)
	// Arrange: preview kanonis + pasien sungguhan; insiden milik pasien
	// sungguhan dengan resolved_by = preview.
	if _, err := conn.ExecContext(ctx,
		`INSERT INTO users (id,email,password_hash,role,display_name) VALUES
		 ($1,'preview_pasien@malva.app','test','patient','Pasien Preview'),
		 ($2,'pasien.nyata@example.test','test','patient','Pasien Nyata')`,
		qaPreviewPatientID, qaRealPatientID); err != nil {
		t.Fatalf("siapkan user: %v", err)
	}
	var incidentID string
	if err := conn.QueryRowContext(ctx,
		`INSERT INTO crisis_incidents (patient_id,triggered_by,resolved_by)
		 VALUES ($1,'manual',$2) RETURNING id`,
		qaRealPatientID, qaPreviewPatientID).Scan(&incidentID); err != nil {
		t.Fatalf("siapkan insiden: %v", err)
	}

	// Act: jalankan berkas migrasi 029 yang SEBENARNYA — tidak boleh error FK.
	qaApplyMigration(t, conn, ctx, filepath.Join("..", "..", "migrations", "029_hapus_pasien_preview.sql"))

	// Assert: preview hilang; insiden pasien sungguhan MASIH ADA dengan pelaku NULL.
	if got := qaCount(t, conn, ctx, `SELECT count(*) FROM users WHERE id=$1`, qaPreviewPatientID); got != 0 {
		t.Errorf("pasien preview masih ada (count=%d, mau 0)", got)
	}
	var owner string
	var resolvedBy sql.NullString
	if err := conn.QueryRowContext(ctx,
		`SELECT patient_id::text, resolved_by::text FROM crisis_incidents WHERE id=$1`, incidentID).
		Scan(&owner, &resolvedBy); err != nil {
		t.Fatalf("insiden pasien sungguhan hilang / tak terbaca: %v", err)
	}
	if owner != qaRealPatientID {
		t.Errorf("insiden berpindah pemilik: %s, mau %s", owner, qaRealPatientID)
	}
	if resolvedBy.Valid {
		t.Errorf("resolved_by masih terisi (%q), mau NULL", resolvedBy.String)
	}
}
