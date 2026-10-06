package store

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"
)

// ============================================================
// SSO + Administrasi pengguna
// ============================================================

// GetUserBySSO mencari pengguna berdasarkan provider SSO (mis. google)
// dan subject ID dari token. Mengabaikan akun yang dinonaktifkan.
func (s *Store) GetUserBySSO(ctx context.Context, provider, ssoID string) (User, error) {
	var user User
	provider = strings.ToLower(strings.TrimSpace(provider))
	ssoID = strings.TrimSpace(ssoID)
	if provider == "" || ssoID == "" {
		return User{}, errors.New("sso provider and sso id are required")
	}
	err := s.db.QueryRowContext(ctx, `
		SELECT id, email, role::text, display_name, phone, date_of_birth, gender, password_hash
		FROM users
		WHERE sso_provider = $1 AND sso_id = $2 AND disabled_at IS NULL
	`, provider, ssoID).
		Scan(&user.ID, &user.Email, &user.Role, &user.DisplayName, &user.Phone, &user.DateOfBirth, &user.Gender, &user.PasswordHash)
	return user, err
}

// LinkSSO menautkan akun SSO ke pengguna yang sudah ada (mis. daftar email
// dulu, lalu login Google dengan email yang sama).
func (s *Store) LinkSSO(ctx context.Context, userID, provider, ssoID string) error {
	provider = strings.ToLower(strings.TrimSpace(provider))
	ssoID = strings.TrimSpace(ssoID)
	if userID == "" || provider == "" || ssoID == "" {
		return errors.New("user_id, provider, and sso id are required")
	}
	res, err := s.db.ExecContext(ctx, `
		UPDATE users
		SET sso_provider = $2, sso_id = $3, updated_at = now()
		WHERE id = $1 AND disabled_at IS NULL
	`, userID, provider, ssoID)
	if err != nil {
		return err
	}
	aff, _ := res.RowsAffected()
	if aff == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// AdminUser adalah proyeksi pengguna untuk panel admin.
type AdminUser struct {
	ID          string     `json:"id"`
	Email       string     `json:"email"`
	Role        string     `json:"role"`
	DisplayName string     `json:"display_name"`
	Phone       *string    `json:"phone,omitempty"`
	DateOfBirth *string    `json:"date_of_birth,omitempty"`
	Gender      *string    `json:"gender,omitempty"`
	SSOProvider *string    `json:"sso_provider,omitempty"`
	DisabledAt  *time.Time `json:"disabled_at,omitempty"`
	CreatedAt   time.Time  `json:"created_at"`
}

// adminUserColumns adalah daftar kolom yang di-scan ke AdminUser (tanpa created_at).
const adminUserColumns = `id, email, role::text, display_name, phone, date_of_birth, gender, sso_provider, disabled_at`

// scanAdminUser meng-scan kolom adminUserColumns + created_at (di akhir) ke AdminUser.
func scanAdminUser(row interface{ Scan(...any) error }) (AdminUser, error) {
	var u AdminUser
	err := row.Scan(&u.ID, &u.Email, &u.Role, &u.DisplayName, &u.Phone, &u.DateOfBirth, &u.Gender, &u.SSOProvider, &u.DisabledAt, &u.CreatedAt)
	return u, err
}

// ListUsers mengembalikan semua pengguna (khusus admin), terbaru dulu.
func (s *Store) ListUsers(ctx context.Context, limit int) ([]AdminUser, error) {
	if limit <= 0 || limit > 500 {
		limit = 200
	}
	rows, err := s.db.QueryContext(ctx, `
		SELECT `+adminUserColumns+`, created_at
		FROM users
		ORDER BY created_at DESC
		LIMIT $1
	`, limit)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var out []AdminUser
	for rows.Next() {
		u, err := scanAdminUser(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}

// UpdateUserAdmin mengubah display name, role, status nonaktif, dan field
// profil (phone/date_of_birth/gender) pengguna (khusus admin).
// Nilai kosong/nil = tidak diubah.
func (s *Store) UpdateUserAdmin(ctx context.Context, userID, displayName, role, phone, dateOfBirth, gender string, disabled *bool) (AdminUser, error) {
	userID = strings.TrimSpace(userID)
	if userID == "" {
		return AdminUser{}, errors.New("user_id is required")
	}
	displayName = strings.TrimSpace(displayName)
	role = strings.ToLower(strings.TrimSpace(role))
	if role != "" && role != "patient" && role != "professional" && role != "admin" {
		return AdminUser{}, errors.New("role must be patient, professional, or admin")
	}
	if displayName != "" {
		if _, err := s.db.ExecContext(ctx, `UPDATE users SET display_name = $2, updated_at = now() WHERE id = $1`, userID, displayName); err != nil {
			return AdminUser{}, err
		}
	}
	if role != "" {
		if _, err := s.db.ExecContext(ctx, `UPDATE users SET role = $2::user_role, updated_at = now() WHERE id = $1`, userID, role); err != nil {
			return AdminUser{}, err
		}
	}
	if phone = normalizePhoneInput(phone); phone != "" {
		if _, err := s.db.ExecContext(ctx, `UPDATE users SET phone = $2, updated_at = now() WHERE id = $1`, userID, phone); err != nil {
			return AdminUser{}, err
		}
	}
	if dateOfBirth = normalizeDateInput(dateOfBirth); dateOfBirth != "" {
		if _, err := s.db.ExecContext(ctx, `UPDATE users SET date_of_birth = $2::date, updated_at = now() WHERE id = $1`, userID, dateOfBirth); err != nil {
			return AdminUser{}, err
		}
	}
	if gender = normalizeGenderInput(gender); gender != "" {
		if _, err := s.db.ExecContext(ctx, `UPDATE users SET gender = $2, updated_at = now() WHERE id = $1`, userID, gender); err != nil {
			return AdminUser{}, err
		}
	}
	if disabled != nil {
		if *disabled {
			if _, err := s.db.ExecContext(ctx, `UPDATE users SET disabled_at = now(), updated_at = now() WHERE id = $1`, userID); err != nil {
				return AdminUser{}, err
			}
		} else {
			if _, err := s.db.ExecContext(ctx, `UPDATE users SET disabled_at = NULL, updated_at = now() WHERE id = $1`, userID); err != nil {
				return AdminUser{}, err
			}
		}
	}
	var u AdminUser
	err := s.db.QueryRowContext(ctx, `
		SELECT `+adminUserColumns+`, created_at
		FROM users WHERE id = $1
	`, userID).Scan(&u.ID, &u.Email, &u.Role, &u.DisplayName, &u.Phone, &u.DateOfBirth, &u.Gender, &u.SSOProvider, &u.DisabledAt, &u.CreatedAt)
	return u, err
}

// DeleteUser menonaktifkan permanen satu pengguna (soft delete via disabled_at)
// agar riwayat klinis/audit tetap utuh. Akun yang dinonaktifkan tidak bisa
// login dan disembunyikan dari direktori dokter.
func (s *Store) DeleteUser(ctx context.Context, userID string) error {
	userID = strings.TrimSpace(userID)
	if userID == "" {
		return errors.New("user_id is required")
	}
	res, err := s.db.ExecContext(ctx, `UPDATE users SET disabled_at = now(), updated_at = now() WHERE id = $1 AND disabled_at IS NULL`, userID)
	if err != nil {
		return err
	}
	aff, _ := res.RowsAffected()
	if aff == 0 {
		return sql.ErrNoRows
	}
	return nil
}
