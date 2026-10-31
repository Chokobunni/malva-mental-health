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

// meetPendingWarning dikirim ke klien ketika sesi video berhasil dijadwalkan
// atau dipindahkan tetapi link Meet belum ada. Bukan error: link dibuat
// menyusul (otomatis oleh sweeper pengingat, atau manual oleh profesional).
const meetPendingWarning = "Jadwal tersimpan, tetapi link Google Meet belum tersedia. Link akan dibuat sebelum sesi dimulai."

// meetPendingCode adalah kode mesin untuk klien ketika Google Meet profesional
// belum aktif (izin Calendar belum ada / kedaluwarsa). Klien memakainya untuk
// menampilkan tombol "Hubungkan" ke layar Akun Google.
const meetPendingCode = "meet_belum_aktif"

// errMeetNoLink: event dibuat tetapi Google tidak mengembalikan entry point
// Meet. Sesi video tidak boleh dibuat tanpa ruang pertemuan.
var errMeetNoLink = errors.New("google tidak mengembalikan link Meet untuk event ini")

// ============================================================
// STATUS "GOOGLE MEET SIAP" — satu sumber kebenaran untuk klien.
//
// Alasan (reason) dikirim apa adanya ke aplikasi agar UI bisa membedakan
// keadaan dan menampilkan tindakan yang tepat: pasien tidak boleh disuruh
// "tautkan ulang" akun Google milik profesional, dan profesional tidak boleh
// disuruh "hubungi admin" ketika yang kurang hanya izin Calendar di akunnya
// sendiri.
// ============================================================

const (
	// meetReasonReady: semua syarat terpenuhi, link Meet bisa dibuat sekarang.
	meetReasonReady = "ready"
	// meetReasonNotLinked: akun Malva profesional belum menautkan Gmail.
	meetReasonNotLinked = "not_linked"
	// meetReasonNoCalendarScope: Gmail tertaut, tetapi izin calendar.events
	// belum pernah diberikan (atau baris token belum ada).
	meetReasonNoCalendarScope = "no_calendar_scope"
	// meetReasonTokenExpired: token ada tetapi refresh token kosong/tercabut
	// atau milik akun Google yang berbeda — perlu tautkan ulang.
	meetReasonTokenExpired = "token_expired"
	// meetReasonServerNotConfigured: server belum punya client secret Google
	// (masalah deployment, bukan akun profesional).
	meetReasonServerNotConfigured = "server_not_configured"
)

// meetStatusReason mengklasifikasikan kesiapan Google Meet seorang profesional.
// Dipakai endpoint GET /v1/professionals/{id}/meet-status dan oleh
// googleCalendarReady, sehingga keduanya tidak pernah berbeda pendapat.
func (s *Server) meetStatusReason(ctx context.Context, professionalID string) string {
	if s.calendar == nil || s.store == nil {
		return meetReasonServerNotConfigured
	}
	identity, err := s.store.GetGoogleIdentity(ctx, professionalID)
	if err != nil || !identity.Linked {
		return meetReasonNotLinked
	}
	info, err := s.store.GetGoogleTokenInfo(ctx, professionalID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			// Gmail tertaut tetapi belum pernah menukar authorization code
			// Calendar: izinnya belum ada.
			return meetReasonNoCalendarScope
		}
		// Gagal membaca token: perlakukan seperti belum tertaut agar UI
		// menawarkan tindakan yang aman (hubungkan ulang), bukan "siap".
		return meetReasonNotLinked
	}
	if meetReady(true, identity, info) {
		return meetReasonReady
	}
	if !info.HasRefreshToken || info.GoogleSubject != identity.Subject {
		return meetReasonTokenExpired
	}
	return meetReasonNoCalendarScope
}

// meetStatusHandler menangani GET /v1/professionals/{professional_id}/meet-status.
//
// Tujuan: klien bisa menampilkan status sebelum pasien memilih sesi video,
// sehingga pasien tahu bahwa link akan menyusul (bukan menemui error saat
// menekan "Jadwalkan").
func (s *Server) meetStatusHandler(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	professionalID := strings.TrimSpace(r.PathValue("professional_id"))
	if professionalID == "" {
		writeError(w, http.StatusBadRequest, errors.New("professional_id is required"))
		return
	}
	switch claims.Role {
	case "patient":
		// Pasien boleh memeriksa profesional mana pun (informasi status saja).
	case "professional":
		// Profesional hanya boleh memeriksa statusnya sendiri.
		if claims.Subject != professionalID {
			writeUserError(w, http.StatusForbidden, "Anda hanya bisa memeriksa status Google Meet akun sendiri.")
			return
		}
	default:
		writeUserError(w, http.StatusForbidden, "Peran ini tidak boleh memeriksa status Google Meet.")
		return
	}
	reason := s.meetStatusReason(r.Context(), professionalID)
	writeJSON(w, http.StatusOK, map[string]any{
		"ready":  reason == meetReasonReady,
		"reason": reason,
	})
}

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

