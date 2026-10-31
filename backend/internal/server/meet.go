package server

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"strings"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
	googlecal "malva/backend/internal/google"
	"malva/backend/internal/store"
)

// ErrMeetUnavailable dikembalikan bila integrasi Google Meet belum aktif di
// server (MALVA_GOOGLE_CLIENT_SECRET kosong). Tidak ada fallback: sesi video
// wajib memakai Google Meet.
var ErrMeetUnavailable = errors.New("google Meet belum dikonfigurasi di server")

// meetCalendar adalah irisan minimal *googlecal.CalendarService yang benar-benar
// dipakai handler. Dibuat sebagai interface kecil agar alur Meet bisa diuji
// dengan fake tanpa memanggil Google. *googlecal.CalendarService otomatis
// memenuhi interface ini (tidak perlu adapter).
type meetCalendar interface {
	CreateMeetEvent(ctx context.Context, professionalUserID string, opts googlecal.MeetEventOptions) (string, string, error)
	UpdateMeetEvent(ctx context.Context, professionalUserID, eventID string, newStart, newEnd time.Time) error
	CancelMeetEvent(ctx context.Context, professionalUserID, eventID string) error
}

// meetUpdateWarning adalah pesan Indonesia yang dikirim ke klien ketika event
// Google Calendar gagal diperbarui padahal jadwal sesi sudah tersimpan.
const meetUpdateWarning = "Jadwal tersimpan, tetapi event Google Calendar gagal diperbarui. Minta profesional menautkan ulang Google atau periksa kalender."

// errMeetNoLink: event dibuat tetapi Google tidak mengembalikan entry point
// Meet. Sesi video tidak boleh dibuat tanpa ruang pertemuan.
var errMeetNoLink = errors.New("google tidak mengembalikan link Meet untuk event ini")

// createScheduledMeet membuat event Meet untuk sesi video yang dijadwalkan
// tanpa link manual. Nilai (eventID, meetURL) yang dikembalikan adalah yang
// kemudian disimpan pemanggil ke care_sessions. Event tanpa entry point Meet
// dibatalkan agar tidak ada event menggantung di kalender profesional.
func (s *Server) createScheduledMeet(ctx context.Context, cal meetCalendar, professionalID string, opts googlecal.MeetEventOptions) (string, string, error) {
	if cal == nil {
		return "", "", ErrMeetUnavailable
	}
	eventID, meetURL, err := cal.CreateMeetEvent(ctx, professionalID, opts)
	if err != nil {
		return "", "", err
	}
	if strings.TrimSpace(meetURL) == "" {
		if strings.TrimSpace(eventID) != "" {
			if cerr := cal.CancelMeetEvent(ctx, professionalID, eventID); cerr != nil && s.logger != nil {
				s.logger.Warn("gagal membatalkan event Meet tanpa link", "error", cerr, "event_id", eventID)
			}
		}
		return "", "", errMeetNoLink
	}
	return eventID, meetURL, nil
}

// updateMeetEventOnReschedule memindahkan event Meet ke jadwal baru sesi.
// Jadwal sudah tersimpan di database, jadi kegagalan Google TIDAK menggagalkan
// reschedule; kegagalan dikembalikan sebagai daftar warning agar bisa
// ditampilkan di respons dan dinotifikasikan ke profesional.
func (s *Server) updateMeetEventOnReschedule(ctx context.Context, cal meetCalendar, professionalID, eventID string, newStart time.Time, durationMinutes int) []string {
	if strings.TrimSpace(eventID) == "" || cal == nil {
		return nil
	}
	if durationMinutes <= 0 {
		durationMinutes = 30
	}
	newEnd := newStart.Add(time.Duration(durationMinutes) * time.Minute)
	if err := cal.UpdateMeetEvent(ctx, professionalID, eventID, newStart, newEnd); err != nil {
		if s.logger != nil {
			s.logger.Warn("gagal memperbarui event Meet saat reschedule", "error", err, "event_id", eventID)
		}
		return []string{meetUpdateWarning}
	}
	return nil
}

// cancelMeetEventBestEffort membatalkan event Meet milik sesi yang dibatalkan.
// Pembatalan sesi sudah tersimpan di database, jadi kegagalan Google hanya
// dicatat — bukan alasan menggagalkan pembatalan.
func (s *Server) cancelMeetEventBestEffort(ctx context.Context, cal meetCalendar, professionalID, eventID string) {
	if strings.TrimSpace(eventID) == "" || cal == nil {
		return
	}
	if err := cal.CancelMeetEvent(ctx, professionalID, eventID); err != nil && s.logger != nil {
		s.logger.Warn("gagal membatalkan event Meet", "error", err, "event_id", eventID)
	}
}

