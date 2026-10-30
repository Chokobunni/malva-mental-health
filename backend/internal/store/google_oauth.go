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
func (s *Store) UpsertGoogleToken(ctx context.Context, userID, refreshToken, accessToken string, expiry time.Time, scope, subject string) error {
	const q = `INSERT INTO google_oauth_tokens (user_id, refresh_token, access_token, token_expiry, scope, updated_at, google_subject)
		VALUES ($1, $2, $3, $4, $5, $6, NULLIF($7, ''))
		ON CONFLICT (user_id) DO UPDATE SET
			refresh_token = EXCLUDED.refresh_token,
			access_token  = EXCLUDED.access_token,
			token_expiry  = EXCLUDED.token_expiry,
			scope         = EXCLUDED.scope,
			google_subject = EXCLUDED.google_subject,
			updated_at    = EXCLUDED.updated_at`
	_, err := s.db.ExecContext(ctx, q, userID, refreshToken, accessToken, expiry, scope, clock.Now(), subject)
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
}

// GetGoogleTokenInfo mengambil ringkasan status token Google milik user.
// Mengembalikan sql.ErrNoRows bila user belum pernah menautkan akun.
func (s *Store) GetGoogleTokenInfo(ctx context.Context, userID string) (GoogleTokenInfo, error) {
	const q = `SELECT COALESCE(refresh_token, '') <> '', COALESCE(scope, ''),
			token_expiry, updated_at, COALESCE(google_subject, '')
		FROM google_oauth_tokens WHERE user_id = $1`
	var info GoogleTokenInfo
	err := s.db.QueryRowContext(ctx, q, userID).Scan(
		&info.HasRefreshToken, &info.Scope, &info.TokenExpiry, &info.UpdatedAt, &info.GoogleSubject,
	)
	if err != nil {
		return GoogleTokenInfo{}, err
	}
	return info, nil
}

// DeleteGoogleToken menghapus token OAuth Google milik user (mis. saat
// unlink atau revokasi akses). Tidak error bila baris tidak ada.
func (s *Store) DeleteGoogleToken(ctx context.Context, userID string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM google_oauth_tokens WHERE user_id = $1`, userID)
	return err
}
