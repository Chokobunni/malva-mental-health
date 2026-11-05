package notify

import (
	"context"
	"database/sql"
	"os"
	"testing"

	"malva/backend/internal/realtime"
	"malva/backend/internal/store"

	_ "github.com/jackc/pgx/v5/stdlib"
)

type recordingProvider struct{ messages []Message }

func (p *recordingProvider) Send(_ context.Context, message Message) error {
	p.messages = append(p.messages, message)
	return nil
}

// Only the explicit isolated test database is allowed; never use the app DSN.
func deliveryTestStore(t *testing.T) (*sql.DB, *store.Store) {
	t.Helper()
	dsn := os.Getenv("MALVA_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("set MALVA_TEST_DATABASE_URL to an isolated test database")
	}
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	if err := db.PingContext(t.Context()); err != nil {
		t.Fatal(err)
	}
	return db, store.New(db)
}

func TestOutboxRechecksDeliveryPolicy(t *testing.T) {
	db, st := deliveryTestStore(t)
	ctx := t.Context()
	var patient, professional, session string
	for _, item := range []struct {
		role string
		id   *string
	}{{"patient", &patient}, {"professional", &professional}} {
		if err := db.QueryRowContext(ctx, `INSERT INTO users (email,password_hash,role,display_name)
			VALUES (gen_random_uuid()::text || '@outbox.test','x',$1,'Synthetic') RETURNING id::text`, item.role).Scan(item.id); err != nil {
			t.Fatal(err)
		}
	}
	t.Cleanup(func() {
		_, _ = db.ExecContext(context.Background(), `DELETE FROM notifications WHERE user_id IN ($1,$2)`, patient, professional)
		_, _ = db.ExecContext(context.Background(), `DELETE FROM care_sessions WHERE patient_id=$1`, patient)
		_, _ = db.ExecContext(context.Background(), `DELETE FROM users WHERE id IN ($1,$2)`, patient, professional)
	})
	if err := db.QueryRowContext(ctx, `INSERT INTO care_sessions
		(patient_id,professional_id,session_type,scheduled_at,duration_minutes,status)
		VALUES ($1,$2,'chat',now(),30,'scheduled') RETURNING id::text`, patient, professional).Scan(&session); err != nil {
		t.Fatal(err)
	}
	if err := st.UpsertDeviceToken(ctx, patient, "android", "synthetic-patient"); err != nil {
		t.Fatal(err)
	}
	if err := st.UpsertDeviceToken(ctx, professional, "android", "synthetic-professional"); err != nil {
		t.Fatal(err)
	}
	provider := &recordingProvider{}
	worker := NewOutboxWorker(st, provider, realtime.NewHub(discardLogger(), nil, st), discardLogger())
	for _, tc := range []struct {
		name, kind, status, age, role, recipient, sender, sessionID string
		want                                                        int
	}{
		{"active patient chat", "chat_message", "scheduled", "0 minutes", "patient", patient, professional, session, 1},
		{"active professional chat", "chat_message", "scheduled", "0 minutes", "patient", professional, patient, session, 1},
		{"completed within session window", "chat_message", "completed", "0 minutes", "patient", patient, professional, session, 0},
		{"at session end", "chat_message", "scheduled", "-30 minutes", "patient", patient, professional, session, 0},
		{"legacy screening queue", "screening_reviewed", "scheduled", "0 minutes", "patient", patient, professional, session, 0},
		{"legacy health queue", "health_record_updated", "scheduled", "0 minutes", "patient", patient, professional, session, 0},
		{"expired session", "chat_message", "scheduled", "-60 minutes", "patient", patient, professional, session, 0},
		{"cancelled session", "chat_message", "cancelled_by_patient", "0 minutes", "patient", patient, professional, session, 0},
		{"no-show session", "chat_message", "no_show", "0 minutes", "patient", patient, professional, session, 0},
		{"future session", "chat_message", "scheduled", "60 minutes", "patient", patient, professional, session, 0},
		{"role changed after enqueue", "chat_message", "scheduled", "0 minutes", "professional", patient, professional, session, 0},
		{"sender outside pair", "chat_message", "scheduled", "0 minutes", "patient", patient, patient, session, 0},
		{"missing session", "chat_message", "scheduled", "0 minutes", "patient", patient, professional, "", 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := db.ExecContext(ctx, `UPDATE care_sessions SET status=$2, scheduled_at=now()+$3::interval WHERE id=$1`, session, tc.status, tc.age); err != nil {
				t.Fatal(err)
			}
			if _, err := db.ExecContext(ctx, `UPDATE users SET role=$2 WHERE id=$1`, patient, tc.role); err != nil {
				t.Fatal(err)
			}
			n, err := st.CreateNotification(ctx, store.Notification{UserID: tc.recipient, Type: tc.kind, Title: "Synthetic", Body: "Synthetic", Data: map[string]string{
				"kind": tc.kind, "sender_id": tc.sender, "session_id": tc.sessionID, "patient_id": patient, "professional_id": professional,
			}})
			if err != nil {
				t.Fatal(err)
			}
			jobs, err := st.AcquireOutboxJobs(ctx, 1000)
			if err != nil {
				t.Fatal(err)
			}
			before := len(provider.messages)
			for _, job := range jobs {
				if job.NotificationID == n.ID {
					if err := worker.sendJob(ctx, job); err != nil {
						t.Fatal(err)
					}
					// A repeated dispatcher invocation must not resend a retired job.
					if err := worker.sendJob(ctx, job); err != nil {
						t.Fatal(err)
					}
				}
			}
			if got := len(provider.messages) - before; got != tc.want {
				t.Fatalf("provider sends=%d, want %d", got, tc.want)
			}
			if tc.want > 0 && provider.messages[before].Data["notification_id"] != n.ID {
				t.Fatal("transport must carry the stable notification ID")
			}
			if tc.want == 0 {
				var status string
				if err := db.QueryRowContext(ctx, `SELECT status FROM notifications WHERE id=$1`, n.ID).Scan(&status); err != nil {
					t.Fatal(err)
				}
				if status != "pending" {
					t.Fatal("suppression must retain in-app history without claiming push delivery")
				}
			}
			var retired bool
			if err := db.QueryRowContext(ctx, `SELECT delivered_at IS NOT NULL FROM notification_outbox WHERE notification_id=$1`, n.ID).Scan(&retired); err != nil {
				t.Fatal(err)
			}
			if !retired {
				t.Fatal("suppressed/delivered job must not remain retryable")
			}
		})
	}
}
