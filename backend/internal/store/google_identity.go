package store

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgconn"

	"malva/backend/internal/clock"
)

var (
	ErrGoogleAlreadyLinked         = errors.New("Google identity belongs to another account")
	ErrGoogleIdentityBound         = errors.New("account is already bound to a different Google identity")
	ErrEmailOwnedByOther           = errors.New("email belongs to another account")
	ErrProfessionalIdentifierTaken = errors.New("STR or SIP is already registered to another professional")
	ErrGoogleNotLinked             = errors.New("account has no linked Google identity")
)

func IsUniqueViolation(err error) bool {
	var pgErr *pgconn.PgError
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

func googleIdentityWriteError(err error) error {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		if pgErr.ConstraintName == "users_sso_unique" {
			return ErrGoogleAlreadyLinked
		}
		return ErrEmailOwnedByOther
	}
	return err
}

// Serialize email ownership checks across users.email and users.sso_email.
// CreateUser and LinkGoogleIdentity are the only runtime writers of these fields.
func lockIdentityOwnership(ctx context.Context, tx *sql.Tx) error {
	_, err := tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(681416201)`)
	return err
}

func checkEmailOwnership(ctx context.Context, tx *sql.Tx, email, excludeUserID string) error {
	if email == "" {
		return nil
	}
	var exists bool
	err := tx.QueryRowContext(ctx, `SELECT EXISTS (
		SELECT 1 FROM users WHERE id <> COALESCE(NULLIF($2, '')::uuid, '00000000-0000-0000-0000-000000000000'::uuid)
		AND (lower(btrim(email)) = $1 OR lower(btrim(sso_email)) = $1)
	)`, email, excludeUserID).Scan(&exists)
	if err != nil {
		return err
	}
	if exists {
		return ErrEmailOwnedByOther
	}
	return nil
}

// Each identifier is unique within its own kind, including disabled owners.
func (s *Store) ProfessionalIdentifierTaken(ctx context.Context, kind, identifier, excludeUserID string) (bool, error) {
	identifier = strings.ToLower(strings.TrimSpace(identifier))
	if identifier == "" {
		return false, nil
	}
	var taken bool
	err := s.db.QueryRowContext(ctx, `SELECT EXISTS (
		SELECT 1 FROM professional_credentials
		WHERE user_id <> COALESCE(NULLIF($3, '')::uuid, '00000000-0000-0000-0000-000000000000'::uuid)
		AND (($1 = 'str' AND lower(btrim(str_number)) = $2)
		  OR ($1 = 'sip' AND lower(btrim(sip_number)) = $2))
	)`, kind, identifier, strings.TrimSpace(excludeUserID)).Scan(&taken)
	return taken, err
}

type GoogleIdentity struct {
	Linked             bool       `json:"linked"`
	Subject            string     `json:"-"`
	Email              string     `json:"email,omitempty"`
	LinkedAt           *time.Time `json:"linked_at,omitempty"`
	EmailIsPlaceholder bool       `json:"email_is_placeholder"`
}

func (s *Store) GetGoogleIdentity(ctx context.Context, userID string) (GoogleIdentity, error) {
	var provider, subject, email sql.NullString
	var linkedAt sql.NullTime
	var accountEmail string
	err := s.db.QueryRowContext(ctx, `SELECT sso_provider, sso_id, sso_email, sso_linked_at, email
		FROM users WHERE id = $1 AND disabled_at IS NULL`, userID).
		Scan(&provider, &subject, &email, &linkedAt, &accountEmail)
	if err != nil {
		return GoogleIdentity{}, err
	}
	out := GoogleIdentity{
		Linked:             provider.String == "google" && strings.TrimSpace(subject.String) != "",
		EmailIsPlaceholder: IsPlaceholderProfessionalEmail(accountEmail),
	}
	if out.Linked {
		out.Subject = subject.String
		out.Email = email.String
		if linkedAt.Valid {
			out.LinkedAt = &linkedAt.Time
		}
	}
	return out, nil
}

// A verified Google identity may be attached, but never replace another subject.
// Placeholder professional emails are upgraded without changing the user UUID.
func (s *Store) LinkGoogleIdentity(ctx context.Context, userID, subject, email string, replaceEmail bool) (GoogleIdentity, error) {
	subject = strings.TrimSpace(subject)
	email = strings.ToLower(strings.TrimSpace(email))
	if strings.TrimSpace(userID) == "" || subject == "" || email == "" {
		return GoogleIdentity{}, errors.New("user, Google subject and verified email are required")
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return GoogleIdentity{}, err
	}
	defer func() { _ = tx.Rollback() }()
	if err := lockIdentityOwnership(ctx, tx); err != nil {
		return GoogleIdentity{}, err
	}
	var provider, existingSubject sql.NullString
	var accountEmail, role string
	var linkedAt sql.NullTime
	err = tx.QueryRowContext(ctx, `SELECT sso_provider, sso_id, email, role::text, sso_linked_at
		FROM users WHERE id = $1 AND disabled_at IS NULL FOR UPDATE`, userID).
		Scan(&provider, &existingSubject, &accountEmail, &role, &linkedAt)
	if err != nil {
		return GoogleIdentity{}, err
	}
	if (provider.String != "" && provider.String != "google") ||
		(existingSubject.String != "" && existingSubject.String != subject) {
		return GoogleIdentity{}, ErrGoogleIdentityBound
	}
	var other bool
	if err := tx.QueryRowContext(ctx, `SELECT EXISTS (SELECT 1 FROM users
		WHERE sso_provider = 'google' AND sso_id = $1 AND id <> $2::uuid)`, subject, userID).Scan(&other); err != nil {
		return GoogleIdentity{}, err
	}
	if other {
		return GoogleIdentity{}, ErrGoogleAlreadyLinked
	}
	if err := checkEmailOwnership(ctx, tx, email, userID); err != nil {
		return GoogleIdentity{}, err
	}
	now := clock.Now().Truncate(time.Microsecond)
	if !linkedAt.Valid {
		linkedAt = sql.NullTime{Time: now, Valid: true}
	}
	// replace_email is accepted for legacy callers; real account emails never change.
	if role == "professional" && IsPlaceholderProfessionalEmail(accountEmail) {
		accountEmail = email
	}
	_, err = tx.ExecContext(ctx, `UPDATE users SET sso_provider = 'google', sso_id = $2,
		sso_email = $3, sso_linked_at = $4, email = $5, updated_at = $6 WHERE id = $1`,
		userID, subject, email, linkedAt.Time, accountEmail, now)
	if err != nil {
		return GoogleIdentity{}, googleIdentityWriteError(err)
	}
	if err := tx.Commit(); err != nil {
		return GoogleIdentity{}, googleIdentityWriteError(err)
	}
	return GoogleIdentity{Linked: true, Subject: subject, Email: email, LinkedAt: &linkedAt.Time,
		EmailIsPlaceholder: IsPlaceholderProfessionalEmail(accountEmail)}, nil
}

// UnbindGoogleIdentity melepas tautan Google tanpa mengubah UUID user.
//
// Perilaku (dalam SATU transaksi, di bawah advisory lock kepemilikan email):
//  1. Mengunci baris user lalu membaca status SSO, email akun, role, dan
//     professional_id (bila ada).
//  2. Menolak bila akun tidak tertaut ke Google (ErrGoogleNotLinked).
//  3. Memulihkan email placeholder profesional bila email akun saat ini sama
//     dengan email Google yang dilepas — supaya Gmail itu bebas dipakai akun
//     Malva lain. Bila placeholder sudah dipakai akun lain, email lama
//     dipertahankan (unbind tidak boleh gagal hanya karena bentrok email).
//  4. Menghapus tautan SSO (sso_* = NULL) dan, bila diminta, mengganti
//     password_hash dalam UPDATE yang sama (akun Google-only belum punya
//     password yang bisa dipakai).
//  5. Menghapus token OAuth Google agar Google Meet ikut nonaktif.
//
// newPasswordHash kosong berarti password tidak diubah.
func (s *Store) UnbindGoogleIdentity(ctx context.Context, userID, newPasswordHash string) (GoogleIdentity, error) {
	if strings.TrimSpace(userID) == "" {
		return GoogleIdentity{}, errors.New("user is required")
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return GoogleIdentity{}, err
	}
	defer func() { _ = tx.Rollback() }()
	if err := lockIdentityOwnership(ctx, tx); err != nil {
		return GoogleIdentity{}, err
	}
	var provider, ssoID sql.NullString
	var ssoEmail, accountEmail, role, profID string
	err = tx.QueryRowContext(ctx, `SELECT u.sso_provider, u.sso_id, COALESCE(u.sso_email,''), u.email,
			u.role::text, COALESCE(pp.professional_id,'')
		FROM users u
		LEFT JOIN professional_profiles pp ON pp.user_id = u.id
		WHERE u.id = $1 AND u.disabled_at IS NULL
		FOR UPDATE OF u`, userID).
		Scan(&provider, &ssoID, &ssoEmail, &accountEmail, &role, &profID)
	if err != nil {
		return GoogleIdentity{}, err
	}
	if provider.String != "google" || strings.TrimSpace(ssoID.String) == "" {
		return GoogleIdentity{}, ErrGoogleNotLinked
	}
	// Default: pertahankan email akun apa adanya. Hanya placeholder profesional
	// yang bisa dipulihkan, dan hanya bila email akun saat ini memang Gmail
	// yang dilepas (bukan Gmail lain yang sengaja dipakai akun lama).
	restoredEmail := accountEmail
	if role == "professional" &&
		strings.EqualFold(accountEmail, ssoEmail) &&
		profID != "" && !strings.HasPrefix(profID, "g-") {
		candidate := profID + "@professional.malva.local"
		if err := checkEmailOwnership(ctx, tx, candidate, userID); err != nil {
			if !errors.Is(err, ErrEmailOwnedByOther) {
				return GoogleIdentity{}, err
			}
			// Placeholder sudah dipakai akun lain → pertahankan email lama.
		} else {
			restoredEmail = candidate
		}
	}
	now := clock.Now().Truncate(time.Microsecond)
	if newPasswordHash != "" {
		_, err = tx.ExecContext(ctx, `UPDATE users SET sso_provider = NULL, sso_id = NULL,
			sso_email = NULL, sso_linked_at = NULL, email = $2, updated_at = $3, password_hash = $4
			WHERE id = $1`, userID, restoredEmail, now, newPasswordHash)
	} else {
		_, err = tx.ExecContext(ctx, `UPDATE users SET sso_provider = NULL, sso_id = NULL,
			sso_email = NULL, sso_linked_at = NULL, email = $2, updated_at = $3
			WHERE id = $1`, userID, restoredEmail, now)
	}
	if err != nil {
		return GoogleIdentity{}, googleIdentityWriteError(err)
	}
	if _, err := tx.ExecContext(ctx, `DELETE FROM google_oauth_tokens WHERE user_id = $1`, userID); err != nil {
		return GoogleIdentity{}, err
	}
	if err := tx.Commit(); err != nil {
		return GoogleIdentity{}, err
	}
	return GoogleIdentity{Linked: false, EmailIsPlaceholder: IsPlaceholderProfessionalEmail(restoredEmail)}, nil
}

func IsPlaceholderProfessionalEmail(email string) bool {
	return strings.HasSuffix(strings.ToLower(strings.TrimSpace(email)), "@professional.malva.local")
}
