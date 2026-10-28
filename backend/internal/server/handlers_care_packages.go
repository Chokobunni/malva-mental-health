package server

import (
	"errors"
	"fmt"
	"net/http"
	"strings"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
	googlecal "malva/backend/internal/google"
	"malva/backend/internal/store"
)

// ============================================================
// CARE PACKAGES & SESSIONS — paket 4 sesi / 6 minggu.
// Menggantikan Continuous Support chat 7 hari.
// ============================================================

type createCarePackageRequest struct {
	ProfessionalID string `json:"professional_id"`
}

type scheduleSessionRequest struct {
	PackageID       string `json:"package_id"`
	ScheduledAt     string `json:"scheduled_at"`
	SessionType     string `json:"session_type"`
	DurationMinutes int    `json:"duration_minutes"`
	MeetingURL      string `json:"meeting_url"`
}

type rescheduleSessionRequest struct {
	ScheduledAt string `json:"scheduled_at"`
	ByPatient   bool   `json:"-"`
}

type updateSessionRequest struct {
	Status            string `json:"status"`
	CancelReason      string `json:"cancel_reason"`
	MeetingURL        string `json:"meeting_url"`
	SummaryForPatient string `json:"summary_for_patient"`
	PrivateNote       string `json:"private_note"`
}

type timeOffRequest struct {
	OffDate string `json:"off_date"`
	Reason  string `json:"reason"`
}

type pricingRequest struct {
	QuickChatPrice  *int64 `json:"quick_chat_price"`
	QuickVideoPrice *int64 `json:"quick_video_price"`
	PackagePrice    *int64 `json:"package_price"`
}

// wibLoc zona waktu sesi (WIB), bersumber tunggal dari paket clock.
// Catatan: magic offset tetap valid untuk WIB (tidak ada DST).
var wibLoc = clock.Location()

func parseWIBDateTime(value string) (time.Time, error) {
	value = strings.TrimSpace(value)
	layouts := []string{time.RFC3339, "2006-01-02T15:04", "2006-01-02 15:04", "2006-01-02T15:04:05", "2006-01-02"}
	var last error
	for _, layout := range layouts {
		if t, err := time.ParseInLocation(layout, value, wibLoc); err == nil {
			return t, nil
		} else {
			last = err
		}
	}
	if last == nil {
		last = errors.New("invalid datetime")
	}
	return time.Time{}, last
}

// pairIDs menyelesaikan pasangan (patient, professional) untuk sesi/chat
// dari klaim pemanggil + parameter.
func (s *Server) pairIDs(r *http.Request, claims auth.Claims) (patientID, professionalID string, err error) {
	if claims.Role == "patient" {
		professionalID = strings.TrimSpace(r.URL.Query().Get("professional_id"))
		if professionalID == "" {
			professionalID = strings.TrimSpace(r.URL.Query().Get("patient_id"))
		}
		if professionalID == "" {
			return "", "", errors.New("professional_id is required")
		}
		return claims.Subject, professionalID, nil
	}
	if claims.Role == "professional" {
		patientID = strings.TrimSpace(r.URL.Query().Get("patient_id"))
		if patientID == "" {
			return "", "", errors.New("patient_id is required")
		}
		linked, lerr := s.store.ProfessionalLinkedToPatient(r.Context(), claims.Subject, patientID)
		if lerr != nil {
			return "", "", lerr
		}
		if !linked {
			hasRel, rerr := s.store.PairRelation(r.Context(), patientID, claims.Subject)
			if rerr != nil || !hasRel {
				return "", "", errors.New("professional is not linked to this patient")
			}
		}
		return patientID, claims.Subject, nil
	}
	return "", "", errors.New("role is not allowed")
}

