package server

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
)

func TestProfessionalAttendanceContract(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	professional := createIdentityTestUser(t, db, st, "professional", nil)
	other := createIdentityTestUser(t, db, st, "professional", nil)
	t.Cleanup(func() {
		_, _ = db.ExecContext(context.Background(), `DELETE FROM care_sessions WHERE patient_id=$1`, patient.ID)
	})
	srv := newOnboardingTestServer(db)
	sessionID := insertManualLinkSession(t, db, patient.ID, professional.ID, "video", "scheduled", "https://meet.google.com/abc-defg-hij")
	if _, err := db.ExecContext(context.Background(), `UPDATE care_sessions SET scheduled_at=$2 WHERE id=$1`, sessionID, clock.Now().Add(-5*time.Minute)); err != nil {
		t.Fatal(err)
	}
	mark := func(role, userID string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodPatch, "/v1/care-sessions/"+sessionID, strings.NewReader(`{"status":"attended"}`))
		req.SetPathValue("session_id", sessionID)
		rec := httptest.NewRecorder()
		srv.updateCareSession(rec, req, auth.Claims{Role: role, Subject: userID})
		return rec
	}
	if rec := mark("patient", patient.ID); rec.Code != http.StatusOK {
		t.Fatalf("patient attendance: status=%d body=%s", rec.Code, rec.Body.String())
	}
	if rec := mark("professional", other.ID); rec.Code != http.StatusForbidden {
		t.Fatalf("other professional attendance: status=%d body=%s", rec.Code, rec.Body.String())
	}
	for range 2 {
		if rec := mark("professional", professional.ID); rec.Code != http.StatusOK {
			t.Fatalf("owner attendance: status=%d body=%s", rec.Code, rec.Body.String())
		}
	}
	session, err := st.GetCareSession(context.Background(), sessionID)
	if err != nil {
		t.Fatal(err)
	}
	if session.Status != "scheduled" || session.AttendedMarkedAt == nil {
		t.Fatalf("attendance must preserve live scheduled session: %+v", session)
	}
	var earnings int
	if err := db.QueryRowContext(context.Background(), `SELECT count(*) FROM earnings WHERE session_id=$1`, sessionID).Scan(&earnings); err != nil {
		t.Fatal(err)
	}
	if earnings != 0 {
		t.Fatalf("attendance recognized earnings before completion: %d", earnings)
	}
}
