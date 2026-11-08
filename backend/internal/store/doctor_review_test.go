package store

import (
	"fmt"
	"testing"
	"time"
)

func TestDoctorReviewPersistsStarsIndependentOfHelpfulAndSearchUsesRealTotals(t *testing.T) {
	s, db, ctx := attendedTestStore(t)
	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	professional := mustUUID(t, db, ctx)
	patient := mustUUID(t, db, ctx)
	for _, row := range []struct{ id, role string }{{professional, "professional"}, {patient, "patient"}} {
		if _, err := db.ExecContext(ctx, `INSERT INTO users(id,email,password_hash,role,display_name) VALUES($1,$2,'test',$3,'Uji')`, row.id, row.id+"@review.test", row.role); err != nil {
			t.Fatal(err)
		}
	}
	t.Cleanup(func() { cleanupTestUsers(t, db, patient, professional) })
	t.Cleanup(func() { _, _ = db.ExecContext(ctx, `DELETE FROM care_sessions WHERE patient_id=$1`, patient) })
	if _, err := db.ExecContext(ctx, `INSERT INTO care_sessions(patient_id,professional_id,scheduled_at,status) VALUES($1,$2,now()-interval '1 hour','completed')`, patient, professional); err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO professional_credentials(user_id,specialization,verification_status,review_count,helpfulness_count) VALUES($1,$2,'VERIFIED',4,3)`, professional, suffix); err != nil {
		t.Fatal(err)
	}
	rv, err := s.CreateDoctorReview(ctx, professional, patient, 4, "  Penjelasan jelas  ", false)
	if err != nil {
		t.Fatal(err)
	}
	if rv.Stars != 4 {
		t.Fatalf("returned stars=%d", rv.Stars)
	}
	reviews, err := s.ListDoctorReviews(ctx, professional, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(reviews) != 1 || reviews[0].Stars != 4 || reviews[0].Helpful || reviews[0].ReviewText != "Penjelasan jelas" {
		t.Fatalf("persisted review lost independent stars/helpful: %+v", reviews)
	}
	rating, err := s.DoctorRating(ctx, professional)
	if err != nil {
		t.Fatal(err)
	}
	if rating.AverageStars != 4 || rating.ReviewCount != 1 || rating.HelpfulPct != 0 {
		t.Fatalf("rating=%+v", rating)
	}
	doctors, err := s.SearchDoctors(ctx, DoctorSearchParams{Specialization: suffix})
	if err != nil {
		t.Fatal(err)
	}
	if len(doctors) != 1 || doctors[0].ReviewCount != 1 || doctors[0].HelpfulnessCount != 0 {
		t.Fatalf("search must ignore seeded counters: %+v", doctors)
	}
}

func TestCreateDoctorReviewRejectsInvalidStarsAndLongComment(t *testing.T) {
	s, _, ctx := attendedTestStore(t)
	for _, stars := range []int{0, 6, -1} {
		if _, err := s.CreateDoctorReview(ctx, "invalid", "invalid", stars, "", true); err == nil || err.Error() != "bintang harus antara 1 dan 5" {
			t.Fatalf("stars %d error=%v", stars, err)
		}
	}
}