// isGoogleMeetURL true bila URL menunjuk ke Google Meet. Dipakai untuk
// mengenali link lama dari penyedia lain (mis. Jitsi) yang harus diganti.
func isGoogleMeetURL(u string) bool {
	return strings.Contains(strings.ToLower(strings.TrimSpace(u)), "meet.google.com/")
}

// meetAttendees mengumpulkan email peserta yang diundang ke event Calendar.
// Email pasien diundang agar menerima undangan + pengingat dari Google.
// Kegagalan mengambil email tidak menggagalkan pembuatan link.
func (s *Server) meetAttendees(ctx context.Context, patientID string) []string {
	email, err := s.store.GetUserEmail(ctx, patientID)
	if err != nil || strings.TrimSpace(email) == "" {
		return nil
	}
	return []string{strings.TrimSpace(email)}
}

// meetEventOptions menyusun parameter event Meet untuk satu sesi.
func (s *Server) meetEventOptions(ctx context.Context, cs store.CareSession) googlecal.MeetEventOptions {
	start := cs.ScheduledAt
	duration := cs.DurationMinutes
	if duration <= 0 {
		duration = 30
	}
	summary := "Sesi Malva"
	if strings.TrimSpace(cs.PatientName) != "" {
		summary = "Sesi Malva - " + strings.TrimSpace(cs.PatientName)
	}
	desc := "Sesi video konsultasi Malva. Bergabung melalui tombol \"Gabung\" di aplikasi Malva."
	if strings.TrimSpace(cs.ProfessionalName) != "" {
		desc += "\nProfesional: " + strings.TrimSpace(cs.ProfessionalName)
	}
	return googlecal.MeetEventOptions{
		Summary:        summary,
		Description:    desc,
		StartTime:      start,
		EndTime:        start.Add(time.Duration(duration) * time.Minute),
		AttendeeEmails: s.meetAttendees(ctx, cs.PatientID),
	}
}

// createMeetLink membuat event Google Calendar + link Meet untuk sesi yang
// belum punya link, lalu menyimpannya. Bila sesi sudah punya link, sesi
// dikembalikan apa adanya (idempoten).
//
// Pemanggil bertanggung jawab memastikan sesi bertipe video dan berstatus
// scheduled.
func (s *Server) createMeetLink(ctx context.Context, cs store.CareSession) (store.CareSession, error) {
	// Tanpa integrasi Google, tidak ada yang bisa dibuat — gagal cepat tanpa
	// menyentuh database. Urutan penting: GetCareSession di bawah memakai
	// s.store yang bisa nil pada Server parsial (test).
	if s.calendar == nil {
		return cs, ErrMeetUnavailable
	}
	// Ambil data terbaru agar ringkasan event memuat nama pasien dan
	// pemeriksaan meeting_url memakai keadaan sebenarnya di database.
	if fresh, err := s.store.GetCareSession(ctx, cs.ID); err == nil {
		cs = fresh
	}
	if strings.TrimSpace(cs.MeetingURL) != "" && isGoogleMeetURL(cs.MeetingURL) {
		return cs, nil
	}
	// Link lama dari penyedia lain (Jitsi dsb.) dianggap belum ada: Google
	// Meet adalah satu-satunya penyedia yang didukung sekarang.
	cs.MeetingURL = ""
	eventID, meetURL, err := s.calendar.CreateMeetEvent(ctx, cs.ProfessionalID, s.meetEventOptions(ctx, cs))
	if err != nil {
		return cs, err
	}
	if strings.TrimSpace(meetURL) == "" {
		// Event dibuat tetapi Google tidak mengembalikan entry point Meet.
		// Jangan simpan event tanpa link: batalkan agar tidak ada event
		// menggantung di kalender profesional.
		if cerr := s.calendar.CancelMeetEvent(ctx, cs.ProfessionalID, eventID); cerr != nil {
			s.logger.Warn("gagal membatalkan event Meet tanpa link", "error", cerr, "event_id", eventID)
		}
		return cs, errors.New("google tidak mengembalikan link Meet untuk event ini")
	}
	updated, err := s.store.UpdateCareSessionMeeting(ctx, cs.ID, meetURL, eventID)
	if err != nil {
		return cs, err
	}
	return updated, nil
}

