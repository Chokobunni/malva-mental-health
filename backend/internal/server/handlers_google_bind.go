package server

import (
	"database/sql"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"strings"

	"github.com/jackc/pgx/v5/pgconn"
	"google.golang.org/api/idtoken"

	"malva/backend/internal/auth"
	"malva/backend/internal/security"
	"malva/backend/internal/store"
)

// Kode mesin pada balasan 409 endpoint identitas Google, supaya UI Flutter
// bisa menampilkan pesan spesifik dan actionable per kasus (bukan generik).
const (
	googleAlreadyLinkedCode = "google_sudah_tertaut"
	googleEmailTakenCode    = "email_sudah_dipakai"
	googleIdentityBoundCode = "akun_sudah_taut_google_lain"
	// Kode mesin endpoint unbind-google.
	googleNotLinkedCode        = "google_belum_tertaut"
	googlePasswordRequiredCode = "perlu_password"
	googlePasswordWrongCode    = "password_salah"
)

type bindGoogleRequest struct {
	IDToken      string `json:"id_token"`
	ReplaceEmail bool   `json:"replace_email"`
}

func validGoogleIdentityPayload(payload *idtoken.Payload) bool {
	return payload != nil && strings.TrimSpace(payload.Subject) != "" &&
		(payload.Issuer == "https://accounts.google.com" || payload.Issuer == "accounts.google.com")
}

// writeGoogleIdentityError memetakan error identitas Google menjadi respons
// HTTP dengan kode mesin agar UI bisa bereaksi spesifik:
//
//   - Google sudah tertaut ke akun lain  -> 409 google_sudah_tertaut
//   - Email Google sudah dipakai akun lain -> 409 email_sudah_dipakai
//   - Akun sudah tertaut ke Google lain  -> 409 akun_sudah_taut_google_lain
//   - Akun tidak ditemukan               -> 404
//
// Semua kasus 409 memakai writeJSON (body `{"error","code"}`), bukan
// writeError, supaya kode mesin ikut terkirim.
func writeGoogleIdentityError(w http.ResponseWriter, err error) {
	var pgErr *pgconn.PgError
	uniqueViolation := errors.As(err, &pgErr) && pgErr.Code == "23505"
	switch {
	case errors.Is(err, store.ErrGoogleAlreadyLinked),
		(uniqueViolation && pgErr.ConstraintName == "users_sso_unique"):
		writeJSON(w, http.StatusConflict, map[string]string{
			"error": "Akun Google ini sudah terhubung ke akun Malva lain.",
			"code":  googleAlreadyLinkedCode,
		})
	case errors.Is(err, store.ErrEmailOwnedByOther), uniqueViolation:
		writeJSON(w, http.StatusConflict, map[string]string{
			"error": "Email Google ini sudah dipakai akun Malva lain.",
			"code":  googleEmailTakenCode,
		})
	case errors.Is(err, store.ErrGoogleIdentityBound):
		writeJSON(w, http.StatusConflict, map[string]string{
			"error": "Akun ini sudah terhubung ke akun Google lain. Lepas Gmail tersebut dulu untuk menggantinya.",
			"code":  googleIdentityBoundCode,
		})
	case errors.Is(err, sql.ErrNoRows):
		writeError(w, http.StatusNotFound, errors.New("Akun tidak ditemukan."))
	default:
		writeError(w, http.StatusInternalServerError, errors.New("Gagal menyimpan identitas Google."))
	}
}

// Legacy link-google shares validation and storage, retaining its success body.
func (s *Server) bindGoogle(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	s.bindGoogleIdentity(w, r, claims, false)
}

func (s *Server) bindGoogleIdentity(w http.ResponseWriter, r *http.Request, claims auth.Claims, legacy bool) {
	if claims.Role != "patient" && claims.Role != "professional" {
		writeError(w, http.StatusForbidden, errors.New("Hanya pasien dan profesional yang dapat menghubungkan Google."))
		return
	}
	var req bindGoogleRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, errors.New("Permintaan penautan Google tidak valid."))
		return
	}
	if strings.TrimSpace(req.IDToken) == "" {
		writeError(w, http.StatusBadRequest, errors.New("id_token wajib diisi."))
		return
	}
	if s.cfg.GoogleClientID == "" {
		writeError(w, http.StatusNotImplemented, errors.New("Login Google belum dikonfigurasi di server. Hubungi admin."))
		return
	}
	payload, err := idtoken.Validate(r.Context(), strings.TrimSpace(req.IDToken), s.cfg.GoogleClientID)
	if err != nil || !validGoogleIdentityPayload(payload) {
		writeError(w, http.StatusUnauthorized, errors.New("Token Google tidak valid atau kedaluwarsa. Silakan coba lagi."))
		return
	}
	email, _ := payload.Claims["email"].(string)
	verified, _ := payload.Claims["email_verified"].(bool)
	if strings.TrimSpace(email) == "" || !verified {
		writeError(w, http.StatusUnauthorized, errors.New("Email Google belum terverifikasi. Gunakan akun Google yang sudah terverifikasi."))
		return
	}
	ident, err := s.store.LinkGoogleIdentity(r.Context(), claims.Subject, payload.Subject, email, req.ReplaceEmail)
	if err != nil {
		writeGoogleIdentityError(w, err)
		return
	}
	if legacy {
		writeJSON(w, http.StatusOK, map[string]string{"status": "linked"})
		return
	}
	writeJSON(w, http.StatusOK, ident)
}

