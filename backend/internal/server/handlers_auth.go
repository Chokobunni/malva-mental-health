package server

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strings"
	"time"

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
			s.writeGoogleIdentityError(w, r, err)
			return
		}
		user, err = s.store.GetUserByID(r.Context(), user.ID)
		if err != nil {
			s.writeGoogleIdentityError(w, r, err)
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
			s.writeGoogleIdentityError(w, r, err)
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
		writeUserError(w, http.StatusBadRequest, "Kode otorisasi Google wajib diisi.")
		return
	}
	if s.cfg.GoogleClientID == "" || s.cfg.GoogleClientSecret == "" {
		writeUserError(w, http.StatusNotImplemented, "Google Meet belum dikonfigurasi di server. Hubungi admin.")
		return
	}
	identity, err := s.store.GetGoogleIdentity(r.Context(), claims.Subject)
	if err != nil {
		s.writeGoogleIdentityError(w, r, err)
		return
	}
	if !identity.Linked {
		writeUserError(w, http.StatusConflict, "Hubungkan Gmail dulu sebelum mengaktifkan Google Meet.")
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
		// Dulu error Google ditelan total (tanpa log, tanpa kode) sehingga
		// kegagalan penukaran tidak bisa didiagnosis. Sekarang ekstrak detail
		// dari *oauth2.RetrieveError agar kode mesin + ErrorCode Google bisa
		// dilihat dari log server MAUPUN dari layar pengguna.
		var re *oauth2.RetrieveError
		if errors.As(err, &re) {
			status := 0
			if re.Response != nil {
				status = re.Response.StatusCode
			}
			s.logger.Error("google token exchange gagal",
				"user", claims.Subject,
				"status", status,
				"google_error", re.ErrorCode,
				"google_description", re.ErrorDescription,
				"error", err)
			writeJSON(w, http.StatusBadRequest, map[string]string{
				"error":                    googleExchangeUserMessage(re.ErrorCode, re.ErrorDescription),
				"code":                     googleExchangeErrorCode(re.ErrorCode),
				"google_error":             re.ErrorCode,
				"google_error_description": re.ErrorDescription,
			})
			return
		}
		// Bukan RetrieveError (mis. jaringan putus): tetap log error mentah.
		s.logger.Error("google token exchange gagal", "user", claims.Subject, "error", err)
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "Gagal menukar authorization code ke Google. Periksa koneksi lalu coba lagi; " +
				"bila berulang hubungi admin.",
			"code": "google_penukaran_gagal",
		})
		return
	}
	// Refresh token kosong tidak boleh disimpan: kalau tersimpan, akses
	// Calendar akan selalu ErrReauthNeeded dan menautkan ulang menghasilkan
	// token kosong lagi (loop tanpa akhir).
	if strings.TrimSpace(tok.RefreshToken) == "" {
		writeUserError(w, http.StatusBadRequest, "google tidak memberikan refresh token. Cabut akses Malva di https://myaccount.google.com/permissions lalu hubungkan ulang akun Google")
		return
	}
	// Token endpoint Google hanya mengembalikan id_token bila scope `openid`
	// ikut diminta. Aplikasi Flutter kini meminta calendarAuthScopes
	// (openid + email + calendar.events), sehingga id_token terbit. Bila
	// id_token tetap kosong/tidak valid, fallback: ambil `sub` dari Google
	// UserInfo memakai access token yang baru ditukar — endpoint UserInfo
	// MENOLAK token yang tidak punya salah satu scope openid/email/profile,
	// sehingga tanpa `openid` fallback ini pasti gagal (403 -> 422).
	scope, _ := tok.Extra("scope").(string)
	subject := ""
	adaIDToken := false
	var verr, ferr error
	if exchangedIDToken, _ := tok.Extra("id_token").(string); strings.TrimSpace(exchangedIDToken) != "" {
		adaIDToken = true
		if payload, v := idtoken.Validate(r.Context(), exchangedIDToken, s.cfg.GoogleClientID); v == nil && validGoogleIdentityPayload(payload) {
			subject = payload.Subject
		} else if v != nil {
			verr = v
		} else {
			// Validate lolos tetapi klaim wajib kosong (sub/issuer): simpan
			// alasannya agar log tidak kehilangan konteks.
			verr = errors.New("klaim id_token tidak memenuhi syarat (sub/issuer kosong)")
		}
	}
	if strings.TrimSpace(subject) == "" {
		fallbackSubject, f := googleSubjectFromUserinfo(r.Context(), tok.AccessToken, googleUserinfoEndpoint)
		if f != nil {
			ferr = f
			// Kode Google SUDAH terpakai di titik ini (pertukaran token sukses).
			// Membalas 401 akan membuat klien mengira access token Malva
			// kedaluwarsa, me-refresh token, lalu MENGIRIM ULANG kode yang sama
			// — dijamin invalid_grant karena kode otorisasi Google sekali pakai.
			// Karena itu 422 (kegagalan semantik, bukan autentikasi) dengan kode
			// mesin yang jelas. Log SEKALI dengan seluruh konteks diagnosis
			// supaya penyebab (id_token vs userinfo, scope yang diberikan)
			// terlihat dari log server tanpa menebak.
			s.logger.Error("google identitas tidak bisa dipastikan setelah penukaran kode",
				"user", claims.Subject,
				"ada_id_token", adaIDToken,
				"id_token_error", verr,
				"userinfo_error", ferr,
				"scope_diberikan", scope)
			writeJSON(w, http.StatusUnprocessableEntity, map[string]string{
				"error": "Google tidak mengembalikan identitas akun yang valid setelah kode ditukar. " +
					"Tekan \"Hubungkan Google Calendar\" lagi — kode lama sudah terpakai dan tidak bisa dipakai ulang.",
				"code":         "google_identitas_gagal",
				"google_scope": scope,
			})
			return
		}
		subject = fallbackSubject
	}
	if subject != identity.Subject {
		writeUserError(w, http.StatusConflict,
			"Gunakan akun Google yang sudah terhubung ke Malva untuk mengaktifkan Google Meet.")
		return
	}
	if !store.HasCalendarScope(scope) {
		writeUserError(w, http.StatusForbidden,
			"Izin Google Calendar wajib diberikan agar Google Meet bisa dipakai.")
		return
	}
	// Penukaran authorization code = grant BARU: perbarui tanggal grant agar
	// umur refresh token (7 hari pada mode Testing) dihitung dari sini.
	if err := s.store.UpsertGoogleToken(r.Context(), claims.Subject, tok.RefreshToken, tok.AccessToken, tok.Expiry, scope, subject, true); err != nil {
		writeUserError(w, http.StatusInternalServerError,
			"Gagal menyimpan izin Google Calendar. Coba lagi.")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// googleExchangeErrorCode memetakan ErrorCode dari token endpoint Google ke
// kode mesin yang dikonsumsi UI Flutter.
func googleExchangeErrorCode(googleError string) string {
	switch googleError {
	case "invalid_grant":
		return "google_code_kedaluwarsa"
	case "invalid_client", "unauthorized_client":
		return "google_konfigurasi_server"
	default:
		return "google_penukaran_gagal"
	}
}

// googleExchangeUserMessage menyusun pesan Indonesia yang actionable untuk
// kegagalan penukaran token, menyertakan kode Google bila ada.
func googleExchangeUserMessage(googleError, description string) string {
	switch googleError {
	case "invalid_grant":
		return "Kode otorisasi Google sudah dipakai atau kedaluwarsa (Google: invalid_grant). " +
			"Cabut akses Malva di https://myaccount.google.com/permissions lalu tekan " +
			"\"Hubungkan Google Calendar\" lagi."
	case "invalid_client", "unauthorized_client":
		return "Konfigurasi Google di server tidak cocok (Google: " + googleError + "). " +
			"Hubungi admin agar MALVA_GOOGLE_CLIENT_ID dan MALVA_GOOGLE_CLIENT_SECRET sama dengan " +
			"OAuth client tipe Web application di Google Cloud Console."
	default:
		msg := "Google menolak menukar authorization code (Google: " + googleError + ")"
		if strings.TrimSpace(description) != "" {
			msg += ": " + description
		}
		return msg + "."
	}
}

// googleUserinfoEndpoint endpoint Google UserInfo (OpenID Connect) yang
// mengembalikan `sub` akun pemilik access token.
const googleUserinfoEndpoint = "https://www.googleapis.com/oauth2/v3/userinfo"

// googleSubjectFromUserinfo mengambil `sub` akun Google dari endpoint UserInfo
// memakai access token OAuth. Dipakai sebagai fallback saat token endpoint
// tidak mengembalikan id_token (klien tidak meminta scope `openid`).
// `endpoint` eksplisit agar bisa diuji dengan httptest tanpa jaringan.
func googleSubjectFromUserinfo(ctx context.Context, accessToken, endpoint string) (string, error) {
	accessToken = strings.TrimSpace(accessToken)
	if accessToken == "" {
		return "", errors.New("access token Google kosong")
	}
	if strings.TrimSpace(endpoint) == "" {
		return "", errors.New("endpoint Google UserInfo kosong")
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return "", fmt.Errorf("gagal menyusun permintaan Google UserInfo: %w", err)
	}
	req.Header.Set("Authorization", "Bearer "+accessToken)
	req.Header.Set("Accept", "application/json")
	// Klien dengan timeout: http.DefaultClient tidak punya batas waktu, sehingga
	// gangguan jaringan ke Google bisa menggantung permintaan tanpa akhir.
	client := &http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return "", fmt.Errorf("gagal menghubungi Google UserInfo: %w", err)
	}
	defer func() { _ = resp.Body.Close() }()
	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("google UserInfo mengembalikan status %d", resp.StatusCode)
	}
	var payload struct {
		Sub string `json:"sub"`
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(&payload); err != nil {
		return "", fmt.Errorf("respons Google UserInfo tidak valid: %w", err)
	}
	subject := strings.TrimSpace(payload.Sub)
	if subject == "" {
		return "", errors.New("google UserInfo tidak memuat sub")
	}
	return subject, nil
}