// ensureMeetLinkBestEffort dipakai di alur yang tidak boleh gagal karena
// masalah Google (mis. setelah pembayaran lunas). Kegagalan hanya dicatat.
func (s *Server) ensureMeetLinkBestEffort(ctx context.Context, cs store.CareSession) store.CareSession {
	if cs.SessionType != "video" || isGoogleMeetURL(cs.MeetingURL) {
		return cs
	}
	updated, err := s.createMeetLink(ctx, cs)
	if err != nil {
		// s.logger selalu terisi pada Server produksi (dibuat di New), tetapi
		// helper ini harus tahan dipanggil dari Server parsial (test) — jangan
		// sampai pencatatan kegagalan ikut mematikan alur pemanggil.
		if s.logger != nil {
			s.logger.Warn("gagal membuat link Google Meet; link bisa dibuat menyusul",
				"error", err, "session", cs.ID, "professional", cs.ProfessionalID)
		}
		return cs
	}
	return updated
}

// ensureMeetLinkHandler menangani POST /v1/care-sessions/{session_id}/meet-link.
// Membuat (atau mengembalikan) link Meet untuk sesi video. Bisa dipanggil
// pasien maupun profesional pemilik sesi — link selalu dibuat di kalender
// profesional.
func (s *Server) ensureMeetLinkHandler(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	sessionID := r.PathValue("session_id")
	cs, err := s.store.GetCareSession(r.Context(), sessionID)
	if err != nil {
		writeError(w, http.StatusNotFound, errors.New("sesi tidak ditemukan"))
		return
	}
	isPatient := claims.Role == "patient" && claims.Subject == cs.PatientID
	isProf := claims.Role == "professional" && claims.Subject == cs.ProfessionalID
	if !isPatient && !isProf {
		writeError(w, http.StatusForbidden, errors.New("Anda tidak berhak atas sesi ini."))
		return
	}
	if cs.SessionType != "video" {
		writeError(w, http.StatusBadRequest, errors.New("sesi ini bukan sesi video"))
		return
	}
	if cs.Status != "scheduled" {
		writeError(w, http.StatusBadRequest, errors.New("link hanya bisa dibuat untuk sesi berstatus scheduled"))
		return
	}
	if isGoogleMeetURL(cs.MeetingURL) {
		writeJSON(w, http.StatusOK, map[string]any{"session": cs, "created": false})
		return
	}
	updated, err := s.createMeetLink(r.Context(), cs)
	if err != nil {
		if errors.Is(err, ErrMeetUnavailable) {
			writeError(w, http.StatusNotImplemented, ErrMeetUnavailable)
			return
		}
		if errors.Is(err, googlecal.ErrReauthNeeded) {
			// Hanya profesional yang bisa menautkan ulang akun Google.
			if isProf {
				writeError(w, http.StatusUnauthorized,
					errors.New("akses Google Calendar kedaluwarsa. Tautkan ulang akun Google di Pengaturan"))
			} else {
				writeError(w, http.StatusConflict,
					errors.New("profesional belum menautkan atau perlu menautkan ulang akun Google. Hubungi profesional"))
			}
			return
		}
		s.logger.Warn("gagal membuat link Meet", "error", err, "session", sessionID)
		writeError(w, http.StatusBadGateway,
			errors.New("gagal membuat link Google Meet. Coba lagi beberapa saat lagi"))
		return
	}
	// Beri tahu lawan bicara bahwa link sudah tersedia.
	if isProf {
		s.notifyPatient(r, cs.PatientID, "session_meet_ready", "Link video call siap",
			"Link Google Meet untuk sesimu sudah tersedia. Buka detail sesi untuk bergabung.",
			map[string]string{"session_id": cs.ID})
	} else {
		s.notifyPatient(r, cs.ProfessionalID, "session_meet_ready", "Link video call siap",
			"Pasien membuka link Google Meet untuk sesi ini.",
			map[string]string{"session_id": cs.ID, "patient_id": cs.PatientID})
	}
	writeJSON(w, http.StatusCreated, map[string]any{"session": updated, "created": true})
}

