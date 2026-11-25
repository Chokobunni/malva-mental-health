package store

import "testing"

func TestCareAttendanceOutcomeAndQuota(t *testing.T) {
	s, db, ctx := attendedTestStore(t)
	patient := insertTestUser(t, db, ctx, "patient", "Attendance outcome", "outcomep")
	professional := insertTestUser(t, db, ctx, "professional", "Attendance outcome", "outcomed")
	t.Cleanup(func() {
		_, _ = db.Exec("DELETE FROM care_sessions WHERE patient_id=$1", patient)
		_, _ = db.Exec("DELETE FROM care_packages WHERE patient_id=$1", patient)
		cleanupTestUsers(t, db, patient, professional)
	})

	for _, tc := range []struct {
		name, patient, professional, status, resultPatient, resultProfessional string
		remaining                                                              int
	}{
		{"both attend", "attended", "attended", "completed", "attended", "attended", 0},
		{"only patient attends", "attended", "", "no_show", "attended", "absent", 1},
		{"only professional attends", "", "attended", "no_show", "absent", "attended", 0},
		{"neither attends", "", "", "no_show", "absent", "absent", 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var packageID, sessionID string
			if err := db.QueryRowContext(ctx, `INSERT INTO care_packages
				(patient_id, professional_id, status, total_sessions, price, expires_at)
				VALUES($1,$2,'active',1,100000,now()+interval '7 days') RETURNING id`,
				patient, professional).Scan(&packageID); err != nil {
				t.Fatal(err)
			}
			if err := db.QueryRowContext(ctx, `INSERT INTO care_sessions
				(package_id, patient_id, professional_id, status, scheduled_at, duration_minutes, patient_attendance, professional_attendance)
				VALUES($1,$2,$3,'scheduled',now()-interval '2 hours',60,$4,$5) RETURNING id`,
				packageID, patient, professional, tc.patient, tc.professional).Scan(&sessionID); err != nil {
				t.Fatal(err)
			}
			if _, err := s.finalizeEndedCareSessions(ctx, " AND id=$2", sessionID); err != nil {
				t.Fatal(err)
			}
			if _, err := s.finalizeEndedCareSessions(ctx, " AND id=$2", sessionID); err != nil {
				t.Fatalf("retry finalization: %v", err)
			}
			session, err := s.GetCareSession(ctx, sessionID)
			if err != nil || session.Status != tc.status || session.PatientAttendance != tc.resultPatient || session.ProfessionalAttendance != tc.resultProfessional {
				t.Fatalf("unexpected terminal attendance: %+v, %v", session, err)
			}
			pkg, err := s.GetCarePackage(ctx, packageID)
			if err != nil || pkg.Remaining != tc.remaining {
				t.Fatalf("unexpected remaining quota: %+v, %v", pkg, err)
			}
		})
	}
}
