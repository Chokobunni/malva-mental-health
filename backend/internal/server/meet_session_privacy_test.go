package server

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"malva/backend/internal/auth"
)

func TestMeetLinkResponsesKeepProfessionalNotePrivate(t *testing.T) {
	for _, existing := range []bool{true, false} {
		name := "created_link"
		if existing {
			name = "existing_link"
		}
		t.Run(name, func(t *testing.T) {
			db, st := openOnboardingTestStore(t)
			patient := createIdentityTestUser(t, db, st, "patient", nil)
			professional := createIdentityTestUser(t, db, st, "professional", nil)
			linkReadyProfessional(t, st, professional.ID)
			link := ""
			if existing {
				link = "https://meet.google.com/abc-defg-hij"
			}
			id := insertManualLinkSession(t, db, patient.ID, professional.ID, "video", "scheduled", link)
			t.Cleanup(func() { _, _ = db.ExecContext(context.Background(), `DELETE FROM care_sessions WHERE id=$1`, id) })
			if _, err := db.ExecContext(context.Background(), `UPDATE care_sessions SET private_note='confidential',summary_for_patient='shared summary' WHERE id=$1`, id); err != nil {
				t.Fatal(err)
			}
			srv := newOnboardingTestServer(db)
			srv.calendar = &fakeMeetCalendar{createEventID: "privacy-event", createMeetURL: "https://meet.google.com/abc-defg-hij"}
			for _, claims := range []auth.Claims{{Role: "patient", Subject: patient.ID}, {Role: "professional", Subject: professional.ID}} {
				r := httptest.NewRequest(http.MethodPost, "/v1/care-sessions/"+id+"/meet-link", nil)
				r.SetPathValue("session_id", id)
				w := httptest.NewRecorder()
				srv.ensureMeetLinkHandler(w, r, claims)
				if w.Code != http.StatusOK && w.Code != http.StatusCreated {
					t.Fatalf("%s meet link: %d %s", claims.Role, w.Code, w.Body.String())
				}
				var body struct {
					Session map[string]any `json:"session"`
				}
				if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
					t.Fatal(err)
				}
				if body.Session["summary_for_patient"] != "shared summary" || body.Session["meeting_url"] != "https://meet.google.com/abc-defg-hij" {
					t.Errorf("%s lost shared session data: %v", claims.Role, body.Session)
				}
				if claims.Role == "patient" {
					if _, leaked := body.Session["private_note"]; leaked {
						t.Error("patient Meet response leaked private_note")
					}
				} else if body.Session["private_note"] != "confidential" {
					t.Error("professional lost own private note")
				}
			}
		})
	}
}
