package server

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
)

func TestClinicalAllergyAccessAndRetry(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	other := createIdentityTestUser(t, db, st, "patient", nil)
	professional := createIdentityTestUser(t, db, st, "professional", nil)
	t.Cleanup(func() {
		_, _ = db.Exec("DELETE FROM care_sessions WHERE patient_id=$1", patient.ID)
	})
	ctx := context.Background()
	srv := newOnboardingTestServer(db)
	const payload = `{"client_id":"4e452b3f-aba5-4dfc-881b-6ecac4f70930","reaction_type":"side_effect","substance":"Obat uji","symptoms":"Mual","severity":"mild"}`
	create := func(subject, role, body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(http.MethodPost, "/v1/health-record/allergies", strings.NewReader(body))
		rec := httptest.NewRecorder()
		srv.createHealthRecordAllergy(rec, r, auth.Claims{Role: role, Subject: subject})
		return rec
	}
	list := func(subject, role, requested string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(http.MethodGet, "/v1/health-record/allergies?patient_id="+requested, nil)
		rec := httptest.NewRecorder()
		srv.listHealthRecordAllergies(rec, r, auth.Claims{Role: role, Subject: subject})
		return rec
	}
	for range 2 {
		if got := create(patient.ID, "patient", payload); got.Code != http.StatusOK {
			t.Fatalf("create/retry HTTP %d: %s", got.Code, got.Body.String())
		}
	}
	if got := create(patient.ID, "patient", strings.Replace(payload, "Mual", "Ruam", 1)); got.Code != http.StatusConflict {
		t.Fatalf("changed retry HTTP %d", got.Code)
	}
	if got := create(patient.ID, "patient", strings.Replace(payload, "mild", "unknown", 1)); got.Code != http.StatusBadRequest {
		t.Fatalf("invalid severity HTTP %d", got.Code)
	}
	if got := create(professional.ID, "professional", payload); got.Code != http.StatusForbidden {
		t.Fatalf("professional create HTTP %d", got.Code)
	}
	if got := list(other.ID, "patient", patient.ID); got.Code != http.StatusForbidden {
		t.Fatalf("other patient HTTP %d", got.Code)
	}
	if got := list(professional.ID, "professional", patient.ID); got.Code != http.StatusForbidden {
		t.Fatalf("unlinked professional HTTP %d", got.Code)
	}
	assertOne := func(got *httptest.ResponseRecorder) {
		t.Helper()
		var data struct {
			Items []struct {
				Substance  string `json:"substance"`
				ReportedBy string `json:"reported_by"`
			} `json:"items"`
		}
		if got.Code != http.StatusOK || json.Unmarshal(got.Body.Bytes(), &data) != nil || len(data.Items) != 1 ||
			data.Items[0].Substance != "Obat uji" || data.Items[0].ReportedBy != "patient" {
			t.Fatalf("unexpected allergy list HTTP %d: %s", got.Code, got.Body.String())
		}
	}
	assertOne(list(patient.ID, "patient", ""))
	if err := st.EnsurePatientProfessionalLink(ctx, patient.ID, professional.ID); err != nil {
		t.Fatal(err)
	}
	sessionID := insertManualLinkSession(t, db, patient.ID, professional.ID, "chat", "scheduled", "")
	if _, err := db.ExecContext(ctx, `UPDATE care_sessions SET scheduled_at=$2 WHERE id=$1`, sessionID, clock.Now().Add(-5*time.Minute)); err != nil {
		t.Fatal(err)
	}
	if got := list(professional.ID, "professional", patient.ID); got.Code != http.StatusForbidden {
		t.Fatalf("without consent HTTP %d", got.Code)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO patient_data_consents(patient_id,professional_id,share_health_record)
		VALUES($1,$2,true) ON CONFLICT(patient_id,professional_id) DO UPDATE SET share_health_record=true`, patient.ID, professional.ID); err != nil {
		t.Fatal(err)
	}
	assertOne(list(professional.ID, "professional", patient.ID))
	if _, err := db.ExecContext(ctx, `UPDATE patient_data_consents SET share_health_record=false WHERE patient_id=$1 AND professional_id=$2`, patient.ID, professional.ID); err != nil {
		t.Fatal(err)
	}
	if got := list(professional.ID, "professional", patient.ID); got.Code != http.StatusForbidden {
		t.Fatalf("revoked consent HTTP %d", got.Code)
	}
}
