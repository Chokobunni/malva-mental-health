package store

import (
	"context"
	"time"
)

// GoogleOAuthToken menyimpan token OAuth2 Google milik profesional untuk
// mengakses Calendar API (membuat/mengubah/membatalkan event Meet).
type GoogleOAuthToken struct {
	UserID       string
	RefreshToken string
	AccessToken  string
	TokenExpiry  time.Time
	Scope        string
}

// UpsertGoogleToken menyimpan atau memperbarui token OAuth Google milik user.
// Menggunakan INSERT ... ON CONFLICT agar idempoten terhadap retry.
func (s *Store) UpsertGoogleToken(ctx context.Context, userID, refreshToken, accessToken string, expiry time.Time, scope string) error {
	const q = `INSERT INTO google_oauth_tokens (user_id, refresh_token, access_token, token_expiry, scope, updated_at)
		VALUES ($1, $2, $3, $4, $5, now())
		ON CONFLICT (user_id) DO UPDATE SET
			refresh_token = EXCLUDED.refresh_token,
			access_token  = EXCLUDED.access_token,
			token_expiry  = EXCLUDED.token_expiry,
			scope         = EXCLUDED.scope,
			updated_at    = now()`
	_, err := s.db.ExecContext(ctx, q, userID, refreshToken, accessToken, expiry, scope)
	return err
}

// GetGoogleToken mengambil token OAuth Google milik user. Mengembalikan
// sql.ErrNoRows bila user belum pernah menautkan akun Google.
func (s *Store) GetGoogleToken(ctx context.Context, userID string) (*GoogleOAuthToken, error) {
	const q = `SELECT user_id, refresh_token, access_token, token_expiry, COALESCE(scope, '')
		FROM google_oauth_tokens WHERE user_id = $1`
	var tok GoogleOAuthToken
	err := s.db.QueryRowContext(ctx, q, userID).Scan(
		&tok.UserID, &tok.RefreshToken, &tok.AccessToken, &tok.TokenExpiry, &tok.Scope,
	)
	if err != nil {
		return nil, err
	}
	return &tok, nil
}

// DeleteGoogleToken menghapus token OAuth Google milik user (mis. saat
// unlink atau revokasi akses). Tidak error bila baris tidak ada.
func (s *Store) DeleteGoogleToken(ctx context.Context, userID string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM google_oauth_tokens WHERE user_id = $1`, userID)
	return err
}
