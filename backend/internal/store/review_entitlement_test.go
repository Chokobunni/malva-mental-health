package store

import (
	"errors"
	"sync"
	"sync/atomic"
	"testing"

	"malva/backend/internal/clock"
)

func TestReviewEntitlementLegacyCutoffAndOwnership(t *testing.T) {
	s, db, ctx := attendedTestStore(t)
	patient, professional, other := mustUUID(t, db, ctx), mustUUID(t, db, ctx), mustUUID(t, db, ctx)
	for _, row := range []struct{ id, role string }{{patient, "patient"}, {professional, "professional"}, {other, "patient"}} {
		if _, err := db.ExecContext(ctx, `INSERT INTO users(id,email,password_hash,role,display_name) VALUES($1,$2,'test',$3,'Uji')`, row.id, row.id+"@review.test", row.role); err != nil {
			t.Fatal(err)
		}
	}
	t.Cleanup(func() {
		if _, err := db.ExecContext(ctx, `DELETE FROM care_sessions WHERE professional_id=$1`, professional); err != nil {
			t.Errorf("cleanup care sessions: %v", err)
		}
		cleanupTestUsers(t, db, patient, professional, other)
	})
	var oldSession, newSession string
	if err := db.QueryRowContext(ctx, `INSERT INTO care_sessions(patient_id,professional_id,scheduled_at,status,updated_at) VALUES($1,$2,now()-interval '3 days','completed',now()-interval '2 days') RETURNING id`, patient, professional).Scan(&oldSession); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO doctor_reviews(patient_id,professional_id,helpfulness_percent,created_at) VALUES($1,$2,100,now()-interval '1 day')`, patient, professional); err != nil {
		t.Fatal(err)
	}
	if ok, err := s.CanReviewProfessional(ctx, patient, professional); err != nil || ok {
		t.Fatalf("ambiguous legacy unit eligible=%v err=%v", ok, err)
	}
	if _, err := s.UpdateCareSessionDetail(ctx, oldSession, "", "Catatan diperbarui", ""); err != nil {
		t.Fatal(err)
	}
	if ok, err := s.CanReviewProfessional(ctx, patient, professional); err != nil || ok {
		t.Fatalf("detail edit reminted legacy entitlement eligible=%v err=%v", ok, err)
	}
	if err := db.QueryRowContext(ctx, `INSERT INTO care_sessions(patient_id,professional_id,scheduled_at,status) VALUES($1,$2,now()-interval '1 hour','completed') RETURNING id`, patient, professional).Scan(&newSession); err != nil {
		t.Fatal(err)
	}
	items, err := s.ListReviewEntitlements(ctx, patient, professional)
	if err != nil || len(items) != 1 || items[0].SessionID != newSession {
		t.Fatalf("new completion must survive legacy cutoff: %+v %v", items, err)
	}
	for _, attempt := range []struct{ patient, session string }{{other, newSession}, {patient, oldSession}} {
		if _, err := s.CreateDoctorReviewForEntitlement(ctx, professional, attempt.patient, 4, "", true, attempt.session, ""); !errors.Is(err, ErrReviewNotEligible) {
			t.Fatalf("foreign/legacy entitlement err=%v", err)
		}
	}
	if _, err := s.CreateDoctorReviewForEntitlement(ctx, professional, patient, 4, "", true, newSession, ""); err != nil {
		t.Fatal(err)
	}
	reviews, err := s.ListDoctorReviews(ctx, professional, 10)
	if err != nil || len(reviews) != 2 {
		t.Fatalf("legacy review visibility lost: %+v %v", reviews, err)
	}
	var unlinked int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM doctor_reviews WHERE patient_id=$1 AND session_id IS NULL AND care_package_id IS NULL`, patient).Scan(&unlinked); err != nil || unlinked != 1 {
		t.Fatalf("legacy association fabricated: count%d err%v", unlinked, err)
	}
}