// RunSessionReminders mengirim pengingat untuk sesi yang akan dimulai dalam
// 15-25 menit ke pasien dan profesional. Dipanggil berkala oleh sweeper di
// cmd/api. Mengembalikan jumlah sesi yang diproses.
//
// Jendela 10 menit dibuat lebih lebar/lebih rapat dari interval ticker (10
// menit) agar setiap sesi tepat masuk satu kali. Kolom reminder_sent_at
// mencegah pengingat ganda.
func (s *Server) RunSessionReminders(ctx context.Context) (int, error) {
	now := clock.Now()
	if s.store == nil {
		return 0, errors.New("store belum diinisialisasi")
	}
	sessions, err := s.store.ListSessionsForReminder(ctx, now.Add(15*time.Minute), now.Add(25*time.Minute))
	if err != nil {
		return 0, err
	}
	sent := 0
	logWarn := func(msg string, args ...any) {
		// s.logger selalu terisi pada Server produksi (dibuat di New), guard
		// ini menjaga Server parsial (test) — pola sama seperti
		// ensureMeetLinkBestEffort.
		if s.logger != nil {
			s.logger.Warn(msg, args...)
		}
	}
	for _, cs := range sessions {
		// Sesi video tanpa link: coba buat sekarang agar pengingat berisi link.
		if cs.SessionType == "video" {
			cs = s.ensureMeetLinkBestEffort(ctx, cs)
		}
		when := cs.ScheduledAt.In(clock.Location()).Format("02 Jan 15:04")
		link := ""
		if strings.TrimSpace(cs.MeetingURL) != "" {
			link = " Link: " + cs.MeetingURL
		}
		s.notifyUser(ctx, cs.PatientID, "session_reminder",
			"Sesi dimulai sebentar lagi",
			"Sesi dengan profesional dimulai "+when+"."+link,
			map[string]string{"session_id": cs.ID, "meeting_url": cs.MeetingURL})
		profBody := "Sesi dengan pasien dimulai " + when + "." + link
		if strings.TrimSpace(cs.PatientName) != "" {
			profBody = "Sesi dengan " + cs.PatientName + " dimulai " + when + "." + link
		}
		s.notifyUser(ctx, cs.ProfessionalID, "session_reminder",
			"Sesi dimulai sebentar lagi", profBody,
			map[string]string{"session_id": cs.ID, "meeting_url": cs.MeetingURL, "patient_id": cs.PatientID})
		if err := s.store.MarkSessionReminderSent(ctx, cs.ID); err != nil {
			logWarn("gagal menandai pengingat terkirim", "error", err, "session", cs.ID)
			continue
		}
		sent++
	}
	return sent, nil
}

// BackfillMissingMeetLinks membuat link Meet untuk sesi video terjadwal yang
// belum punya link (mis. sesi lama sebelum integrasi dipasang, atau sesi yang
// pembuatan link-nya gagal saat pembayaran). Dibatasi limit per pemanggilan.
func (s *Server) BackfillMissingMeetLinks(ctx context.Context, limit int) (int, error) {
	if s.calendar == nil {
		return 0, ErrMeetUnavailable
	}
	sessions, err := s.store.ListCareSessionsNeedingMeetLink(ctx, limit)
	if err != nil {
		return 0, err
	}
	created := 0
	for _, cs := range sessions {
		if _, err := s.createMeetLink(ctx, cs); err != nil {
			s.logger.Warn("backfill link Meet gagal", "error", err, "session", cs.ID)
			continue
		}
		created++
	}
	return created, nil
}

// googleStatusHandler menangani GET /v1/google/status. Profesional dapat
// memastikan akun Google-nya masih tertaut sebelum sesi dimulai, tanpa harus
// menunggu pembuatan Meet gagal.
func (s *Server) googleStatusHandler(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "professional" {
		writeError(w, http.StatusForbidden, errors.New("endpoint ini hanya untuk profesional"))
		return
	}
	identity, err := s.store.GetGoogleIdentity(r.Context(), claims.Subject)
	if err != nil {
		writeGoogleIdentityError(w, err)
		return
	}
	resp := map[string]any{
		"server_configured": s.calendar != nil,
		"identity_bound":    identity.Linked,
		"calendar_ready":    false,
		"connected":         false,
	}
	info, err := s.store.GetGoogleTokenInfo(r.Context(), claims.Subject)
	if errors.Is(err, sql.ErrNoRows) {
		writeJSON(w, http.StatusOK, resp)
		return
	}
	if err != nil {
		writeError(w, http.StatusInternalServerError, errors.New("Gagal memuat status Google Calendar."))
		return
	}
	ready := s.calendar != nil && identity.Linked && info.GoogleSubject == identity.Subject && info.HasRefreshToken && store.HasCalendarScope(info.Scope)
	resp["connected"] = ready
	resp["calendar_ready"] = ready
	resp["scope"] = info.Scope
	resp["expires_at"] = info.TokenExpiry
	resp["updated_at"] = info.UpdatedAt
	writeJSON(w, http.StatusOK, resp)
}
