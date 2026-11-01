package server

import (
	"bytes"
	"context"
	"database/sql"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"malva/backend/internal/auth"
)

// ============================================================
// PUT /v1/care-sessions/{session_id}/meet-link — fallback link manual.
//
// QA menambahkan test level handler ini untuk mengunci OTORISASI & VALIDASI
// yang tidak dicakup TestNormalizeManualMeetURL (yang hanya menguji helper
// URL). Butuh Postgres: di-skip bila MALVA_TEST_DATABASE_URL kosong.
// ============================================================

// insertManualLinkSession menyisipkan care_session langsung (melewati aturan
// "jadwal harus di masa depan" milik CreateCareSession) agar test bisa membuat
// sesi non-video / non-scheduled. Didaftarkan cleanup via patient_id.
func insertManualLinkSession(t *testing.T, db *sql.DB, patientID, profID, sessionType, status, meetingURL string) string {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	var id string
	err := db.QueryRowContext(ctx, `
		INSERT INTO care_sessions
			(patient_id, professional_id, session_type, scheduled_at, duration_minutes,
			 status, meeting_url)
		VALUES ($1,$2,$3,$4,30,$5,$6)
		RETURNING id::text`,
		patientID, profID, sessionType, time.Now().Add(2*time.Hour), status, meetingURL,
	).Scan(&id)
	if err != nil {
		t.Fatalf("insert care_session: %v", err)
	}
	return id
}

func callSetManualMeetLink(srv *Server, sessionID, role, subject, body string) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPut, "/v1/care-sessions/"+sessionID+"/meet-link",
		bytes.NewReader([]byte(body)))
	req.SetPathValue("session_id", sessionID)
	srv.setManualMeetLinkHandler(rec, req, auth.Claims{Subject: subject, Role: role})
	return rec
}

func TestSetManualMeetLinkHandler(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	patient := createIdentityTestUser(t, db, st, "patient", nil)
	owner := createIdentityTestUser(t, db, st, "professional", nil)
	other := createIdentityTestUser(t, db, st, "professional", nil)
	t.Cleanup(func() {
		_, _ = db.ExecContext(context.Background(),
			`DELETE FROM care_sessions WHERE patient_id = $1`, patient.ID)
	})

	srv := newOnboardingTestServer(db)

	validBody := `{"meet_url":"https://meet.google.com/abc-defg-hij"}`
	badURLBody := `{"meet_url":"https://zoom.us/j/123"}`

	t.Run("tolak pasien (403)", func(t *testing.T) {
		sess := insertManualLinkSession(t, db, patient.ID, owner.ID, "video", "scheduled", "")
		rec := callSetManualMeetLink(srv, sess, "patient", patient.ID, validBody)
		if rec.Code != http.StatusForbidden {
			t.Fatalf("status = %d, mau 403 (body: %s)", rec.Code, rec.Body.String())
		}
	})

	t.Run("tolak profesional lain bukan pemilik sesi (403)", func(t *testing.T) {
		sess := insertManualLinkSession(t, db, patient.ID, owner.ID, "video", "scheduled", "")
		rec := callSetManualMeetLink(srv, sess, "professional", other.ID, validBody)
		if rec.Code != http.StatusForbidden {
			t.Fatalf("status = %d, mau 403 (body: %s)", rec.Code, rec.Body.String())
		}
	})

	t.Run("tolak sesi non-video (400)", func(t *testing.T) {
		sess := insertManualLinkSession(t, db, patient.ID, owner.ID, "chat", "scheduled", "")
		rec := callSetManualMeetLink(srv, sess, "professional", owner.ID, validBody)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("status = %d, mau 400 (body: %s)", rec.Code, rec.Body.String())
		}
	})

	t.Run("tolak status bukan scheduled (400)", func(t *testing.T) {
		sess := insertManualLinkSession(t, db, patient.ID, owner.ID, "video", "completed", "")
		rec := callSetManualMeetLink(srv, sess, "professional", owner.ID, validBody)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("status = %d, mau 400 (body: %s)", rec.Code, rec.Body.String())
		}
	})

	t.Run("tolak URL bukan meet.google.com (400)", func(t *testing.T) {
		sess := insertManualLinkSession(t, db, patient.ID, owner.ID, "video", "scheduled", "")
		rec := callSetManualMeetLink(srv, sess, "professional", owner.ID, badURLBody)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("status = %d, mau 400 (body: %s)", rec.Code, rec.Body.String())
		}
	})

	t.Run("terima URL valid & simpan (200)", func(t *testing.T) {
		sess := insertManualLinkSession(t, db, patient.ID, owner.ID, "video", "scheduled", "")
		rec := callSetManualMeetLink(srv, sess, "professional", owner.ID, validBody)
		if rec.Code != http.StatusOK {
			t.Fatalf("status = %d, mau 200 (body: %s)", rec.Code, rec.Body.String())
		}
		updated, err := st.GetCareSession(ctx, sess)
		if err != nil {
			t.Fatalf("GetCareSession: %v", err)
		}
		if updated.MeetingURL != "https://meet.google.com/abc-defg-hij" {
			t.Fatalf("meeting_url = %q, mau URL valid", updated.MeetingURL)
		}
	})

	t.Run("sesi tidak ditemukan (404)", func(t *testing.T) {
		rec := callSetManualMeetLink(srv, "00000000-0000-0000-0000-000000000000",
			"professional", owner.ID, validBody)
		if rec.Code != http.StatusNotFound {
			t.Fatalf("status = %d, mau 404 (body: %s)", rec.Code, rec.Body.String())
		}
	})
}