func TestReviewEntitlementConcurrentLegacyRequests(t *testing.T) {
	s, db, ctx := attendedTestStore(t)
	patient, professional := mustUUID(t, db, ctx), mustUUID(t, db, ctx)
	for _, row := range []struct{ id, role string }{{patient, "patient"}, {professional, "professional"}} {
		if _, err := db.ExecContext(ctx, `INSERT INTO users(id,email,password_hash,role,display_name) VALUES($1,$2,'test',$3,'Uji')`, row.id, row.id+"@review.test", row.role); err != nil {
			t.Fatal(err)
		}
	}
	t.Cleanup(func() {
		if _, err := db.ExecContext(ctx, `DELETE FROM care_sessions WHERE patient_id=$1`, patient); err != nil {
			t.Errorf("cleanup care sessions: %v", err)
		}
		cleanupTestUsers(t, db, patient, professional)
	})
	if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions(patient_id,professional_id,scheduled_at,status) VALUES($1,$2,now()-interval '1 hour','completed')`, patient, professional); err != nil {
		t.Fatal(err)
	}
	var successes atomic.Int32
	var wg sync.WaitGroup
	for i := 0; i < 12; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			if _, err := s.CreateDoctorReview(ctx, professional, patient, 5, "", true); err == nil {
				successes.Add(1)
			}
		}()
	}
	wg.Wait()
	if got := successes.Load(); got != 1 {
		t.Fatalf("one completed session accepted %d concurrent reviews, want 1", got)
	}
	if ok, err := s.CanReviewProfessional(ctx, patient, professional); err != nil || ok {
		t.Fatalf("consumed entitlement eligible=%v err=%v", ok, err)
	}
}

func TestReviewEntitlementWaitsForWholePackage(t *testing.T) {
	s, db, ctx := attendedTestStore(t)
	patient, professional, pkg := mustUUID(t, db, ctx), mustUUID(t, db, ctx), mustUUID(t, db, ctx)
	t.Cleanup(func() {
		if _, err := db.ExecContext(ctx, `DELETE FROM care_sessions WHERE package_id=$1`, pkg); err != nil {
			t.Errorf("cleanup care sessions: %v", err)
		}
		if _, err := db.ExecContext(ctx, `DELETE FROM care_packages WHERE id=$1`, pkg); err != nil {
			t.Errorf("cleanup care package: %v", err)
		}
	})
	if _, err := db.ExecContext(ctx, `INSERT INTO care_packages(id,patient_id,professional_id,status,expires_at) VALUES($1,$2,$3,'active',now()+interval '1 day')`, pkg, patient, professional); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions(package_id,patient_id,professional_id,scheduled_at,status) VALUES($1,$2,$3,now()-interval '1 hour','completed')`, pkg, patient, professional); err != nil {
		t.Fatal(err)
	}
	if ok, err := s.CanReviewProfessional(ctx, patient, professional); err != nil || ok {
		t.Fatalf("one of four package meetings eligible=%v err=%v, want false", ok, err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions(package_id,patient_id,professional_id,scheduled_at,status) SELECT $1,$2,$3,now()-i*interval '1 hour','no_show' FROM generate_series(2,4) i`, pkg, patient, professional); err != nil {
		t.Fatal(err)
	}
	if ok, err := s.CanReviewProfessional(ctx, patient, professional); err != nil || !ok {
		t.Fatalf("finished package eligible=%v err=%v, want true", ok, err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions(package_id,patient_id,professional_id,scheduled_at,status) VALUES($1,$2,$3,now()+interval '10 days','cancelled_by_professional')`, pkg, patient, professional); err != nil {
		t.Fatal(err)
	}
	items, err := s.ListReviewEntitlements(ctx, patient, professional)
	if err != nil || len(items) != 1 || items[0].CompletedAt.After(clock.Now()) {
		t.Fatalf("cancelled future session changed package end: %+v %v", items, err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE care_sessions SET status='no_show' WHERE package_id=$1`, pkg); err != nil {
		t.Fatal(err)
	}
	if ok, err := s.CanReviewProfessional(ctx, patient, professional); err != nil || ok {
		t.Fatalf("all no-show package eligible=%v err=%v", ok, err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE care_sessions SET status='scheduled' WHERE id=(SELECT id FROM care_sessions WHERE package_id=$1 AND status='no_show' LIMIT 1)`, pkg); err != nil {
		t.Fatal(err)
	}
	if ok, err := s.CanReviewProfessional(ctx, patient, professional); err != nil || ok {
		t.Fatalf("unfinished package eligible=%v err=%v", ok, err)
	}
}
