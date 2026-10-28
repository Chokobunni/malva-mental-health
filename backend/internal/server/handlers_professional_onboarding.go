package server

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"malva/backend/internal/auth"
	googlecal "malva/backend/internal/google"
	"malva/backend/internal/store"
)

// completeProfessionalRequest payload untuk melengkapi profil profesional
// setelah login via Google (STR/SIP belum terisi saat pendaftaran SSO).
type completeProfessionalRequest struct {
	STRNumber      string `json:"str_number"`
	SIPNumber      string `json:"sip_number"`
	Specialization string `json:"specialization"`
	DisplayName    string `json:"display_name"`
	// ExistingPassword adalah password akun LAMA (bukan akun Google) yang
	// dipakai sebagai bukti kepemilikan ketika nomor STR sudah terdaftar pada
	// akun profesional lain. Hanya diperlukan pada kasus itu; jalur normal
	// tidak mengirimnya.
	ExistingPassword string `json:"existing_password"`
}

// mergeVerificationRequiredCode adalah kode mesin pada balasan 409 yang dipakai
// klien untuk mengenali "perlu password akun lama" dan menampilkan kolom
// tambahan. Jangan diubah tanpa memperbarui klien
// (lib/src/services/malva_api_client.dart).
const mergeVerificationRequiredCode = "str_terdaftar_perlu_verifikasi"

// mergeVerificationRequiredBody menyusun body balasan 409 saat pengguna mencoba
// menautkan akun Google ke akun profesional lama TANPA bukti kepemilikan.
// Dipisahkan sebagai fungsi murni agar isinya bisa diuji tanpa database.
func mergeVerificationRequiredBody() map[string]string {
	return map[string]string{
		"error": "Nomor STR sudah terdaftar pada akun lain. Untuk menautkan akun " +
			"Google ini, masukkan password akun lama Anda, atau masuk dengan " +
			"nomor STR + password lalu gunakan menu 'Hubungkan Google' di Pengaturan.",
		"code": mergeVerificationRequiredCode,
	}
}

// sameProfessionalEmail membandingkan email akun Google pemanggil dengan email
// akun lama secara case-insensitive dan trim. Email kosong TIDAK PERNAH
// dianggap sama (tidak ada yang bisa dibandingkan).
func sameProfessionalEmail(callerEmail, existingEmail string) bool {
	caller := strings.ToLower(strings.TrimSpace(callerEmail))
	if caller == "" {
		return false
	}
	target := strings.ToLower(strings.TrimSpace(existingEmail))
	return target != "" && caller == target
}

// allowProfessionalMerge memutuskan apakah akun Google pemanggil boleh
// MENYERAP akun profesional lama yang sudah memakai nomor STR tersebut.
//
// Ini adalah penjaga anti account-takeover: tanpa bukti kepemilikan, siapa pun
// yang tahu nomor STR korban bisa menautkan akun Google-nya sendiri ke akun
// korban dan menerima sesi + kredensial korban.
//
// Bukti kepemilikan yang diterima:
//   - email akun Google pemanggil SAMA dengan email akun lama (email Google
//     sudah terverifikasi saat signup), atau
//   - password akun lama benar.
//
// callerEmail kosong selalu ditolak: tanpa email tepercaya tidak ada yang bisa
// dibandingkan, dan jalur ini tidak boleh dilalui secara buta.
func allowProfessionalMerge(callerEmail, existingEmail string, passwordOK bool) bool {
	if strings.ToLower(strings.TrimSpace(callerEmail)) == "" {
		return false
	}
	return sameProfessionalEmail(callerEmail, existingEmail) || passwordOK
}

// mergeLockoutApplies memutuskan apakah lockout per-akun perlu diperiksa untuk
// permintaan merge ini.
//
// Pemilik sah (email Google == email akun lama) SELALU dikecualikan: ia tidak
// perlu password, sehingga penyerang tidak boleh bisa menutup aksesnya hanya
// dengan salah password berulang kali pada nomor STR yang ia ketahui.
//
// lockoutAktif=false berarti fitur lockout dimatikan (MaxLoginAttempts == 0,
// mis. pada konfigurasi test) — perlakukan sebagai nonaktif, BUKAN "kunci pada
// percobaan pertama".
func mergeLockoutApplies(sameEmail, lockoutAktif bool) bool {
	return lockoutAktif && !sameEmail
}

// mergeLockoutKey menyusun kunci lockout jalur merge: per (IP, nomor STR).
// Dipisahkan agar handler dan test memakai rumus yang sama persis.
func mergeLockoutKey(r *http.Request, strNumber string) string {
	return clientIP(r) + ":merge:" + strings.ToLower(strings.TrimSpace(strNumber))
}

// mergeTooManyAttemptsCode adalah kode mesin pada balasan 429 jalur merge,
// dipakai klien untuk menampilkan pesan "coba lagi nanti" tanpa membuka form
// password lagi. Jangan diubah tanpa memperbarui klien.
const mergeTooManyAttemptsCode = "terlalu_banyak_percobaan"