func (s *Server) createCarePackage(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "patient" {
		writeError(w, http.StatusForbidden, errors.New("only patients can buy a package"))
		return
	}
	var req createCarePackageRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	professionalID := strings.TrimSpace(req.ProfessionalID)
	if professionalID == "" {
		writeError(w, http.StatusBadRequest, errors.New("professional_id is required"))
		return
	}
	cred, err := s.store.GetProfessionalCredential(r.Context(), professionalID)
	if err != nil || cred.VerificationStatus != "VERIFIED" {
		writeError(w, http.StatusNotFound, errors.New("professional not found or not verified"))
		return
	}
	// Tolak bila masih ada paket aktif dengan profesional yang sama.
	if _, has, _ := s.store.ActivePackageBetween(r.Context(), claims.Subject, professionalID); has {
		writeError(w, http.StatusConflict, errors.New("kamu masih punya paket aktif dengan profesional ini. Selesaikan dulu sebelum membeli lagi"))
		return
	}
	pricing, err := s.store.GetProfessionalPricing(r.Context(), professionalID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if pricing.PackagePrice <= 0 {
		writeError(w, http.StatusBadRequest, errors.New("profesional belum mengatur harga paket. Pilih Quick Consult atau hubungi profesional"))
		return
	}
	now := time.Now()
	pkg, err := s.store.CreateCarePackage(r.Context(), store.CarePackage{
		PatientID:      claims.Subject,
		ProfessionalID: professionalID,
		TotalSessions:  store.CarePackageSessionsTotal,
		ValidityDays:   store.CarePackageValidityDays,
		Price:          pricing.PackagePrice,
		Status:         "pending_payment",
		StartsAt:       now,
		ExpiresAt:      now.AddDate(0, 0, store.CarePackageValidityDays),
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"package": pkg})
}

func (s *Server) listCarePackages(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	patientScope := ""
	if claims.Role == "professional" {
		patientScope = r.URL.Query().Get("patient_id")
	}
	pkgs, err := s.store.ListCarePackages(r.Context(), claims.Subject, claims.Role, patientScope, 50)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if pkgs == nil {
		pkgs = []store.CarePackage{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"packages": pkgs})
}

// cancelPendingCarePackage membatalkan paket yang masih pending_payment.
// Hanya pasien pemilik paket yang boleh membatalkan, dan hanya bila statusnya
// masih pending_payment (paket aktif/expired/completed tidak bisa dibatalkan
// lewat endpoint ini — gunakan jalur refund sesi).
func (s *Server) cancelPendingCarePackage(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "patient" {
		writeError(w, http.StatusForbidden, errors.New("only patients can cancel a pending package"))
		return
	}
	packageID := r.PathValue("package_id")
	if strings.TrimSpace(packageID) == "" {
		writeError(w, http.StatusBadRequest, errors.New("package_id is required"))
		return
	}
	pkg, err := s.store.GetCarePackage(r.Context(), packageID)
	if err != nil {
		writeError(w, http.StatusNotFound, errors.New("care package tidak ditemukan"))
		return
	}
	if pkg.PatientID != claims.Subject {
		writeError(w, http.StatusForbidden, errors.New("not your package"))
		return
	}
	if pkg.Status != "pending_payment" {
		writeError(w, http.StatusBadRequest, errors.New("hanya paket pending_payment yang bisa dibatalkan"))
		return
	}
	if err := s.store.UpdateCarePackageStatus(r.Context(), packageID, "cancelled"); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "cancelled"})
}

