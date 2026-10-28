package server

import (
	"crypto/rand"
	"database/sql"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
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
		writeError(w, http.StatusBadRequest, errors.New("id_token wajib diisi"))
		return
	}
	if s.cfg.GoogleClientID == "" {
		writeError(w, http.StatusNotImplemented, errors.New("login Google belum dikonfigurasi di server. Hubungi admin untuk mengisi MALVA_GOOGLE_CLIENT_ID"))
		return
	}
	payload, err := idtoken.Validate(r.Context(), strings.TrimSpace(req.IDToken), s.cfg.GoogleClientID)
	if err != nil {
		// Diagnosa: token yang ditolak hampir selalu karena audience/issuer
		// tidak cocok (mis. APK di-build dengan Web Client ID berbeda, atau
		// token berasal dari project Firebase lain). Kita hanya MEMBACA
		// klaim tanpa memverifikasi tanda tangan — khusus untuk log. Validasi
		// audience TIDAK dilonggarkan: token tetap ditolak dengan 401.
		aud, iss, sub := peekIDTokenClaimsUnverified(strings.TrimSpace(req.IDToken))
		s.logger.Warn("validasi id_token Google gagal",
			"error", err,
			"aud", aud,
			"iss", iss,
			"sub_panjang", len(sub),
			"expected_aud", s.cfg.GoogleClientID,
		)
		s.secLogger.LogAuthFailure(r, "google", "invalid id_token")
		writeError(w, http.StatusUnauthorized, errors.New("token Google tidak valid atau kedaluwarsa. Silakan coba lagi"))
		return
	}
	if payload.Subject == "" {
		writeError(w, http.StatusUnauthorized, errors.New("token Google tidak valid atau kedaluwarsa. Silakan coba lagi"))
		return
	}
	email, _ := payload.Claims["email"].(string)
	emailVerified, _ := payload.Claims["email_verified"].(bool)
	displayName, _ := payload.Claims["name"].(string)
	email = strings.ToLower(strings.TrimSpace(email))
	if email == "" || !emailVerified {
		writeError(w, http.StatusUnauthorized, errors.New("email Google belum terverifikasi. Gunakan akun Google yang sudah terverifikasi"))
		return
	}
	if strings.TrimSpace(displayName) == "" {
		displayName = email
	}

	role := "patient"
	if strings.TrimSpace(req.Role) != "" {
		role, err = auth.NormalizeRole(req.Role)
		if err != nil || role == "admin" {
			writeError(w, http.StatusBadRequest, errors.New("role harus patient atau professional"))
			return
		}
	}

	// 1. Akun SSO sudah pernah login -> langsung masuk.
	if user, err := s.store.GetUserBySSO(r.Context(), "google", payload.Subject); err == nil {
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
	params := store.CreateUserParams{
		Email:        email,
		PasswordHash: unusableHash,
		Role:         role,
		DisplayName:  displayName,
		SSOProvider:  "google",
		SSOID:        payload.Subject,
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
		needsCompletion = true
	}
	user, err := s.store.CreateUser(r.Context(), params)
	if err != nil {
		if isDuplicateKeyError(err) {
			writeError(w, http.StatusConflict, errors.New("email ini sudah terdaftar. Silakan masuk dengan email & password, lalu tautkan Google"))
			return
		}
		writeError(w, http.StatusBadRequest, err)
		return
	}
	// Profesional baru: buat kredensial placeholder (status PENDING).
	if role == "professional" {
		_, _ = s.store.UpsertProfessionalCredential(r.Context(), store.ProfessionalCredential{
			UserID:         user.ID,
			Specialization: "M.Psi",
		})
	}
	s.secLogger.LogAuthSuccess(r, user.ID)
	s.writeAuthResponseWithCompletion(w, r, http.StatusCreated, user, needsCompletion)
}

