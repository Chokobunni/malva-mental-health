package server

import (
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"errors"
	"net/http"
	"strings"

	"golang.org/x/oauth2"
	googoauth "golang.org/x/oauth2/google"
	"google.golang.org/api/idtoken"

	"malva/backend/internal/auth"
	"malva/backend/internal/store"
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
		writeUserError(w, http.StatusBadRequest, "id_token wajib diisi")
		return
	}
	if s.cfg.GoogleClientID == "" {
		writeUserError(w, http.StatusNotImplemented, "login Google belum dikonfigurasi di server. Hubungi admin untuk mengisi MALVA_GOOGLE_CLIENT_ID")
		return
	}
	payload, err := idtoken.Validate(r.Context(), strings.TrimSpace(req.IDToken), s.cfg.GoogleClientID)
	if err != nil {
		s.secLogger.LogAuthFailure(r, "google", "invalid id_token")
		writeUserError(w, http.StatusUnauthorized, "token Google tidak valid atau kedaluwarsa. Silakan coba lagi")
		return
	}
	if !validGoogleIdentityPayload(payload) {
		writeUserError(w, http.StatusUnauthorized, "token Google tidak valid atau kedaluwarsa. Silakan coba lagi")
		return
	}
	email, _ := payload.Claims["email"].(string)
	emailVerified, _ := payload.Claims["email_verified"].(bool)
	displayName, _ := payload.Claims["name"].(string)
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" || !emailVerified {
		writeUserError(w, http.StatusUnauthorized, "email Google belum terverifikasi. Gunakan akun Google yang sudah terverifikasi")
		return
	}
	if strings.TrimSpace(displayName) == "" {
		displayName = email
	}

	role := "patient"
	if strings.TrimSpace(req.Role) != "" {
		role, err = auth.NormalizeRole(req.Role)
		if err != nil || role == "admin" {
			writeUserError(w, http.StatusBadRequest, "role harus patient atau professional")
			return
		}
	}

	// 1. Akun SSO sudah pernah login -> langsung masuk.
	if user, err := s.store.GetUserBySSO(r.Context(), "google", payload.Subject); err == nil {
		if _, err := s.store.LinkGoogleIdentity(r.Context(), user.ID, payload.Subject, email, false); err != nil {
			writeGoogleIdentityError(w, err)
			return
		}
		user, err = s.store.GetUserByID(r.Context(), user.ID)
		if err != nil {
			writeGoogleIdentityError(w, err)
			return
		}
		s.secLogger.LogAuthSuccess(r, user.ID)
		// Profesional yang belum melengkapi profil (STR/SIP) perlu diarahkan
		// ke halaman complete-professional. Patokannya bukan ada/tidaknya baris
		// kredensial (placeholder selalu ada sejak pendaftaran), melainkan
		// apakah professional_id masih sementara ("g-...") atau profil belum ada.
		needsCompletion := false
		if user.Role == "professional" {
			incomplete, cerr := s.store.IsProfessionalProfileIncomplete(r.Context(), user.ID)
			if cerr != nil {
				s.logger.Warn("gagal memeriksa kelengkapan profil profesional", "error", cerr, "user", user.ID)
			}
			needsCompletion = cerr == nil && incomplete
		}
		s.writeAuthResponseWithCompletion(w, r, http.StatusOK, user, needsCompletion)
		return
	} else if !errors.Is(err, sql.ErrNoRows) {
		writeUserError(w, http.StatusInternalServerError, "could not process Google authentication")
		return
	}

	// 2. Email sudah terdaftar via password -> tautkan SSO lalu masuk.
	if user, err := s.store.GetUserByEmail(r.Context(), email); err == nil {
		if _, err := s.store.LinkGoogleIdentity(r.Context(), user.ID, payload.Subject, email, false); err != nil {
			writeGoogleIdentityError(w, err)
			return
		}
		linked, err := s.store.GetUserByID(r.Context(), user.ID)
		if err != nil {
			writeUserError(w, http.StatusInternalServerError, "could not process Google authentication")
			return
		}
		s.secLogger.LogAuthSuccess(r, linked.ID)
		needsCompletion := false
		if linked.Role == "professional" {
			incomplete, cerr := s.store.IsProfessionalProfileIncomplete(r.Context(), linked.ID)
			if cerr != nil {
				s.logger.Warn("gagal memeriksa kelengkapan profil profesional", "error", cerr, "user", linked.ID)
			}
			needsCompletion = cerr == nil && incomplete
		}
		s.writeAuthResponseWithCompletion(w, r, http.StatusOK, linked, needsCompletion)
		return
	} else if !errors.Is(err, sql.ErrNoRows) {
		writeUserError(w, http.StatusInternalServerError, "could not process Google authentication")
		return
	}

	// 3. Akun baru -> buat dengan hash acak yang tidak bisa dipakai login password.
	// 30 byte random -> 60 hex + prefiks 11 = 71 byte, di bawah batas bcrypt 72.
	random := make([]byte, 30)
	if _, err := rand.Read(random); err != nil {
		writeUserError(w, http.StatusInternalServerError, "could not process Google authentication")
		return
	}
	unusableHash, err := auth.HashPassword("sso-google-" + hex.EncodeToString(random))
	if err != nil {
		writeUserError(w, http.StatusInternalServerError, "could not process Google authentication")
		return
	}
	params := store.CreateUserParams{
		Email:        email,
		PasswordHash: unusableHash,
		Role:         role,
		DisplayName:  displayName,
		SSOProvider:  "google",
		SSOID:        payload.Subject,
		SSOEmail:     email,
	}
	needsCompletion := false
	if role == "professional" {
		// Profesional baru via Google perlu temporary professional_id agar
		// CreateUser tidak gagal. Nanti diganti nomor STR saat complete-professional.
		tempID := "g-" + payload.Subject
		if len(tempID) > 30 {
			tempID = tempID[:30]
		}
		params.ProfessionalID = tempID
		params.Credential = &store.ProfessionalCredential{Specialization: "M.Psi"}
		needsCompletion = true
	}
	user, err := s.store.CreateUser(r.Context(), params)
	if err != nil {
		if isDuplicateKeyError(err) || errors.Is(err, store.ErrEmailOwnedByOther) {
			writeUserError(w, http.StatusConflict, "email ini sudah terdaftar. Silakan masuk dengan email & password, lalu tautkan Google")
			return
		}
		writeUserError(w, http.StatusInternalServerError, "could not create Google account")
		return
	}
	s.secLogger.LogAuthSuccess(r, user.ID)
	s.writeAuthResponseWithCompletion(w, r, http.StatusCreated, user, needsCompletion)
}