// scheduleSession menjadwalkan satu sesi dari paket aktif.
func (s *Server) scheduleSession(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	var req scheduleSessionRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	pkg, err := s.store.GetCarePackage(r.Context(), strings.TrimSpace(req.PackageID))
	if err != nil {
		writeError(w, http.StatusNotFound, errors.New("care package tidak ditemukan"))
		return
	}
	isPatient := claims.Role == "patient" && claims.Subject == pkg.PatientID
	isProf := claims.Role == "professional" && claims.Subject == pkg.ProfessionalID
	if !isPatient && !isProf {
		writeError(w, http.StatusForbidden, errors.New("not authorized for this package"))
		return
	}
	at, err := parseWIBDateTime(req.ScheduledAt)
	if err != nil {
		writeError(w, http.StatusBadRequest, errors.New("scheduled_at tidak valid (contoh: 2026-10-20T10:00)"))
		return
	}
	// Durasi sesi = durasi slot jadwal profesional hari itu (bukan input bebas).
	duration := s.slotDurationFor(r.Context(), pkg.ProfessionalID, at)
	// Validasi slot: sebelumnya endpoint ini sama sekali tidak memvalidasi,
	// sehingga sesi paket bisa dijadwalkan di luar jam praktik, pada hari
	// libur profesional, bahkan di masa lalu — dan tetap memotong kuota paket.
	// Aturan sama dengan createBooking; lead time 24 jam hanya untuk pasien
	// agar profesional masih bisa menjadwalkan sesi mendadak (<24 jam).
	if isProf {
		if verr := s.validateSlotWindow(r.Context(), pkg.ProfessionalID, at, duration); verr != nil {
			writeError(w, http.StatusBadRequest, verr)
			return
		}
	} else if verr := s.validateSlot(r.Context(), pkg.ProfessionalID, at, duration); verr != nil {
		writeError(w, http.StatusBadRequest, verr)
		return
	}
	// Link meeting untuk sesi video: selalu Google Meet, tanpa fallback.
	// Bila pembuatan link gagal, sesi TIDAK dibuat agar pasien tidak menerima
	// sesi video tanpa ruang pertemuan.
	meetingURL := strings.TrimSpace(req.MeetingURL)
	googleEventID := ""
	sessionType := strings.ToLower(strings.TrimSpace(req.SessionType))
	if sessionType == "video" && meetingURL == "" {
		if s.calendar == nil {
			writeError(w, http.StatusNotImplemented, ErrMeetUnavailable)
			return
		}
		opts := s.meetEventOptions(r.Context(), store.CareSession{
			PatientID:        pkg.PatientID,
			ProfessionalID:   pkg.ProfessionalID,
			PatientName:      pkg.PatientName,
			ProfessionalName: pkg.ProfessionalName,
			SessionType:      "video",
			ScheduledAt:      at,
			DurationMinutes:  duration,
		})
		eventID, meetURL, cerr := s.calendar.CreateMeetEvent(r.Context(), pkg.ProfessionalID, opts)
		if cerr != nil {
			if errors.Is(cerr, googlecal.ErrReauthNeeded) {
				writeError(w, http.StatusUnauthorized,
					errors.New("akses Google Calendar profesional kedaluwarsa. Profesional perlu menautkan ulang akun Google"))
				return
			}
			s.logger.Warn("gagal membuat event Google Meet", "error", cerr, "professional", pkg.ProfessionalID)
			writeError(w, http.StatusBadGateway,
				errors.New("gagal membuat link Google Meet. Coba lagi beberapa saat lagi"))
			return
		}
		if strings.TrimSpace(meetURL) == "" {
			if eventID != "" {
				if cerr := s.calendar.CancelMeetEvent(r.Context(), pkg.ProfessionalID, eventID); cerr != nil {
					s.logger.Warn("gagal membatalkan event Meet tanpa link", "error", cerr, "event_id", eventID)
				}
			}
			writeError(w, http.StatusBadGateway,
				errors.New("google tidak mengembalikan link Meet untuk event ini. Coba lagi"))
			return
		}
		meetingURL = meetURL
		googleEventID = eventID
	}
	cs, err := s.store.CreateCareSession(r.Context(), store.CareSession{
		PackageID:       &pkg.ID,
		PatientID:       pkg.PatientID,
		ProfessionalID:  pkg.ProfessionalID,
		SessionType:     req.SessionType,
		ScheduledAt:     at,
		DurationMinutes: duration,
		Status:          "scheduled",
		MeetingURL:      meetingURL,
		GoogleEventID:   googleEventID,
	})
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	s.notifyPatient(r, pkg.ProfessionalID, "session_scheduled",
		"Sesi baru dijadwalkan", "Ada sesi baru yang dijadwalkan dengan pasien.",
		map[string]string{"session_id": cs.ID, "patient_id": pkg.PatientID})
	body := "Sesi dengan profesional dijadwalkan pada " + cs.ScheduledAt.In(wibLoc).Format("02 Jan 2006 15:04") + "."
	if strings.TrimSpace(cs.MeetingURL) != "" {
		body += " Link video call: " + cs.MeetingURL
	}
	s.notifyPatient(r, pkg.PatientID, "session_scheduled",
		"Sesi berhasil dijadwalkan", body,
		map[string]string{"session_id": cs.ID, "meeting_url": cs.MeetingURL})
	writeJSON(w, http.StatusCreated, map[string]any{"session": cs})
}

