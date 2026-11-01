package store

import (
	"testing"

	"malva/backend/internal/screening"
)

// ============================================================
// QA — W6(a): ListCrisisIncidentLog menggabungkan insiden SOS
// (crisis_incidents) DAN flag krisis screening (screening_sessions) untuk
// pasien terhubung, terbaru di atas, dengan hitungan total/unresolved.
//
// Butuh Postgres: di-skip bila MALVA_TEST_DATABASE_URL kosong.
// ============================================================

func TestListCrisisIncidentLogGabunganSumber(t *testing.T) {
	db, ctx := openMigrationTestDB(t)

	patient := insertTestUser(t, db, ctx, "patient", "Ami Krisis", "m6ami")
	prof := insertTestUser(t, db, ctx, "professional", "Rina Prasetyo", "m6rina")
	t.Cleanup(func() { cleanupTestUsers(t, db, patient, prof) })

	// Link aktif pasien–profesional agar pasien masuk himpunan feed.
	if _, err := db.ExecContext(ctx, `INSERT INTO patient_professional_links
		(patient_id, professional_id, status) VALUES ($1,$2,'active')
		ON CONFLICT DO NOTHING`, patient, prof); err != nil {
		t.Fatalf("insert link: %v", err)
	}

	st := New(db)

	// Sumber 1: insiden SOS.
	if _, err := st.CreateCrisisIncident(ctx, CrisisIncident{
		PatientID:   patient,
		TriggeredBy: "sos_button",
	}); err != nil {
		t.Fatalf("buat insiden SOS: %v", err)
	}

	// Sumber 2: screening dengan crisis_flag (item PHQ-9 self-harm > 0).
	bundle, err := screening.ScoreBundle(
		[]int{0, 0, 0, 0, 0, 0, 0, 0, 3},
		[]int{0, 0, 0, 0, 0, 0, 0},
	)
	if err != nil {
		t.Fatalf("score bundle: %v", err)
	}
	if !bundle.CrisisFlag {
		t.Fatalf("prasyarat: bundle harus crisis_flag=true (self_harm>0)")
	}
	if _, err := st.CreateScreeningBundle(ctx, CreateScreeningParams{
		PatientID:   patient,
		SubmittedBy: patient,
		IsInitial:   true,
		Bundle:      bundle,
	}); err != nil {
		t.Fatalf("buat screening krisis: %v", err)
	}

	feed, err := st.ListCrisisIncidentLog(ctx, prof, 50)
	if err != nil {
		t.Fatalf("list feed: %v", err)
	}

	// Kedua sumber hadir dalam SATU respons.
	sources := map[string]int{}
	for _, it := range feed.Items {
		sources[it.Source]++
	}
	if sources["sos"] < 1 {
		t.Errorf("feed tidak memuat sumber SOS: %+v", sources)
	}
	if sources["screening"] < 1 {
		t.Errorf("feed tidak memuat sumber screening: %+v", sources)
	}
	if feed.Counts.Total < 2 {
		t.Errorf("counts.total=%d, mau >= 2", feed.Counts.Total)
	}
	if feed.Counts.Unresolved < 2 {
		t.Errorf("counts.unresolved=%d, mau >= 2", feed.Counts.Unresolved)
	}

	// Terbaru di atas (hanya gagal bila yang lebih lama muncul sebelum yang
	// lebih baru; timestamp sama tidak dianggap pelanggaran).
	for i := 1; i < len(feed.Items); i++ {
		if feed.Items[i].CreatedAt.After(feed.Items[i-1].CreatedAt) {
			t.Errorf("feed tidak terurut terbaru-dulu di indeks %d: %v > %v",
				i, feed.Items[i].CreatedAt, feed.Items[i-1].CreatedAt)
		}
	}
}
