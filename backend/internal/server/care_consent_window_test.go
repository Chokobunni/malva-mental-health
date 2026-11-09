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