func (s *Server) listCareSessions(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	scope := r.URL.Query().Get("scope")
	if scope == "" {
		scope = "all"
	}
	patientScope := ""
	if claims.Role == "professional" {
		patientScope = r.URL.Query().Get("patient_id")
	}
	sessions, err := s.store.ListCareSessions(r.Context(), claims.Subject, claims.Role, scope, patientScope, 100)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if sessions == nil {
		sessions = []store.CareSession{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"sessions": sessions})
}

// updateCareSession: profesional (hadir/tidak, cancel, ringkasan) & pasien (cancel >=24 jam).
func (s *Server) updateCareSession(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	sessionID := r.PathValue("session_id")
	cs, err := s.store.GetCareSession(r.Context(), sessionID)
	if err != nil {
		writeError(w, http.StatusNotFound, errors.New("sesi tidak ditemukan"))
		return
	}
	isPatient := claims.Role == "patient" && claims.Subject == cs.PatientID
	isProf := claims.Role == "professional" && claims.Subject == cs.ProfessionalID
	if !isPatient && !isProf {
		writeError(w, http.StatusForbidden, errors.New("not authorized for this session"))
		return
	}
	var req updateSessionRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	status := strings.ToLower(strings.TrimSpace(req.Status))

	// Update detail saja (meeting_url / ringkasan / catatan) tanpa ubah status.
	if status == "" {
		if !isProf {
			writeError(w, http.StatusForbidden, errors.New("only professionals can update session detail"))
			return
		}
		updated, err := s.store.UpdateCareSessionDetail(r.Context(), sessionID, req.MeetingURL, req.SummaryForPatient, req.PrivateNote)
		if err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		if strings.TrimSpace(req.SummaryForPatient) != "" {
			s.notifyPatient(r, cs.PatientID, "session_summary",
				"Ringkasan sesi tersedia",
				"Profesional membagikan ringkasan sesi terakhirmu.",
				map[string]string{"session_id": sessionID})
		}
		writeJSON(w, http.StatusOK, map[string]any{"session": updated})
		return
	}

	switch {
	case isProf && (status == "completed" || status == "no_show"):
		if time.Now().Before(cs.ScheduledAt.Add(-10 * time.Minute)) {
			writeError(w, http.StatusBadRequest, errors.New("kehadiran baru bisa ditandai sejak 10 menit sebelum sesi"))
			return
		}
		updated, err := s.store.UpdateCareSessionStatus(r.Context(), sessionID, status, "", claims.Subject)
		if err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		if status == "no_show" {
			s.notifyPatient(r, cs.PatientID, "session_no_show",
				"Sesi tercatat tidak hadir",
				"Kamu tercatat tidak hadir; 1 sesi paket hangus sesuai aturan.",
				map[string]string{"session_id": sessionID})
		}
		writeJSON(w, http.StatusOK, map[string]any{"session": updated})
		return
	case status == "cancelled_by_professional":
		// Profesional boleh batal kapan saja sebelum sesi mulai;
		// kredit sesi otomatis kembali ke paket (bisa dijadwal ulang).
		if !isProf {
			writeError(w, http.StatusForbidden, errors.New("only professionals can cancel as professional"))
			return
		}
		if cs.Status != "scheduled" {
			writeError(w, http.StatusBadRequest, errors.New("hanya sesi terjadwal yang bisa dibatalkan"))
			return
		}
		if time.Now().After(cs.ScheduledAt) {
			writeError(w, http.StatusBadRequest, errors.New("sesi sudah lewat, tandai kehadiran sebagai gantinya"))
			return
		}
		updated, err := s.store.UpdateCareSessionStatus(r.Context(), sessionID, status, req.CancelReason, claims.Subject)
		if err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		// Best-effort: batalkan event Google Calendar bila ada.
		if cs.GoogleEventID != "" && s.calendar != nil {
			if cerr := s.calendar.CancelMeetEvent(r.Context(), cs.ProfessionalID, cs.GoogleEventID); cerr != nil {
				s.logger.Warn("gagal membatalkan event Meet saat cancel profesional", "error", cerr, "event_id", cs.GoogleEventID)
			}
		}
		// Ledger kredit otomatis (idempoten): bukti audit kuota kembali.
		refund, creditErr := s.recordAutoCredit(r, updated)
		if creditErr != nil {
			s.logger.Warn("auto credit refund failed", "session", sessionID, "error", creditErr)
		}
		s.notifyPatient(r, cs.PatientID, "session_cancelled_professional",
			"Sesi dibatalkan profesional",
			"Profesional membatalkan sesi. Kredit sesimu kembali dan bisa dijadwalkan ulang atau diminta sebagai refund.",
			map[string]string{"session_id": sessionID})
		writeJSON(w, http.StatusOK, map[string]any{"session": updated, "refund": refund})
		return
	case status == "cancelled_by_patient":
		if !isPatient {
			writeError(w, http.StatusForbidden, errors.New("only patients can cancel as patient"))
			return
		}
		if cs.Status != "scheduled" {
			writeError(w, http.StatusBadRequest, errors.New("hanya sesi terjadwal yang bisa dibatalkan"))
			return
		}
		// Pembatalan pasien <24 jam hangus.
		if time.Until(cs.ScheduledAt) < 24*time.Hour {
			writeError(w, http.StatusBadRequest, errors.New("pembatalan kurang dari 24 jam sebelum sesi: sesi hangus. Hubungi sesi atau tandai tidak hadir"))
			return
		}
		updated, err := s.store.UpdateCareSessionStatus(r.Context(), sessionID, status, req.CancelReason, claims.Subject)
		if err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
		// Best-effort: batalkan event Google Calendar bila ada.
		if cs.GoogleEventID != "" && s.calendar != nil {
			if cerr := s.calendar.CancelMeetEvent(r.Context(), cs.ProfessionalID, cs.GoogleEventID); cerr != nil {
				s.logger.Warn("gagal membatalkan event Meet saat cancel pasien", "error", cerr, "event_id", cs.GoogleEventID)
			}
		}
		s.notifyPatient(r, cs.ProfessionalID, "session_cancelled_patient",
			"Pasien membatalkan sesi", "Seorang pasien membatalkan sesi terjadwal.",
			map[string]string{"session_id": sessionID, "patient_id": cs.PatientID})
		writeJSON(w, http.StatusOK, map[string]any{"session": updated})
		return
	default:
		writeError(w, http.StatusBadRequest, errors.New("status tidak didukung untuk peran ini"))
		return
	}
}

