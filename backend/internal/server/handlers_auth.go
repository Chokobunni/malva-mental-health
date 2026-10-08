package server

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"net/http"
	"strings"

	"malva/backend/internal/auth"
	"malva/backend/internal/store"

	"google.golang.org/api/idtoken"
)

type googleAuthRequest struct {
	IDToken string `json:"id_token"`
	Role    string `json:"role"`
}

// googleLogin menukar Google ID Token (dari aplikasi Flutter via Google
// Sign-In) menjadi sesi Malva. Alurnya: cari akun by SSO -> tautkan bila
// email sudah ada -> buat akun baru bila belum ada.
func (s *Server) googleLogin(w http.ResponseWriter, r *http.Request) {
	var req googleAuthRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if strings.TrimSpace(req.IDToken) == "" {
		writeError(w, http.StatusBadRequest, errors.New("id_token wajib diisi."))
		return
	}
	if s.cfg.GoogleClientID == "" {
		writeError(w, http.StatusNotImplemented, errors.New("Login Google belum dikonfigurasi di server. Hubungi admin untuk mengisi MALVA_GOOGLE_CLIENT_ID."))
		return
	}
	payload, err := idtoken.Validate(r.Context(), strings.TrimSpace(req.IDToken), s.cfg.GoogleClientID)
	if err != nil {
		s.secLogger.LogAuthFailure(r, "google", "invalid id_token")
		writeError(w, http.StatusUnauthorized, errors.New("Token Google tidak valid atau kedaluwarsa. Silakan coba lagi."))
		return
	}
	if payload.Subject == "" {
		writeError(w, http.StatusUnauthorized, errors.New("Token Google tidak valid atau kedaluwarsa. Silakan coba lagi."))
		return
	}
	email, _ := payload.Claims["email"].(string)
	emailVerified, _ := payload.Claims["email_verified"].(bool)
	displayName, _ := payload.Claims["name"].(string)
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" || !emailVerified {
		writeError(w, http.StatusUnauthorized, errors.New("Email Google belum terverifikasi. Gunakan akun Google yang sudah terverifikasi."))
		return
	}
	if strings.TrimSpace(displayName) == "" {
		displayName = email
	}

	role := "patient"
	if strings.TrimSpace(req.Role) != "" {
		role, err = auth.NormalizeRole(req.Role)
		if err != nil || role == "admin" {
			writeError(w, http.StatusBadRequest, errors.New("Role harus patient atau professional."))
			return
		}
	}

	// 1. Akun SSO sudah pernah login -> langsung masuk.
	if user, err := s.store.GetUserBySSO(r.Context(), "google", payload.Subject); err == nil {
		s.secLogger.LogAuthSuccess(r, user.ID)
		s.writeAuthResponse(w, r, http.StatusOK, user)
		return
	} else if !errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	// 2. Email sudah terdaftar via password -> tautkan SSO lalu masuk.
	if user, err := s.store.GetUserByEmail(r.Context(), email); err == nil {
		if err := s.store.LinkSSO(r.Context(), user.ID, "google", payload.Subject); err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		linked, err := s.store.GetUserByID(r.Context(), user.ID)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		s.secLogger.LogAuthSuccess(r, linked.ID)
		s.writeAuthResponse(w, r, http.StatusOK, linked)
		return
	} else if !errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	// 3. Akun baru -> buat dengan hash acak yang tidak bisa dipakai login password.
	// 30 byte random -> 60 hex + prefiks 11 = 71 byte, di bawah batas bcrypt 72.
	random := make([]byte, 30)
	if _, err := rand.Read(random); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	unusableHash, err := auth.HashPassword("sso-google-" + hex.EncodeToString(random))
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	user, err := s.store.CreateUser(r.Context(), store.CreateUserParams{
		Email:        email,
		PasswordHash: unusableHash,
		Role:         role,
		DisplayName:  displayName,
		SSOProvider:  "google",
		SSOID:        payload.Subject,
	})
	if err != nil {
		if isDuplicateKeyError(err) {
			writeError(w, http.StatusConflict, errors.New("Email ini sudah terdaftar. Silakan masuk dengan email & password, lalu tautkan Google."))
			return
		}
		writeError(w, http.StatusBadRequest, err)
		return
	}
	s.secLogger.LogAuthSuccess(r, user.ID)
	s.writeAuthResponse(w, r, http.StatusCreated, user)
}

// isDuplicateKeyError mendeteksi pelanggaran unique constraint Postgres
// tanpa mengimpor driver pg di layer server.
func isDuplicateKeyError(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	return strings.Contains(msg, "duplicate key") ||
		strings.Contains(msg, "unique constraint") ||
		strings.Contains(msg, "already exists")
}
