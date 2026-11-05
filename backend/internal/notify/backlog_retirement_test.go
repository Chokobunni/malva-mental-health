package notify

import (
	"context"
	"os"
	"strings"
	"testing"

	"malva/backend/internal/store"
)

func TestBacklogRetirementPreservesHistoryAndNewWork(t *testing.T) {
	db, st := deliveryTestStore(t)
	ctx := t.Context()
	var user string
	if err := db.QueryRowContext(ctx, `INSERT INTO users(email,password_hash,role,display_name)
 VALUES(gen_random_uuid()::text || '@retirement.test','x','patient','Synthetic') RETURNING id::text`).Scan(&user); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = db.ExecContext(context.Background(), `DELETE FROM users WHERE id=$1`, user) })
	old, err := st.CreateNotification(ctx, store.Notification{UserID: user, Type: "screening_reviewed", Title: "Synthetic", Body: "Synthetic"})
	if err != nil {
		t.Fatal(err)
	}
	fresh, err := st.CreateNotification(ctx, store.Notification{UserID: user, Type: "chat_message", Title: "Synthetic", Body: "Synthetic"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE notification_outbox SET created_at = CASE WHEN notification_id=$1 THEN '2000-01-01T00:00:00+07:00'::timestamptz ELSE '2002-01-01T00:00:00+07:00'::timestamptz END WHERE notification_id IN($1,$2)`, old.ID, fresh.ID); err != nil {
		t.Fatal(err)
	}
	script, err := os.ReadFile("../../deploy/scripts/retire_notification_backlog.sql")
	if err != nil {
		t.Fatal(err)
	}
	sql := strings.ReplaceAll(string(script), "\\set ON_ERROR_STOP on", "")
	sql = strings.ReplaceAll(sql, ":'cutoff'", "'2001-01-01T00:00:00+07:00'")
	if _, err := db.ExecContext(ctx, sql); err != nil {
		t.Fatal(err)
	}
	var retired, pending bool
	if err := db.QueryRowContext(ctx, `SELECT delivered_at IS NOT NULL FROM notification_outbox WHERE notification_id=$1`, old.ID).Scan(&retired); err != nil {
		t.Fatal(err)
	}
	if err := db.QueryRowContext(ctx, `SELECT delivered_at IS NULL FROM notification_outbox WHERE notification_id=$1`, fresh.ID).Scan(&pending); err != nil {
		t.Fatal(err)
	}
	if !retired || !pending {
		t.Fatalf("retired old=%v, pending new=%v", retired, pending)
	}
	var history int
	if err := db.QueryRowContext(ctx, `SELECT count(*) FROM notifications WHERE id IN($1,$2) AND status='pending' AND title='Synthetic' AND body='Synthetic'`, old.ID, fresh.ID).Scan(&history); err != nil {
		t.Fatal(err)
	}
	if history != 2 {
		t.Fatal("transport retirement changed in-app history")
	}
}