// rescheduleCareSession: pasien >=24 jam sebelum; profesional kapan saja sebelum mulai.
func (s *Server) rescheduleCareSession(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	sessionID := r.PathValue("session_id")
	cs, err := s.store.GetCareSession(r.Context(), sessionID)
	if err != nil {
		writeError(w, http.StatusNotFound, errors.New("sesi tidak ditemukan"))
		return
	}
	isPatient := claims.Role == "patient" && claims.Subject == cs.PatientID
	isProf := claims.Role == "professional" && claims.Subject == cs.ProfessionalID
	if !isPatient && !isProf {
		writeError(w, http.StatusForbidden, errors.New("not authorized for this session"))
		return
	}
	var req rescheduleSessionRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	at, err := parseWIBDateTime(req.ScheduledAt)
	if err != nil {
		writeError(w, http.StatusBadRequest, errors.New("scheduled_at tidak valid (contoh: 2026-10-20T10:00)"))
		return
	}
	if isPatient && time.Until(cs.ScheduledAt) < 24*time.Hour {
		writeError(w, http.StatusBadRequest, errors.New("reschedule pasien minimal 24 jam sebelum sesi"))
		return
	}
	if isProf && time.Now().After(cs.ScheduledAt) {
		writeError(w, http.StatusBadRequest, errors.New("sesi sudah lewat, tidak bisa di-reschedule"))
		return
	}
	// Reschedule pasien tidak boleh melewati kedaluwarsa paket.
	if isPatient && cs.PackageID != nil && *cs.PackageID != "" {
		pkg, perr := s.store.GetCarePackage(r.Context(), *cs.PackageID)
		if perr == nil && !at.Before(pkg.ExpiresAt) {
			writeError(w, http.StatusBadRequest, errors.New("jadwal baru melewati masa berlaku paket"))
			return
		}
	}
	// Validasi slot tujuan: jam praktik, hari libur, dan ketersediaan berlaku
	// untuk kedua peran (dulu tidak dicek sama sekali, padahal dialog
	// reschedule profesional sendiri meminta "pilih slot dalam jam praktikmu").
	// Lead time 24 jam untuk jadwal BARU hanya diterapkan ke pasien.
	if isProf {
		if verr := s.validateSlotWindow(r.Context(), cs.ProfessionalID, at, cs.DurationMinutes); verr != nil {
			writeError(w, http.StatusBadRequest, verr)
			return
		}
	} else if verr := s.validateSlot(r.Context(), cs.ProfessionalID, at, cs.DurationMinutes); verr != nil {
		writeError(w, http.StatusBadRequest, verr)
		return
	}
	updated, err := s.store.RescheduleCareSession(r.Context(), sessionID, at)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	// Best-effort: perbarui event Google Calendar bila ada.
	if cs.GoogleEventID != "" && s.calendar != nil {
		newEnd := at.Add(time.Duration(cs.DurationMinutes) * time.Minute)
		if uerr := s.calendar.UpdateMeetEvent(r.Context(), cs.ProfessionalID, cs.GoogleEventID, at, newEnd); uerr != nil {
			s.logger.Warn("gagal memperbarui event Meet saat reschedule", "error", uerr, "event_id", cs.GoogleEventID)
		}
	}
	other := cs.PatientID
	title := "Sesi di-reschedule profesional"
	if isPatient {
		other = cs.ProfessionalID
		title = "Sesi di-reschedule pasien"
	}
	s.notifyPatient(r, other, "session_rescheduled", title,
		"Sesi dipindahkan ke "+at.In(wibLoc).Format("02 Jan 2006 15:04")+".",
		map[string]string{"session_id": sessionID})
	writeJSON(w, http.StatusOK, map[string]any{"session": updated})
}

