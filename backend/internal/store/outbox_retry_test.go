package store

import (
	"malva/backend/internal/clock"
	"testing"
)

func TestOutboxTerminalFailureIsNotAcquiredAgain(t *testing.T) {
	db, ctx := openMigrationTestDB(t)
	patient := insertTestUser(t, db, ctx, "patient", "Synthetic", "outbox-terminal")
	t.Cleanup(func() { cleanupTestUsers(t, db, patient) })
	st := New(db)
	n, err := st.CreateNotification(ctx, Notification{UserID: patient, Type: "chat_message", Title: "Synthetic", Body: "Synthetic"})
	if err != nil {
		t.Fatal(err)
	}
	for attempt := 1; attempt <= 5; attempt++ {
		jobs, err := st.AcquireOutboxJobs(ctx, 1000)
		if err != nil {
			t.Fatal(err)
		}
		found := false
		for _, job := range jobs {
			if job.NotificationID == n.ID {
				found = true
				if job.Attempts != attempt {
					t.Fatalf("attempt=%d, want %d", job.Attempts, attempt)
				}
				if err := st.MarkOutboxFailed(ctx, job.ID, "synthetic transient failure", clock.Now(), attempt == 5); err != nil {
					t.Fatal(err)
				}
			}
		}
		if !found {
			t.Fatalf("missing retry attempt %d", attempt)
		}
	}
	jobs, err := st.AcquireOutboxJobs(ctx, 1000)
	if err != nil {
		t.Fatal(err)
	}
	for _, job := range jobs {
		if job.NotificationID == n.ID {
			t.Fatal("terminal failure was acquired for a sixth attempt")
		}
	}
}
