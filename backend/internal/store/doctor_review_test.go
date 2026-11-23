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
	if _, err := db.ExecContext(ctx, `INSERT INTO professional_pricing(professional_id,quick_chat_price,quick_video_price,package_price) VALUES($1,200000,500000,1300000)`, professional); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if _, err := db.ExecContext(ctx, `DELETE FROM professional_pricing WHERE professional_id=$1`, professional); err != nil {
			t.Errorf("cleanup professional pricing: %v", err)
		}
	})
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
	got := doctors[0]
	if got.QuickChatPrice != 200000 || got.QuickVideoPrice != 500000 || got.PackagePrice != 1300000 {
		t.Fatalf("directory prices = %d, %d, %d", got.QuickChatPrice, got.QuickVideoPrice, got.PackagePrice)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO service_packages
		(professional_id,package_sessions,package_duration_days,price,label)
		VALUES($1,1,1,175000,'Quick chat'),($1,1,1,475000,'Quick video'),($1,4,42,1200000,'Continuous')`, professional); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if _, err := db.ExecContext(ctx, `DELETE FROM service_packages WHERE professional_id=$1`, professional); err != nil {
			t.Errorf("cleanup legacy pricing: %v", err)
		}
	})
	if _, err := db.ExecContext(ctx, `UPDATE professional_pricing SET quick_chat_price=0 WHERE professional_id=$1`, professional); err != nil {
		t.Fatal(err)
	}
	doctors, err = s.SearchDoctors(ctx, DoctorSearchParams{Specialization: suffix})
	if err != nil || len(doctors) != 1 || doctors[0].QuickChatPrice != 0 {
		t.Fatalf("explicit zero must hide legacy quick chat price: %+v, %v", doctors, err)
	}
	if _, err := db.ExecContext(ctx, `DELETE FROM professional_pricing WHERE professional_id=$1`, professional); err != nil {
		t.Fatal(err)
	}
	doctors, err = s.SearchDoctors(ctx, DoctorSearchParams{Specialization: suffix})
	if err != nil || len(doctors) != 1 || doctors[0].QuickChatPrice != 175000 ||
		doctors[0].QuickVideoPrice != 475000 || doctors[0].PackagePrice != 1200000 {
		t.Fatalf("missing legacy prices: %+v, %v", doctors, err)
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