// chatPermission: boleh kirim teks? boleh share? sesi berikutnya kapan?
func (s *Server) chatPermission(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	patientID, professionalID, err := s.pairIDs(r, claims)
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	access, err := s.store.ChatAccessFor(r.Context(), patientID, professionalID, claims.Role)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"access": access})
}

// listTimeOff / addTimeOff / deleteTimeOff — profesional mengatur hari libur.
func (s *Server) listTimeOff(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	professionalID := claims.Subject
	if claims.Role == "professional" {
		// ok
	} else {
		professionalID = strings.TrimSpace(r.URL.Query().Get("professional_id"))
		if professionalID == "" {
			writeError(w, http.StatusBadRequest, errors.New("professional_id is required"))
			return
		}
	}
	items, err := s.store.ListTimeOff(r.Context(), professionalID, r.URL.Query().Get("from"), r.URL.Query().Get("to"))
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if items == nil {
		items = []store.ProfessionalTimeOff{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"time_off": items})
}

func (s *Server) addTimeOff(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "professional" {
		writeError(w, http.StatusForbidden, errors.New("only professionals can manage time off"))
		return
	}
	var req timeOffRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	item, err := s.store.AddTimeOff(r.Context(), claims.Subject, req.OffDate, req.Reason)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"time_off": item})
}

