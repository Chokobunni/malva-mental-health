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
// updated_at dan last_refreshed_at selalu ditulis atomik dengan token/expiry.
// Umur refresh token tetap dihitung dari refresh_token_issued_at, bukan waktu
// refresh access token. Job berkala memakai SaveGoogleTokenRefresh agar tidak
// menimpa consent yang berubah saat request Google berjalan.
func (s *Store) UpsertGoogleToken(ctx context.Context, userID, refreshToken, accessToken string, expiry time.Time, scope, subject string, newGrant bool) error {
	now := clock.Now()
	const q = `INSERT INTO google_oauth_tokens (user_id, refresh_token, access_token, token_expiry, scope, updated_at, google_subject, refresh_token_issued_at, last_refreshed_at)
		VALUES ($1, $2, $3, $4, $5, $6, NULLIF($7, ''), $8, $6)
		ON CONFLICT (user_id) DO UPDATE SET
			refresh_token = EXCLUDED.refresh_token,
			access_token  = EXCLUDED.access_token,
			token_expiry  = EXCLUDED.token_expiry,
			scope         = EXCLUDED.scope,
			google_subject = EXCLUDED.google_subject,
			updated_at    = EXCLUDED.updated_at,
			last_refreshed_at = EXCLUDED.last_refreshed_at,
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

// DeleteGoogleToken menghapus token OAuth Google milik user (mis. saat
// unlink atau revokasi akses). Tidak error bila baris tidak ada.
func (s *Store) DeleteGoogleToken(ctx context.Context, userID string) error {
	_, err := s.db.ExecContext(ctx, `DELETE FROM google_oauth_tokens WHERE user_id = $1`, userID)
	return err
}

// GoogleTokenRefreshCandidate merangkum satu token yang perlu di-refresh oleh
// job auto-refresh (RunGoogleTokenRefresh): user, refresh token, dan metadata
// yang diperlukan untuk memanggil endpoint token Google lalu menyimpannya
// kembali lewat SaveGoogleTokenRefresh.
type GoogleTokenRefreshCandidate struct {
	UserID        string
	RefreshToken  string
	Scope         string
	GoogleSubject string
}

// ListGoogleTokensDueForRefresh mengambil profesional aktif yang identitas
// Google-nya masih cocok. Token jatuh tempo saat access token hampir habis
// (expiryBefore), atau pemeliharaan tujuh hari terlewati (maintenanceBefore).
// Refresh access token yang diperlukan tidak menunggu jadwal pemeliharaan.
func (s *Store) ListGoogleTokensDueForRefresh(ctx context.Context, maintenanceBefore, expiryBefore time.Time) ([]GoogleTokenRefreshCandidate, error) {
	const q = `SELECT t.user_id, t.refresh_token, COALESCE(t.scope, ''), t.google_subject
		FROM google_oauth_tokens t
		JOIN users u ON u.id = t.user_id
		WHERE u.role = 'professional' AND u.disabled_at IS NULL
		  AND u.sso_provider = 'google' AND u.sso_id = t.google_subject
		  AND COALESCE(t.refresh_token, '') <> ''
		  AND (t.last_refreshed_at IS NULL OR t.last_refreshed_at <= $1 OR t.token_expiry <= $2)
		ORDER BY t.token_expiry ASC`
	rows, err := s.db.QueryContext(ctx, q, maintenanceBefore, expiryBefore)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var out []GoogleTokenRefreshCandidate
	for rows.Next() {
		var c GoogleTokenRefreshCandidate
		if err := rows.Scan(&c.UserID, &c.RefreshToken, &c.Scope, &c.GoogleSubject); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	if err := rows.Err(); err != nil {
		return nil, err
	}
	return out, nil
}

// SaveGoogleTokenRefresh menyimpan hasil refresh dan waktunya secara atomik,
// tanpa menghidupkan kembali token yang sudah dilepas atau menimpa consent baru.
// Tanggal grant dipertahankan: refresh tidak menghapus batas Testing tujuh hari.
func (s *Store) SaveGoogleTokenRefresh(ctx context.Context, userID, previousRefresh, refreshToken, accessToken string, expiry time.Time) (bool, error) {
	result, err := s.db.ExecContext(ctx, `UPDATE google_oauth_tokens t
		SET refresh_token = $3, access_token = $4, token_expiry = $5,
		    last_refreshed_at = $6, updated_at = $6
		WHERE t.user_id = $1 AND t.refresh_token = $2
		  AND EXISTS (SELECT 1 FROM users u WHERE u.id = t.user_id
		    AND u.role = 'professional' AND u.disabled_at IS NULL
		    AND u.sso_provider = 'google' AND u.sso_id = t.google_subject)`,
		userID, previousRefresh, refreshToken, accessToken, expiry, clock.Now())
	if err != nil {
		return false, err
	}
	n, err := result.RowsAffected()
	return n == 1, err
}

// DeleteGoogleTokenIfUnchanged membuang token yang ditolak permanen hanya bila
// belum diganti oleh consent baru selama request refresh berjalan.
func (s *Store) DeleteGoogleTokenIfUnchanged(ctx context.Context, userID, refreshToken string) error {
	_, err := s.db.ExecContext(ctx,
		`DELETE FROM google_oauth_tokens WHERE user_id = $1 AND refresh_token = $2`, userID, refreshToken)
	return err
}
