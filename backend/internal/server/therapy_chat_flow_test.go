package server

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"malva/backend/internal/auth"
	"malva/backend/internal/store"
)

func TestTherapyChatShareAndAuthorizedRead(t *testing.T) {
	f := newTherapyConsentFixture(t)
	t.Cleanup(func() {
		if _, err := f.db.Exec(`DELETE FROM chat_messages WHERE patient_id=$1`, f.patient.ID); err != nil {
			t.Errorf("cleanup synthetic messages: %v", err)
		}
	})
	_, private := f.seedSubmissions(t)
	pkg, err := f.st.CreateCarePackage(context.Background(), store.CarePackage{
		PatientID: f.patient.ID, ProfessionalID: f.prof.ID, Price: 400000,
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := f.st.UpdateCarePackageStatus(context.Background(), pkg.ID, "active"); err != nil {
		t.Fatal(err)
	}

	body, _ := json.Marshal(map[string]string{"professional_id": f.prof.ID})
	req := httptest.NewRequest(http.MethodPost, "/v1/therapy-submissions/"+private.ID+"/share", bytes.NewReader(body))
	req.SetPathValue("submission_id", private.ID)
	rec := httptest.NewRecorder()
	f.srv.shareTherapySubmission(rec, req, auth.Claims{Subject: f.patient.ID, Role: "patient"})
	if rec.Code != http.StatusOK {
		t.Fatalf("share status %d: %s", rec.Code, rec.Body.String())
	}
	var payload struct {
		ChatMessageID string `json:"chat_message_id"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatal(err)
	}
	if payload.ChatMessageID == "" {
		t.Fatal("share must persist a visible chat message")
	}
	var kind, submissionID string
	if err := f.db.QueryRow(`SELECT kind, attachment_meta->>'submission_id' FROM chat_messages WHERE id=$1`, payload.ChatMessageID).Scan(&kind, &submissionID); err != nil {
		t.Fatal(err)
	}
	if kind != "worksheet" || submissionID != private.ID {
		t.Fatalf("wrong chat reference %s %s", kind, submissionID)
	}

	for _, tc := range []struct {
		name, userID, role string
		want               int
	}{
		{"recipient", f.prof.ID, "professional", http.StatusOK},
		{"other patient", f.other.ID, "patient", http.StatusNotFound},
	} {
		t.Run(tc.name, func(t *testing.T) {
			get := httptest.NewRequest(http.MethodGet, "/v1/therapy-submissions/"+private.ID, nil)
			get.SetPathValue("submission_id", private.ID)
			out := httptest.NewRecorder()
			f.srv.getTherapySubmission(out, get, auth.Claims{Subject: tc.userID, Role: tc.role})
			if out.Code != tc.want {
				t.Fatalf("read status %d want %d: %s", out.Code, tc.want, out.Body.String())
			}
		})
	}
}

func TestTherapyChatShareRequiresActivePackageAndOwnership(t *testing.T) {
	f := newTherapyConsentFixture(t)
	_, private := f.seedSubmissions(t)
	for _, patientID := range []string{f.patient.ID, f.other.ID} {
		body, _ := json.Marshal(map[string]string{"professional_id": f.prof.ID})
		req := httptest.NewRequest(http.MethodPost, "/v1/therapy-submissions/"+private.ID+"/share", bytes.NewReader(body))
		req.SetPathValue("submission_id", private.ID)
		rec := httptest.NewRecorder()
		f.srv.shareTherapySubmission(rec, req, auth.Claims{Subject: patientID, Role: "patient"})
		if rec.Code != http.StatusForbidden {
			t.Fatalf("status %d want forbidden: %s", rec.Code, rec.Body.String())
		}
	}
}
