package server

import (
	"context"
	"net/http"
	"testing"
	"time"

	"malva/backend/internal/clock"
)

func TestDiagnosisWriteRequiresConsentAndActiveCare(t *testing.T) {
	for _, tc := range []struct {
		name          string
		sessionOffset time.Duration
		video         bool
		packageStatus string
		totalSessions int
		packageStart  time.Duration
		packageEnd    time.Duration
		usePackage    bool
		reassign      bool
		unlinked      bool
		consentOff    bool
		unverified    bool
		patientCaller bool
		allowed       bool
	}{
		{name: "one time before, while chat is open", sessionOffset: 5 * time.Minute},
		{name: "one time in actual window", sessionOffset: -time.Minute, allowed: true},
		{name: "one time video in actual window", sessionOffset: -time.Minute, video: true, allowed: true},
		{name: "one time at or after end", sessionOffset: -30 * time.Minute},
		{name: "unused active package", sessionOffset: time.Hour, packageStatus: "active", totalSessions: 4, packageEnd: time.Hour, allowed: true},
		{name: "active package between sessions", sessionOffset: -time.Hour, packageStatus: "active", totalSessions: 4, packageEnd: time.Hour, usePackage: true, allowed: true},
		{name: "active package has not started", sessionOffset: time.Hour, packageStatus: "active", totalSessions: 4, packageStart: time.Minute, packageEnd: time.Hour},
		{name: "active package has expired", sessionOffset: time.Hour, packageStatus: "active", totalSessions: 4, packageEnd: -time.Minute},
		{name: "expired package with a scheduled package session", sessionOffset: -time.Minute, packageStatus: "expired", totalSessions: 4, packageEnd: -time.Minute, usePackage: true},
		{name: "pending payment package", sessionOffset: time.Hour, packageStatus: "pending_payment", totalSessions: 4, packageEnd: time.Hour},
		{name: "one session package outside its session", sessionOffset: time.Hour, packageStatus: "active", totalSessions: 1, packageEnd: time.Hour},
		{name: "package reassigned to another professional", sessionOffset: time.Hour, packageStatus: "active", totalSessions: 4, packageEnd: time.Hour, reassign: true},
		{name: "active package without active link", sessionOffset: time.Hour, packageStatus: "active", totalSessions: 4, packageEnd: time.Hour, unlinked: true},
		{name: "active package with consent revoked", sessionOffset: time.Hour, packageStatus: "active", totalSessions: 4, packageEnd: time.Hour, consentOff: true},
		{name: "active package and unverified professional", sessionOffset: time.Hour, packageStatus: "active", totalSessions: 4, packageEnd: time.Hour, unverified: true},
		{name: "patient has read-only access", sessionOffset: -time.Minute, patientCaller: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := newClinicalFixture(t)
			ctx := context.Background()
			now := clock.Now()
			exec := func(query string, args ...any) {
				t.Helper()
				if _, err := f.db.ExecContext(ctx, query, args...); err != nil {
					t.Fatal(err)
				}
			}
			exec(`UPDATE care_sessions SET scheduled_at=$2 WHERE id=$1`, f.sessionID, now.Add(tc.sessionOffset))
			if tc.video {
				exec(`UPDATE care_sessions SET session_type='video' WHERE id=$1`, f.sessionID)
			}
			if tc.packageStatus != "" {
				professionalID := f.prof.ID
				if tc.reassign {
					professionalID = createIdentityTestUser(t, f.db, f.st, "professional", nil).ID
				}
				var packageID string
				err := f.db.QueryRowContext(ctx, `INSERT INTO care_packages
					(patient_id,professional_id,total_sessions,status,starts_at,expires_at)
					VALUES ($1,$2,$3,$4,$5,$6) RETURNING id`,
					f.patient.ID, professionalID, tc.totalSessions, tc.packageStatus, now.Add(tc.packageStart-time.Second), now.Add(tc.packageEnd)).Scan(&packageID)
				if err != nil {
					t.Fatal(err)
				}
				t.Cleanup(func() { exec(`DELETE FROM care_packages WHERE id=$1`, packageID) })
				if tc.usePackage {
					exec(`UPDATE care_sessions SET package_id=$2 WHERE id=$1`, f.sessionID, packageID)
				}
			}
			if tc.unlinked {
				exec(`UPDATE patient_professional_links SET status='inactive' WHERE patient_id=$1 AND professional_id=$2`, f.patient.ID, f.prof.ID)
			}
			if tc.consentOff {
				exec(`UPDATE patient_data_consents SET share_health_record=false WHERE patient_id=$1 AND professional_id=$2`, f.patient.ID, f.prof.ID)
			}
			if tc.unverified {
				exec(`UPDATE professional_credentials SET verification_status='PENDING' WHERE user_id=$1`, f.prof.ID)
			}
			role, subject := "professional", f.prof.ID
			if tc.patientCaller {
				role, subject = "patient", f.patient.ID
			}
			save := func(summary string, status int) {
				t.Helper()
				out := f.call(t, http.MethodPut, "/v1/health-record", role, subject,
					map[string]string{"patient_id": f.patient.ID, "diagnosis_summary": summary})
				if out.Code != status {
					t.Fatalf("PUT diagnosis got %d, want %d: %s", out.Code, status, out.Body)
				}
			}
			want := ""
			if tc.allowed {
				save("Diagnosis created", http.StatusOK)
				want = "F41.1 - Generalized anxiety disorder\nF43.1 - Post-traumatic stress disorder"
				save(want, http.StatusOK)
			} else {
				want = "Existing diagnosis"
				exec(`UPDATE patient_profiles SET diagnosis_summary=$2 WHERE user_id=$1`, f.patient.ID, want)
				save("Unexpected diagnosis", http.StatusForbidden)
			}
			record, err := f.st.GetHealthRecord(ctx, f.patient.ID)
			if err != nil || record.DiagnosisSummary != want {
				t.Fatalf("diagnosis persisted incorrectly: %v", err)
			}
		})
	}
}
