package server

import (
	"bytes"
	"context"
	"encoding/json"
	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
	"malva/backend/internal/store"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestConsentPreferencesOnlyApplyDuringScheduledDuration(t *testing.T) {
	f := newClinicalFixture(t)
	req := httptest.NewRequest(http.MethodGet, "/", nil)
	if _, err := f.st.UpdatePatientDataConsent(context.Background(), store.PatientDataConsent{PatientID: f.patient.ID, ProfessionalID: f.prof.ID, ShareGoals: true}); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name   string
		offset time.Duration
		status string
		want   bool
	}{
		{"before-start", 5 * time.Minute, "scheduled", false},
		{"during", -time.Minute, "scheduled", true},
		{"ended", -time.Hour, "scheduled", false},
		{"cancelled", -time.Minute, "cancelled_by_patient", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := f.db.Exec(`UPDATE care_sessions SET scheduled_at=$2,duration_minutes=60,status=$3 WHERE id=$1`, f.sessionID, clock.Now().Add(tc.offset), tc.status); err != nil {
				t.Fatal(err)
			}
			if got := f.srv.consentAllows(req, f.patient.ID, f.prof.ID, "goals"); got != tc.want {
				t.Errorf("effective consent=%v want %v", got, tc.want)
			}
			pref, err := f.st.GetPatientDataConsent(context.Background(), f.patient.ID, f.prof.ID)
			if err != nil || !pref.ShareGoals {
				t.Fatalf("preference lost: %+v %v", pref, err)
			}
		})
	}
}

func TestOneTimeWorksheetShareAndReadExpireAtSessionEnd(t *testing.T) {
	f := newClinicalFixture(t)
	_, worksheet := f.seedSubmissions(t)
	share := func() *httptest.ResponseRecorder {
		body, _ := json.Marshal(map[string]string{"professional_id": f.prof.ID})
		req := httptest.NewRequest("POST", "/", bytes.NewReader(body))
		req.SetPathValue("submission_id", worksheet.ID)
		out := httptest.NewRecorder()
		f.srv.shareTherapySubmission(out, req, auth.Claims{Subject: f.patient.ID, Role: "patient"})
		return out
	}
	if out := share(); out.Code != http.StatusOK {
		t.Fatalf("active one-time worksheet share: %d %s", out.Code, out.Body)
	}
	if _, err := f.db.Exec(`UPDATE care_sessions SET scheduled_at=$2,duration_minutes=60 WHERE id=$1`, f.sessionID, clock.Now().Add(-time.Hour)); err != nil {
		t.Fatal(err)
	}
	if out := share(); out.Code != http.StatusForbidden {
		t.Fatalf("ended one-time share: %d %s", out.Code, out.Body)
	}
	req := httptest.NewRequest("GET", "/", nil)
	req.SetPathValue("submission_id", worksheet.ID)
	out := httptest.NewRecorder()
	f.srv.getTherapySubmission(out, req, auth.Claims{Subject: f.prof.ID, Role: "professional"})
	if out.Code != http.StatusNotFound {
		t.Fatalf("ended professional read: %d %s", out.Code, out.Body)
	}
}
func TestSessionNoteContextUsesCategoryConsentAndActiveRows(t *testing.T) {
	f := newClinicalFixture(t)
	ctx := context.Background()
	if _, err := f.db.Exec(`UPDATE care_sessions SET scheduled_at=$2,duration_minutes=60,status='completed' WHERE id=$1`, f.sessionID, clock.Now().Add(-2*time.Hour)); err != nil {
		t.Fatal(err)
	}
	if _, err := f.db.Exec(`INSERT INTO goals(patient_id,title,is_active) VALUES ($1,'Active goal',true),($1,'Inactive goal',false)`, f.patient.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := f.db.Exec(`INSERT INTO medications(patient_id,name,dosage,form,active) VALUES ($1,'Active medication','10 mg','Tablet',true),($1,'Inactive medication','10 mg','Tablet',false)`, f.patient.ID); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, _ = f.db.Exec("DELETE FROM goals WHERE patient_id=$1", f.patient.ID)
		_, _ = f.db.Exec("DELETE FROM medications WHERE patient_id=$1", f.patient.ID)
	})
	load := func() *httptest.ResponseRecorder {
		req := httptest.NewRequest("GET", "/", nil)
		req.SetPathValue("session_id", f.sessionID)
		out := httptest.NewRecorder()
		f.srv.careSessionNoteContext(out, req, auth.Claims{Subject: f.prof.ID, Role: "professional"})
		return out
	}
	for _, tc := range []struct{ goals, medications bool }{{}, {true, false}, {false, true}, {true, true}} {
		if _, err := f.st.UpdatePatientDataConsent(ctx, store.PatientDataConsent{
			PatientID: f.patient.ID, ProfessionalID: f.prof.ID, ShareGoals: tc.goals, ShareMedications: tc.medications,
		}); err != nil {
			t.Fatal(err)
		}
		out := load()
		body := out.Body.String()
		if out.Code != 200 || strings.Contains(body, "Active goal") != tc.goals ||
			strings.Contains(body, "Active medication") != tc.medications || strings.Contains(body, "Inactive") {
			t.Fatalf("goal=%t medication=%t: %d %s", tc.goals, tc.medications, out.Code, body)
		}
	}
	if _, err := f.db.Exec(`UPDATE care_sessions SET scheduled_at=$2 WHERE id=$1`, f.sessionID, clock.Now().Add(-25*time.Hour)); err != nil {
		t.Fatal(err)
	}
	if out := load(); out.Code != http.StatusForbidden {
		t.Fatalf("expired note context: %d %s", out.Code, out.Body)
	}
}