func (s *Server) deleteTimeOff(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "professional" {
		writeError(w, http.StatusForbidden, errors.New("only professionals can manage time off"))
		return
	}
	if err := s.store.DeleteTimeOff(r.Context(), claims.Subject, r.PathValue("id")); err != nil {
		writeError(w, http.StatusNotFound, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// getPricing / updatePricing — profesional mengatur harga layanannya sendiri.
func (s *Server) getPricing(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	professionalID := strings.TrimSpace(r.URL.Query().Get("professional_id"))
	if claims.Role == "professional" {
		professionalID = claims.Subject
	}
	if professionalID == "" {
		writeError(w, http.StatusBadRequest, errors.New("professional_id is required"))
		return
	}
	pricing, err := s.store.GetProfessionalPricing(r.Context(), professionalID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"pricing": pricing})
}

func (s *Server) updatePricing(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "professional" {
		writeError(w, http.StatusForbidden, errors.New("only professionals can update pricing"))
		return
	}
	var req pricingRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	current, err := s.store.GetProfessionalPricing(r.Context(), claims.Subject)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if req.QuickChatPrice != nil {
		current.QuickChatPrice = *req.QuickChatPrice
	}
	if req.QuickVideoPrice != nil {
		current.QuickVideoPrice = *req.QuickVideoPrice
	}
	if req.PackagePrice != nil {
		current.PackagePrice = *req.PackagePrice
	}
	current.ProfessionalID = claims.Subject
	updated, err := s.store.UpsertProfessionalPricing(r.Context(), current)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"pricing": updated})
}

// ============================================================
// REFUND / KREDIT PAKET (WS-2)
// ============================================================

type refundRequest struct {
	Kind   string `json:"kind"`
	Reason string `json:"reason"`
}

// defaultRefundKey menyusun idempotency key default bila klien tidak
// mengirim header Idempotency-Key.
func defaultRefundKey(sessionID, kind string) string {
	return fmt.Sprintf("refund:care_session:%s:%s", strings.TrimSpace(sessionID), kind)
}

// recordAutoCredit mencatat ledger kredit idempoten untuk sesi yang
// dibatalkan profesional. Best-effort: kegagalan tidak menggagalkan cancel.
func (s *Server) recordAutoCredit(r *http.Request, cs store.CareSession) (store.CareRefund, error) {
	packageID := ""
	amount := int64(0)
	if cs.PackageID != nil && *cs.PackageID != "" {
		packageID = *cs.PackageID
		if pkg, err := s.store.GetCarePackage(r.Context(), packageID); err == nil {
			amount = pkg.RefundValue
		}
	}
	return s.store.RecordRefund(r.Context(), store.CareRefund{
		PackageID:      packageID,
		SessionID:      cs.ID,
		PatientID:      cs.PatientID,
		ProfessionalID: cs.ProfessionalID,
		Amount:         amount,
		Kind:           "credit",
		Status:         "recorded",
		Reason:         "Sesi dibatalkan profesional; kredit kuota dikembalikan",
		IdempotencyKey: defaultRefundKey(cs.ID, "credit"),
		CreatedBy:      cs.ProfessionalID,
	})
}

