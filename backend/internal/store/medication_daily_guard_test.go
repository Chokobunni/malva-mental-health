package store

import (
	"errors"
	"sync"
	"testing"
	"time"

	"malva/backend/internal/clock"
)

func TestMedicationConsumedLogsAreAtomicAndIdempotentFor24Hours(t *testing.T) {
	s, db, ctx := attendedTestStore(t)
	patient := mustUUID(t, db, ctx)
	if _, err := db.ExecContext(ctx, `INSERT INTO users(id,email,password_hash,role,display_name) VALUES($1,$2,'test','patient','Uji obat')`, patient, patient+"@medication.test"); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { cleanupTestUsers(t, db, patient) })
	med, err := s.UpsertMedication(ctx, Medication{PatientID: patient, Name: "Obat uji", CurrentStock: 30, Schedule: []byte(`{"times":[],"weekdays":[1,2,3,4,5,6,7],"start_at":"2026-01-01T00:00:00+07:00","units_per_dose":2}`)})
	if err != nil {
		t.Fatal(err)
	}
	firstAt := clock.Now().Add(-25 * time.Hour)
	input := MedicationLog{PatientID: patient, MedicationID: med.ID, MedicationName: med.Name, Status: "taken", TakenAt: firstAt}
	first, err := s.CreateMedicationLog(ctx, input)
	if err != nil {
		t.Fatal(err)
	}
	for _, delta := range []time.Duration{0, 2 * time.Minute, 24*time.Hour - time.Second, -time.Hour} {
		input.TakenAt = firstAt.Add(delta)
		duplicate, err := s.CreateMedicationLog(ctx, input)
		if err != nil || duplicate.ID != first.ID {
			t.Fatalf("repeat at %s: got %s, want existing %s (err %v)", delta, duplicate.ID, first.ID, err)
		}
	}
	input.Status = "skipped"
	input.TakenAt = firstAt.Add(time.Hour)
	if _, err := s.CreateMedicationLog(ctx, input); err != nil {
		t.Fatal(err)
	}
	input.Status = "partial"
	input.TakenAt = firstAt.Add(24 * time.Hour)
	second, err := s.CreateMedicationLog(ctx, input)
	if err != nil || second.ID == first.ID {
		t.Fatalf("24 hour boundary must permit next dose: %v", err)
	}
	input.Status = "taken"
	input.TakenAt = second.TakenAt.Add(time.Minute)
	duplicate, err := s.CreateMedicationLog(ctx, input)
	if err != nil || duplicate.ID != second.ID {
		t.Fatalf("partial also consumes and must block taken: %v", err)
	}
	var stock, logs int
	if err := db.QueryRowContext(ctx, `SELECT current_stock FROM medications WHERE id=$1`, med.ID).Scan(&stock); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRowContext(ctx, `SELECT count(*) FROM medication_logs WHERE medication_id=$1`, med.ID).Scan(&logs); err != nil {
		t.Fatal(err)
	}
	if stock != 26 || logs != 3 {
		t.Fatalf("stock=%d logs=%d; want 26 and 3 (two consumed, one skipped)", stock, logs)
	}
}

func TestMedicationConcurrentClientsConsumeOneDose(t *testing.T) {
	s, db, ctx := attendedTestStore(t)
	patient, other := mustUUID(t, db, ctx), mustUUID(t, db, ctx)
	for _, id := range []string{patient, other} {
		if _, err := db.ExecContext(ctx, `INSERT INTO users(id,email,password_hash,role,display_name) VALUES($1,$2,'test','patient','Uji obat')`, id, id+"@medication.test"); err != nil {
			t.Fatal(err)
		}
	}
	t.Cleanup(func() { cleanupTestUsers(t, db, patient, other) })
	med, err := s.UpsertMedication(ctx, Medication{PatientID: patient, Name: "Obat uji", CurrentStock: 10})
	if err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	ids := make(chan string, 12)
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			log, err := s.CreateMedicationLog(ctx, MedicationLog{PatientID: patient, MedicationID: med.ID, MedicationName: med.Name, Status: "taken"})
			if err != nil {
				t.Error(err)
			}
			ids <- log.ID
		}()
	}
	wg.Wait()
	close(ids)
	unique := map[string]bool{}
	for id := range ids {
		unique[id] = true
	}
	var stock int
	if err := db.QueryRowContext(ctx, `SELECT current_stock FROM medications WHERE id=$1`, med.ID).Scan(&stock); err != nil {
		t.Fatal(err)
	}
	if len(unique) != 1 || stock != 9 {
		t.Fatalf("concurrent submissions produced %d logs, stock %d; want one log and stock9", len(unique), stock)
	}
	_, err = s.CreateMedicationLog(ctx, MedicationLog{PatientID: other, MedicationID: med.ID, MedicationName: med.Name, Status: "taken"})
	if !errors.Is(err, ErrMedicationNotFound) {
		t.Fatalf("foreign medication must reject: %v", err)
	}
}
