package store

import (
	"context"
	"strings"
	"time"

	"malva/backend/internal/clock"
)

func HasCalendarScope(scope string) bool {
	for _, s := range strings.Fields(scope) {
		if s == "https://www.googleapis.com/auth/calendar.events" || s == "https://www.googleapis.com/auth/calendar" {
			return true
		}
	}
	return false
}

// GoogleOAuthToken menyimpan token OAuth2 Google milik profesional untuk
// mengakses Calendar API (membuat/mengubah/membatalkan event Meet).
type GoogleOAuthToken struct {
	UserID        string
	RefreshToken  string
	AccessToken   string
	TokenExpiry   time.Time
	Scope         string
	GoogleSubject string
}

// UpsertGoogleToken menyimpan atau memperbarui token OAuth Google milik user.
// Menggunakan INSERT ... ON CONFLICT agar idempoten terhadap retry.
//
// Parameter newGrant membedakan dua jalur pemanggil:
//   - newGrant == true  -> penukaran authorization code (grant BARU). Tanggal
//     grant (refresh_token_issued_at) diisi clock.Now() karena refresh token
//     benar-benar diterbitkan ulang.
//   - newGrant == false -> auto-refresh access token (internal/google). Tanggal
//     grant LAMA DIPERTAHANKAN: memperbarui access token tidak memperpanjang
//     umur refresh token, sehingga umur izin tidak boleh ter-reset.
//
// updated_at selalu ditulis ulang pada tiap panggilan (untuk audit "kapan
// terakhir disentuh"), karena itu umur refresh token dihitung dari
// refresh_token_issued_at, bukan updated_at.
func (s *Store) UpsertGoogleToken(ctx context.Context, userID, refreshToken, accessToken string, expiry time.Time, scope, subject string, newGrant bool) error {
	now := clock.Now()
	const q = `INSERT INTO google_oauth_tokens (user_id, refresh_token, access_token, token_expiry, scope, updated_at, google_subject, refresh_token_issued_at)
		VALUES ($1, $2, $3, $4, $5, $6, NULLIF($7, ''), $8)
		ON CONFLICT (user_id) DO UPDATE SET
			refresh_token = EXCLUDED.refresh_token,
			access_token  = EXCLUDED.access_token,
			token_expiry  = EXCLUDED.token_expiry,
			scope         = EXCLUDED.scope,
			google_subject = EXCLUDED.google_subject,
			updated_at    = EXCLUDED.updated_at,
			refresh_token_issued_at = CASE WHEN $9 THEN EXCLUDED.refresh_token_issued_at
				ELSE google_oauth_tokens.refresh_token_issued_at END`
	_, err := s.db.ExecContext(ctx, q, userID, refreshToken, accessToken, expiry, scope, now, subject, now, newGrant)
	return err
}

// GetGoogleToken mengambil token OAuth Google milik user. Mengembalikan
// sql.ErrNoRows bila user belum pernah menautkan akun Google.
func (s *Store) GetGoogleToken(ctx context.Context, userID string) (*GoogleOAuthToken, error) {
	const q = `SELECT user_id, refresh_token, access_token, token_expiry, COALESCE(scope, ''), COALESCE(google_subject, '')
		FROM google_oauth_tokens WHERE user_id = $1`
	var tok GoogleOAuthToken
	err := s.db.QueryRowContext(ctx, q, userID).Scan(
		&tok.UserID, &tok.RefreshToken, &tok.AccessToken, &tok.TokenExpiry, &tok.Scope, &tok.GoogleSubject,
	)
	if err != nil {
		return nil, err
	}
	return &tok, nil
}

// GoogleTokenInfo ringkasan status tautan Google tanpa membocorkan token.
// Dipakai endpoint GET /v1/google/status.
type GoogleTokenInfo struct {
	GoogleSubject   string    `json:"-"`
	HasRefreshToken bool      `json:"has_refresh_token"`
	Scope           string    `json:"scope"`
	TokenExpiry     time.Time `json:"expires_at"`
	UpdatedAt       time.Time `json:"updated_at"`
	// RefreshTokenIssuedAt adalah kapan refresh token terakhir DITERBITKAN
	// (grant baru). Terpisah dari UpdatedAt yang ikut berubah saat access token
	// di-refresh. Dipakai menghitung umur izin Google (7 hari pada mode
	// Testing). Untuk baris lama, nilainya di-COALESCE dari updated_at.
	RefreshTokenIssuedAt time.Time `json:"refresh_token_issued_at"`
}

// GetGoogleTokenInfo mengambil ringkasan status token Google milik user.
// Mengembalikan sql.ErrNoRows bila user belum pernah menautkan akun.
func (s *Store) GetGoogleTokenInfo(ctx context.Context, userID string) (GoogleTokenInfo, error) {
	const q = `SELECT COALESCE(refresh_token, '') <> '', COALESCE(scope, ''),
			token_expiry, updated_at, COALESCE(google_subject, ''),
			COALESCE(refresh_token_issued_at, updated_at)
		FROM google_oauth_tokens WHERE user_id = $1`
	var info GoogleTokenInfo
	err := s.db.QueryRowContext(ctx, q, userID).Scan(
		&info.HasRefreshToken, &info.Scope, &info.TokenExpiry, &info.UpdatedAt, &info.GoogleSubject,
		&info.RefreshTokenIssuedAt,
	)
	if err != nil {
		return GoogleTokenInfo{}, err
	}
	return info, nil
}

// GoogleTokenGrant merangkum kapan refresh token Google seorang user
// diterbitkan. Dipakai sweeper umur token (RunGoogleTokenExpiryCheck).
type GoogleTokenGrant struct {
	UserID   string
	IssuedAt time.Time
}

// ListGoogleTokenGrantAges mengembalikan tanggal grant refresh token untuk
// SEMUA user yang masih punya refresh token (refresh_token tidak kosong).
// Baris lama tanpa refresh_token_issued_at memakai updated_at sebagai
// perkiraan (COALESCE), konsisten dengan GetGoogleTokenInfo.
func (s *Store) ListGoogleTokenGrantAges(ctx context.Context) ([]GoogleTokenGrant, error) {
	const q = `SELECT user_id, COALESCE(refresh_token_issued_at, updated_at)
		FROM google_oauth_tokens
		WHERE COALESCE(refresh_token, '') <> ''
		ORDER BY COALESCE(refresh_token_issued_at, updated_at) ASC`
	rows, err := s.db.QueryContext(ctx, q)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var out []GoogleTokenGrant
	for rows.Next() {
		var g GoogleTokenGrant
		if err := rows.Scan(&g.UserID, &g.IssuedAt); err != nil {
			return nil, err
		}
		out = append(out, g)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return out, nil
}

// DeleteGoogleToken menghapus token OAuth Google milik user (mis. saat
// unlink atau revokasi akses). Tidak error bila baris tidak ada.
func (s *Store) DeleteGoogleToken(ctx context.Context, userID string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM google_oauth_tokens WHERE user_id = $1`, userID)
	return err
}