// refundCareSession mengeksekusi refund uang (kind=refund) atau mencatat
// kredit (kind=credit) untuk sesi yang dibatalkan profesional.
// RBAC: pasien pemilik / profesional terkait / admin. Idempoten.
func (s *Server) refundCareSession(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	sessionID := r.PathValue("session_id")
	cs, err := s.store.GetCareSession(r.Context(), sessionID)
	if err != nil {
		writeError(w, http.StatusNotFound, errors.New("sesi tidak ditemukan"))
		return
	}
	isPatient := claims.Role == "patient" && claims.Subject == cs.PatientID
	isProf := claims.Role == "professional" && claims.Subject == cs.ProfessionalID
	isAdmin := claims.Role == "admin"
	if !isPatient && !isProf && !isAdmin {
		writeError(w, http.StatusForbidden, errors.New("not authorized for this session"))
		return
	}
	var req refundRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	kind := strings.ToLower(strings.TrimSpace(req.Kind))
	if kind == "" {
		kind = "credit"
	}
	if kind != "credit" && kind != "refund" {
		writeError(w, http.StatusBadRequest, errors.New("kind harus credit atau refund"))
		return
	}
	// Nilai refund = price / total_sessions (dari paket).
	packageID := ""
	amount := int64(0)
	if cs.PackageID != nil && *cs.PackageID != "" {
		packageID = *cs.PackageID
		pkg, perr := s.store.GetCarePackage(r.Context(), packageID)
		if perr != nil {
			writeError(w, http.StatusInternalServerError, perr)
			return
		}
		amount = pkg.RefundValue
	}

	idemKey := strings.TrimSpace(r.Header.Get("Idempotency-Key"))
	if idemKey == "" {
		idemKey = defaultRefundKey(sessionID, kind)
	}

	if kind == "refund" {
		// Refund uang hanya bila sesi dibatalkan profesional.
		if cs.Status != "cancelled_by_professional" {
			writeError(w, http.StatusBadRequest, errors.New("refund uang hanya untuk sesi yang dibatalkan profesional"))
			return
		}
		if amount <= 0 {
			writeError(w, http.StatusBadRequest, errors.New("nilai refund tidak valid (0)"))
			return
		}
		// Cegah double-refund uang: bila sudah ada refund uang untuk sesi ini
		// dengan Idempotency-Key berbeda -> 409.
		if existing, found, qerr := s.store.GetRefundBySessionKind(r.Context(), sessionID, "refund"); qerr != nil {
			writeError(w, http.StatusInternalServerError, qerr)
			return
		} else if found && existing.IdempotencyKey != idemKey {
			writeError(w, http.StatusConflict, errors.New("refund uang untuk sesi ini sudah ada"))
			return
		}
	}

	status := "recorded"
	if kind == "refund" {
		status = "processing"
	}
	refund, err := s.store.RecordRefund(r.Context(), store.CareRefund{
		PackageID:      packageID,
		SessionID:      sessionID,
		PatientID:      cs.PatientID,
		ProfessionalID: cs.ProfessionalID,
		Amount:         amount,
		Kind:           kind,
		Status:         status,
		Reason:         strings.TrimSpace(req.Reason),
		IdempotencyKey: idemKey,
		CreatedBy:      claims.Subject,
	})
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	// Sertakan paket terbaru (remaining + refunded_amount) bila ada.
	resp := map[string]any{"refund": refund}
	if packageID != "" {
		if pkg, perr := s.store.GetCarePackage(r.Context(), packageID); perr == nil {
			resp["package"] = pkg
		}
	}
	if isPatient || isProf {
		other := cs.PatientID
		title := "Refund sesi diproses"
		if isPatient {
			other = cs.ProfessionalID
		}
		s.notifyPatient(r, other, "care_refund_recorded", title,
			"Permintaan refund/kredit sesi tercatat.",
			map[string]string{"session_id": sessionID, "refund_id": refund.ID, "kind": kind})
	}
	writeJSON(w, http.StatusOK, resp)
}

// listCareRefunds mengembalikan riwayat refund/kredit sesuai peran.
func (s *Server) listCareRefunds(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	filter := store.RefundFilter{
		PatientID: strings.TrimSpace(r.URL.Query().Get("patient_id")),
		PackageID: strings.TrimSpace(r.URL.Query().Get("package_id")),
	}
	refunds, err := s.store.ListRefunds(r.Context(), claims.Subject, claims.Role, filter)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if refunds == nil {
		refunds = []store.CareRefund{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"refunds": refunds})
}