// peekIDTokenClaimsUnverified membaca klaim `aud`, `iss`, dan `sub` dari
// payload JWT TANPA memverifikasi tanda tangan.
//
// HANYA dipakai untuk logging/diagnosa ketika validasi gagal — jangan pernah
// memakai hasilnya untuk mengambil keputusan otorisasi. Bila token tidak bisa
// diurai, ketiga nilai dikembalikan sebagai string kosong.
func peekIDTokenClaimsUnverified(raw string) (aud, iss, sub string) {
	parts := strings.Split(raw, ".")
	if len(parts) < 2 {
		return "", "", ""
	}
	// JWT memakai base64url tanpa padding.
	decoded, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil {
		return "", "", ""
	}
	var claims map[string]any
	if err := json.Unmarshal(decoded, &claims); err != nil {
		return "", "", ""
	}
	// `aud` boleh berupa string tunggal atau array (multi-audience).
	switch v := claims["aud"].(type) {
	case string:
		aud = v
	case []any:
		items := make([]string, 0, len(v))
		for _, item := range v {
			if s, ok := item.(string); ok {
				items = append(items, s)
			}
		}
		aud = strings.Join(items, ",")
	}
	iss, _ = claims["iss"].(string)
	sub, _ = claims["sub"].(string)
	return aud, iss, sub
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

// ============================================================
// Link Google & Token Exchange — untuk profesional yang sudah
// punya akun (password/SSO lain) dan ingin menautkan Google
// agar bisa memakai Google Meet.
// ============================================================

type linkGoogleRequest struct {
	IDToken string `json:"id_token"`
}

// linkGoogle menautkan akun Google ke user yang sedang login.
// Dipakai profesional yang mendaftar via password/email lalu ingin
// menambahkan akses Google Calendar/Meet.
func (s *Server) linkGoogle(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	var req linkGoogleRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if strings.TrimSpace(req.IDToken) == "" {
		writeError(w, http.StatusBadRequest, errors.New("id_token wajib diisi"))
		return
	}
	if s.cfg.GoogleClientID == "" {
		writeError(w, http.StatusNotImplemented, errors.New("login Google belum dikonfigurasi di server"))
		return
	}
	payload, err := idtoken.Validate(r.Context(), strings.TrimSpace(req.IDToken), s.cfg.GoogleClientID)
	if err != nil {
		writeError(w, http.StatusUnauthorized, errors.New("token Google tidak valid atau kedaluwarsa"))
		return
	}
	if payload.Subject == "" {
		writeError(w, http.StatusUnauthorized, errors.New("token Google tidak valid"))
		return
	}
	// Cek apakah subject Google ini sudah ditautkan ke akun lain.
	if existing, err := s.store.GetUserBySSO(r.Context(), "google", payload.Subject); err == nil && existing.ID != claims.Subject {
		writeError(w, http.StatusConflict, errors.New("akun Google ini sudah ditautkan ke pengguna lain"))
		return
	}
	if err := s.store.LinkSSO(r.Context(), claims.Subject, "google", payload.Subject); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "linked"})
}

type googleTokenExchangeRequest struct {
	AuthorizationCode string `json:"authorization_code"`
}

// exchangeGoogleToken menukar authorization code dari aplikasi Flutter
// menjadi refresh+access token, lalu menyimpannya untuk akses Calendar API.
func (s *Server) exchangeGoogleToken(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "professional" {
		writeError(w, http.StatusForbidden, errors.New("endpoint ini hanya untuk profesional"))
		return
	}
	var req googleTokenExchangeRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	code := strings.TrimSpace(req.AuthorizationCode)
	if code == "" {
		writeError(w, http.StatusBadRequest, errors.New("authorization_code wajib diisi"))
		return
	}
	if s.cfg.GoogleClientSecret == "" {
		writeError(w, http.StatusNotImplemented, errors.New("google OAuth client secret belum dikonfigurasi"))
		return
	}
	oauthCfg := &oauth2.Config{
		ClientID:     s.cfg.GoogleClientID,
		ClientSecret: s.cfg.GoogleClientSecret,
		Endpoint:     googoauth.Endpoint,
		Scopes:       []string{"https://www.googleapis.com/auth/calendar.events"},
	}
	// access_type=offline + prompt=consent memaksa Google mengirim refresh
	// token. Tanpa ini, penukaran ulang kode sering hanya menghasilkan access
	// token, sehingga integrasi Calendar gagal dan memicu loop "tautkan ulang".
	tok, err := oauthCfg.Exchange(r.Context(), code,
		oauth2.SetAuthURLParam("access_type", "offline"),
		oauth2.SetAuthURLParam("prompt", "consent"),
	)
	if err != nil {
		s.logger.Warn("gagal menukar authorization code Google", "error", err, "user", claims.Subject)
		writeError(w, http.StatusBadRequest, errors.New("gagal menukar authorization code. Pastikan code masih berlaku"))
		return
	}
	// Refresh token kosong tidak boleh disimpan: kalau tersimpan, akses
	// Calendar akan selalu ErrReauthNeeded dan menautkan ulang menghasilkan
	// token kosong lagi (loop tanpa akhir).
	if strings.TrimSpace(tok.RefreshToken) == "" {
		writeError(w, http.StatusBadRequest, errors.New("google tidak memberikan refresh token. Cabut akses Malva di https://myaccount.google.com/permissions lalu hubungkan ulang akun Google"))
		return
	}
	scope := strings.Join(oauthCfg.Scopes, " ")
	if err := s.store.UpsertGoogleToken(r.Context(), claims.Subject, tok.RefreshToken, tok.AccessToken, tok.Expiry, scope); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}
