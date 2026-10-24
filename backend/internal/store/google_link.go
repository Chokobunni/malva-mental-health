package store

import (
	"context"
	"database/sql"
	"errors"
	"strings"
)

// CanAbsorbGoogleLink melaporkan apakah tautan Google milik akun placeholder
// bisa dipindahkan ke akun target: target belum punya SSO apa pun, dan akun
// placeholder benar-benar akun Google sementara ("g-...").
func (s *Store) CanAbsorbGoogleLink(ctx context.Context, targetUserID, placeholderUserID string) (bool, error) {
	targetUserID = strings.TrimSpace(targetUserID)
	placeholderUserID = strings.TrimSpace(placeholderUserID)
	if targetUserID == "" || placeholderUserID == "" || targetUserID == placeholderUserID {
		return false, nil
	}
	// Satu query menilai semua syarat: target tanpa SSO, placeholder bertautan
	// Google yang valid, professional_id placeholder masih sementara ("g-..."),
	// dan keduanya berperan profesional.
	const q = `SELECT
	  COALESCE(t.sso_provider, '') = '',
	  COALESCE(p.sso_provider, '') = 'google' AND COALESCE(p.sso_id, '') <> '',
	  COALESCE(pp.professional_id LIKE 'g-%', false),
	  t.role = 'professional', p.role = 'professional'
	FROM users t
	JOIN users p ON p.id = $2
	LEFT JOIN professional_profiles pp ON pp.user_id = p.id
	WHERE t.id = $1`
	var (
		targetTanpaSSO       bool
		placeholderGoogle    bool
		placeholderSementara bool
		targetProfesional    bool
		placeholderProfesion bool
	)
	err := s.db.QueryRowContext(ctx, q, targetUserID, placeholderUserID).Scan(
		&targetTanpaSSO, &placeholderGoogle, &placeholderSementara, &targetProfesional, &placeholderProfesion)
	if err != nil {
		return false, err
	}
	return targetTanpaSSO && placeholderGoogle && placeholderSementara && targetProfesional && placeholderProfesion, nil
}

// MoveGoogleLink memindahkan tautan Google dari akun placeholder ke akun
// target lalu menonaktifkan placeholder, dalam satu transaksi.
//
// Urutannya penting: tautan harus dilepas dari placeholder LEBIH DULU karena
// tabel users memiliki partial UNIQUE index pada (sso_provider, sso_id).
func (s *Store) MoveGoogleLink(ctx context.Context, targetUserID, placeholderUserID string) error {
	targetUserID = strings.TrimSpace(targetUserID)
	placeholderUserID = strings.TrimSpace(placeholderUserID)
	if targetUserID == "" || placeholderUserID == "" || targetUserID == placeholderUserID {
		return errors.New("target dan placeholder user wajib diisi dan berbeda")
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	// 1) Baca tautan SSO placeholder sambil mengunci barisnya.
	var provider, ssoID sql.NullString
	if err := tx.QueryRowContext(ctx,
		`SELECT sso_provider, sso_id FROM users WHERE id = $1 FOR UPDATE`,
		placeholderUserID).Scan(&provider, &ssoID); err != nil {
		return err
	}
	// 2) Hanya tautan Google yang non-kosong yang boleh dipindahkan.
	if !provider.Valid || strings.ToLower(strings.TrimSpace(provider.String)) != "google" ||
		!ssoID.Valid || strings.TrimSpace(ssoID.String) == "" {
		return errors.New("akun placeholder tidak memiliki tautan Google yang bisa dipindahkan")
	}
	// 3) Lepas tautan dari placeholder agar unique index tidak bentrok.
	if _, err := tx.ExecContext(ctx,
		`UPDATE users SET sso_provider = NULL, sso_id = NULL, updated_at = now() WHERE id = $1`,
		placeholderUserID); err != nil {
		return err
	}
	// 4) Tautkan Google ke akun target.
	if _, err := tx.ExecContext(ctx,
		`UPDATE users SET sso_provider = 'google', sso_id = $2, updated_at = now() WHERE id = $1`,
		targetUserID, strings.TrimSpace(ssoID.String)); err != nil {
		return err
	}
	// 5) Nonaktifkan akun placeholder supaya tidak bisa dipakai lagi.
	if _, err := tx.ExecContext(ctx,
		`UPDATE users SET disabled_at = now(), updated_at = now() WHERE id = $1`,
		placeholderUserID); err != nil {
		return err
	}
	// 6) Commit.
	return tx.Commit()
}
