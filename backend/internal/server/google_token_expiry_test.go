package server

import (
	"context"
	"database/sql"
	"fmt"
	"testing"
	"time"

	"malva/backend/internal/clock"
	"malva/backend/internal/store"
)

const expiryTestScope = "https://www.googleapis.com/auth/calendar.events"

// setGrantAge memundurkan tanggal grant refresh token ke [age] hari yang lalu
// agar umur izin bisa diuji tanpa memalsukan clock global.
func setGrantAge(t *testing.T, db *sql.DB, userID string, age time.Duration) {
	t.Helper()
	if _, err := db.ExecContext(context.Background(),
		`UPDATE google_oauth_tokens SET refresh_token_issued_at = $1 WHERE user_id = $2`,
		clock.Now().Add(-age), userID); err != nil {
		t.Fatalf("set umur grant: %v", err)
	}
}

// setupExpiryProfessional membuat profesional dengan Google tertaut + token
// Calendar lengkap, lalu mengembalikan server (TTL=7) dan user-nya.
func setupExpiryProfessional(t *testing.T, tag string) (*Server, *sql.DB, *store.Store, store.User) {
	t.Helper()
	db, st := openOnboardingTestStore(t)
	ctx := context.Background()
	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      "STR-" + tag + "-" + fmt.Sprint(time.Now().UnixNano()),
		SIPNumber:      "SIP-" + tag + "-" + fmt.Sprint(time.Now().UnixNano()),
	})
	t.Cleanup(func() { cleanupTestUsers(t, db, prof.ID) })

	srv := newOnboardingTestServer(db)
	srv.calendar = &fakeMeetCalendar{}
	srv.cfg.GoogleRefreshTokenTTLDays = 7

	subject := "sub-" + tag + "-" + fmt.Sprint(time.Now().UnixNano())
	if _, err := st.LinkGoogleIdentity(ctx, prof.ID, subject,
		tag+fmt.Sprint(time.Now().UnixNano())+"@example.test", false); err != nil {
		t.Fatalf("tautkan identitas: %v", err)
	}
	if err := st.UpsertGoogleToken(ctx, prof.ID, "refresh", "access",
		time.Now().Add(time.Hour), expiryTestScope, subject, true); err != nil {
		t.Fatalf("simpan token: %v", err)
	}
	return srv, db, st, prof
}

// TestMeetStatusReasonTokenExpiringSoon mengunci klasifikasi umur grant:
// umur >= TTL-1 hari -> token_hampir_kedaluwarsa (tetap ready untuk link),
// umur jauh dari batas -> ready, dan TTL 0 -> peringatan nonaktif (ready).
func TestMeetStatusReasonTokenExpiringSoon(t *testing.T) {
	srv, db, _, prof := setupExpiryProfessional(t, "EXP")
	ctx := context.Background()

	// Umur 3 hari dari TTL 7: masih jauh dari ambang 6 hari -> ready.
	setGrantAge(t, db, prof.ID, 3*24*time.Hour)
	if got := srv.meetStatusReason(ctx, prof.ID); got != meetReasonReady {
		t.Errorf("umur 3 hari: reason = %q, mau %q", got, meetReasonReady)
	}

	// Umur 6 hari: mencapai ambang TTL-1 -> hampir kedaluwarsa.
	setGrantAge(t, db, prof.ID, 6*24*time.Hour)
	if got := srv.meetStatusReason(ctx, prof.ID); got != meetReasonTokenExpiringSoon {
		t.Errorf("umur 6 hari: reason = %q, mau %q", got, meetReasonTokenExpiringSoon)
	}

	// Meski hampir kedaluwarsa, link Meet TETAP bisa dibuat.
	if !srv.googleCalendarReady(ctx, prof.ID) {
		t.Error("token_hampir_kedaluwarsa harus tetap siap membuat link Meet")
	}

	// TTL 0 -> peringatan nonaktif -> kembali ready.
	srv.cfg.GoogleRefreshTokenTTLDays = 0
	if got := srv.meetStatusReason(ctx, prof.ID); got != meetReasonReady {
		t.Errorf("TTL 0: reason = %q, mau %q", got, meetReasonReady)
	}
}

// TestRunGoogleTokenExpiryCheckSendsOncePerDay memastikan sweeper umur token
// mengirim TEPAT satu notifikasi untuk grant yang mendekati kedaluwarsa, dan
// pemanggilan kedua pada hari yang sama tidak menambah notifikasi (dedupe).
func TestRunGoogleTokenExpiryCheckSendsOncePerDay(t *testing.T) {
	srv, db, st, prof := setupExpiryProfessional(t, "WATCH")
	ctx := context.Background()

	setGrantAge(t, db, prof.ID, 6*24*time.Hour)

	n, err := srv.RunGoogleTokenExpiryCheck(ctx)
	if err != nil {
		t.Fatalf("pemeriksaan pertama: %v", err)
	}
	if n != 1 {
		t.Fatalf("notifikasi terkirim = %d, mau 1", n)
	}

	n2, err := srv.RunGoogleTokenExpiryCheck(ctx)
	if err != nil {
		t.Fatalf("pemeriksaan kedua: %v", err)
	}
	if n2 != 0 {
		t.Fatalf("pemeriksaan kedua = %d, mau 0 (dedupe hari yang sama)", n2)
	}

	items, err := st.ListNotifications(ctx, prof.ID, 50)
	if err != nil {
		t.Fatalf("daftar notifikasi: %v", err)
	}
	count := 0
	for _, it := range items {
		if it.Type == notifGoogleTokenExpiring {
			count++
		}
	}
	if count != 1 {
		t.Fatalf("jumlah notifikasi %q = %d, mau 1", notifGoogleTokenExpiring, count)
	}
}