// prepareScheduledMeet mencoba membuat link Meet untuk sesi video yang AKAN
// dijadwalkan (baris care_sessions belum ada).
//
// Kontrak: kondisi Google milik profesional tidak boleh memblokir pasien.
// Nilai kembalian:
//   - (meetURL, eventID, false, nil)  -> link siap, simpan apa adanya;
//   - ("", "", true, nil)             -> sesi dibuat "menunggu link"
//     (Google belum siap, izin kedaluwarsa, atau Google sedang gagal);
//   - ("", "", false, ErrMeetUnavailable) -> server belum dikonfigurasi.
//     Ini kesalahan deployment (admin), bukan kesalahan akun profesional,
//     jadi tetap dilaporkan sebagai kegagalan keras.
func (s *Server) prepareScheduledMeet(ctx context.Context, professionalID string, opts googlecal.MeetEventOptions) (string, string, bool, error) {
	if s.calendar == nil {
		return "", "", false, ErrMeetUnavailable
	}
	if !s.googleCalendarReady(ctx, professionalID) {
		return "", "", true, nil
	}
	eventID, meetURL, err := s.createScheduledMeet(ctx, s.calendar, professionalID, opts)
	if err == nil {
		return meetURL, eventID, false, nil
	}
	if errors.Is(err, ErrMeetUnavailable) {
		return "", "", false, err
	}
	// ErrReauthNeeded / errMeetNoLink / galat Google lain (5xx, jaringan):
	// sesi tetap dijadwalkan, link menyusul.
	if s.logger != nil {
		s.logger.Warn("link Meet belum bisa dibuat; sesi dijadwalkan menunggu link",
			"error", err, "professional", professionalID)
	}
	return "", "", true, nil
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

// isVideoSession true bila tipe sesi menuntut ruang pertemuan.
func isVideoSession(sessionType string) bool {
	return strings.EqualFold(strings.TrimSpace(sessionType), "video")
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
	return s.createMeetLinkAt(ctx, cs, time.Time{})
}

// createMeetLinkAt seperti createMeetLink, tetapi event dibuat pada jam [start]
// bila tidak zero.
//
// Dipakai saat reschedule sesi video lama yang belum punya link: event harus
// lahir di jam BARU, bukan jam lama, agar kalender profesional tidak sempat
// menampilkan slot yang salah.
func (s *Server) createMeetLinkAt(ctx context.Context, cs store.CareSession, start time.Time) (store.CareSession, error) {
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
	if !start.IsZero() {
		cs.ScheduledAt = start
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
		if cerr := s.calendar.CancelMeetEvent(ctx, cs.ProfessionalID, eventID); cerr != nil && s.logger != nil {
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

// prepareMeetEventFor mencoba membuat link Meet untuk sesi yang BELUM
// tersimpan, memakai semantik degradasi yang SAMA dengan jalur penjadwalan
// (prepareScheduledMeet).
//
// Dipakai aktivasi pembayaran: baris care_sessions dibuat setelah helper ini
// selesai (store menolak sesi video tanpa link kecuali AllowPendingMeet).
// Ringkasan event memuat nama pasien dan profesional.
//
// Nilai kembalian sama dengan prepareScheduledMeet:
//   - (meetURL, eventID, false, nil) -> link siap, simpan apa adanya;
//   - ("", "", true, nil)            -> sesi dibuat "menunggu link";
//   - ("", "", false, ErrMeetUnavailable) -> server belum dikonfigurasi Google.
func (s *Server) prepareMeetEventFor(ctx context.Context, patientID, professionalID string, start time.Time, durationMinutes int) (string, string, bool, error) {
	// Cek konfigurasi server lebih dulu agar GetUserByID tidak dipanggil pada
	// Server parsial (test) yang store-nya nil. prepareScheduledMeet juga
	// memeriksa ini, tetapi di sini opsi event dibangun sebelum memanggilnya.
	if s.calendar == nil {
		return "", "", false, ErrMeetUnavailable
	}
	if durationMinutes <= 0 {
		durationMinutes = 30
	}
	opts := googlecal.MeetEventOptions{
		Summary:        "Sesi Malva",
		Description:    "Sesi video konsultasi Malva. Bergabung melalui tombol \"Gabung\" di aplikasi Malva.",
		StartTime:      start,
		EndTime:        start.Add(time.Duration(durationMinutes) * time.Minute),
		AttendeeEmails: s.meetAttendees(ctx, patientID),
	}
	// Nama hanya pelengkap; kegagalan membaca nama tidak boleh menggagalkan
	// pembuatan ruang pertemuan.
	if u, err := s.store.GetUserByID(ctx, patientID); err == nil && strings.TrimSpace(u.DisplayName) != "" {
		opts.Summary = "Sesi Malva - " + strings.TrimSpace(u.DisplayName)
	}
	if u, err := s.store.GetUserByID(ctx, professionalID); err == nil && strings.TrimSpace(u.DisplayName) != "" {
		opts.Description += "\nProfesional: " + strings.TrimSpace(u.DisplayName)
	}
	return s.prepareScheduledMeet(ctx, professionalID, opts)
}

// googleCalendarReady melaporkan apakah profesional dapat membuat link Meet
// saat ini: server terkonfigurasi, identitas tertaut, token milik akun Google
// yang sama, punya refresh token, dan memberi izin calendar.events.
//
// Dipakai sebelum booking sesi video dibuat, agar pasien tidak membayar untuk
// sesi yang ruang pertemuannya tidak mungkin dibuat. Definisi "siap" tidak
// diduplikasi di sini: lihat meetStatusReason/meetReady.
func (s *Server) googleCalendarReady(ctx context.Context, professionalID string) bool {
	return s.meetStatusReason(ctx, professionalID) == meetReasonReady
}

// meetReady adalah satu-satunya definisi "Google Meet siap" untuk seorang
// profesional. Dipakai status handler maupun pemeriksaan sebelum booking,
// supaya kedua tempat tidak pernah berbeda pendapat.
func meetReady(serverConfigured bool, identity store.GoogleIdentity, info store.GoogleTokenInfo) bool {
	return serverConfigured &&
		identity.Linked &&
		info.GoogleSubject == identity.Subject &&
		info.HasRefreshToken &&
		store.HasCalendarScope(info.Scope)
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
		writeUserError(w, http.StatusForbidden, "Anda tidak berhak atas sesi ini.")
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
	// Server tanpa konfigurasi Google: masalah deployment, bukan akun
	// profesional — tetap 501 seperti sebelumnya.
	if s.calendar == nil {
		writeError(w, http.StatusNotImplemented, ErrMeetUnavailable)
		return
	}
	// Google Meet profesional belum aktif (Gmail belum tertaut, izin
	// calendar.events belum ada, atau token perlu ditautkan ulang). Pesannya
	// berbeda untuk pasien & profesional: pasien tidak bisa memperbaiki akun
	// Google orang lain, jadi jangan menyuruhnya "tautkan ulang".
	if !s.googleCalendarReady(r.Context(), cs.ProfessionalID) {
		message := "Profesional belum mengaktifkan Google Calendar, sehingga link video belum bisa dibuat. Link akan dibuat otomatis setelah profesional mengaktifkannya."
		if isProf {
			message = "Google Calendar Anda belum aktif. Buka Pengaturan → Akun Google → Hubungkan Google Calendar, lalu coba lagi."
		}
		writeJSON(w, http.StatusConflict, map[string]string{
			"error": message,
			"code":  meetPendingCode,
		})
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
		s.writeGoogleIdentityError(w, r, err)
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
		writeUserError(w, http.StatusInternalServerError, "Gagal memuat status Google Calendar.")
		return
	}
	ready := meetReady(s.calendar != nil, identity, info)
	resp["connected"] = ready
	resp["calendar_ready"] = ready
	resp["scope"] = info.Scope
	resp["expires_at"] = info.TokenExpiry
	resp["updated_at"] = info.UpdatedAt
	writeJSON(w, http.StatusOK, resp)
}
