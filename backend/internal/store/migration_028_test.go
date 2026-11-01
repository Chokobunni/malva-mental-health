package store

import (
	"os"
	"testing"
)

// ============================================================
// QA — verifikasi migrasi 028 (W3) terhadap ATURAN YANG DIPERBAIKI.
//
// Aturan "link sah" = BUKTI KLINIS SAJA:
//   * care_sessions.status IN ('scheduled','completed'), ATAU
//   * care_packages.status IN ('active','expired').
// Klausa `bookings` (pending/paid) HARUS DIHAPUS: sesi no_show hanya ada
// karena ada booking yang dibayar, jadi klausa bookings membuat aturan
// membatalkan dirinya sendiri (link no_show-only tak pernah dinonaktifkan).
//
// CATATAN: test ini menjalankan berkas migrasi 028 APA ADANYA. Pada SQL yang
// BELUM diperbaiki, kasus (c) & (E) GAGAL — memang itu bukti bug yang harus
// diperbaiki engineer. Setelah SQL diperbaiki (klausa bookings dihapus),
// semua kasus hijau.
//
// Butuh Postgres: di-skip bila MALVA_TEST_DATABASE_URL kosong.
// ============================================================

// TestMigration028CorrectedRule mengunci perilaku aturan yang benar:
// (a) sesi scheduled -> tetap active
// (b) paket active -> tetap active
// (c) HANYA sesi no_show + booking paid -> jadi inactive  (kasus bug)
// (d) hanya no_show tanpa booking -> inactive
// (E) HANYA booking paid (tanpa sesi/paket) -> inactive (bookings bukan bukti)
// (F) sesi completed -> tetap active
// (e) idempoten: run kedua tidak mengubah status apa pun.
func TestMigration028CorrectedRule(t *testing.T) {
	db, ctx := openMigrationTestDB(t)

	type pair struct {
		pid, rid string
	}
	newPair := func(tag, role, name string) pair {
		p := insertTestUser(t, db, ctx, "patient", name, "m28p"+tag)
		r := insertTestUser(t, db, ctx, "professional", "Prof "+name, "m28r"+tag)
		t.Cleanup(func() { cleanupTestUsers(t, db, p, r) })
		return pair{p, r}
	}
	insertActiveLink := func(pr pair) {
		if _, err := db.ExecContext(ctx, `INSERT INTO patient_professional_links
			(patient_id, professional_id, status) VALUES ($1,$2,'active')
			ON CONFLICT DO NOTHING`, pr.pid, pr.rid); err != nil {
			t.Fatalf("insert link: %v", err)
		}
	}
	insertSession := func(pr pair, status string) {
		if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions
			(patient_id, professional_id, session_type, scheduled_at, duration_minutes, status)
			VALUES ($1,$2,'video', now() - interval '1 day', 30, $3)`,
			pr.pid, pr.rid, status); err != nil {
			t.Fatalf("insert sesi %s: %v", status, err)
		}
	}
	insertPackage := func(pr pair, status string) {
		if _, err := db.ExecContext(ctx, `INSERT INTO care_packages
			(patient_id, professional_id, status, expires_at)
			VALUES ($1,$2,$3, now() + interval '30 day')`, pr.pid, pr.rid, status); err != nil {
			t.Fatalf("insert paket %s: %v", status, err)
		}
	}
	insertBooking := func(pr pair, status string) {
		if _, err := db.ExecContext(ctx, `INSERT INTO bookings
			(patient_id, professional_id, service_type, session_type, booking_date,
			 slot_time, price, status)
			VALUES ($1,$2,'quick_consult','video','2026-01-02','10:00',100000,$3)`,
			pr.pid, pr.rid, status); err != nil {
			t.Fatalf("insert booking %s: %v", status, err)
		}
	}

	// (a) sesi scheduled -> active
	pA := newPair("a", "patient", "A Terjadwal")
	insertActiveLink(pA)
	insertSession(pA, "scheduled")

	// (b) paket active -> active
	pB := newPair("b", "patient", "B Paket")
	insertActiveLink(pB)
	insertPackage(pB, "active")

	// (c) HANYA no_show + booking paid -> INACTIVE (bug: SQL lama menyimpannya active)
	pC := newPair("c", "patient", "C NoShow Paid")
	insertActiveLink(pC)
	insertSession(pC, "no_show")
	insertBooking(pC, "paid")

	// (d) hanya no_show tanpa booking -> inactive
	pD := newPair("d", "patient", "D NoShow Saja")
	insertActiveLink(pD)
	insertSession(pD, "no_show")

	// (E) HANYA booking paid tanpa sesi/paket -> inactive (bookings bukan bukti)
	pE := newPair("e", "patient", "E Booking Saja")
	insertActiveLink(pE)
	insertBooking(pE, "paid")

	// (F) sesi completed -> active
	pF := newPair("f", "patient", "F Selesai")
	insertActiveLink(pF)
	insertSession(pF, "completed")

	content, err := os.ReadFile(migrationFilePath(t, "028_digest_and_deactivate_noshow_links.sql"))
	if err != nil {
		t.Fatalf("baca migrasi 028: %v", err)
	}
	if _, err := db.ExecContext(ctx, string(content)); err != nil {
		t.Fatalf("jalankan 028 (iterasi 1): %v", err)
	}

	statusOf := func(pr pair) string {
		var s string
		if err := db.QueryRowContext(ctx, `SELECT status FROM patient_professional_links
			WHERE patient_id=$1 AND professional_id=$2`, pr.pid, pr.rid).Scan(&s); err != nil {
			t.Fatalf("baca status: %v", err)
		}
		return s
	}
	expect := func(label string, pr pair, want string) {
		if got := statusOf(pr); got != want {
			t.Errorf("%s: status=%q, mau %q", label, got, want)
		}
	}

	expect("(a) sesi scheduled", pA, "active")
	expect("(b) paket active", pB, "active")
	expect("(c) no_show + booking paid", pC, "inactive")
	expect("(d) no_show saja", pD, "inactive")
	expect("(E) booking paid saja", pE, "inactive")
	expect("(F) sesi completed", pF, "active")

	// (e) Idempoten: run kedua tidak mengubah apa pun.
	if _, err := db.ExecContext(ctx, string(content)); err != nil {
		t.Fatalf("jalankan 028 (iterasi 2): %v", err)
	}
	expect("(a) setelah run 2", pA, "active")
	expect("(b) setelah run 2", pB, "active")
	expect("(c) setelah run 2", pC, "inactive")
	expect("(d) setelah run 2", pD, "inactive")
	expect("(E) setelah run 2", pE, "inactive")
	expect("(F) setelah run 2", pF, "active")
}

// TestMigration028NoOpTanpaLink: menjalankan 028 pada keadaan tanpa link yang
// memenuhi syarat deaktivasi tidak boleh error dan tidak mengubah apa pun.
// (Struktur WHERE l.status='active' AND NOT EXISTS(...) menjamin no-op pada
// database tanpa link — tidak ada baris yang cocok.)
func TestMigration028NoOpTanpaLink(t *testing.T) {
	db, ctx := openMigrationTestDB(t)

	content, err := os.ReadFile(migrationFilePath(t, "028_digest_and_deactivate_noshow_links.sql"))
	if err != nil {
		t.Fatalf("baca migrasi 028: %v", err)
	}

	// Profesional "hantu" tanpa link apa pun: tidak ada yang bisa diubah.
	// patient_professional_links.professional_id bertipe uuid, jadi nilai hantu
	// wajib berupa UUID valid yang dijamin tidak punya baris (bukan string biasa).
	const phantom = "00000000-0000-0000-0000-0000000000ff"
	var before int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM patient_professional_links
		WHERE professional_id = $1`, phantom).Scan(&before); err != nil {
		t.Fatalf("hitung awal: %v", err)
	}
	if before != 0 {
		t.Fatalf("prasyarat: profesional hantu harus tanpa link, dapat %d", before)
	}

	// Jalankan dua kali — harus tanpa error dan tetap tanpa link.
	for i := 1; i <= 2; i++ {
		if _, err := db.ExecContext(ctx, string(content)); err != nil {
			t.Fatalf("jalankan 028 (iterasi %d): %v", i, err)
		}
	}
	var after int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM patient_professional_links
		WHERE professional_id = $1`, phantom).Scan(&after); err != nil {
		t.Fatalf("hitung akhir: %v", err)
	}
	if after != 0 {
		t.Fatalf("profesional hantu mendapat %d link (mau 0)", after)
	}
}