// mergeTooManyAttemptsBody menyusun body balasan 429 saat kunci lockout jalur
// merge masih aktif.
func mergeTooManyAttemptsBody() map[string]string {
	return map[string]string{
		"error": "Terlalu banyak percobaan verifikasi identitas. Coba lagi beberapa menit lagi.",
		"code":  mergeTooManyAttemptsCode,
	}
}

// completeProfessionalProfile menangani POST /v1/auth/complete-professional.
// Endpoint ini dipanggil setelah profesional baru mendaftar via Google dan
// perlu mengisi nomor STR, SIP, serta spesialisasi agar bisa diverifikasi admin.
//
// Route-nya dibungkus `s.rateLimit(...)` DI LUAR `s.requireAuth(...)` karena
// endpoint ini memverifikasi password akun lama sebagai bukti kepemilikan saat
// merge akun — percobaan password berulang harus dibatasi (brute force), sama
// seperti jalur login.
func (s *Server) completeProfessionalProfile(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "professional" {
		writeError(w, http.StatusForbidden, errors.New("endpoint ini hanya untuk profesional"))
		return
	}
	var req completeProfessionalRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	strNumber := strings.TrimSpace(req.STRNumber)
	sipNumber := strings.TrimSpace(req.SIPNumber)
	specialization := strings.TrimSpace(req.Specialization)
	if strNumber == "" || sipNumber == "" {
		writeError(w, http.StatusBadRequest, errors.New("nomor STR dan SIP wajib diisi"))
		return
	}
	if !validSpecialization(specialization) {
		writeError(w, http.StatusBadRequest, errors.New("spesialisasi harus Sp.KJ (psikiater) atau M.Psi (psikolog)"))
		return
	}
	// Cek apakah STR sudah dipakai profesional lain. Bila ya, jangan langsung
	// menolak: bisa jadi ini profesional lama (akun email sintetis) yang
	// mendaftar ulang lewat Google. Dalam kasus itu tautan Google milik akun
	// placeholder dipindahkan ke akun lama, bukan dibiarkan menggantung.
	existing, err := s.store.FindUserByProfessionalIdentifier(r.Context(), strNumber)
	if err == nil && existing.ID != claims.Subject {
		canMerge, merr := s.store.CanAbsorbGoogleLink(r.Context(), existing.ID, claims.Subject)
		if merr != nil {
			s.logger.Warn("gagal memeriksa kemungkinan merge akun Google", "error", merr)
		}
		if merr == nil && canMerge {
			// ------------------------------------------------------------
			// BUKTI KEPEMILIKAN (anti account takeover).
			//
			// CanAbsorbGoogleLink hanya memeriksa bentuk akun (akun lama tanpa
			// SSO, pemanggil punya Google, placeholder "g-...", keduanya
			// profesional) — TIDAK memeriksa bahwa akun Google ini benar milik
			// pemilik akun lama. Tanpa pemeriksaan di bawah, siapa pun yang
			// tahu nomor STR korban bisa menyerap akun korban beserta
			// kredensialnya.
			// ------------------------------------------------------------
			caller, cerr := s.store.GetUserByID(r.Context(), claims.Subject)
			if cerr != nil {
				writeError(w, http.StatusInternalServerError, cerr)
				return
			}
			// Lockout per-akun: endpoint ini memverifikasi password, jadi
			// kegagalan berulang harus dibatasi seperti jalur login.
			lockoutKey := mergeLockoutKey(r, strNumber)
			lockoutAktif := s.cfg.MaxLoginAttempts > 0 && s.lockout != nil
			sameEmail := sameProfessionalEmail(caller.Email, existing.Email)
			if mergeLockoutApplies(sameEmail, lockoutAktif) && s.lockout.IsLocked(lockoutKey) {
				writeJSON(w, http.StatusTooManyRequests, mergeTooManyAttemptsBody())
				return
			}
			passwordOK := false
			if strings.TrimSpace(req.ExistingPassword) != "" {
				passwordOK = auth.CheckPassword(existing.PasswordHash, req.ExistingPassword)
			}
			if !allowProfessionalMerge(caller.Email, existing.Email, passwordOK) {
				if lockoutAktif {
					s.lockout.RecordFailure(lockoutKey)
				}
				s.secLogger.LogAuthFailure(r, strNumber, "merge tanpa bukti kepemilikan")
				writeJSON(w, http.StatusConflict, mergeVerificationRequiredBody())
				return
			}
			// Bukti kepemilikan sah (email sama atau password benar): bersihkan
			// hitungan gagal agar pemilik tidak terkunci oleh percobaan orang lain.
			if lockoutAktif {
				s.lockout.Reset(lockoutKey)
			}
			if lerr := s.store.MoveGoogleLink(r.Context(), existing.ID, claims.Subject); lerr != nil {
				writeError(w, http.StatusInternalServerError, lerr)
				return
			}
			// Sinkronkan nama: akun lama sering dibuat otomatis dengan
			// display_name = email, sehingga profesional melihat "nama" berupa
			// alamat email setelah login Google. Hanya nilai placeholder yang
			// ditimpa — nama yang sudah diisi rapi tidak pernah diubah.
			googleName := strings.TrimSpace(req.DisplayName)
			if shouldSyncDisplayNameFromGoogle(existing.DisplayName, existing.Email, googleName) {
				if uerr := s.store.UpdateDisplayName(r.Context(), existing.ID, googleName); uerr != nil {
					s.logger.Warn("gagal menyinkronkan display_name akun lama",
						"error", uerr, "user", existing.ID)
				}
			}
			// Muat ulang user agar respons memuat nama hasil sinkronisasi.
			merged, uerr := s.store.GetUserByID(r.Context(), existing.ID)
			if uerr != nil {
				writeError(w, http.StatusInternalServerError, uerr)
				return
			}
			// Sertakan kredensial agar klien langsung menerima detail
			// tersinkronisasi (STR/SIP/spesialisasi) tanpa request tambahan.
			extra := map[string]any{}
			if cred, cerr := s.store.GetProfessionalCredential(r.Context(), existing.ID); cerr == nil {
				extra["credential"] = cred
			} else {
				s.logger.Warn("gagal memuat kredensial akun lama saat merge",
					"error", cerr, "user", existing.ID)
			}
			s.secLogger.LogAuthSuccess(r, merged.ID)
			// Kembalikan sesi untuk akun LAMA (token baru) agar klien berpindah akun.
			s.writeAuthResponseWithCompletionAndExtra(w, r, http.StatusOK, merged, false, extra)
			return
		}
		writeError(w, http.StatusConflict, errors.New("nomor STR sudah terdaftar pada akun lain. Masuk dengan akun tersebut lalu gunakan menu 'Hubungkan Google' di Pengaturan"))
		return
	}
	// Perbarui professional_profiles.professional_id dari temporary "g-..." ke STR asli.
	if err := s.store.UpdateProfessionalID(r.Context(), claims.Subject, strNumber); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	// Simpan kredensial lengkap (STR, SIP, spesialisasi).
	cred, err := s.store.UpsertProfessionalCredential(r.Context(), store.ProfessionalCredential{
		UserID:         claims.Subject,
		STRNumber:      strNumber,
		SIPNumber:      sipNumber,
		Specialization: specialization,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	// Perbarui display_name bila disediakan.
	displayName := strings.TrimSpace(req.DisplayName)
	if displayName != "" {
		if err := s.store.UpdateDisplayName(r.Context(), claims.Subject, displayName); err != nil {
			s.logger.Warn("gagal memperbarui display_name saat complete-professional", "error", err)
		}
	}
	user, err := s.store.GetUserByID(r.Context(), claims.Subject)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"user":       user,
		"credential": cred,
	})
}

