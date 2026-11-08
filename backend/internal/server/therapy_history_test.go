package server

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
	"malva/backend/internal/store"
)

func TestTherapyFullHistoryPreservesOwnershipConsentAndDefaultLimit(t *testing.T) {
	f := newTherapyConsentFixture(t)
	for _, patient := range []string{f.patient.ID, f.other.ID} {
		_, err := f.db.ExecContext(context.Background(), `INSERT INTO therapy_submissions(patient_id,module_id,title,answers,summary,created_at) SELECT $1,'abcde','Test','{}','',$2::timestamptz + make_interval(mins=>n) FROM generate_series(1,125)n`, patient, clock.Now())
		if err != nil {
			t.Fatal(err)
		}
	}
	list := func(subject, role, query string, want int) {
		t.Helper()
		rec := httptest.NewRecorder()
		f.srv.listTherapySubmissions(rec, httptest.NewRequest(http.MethodGet, "/v1/therapy-submissions"+query, nil), auth.Claims{Subject: subject, Role: role})
		if rec.Code != http.StatusOK {
			t.Fatalf("status%d: %s", rec.Code, rec.Body.String())
		}
		var payload struct {
			Submissions []store.TherapySubmission `json:"submissions"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
			t.Fatal(err)
		}
		if len(payload.Submissions) != want {
			t.Fatalf("query%s: got%d want%d", query, len(payload.Submissions), want)
		}
		for _, row := range payload.Submissions {
			if row.PatientID != f.patient.ID {
				t.Fatal("another patient's history leaked")
			}
		}
	}
	list(f.patient.ID, "patient", "", 100)
	list(f.patient.ID, "patient", "?limit=0", 125)
	list(f.patient.ID, "patient", "?limit=7", 7)
	list(f.prof.ID, "professional", "?patient_id="+f.patient.ID+"&limit=0", 0)
	if _, err := f.st.UpdatePatientDataConsent(context.Background(), store.PatientDataConsent{PatientID: f.patient.ID, ProfessionalID: f.prof.ID, ShareTherapyRecords: true}); err != nil {
		t.Fatal(err)
	}
	list(f.prof.ID, "professional", "?patient_id="+f.patient.ID+"&limit=0", 125)
}
