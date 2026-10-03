package store

import (
	"context"
	"database/sql"
	"os"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"
)

func TestSOSBlastUpdateFlowDebug(t *testing.T) {
	dsn := "postgres://malva:malva_dev_password@localhost:5432/malva?sslmode=disable"
	if v := os.Getenv("MALVA_TEST_DATABASE_URL"); v != "" {
		dsn = v
	}
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Skipf("db unavailable: %v", err)
	}
	defer func() { _ = db.Close() }()
	ctxPing, cancelPing := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancelPing()
	if err := db.PingContext(ctxPing); err != nil {
		t.Skipf("db unreachable (CI-safe): %v", err)
	}
	s := New(db)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// Ambil incident terbaru (butuh seed data; skip bila kosong agar CI aman)
	var incidentID, patientID string
	err = db.QueryRowContext(ctx, `SELECT id, patient_id FROM crisis_incidents ORDER BY created_at DESC LIMIT 1`).Scan(&incidentID, &patientID)
	if err != nil {
		t.Skipf("no seed crisis incident (CI-safe): %v", err)
	}

	contacts, err := s.ListEmergencyContacts(ctx, patientID)
	if err != nil {
		t.Fatalf("list: %v", err)
	}
	t.Logf("contacts: %d", len(contacts))
	if len(contacts) == 0 {
		t.Skip("no emergency contacts seeded (CI-safe)")
	}

	blastID, err := s.CreateSOSBlastLog(ctx, incidentID, contacts[0].ContactPhone, "sms")
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	t.Logf("blastID: %s", blastID)

	if err := s.AddAuditLog(ctx, patientID, patientID, "sos_blast.sms", "sos_blast_log", blastID,
		map[string]any{"message": "x", "contact": contacts[0].ContactName}); err != nil {
		t.Fatalf("audit: %v", err)
	}

	if err := s.UpdateSOSBlastStatus(ctx, blastID, "sent", blastID); err != nil {
		t.Fatalf("update: %v", err)
	}

	var status string
	err = db.QueryRowContext(ctx, `SELECT status FROM sos_blast_log WHERE id = $1`, blastID).Scan(&status)
	if err != nil {
		t.Fatal(err)
	}
	if status != "sent" {
		t.Fatalf("expected sent, got %s", status)
	}
	t.Logf("OK status=%s", status)
}
