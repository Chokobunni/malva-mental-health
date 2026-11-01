package server

import (
	"context"
	"database/sql"
	"fmt"
	"io"
	"net/http"
	"strings"
	"sync/atomic"
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
// umur >= TTL-2 hari -> token_hampir_kedaluwarsa (tetap ready untuk link),
// umur jauh dari batas -> ready, dan TTL 0 -> peringatan nonaktif (ready).
func TestMeetStatusReasonTokenExpiringSoon(t *testing.T) {
	srv, db, _, prof := setupExpiryProfessional(t, "EXP")
	ctx := context.Background()

	// Umur 3 hari dari TTL 7: masih jauh dari ambang 5 hari -> ready.
	setGrantAge(t, db, prof.ID, 3*24*time.Hour)
	if got := srv.meetStatusReason(ctx, prof.ID); got != meetReasonReady {
		t.Errorf("umur 3 hari: reason = %q, mau %q", got, meetReasonReady)
	}

	// Umur 5 hari: mencapai ambang TTL-2 -> hampir kedaluwarsa.
	setGrantAge(t, db, prof.ID, 5*24*time.Hour)
	if got := srv.meetStatusReason(ctx, prof.ID); got != meetReasonTokenExpiringSoon {
		t.Errorf("umur 5 hari: reason = %q, mau %q", got, meetReasonTokenExpiringSoon)
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

// TestRunGoogleTokenRefreshRespectsInterval memastikan pemeliharaan tujuh hari
// tidak menggandakan request selama access token masih valid, tetapi expiry
// yang dekat selalu memicu refresh lebih awal. Rotasi dan tanggal grant diuji.
func TestRunGoogleTokenRefreshRespectsInterval(t *testing.T) {
	srv, db, _, prof := setupExpiryProfessional(t, "REFRESH")
	ctx := context.Background()
	// Kredensial Google wajib terisi agar job tidak no-op.
	srv.cfg.GoogleClientID = "test-client"
	srv.cfg.GoogleClientSecret = "test-secret"

	var tokenCalls int32
	oldTransport := http.DefaultTransport
	http.DefaultTransport = identityTestTransport(func(r *http.Request) (*http.Response, error) {
		if r.URL.Host != "oauth2.googleapis.com" || r.URL.Path != "/token" {
			return nil, fmt.Errorf("endpoint tak terduga: %s%s", r.URL.Host, r.URL.Path)
		}
		if err := r.ParseForm(); err != nil {
			return nil, err
		}
		if r.Form.Get("grant_type") != "refresh_token" {
			t.Error("grant_type harus refresh_token")
		}
		atomic.AddInt32(&tokenCalls, 1)
		return &http.Response{
			StatusCode: 200,
			Header:     http.Header{"Content-Type": []string{"application/json"}},
			Body: io.NopCloser(strings.NewReader(
				`{"access_token":"akses-baru","token_type":"Bearer","expires_in":3600,"refresh_token":"refresh-baru"}`)),
		}, nil
	})
	t.Cleanup(func() { http.DefaultTransport = oldTransport })

	// Batasi data uji ke akun ini; transport menghitung request akun ini saja.
	if _, err := db.ExecContext(ctx, `UPDATE google_oauth_tokens SET last_refreshed_at = $2,
		token_expiry = $3 WHERE user_id = $1`, prof.ID,
		clock.Now().Add(-7*24*time.Hour-time.Minute), clock.Now().Add(24*time.Hour)); err != nil {
		t.Fatalf("siapkan jadwal pemeliharaan: %v", err)
	}
	setGrantAge(t, db, prof.ID, 5*24*time.Hour)
	original, err := srv.store.GetGoogleTokenInfo(ctx, prof.ID)
	if err != nil {
		t.Fatal(err)
	}
	// Jalankan pertama: jadwal pemeliharaan terlewati meski access token valid.
	if _, err := srv.RunGoogleTokenRefresh(ctx); err != nil {
		t.Fatalf("refresh pertama: %v", err)
	}
	firstCalls := atomic.LoadInt32(&tokenCalls)
	if firstCalls < 1 {
		t.Fatalf("endpoint token tidak dipanggil pada refresh pertama (calls=%d)", firstCalls)
	}

	// last_refreshed_at harus terisi untuk pengguna ini.
	var refreshedAt sql.NullTime
	if err := db.QueryRowContext(ctx,
		`SELECT last_refreshed_at FROM google_oauth_tokens WHERE user_id = $1`, prof.ID).
		Scan(&refreshedAt); err != nil {
		t.Fatalf("baca last_refreshed_at: %v", err)
	}
	if !refreshedAt.Valid {
		t.Fatal("last_refreshed_at tidak tercatat setelah refresh")
	}

	token, err := srv.store.GetGoogleToken(ctx, prof.ID)
	if err != nil || token.RefreshToken != "refresh-baru" || token.AccessToken != "akses-baru" || !token.TokenExpiry.After(clock.Now()) {
		t.Fatalf("token hasil refresh/rotasi tidak tersimpan: %v", err)
	}
	info, err := srv.store.GetGoogleTokenInfo(ctx, prof.ID)
	if err != nil || !info.RefreshTokenIssuedAt.Equal(original.RefreshTokenIssuedAt) {
		t.Fatalf("tanggal grant berubah saat refresh: %v", err)
	}
	// Jalankan kedua: token masih valid -> TIDAK ada panggilan baru.
	before := atomic.LoadInt32(&tokenCalls)
	refreshed, err := srv.RunGoogleTokenRefresh(ctx)
	if err != nil {
		t.Fatalf("refresh kedua: %v", err)
	}
	if refreshed != 0 {
		t.Fatalf("refresh kedua me-refresh %d token, mau 0 (access token valid)", refreshed)
	}
	if after := atomic.LoadInt32(&tokenCalls); after != before {
		t.Fatalf("endpoint token dipanggil lagi ketika token valid (%d -> %d)", before, after)
	}
	// Enam hari masih di dalam jadwal tujuh hari; access token panjang valid.
	if _, err := db.ExecContext(ctx, `UPDATE google_oauth_tokens SET last_refreshed_at = $2,
		token_expiry = $3 WHERE user_id = $1`, prof.ID, clock.Now().Add(-6*24*time.Hour), clock.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	if _, err := srv.RunGoogleTokenRefresh(ctx); err != nil {
		t.Fatal(err)
	}
	if atomic.LoadInt32(&tokenCalls) != before {
		t.Fatal("pemeliharaan tidak boleh diulang sebelum tujuh hari")
	}
	// Expiry sepuluh menit lagi mengalahkan jadwal pemeliharaan.
	if _, err := db.ExecContext(ctx, `UPDATE google_oauth_tokens SET token_expiry = $2 WHERE user_id = $1`,
		prof.ID, clock.Now().Add(10*time.Minute)); err != nil {
		t.Fatal(err)
	}
	if _, err := srv.RunGoogleTokenRefresh(ctx); err != nil {
		t.Fatal(err)
	}
	if atomic.LoadInt32(&tokenCalls) != before+1 {
		t.Fatal("access token hampir habis harus di-refresh sebelum kedaluwarsa")
	}
}

// TestGoogleTokenWarnFrom memastikan ambang status tunggal tepat pada batas,
// dinonaktifkan untuk TTL nol, dan tidak menyala sejak grant untuk TTL pendek.
func TestGoogleTokenWarnFrom(t *testing.T) {
	now := clock.Now()
	for _, tc := range []struct {
		nama string
		ttl  time.Duration
		age  time.Duration
		want bool
	}{
		{"sebelum_ambang", 7 * 24 * time.Hour, 5*24*time.Hour - time.Second, false},
		{"tepat_ambang", 7 * 24 * time.Hour, 5 * 24 * time.Hour, true},
		{"dinonaktifkan", 0, 8 * 24 * time.Hour, false},
		{"ttl_pendek_baru", 24 * time.Hour, 0, false},
		{"ttl_pendek_setengah", 24 * time.Hour, 12 * time.Hour, true},
	} {
		t.Run(tc.nama, func(t *testing.T) {
			if got := googleTokenExpiringSoon(now.Add(-tc.age), now, tc.ttl); got != tc.want {
				t.Fatalf("status hampir kedaluwarsa = %v, mau %v", got, tc.want)
			}
		})
	}
}

// TestRunGoogleTokenRefreshRevokedTokenSilent memastikan token dicabut dihapus
// tanpa notifikasi dan tidak dikirim ulang ke Google pada tick berikutnya.
func TestRunGoogleTokenRefreshRevokedTokenSilent(t *testing.T) {
	srv, db, st, prof := setupExpiryProfessional(t, "REVOKED")
	srv.cfg.GoogleClientID = "test-client"
	srv.cfg.GoogleClientSecret = "test-secret"
	ctx := context.Background()
	if _, err := db.ExecContext(ctx, `UPDATE google_oauth_tokens SET token_expiry = $2 WHERE user_id = $1`,
		prof.ID, clock.Now().Add(-time.Minute)); err != nil {
		t.Fatal(err)
	}
	calls := 0
	old := http.DefaultTransport
	http.DefaultTransport = identityTestTransport(func(r *http.Request) (*http.Response, error) {
		calls++
		return &http.Response{StatusCode: 400,
			Header: http.Header{"Content-Type": []string{"application/json"}},
			Body:   io.NopCloser(strings.NewReader(`{"error":"invalid_grant"}`))}, nil
	})
	t.Cleanup(func() { http.DefaultTransport = old })
	for i := 0; i < 2; i++ {
		if _, err := srv.RunGoogleTokenRefresh(ctx); err != nil {
			t.Fatal(err)
		}
	}
	if calls != 1 {
		t.Fatalf("token ditolak harus dicoba sekali, dapat %d", calls)
	}
	if _, err := st.GetGoogleToken(ctx, prof.ID); err != sql.ErrNoRows {
		t.Fatalf("token dicabut belum dihapus: %v", err)
	}
	items, err := st.ListNotifications(ctx, prof.ID, 50)
	if err != nil || len(items) != 0 {
		t.Fatalf("refresh ditolak harus senyap: notifikasi=%d, galat=%v", len(items), err)
	}
}
