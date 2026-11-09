package server

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"net/url"
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

// userMessageError membawa pesan siap-tampil (Indonesia, boleh berkapital dan
// berakhir titik) tanpa melanggar ST1005 yang hanya memeriksa literal
// errors.New/fmt.Errorf. Dipakai untuk pesan validasi yang memang dibaca
// pengguna lewat writeUserError, agar nadanya tetap sopan.
type userMessageError string

func (e userMessageError) Error() string { return string(e) }

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

// meetPendingNotices menyusun teks notifikasi "link Meet belum ada" untuk
// pasien (sufiks badan) dan profesional (judul + badan).
//
// serverUnavailable=true berarti integrasi Google di server mati
// (ErrMeetUnavailable): tombol "Buat link Meet" akan membalas 501, sehingga
// profesional TIDAK boleh disuruh menekannya (jalan buntu), dan pasien tidak
// boleh dijanjikan link "sebelum sesi dimulai" karena tidak ada yang bisa
// memenuhi janji itu sampai admin mengaktifkan integrasi. Pesannya tetap
// menenangkan: sesi sudah terjadwal dan pembayaran tidak hangus.
func meetPendingNotices(when string, serverUnavailable bool) (patientSuffix, profTitle, profBody string) {
	if serverUnavailable {
		return " Link video akan dibuat otomatis setelah integrasi video di server aktif; hubungi dukungan bila sesi sudah dekat dan link belum muncul.",
			"Link Google Meet belum bisa dibuat",
			"Sesi video dengan pasien dijadwalkan pada " + when + " tetapi integrasi Google Meet di server belum aktif. Tidak ada tindakan yang bisa dilakukan dari akun Anda; link dibuat otomatis begitu admin mengaktifkan integrasi."
	}
	return " Link video akan tersedia sebelum sesi dimulai.",
		"Buat link Google Meet untuk sesi ini",
		"Sesi video dengan pasien dijadwalkan pada " + when + " tetapi link Meet belum ada. Buka detail sesi lalu tekan \"Buat link Meet\"."
}

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
	// meetReasonTokenExpiringSoon: semua syarat "siap" terpenuhi dan link Meet
	// MASIH bisa dibuat, tetapi umur refresh token mendekati batas (mode
	// Testing = 7 hari). Reason ini hanya untuk memberi tahu profesional agar
	// menekan "Perbarui izin" sebelum benar-benar kedaluwarsa — bukan alasan
	// memblokir pembuatan link.
	meetReasonTokenExpiringSoon = "token_hampir_kedaluwarsa"
	// meetReasonServerNotConfigured: server belum punya client secret Google
	// (masalah deployment, bukan akun profesional).
	meetReasonServerNotConfigured = "server_not_configured"
)

// meetStatusHint mengembalikan saran tindakan berbahasa Indonesia untuk
// `reason` yang menandakan akun profesional belum siap membuat link Meet.
// Kosong untuk reason yang sudah siap (ready / token_hampir_kedaluwarsa) dan
// untuk masalah deployment (server_not_configured) yang bukan urusan
// profesional. Hint TIDAK membocorkan token — hanya langkah perbaikan.
func meetStatusHint(reason string) string {
	switch reason {
	case meetReasonNotLinked:
		return "Hubungkan Gmail Anda dulu di Pengaturan → Akun Google. Jika Gmail muncul sebagai Test user, mintalah admin menambahkannya ke OAuth consent screen."
	case meetReasonNoCalendarScope:
		return "Gmail sudah tertaut, tetapi izin Google Calendar belum diberikan. Tekan \"Hubungkan Google Calendar\" dan setujui akses kalender."
	case meetReasonTokenExpired:
		return "Izin Google Calendar sudah tidak berlaku. Tautkan ulang akun Google di Pengaturan → Akun Google agar link Meet bisa dibuat lagi."
	default:
		return ""
	}
}

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
		if s.refreshTokenExpiringSoon(info) {
			return meetReasonTokenExpiringSoon
		}
		return meetReasonReady
	}
	if !info.HasRefreshToken || info.GoogleSubject != identity.Subject {
		return meetReasonTokenExpired
	}
	return meetReasonNoCalendarScope
}

// googleRefreshTokenTTL adalah umur refresh token Google sebelum dianggap
// mendekati kedaluwarsa, dari konfigurasi MALVA_GOOGLE_REFRESH_TOKEN_TTL_DAYS.
// Nilai <= 0 berarti peringatan dinonaktifkan (return 0).
func (s *Server) googleRefreshTokenTTL() time.Duration {
	if s.cfg.GoogleRefreshTokenTTLDays <= 0 {
		return 0
	}
	return time.Duration(s.cfg.GoogleRefreshTokenTTLDays) * 24 * time.Hour
}