// isDuplicateKeyError mendeteksi pelanggaran unique constraint Postgres
// tanpa mengimpor driver pg di layer server.
func isDuplicateKeyError(err error) bool {
	if err == nil {
		return false
	}
	if store.IsUniqueViolation(err) {
		return true
	}
	msg := err.Error()
	return strings.Contains(msg, "duplicate key") || strings.Contains(msg, "unique constraint")
}

// ============================================================
// Link Google & Token Exchange — untuk profesional yang sudah
// punya akun (password/SSO lain) dan ingin menautkan Google
// agar bisa memakai Google Meet.
// ============================================================

// linkGoogle menautkan akun Google ke user yang sedang login.
// Dipakai profesional yang mendaftar via password/email lalu ingin
// menambahkan akses Google Calendar/Meet.
func (s *Server) linkGoogle(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	s.bindGoogleIdentity(w, r, claims, true)
}

type googleTokenExchangeRequest struct {
	AuthorizationCode string `json:"authorization_code"`
}

// exchangeGoogleToken menukar authorization code dari aplikasi Flutter
// menjadi refresh+access token, lalu menyimpannya untuk akses Calendar API.
func (s *Server) exchangeGoogleToken(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "professional" {
		writeUserError(w, http.StatusForbidden, "endpoint ini hanya untuk profesional")
		return
	}
	var req googleTokenExchangeRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	code := strings.TrimSpace(req.AuthorizationCode)
	if code == "" {
		writeUserError(w, http.StatusBadRequest, "authorization_code wajib diisi")
		return
	}
	if s.cfg.GoogleClientID == "" || s.cfg.GoogleClientSecret == "" {
		writeUserError(w, http.StatusNotImplemented, "google OAuth client secret belum dikonfigurasi")
		return
	}
	identity, err := s.store.GetGoogleIdentity(r.Context(), claims.Subject)
	if err != nil {
		writeGoogleIdentityError(w, err)
		return
	}
	if !identity.Linked {
		writeUserError(w, http.StatusConflict, "bind Google before authorizing Calendar")
		return
	}
	oauthCfg := &oauth2.Config{
		ClientID:     s.cfg.GoogleClientID,
		ClientSecret: s.cfg.GoogleClientSecret,
		Endpoint:     googoauth.Endpoint,
		Scopes:       []string{"https://www.googleapis.com/auth/calendar.events"},
	}
	// The client must request offline Calendar consent during authorization.
	// Exchange options cannot add scopes or consent to an already issued code.
	tok, err := oauthCfg.Exchange(r.Context(), code)
	if err != nil {
		writeUserError(w, http.StatusBadRequest, "gagal menukar authorization code. Pastikan code masih berlaku")
		return
	}
	// Refresh token kosong tidak boleh disimpan: kalau tersimpan, akses
	// Calendar akan selalu ErrReauthNeeded dan menautkan ulang menghasilkan
	// token kosong lagi (loop tanpa akhir).
	if strings.TrimSpace(tok.RefreshToken) == "" {
		writeUserError(w, http.StatusBadRequest, "google tidak memberikan refresh token. Cabut akses Malva di https://myaccount.google.com/permissions lalu hubungkan ulang akun Google")
		return
	}
	exchangedIDToken, _ := tok.Extra("id_token").(string)
	payload, err := idtoken.Validate(r.Context(), exchangedIDToken, s.cfg.GoogleClientID)
	if err != nil || !validGoogleIdentityPayload(payload) {
		writeUserError(w, http.StatusUnauthorized, "Google authorization did not return a valid identity token")
		return
	}
	if payload.Subject != identity.Subject {
		writeUserError(w, http.StatusConflict, "authorize Calendar using the Google account already bound to Malva")
		return
	}
	scope, _ := tok.Extra("scope").(string)
	if !store.HasCalendarScope(scope) {
		writeUserError(w, http.StatusForbidden, "Google Calendar consent is required")
		return
	}
	if err := s.store.UpsertGoogleToken(r.Context(), claims.Subject, tok.RefreshToken, tok.AccessToken, tok.Expiry, scope, payload.Subject); err != nil {
		writeUserError(w, http.StatusInternalServerError, "could not save Calendar authorization")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}