// shouldSyncDisplayNameFromGoogle menentukan apakah display_name akun lama
// boleh ditimpa dengan nama dari akun Google saat merge akun.
//
// Aturan: HANYA nilai placeholder yang boleh ditimpa — kosong, mengandung
// "@" (tanda nilainya sebenarnya alamat email, bukan nama orang), atau sama
// persis dengan email akun. Nama yang sudah diisi rapi tidak pernah diubah.
// Nama Google yang kosong juga tidak pernah menimpa apa pun.
func shouldSyncDisplayNameFromGoogle(currentDisplayName, email, googleName string) bool {
	googleName = strings.TrimSpace(googleName)
	if googleName == "" {
		return false
	}
	current := strings.TrimSpace(currentDisplayName)
	if current == "" {
		return true
	}
	if strings.Contains(current, "@") {
		return true
	}
	if email != "" && strings.EqualFold(current, strings.TrimSpace(email)) {
		return true
	}
	return false
}

// createQuickMeet menangani POST /v1/meet/quick.
// Membuat event Meet ad-hoc (mulai sekarang, durasi 30 menit) untuk
// panggilan video cepat tanpa perlu menjadwalkan sesi paket.
func (s *Server) createQuickMeet(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "professional" {
		writeError(w, http.StatusForbidden, errors.New("endpoint ini hanya untuk profesional"))
		return
	}
	if s.calendar == nil {
		writeError(w, http.StatusNotImplemented, errors.New("google Calendar belum dikonfigurasi di server"))
		return
	}
	now := time.Now()
	end := now.Add(30 * time.Minute)
	eventID, meetURL, err := s.calendar.CreateMeetEvent(r.Context(), claims.Subject, googlecal.MeetEventOptions{
		Summary:   "Sesi Cepat Malva",
		StartTime: now,
		EndTime:   end,
	})
	if err != nil {
		if errors.Is(err, googlecal.ErrReauthNeeded) {
			writeError(w, http.StatusUnauthorized, errors.New("akses Google Calendar kedaluwarsa. Silakan tautkan ulang akun Google"))
			return
		}
		s.logger.Warn("gagal membuat quick Meet event", "error", err, "user", claims.Subject)
		writeError(w, http.StatusInternalServerError, errors.New("gagal membuat link video call. Coba lagi nanti"))
		return
	}
	writeJSON(w, http.StatusCreated, map[string]string{
		"meet_url": meetURL,
		"event_id": eventID,
	})
}