func (s *Server) googleIdentityStatus(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "patient" && claims.Role != "professional" {
		writeError(w, http.StatusForbidden, errors.New("Hanya pasien dan profesional yang dapat menghubungkan Google."))
		return
	}
	ident, err := s.store.GetGoogleIdentity(r.Context(), claims.Subject)
	if err != nil {
		writeGoogleIdentityError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, ident)
}

type unbindGoogleRequest struct {
	CurrentPassword string `json:"current_password"`
	NewPassword     string `json:"new_password"`
}

// unbindGoogle melepas tautan Google dari akun pasien/profesional.
//
// Alasan current_password ATAU new_password wajib: akun yang dibuat lewat
// "Login Google" memakai hash password acak yang tidak bisa dipakai untuk
// login. Bila Gmail dilepas tanpa menetapkan password, akun itu mati permanen
// (tidak bisa login lagi dan changePassword menuntut password lama yang tak
// diketahui). Jadi sebelum melepas, pengguna harus membuktikan kepemilikan
// password saat ini (akun password) ATAU menetapkan password baru (akun
// Google-only). Body boleh kosong — server membalas 409 `perlu_password`
// alih-alih 400 agar UI tahu harus meminta password baru.
func (s *Server) unbindGoogle(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "patient" && claims.Role != "professional" {
		writeError(w, http.StatusForbidden, errors.New("Hanya pasien dan profesional yang dapat menghubungkan Google."))
		return
	}
	// Body opsional: baca mentah dulu, hanya unmarshal bila ada isi.
	var req unbindGoogleRequest
	if r.Body != nil {
		raw, err := io.ReadAll(http.MaxBytesReader(w, r.Body, 1<<20))
		if err != nil {
			writeError(w, http.StatusBadRequest, errors.New("Permintaan pelepasan Google tidak valid."))
			return
		}
		if len(raw) > 0 {
			if err := json.Unmarshal(raw, &req); err != nil {
				writeError(w, http.StatusBadRequest, errors.New("Permintaan pelepasan Google tidak valid."))
				return
			}
		}
	}
	user, err := s.store.GetUserByID(r.Context(), claims.Subject)
	if errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusNotFound, errors.New("Akun tidak ditemukan."))
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	// Tentukan kredensial: password lama (bila ada) atau password baru.
	newPasswordHash := ""
	switch {
	case strings.TrimSpace(req.CurrentPassword) != "":
		if !auth.CheckPassword(user.PasswordHash, req.CurrentPassword) {
			writeJSON(w, http.StatusUnauthorized, map[string]string{
				"error": "Password saat ini salah.",
				"code":  googlePasswordWrongCode,
			})
			return
		}
	case strings.TrimSpace(req.NewPassword) != "":
		if err := security.ValidatePassword(req.NewPassword, user.Email); err != nil {
			// Samakan dengan register: pesan kebijakan password berbahasa Indonesia.
			writeError(w, http.StatusBadRequest, errors.New(security.IndonesianMessage(err)))
			return
		}
		hash, herr := auth.HashPassword(req.NewPassword)
		if herr != nil {
			writeError(w, http.StatusInternalServerError, herr)
			return
		}
		newPasswordHash = hash
	default:
		writeJSON(w, http.StatusConflict, map[string]string{
			"error": "Tetapkan password baru dulu agar akun tetap bisa dipakai setelah Gmail dilepas.",
			"code":  googlePasswordRequiredCode,
		})
		return
	}
	ident, err := s.store.UnbindGoogleIdentity(r.Context(), claims.Subject, newPasswordHash)
	if errors.Is(err, store.ErrGoogleNotLinked) {
		writeJSON(w, http.StatusConflict, map[string]string{
			"error": "Akun ini belum terhubung ke Gmail.",
			"code":  googleNotLinkedCode,
		})
		return
	}
	if err != nil {
		writeGoogleIdentityError(w, err)
		return
	}
	s.secLogger.LogIdentityChange(r, claims.Subject, "google_unlinked")
	writeJSON(w, http.StatusOK, ident)
}
