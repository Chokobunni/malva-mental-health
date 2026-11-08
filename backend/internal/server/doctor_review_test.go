package server

import (
	"bytes"
	"context"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"

	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
)

func TestReviewPackageConcurrentLegacyPOSTAndOwnership(t *testing.T) {
	db, _ := openOnboardingTestStore(t)
	ctx := context.Background()
	ids := make([]string, 3)
	for i, role := range []string{"patient", "professional", "patient"} {
		if err := db.QueryRowContext(ctx, `INSERT INTO users(email,password_hash,role,display_name) VALUES(gen_random_uuid()::text||'@review-concurrent.test','test',$1,'Uji') RETURNING id`, role).Scan(&ids[i]); err != nil {
			t.Fatal(err)
		}
	}
	t.Cleanup(func() {
		db.ExecContext(ctx, `DELETE FROM care_sessions WHERE patient_id=$1`, ids[0])
		db.ExecContext(ctx, `DELETE FROM care_packages WHERE patient_id=$1`, ids[0])
		cleanupTestUsers(t, db, ids...)
	})
	var pkg, session string
	if err := db.QueryRowContext(ctx, `INSERT INTO care_packages(patient_id,professional_id,status,expires_at) VALUES($1,$2,'active',now()+interval '1 day') RETURNING id`, ids[0], ids[1]).Scan(&pkg); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions(package_id,patient_id,professional_id,scheduled_at,status) SELECT $1,$2,$3,now()-i*interval '1 hour','completed' FROM generate_series(1,4) i`, pkg, ids[0], ids[1]); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRowContext(ctx, `SELECT id FROM care_sessions WHERE package_id=$1 LIMIT 1`, pkg).Scan(&session); err != nil {
		t.Fatal(err)
	}
	srv := newOnboardingTestServer(db)
	submit := func(patient, body string) int {
		req := httptest.NewRequest("POST", "/v1/doctors/"+ids[1]+"/reviews", strings.NewReader(body))
		req.SetPathValue("user_id", ids[1])
		res := httptest.NewRecorder()
		srv.createDoctorReview(res, req, auth.Claims{Role: "patient", Subject: patient})
		return res.Code
	}
	if status := submit(ids[2], `{"stars":5,"care_package_id":"`+pkg+`"}`); status != 409 {
		t.Fatalf("foreign package POST status%d", status)
	}
	if status := submit(ids[0], `{"stars":5,"session_id":"`+session+`"}`); status != 409 {
		t.Fatalf("individual package meeting POST status%d", status)
	}
	var created, conflicts atomic.Int32
	var wg sync.WaitGroup
	for i := 0; i < 10; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			switch submit(ids[0], `{"stars":5}`) {
			case 201:
				created.Add(1)
			case 409:
				conflicts.Add(1)
			}
		}()
	}
	wg.Wait()
	if created.Load() != 1 || conflicts.Load() != 9 {
		t.Fatalf("concurrent old-client POSTs: created%d conflicts%d", created.Load(), conflicts.Load())
	}
	var count int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM doctor_reviews WHERE care_package_id=$1 AND session_id IS NULL`, pkg).Scan(&count); err != nil || count != 1 {
		t.Fatalf("package review count%d err%v", count, err)
	}
}

func TestReviewValidationRejectsInvalidPayloadBeforeDatabase(t *testing.T) {
	srv, _, _ := newSafetyTestServer()
	for _, body := range []string{`{"stars":0}`, `{"stars":6}`, `{"stars":4,"review_text":"` + strings.Repeat("a", 2001) + `"}`} {
		req := httptest.NewRequest("POST", "/v1/doctors/test/reviews", strings.NewReader(body))
		req.SetPathValue("user_id", "test")
		res := httptest.NewRecorder()
		srv.createDoctorReview(res, req, auth.Claims{Role: "patient", Subject: "patient"})
		if res.Code != 400 {
			t.Fatalf("invalid review status%d, want400: %s", res.Code, res.Body.String())
		}
	}
}

func TestReviewRequiresCompletedSessionAcrossFullHistory(t *testing.T) {
	db, _ := openOnboardingTestStore(t)
	ctx := context.Background()
	ids := make([]string, 3)
	for i, role := range []string{"patient", "professional", "professional"} {
		if err := db.QueryRowContext(ctx, `INSERT INTO users(email,password_hash,role,display_name) VALUES(gen_random_uuid()::text||'@review-handler.test','test',$1,'Uji') RETURNING id`, role).Scan(&ids[i]); err != nil {
			t.Fatal(err)
		}
	}
	t.Cleanup(func() { cleanupTestUsers(t, db, ids...) })
	t.Cleanup(func() { _, _ = db.ExecContext(ctx, `DELETE FROM care_sessions WHERE patient_id=$1`, ids[0]) })
	srv := newOnboardingTestServer(db)
	submit := func() *httptest.ResponseRecorder {
		req := httptest.NewRequest("POST", "/v1/doctors/"+ids[1]+"/reviews", bytes.NewBufferString(`{"stars":4,"helpful":false,"review_text":"Jelas"}`))
		req.SetPathValue("user_id", ids[1])
		rec := httptest.NewRecorder()
		srv.createDoctorReview(rec, req, auth.Claims{Role: "patient", Subject: ids[0]})
		return rec
	}
	if rec := submit(); rec.Code != 409 {
		t.Fatalf("no completed session status%d, want409", rec.Code)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions(patient_id,professional_id,session_type,scheduled_at,status) VALUES($1,$2,'chat',$3::timestamptz - interval '200 days','scheduled')`, ids[0], ids[1], clock.Now()); err != nil {
		t.Fatal(err)
	}
	if rec := submit(); rec.Code != 409 {
		t.Fatalf("scheduled session status%d, want409", rec.Code)
	}
	if _, err := db.ExecContext(ctx, `UPDATE care_sessions SET status='completed' WHERE patient_id=$1`, ids[0]); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions(patient_id,professional_id,session_type,scheduled_at,status) SELECT $1,$2,'chat',$3::timestamptz - make_interval(days=>n),'completed' FROM generate_series(1,125)n`, ids[0], ids[2], clock.Now()); err != nil {
		t.Fatal(err)
	}
	if rec := submit(); rec.Code != 201 {
		t.Fatalf("old completed session status%d, want201: %s", rec.Code, rec.Body.String())
	}
	var count, percent int
	var helpful bool
	if err := db.QueryRowContext(ctx, `SELECT count(*),max(helpfulness_percent),bool_or(helpful) FROM doctor_reviews WHERE professional_id=$1 AND patient_id=$2`, ids[1], ids[0]).Scan(&count, &percent, &helpful); err != nil {
		t.Fatal(err)
	}
	if count != 1 || percent != 80 || helpful {
		t.Fatalf("stored count%d rating%d helpful%v", count, percent, helpful)
	}
}
