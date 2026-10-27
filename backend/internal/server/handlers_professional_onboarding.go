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
}

// completeProfessionalProfile menangani POST /v1/auth/complete-professional.
// Endpoint ini dipanggil setelah profesional baru mendaftar via Google dan
// perlu mengisi nomor STR, SIP, serta spesialisasi agar bisa diverifikasi admin.
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
			if lerr := s.store.MoveGoogleLink(r.Context(), existing.ID, claims.Subject); lerr != nil {
				writeError(w, http.StatusInternalServerError, lerr)
				return
			}
			s.secLogger.LogAuthSuccess(r, existing.ID)
			// Kembalikan sesi untuk akun LAMA (token baru) agar klien berpindah akun.
			s.writeAuthResponseWithCompletion(w, r, http.StatusOK, existing, false)
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
