package store

import (
	"context"
	"database/sql"
	"fmt"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"

	"malva/backend/internal/clock"
)

const grantTestScope = "https://www.googleapis.com/auth/calendar.events"

// openGoogleGrantTestStore membuka store untuk test umur grant refresh token.
// Skip bila DB tidak tersedia atau migrasi 024 (refresh_token_issued_at) belum
// diterapkan (CI-safe).
func openGoogleGrantTestStore(t *testing.T) (*Store, *sql.DB) {
	t.Helper()
	dsn := testDatabaseDSN(t)
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Skipf("db unavailable: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		_ = db.Close()
		t.Skipf("db unreachable (CI-safe): %v", err)
	}
	var n int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM information_schema.columns
		WHERE table_schema = current_schema() AND table_name = 'google_oauth_tokens'
		  AND column_name = 'refresh_token_issued_at'`).Scan(&n); err != nil || n < 1 {
		_ = db.Close()
		t.Skip("migrasi 024 (google_oauth_tokens.refresh_token_issued_at) belum diterapkan (CI-safe)")
	}
	t.Cleanup(func() { _ = db.Close() })
	return New(db), db
}

// TestUpsertGoogleTokenGrantTracking membuktikan inti Tugas 2: tanggal grant
// refresh token HANYA berubah saat grant baru (newGrant=true), dan DIPERTAHANKAN
// saat auto-refresh access token (newGrant=false). Tanpa ini, umur izin Google
// akan ter-reset tiap kali access token di-refresh sehingga peringatan 7 hari
// tidak pernah muncul.
func TestUpsertGoogleTokenGrantTracking(t *testing.T) {
	s, db := openGoogleGrantTestStore(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	suffix := fmt.Sprintf("%d", clock.Now().UnixNano())
	var userID string
	if err := db.QueryRowContext(ctx, `INSERT INTO users (email, password_hash, role, display_name)
		VALUES ($1,'test-hash','professional','Prof Grant') RETURNING id::text`,
		"grant-"+suffix+"@malva.test").Scan(&userID); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	t.Cleanup(func() { cleanupTestUsers(t, db, userID) })
	subject := "sub-grant-" + suffix

	// 1. Grant baru menulis tanggal grant.
	if err := s.UpsertGoogleToken(ctx, userID, "refresh-1", "access-1",
		clock.Now().Add(time.Hour), grantTestScope, subject, true); err != nil {
		t.Fatalf("grant baru: %v", err)
	}
	info1, err := s.GetGoogleTokenInfo(ctx, userID)
	if err != nil {
		t.Fatalf("info setelah grant: %v", err)
	}
	if info1.RefreshTokenIssuedAt.IsZero() {
		t.Fatal("refresh_token_issued_at kosong setelah grant baru")
	}

	// Mundurkan tanggal grant ke 2 hari lalu agar perbedaan auto-refresh jelas.
	oldIssued := clock.Now().Add(-48 * time.Hour).Truncate(time.Microsecond)
	if _, err := db.ExecContext(ctx,
		`UPDATE google_oauth_tokens SET refresh_token_issued_at = $1 WHERE user_id = $2`,
		oldIssued, userID); err != nil {
		t.Fatalf("mundurkan grant: %v", err)
	}

	// 2. Auto-refresh access token (newGrant=false): tanggal grant TETAP.
	if err := s.UpsertGoogleToken(ctx, userID, "refresh-1", "access-2",
		clock.Now().Add(2*time.Hour), grantTestScope, subject, false); err != nil {
		t.Fatalf("auto-refresh: %v", err)
	}
	info2, err := s.GetGoogleTokenInfo(ctx, userID)
	if err != nil {
		t.Fatalf("info setelah auto-refresh: %v", err)
	}
	if !info2.RefreshTokenIssuedAt.Equal(oldIssued) {
		t.Errorf("grant berubah saat newGrant=false: dapat %v, mau %v",
			info2.RefreshTokenIssuedAt, oldIssued)
	}

	// 3. Grant baru lagi (newGrant=true): tanggal grant MAJU.
	if err := s.UpsertGoogleToken(ctx, userID, "refresh-2", "access-3",
		clock.Now().Add(time.Hour), grantTestScope, subject, true); err != nil {
		t.Fatalf("grant ulang: %v", err)
	}
	info3, err := s.GetGoogleTokenInfo(ctx, userID)
	if err != nil {
		t.Fatalf("info setelah grant ulang: %v", err)
	}
	if !info3.RefreshTokenIssuedAt.After(oldIssued) {
		t.Errorf("grant baru harus lebih baru dari %v, dapat %v",
			oldIssued, info3.RefreshTokenIssuedAt)
	}
}
