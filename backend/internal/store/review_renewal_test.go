package store

import (
	"errors"
	"testing"
	"time"

	"malva/backend/internal/clock"
)

func TestReviewRenewalWaitsForEarlierAttendanceAndCreditReplacement(t *testing.T) {
	s, db, ctx := attendedTestStore(t)
	patient, professional := mustUUID(t, db, ctx), mustUUID(t, db, ctx)
	for _, row := range []struct{ id, role string }{{patient, "patient"}, {professional, "professional"}} {
		if _, err := db.ExecContext(ctx, `INSERT INTO users(id,email,password_hash,role,display_name) VALUES($1,$2,'test',$3,'Uji')`, row.id, row.id+"@review-range.test", row.role); err != nil {
			t.Fatal(err)
		}
	}
	t.Cleanup(func() {
		if _, err := db.ExecContext(ctx, `DELETE FROM care_sessions WHERE patient_id=$1`, patient); err != nil {
			t.Errorf("cleanup care sessions: %v", err)
		}
		if _, err := db.ExecContext(ctx, `DELETE FROM care_packages WHERE patient_id=$1`, patient); err != nil {
			t.Errorf("cleanup care packages: %v", err)
		}
		cleanupTestUsers(t, db, patient, professional)
	})
	var original, renewal, delayed string
	if err := db.QueryRowContext(ctx, `INSERT INTO care_packages(patient_id,professional_id,status,total_sessions,price,expires_at) VALUES($1,$2,'active',8,400000,now()+interval '30 days') RETURNING id`, patient, professional).Scan(&original); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRowContext(ctx, `INSERT INTO care_packages(patient_id,professional_id,status,total_sessions,price,expires_at,merged_into,merged_at) VALUES($1,$2,'merged',4,200000,now()+interval '30 days',$3,now()) RETURNING id`, patient, professional, original).Scan(&renewal); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions(package_id,patient_id,professional_id,scheduled_at,status) SELECT $1,$2,$3,now()-(10-i)*interval '1 hour',CASE WHEN i=1 THEN 'scheduled' ELSE 'completed' END FROM generate_series(1,8)i`, original, patient, professional); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRowContext(ctx, `SELECT id FROM care_sessions WHERE package_id=$1 AND status='scheduled'`, original).Scan(&delayed); err != nil {
		t.Fatal(err)
	}
	if items, err := s.ListReviewEntitlements(ctx, patient, professional); err != nil || len(items) != 0 {
		t.Fatalf("renewal unlocked before earlier attendance: %+v %v", items, err)
	}
	if _, err := s.CreateDoctorReviewForEntitlement(ctx, professional, patient, 5, "Terlalu awal", true, "", renewal); !errors.Is(err, ErrReviewNotEligible) {
		t.Fatalf("premature renewal POST=%v", err)
	}
	cancelled, err := s.MarkCareSessionAttendance(ctx, delayed, "professional", professional, "absent")
	if err != nil || cancelled.Status != "cancelled_by_professional" {
		t.Fatalf("delayed professional absence: %+v %v", cancelled, err)
	}
	pkg, err := s.GetCarePackage(ctx, original)
	if err != nil || pkg.Remaining != 1 || pkg.TotalSessions != 8 || pkg.Price != 400000 {
		t.Fatalf("returned credit/payment changed: %+v %v", pkg, err)
	}
	items, err := s.ListReviewEntitlements(ctx, patient, professional)
	if err != nil || len(items) != 1 || items[0].CarePackageID != original {
		t.Fatalf("only original range should be complete after credit return: %+v %v", items, err)
	}
	if _, err := s.CreateDoctorReviewForEntitlement(ctx, professional, patient, 5, "Awal selesai", true, "", original); err != nil {
		t.Fatal(err)
	}
	replacement, err := s.CreateCareSession(ctx, CareSession{PackageID: &original, PatientID: patient, ProfessionalID: professional, SessionType: "chat", ScheduledAt: clock.Now().Add(time.Hour), DurationMinutes: 30})
	if err != nil {
		t.Fatal(err)
	}
	if items, err := s.ListReviewEntitlements(ctx, patient, professional); err != nil || len(items) != 0 {
		t.Fatalf("unfinished replacement allowed renewal: %+v %v", items, err)
	}
	// Advance only the fixture schedule to exercise real terminal completion.
	if _, err := db.ExecContext(ctx, `UPDATE care_sessions SET scheduled_at=now()-interval '1 hour' WHERE id=$1`, replacement.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := s.UpdateCareSessionStatus(ctx, replacement.ID, "completed", "", professional); err != nil {
		t.Fatal(err)
	}
	items, err = s.ListReviewEntitlements(ctx, patient, professional)
	if err != nil || len(items) != 1 || items[0].CarePackageID != renewal {
		t.Fatalf("completed replacement must unlock only renewal: %+v %v", items, err)
	}
	if _, err := s.CreateDoctorReviewForEntitlement(ctx, professional, patient, 4, "Renewal selesai", true, "", renewal); err != nil {
		t.Fatal(err)
	}
	if items, err := s.ListReviewEntitlements(ctx, patient, professional); err != nil || len(items) != 0 {
		t.Fatalf("consumed range reminted: %+v %v", items, err)
	}
	var count int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM doctor_reviews WHERE patient_id=$1`, patient).Scan(&count); err != nil || count != 2 {
		t.Fatalf("one per purchase count=%d err=%v", count, err)
	}
}

