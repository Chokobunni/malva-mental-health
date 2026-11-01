package store

import (
	"fmt"
	"os"
	"testing"
)

// ============================================================
// QA — verifikasi UpsertDailyDigest (W1): notifikasi low-priority digabung
// menjadi satu baris digest per (user, jenis, profesional, hari WIB), TANPA
// baris notification_outbox (tidak ada push).
// Butuh Postgres: di-skip bila MALVA_TEST_DATABASE_URL kosong.
// ============================================================

func TestUpsertDailyDigestCoalesces(t *testing.T) {
	db, ctx := openMigrationTestDB(t)
	patient := insertTestUser(t, db, ctx, "patient", "Pasien Digest", "m28digp")
	prof := insertTestUser(t, db, ctx, "professional", "Rina Prasetyo, M.Psi", "m28digr")
	t.Cleanup(func() { cleanupTestUsers(t, db, patient, prof) })

	// Pastikan indeks unik digest (migrasi 028) sudah ada.
	content, err := os.ReadFile(migrationFilePath(t, "028_digest_and_deactivate_noshow_links.sql"))
	if err != nil {
		t.Fatalf("baca migrasi 028: %v", err)
	}
	if _, err := db.ExecContext(ctx, string(content)); err != nil {
		t.Fatalf("jalankan 028: %v", err)
	}

	st := New(db)
	base := Notification{
		UserID: patient,
		Type:   "screening_reviewed",
		Title:  "Screening sudah direview",
		Body:   "1 pembaruan screening dari Rina Prasetyo, M.Psi.",
		Data:   map[string]string{"professional_id": prof},
	}
	format := func(count int) string {
		return fmt.Sprintf("%d pembaruan screening dari Rina Prasetyo, M.Psi.", count)
	}

	first, err := st.UpsertDailyDigest(ctx, base, format)
	if err != nil {
		t.Fatalf("digest pertama: %v", err)
	}
	if got := first.Data["digest_count"]; got != "1" {
		t.Fatalf("digest_count pertama=%q, mau 1", got)
	}

	// Panggilan kedua (hari yang sama, profesional sama) harus MENGGABUNG.
	second, err := st.UpsertDailyDigest(ctx, base, format)
	if err != nil {
		t.Fatalf("digest kedua: %v", err)
	}
	if got := second.Data["digest_count"]; got != "2" {
		t.Fatalf("digest_count kedua=%q, mau 2", got)
	}
	if second.ID != first.ID {
		t.Fatalf("baris digest harus sama (id %q != %q)", second.ID, first.ID)
	}
	if second.Body != "2 pembaruan screening dari Rina Prasetyo, M.Psi." {
		t.Fatalf("body digest tidak diperbarui: %q", second.Body)
	}

	// Tepat satu baris notifikasi untuk pasangan ini.
	var notifCount int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM notifications
		WHERE user_id=$1 AND type='screening_reviewed'`, patient).Scan(&notifCount); err != nil {
		t.Fatalf("hitung notifikasi: %v", err)
	}
	if notifCount != 1 {
		t.Fatalf("jumlah notifikasi=%d, mau 1 (digest digabung)", notifCount)
	}

	// TIDAK ada baris outbox -> tidak ada push untuk digest.
	var outboxCount int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM notification_outbox
		WHERE notification_id=$1`, first.ID).Scan(&outboxCount); err != nil {
		t.Fatalf("hitung outbox: %v", err)
	}
	if outboxCount != 0 {
		t.Fatalf("outbox digest=%d, mau 0 (digest tidak push)", outboxCount)
	}
}
