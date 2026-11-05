package server

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
	"malva/backend/internal/store"
)

func TestSessionLifecycleContract(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	professional := createIdentityTestUser(t, db, st, "professional", nil)
	t.Cleanup(func() {
		_, _ = db.ExecContext(context.Background(), `DELETE FROM care_sessions WHERE patient_id=$1`, patient.ID)
	})
	srv := newOnboardingTestServer(db)
	id := insertManualLinkSession(t, db, patient.ID, professional.ID, "video", "scheduled", "https://meet.google.com/abc-defg-hij")
	_, err := db.ExecContext(context.Background(), `UPDATE care_sessions SET scheduled_at=$2, private_note='confidential' WHERE id=$1`, id, clock.Now().Add(-5*time.Minute))
	if err != nil {
		t.Fatal(err)
	}
	patch := func(role, actor, body string) *httptest.ResponseRecorder {
		r := httptest.NewRequest(http.MethodPatch, "/v1/care-sessions/"+id, strings.NewReader(body))
		r.SetPathValue("session_id", id)
		w := httptest.NewRecorder()
		srv.updateCareSession(w, r, auth.Claims{Role: role, Subject: actor})
		return w
	}
	t.Run("patient attendance is independent", func(t *testing.T) {
		w := patch("patient", patient.ID, `{"status":"attended"}`)
		if w.Code != 200 {
			t.Fatalf("patient attendance: %d %s", w.Code, w.Body.String())
		}
		var body map[string]map[string]any
		if err := json.Unmarshal(w.Body.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		s := body["session"]
		if s["patient_attendance"] != "attended" || s["professional_attendance"] == "attended" || s["status"] != "scheduled" {
			t.Fatalf("independent attendance: %v", s)
		}
		if _, ok := s["private_note"]; ok {
			t.Fatal("private note leaked to patient")
		}
	})
	t.Run("completion before scheduled end is rejected", func(t *testing.T) {
		w := patch("professional", professional.ID, `{"status":"completed"}`)
		if w.Code != http.StatusBadRequest {
			t.Fatalf("early completion: %d %s", w.Code, w.Body.String())
		}
	})
	t.Run("summary patch preserves omitted fields", func(t *testing.T) {
		w := patch("professional", professional.ID, `{"summary_for_patient":"summary"}`)
		if w.Code != 200 {
			t.Fatalf("summary: %d %s", w.Code, w.Body.String())
		}
		s, err := st.GetCareSession(context.Background(), id)
		if err != nil {
			t.Fatal(err)
		}
		if s.PrivateNote != "confidential" || s.MeetingURL != "https://meet.google.com/abc-defg-hij" {
			t.Fatalf("summary cleared unrelated fields: %+v", s)
		}
	})
	t.Run("patient list hides private notes", func(t *testing.T) {
		_, _ = db.ExecContext(context.Background(), `UPDATE care_sessions SET private_note='confidential' WHERE id=$1`, id)
		r := httptest.NewRequest(http.MethodGet, "/v1/care-sessions?scope=all", nil)
		w := httptest.NewRecorder()
		srv.listCareSessions(w, r, auth.Claims{Role: "patient", Subject: patient.ID})
		if w.Code != 200 || strings.Contains(w.Body.String(), "private_note") {
			t.Fatalf("patient list: %d %s", w.Code, w.Body.String())
		}
	})
	t.Run("completed session is terminal for chat", func(t *testing.T) {
		_, err := db.ExecContext(context.Background(), `UPDATE care_sessions SET status='completed',scheduled_at=$2 WHERE id=$1`, id, clock.Now().Add(-5*time.Minute))
		if err != nil {
			t.Fatal(err)
		}
		access, err := st.ChatAccessFor(context.Background(), patient.ID, professional.ID, "patient")
		if err != nil {
			t.Fatal(err)
		}
		if access.CanSendText || access.InSession {
			t.Fatalf("completed session still live: %+v", access)
		}
		w := patch("professional", professional.ID, `{"status":"no_show"}`)
		if w.Code < 400 {
			t.Fatalf("terminal completed overwritten: %d %s", w.Code, w.Body.String())
		}
	})
}

func TestManualCompletionAfterEndAndReplay(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	professional := createIdentityTestUser(t, db, st, "professional", nil)
	id := insertManualLinkSession(t, db, patient.ID, professional.ID, "chat", "scheduled", "")
	t.Cleanup(func() { _, _ = db.ExecContext(context.Background(), `DELETE FROM care_sessions WHERE id=$1`, id) })
	if _, err := db.ExecContext(context.Background(), `UPDATE care_sessions SET scheduled_at=$2 WHERE id=$1`, id, clock.Now().Add(-time.Hour)); err != nil {
		t.Fatal(err)
	}
	srv := newOnboardingTestServer(db)
	for range 2 {
		r := httptest.NewRequest(http.MethodPatch, "/v1/care-sessions/"+id, strings.NewReader(`{"status":"completed"}`))
		r.SetPathValue("session_id", id)
		w := httptest.NewRecorder()
		srv.updateCareSession(w, r, auth.Claims{Role: "professional", Subject: professional.ID})
		if w.Code != 200 {
			t.Fatalf("completion after end: %d %s", w.Code, w.Body.String())
		}
	}
	session, err := st.GetCareSession(context.Background(), id)
	if err != nil {
		t.Fatal(err)
	}
	if session.Status != "completed" || session.PatientAttendance != "" || session.ProfessionalAttendance != "" {
		t.Fatalf("completion fabricated attendance: %+v", session)
	}
}

func TestChatAccessChoosesActiveSessionBeforeEndedOrFuture(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	professional := createIdentityTestUser(t, db, st, "professional", nil)
	t.Cleanup(func() {
		_, _ = db.ExecContext(context.Background(), `DELETE FROM care_sessions WHERE patient_id=$1`, patient.ID)
	})
	active := ""
	for _, tc := range []struct {
		offset   time.Duration
		duration int
	}{{-time.Hour, 120}, {-15 * time.Minute, 10}, {20 * time.Minute, 30}} {
		id := insertManualLinkSession(t, db, patient.ID, professional.ID, "chat", "scheduled", "")
		if active == "" {
			active = id
		}
		if _, err := db.ExecContext(context.Background(), `UPDATE care_sessions SET scheduled_at=$2,duration_minutes=$3 WHERE id=$1`, id, clock.Now().Add(tc.offset), tc.duration); err != nil {
			t.Fatal(err)
		}
	}
	access, err := st.ChatAccessFor(context.Background(), patient.ID, professional.ID, "professional")
	if err != nil {
		t.Fatal(err)
	}
	if !access.InSession || access.SessionID != active || access.SessionEndsAt == nil {
		t.Fatalf("active session hidden: %+v", access)
	}
}

func TestSessionCompletionAndAbsenceSerialize(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	professional := createIdentityTestUser(t, db, st, "professional", nil)
	id := insertManualLinkSession(t, db, patient.ID, professional.ID, "chat", "scheduled", "")
	t.Cleanup(func() { _, _ = db.ExecContext(context.Background(), `DELETE FROM care_sessions WHERE id=$1`, id) })
	if _, err := db.ExecContext(context.Background(), `UPDATE care_sessions SET scheduled_at=$2 WHERE id=$1`, id, clock.Now().Add(-time.Hour)); err != nil {
		t.Fatal(err)
	}
	start := make(chan struct{})
	results := make(chan error, 2)
	go func() {
		<-start
		_, err := st.UpdateCareSessionStatus(context.Background(), id, "completed", "", professional.ID)
		results <- err
	}()
	go func() {
		<-start
		_, err := st.MarkCareSessionAttendance(context.Background(), id, "patient", patient.ID, "absent")
		results <- err
	}()
	close(start)
	accepted, rejected := 0, 0
	for range 2 {
		err := <-results
		if err == nil {
			accepted++
		} else if errors.Is(err, store.ErrCareSessionTerminal) {
			rejected++
		} else {
			t.Fatalf("unexpected concurrent transition error: %v", err)
		}
	}
	if accepted != 1 || rejected != 1 {
		t.Fatalf("accepted=%d rejected=%d; exactly one terminal transition must win", accepted, rejected)
	}
	session, err := st.GetCareSession(context.Background(), id)
	if err != nil {
		t.Fatal(err)
	}
	if session.Status != "completed" && session.Status != "no_show" {
		t.Fatalf("concurrent terminal updates left status %q", session.Status)
	}
	if session.Status == "completed" && session.PatientAttendance != "" {
		t.Fatal("losing absence changed a completed session")
	}
	if session.Status == "no_show" && session.PatientAttendance != "absent" {
		t.Fatal("winning absence did not preserve participant attendance")
	}
}
