package server

import (
	"context"
	"net/http"
	"testing"
	"time"

	"malva/backend/internal/clock"
	"malva/backend/internal/store"
)

func TestSessionNotesGoalMutationsRequireSelectedAuthorizedSession(t *testing.T) {
	f := newClinicalFixture(t)
	if _, err := f.db.Exec(`UPDATE care_sessions SET scheduled_at=$2,duration_minutes=60,status='completed' WHERE id=$1`, f.sessionID, clock.Now().Add(-2*time.Hour)); err != nil {
		t.Fatal(err)
	}
	body := map[string]any{"patient_id": f.patient.ID, "title": "Practice", "target_per_week": 3}
	for _, tc := range []struct {
		suffix string
		want   int
	}{
		{"", http.StatusForbidden},
		{"?session_id=" + f.sessionID, http.StatusCreated},
		{"?session_id=" + f.other.ID, http.StatusForbidden},
	} {
		out := f.call(t, "POST", "/v1/goals"+tc.suffix, "professional", f.prof.ID, body)
		if out.Code != tc.want {
			t.Fatalf("%s: %d %s", tc.suffix, out.Code, out.Body)
		}
	}
	goal, err := f.st.CreateGoal(context.Background(), store.UpsertGoalParams{PatientID: f.patient.ID, Title: "Edit me"})
	if err != nil {
		t.Fatal(err)
	}
	path := "/v1/goals/" + goal.ID + "?session_id=" + f.sessionID
	if out := f.call(t, "PATCH", path, "professional", f.prof.ID, body); out.Code != http.StatusOK {
		t.Fatalf("edit: %d %s", out.Code, out.Body)
	}
	if _, err := f.st.UpdatePatientDataConsent(context.Background(), store.PatientDataConsent{PatientID: f.patient.ID, ProfessionalID: f.prof.ID}); err != nil {
		t.Fatal(err)
	}
	if out := f.call(t, "PATCH", path, "professional", f.prof.ID, body); out.Code != http.StatusForbidden {
		t.Fatalf("no consent: %d %s", out.Code, out.Body)
	}
	if _, err := f.st.UpdatePatientDataConsent(context.Background(), store.PatientDataConsent{PatientID: f.patient.ID, ProfessionalID: f.prof.ID, ShareGoals: true}); err != nil {
		t.Fatal(err)
	}
	if _, err := f.db.Exec(`UPDATE care_sessions SET scheduled_at=$2 WHERE id=$1`, f.sessionID, clock.Now().Add(-25*time.Hour)); err != nil {
		t.Fatal(err)
	}
	if out := f.call(t, "PATCH", path, "professional", f.prof.ID, body); out.Code != http.StatusForbidden {
		t.Fatalf("cutoff: %d %s", out.Code, out.Body)
	}
}

func TestSessionNotesMedicationEditKeepsConsentRoleAndWindow(t *testing.T) {
	f := newClinicalFixture(t)
	if _, err := f.db.Exec(`UPDATE care_sessions SET scheduled_at=$2,duration_minutes=60,status='completed' WHERE id=$1`, f.sessionID, clock.Now().Add(-2*time.Hour)); err != nil {
		t.Fatal(err)
	}
	med, err := f.st.UpsertMedication(context.Background(), store.Medication{PatientID: f.patient.ID, Name: "Before", Dosage: "5 mg", Form: "Tablet"})
	if err != nil {
		t.Fatal(err)
	}
	body := map[string]any{"patient_id": f.patient.ID, "name": "After", "dosage": "10 mg", "form": "Tablet"}
	path := "/v1/medications/" + med.ID
	for _, tc := range []struct {
		suffix string
		want   int
	}{{"", 403}, {"?session_id=" + f.sessionID, 200}, {"?session_id=" + f.other.ID, 403}} {
		out := f.call(t, "PUT", path+tc.suffix, "professional", f.prof.ID, body)
		if out.Code != tc.want {
			t.Fatalf("%s: %d %s", tc.suffix, out.Code, out.Body)
		}
		created := f.call(t, "POST", "/v1/medications"+tc.suffix, "professional", f.prof.ID, body)
		wantCreate := tc.want
		if wantCreate == 200 {
			wantCreate = 201
		}
		if created.Code != wantCreate {
			t.Fatalf("create %s: %d %s", tc.suffix, created.Code, created.Body)
		}
	}
	if _, err := f.db.Exec(`UPDATE professional_credentials SET specialization='Psikolog' WHERE user_id=$1`, f.prof.ID); err != nil {
		t.Fatal(err)
	}
	if out := f.call(t, "PUT", path+"?session_id="+f.sessionID, "professional", f.prof.ID, body); out.Code != 403 {
		t.Fatalf("psychologist: %d %s", out.Code, out.Body)
	}
	if out := f.call(t, "POST", "/v1/medications?session_id="+f.sessionID, "professional", f.prof.ID, body); out.Code != 403 {
		t.Fatalf("psychologist create: %d %s", out.Code, out.Body)
	}
	if _, err := f.db.Exec(`UPDATE professional_credentials SET specialization='Sp.KJ' WHERE user_id=$1`, f.prof.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := f.st.UpdatePatientDataConsent(context.Background(), store.PatientDataConsent{PatientID: f.patient.ID, ProfessionalID: f.prof.ID}); err != nil {
		t.Fatal(err)
	}
	if out := f.call(t, "PUT", path+"?session_id="+f.sessionID, "professional", f.prof.ID, body); out.Code != 403 {
		t.Fatalf("revoked consent: %d %s", out.Code, out.Body)
	}
	if out := f.call(t, "POST", "/v1/medications?session_id="+f.sessionID, "professional", f.prof.ID, body); out.Code != 403 {
		t.Fatalf("revoked consent create: %d %s", out.Code, out.Body)
	}
	if _, err := f.st.UpdatePatientDataConsent(context.Background(), store.PatientDataConsent{PatientID: f.patient.ID, ProfessionalID: f.prof.ID, ShareMedications: true}); err != nil {
		t.Fatal(err)
	}
	if _, err := f.db.Exec(`UPDATE care_sessions SET scheduled_at=$2 WHERE id=$1`, f.sessionID, clock.Now().Add(-25*time.Hour)); err != nil {
		t.Fatal(err)
	}
	if out := f.call(t, "PUT", path+"?session_id="+f.sessionID, "professional", f.prof.ID, body); out.Code != 403 {
		t.Fatalf("cutoff: %d %s", out.Code, out.Body)
	}
	if out := f.call(t, "POST", "/v1/medications?session_id="+f.sessionID, "professional", f.prof.ID, body); out.Code != 403 {
		t.Fatalf("cutoff create: %d %s", out.Code, out.Body)
	}
	if _, err := f.db.Exec(`UPDATE care_sessions SET scheduled_at=$2,status='scheduled' WHERE id=$1`, f.sessionID, clock.Now().Add(-30*time.Minute)); err != nil {
		t.Fatal(err)
	}
	if out := f.call(t, "POST", "/v1/medications?session_id="+f.sessionID, "professional", f.prof.ID, body); out.Code != 201 {
		t.Fatalf("live create: %d %s", out.Code, out.Body)
	}
}