func TestReviewMergedPurchasesUnlockOwnCompletedRange(t *testing.T) {
	s, db, ctx := attendedTestStore(t)
	patient, professional, foreign := mustUUID(t, db, ctx), mustUUID(t, db, ctx), mustUUID(t, db, ctx)
	for _, row := range []struct{ id, role string }{{patient, "patient"}, {professional, "professional"}, {foreign, "patient"}} {
		if _, err := db.ExecContext(ctx, `INSERT INTO users(id,email,password_hash,role,display_name) VALUES($1,$2,'test',$3,'Uji')`, row.id, row.id+"@review-renewal.test", row.role); err != nil {
			t.Fatal(err)
		}
	}
	t.Cleanup(func() {
		if _, err := db.ExecContext(ctx, `DELETE FROM care_sessions WHERE patient_id=$1`, patient); err != nil {
			t.Errorf("cleanup care sessions: %v", err)
		}
		if _, err := db.ExecContext(ctx, `DELETE FROM care_packages WHERE professional_id=$1`, professional); err != nil {
			t.Errorf("cleanup care packages: %v", err)
		}
		cleanupTestUsers(t, db, patient, professional, foreign)
	})
	var original, booking, pending string
	if err := db.QueryRowContext(ctx, `INSERT INTO care_packages(patient_id,professional_id,status,expires_at,price) VALUES($1,$2,'active',now()+interval '30 days',200000) RETURNING id`, patient, professional).Scan(&original); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions(package_id,patient_id,professional_id,scheduled_at,status) SELECT $1,$2,$3,now()-(10-i)*interval '1 day',CASE WHEN i=4 THEN 'scheduled' ELSE 'completed' END FROM generate_series(1,4)i`, original, patient, professional); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRowContext(ctx, `INSERT INTO bookings(patient_id,professional_id,service_type,session_type,booking_date,slot_time,price,status) VALUES($1,$2,'package_session','chat',CURRENT_DATE,'12:00',200000,'paid') RETURNING id`, patient, professional).Scan(&booking); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRowContext(ctx, `INSERT INTO care_packages(patient_id,professional_id,booking_id,status,expires_at,price) VALUES($1,$2,$3,'pending_payment',now()+interval '42 days',200000) RETURNING id`, patient, professional, booking).Scan(&pending); err != nil {
		t.Fatal(err)
	}
	if _, merged, err := s.ActivatePendingPackage(ctx, patient, professional, booking); err != nil || !merged {
		t.Fatalf("precompletion merge %v %v", merged, err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions(package_id,patient_id,professional_id,scheduled_at,status) SELECT $1,$2,$3,now()-(6-i)*interval '1 day','scheduled' FROM generate_series(1,4)i`, original, patient, professional); err != nil {
		t.Fatal(err)
	}
	if items, err := s.ListReviewEntitlements(ctx, patient, professional); err != nil || len(items) != 0 {
		t.Fatalf("incomplete purchase eligible: %+v %v", items, err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE care_sessions SET status='completed' WHERE package_id=$1 AND scheduled_at<now()-interval '6 days'`, original); err != nil {
		t.Fatal(err)
	}
	items, err := s.ListReviewEntitlements(ctx, patient, professional)
	if err != nil || len(items) != 1 || items[0].CarePackageID != original {
		t.Fatalf("first four should unlock despite renewal scheduled: %+v %v", items, err)
	}
	firstEnd := items[0].CompletedAt
	if _, err := s.CreateDoctorReviewForEntitlement(ctx, professional, patient, 5, "Pertama", true, "", original); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateDoctorReviewForEntitlement(ctx, professional, patient, 5, "Terlalu awal", true, "", pending); !errors.Is(err, ErrReviewNotEligible) {
		t.Fatalf("renewal premature review=%v", err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE care_sessions SET status='completed' WHERE package_id=$1 AND status='scheduled'`, original); err != nil {
		t.Fatal(err)
	}
	items, err = s.ListReviewEntitlements(ctx, patient, professional)
	if err != nil || len(items) != 1 || items[0].CarePackageID != pending || !items[0].CompletedAt.After(firstEnd) {
		t.Fatalf("renewal own range/end: %+v %v", items, err)
	}
	if _, err := s.CreateDoctorReviewForEntitlement(ctx, professional, foreign, 5, "Asing", true, "", pending); !errors.Is(err, ErrReviewNotEligible) {
		t.Fatalf("foreign purchase review=%v", err)
	}
	// Corrupt ownership is never treated as another patient's entitlement.
	if _, err := db.ExecContext(ctx, `UPDATE care_packages SET patient_id=$2 WHERE id=$1`, pending, foreign); err != nil {
		t.Fatal(err)
	}
	if items, err := s.ListReviewEntitlements(ctx, patient, professional); err != nil || len(items) != 0 {
		t.Fatalf("foreign child eligible: %+v %v", items, err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE care_packages SET patient_id=$2 WHERE id=$1`, pending, patient); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateDoctorReviewForEntitlement(ctx, professional, patient, 4, "Perpanjangan", true, "", pending); err != nil {
		t.Fatal(err)
	}
	if _, err := s.CreateDoctorReviewForEntitlement(ctx, professional, patient, 5, "Ulang", true, "", pending); !errors.Is(err, ErrReviewNotEligible) {
		t.Fatalf("renewal duplicate=%v", err)
	}
}

func TestReviewCompletedPackageThenRenewalKeepsSeparateEntitlements(t *testing.T) {
	s, db, ctx := attendedTestStore(t)
	patient, professional := mustUUID(t, db, ctx), mustUUID(t, db, ctx)
	for _, row := range []struct{ id, role string }{{patient, "patient"}, {professional, "professional"}} {
		if _, err := db.ExecContext(ctx, `INSERT INTO users(id,email,password_hash,role,display_name) VALUES($1,$2,'test',$3,'Uji')`, row.id, row.id+"@review-renewal.test", row.role); err != nil {
			t.Fatal(err)
		}
	}
	t.Cleanup(func() {
		if _, err := db.ExecContext(ctx, `DELETE FROM care_sessions WHERE patient_id=$1`, patient); err != nil {
			t.Errorf("cleanup care sessions: %v", err)
		}
		if _, err := db.ExecContext(ctx, `DELETE FROM care_packages WHERE patient_id=$1`, patient); err != nil {
			t.Errorf("cleanup care packages: %v", err)
		}
		cleanupTestUsers(t, db, patient, professional)
	})
	var original string
	if err := db.QueryRowContext(ctx, `INSERT INTO care_packages(patient_id,professional_id,status,expires_at,price) VALUES($1,$2,'active',now()+interval '30 days',200000) RETURNING id`, patient, professional).Scan(&original); err != nil {
		t.Fatal(err)
	}
	complete := func(pkg string) {
		t.Helper()
		if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions(package_id,patient_id,professional_id,scheduled_at,status) SELECT $1,$2,$3,now()-i*interval '1 hour','completed' FROM generate_series(1,4)i`, pkg, patient, professional); err != nil {
			t.Fatal(err)
		}
	}
	complete(original)
	if _, err := s.CreateDoctorReviewForEntitlement(ctx, professional, patient, 5, "Pertama", true, "", original); err != nil {
		t.Fatal(err)
	}
	var booking, pending string
	if err := db.QueryRowContext(ctx, `INSERT INTO bookings(patient_id,professional_id,service_type,session_type,booking_date,slot_time,price,status) VALUES($1,$2,'package_session','chat',CURRENT_DATE,'12:00',200000,'paid') RETURNING id`, patient, professional).Scan(&booking); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRowContext(ctx, `INSERT INTO care_packages(patient_id,professional_id,booking_id,status,expires_at,price) VALUES($1,$2,$3,'pending_payment',now()+interval '42 days',200000) RETURNING id`, patient, professional, booking).Scan(&pending); err != nil {
		t.Fatal(err)
	}
	renewal, merged, err := s.ActivatePendingPackage(ctx, patient, professional, booking)
	if err != nil {
		t.Fatal(err)
	}
	if !merged || renewal.ID != original || renewal.TotalSessions != 8 || renewal.Price != 400000 {
		t.Fatalf("renewal merge lost credits/payment: %+v merged=%v", renewal, merged)
	}
	old, err := s.GetCarePackage(ctx, original)
	if err != nil || old.Status != "active" || old.TotalSessions != 8 {
		t.Fatalf("merged quota lost: %+v %v", old, err)
	}
	complete(renewal.ID)
	if _, err := s.CreateDoctorReviewForEntitlement(ctx, professional, patient, 4, "Perpanjangan", true, "", pending); err != nil {
		t.Fatal(err)
	}
	replay, merged, err := s.ActivatePendingPackage(ctx, patient, professional, booking)
	if err != nil || !merged || replay.ID != renewal.ID || replay.TotalSessions != 8 {
		t.Fatalf("renewal replay changed quota: %+v %v %v", replay, merged, err)
	}
	if eligible, err := s.CanReviewProfessional(ctx, patient, professional); err != nil || eligible {
		t.Fatalf("replay reminted review: %v %v", eligible, err)
	}
}
