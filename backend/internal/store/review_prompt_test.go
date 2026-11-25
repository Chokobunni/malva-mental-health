package store

import "testing"

func TestReviewPromptClaimIsEligibleAndOncePerAccount(t *testing.T) {
	s, db, ctx := attendedTestStore(t)
	patient := insertTestUser(t, db, ctx, "patient", "Review prompt", "promptp")
	other := insertTestUser(t, db, ctx, "patient", "Review prompt", "prompto")
	professional := insertTestUser(t, db, ctx, "professional", "Review prompt", "promptd")
	t.Cleanup(func() {
		_, _ = db.Exec("DELETE FROM care_sessions WHERE patient_id=$1", patient)
		cleanupTestUsers(t, db, patient, other, professional)
	})
	var sessionID string
	claimIDs := []string{mustUUID(t, db, ctx), mustUUID(t, db, ctx)}
	if err := db.QueryRowContext(ctx, `INSERT INTO care_sessions
		(patient_id,professional_id,status,scheduled_at,session_type)
		VALUES ($1,$2,'scheduled',now()-interval '2 hours','video') RETURNING id`,
		patient, professional).Scan(&sessionID); err != nil {
		t.Fatal(err)
	}
	if shown, err := s.ClaimReviewPrompt(ctx, patient, sessionID, "session", claimIDs[0]); err != nil || shown {
		t.Fatalf("scheduled session prompt %v, %v", shown, err)
	}
	if _, err := db.ExecContext(ctx, "UPDATE care_sessions SET status='completed' WHERE id=$1", sessionID); err != nil {
		t.Fatal(err)
	}
	if shown, err := s.ClaimReviewPrompt(ctx, other, sessionID, "session", claimIDs[0]); err != nil || shown {
		t.Fatalf("different account prompt %v, %v", shown, err)
	}
	type result struct {
		show    bool
		err     error
		claimID string
	}
	claims := make(chan result, 2)
	for _, claimID := range claimIDs {
		go func() {
			show, err := s.ClaimReviewPrompt(ctx, patient, sessionID, "session", claimID)
			claims <- result{show, err, claimID}
		}()
	}
	first, second := <-claims, <-claims
	if first.err != nil || second.err != nil || first.show == second.show {
		t.Fatalf("concurrent devices must claim exactly once: %+v, %+v", first, second)
	}
	for _, original := range []result{first, second} {
		show, err := s.ClaimReviewPrompt(ctx, patient, sessionID, "session", original.claimID)
		if err != nil || show != original.show {
			t.Fatalf("retry changed claim result: show=%v, err=%v, original=%+v", show, err, original)
		}
	}
	if items, err := s.ListReviewEntitlements(ctx, patient, professional); err != nil || len(items) != 1 {
		t.Fatalf("manual review eligibility after claim: %+v, %v", items, err)
	}
}
