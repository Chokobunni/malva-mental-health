package server

import (
	"bytes"
	"context"
	"net/http/httptest"
	"strings"
	"testing"

	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
)

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
	if rec := submit(); rec.Code != 403 {
		t.Fatalf("no completed session status%d, want403", rec.Code)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions(patient_id,professional_id,session_type,scheduled_at,status) VALUES($1,$2,'chat',$3::timestamptz - interval '200 days','scheduled')`, ids[0], ids[1], clock.Now()); err != nil {
		t.Fatal(err)
	}
	if rec := submit(); rec.Code != 403 {
		t.Fatalf("scheduled session status%d, want403", rec.Code)
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