// googleTokenWarnLead adalah JENDELA PERINGATAN: berapa lama SEBELUM izin
// benar-benar mati status mulai berubah menjadi `token_hampir_kedaluwarsa` di
// endpoint meet-status. Ini HANYA memengaruhi status yang dilihat profesional
// di aplikasi — TIDAK mengirim notifikasi/push/banner/dialog apa pun, sesuai
// keputusan produk bahwa pengguna tidak boleh terganggu notifikasi sistem.
//
// Jendela dua hari mempertahankan klasifikasi status selama Testing. Link Meet
// tetap dapat dibuat dan pasien tidak diblokir hanya karena umur grant.
// Ambang hanya ditetapkan di sini, tidak diduplikasi di job latar belakang.
const googleTokenWarnLead = 48 * time.Hour

// googleTokenWarnFrom menghitung titik mulai peringatan untuk sebuah TTL.
// Mengembalikan false bila peringatan dinonaktifkan (TTL <= 0). Jendela
// peringatan tidak pernah melebihi setengah TTL, agar TTL pendek (mis. 1 hari)
// tidak membuat status "hampir kedaluwarsa" menyala terus sejak awal dan
// menghilangkan maknanya.
func googleTokenWarnFrom(ttl time.Duration) (time.Duration, bool) {
	if ttl <= 0 {
		return 0, false
	}
	lead := googleTokenWarnLead
	if half := ttl / 2; lead > half {
		lead = half
	}
	return ttl - lead, true
}

// googleTokenExpiringSoon melaporkan apakah umur grant sudah mencapai titik
// mulai peringatan. Hanya dipakai meetStatusReason lewat refreshTokenExpiringSoon;
// tidak ada ambang terpisah atau notifikasi dari job latar belakang.
func googleTokenExpiringSoon(issuedAt, now time.Time, ttl time.Duration) bool {
	warnFrom, ok := googleTokenWarnFrom(ttl)
	if !ok {
		return false
	}
	return now.Sub(issuedAt) >= warnFrom
}

