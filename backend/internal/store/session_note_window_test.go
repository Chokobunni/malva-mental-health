package store

import (
	"context"
	"errors"
	"malva/backend/internal/clock"
	"testing"
	"time"
)

func TestSessionNoteWindow(t *testing.T) {
	start := time.Date(2026, 11, 5, 15, 0, 0, 0, time.FixedZone("WIB", 7*3600))
	end := start.Add(time.Hour)
	session := CareSession{ScheduledAt: start, DurationMinutes: 60, Status: "completed"}
	for _, tc := range []struct {
		when    time.Time
		allowed bool
	}{
		{end.Add(-time.Nanosecond), false},
		{end, true},
		{end.Add(24*time.Hour - time.Nanosecond), true},
		{end.Add(24 * time.Hour), false},
	} {
		if got := session.CanWriteNotesAt(tc.when); got != tc.allowed {
			t.Fatalf("at %s: got %t, want %t", tc.when, got, tc.allowed)
		}
	}
	session.Status = "scheduled"
	if session.CanWriteNotesAt(end) {
		t.Fatal("incomplete session allowed")
	}
}

func TestSessionNoteResourceWindow(t *testing.T) {
	start := time.Date(2026, 11, 28, 10, 0, 0, 0, clock.Location())
	for _, tc := range []struct {
		status string
		at     time.Time
		want   bool
	}{
		{"scheduled", start.Add(-time.Nanosecond), false},
		{"scheduled", start, true},
		{"scheduled", start.Add(time.Hour), false},
		{"completed", start.Add(time.Hour), true},
		{"completed", start.Add(25*time.Hour - time.Nanosecond), true},
		{"completed", start.Add(25 * time.Hour), false},
		{"cancelled_by_patient", start.Add(2 * time.Hour), false},
	} {
		cs := CareSession{ScheduledAt: start, DurationMinutes: 60, Status: tc.status}
		if got := cs.CanManageNoteResourcesAt(tc.at); got != tc.want {
			t.Fatalf("%s at %s: got %t want %t", tc.status, tc.at, got, tc.want)
		}
	}
}
func TestSaveCareSessionNotesIssuesPrescriptionOnce(t *testing.T) {
	s, db, ctx := attendedTestStore(t)
	sessionID, patientID, professionalID := mustUUID(t, db, ctx), mustUUID(t, db, ctx), mustUUID(t, db, ctx)
	if _, err := db.ExecContext(ctx, `INSERT INTO users (id,email,password_hash,role,display_name)
		VALUES ($1,$2,'x','patient','Patient'), ($3,$4,'x','professional','Professional')`,
		patientID, patientID+"@note.test", professionalID, professionalID+"@note.test"); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		cleanup, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		for _, query := range []string{
			"DELETE FROM audit_logs WHERE patient_id=$1",
			"DELETE FROM e_prescriptions WHERE patient_id=$1",
			"DELETE FROM medications WHERE patient_id=$1",
			"DELETE FROM care_sessions WHERE patient_id=$1",
		} {
			_, _ = db.ExecContext(cleanup, query, patientID)
		}
		_, _ = db.ExecContext(cleanup, "DELETE FROM users WHERE id IN ($1,$2)", patientID, professionalID)
	})
	if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions
		(id,patient_id,professional_id,session_type,scheduled_at,duration_minutes,status)
		VALUES ($1,$2,$3,'chat',$4,60,'completed')`,
		sessionID, patientID, professionalID, clock.Now().Add(-2*time.Hour)); err != nil {
		t.Fatal(err)
	}
	note := "Saved note"
	item := EPrescriptionItem{Name: "Example", Dosage: "10 mg", Form: "Tablet", Unit: "mg", CurrentStock: 10, Days: 30, UnitsPerDay: 1}
	token := mustUUID(t, db, ctx)
	rx := EPrescription{QRToken: token, Status: "issued"}
	_, _, _, err := s.SaveCareSessionNotes(ctx, sessionID, professionalID, nil, nil, &note, token, rx, []EPrescriptionItem{item, {ID: mustUUID(t, db, ctx)}})
	if !errors.Is(err, ErrPrescriptionConflict) {
		t.Fatalf("invalid item: %v", err)
	}
	if session, err := s.GetCareSession(ctx, sessionID); err != nil || session.PrivateNote != "" {
		t.Fatalf("note committed despite failed prescription: %q %v", session.PrivateNote, err)
	}
	saved, rxID, changed, err := s.SaveCareSessionNotes(ctx, sessionID, professionalID, nil, nil, &note, token, rx, []EPrescriptionItem{item, item})
	if err != nil || !changed || saved.PrivateNote != note || rxID == "" {
		t.Fatalf("note and prescription save: %q %q %t %v", saved.PrivateNote, rxID, changed, err)
	}
	if _, err := db.ExecContext(ctx, "UPDATE e_prescriptions SET qr_token=$2 WHERE id=$1", rxID, mustUUID(t, db, ctx)); err != nil {
		t.Fatal(err)
	}
	_, retryID, changed, err := s.SaveCareSessionNotes(ctx, sessionID, professionalID, nil, nil, &note, token, rx, []EPrescriptionItem{item, item})
	if err != nil || changed || retryID != "" {
		t.Fatalf("replay after QR rotation: %q %t %v", retryID, changed, err)
	}
	medications, err := s.ListMedications(ctx, patientID, 10)
	if err != nil || len(medications) != 2 {
		t.Fatalf("two intentional rows, no leaked or retried rows: %d %v", len(medications), err)
	}
}
