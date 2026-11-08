package store

import (
	"malva/backend/internal/clock"
	"testing"
)

func TestPatientFullHistoryKeepsMoreThan100AndPatientIsolation(t *testing.T) {
	s, db, ctx := attendedTestStore(t)
	patient, other := mustUUID(t, db, ctx), mustUUID(t, db, ctx)
	for _, id := range []string{patient, other} {
		if _, err := db.ExecContext(ctx, `INSERT INTO users(id,email,password_hash,role,display_name) VALUES($1,$2,'test','patient','Uji riwayat')`, id, id+"@history.test"); err != nil {
			t.Fatal(err)
		}
	}
	t.Cleanup(func() { cleanupTestUsers(t, db, patient, other) })
	for _, query := range []string{
		`INSERT INTO mood_checkins(patient_id,mood,energy,anxiety,irritability,occurred_at) SELECT $1,'baik',5,3,2,$2::timestamptz + make_interval(mins=>n) FROM generate_series(1,125)n`,
		`INSERT INTO diary_entries(patient_id,mood,title,note,occurred_at) SELECT $1,'baik','Judul uji','Catatan uji',$2::timestamptz + make_interval(mins=>n) FROM generate_series(1,125)n`,
		`INSERT INTO medication_logs(patient_id,medication_name,status,taken_at) SELECT $1,'Obat uji','taken',$2::timestamptz + make_interval(mins=>n) FROM generate_series(1,125)n`,
		`INSERT INTO screening_sessions(patient_id,submitted_by,rule_version,overall_level,created_at) SELECT $1,$1,'test','minimal',$2::timestamptz + make_interval(mins=>n) FROM generate_series(1,125)n`,
	} {
		for _, id := range []string{patient, other} {
			if _, err := db.ExecContext(ctx, query, id, clock.Now()); err != nil {
				t.Fatal(err)
			}
		}
	}
	for _, limit := range []int{0, 7} {
		want := limit
		if limit == 0 {
			want = 125
		}
		moods, err := s.ListMoodCheckins(ctx, patient, limit)
		if err != nil {
			t.Fatal(err)
		}
		diaries, err := s.ListDiaryEntries(ctx, patient, false, limit)
		if err != nil {
			t.Fatal(err)
		}
		logs, err := s.ListMedicationLogs(ctx, patient, limit)
		if err != nil {
			t.Fatal(err)
		}
		screenings, err := s.ListScreeningSessions(ctx, patient, limit)
		if err != nil {
			t.Fatal(err)
		}
		if len(screenings) != want {
			t.Fatalf("screening limit%d: got%d, want%d", limit, len(screenings), want)
		}
		if len(moods) != want || len(diaries) != want || len(logs) != want {
			t.Fatalf("limit%d: moods%d diaries%d logs%d, want%d", limit, len(moods), len(diaries), len(logs), want)
		}
		for i := 0; i < want; i++ {
			if screenings[i].PatientID != patient || moods[i].PatientID != patient || diaries[i].PatientID != patient || logs[i].PatientID != patient {
				t.Fatal("history leaked another patient's rows")
			}
			if i > 0 && (screenings[i].CreatedAt.After(screenings[i-1].CreatedAt) || moods[i].OccurredAt.After(moods[i-1].OccurredAt) || diaries[i].OccurredAt.After(diaries[i-1].OccurredAt) || logs[i].TakenAt.After(logs[i-1].TakenAt)) {
				t.Fatal("history not newest first")
			}
		}
	}
}