// refreshTokenExpiringSoon melaporkan apakah umur grant refresh token sudah
// mencapai ambang peringatan. Mengembalikan false bila peringatan dinonaktifkan
// (TTL 0). Tidak mengubah meetReady: link Meet tetap bisa dibuat selama token
// belum mati.
func (s *Server) refreshTokenExpiringSoon(info store.GoogleTokenInfo) bool {
	return googleTokenExpiringSoon(info.RefreshTokenIssuedAt, clock.Now(), s.googleRefreshTokenTTL())
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
	// `ready` menandakan link Meet BISA dibuat sekarang. `token_hampir_kedaluwarsa`
	// tetap ready (link masih bisa dibuat) — reason-nya saja yang meminta
	// profesional memperbarui izin lebih awal.
	resp := map[string]any{
		"ready":                         reason == meetReasonReady || reason == meetReasonTokenExpiringSoon,
		"reason":                        reason,
		"refresh_token_age_days":        0,
		"refresh_token_expires_in_days": -1,
	}
	// `google_email` = email akun Google yang tertaut (bila ada). Berguna bagi
	// UI untuk memberi tahu profesional Gmail MANA yang harus didaftarkan
	// sebagai Test user ketika Google memblokir access_denied. Tidak pernah
	// membocorkan token — hanya alamat email yang memang milik profesional ini.
	// Hanya profesional pemilik yang melihat email; pasien cukup melihat status.
	if s.store != nil {
		if identity, ierr := s.store.GetGoogleIdentity(r.Context(), professionalID); ierr == nil &&
			identity.Linked && claims.Role == "professional" {
			resp["google_email"] = identity.Email
		}
	}
	// `hint` = saran tindakan berbahasa Indonesia untuk reason yang butuh
	// perbaikan akun. Hanya disertakan untuk profesional pemilik akun, karena
	// pasien tidak bisa memperbaiki akun Google orang lain.
	if claims.Role == "professional" {
		if hint := meetStatusHint(reason); hint != "" {
			resp["hint"] = hint
		}
	}
	// Isi umur & sisa hari grant bila token tersedia. Nilai default di atas
	// dipakai untuk keadaan tanpa token (mis. not_linked / server_not_configured)
	// agar klien lama tetap aman.
	if s.store != nil {
		if info, ierr := s.store.GetGoogleTokenInfo(r.Context(), professionalID); ierr == nil {
			age := clock.Now().Sub(info.RefreshTokenIssuedAt)
			ageDays := int(age.Hours() / 24)
			if ageDays < 0 {
				ageDays = 0
			}
			resp["refresh_token_age_days"] = ageDays
			if ttl := s.googleRefreshTokenTTL(); ttl > 0 {
				remaining := ttl - age
				if remaining < 0 {
					remaining = 0
				}
				// Bulatkan ke atas: sisa 0,5 hari tetap ditampilkan "1 hari".
				expiresDays := int((remaining + 24*time.Hour - 1) / (24 * time.Hour))
				resp["refresh_token_expires_in_days"] = expiresDays
			}
		}
	}
	writeJSON(w, http.StatusOK, resp)
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
		durationMinutes = 60
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
		duration = 60
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
		durationMinutes = 60
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
	// `token_hampir_kedaluwarsa` tetap dianggap siap: link Meet masih bisa
	// dibuat selama refresh token belum mati. Peringatan hanya lewat UI.
	reason := s.meetStatusReason(ctx, professionalID)
	return reason == meetReasonReady || reason == meetReasonTokenExpiringSoon
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

// meetManualURLRequest adalah body untuk PUT /v1/care-sessions/{session_id}/meet-link.
type meetManualURLRequest struct {
	MeetURL string `json:"meet_url"`
}

// setManualMeetLinkHandler menangani PUT /v1/care-sessions/{session_id}/meet-link.
//
// Ini adalah JALUR FALLBACK agar profesional tetap bisa menyelenggarakan sesi
// video ketika Google Calendar tidak bisa dipakai (mis. Gmail belum terdaftar
// sebagai Test user pada OAuth consent screen sehingga Google memblokir
// access_denied SEBELUM callback). Profesional membuat link Google Meet secara
// manual (mis. dari Google Calendar pribadinya) lalu menempelkannya di sini.
//
// Batasan & otorisasi:
//   - HANYA profesional pemilik sesi yang boleh menempelkan link manual. Pasien
//     tidak boleh mengubah tujuan link video.
//   - Sesi harus bertipe video dan berstatus scheduled.
//   - URL divalidasi ketat: wajib https, host meet.google.com, panjang wajar.
//     Provider lain (zoom.us dsb.) belum didukung repo ini — lihat
//     isGoogleMeetURL — jadi ditolak 400.
//   - Fallback ini TIDAK melemahkan gerbang booking berbayar: createBooking
//     tetap menolak 409 meet_belum_aktif sebelum bayar. Manual link hanya untuk
//     sesi yang sudah ada.
func (s *Server) setManualMeetLinkHandler(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	sessionID := r.PathValue("session_id")
	cs, err := s.store.GetCareSession(r.Context(), sessionID)
	if err != nil {
		writeError(w, http.StatusNotFound, errors.New("sesi tidak ditemukan"))
		return
	}
	// Hanya profesional pemilik sesi yang boleh menempelkan link manual.
	if claims.Role != "professional" || claims.Subject != cs.ProfessionalID {
		writeUserError(w, http.StatusForbidden, "Hanya profesional pemilik sesi yang boleh menempelkan link video.")
		return
	}
	if cs.SessionType != "video" {
		writeError(w, http.StatusBadRequest, errors.New("sesi ini bukan sesi video"))
		return
	}
	if cs.Status != "scheduled" {
		writeError(w, http.StatusBadRequest, errors.New("link hanya bisa diatur untuk sesi berstatus scheduled"))
		return
	}
	var req meetManualURLRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	meetURL, verr := normalizeManualMeetURL(req.MeetURL)
	if verr != nil {
		writeUserError(w, http.StatusBadRequest, verr.Error())
		return
	}
	// Simpan lewat store yang ada; pertahankan ringkasan & catatan privat
	// (UpdateCareSessionDetail menulis ketiganya, jadi kirim nilai saat ini).
	updated, err := s.store.UpdateCareSessionDetail(
		r.Context(), sessionID, meetURL, cs.SummaryForPatient, cs.PrivateNote)
	if err != nil {
		writeUserError(w, http.StatusInternalServerError, "Gagal menyimpan link video. Coba lagi.")
		return
	}
	// Beri tahu pasien bahwa link video sudah tersedia.
	s.notifyPatient(r, cs.PatientID, "session_meet_ready", "Link video call siap",
		"Profesional menambahkan link video untuk sesimu. Buka detail sesi untuk bergabung.",
		map[string]string{"session_id": cs.ID})
	writeJSON(w, http.StatusOK, map[string]any{"session": updated, "manual": true})
}

// normalizeManualMeetURL memvalidasi & merapikan URL Meet yang ditempel
// profesional. Aturan ketat: wajib https, host tepat meet.google.com, panjang
// wajar. Mengembalikan pesan error berbahasa Indonesia bila tidak valid.
func normalizeManualMeetURL(raw string) (string, error) {
	trimmed := strings.TrimSpace(raw)
	if trimmed == "" {
		return "", userMessageError("Link video tidak boleh kosong.")
	}
	if len(trimmed) > 500 {
		return "", userMessageError("Link video terlalu panjang.")
	}
	u, err := url.Parse(trimmed)
	if err != nil {
		return "", userMessageError("Link video tidak valid.")
	}
	if u.Scheme != "https" {
		return "", userMessageError("Link video harus diawali https://")
	}
	host := strings.ToLower(strings.TrimSpace(u.Hostname()))
	if host != "meet.google.com" {
		return "", userMessageError("Link video harus berupa link Google Meet (meet.google.com).")
	}
	if strings.TrimSpace(u.Path) == "" || u.Path == "/" {
		return "", userMessageError("Link Google Meet tidak lengkap. Salin tautan lengkap dari Google Meet.")
	}
	return u.String(), nil
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
		writeJSON(w, http.StatusOK, map[string]any{"session": careSessionForRole(cs, claims.Role), "created": false})
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
	writeJSON(w, http.StatusCreated, map[string]any{"session": careSessionForRole(updated, claims.Role), "created": true})
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

// RunMeetLinkBackfill membuat link Meet untuk sesi video terjadwal yang belum
// punya link (sesi lama sebelum integrasi dipasang, atau sesi berbayar yang
// lahir "menunggu link" karena Google profesional sedang bermasalah).
// Dibatasi limit per pemanggilan.
//
// Dipanggil BERKALA oleh sweeper (10 menit), bukan hanya sekali saat start:
// satu-satunya jalur lain yang mengisi link adalah pengingat sesi (jendela
// 15-25 menit sebelum sesi), sehingga tanpa backfill periodik sesi berbayar
// bisa tampil tanpa link hampir sampai jam mulai — atau sampai server restart.
//
// Dua perbedaan penting dari backfill "buta":
//   - Sesi milik profesional yang Google-nya belum siap DILEWATI tanpa
//     memanggil Google dan tanpa menulis log, agar tidak membanjiri log tiap
//     tick. Begitu profesional menyambungkan Google, tick berikutnya mengisi
//     link-nya otomatis (sesi tetap ada di daftar selama belum punya link).
//   - Urutan ListCareSessionsNeedingMeetLink adalah scheduled_at ASC, jadi
//     dengan limit kecil pun sesi yang paling dekat dimulai selalu dicoba
//     lebih dulu — inilah yang memberi percobaan ulang nyata bagi sesi yang
//     gagal dibuatkan link tepat pada tick pengingat.
//
// Bila server belum dikonfigurasi Google, ErrMeetUnavailable dikembalikan
// tanpa log: pemanggil memperlakukannya sebagai keadaan normal (bukan
// kegagalan per tick).
func (s *Server) RunMeetLinkBackfill(ctx context.Context, limit int) (int, error) {
	if s.store == nil {
		return 0, errors.New("store belum diinisialisasi")
	}
	if s.calendar == nil {
		return 0, ErrMeetUnavailable
	}
	sessions, err := s.store.ListCareSessionsNeedingMeetLink(ctx, limit)
	if err != nil {
		return 0, err
	}
	// Kesiapan Google dihitung sekali per profesional: satu pemeriksaan
	// mencakup beberapa sesi bila pasien/profesional sama.
	ready := make(map[string]bool, len(sessions))
	created := 0
	for _, cs := range sessions {
		isReady, seen := ready[cs.ProfessionalID]
		if !seen {
			isReady = s.googleCalendarReady(ctx, cs.ProfessionalID)
			ready[cs.ProfessionalID] = isReady
		}
		if !isReady {
			continue
		}
		if _, err := s.createMeetLink(ctx, cs); err != nil {
			// s.logger selalu terisi pada Server produksi (dibuat di New);
			// guard ini menjaga Server parsial (test).
			if s.logger != nil {
				s.logger.Warn("backfill link Meet gagal", "error", err, "session", cs.ID)
			}
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
