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
	"malva/backend/internal/store"
)

func TestSelfAttendanceOutcomes(t *testing.T) {
	for _, role := range []string{"patient", "professional"} {
		t.Run(role, func(t *testing.T) {
			db, st := openOnboardingTestStore(t)
			patient := createIdentityTestUser(t, db, st, "patient", nil)
			professional := createIdentityTestUser(t, db, st, "professional", nil)
			pkg, err := st.CreateCarePackage(context.Background(), store.CarePackage{PatientID: patient.ID, ProfessionalID: professional.ID, Status: "active", Price: 400000})
			if err != nil {
				t.Fatal(err)
			}
			id := insertManualLinkSession(t, db, patient.ID, professional.ID, "chat", "scheduled", "")
			t.Cleanup(func() {
				_, _ = db.ExecContext(context.Background(), `DELETE FROM care_refunds WHERE session_id=$1`, id)
				_, _ = db.ExecContext(context.Background(), `DELETE FROM care_sessions WHERE id=$1`, id)
				_, _ = db.ExecContext(context.Background(), `DELETE FROM care_packages WHERE id=$1`, pkg.ID)
			})
			if _, err := db.ExecContext(context.Background(), `UPDATE care_sessions SET package_id=$2,scheduled_at=$3 WHERE id=$1`, id, pkg.ID, clock.Now().Add(-5*time.Minute)); err != nil {
				t.Fatal(err)
			}
			if role == "professional" {
				// Legacy sweepers could complete a package while its last session
				// was still scheduled. Returned quota must make it usable again.
				if _, err := db.ExecContext(context.Background(), `UPDATE care_packages SET status='completed',expires_at=$2 WHERE id=$1`, pkg.ID, clock.Now().Add(24*time.Hour)); err != nil {
					t.Fatal(err)
				}
			}
			actor := patient.ID
			if role == "professional" {
				actor = professional.ID
			}
			srv := newOnboardingTestServer(db)
			for range 2 {
				r := httptest.NewRequest(http.MethodPatch, "/v1/care-sessions/"+id, strings.NewReader(`{"status":"absent"}`))
				r.SetPathValue("session_id", id)
				w := httptest.NewRecorder()
				srv.updateCareSession(w, r, auth.Claims{Role: role, Subject: actor})
				if w.Code != 200 {
					t.Fatalf("absence: %d %s", w.Code, w.Body.String())
				}
			}
			session, err := st.GetCareSession(context.Background(), id)
			if err != nil {
				t.Fatal(err)
			}
			pkg, err = st.GetCarePackage(context.Background(), pkg.ID)
			if err != nil {
				t.Fatal(err)
			}
			var credits, earnings int
			if err := db.QueryRowContext(context.Background(), `SELECT count(*) FROM care_refunds WHERE session_id=$1 AND kind='credit'`, id).Scan(&credits); err != nil {
				t.Fatal(err)
			}
			if err := db.QueryRowContext(context.Background(), `SELECT count(*) FROM earnings WHERE session_id=$1`, id).Scan(&earnings); err != nil {
				t.Fatal(err)
			}
			if earnings != 0 {
				t.Fatal("absence recognized earnings")
			}
			if role == "patient" {
				if session.Status != "no_show" || session.PatientAttendance != "absent" || session.ProfessionalAttendance != "" || pkg.UsedSessions != 1 || credits != 0 {
					t.Fatalf("patient absence: session=%+v package=%+v credits=%d", session, pkg, credits)
				}
			} else {
				if session.Status != "cancelled_by_professional" || session.ProfessionalAttendance != "absent" || session.PatientAttendance != "" || pkg.Status != "active" || pkg.UsedSessions != 0 || credits != 1 {
					t.Fatalf("professional absence: session=%+v package=%+v credits=%d", session, pkg, credits)
				}
			}
			if _, err := st.UpdateCareSessionStatus(context.Background(), id, "completed", "", professional.ID); err == nil {
				t.Fatal("terminal absence reopened as completed")
			}
		})
	}
}
