package store

import (
	"testing"
	"time"

	"malva/backend/internal/clock"
)

func TestCareSessionFeedKeepsScheduleAndBoundsHistory(t *testing.T) {
	db, ctx := openMigrationTestDB(t)
	var patientID, professionalID, otherPatientID string
	if err := db.QueryRowContext(ctx, `SELECT gen_random_uuid(),gen_random_uuid(),gen_random_uuid()`).
		Scan(&patientID, &professionalID, &otherPatientID); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, _ = db.ExecContext(ctx, `DELETE FROM care_sessions WHERE professional_id=$1`, professionalID)
	})
	nearest := clock.Now().Add(24 * time.Hour).Truncate(time.Microsecond)
	if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions(patient_id,professional_id,scheduled_at,status)
		SELECT $1,$2,$3::timestamptz + make_interval(hours => n),'scheduled' FROM generate_series(0,100) n`, patientID, professionalID, nearest); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions(patient_id,professional_id,scheduled_at,status)
		SELECT $1,$2,$3::timestamptz - make_interval(mins => n),'completed' FROM generate_series(0,100) n`, patientID, professionalID, clock.Now().Add(-time.Hour)); err != nil {
		t.Fatal(err)
	}
	var oldScheduledID string
	if err := db.QueryRowContext(ctx, `INSERT INTO care_sessions(patient_id,professional_id,scheduled_at,status)
		VALUES($1,$2,$3,'scheduled') RETURNING id`, patientID, professionalID, clock.Now().AddDate(0, 0, -30)).Scan(&oldScheduledID); err != nil {
		t.Fatal(err)
	}
	// A different patient's history must not inflate the selected patient's limit.
	if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions(patient_id,professional_id,scheduled_at,status)
		SELECT $1,$2,$3::timestamptz - make_interval(mins => n),'completed' FROM generate_series(0,149) n`, otherPatientID, professionalID, clock.Now().Add(-time.Minute)); err != nil {
		t.Fatal(err)
	}
	st := New(db)
	for _, actor := range []struct{ role, id, patient string }{
		{"professional", professionalID, patientID},
		{"patient", patientID, ""},
	} {
		t.Run(actor.role, func(t *testing.T) {
			t.Run("all upcoming includes nearest first", func(t *testing.T) {
				items, err := st.ListCareSessionFeed(ctx, actor.id, actor.role, "upcoming", actor.patient, 100)
				if err != nil {
					t.Fatal(err)
				}
				if len(items) != 101 {
					t.Fatalf("upcoming count=%d, want 101", len(items))
				}
				if !items[0].ScheduledAt.Equal(nearest) {
					t.Fatalf("upcoming nearest=%v, want %v", items[0].ScheduledAt, nearest)
				}
			})
			for _, scope := range []string{"past", "all"} {
				t.Run(scope+" keeps actionable before bounded history", func(t *testing.T) {
					items, err := st.ListCareSessionFeed(ctx, actor.id, actor.role, scope, actor.patient, 100)
					if err != nil {
						t.Fatal(err)
					}
					scheduled, terminal := 0, 0
					foundOld := false
					for _, item := range items {
						if item.PatientID != patientID {
							t.Fatal("feed included another patient's session")
						}
						if item.Status == "scheduled" {
							scheduled++
							if terminal > 0 {
								t.Fatal("actionable sessions sorted behind history")
							}
						} else {
							terminal++
						}
						foundOld = foundOld || item.ID == oldScheduledID
					}
					wantScheduled := 1
					if scope == "all" {
						wantScheduled = 102
					}
					if !foundOld || scheduled != wantScheduled || terminal != 100 {
						t.Fatalf("%s: old=%t scheduled=%d terminal=%d, want old=true scheduled=%d terminal=100", scope, foundOld, scheduled, terminal, wantScheduled)
					}
				})
			}
		})
	}
	legacy, err := st.ListCareSessions(ctx, professionalID, "professional", "upcoming", patientID, 7)
	if err != nil {
		t.Fatal(err)
	}
	if len(legacy) != 7 {
		t.Fatalf("legacy limit changed: count=%d", len(legacy))
	}
	if !legacy[0].ScheduledAt.Equal(nearest.Add(100 * time.Hour)) {
		t.Fatalf("legacy order changed: first=%v", legacy[0].ScheduledAt)
	}
}
