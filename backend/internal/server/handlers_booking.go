package server

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
	"malva/backend/internal/payment"
	"malva/backend/internal/store"
)

// validateSlot memastikan slot bisa dipesan pasien: masa depan, minimal 24 jam
// ke depan (sama dengan aturan cancel/reschedule pasien), di dalam jam praktik,
// bukan hari libur, dan belum terisi.
func (s *Server) validateSlot(ctx context.Context, professionalID string, start time.Time, durationMinutes int) error {
	if start.Before(time.Now().Add(-time.Minute)) {
		return errors.New("slot harus di masa depan")
	}
	// Lead time 24 jam: sesi butuh persiapan kedua belah pihak.
	// Sama dengan aturan cancel/reschedule pasien (<24 jam hangus).
	if time.Until(start) < 24*time.Hour {
		return errors.New("booking minimal 24 jam sebelum sesi")
	}
	return s.validateSlotWindow(ctx, professionalID, start, durationMinutes)
}

// validateSlotWindow memeriksa syarat slot yang berlaku untuk SEMUA peran:
// masa depan, bukan hari libur, di dalam jam praktik, dan belum terisi.
// Dipisahkan dari validateSlot supaya profesional tetap bisa menjadwalkan
// atau memindahkan sesi secara mendadak (<24 jam) — mis. kendala di hari-H —
// tanpa melewati aturan jam praktik/hari libur.
func (s *Server) validateSlotWindow(ctx context.Context, professionalID string, start time.Time, durationMinutes int) error {
	if start.Before(time.Now().Add(-time.Minute)) {
		return errors.New("slot harus di masa depan")
	}
	wibStart := start.In(wibLoc)
	dayOfWeek := int(wibStart.Weekday())
	dateStr := wibStart.Format("2006-01-02")
	off, err := s.store.ListTimeOff(ctx, professionalID, dateStr, dateStr)
	if err != nil {
		return err
	}
	if len(off) > 0 {
		return errors.New("profesional libur pada tanggal tersebut")
	}
	schedules, err := s.store.ListActiveSchedulesForProfessional(ctx, professionalID)
	if err != nil {
		return err
	}
	clock := wibStart.Format("15:04")
	fits := false
	for _, sch := range schedules {
		if sch.DayOfWeek != dayOfWeek {
			continue
		}
		// Beberapa driver mengembalikan "15:04:05".
		startT := strings.TrimSpace(sch.StartTime)
		endT := strings.TrimSpace(sch.EndTime)
		if len(startT) > 5 {
			startT = startT[:5]
		}
		if len(endT) > 5 {
			endT = endT[:5]
		}
		endClock, err := time.ParseInLocation("15:04", endT, wibLoc)
		if err != nil {
			continue
		}
		slotEnd := wibStart.Add(time.Duration(durationMinutes) * time.Minute)
		slotEndClock := slotEnd.Format("15:04")
		if startT <= clock && slotEndClock <= endClock.Format("15:04") {
			fits = true
			break
		}
	}
	if !fits {
		return errors.New("slot di luar jam praktik profesional")
	}
	booked, err := s.store.IsSlotBooked(ctx, professionalID, start)
	if err != nil {
		return err
	}
	if booked {
		return errors.New("slot sudah terisi, pilih jam lain")
	}
	return nil
}

// slotDurationFor mengambil durasi slot jadwal profesional pada hari tsb.
func (s *Server) slotDurationFor(ctx context.Context, professionalID string, start time.Time) int {
	wibStart := start.In(wibLoc)
	dayOfWeek := int(wibStart.Weekday())
	clock := wibStart.Format("15:04")
	schedules, err := s.store.ListActiveSchedulesForProfessional(ctx, professionalID)
	if err != nil {
		return 30
	}
	for _, sch := range schedules {
		if sch.DayOfWeek != dayOfWeek {
			continue
		}
		startT := strings.TrimSpace(sch.StartTime)
		endT := strings.TrimSpace(sch.EndTime)
		if len(startT) > 5 {
			startT = startT[:5]
		}
		if len(endT) > 5 {
			endT = endT[:5]
		}
		if startT <= clock && clock < endT && sch.SlotDurationMinutes > 0 {
			return sch.SlotDurationMinutes
		}
	}
	return 30
}

// Penyebab slot sesi berbayar tidak bisa dipakai. Dipakai jalur terminal
// handlePaidBookingSlotUnusable / handlePaidBookingNoSchedule.
const (
	slotCausePassed     = "slot_lewat"
	slotCauseTaken      = "slot_terisi"
	slotCauseNoSchedule = "jadwal_tidak_terbaca"
)

// notifNeedsReschedule adalah tipe notifikasi "sesi berbayar perlu dijadwalkan
// ulang" (slot lewat / slot terisi / jadwal tidak terbaca).
const notifNeedsReschedule = "session_needs_reschedule"

// notifPaymentReconciliation adalah tipe notifikasi untuk dana yang masuk pada
// pembayaran yang sudah dibatalkan (perlu pengembalian dana manual).
const notifPaymentReconciliation = "payment_needs_reconciliation"

// slotAlreadyPassed true bila jam sesi sudah lewat melewati toleransi yang SAMA
// dengan store.CreateCareSession (1 menit), agar handler dan store tidak pernah
// berbeda pendapat.
//
// Deteksi ini harus dilakukan SEBELUM memanggil CreateCareSession: store
// menolak jadwal masa lalu, dan error itu membuat webhook pembayaran membalas
// 5xx selamanya padahal uang pasien sudah masuk (kasus VA/QRIS yang settle
// beberapa menit setelah jam sesi dimulai).
func slotAlreadyPassed(start time.Time) bool {
	return start.Before(clock.Now().Add(-time.Minute))
}

// alreadyNotifiedForBooking true bila notifikasi bertipe kind untuk booking ini
// sudah pernah dibuat untuk userID.
func (s *Server) alreadyNotifiedForBooking(ctx context.Context, userID, kind, bookingID string) bool {
	return s.hasNotificationMatching(ctx, userID, kind, "booking_id", bookingID)
}

// alreadyNotifiedForReference true bila notifikasi bertipe kind untuk reference
// pembayaran (order_id gateway) ini sudah pernah dibuat untuk userID.
//
// Dipakai jalur webhook terminal: event berstatus 'ignored' TIDAK menghentikan
// replay (hanya 'processed' yang short-circuit di paymentWebhook), sehingga
// dedupe harus berdasarkan reference pembayaran, bukan status event.
func (s *Server) alreadyNotifiedForReference(ctx context.Context, userID, kind, reference string) bool {
	return s.hasNotificationMatching(ctx, userID, kind, "reference", reference)
}

// hasNotificationMatching mencari notifikasi bertipe kind yang data[dataKey]
// sama dengan want. Dipakai agar jalur terminal idempoten tanpa skema/kolom
// baru. Nilai kosong tidak pernah dianggap cocok (mencegah dedupe "global").
func (s *Server) hasNotificationMatching(ctx context.Context, userID, kind, dataKey, want string) bool {
	if strings.TrimSpace(want) == "" || s.store == nil {
		return false
	}
	items, err := s.store.ListNotifications(ctx, userID, 50)
	if err != nil {
		return false
	}
	for _, n := range items {
		if n.Type == kind && n.Data[dataKey] == want {
			return true
		}
	}
	return false
}

// handlePaidBookingSlotUnusable menangani pembayaran yang SUDAH LUNAS tetapi
// slot sesinya tidak bisa dipakai (jamnya sudah lewat, atau slot keburu terisi
// sesi lain).
//
// Terminal, bukan error:
//   - tidak membuat sesi — sesi bertanggal masa lalu akan ditandai no_show oleh
//     sweeper, memakan kuota paket, dan memalsukan riwayat pasien;
//   - tidak mengembalikan error — webhook 5xx diulang gateway selamanya;
//   - pembayaran tetap berstatus 'paid' untuk rekonsiliasi manual, dan booking
//     TIDAK dikembalikan ke 'pending' (itu yang dulu memungkinkan pasien
//     membayar dua kali untuk satu sesi);
//   - pasien & profesional diberi tahu langkah berikutnya yang nyata:
//     profesional membuat sesi pengganti lewat POST /v1/care-sessions.
func (s *Server) handlePaidBookingSlotUnusable(ctx context.Context, booking store.Booking, paymentID string, start time.Time, cause, patientNote string) {
	when := start.In(wibLoc).Format("02 Jan 2006 15:04")
	logMsg := "pembayaran lunas tetapi slot sudah lewat; perlu penjadwalan ulang manual"
	causeText := "jam sesi itu sudah lewat saat pembayaran terkonfirmasi"
	if cause == slotCauseTaken {
		logMsg = "pembayaran lunas tetapi slot sudah terisi sesi lain; perlu penjadwalan ulang manual"
		causeText = "slot itu sudah terisi sesi lain saat pembayaran terkonfirmasi"
	}
	s.logger.Error(logMsg, "booking", booking.ID, "payment", paymentID, "slot", when)
	// Dedupe PER PENERIMA: kalau proses mati setelah notifikasi pasien terkirim
	// tetapi sebelum notifikasi profesional, percobaan ulang harus tetap
	// mengirim notifikasi profesional — jangan ada return dini yang melewati
	// penerima lain.
	if !s.alreadyNotifiedForBooking(ctx, booking.PatientID, notifNeedsReschedule, booking.ID) {
		s.notifyUser(ctx, booking.PatientID, notifNeedsReschedule,
			"Sesi perlu dijadwalkan ulang",
			"Pembayaran sesi "+when+" sudah kami terima, tetapi "+causeText+". "+patientNote+
				"Profesional akan membuatkan sesi pengganti; Anda tidak perlu membayar lagi.",
			map[string]string{"booking_id": booking.ID, "slot": when, "cause": cause})
	}
	if !s.alreadyNotifiedForBooking(ctx, booking.ProfessionalID, notifNeedsReschedule, booking.ID) {
		s.notifyUser(ctx, booking.ProfessionalID, notifNeedsReschedule,
			"Sesi berbayar perlu dijadwalkan ulang",
			"Pembayaran pasien untuk slot "+when+" sudah lunas, tetapi "+causeText+
				". Buat sesi pengganti dari menu Jadwal agar pasien tidak kehilangan sesi yang sudah dibayar.",
			map[string]string{"booking_id": booking.ID, "slot": when, "cause": cause, "patient_id": booking.PatientID})
	}
}

// handlePaidBookingNoSchedule menangani pembayaran paket yang SUDAH LUNAS
// tetapi jadwal sesi pertamanya tidak terbaca (bookings.slot_time NULLABLE —
// data legacy tanpa jam).
//
// Terminal, bukan error: paket sudah aktif (ActivatePendingPackage berjalan
// sebelum titik ini), jadi pasien tidak kehilangan kuota. Yang tidak boleh
// dilakukan: menebak jam sesi, membuat sesi tanpa jam, atau membalas 5xx yang
// akan diulang gateway selamanya.
func (s *Server) handlePaidBookingNoSchedule(ctx context.Context, booking store.Booking, paymentID string, pkg store.CarePackage) {
	s.logger.Error("pembayaran lunas tetapi jadwal sesi pertama paket tidak terbaca; paket tetap aktif",
		"booking", booking.ID, "payment", paymentID, "package", pkg.ID,
		"booking_date", booking.BookingDate, "slot_time", booking.SlotTime)
	expires := pkg.ExpiresAt.In(wibLoc).Format("02 Jan 2006")
	if !s.alreadyNotifiedForBooking(ctx, booking.PatientID, notifNeedsReschedule, booking.ID) {
		s.notifyUser(ctx, booking.PatientID, notifNeedsReschedule,
			"Sesi pertama belum terjadwal",
			fmt.Sprintf("Paket %d sesi Anda sudah aktif (sampai %s), tetapi jadwal sesi pertama tidak terbaca sehingga belum bisa dijadwalkan. Pilih jadwal sesi dari menu paket; Anda tidak perlu membayar lagi.",
				pkg.TotalSessions, expires),
			map[string]string{"booking_id": booking.ID, "package_id": pkg.ID, "cause": slotCauseNoSchedule})
	}
	if !s.alreadyNotifiedForBooking(ctx, booking.ProfessionalID, notifNeedsReschedule, booking.ID) {
		s.notifyUser(ctx, booking.ProfessionalID, notifNeedsReschedule,
			"Sesi pertama paket perlu dijadwalkan",
			"Pembayaran pasien sudah lunas dan paketnya aktif, tetapi jadwal sesi pertama tidak terbaca. Buat sesi untuk pasien ini dari menu Jadwal agar kuota paketnya bisa dipakai.",
			map[string]string{"booking_id": booking.ID, "package_id": pkg.ID, "patient_id": booking.PatientID, "cause": slotCauseNoSchedule})
	}
}

// activatePaidBooking membuat sesi terjadwal (quick) / paket aktif + link.
// Nilai kembalian string = id paket target bila paket baru DIGABUNG ke paket
// aktif yang sudah ada (kosong bila tidak ada penggabungan).
func (s *Server) activatePaidBooking(r *http.Request, p store.Payment) (string, error) {
	ctx := r.Context()
	booking, err := s.store.GetBooking(ctx, p.BookingID)
	if err != nil {
		return "", err
	}
	if booking.Status != "paid" {
		return "", nil
	}
	// Materialisasi relasi pasien–profesional SEGERA setelah booking lunas.
	//
	// Ini jalur tunggal yang mencakup SEMUA cabang di bawah (paket, quick,
	// legacy tanpa jam, slot sudah lewat/terisi) sehingga profesional yang
	// sudah dibayar pasiennya TIDAK kehilangan akses ke data pasien meski
	// sesi pertama gagal dibuat. Idempoten (ON CONFLICT), jadi aman untuk
	// webhook yang dikirim ulang. Kegagalan hanya dicatat: relasi bukan alasan
	// menggagalkan aktivasi yang sudah dibayar (webhook akan diulang).
	if linkErr := s.store.EnsurePatientProfessionalLink(ctx, booking.PatientID, booking.ProfessionalID); linkErr != nil {
		s.logger.Warn("gagal materialisasi relasi pasien-profesional pasca-bayar",
			"error", linkErr, "booking", booking.ID,
			"patient", booking.PatientID, "professional", booking.ProfessionalID)
	}
	// Idempotensi aktivasi: webhook gateway bisa dikirim ulang setelah balasan
	// 5xx (mis. Google sedang gagal saat membuat link Meet). Bila booking ini
	// sudah punya sesi, jangan buat sesi kedua — unique index slot akan
	// menolaknya dan pengulangan berikutnya gagal selamanya.
	if existing, serr := s.store.GetCareSessionByBookingID(ctx, booking.ID); serr == nil && existing.ID != "" {
		return "", nil
	} else if serr != nil && !errors.Is(serr, sql.ErrNoRows) {
		return "", serr
	}
	// Paket: aktifkan paket pending milik pasangan + link + jadwalkan sesi
	// pertama dari slot booking. (bookings.package_id tidak dipakai karena
	// kolom itu FK ke tabel service_packages lama.)
	if booking.ServiceType == "package_session" {
		pkg, merged, err := s.store.ActivatePendingPackage(ctx, booking.PatientID, booking.ProfessionalID, booking.ID)
		if err != nil {
			// Pengulangan webhook setelah aktivasi paket berhasil tetapi sesi
			// pertama gagal dibuat: paket pending sudah tidak ada, jadi pakai
			// paket yang sudah mencatat booking ini.
			if existing, gerr := s.store.GetCarePackageByBookingID(ctx, booking.ID); gerr == nil && existing.ID != "" {
				pkg, merged, err = existing, false, nil
			}
		}
		if err != nil {
			return "", err
		}
		if _, err := s.store.LinkPatientToProfessional(ctx, booking.PatientID, booking.ProfessionalID); err != nil {
			s.logger.Warn("link patient failed", "error", err)
		}
		start, perr := parseWIBDateTime(booking.BookingDate + "T" + booking.SlotTime)
		if perr != nil || booking.SlotTime == "" {
			// Data legacy: bookings.slot_time NULLABLE, jadi baris paket tanpa
			// jam memang ada. Paket sudah aktif di atas; sesi pertama tidak bisa
			// dijadwalkan tanpa menebak jam. Terminal — bukan 5xx selamanya.
			s.handlePaidBookingNoSchedule(ctx, booking, p.ID, pkg)
			return "", nil
		}
		duration := booking.DurationMinutes
		if duration <= 0 {
			duration = s.slotDurationFor(ctx, booking.ProfessionalID, start)
		}
		// Slot sesi pertama paket bisa sudah lewat saat pembayaran settle (VA/
		// QRIS lunas beberapa menit setelah jam mulai). Paket sudah diaktifkan
		// di atas dan tetap utuh; hanya sesi pertamanya yang tidak dibuat.
		if slotAlreadyPassed(start) {
			s.handlePaidBookingSlotUnusable(ctx, booking, p.ID, start, slotCausePassed, "Paket Anda tetap aktif. ")
			return "", nil
		}
		// Sesi pertama paket bisa bertipe video. Link Google Meet dibuat
		// SEBELUM baris sesi disimpan, tetapi kegagalan Google TIDAK boleh
		// membuat pasien kehilangan sesi yang SUDAH DIBAYAR.
		//
		// Semantik degradasi sengaja disamakan dengan jalur penjadwalan
		// (prepareScheduledMeet): bila Google profesional bermasalah
		// (ErrReauthNeeded / tanpa link / galat Google lain) sesi dibuat
		// "menunggu link" (AllowPendingMeet) dan link dibuat menyusul.
		//
		// PEMBEDAAN dari jalur penjadwalan: bila server belum dikonfigurasi
		// Google (ErrMeetUnavailable), scheduleSession membalas 501 karena
		// pasien belum membayar. Di sini uang pasien SUDAH masuk — webhook
		// pembayaran yang mengulang terus lebih buruk daripada sesi tanpa
		// link — jadi tetap dibuat "menunggu link" dan kegagalan dicatat.
		meetingURL, googleEventID := "", ""
		meetPending := false
		// meetServerUnavailable menandai penyebab "menunggu link" adalah
		// integrasi Google di server yang mati (ErrMeetUnavailable), bukan akun
		// Google profesional. Pesan ke pengguna HARUS dibedakan: pada kasus ini
		// tombol "Buat link Meet" membalas 501, jadi profesional tidak boleh
		// disuruh menekannya (lihat meetPendingNotices).
		meetServerUnavailable := false
		if isVideoSession(booking.SessionType) {
			meetURL, eventID, pending, merr := s.prepareMeetEventFor(ctx, booking.PatientID, booking.ProfessionalID, start, duration)
			if merr != nil {
				if errors.Is(merr, ErrMeetUnavailable) {
					s.logger.Error("google Meet belum dikonfigurasi; sesi berbayar tetap dibuat menunggu link",
						"booking", booking.ID, "error", merr)
					meetPending = true
					meetServerUnavailable = true
				} else {
					// prepareMeetEventFor saat ini hanya bisa mengembalikan
					// ErrMeetUnavailable: galat Google lain (ErrReauthNeeded,
					// tanpa link Meet, 5xx) sudah didegradasi menjadi "menunggu
					// link" di dalam prepareScheduledMeet. Cabang ini disimpan
					// sebagai jaring pengaman agar galat keras baru tetap
					// menggagalkan aktivasi seperti perilaku lama — jangan
					// dihapus tanpa memeriksa helper tersebut.
					return "", merr
				}
			} else {
				meetingURL, googleEventID, meetPending = meetURL, eventID, pending
			}
		}
		cs, cerr := s.store.CreateCareSession(ctx, store.CareSession{
			// WAJIB memakai pkg.ID (care_packages), BUKAN booking.PackageID.
			// booking.PackageID menunjuk service_packages lama dan — karena
			// createBooking memang tidak pernah mengisinya — selalu NULL.
			// Akibatnya sesi pertama paket tidak terhitung pada kuota
			// (hitungnya WHERE package_id = cp.id), sehingga pasien mendapat
			// 1 sesi ekstra gratis dari setiap paket 4 sesi.
			PackageID:       &pkg.ID,
			BookingID:       &booking.ID,
			PatientID:       booking.PatientID,
			ProfessionalID:  booking.ProfessionalID,
			SessionType:     booking.SessionType,
			ScheduledAt:     start,
			DurationMinutes: duration,
			Status:          "scheduled",
			MeetingURL:      meetingURL,
			GoogleEventID:   googleEventID,
			// Izin eksplisit: sesi video berbayar boleh lahir tanpa link bila
			// Google profesional sedang bermasalah (lihat prepareMeetEventFor).
			AllowPendingMeet: meetPending,
		})
		if cerr != nil {
			// Event sudah lahir di kalender profesional; jangan biarkan
			// menggantung tanpa sesi yang menunjuknya.
			if googleEventID != "" {
				s.cancelMeetEventBestEffort(ctx, s.calendar, booking.ProfessionalID, googleEventID)
			}
			// Balapan sempit: slot bisa terisi di antara pemeriksaan di atas dan
			// INSERT. Bila sekarang benar-benar terisi, jadikan terminal
			// (notifikasi + 200) alih-alih 5xx yang diulang selamanya.
			if booked, berr := s.store.IsSlotBooked(ctx, booking.ProfessionalID, start); berr == nil && booked {
				s.handlePaidBookingSlotUnusable(ctx, booking, p.ID, start, slotCauseTaken, "Paket Anda tetap aktif. ")
				return "", nil
			}
			return "", cerr
		}
		// Jumlah sesi diambil dari paket sebenarnya, bukan angka 4: paket bisa
		// DIGABUNG ke paket aktif (store.ActivatePendingPackage) sehingga
		// total_sessions menjadi 4+4 dan masa berlakunya melewati 42 hari.
		s.notifyPatient(r, booking.ProfessionalID, "package_activated",
			"Paket baru aktif", fmt.Sprintf("Pasien membeli paket %d sesi.", pkg.TotalSessions),
			map[string]string{"package_id": pkg.ID, "patient_id": booking.PatientID})
		when := start.In(wibLoc).Format("02 Jan 2006 15:04")
		pkgBody := fmt.Sprintf("Paket %d sesi aktif (sampai %s). Sesi pertama: %s.",
			pkg.TotalSessions, pkg.ExpiresAt.In(wibLoc).Format("02 Jan 2006"), when)
		if meetPending {
			// Link belum ada: pesan menyesuaikan penyebabnya, dan profesional
			// hanya diminta membuat link bila tombolnya memang berfungsi.
			patientSuffix, profTitle, profBody := meetPendingNotices(when, meetServerUnavailable)
			pkgBody += patientSuffix
			s.notifyPatient(r, booking.ProfessionalID, "session_meet_missing",
				profTitle, profBody,
				map[string]string{"session_id": cs.ID, "patient_id": booking.PatientID, "meet_pending": "true"})
		} else if strings.TrimSpace(cs.MeetingURL) != "" {
			pkgBody += " Link video call: " + cs.MeetingURL
		}
		s.notifyPatient(r, booking.PatientID, "package_activated",
			"Paket aktif!", pkgBody,
			map[string]string{"package_id": pkg.ID, "session_id": cs.ID, "meeting_url": cs.MeetingURL})
		mergedID := ""
		if merged {
			mergedID = pkg.ID
		}
		return mergedID, nil
	}
	start, perr := parseWIBDateTime(booking.BookingDate + "T" + booking.SlotTime)
	if perr != nil || booking.SlotTime == "" {
		// Tanpa jam (warisan continuous lama): hanya link.
		_, _ = s.store.PairRelation(ctx, booking.PatientID, booking.ProfessionalID)
		_, _ = s.store.LinkPatientToProfessional(ctx, booking.PatientID, booking.ProfessionalID)
		// Booking seperti ini tidak akan pernah punya sesi, jadi pendapatan
		// profesional tidak akan pernah tercatat lewat jalur "sesi selesai".
		// Catat di sini agar profesional pemilik data lama tidak kehilangan
		// pendapatannya. Idempoten (dilewati bila earnings sudah ada).
		if earnErr := s.store.RecognizeEarningForPayment(ctx, p.ID); earnErr != nil {
			s.logger.Warn("recognize earning for legacy booking failed", "payment", p.ID, "error", earnErr)
		}
		return "", nil
	}
	duration := booking.DurationMinutes
	if duration <= 0 {
		duration = s.slotDurationFor(ctx, booking.ProfessionalID, start)
	}
	// Slot sudah lewat saat pembayaran settle: terminal, bukan 5xx (lihat
	// handlePaidBookingSlotUnusable). Sesi bertanggal masa lalu TIDAK dibuat.
	if slotAlreadyPassed(start) {
		s.handlePaidBookingSlotUnusable(ctx, booking, p.ID, start, slotCausePassed, "")
		return "", nil
	}
	if booked, berr := s.store.IsSlotBooked(ctx, booking.ProfessionalID, start); berr != nil {
		// Galat baca database: transien, biarkan gateway mengulang webhook.
		return "", berr
	} else if booked {
		// Slot keburu terisi sesi lain. JANGAN kembalikan booking ke 'pending':
		// pembayaran sudah lunas (MarkPaymentPaid) dan createPayment hanya
		// menolak booking yang bukan 'pending', sehingga mengembalikannya ke
		// pending membuat pasien bisa membayar LAGI untuk sesi yang sama.
		s.handlePaidBookingSlotUnusable(ctx, booking, p.ID, start, slotCauseTaken, "")
		return "", nil
	}
	// Quick consult video: link dibuat SEBELUM sesi disimpan, tetapi kegagalan
	// Google TIDAK boleh membuat pasien kehilangan sesi yang sudah dibayar.
	// Semantik degradasi disamakan dengan alur aktivasi paket di atas
	// (prepareMeetEventFor / prepareScheduledMeet).
	meetingURL, googleEventID := "", ""
	meetPending := false
	// Lihat catatan di cabang paket: penyebab "menunggu link" menentukan pesan
	// yang boleh dikirim (server belum dikonfigurasi vs akun Google profesional).
	meetServerUnavailable := false
	if isVideoSession(booking.SessionType) {
		meetURL, eventID, pending, merr := s.prepareMeetEventFor(ctx, booking.PatientID, booking.ProfessionalID, start, duration)
		if merr != nil {
			if errors.Is(merr, ErrMeetUnavailable) {
				s.logger.Error("google Meet belum dikonfigurasi; sesi berbayar tetap dibuat menunggu link",
					"booking", booking.ID, "error", merr)
				meetPending = true
				meetServerUnavailable = true
			} else {
				// Jaring pengaman (saat ini tidak reachable): lihat catatan di
				// cabang paket.
				return "", merr
			}
		} else {
			meetingURL, googleEventID, meetPending = meetURL, eventID, pending
		}
	}
	cs, cerr := s.store.CreateCareSession(ctx, store.CareSession{
		BookingID:       &booking.ID,
		PatientID:       booking.PatientID,
		ProfessionalID:  booking.ProfessionalID,
		SessionType:     booking.SessionType,
		ScheduledAt:     start,
		DurationMinutes: duration,
		Status:          "scheduled",
		MeetingURL:      meetingURL,
		GoogleEventID:   googleEventID,
		// Izin eksplisit: sesi video berbayar boleh lahir tanpa link.
		AllowPendingMeet: meetPending,
	})
	if cerr != nil {
		if googleEventID != "" {
			s.cancelMeetEventBestEffort(ctx, s.calendar, booking.ProfessionalID, googleEventID)
		}
		// Balapan sempit: slot terisi di antara pemeriksaan dan INSERT. Lihat
		// catatan di cabang paket.
		if booked, berr := s.store.IsSlotBooked(ctx, booking.ProfessionalID, start); berr == nil && booked {
			s.handlePaidBookingSlotUnusable(ctx, booking, p.ID, start, slotCauseTaken, "")
			return "", nil
		}
		return "", cerr
	}
	// Quick consult: buat relasi agar chat sesi bisa dipakai (tanpa data sharing).
	_, _ = s.store.LinkPatientToProfessional(ctx, booking.PatientID, booking.ProfessionalID)
	s.notifyPatient(r, booking.ProfessionalID, "session_scheduled",
		"Sesi baru dijadwalkan", "Ada sesi quick consult baru.",
		map[string]string{"session_id": cs.ID, "patient_id": booking.PatientID})
	when := start.In(wibLoc).Format("02 Jan 2006 15:04")
	quickBody := "Sesi pada " + when + "."
	if meetPending {
		// Link belum ada: pesan menyesuaikan penyebabnya (lihat
		// meetPendingNotices) agar profesional tidak disuruh menekan tombol
		// yang akan membalas 501 saat integrasi server mati.
		patientSuffix, profTitle, profBody := meetPendingNotices(when, meetServerUnavailable)
		quickBody += patientSuffix
		s.notifyPatient(r, booking.ProfessionalID, "session_meet_missing",
			profTitle, profBody,
			map[string]string{"session_id": cs.ID, "patient_id": booking.PatientID, "meet_pending": "true"})
	} else if strings.TrimSpace(cs.MeetingURL) != "" {
		quickBody += " Link video call: " + cs.MeetingURL
	}
	s.notifyPatient(r, booking.PatientID, "session_scheduled",
		"Sesi berhasil dijadwalkan", quickBody,
		map[string]string{"session_id": cs.ID, "meeting_url": cs.MeetingURL})
	return "", nil
}

// ============================================================
// BOOKING, PAYMENT, EARNINGS, E-PRESCRIPTION
// ============================================================

type createBookingRequest struct {
	PatientID       string  `json:"patient_id"`
	ProfessionalID  string  `json:"professional_id"`
	PackageID       *string `json:"package_id,omitempty"`
	ServiceType     string  `json:"service_type"`
	SessionType     string  `json:"session_type"`
	BookingDate     string  `json:"booking_date"`
	SlotTime        string  `json:"slot_time"`
	DurationMinutes int     `json:"duration_minutes"`
	Price           int64   `json:"price"`
}

type createPaymentRequest struct {
	BookingID     string `json:"booking_id"`
	PaymentMethod string `json:"payment_method"`
}

type markPaidRequest struct {
	Reference  string `json:"reference"`
	ExternalID string `json:"external_id"`
}

func (s *Server) createBooking(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	// Profesional terverifikasi bisa buat booking untuk pasiennya, atau pasien buat sendiri
	var req createBookingRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	isProfessional := claims.Role == "professional"
	patientID := req.PatientID
	var professionalID string

	if !isProfessional {
		patientID = claims.Subject
		if req.ProfessionalID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "professional_id is required"})
			return
		}
		professionalID = req.ProfessionalID
	} else {
		if patientID == "" {
			patientID = claims.Subject
		}
		isVerified := s.requireVerifiedProfessional(w, r, claims)
		if !isVerified {
			return
		}
		professionalID = claims.Subject
	}

	cred, err := s.store.GetProfessionalCredential(r.Context(), professionalID)
	if err != nil || cred.VerificationStatus != "VERIFIED" {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "Professional not found or not verified"})
		return
	}

	serviceType := strings.ToLower(strings.TrimSpace(req.ServiceType))
	if serviceType == "continuous_support" {
		writeJSON(w, http.StatusGone, map[string]string{
			"error": "Continuous Support 7 hari sudah diganti sistem paket 4 sesi. Beli paket lewat /v1/care-packages lalu jadwalkan sesinya.",
		})
		return
	}
	isPackageSession := serviceType == "package_session"
	if serviceType != "quick_consult" && serviceType != "quick_consult_video" && !isPackageSession {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "service_type harus quick_consult, quick_consult_video, atau package_session"})
		return
	}
	sessionType := strings.ToLower(strings.TrimSpace(req.SessionType))
	switch sessionType {
	case "video":
	case "chat":
	default:
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "session_type harus chat atau video"})
		return
	}
	// Setiap sesi video WAJIB punya ruang pertemuan, jadi kemampuan profesional
	// membuat link Meet diperiksa SEBELUM pasien membayar. Menolak di sini jauh
	// lebih baik daripada menerima uang lalu gagal membuat link saat aktivasi.
	if sessionType == "video" && !s.googleCalendarReady(r.Context(), professionalID) {
		writeJSON(w, http.StatusConflict, map[string]string{
			"error": "Profesional ini belum mengaktifkan Google Meet, sehingga sesi video belum bisa dipesan. Pilih sesi chat, atau minta profesional mengaktifkan Google Meet lebih dulu.",
			"code":  "meet_belum_aktif",
		})
		return
	}
	// Harga dihitung server dari tarif profesional (bukan dari klien).
	// package_session: harga = harga paket pending milik pasangan;
	// aktivasi paket terjadi saat paid (bookings.package_id TIDAK dipakai).
	var price int64
	if isPackageSession {
		pkgs, err := s.store.ListCarePackages(r.Context(), patientID, "patient", "", 50)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		found := false
		for _, p := range pkgs {
			if p.ProfessionalID == professionalID && p.Status == "pending_payment" {
				price = p.Price
				found = true
				break
			}
		}
		if !found {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "tidak ada paket pending dengan profesional ini — buat paket dulu lewat /v1/care-packages"})
			return
		}
		if price <= 0 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "harga paket tidak valid"})
			return
		}
	} else {
		pricing, err := s.store.GetProfessionalPricing(r.Context(), professionalID)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		if sessionType == "video" {
			price = pricing.QuickVideoPrice
		} else {
			price = pricing.QuickChatPrice
		}
		if price <= 0 {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Profesional belum mengatur harga sesi. Hubungi profesional."})
			return
		}
	}

	target, err := parseWIBDateTime(req.BookingDate + "T" + req.SlotTime)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "booking_date/slot_time tidak valid (butuh tanggal + jam)"})
		return
	}
	duration := req.DurationMinutes
	if duration <= 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "duration_minutes wajib diisi (10-180)"})
		return
	}
	if duration < 10 || duration > 180 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "duration_minutes harus 10-180 menit"})
		return
	}
	if target.Before(time.Now().Add(-time.Minute)) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "slot harus di masa depan"})
		return
	}
	// Validasi slot: masuk jadwal mingguan, bukan hari libur, belum terisi.
	// Durasi sesi = durasi slot jadwal profesional hari itu.
	duration = s.slotDurationFor(r.Context(), professionalID, target)
	if err := s.validateSlot(r.Context(), professionalID, target, duration); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	b, err := s.store.CreateBooking(r.Context(), store.Booking{
		PatientID:       patientID,
		ProfessionalID:  professionalID,
		ServiceType:     serviceType,
		SessionType:     sessionType,
		BookingDate:     req.BookingDate,
		SlotTime:        req.SlotTime,
		DurationMinutes: duration,
		Price:           price,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	writeJSON(w, http.StatusCreated, map[string]interface{}{"booking": b})
}

func (s *Server) createPayment(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	var req createPaymentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	// Generate reference: TXN-YYYYMMDDHHMMSS-RANDOM6
	reference := fmt.Sprintf("TXN-%s-%06d",
		clock.Now().Format("20060102150405"),
		(int64)(time.Now().UnixNano()%1000000),
	)

	// Harga diambil dari booking milik pasien sendiri (bukan dari klien).
	booking, err := s.store.GetBooking(r.Context(), req.BookingID)
	if err != nil {
		writeError(w, http.StatusNotFound, err)
		return
	}
	if booking.PatientID != claims.Subject || claims.Role != "patient" {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "only the booking owner can pay"})
		return
	}
	if booking.Status != "pending" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "booking sudah dibayar atau kedaluwarsa"})
		return
	}
	bookingPrice := booking.Price
	platformFee := bookingPrice * 10 / 100 // fee platform 10%
	serviceFee := int64(2000)
	gross := bookingPrice
	net := gross - platformFee

	p, err := s.store.CreatePayment(r.Context(), store.Payment{
		BookingID:         req.BookingID,
		PaymentMethod:     req.PaymentMethod,
		GrossAmount:       gross,
		ServiceFeeAmount:  serviceFee,
		PlatformFeeAmount: platformFee,
		NetAmount:         net,
		Reference:         reference,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	// Mode gateway: buat transaksi Snap, simpan token/redirect ke payment.
	// Record lokal tetap ada walau gateway gagal (webhook bisa menyusul).
	if s.cfg.PaymentMode == "gateway" && s.payment != nil {
		customer := map[string]any{"first_name": claims.Subject}
		if user, uerr := s.store.GetUserByID(r.Context(), claims.Subject); uerr == nil {
			if strings.TrimSpace(user.DisplayName) != "" {
				customer["first_name"] = user.DisplayName
			}
			if user.Email != "" {
				customer["email"] = user.Email
			}
			if user.Phone != nil && *user.Phone != "" {
				customer["phone"] = *user.Phone
			}
		}
		intent, gerr := s.payment.CreateTransaction(r.Context(), reference, gross+serviceFee, customer)
		if gerr != nil {
			s.logger.Warn("gateway create transaction failed", "reference", reference, "error", gerr)
			writeError(w, http.StatusBadGateway, errors.New("gagal membuat transaksi pembayaran, coba lagi"))
			return
		}
		if updated, uerr := s.store.UpdatePaymentGateway(r.Context(), reference, "midtrans", intent.Token, intent.RedirectURL); uerr == nil {
			p = updated
		} else {
			s.logger.Warn("simpan token gateway gagal", "reference", reference, "error", uerr)
			p.Gateway = "midtrans"
			p.SnapToken = intent.Token
			p.RedirectURL = intent.RedirectURL
		}
	}

	writeJSON(w, http.StatusCreated, map[string]interface{}{
		"payment": p,
		"breakdown": map[string]interface{}{
			"consultation":  bookingPrice,
			"service_fee":   serviceFee,
			"total":         gross + serviceFee,
			"platform_fee":  platformFee,
			"net_to_doctor": net,
		},
	})
}

func (s *Server) markPaymentPaid(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	// Produksi (mode gateway): konfirmasi manual dinonaktifkan; satu-satunya
	// jalur sukses adalah webhook gateway.
	if s.cfg.PaymentMode == "gateway" {
		writeError(w, http.StatusGone, errors.New("mark-paid dinonaktifkan; gunakan gateway (webhook)"))
		return
	}
	// Konfirmasi pembayaran internal (simulasi gateway): hanya pasien
	// pemilik booking yang boleh mengonfirmasi, dan hanya saat pending.
	// Produksi: ganti dengan webhook gateway (Midtrans/dll).
	var req markPaidRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	// Otorisasi WAJIB sebelum mutasi apa pun. Sebelumnya MarkPaymentPaid
	// dijalankan lebih dulu, sehingga pemanggil yang akhirnya ditolak 403
	// sudah terlanjur menandai payment 'paid' (dan memicu earnings) hanya
	// dengan menebak reference milik orang lain.
	if err := s.store.AuthorizePaymentByReference(r.Context(), req.Reference, claims.Subject, claims.Role); err != nil {
		if errors.Is(err, store.ErrPaymentNotFound) {
			writeError(w, http.StatusNotFound, errors.New("payment not found or already paid"))
			return
		}
		writeError(w, http.StatusForbidden, err)
		return
	}

	p, err := s.store.MarkPaymentPaid(r.Context(), req.Reference, req.ExternalID)
	if err != nil {
		writeError(w, http.StatusNotFound, err)
		return
	}

	// Efek samping pembayaran: quick consult -> sesi terjadwal;
	// paket -> care package aktif + link pasien-profesional.
	mergedPkgID, aerr := s.activatePaidBooking(r, p)
	if aerr != nil {
		s.logger.Warn("activate paid booking failed", "payment", p.ID, "error", aerr)
	}

	resp := map[string]interface{}{"payment": p, "status": "paid"}
	if mergedPkgID != "" {
		resp["merged"] = true
		resp["merged_package_id"] = mergedPkgID
	}
	writeJSON(w, http.StatusOK, resp)
}

// cancelPendingBooking membatalkan booking yang masih pending beserta
// pembayaran pending yang terkait. Dipakai ketika pasien membatalkan paket
// pending_payment dari layar MyCare — tanpa ini booking & payment tetap
// menggantung di database selamanya.
func (s *Server) cancelPendingBooking(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "patient" {
		writeError(w, http.StatusForbidden, errors.New("only patients can cancel a booking"))
		return
	}
	bookingID := r.PathValue("booking_id")
	if strings.TrimSpace(bookingID) == "" {
		writeError(w, http.StatusBadRequest, errors.New("booking_id is required"))
		return
	}
	booking, err := s.store.GetBooking(r.Context(), bookingID)
	if err != nil {
		writeError(w, http.StatusNotFound, errors.New("booking tidak ditemukan"))
		return
	}
	if booking.PatientID != claims.Subject {
		writeError(w, http.StatusForbidden, errors.New("not your booking"))
		return
	}
	if booking.Status != "pending" {
		writeError(w, http.StatusBadRequest, errors.New("hanya booking pending yang bisa dibatalkan"))
		return
	}
	// Batalkan booking dan payment pending terkait dalam satu transaksi.
	if err := s.store.CancelPendingBooking(r.Context(), bookingID); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "cancelled"})
}

// paymentWebhook menerima notifikasi pembayaran gateway (Midtrans). Publik,
// keaslian diverifikasi via signature SHA-512; idempoten via payment_events.
func (s *Server) paymentWebhook(w http.ResponseWriter, r *http.Request) {
	if s.payment == nil {
		// Gateway tidak aktif: tidak ada yang bisa diverifikasi.
		writeJSON(w, http.StatusOK, map[string]string{"status": "ignored"})
		return
	}
	body, err := io.ReadAll(io.LimitReader(r.Body, 1<<20))
	if err != nil {
		writeError(w, http.StatusBadRequest, errors.New("body tidak terbaca"))
		return
	}
	_ = r.Body.Close()
	evt, err := s.payment.ParseWebhook(body, r.Header)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	// 1. Verifikasi signature; tidak cocok -> 401 tanpa efek (AC-4.2).
	if !s.payment.VerifySignature(evt) {
		writeError(w, http.StatusUnauthorized, errors.New("invalid signature"))
		return
	}
	// 2. Idempotensi replay via payment_events (AC-4.3).
	eventType := strings.ToLower(strings.TrimSpace(evt.Status))
	inserted, err := s.store.RecordPaymentEvent(r.Context(), store.PaymentEvent{
		Gateway:     "midtrans",
		ExternalID:  evt.OrderID,
		EventType:   eventType,
		Signature:   evt.Signature,
		GrossAmount: parseGrossAmount(evt.GrossAmount),
		RawPayload:  evt.Raw,
		Status:      "received",
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if !inserted {
		// Event ini sudah pernah diterima. Dulu handler langsung membalas 200
		// tanpa memeriksa hasil pemrosesan sebelumnya, sehingga kegagalan
		// sementara berubah menjadi pembayaran hilang permanen: gateway
		// menganggap terkirim, dan percobaan ulang pun ditelan di sini.
		// Sekarang: hanya event yang benar-benar sudah 'processed' yang
		// dianggap selesai; selain itu diproses ulang.
		status, found, serr := s.store.PaymentEventStatus(r.Context(), "midtrans", evt.OrderID, eventType)
		if serr != nil {
			s.logger.Error("webhook read event status failed", "order_id", evt.OrderID, "error", serr)
			writeError(w, http.StatusInternalServerError, errors.New("gagal membaca status event"))
			return
		}
		if found && status == "processed" {
			writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
			return
		}
		s.logger.Warn("webhook event diproses ulang", "order_id", evt.OrderID,
			"event_type", eventType, "status_sebelumnya", status)
	}
	// 3. Efek: settlement/capture -> tandai lunas + aktivasi booking.
	switch eventType {
	case "settlement", "capture":
		if evt.FraudStatus != "" && evt.FraudStatus != "accept" {
			_ = s.store.UpdatePaymentEventStatus(r.Context(), "midtrans", evt.OrderID, eventType, "ignored", "", "")
			writeJSON(w, http.StatusOK, map[string]string{"status": "ignored"})
			return
		}
		// Cocokkan nominal SEBELUM menandai lunas. Transaksi Snap dibuat dengan
		// gross+serviceFee (lihat CreateTransaction(..., gross+serviceFee, ...)),
		// jadi tagihan yang sah = payments.gross_amount + service_fee_amount.
		// Tanpa pengecekan ini, settlement Rp1.000 untuk tagihan Rp102.000 tetap
		// dianggap lunas dan mengaktifkan sesi penuh.
		p0, gerr := s.store.GetPaymentByReference(r.Context(), evt.OrderID)
		if gerr != nil {
			// Termasuk order_id tak dikenal (ErrPaymentNotFound) maupun gangguan
			// DB: perlakukan sebagai transien agar gateway mengirim ulang.
			s.logger.Error("webhook baca payment gagal", "order_id", evt.OrderID, "error", gerr)
			writeError(w, http.StatusInternalServerError, errors.New("gagal membaca data pembayaran"))
			return
		}
		expectedAmount := p0.GrossAmount + p0.ServiceFeeAmount
		receivedAmount := parseGrossAmount(evt.GrossAmount)
		if receivedAmount != expectedAmount {
			// Nominal tidak cocok: JANGAN tandai lunas, JANGAN buat sesi. Balas
			// 200 (bukan 5xx) karena uang sudah masuk dan retry gateway tidak
			// akan mengubah nominal — rekonsiliasi manual. Status event dibuat
			// 'rejected' (satu-satunya nilai terminal yang diizinkan selain
			// received/processed/ignored) agar terlihat di audit.
			//
			// Payment sudah terminal (cancelled/refunded/expired) tetapi dana
			// masuk dengan nominal berbeda: tetap jalankan jalur rekonsiliasi
			// agar pasien diberi tahu dananya diterima dan tidak membayar lagi.
			// Dipanggil SEBELUM menulis 'rejected' karena
			// handlePaymentAfterCancellation menulis 'ignored' lebih dulu;
			// 'rejected' harus menjadi status akhir agar terlihat di audit.
			if p0.Status != "" && p0.Status != "pending" {
				s.handlePaymentAfterCancellation(r.Context(), evt, p0.Status)
			}
			_ = s.store.UpdatePaymentEventStatus(r.Context(), "midtrans", evt.OrderID, eventType, "rejected", "", "")
			s.logger.Error("webhook gross_amount tidak cocok",
				"order_id", evt.OrderID,
				"tagihan", expectedAmount,
				"diterima", receivedAmount,
				"status_payment", p0.Status)
			writeJSON(w, http.StatusOK, map[string]string{"status": "mismatch"})
			return
		}
		p, perr := s.store.MarkPaymentPaid(r.Context(), evt.OrderID, evt.TransactionID)
		if perr != nil {
			// Baca status SEKALI, lalu klasifikasikan. MarkPaymentPaid hanya
			// berhasil untuk payment berstatus 'pending', sehingga kegagalan di
			// sini berarti salah satu dari tiga hal: sudah lunas (settlement
			// ganda), sudah dibatalkan/kedaluwarsa (dana telanjur masuk), atau
			// kegagalan DB yang sesungguhnya.
			st, serr := s.store.PaymentStatusByReference(r.Context(), evt.OrderID)
			switch {
			case serr == nil && st == "paid":
				// Replay settlement SETELAH aktivasi gagal pada percobaan
				// pertama (mis. 5xx karena Google gagal membuat link Meet):
				// pembayaran sudah lunas tetapi sesi belum tentu ada. Panggil
				// aktivasi (idempoten — dijaga GetCareSessionByBookingID) agar
				// sesi benar-benar dibuat sebelum menandai event 'processed'.
				// Bila aktivasi gagal, JANGAN tandai 'processed' dan balas 5xx
				// agar gateway mengulang.
				pPaid, gerr := s.store.GetPaymentByReference(r.Context(), evt.OrderID)
				if gerr != nil {
					s.logger.Error("webhook baca payment (paid) gagal", "order_id", evt.OrderID, "error", gerr)
					writeError(w, http.StatusInternalServerError, errors.New("gagal membaca data pembayaran"))
					return
				}
				if _, aerr := s.activatePaidBooking(r, pPaid); aerr != nil {
					s.logger.Error("webhook aktivasi ulang (paid) gagal", "payment", pPaid.ID, "error", aerr)
					writeError(w, http.StatusInternalServerError, errors.New("gagal mengaktifkan booking"))
					return
				}
				_ = s.store.UpdatePaymentEventStatus(r.Context(), "midtrans", evt.OrderID, eventType, "processed", pPaid.ID, pPaid.BookingID)
				writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
				return
			case serr == nil && st != "" && st != "pending":
				// Status terminal lain: 'cancelled' (pasien membatalkan sesi
				// tetapi VA/QRIS yang sudah terbuka tetap dibayar), 'refunded',
				// 'expired', 'deny', dst. Uang sudah masuk dan TIDAK akan hilang
				// dengan mengulang webhook — jadi terminal + rekonsiliasi
				// manual, bukan 5xx selamanya.
				s.handlePaymentAfterCancellation(r.Context(), evt, st)
				writeJSON(w, http.StatusOK, map[string]string{"status": "ignored"})
				return
			}
			// 'pending' atau gagal membaca status: transien. Dulu handler
			// membalas 200 + menandai 'ignored' sehingga gateway tidak pernah
			// mengulang dan pembayaran hilang. Sekarang balas 5xx dan biarkan
			// status event tetap 'received' agar percobaan ulang gateway
			// benar-benar diproses.
			s.logger.Error("webhook mark paid failed", "order_id", evt.OrderID, "error", perr, "payment_status", st)
			writeError(w, http.StatusInternalServerError, errors.New("gagal memproses pembayaran"))
			return
		}
		if _, aerr := s.activatePaidBooking(r, p); aerr != nil {
			// Jangan tandai 'processed': pembayaran sudah lunas tetapi sesi
			// (termasuk link Google Meet-nya) belum siap. Balas 5xx agar
			// gateway mengirim ulang. Aktivasi idempoten — sesi dicari lewat
			// booking_id dan paket lewat booking_id — sehingga pengulangan
			// tidak membuat data ganda.
			s.logger.Error("webhook activate booking failed", "payment", p.ID, "error", aerr)
			writeError(w, http.StatusInternalServerError, errors.New("gagal mengaktifkan booking"))
			return
		}
		_ = s.store.UpdatePaymentEventStatus(r.Context(), "midtrans", evt.OrderID, eventType, "processed", p.ID, p.BookingID)
		writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
		return
	default:
		// expire/cancel/deny/pending: catat sebagai ignored.
		_ = s.store.UpdatePaymentEventStatus(r.Context(), "midtrans", evt.OrderID, eventType, "ignored", "", "")
		writeJSON(w, http.StatusOK, map[string]string{"status": "ignored"})
		return
	}
}

// handlePaymentAfterCancellation menangani dana yang masuk untuk pembayaran
// yang TIDAK bisa ditandai lunas lagi (mis. pasien sudah menekan "Batalkan"
// sehingga payments.status='cancelled', tetapi VA/QRIS yang sudah terbuka
// tetap dibayar). Kelas bug yang sama dengan 17f903f: uang masuk, tidak ada
// yang tahu, dan webhook 5xx diulang selamanya.
//
// Terminal — sengaja TIDAK:
//   - mengaktifkan ulang booking/sesi (keputusan produk: sesi sudah dibatalkan
//     pasien, bukan wewenang webhook untuk menghidupkannya kembali),
//   - membuat refund otomatis (butuh keputusan produk & jalur pembayaran).
//
// Yang dilakukan: catat event, log Error bertanda untuk rekonsiliasi manual,
// dan beri tahu pasien agar tidak membayar lagi.
func (s *Server) handlePaymentAfterCancellation(ctx context.Context, evt payment.WebhookEvent, paymentStatus string) {
	eventType := strings.ToLower(strings.TrimSpace(evt.Status))
	// 'ignored', bukan 'processed': tidak ada yang selesai diproses, dan replay
	// tetap diproses ulang (paymentWebhook hanya short-circuit untuk
	// 'processed'). Karena itu notifikasi di-dedupe lewat reference, bukan
	// lewat status event.
	_ = s.store.UpdatePaymentEventStatus(ctx, "midtrans", evt.OrderID, eventType, "ignored", "", "")
	pc, err := s.store.PaymentContextByReference(ctx, evt.OrderID)
	if err != nil {
		// Tanpa konteks pembayaran, penerima notifikasi tidak bisa ditentukan —
		// catat saja (jangan menebak pasien dari order_id).
		s.logger.Error("dana masuk untuk pembayaran yang sudah dibatalkan; perlu rekonsiliasi manual",
			"order_id", evt.OrderID, "status", paymentStatus, "gross_amount", evt.GrossAmount, "error", err)
		return
	}
	s.logger.Error("dana masuk untuk pembayaran yang sudah dibatalkan; perlu rekonsiliasi manual",
		"order_id", evt.OrderID, "status", paymentStatus, "gross_amount", evt.GrossAmount,
		"payment", pc.PaymentID, "booking", pc.BookingID)
	if s.alreadyNotifiedForReference(ctx, pc.PatientID, notifPaymentReconciliation, evt.OrderID) {
		return
	}
	s.notifyUser(ctx, pc.PatientID, notifPaymentReconciliation,
		"Pembayaran perlu ditindaklanjuti",
		"Pembayaran Anda kami terima setelah sesi ini dibatalkan, sehingga sesinya tidak dapat diaktifkan kembali. Tim Malva akan menghubungi Anda untuk pengembalian dana — mohon jangan membayar lagi.",
		map[string]string{
			"reference":    evt.OrderID,
			"booking_id":   pc.BookingID,
			"status":       paymentStatus,
			"gross_amount": evt.GrossAmount,
		})
}

// parseGrossAmount mengubah "150000.00" menjadi 150000 (rupiah utuh).
func parseGrossAmount(value string) int64 {
	value = strings.TrimSpace(value)
	if value == "" {
		return 0
	}
	if dot := strings.IndexByte(value, '.'); dot >= 0 {
		value = value[:dot]
	}
	n, err := strconv.ParseInt(value, 10, 64)
	if err != nil {
		return 0
	}
	return n
}

func (s *Server) listBookings(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	limit := parseQueryInt(r, "limit", 20, 100)
	bookings, err := s.store.ListBookingsForUser(r.Context(), claims.Subject, claims.Role, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"bookings": bookings})
}

func (s *Server) earningsSummary(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if !s.requireVerifiedProfessional(w, r, claims) {
		return
	}
	summary, err := s.store.EarningsSummary(r.Context(), claims.Subject)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	transactions, _ := s.store.ListEarningsTransactions(r.Context(), claims.Subject, 20)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"summary":      summary,
		"transactions": transactions,
	})
}

type payoutRequest struct {
	Bank    string `json:"bank"`
	Account string `json:"account"`
}

func (s *Server) requestPayout(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if !s.requireVerifiedProfessional(w, r, claims) {
		return
	}
	var req payoutRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	bank := strings.TrimSpace(req.Bank)
	account := strings.TrimSpace(req.Account)
	if bank == "" || account == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "bank dan nomor rekening wajib diisi"})
		return
	}
	earningID := r.PathValue("earning_id")
	if err := s.store.RequestPayout(r.Context(), earningID, claims.Subject, bank, account); err != nil {
		writeError(w, http.StatusNotFound, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"status": "payout_requested"})
}

// requestPayoutAll mencairkan SELURUH saldo pending sekaligus (model saldo
// gabungan). Endpoint per-earning di atas dipertahankan untuk kompatibilitas,
// tetapi aplikasi tidak lagi memakainya: sebelumnya satu klik hanya meminta
// earning pertama padahal UI menyebut seluruh net sebagai "Balance".
func (s *Server) requestPayoutAll(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if !s.requireVerifiedProfessional(w, r, claims) {
		return
	}
	var req payoutRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	bank := strings.TrimSpace(req.Bank)
	account := strings.TrimSpace(req.Account)
	if bank == "" || account == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "bank dan nomor rekening wajib diisi"})
		return
	}
	count, total, err := s.store.PayoutAllPending(r.Context(), claims.Subject, bank, account)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if count == 0 {
		// 409, bukan 200: tidak ada yang berubah, dan klien tidak boleh
		// menampilkan pesan sukses.
		writeJSON(w, http.StatusConflict, map[string]string{"error": "Tidak ada saldo yang bisa dicairkan."})
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"status":     "payout_requested",
		"count":      count,
		"net_amount": total,
	})
}

// ============================================================
// BOOKING, PAYMENT, EARNINGS, E-PRESCRIPTION
// ============================================================

type createEPrescriptionRequest struct {
	PatientID    string           `json:"patient_id"`
	Instructions string           `json:"instructions"`
	Notes        string           `json:"notes"`
	Items        []eRxItemRequest `json:"items"`
}

type eRxItemRequest struct {
	Name         string  `json:"name"`
	Dosage       string  `json:"dosage"`
	Frequency    string  `json:"frequency"`
	Days         int     `json:"days"`
	UnitsPerDay  int     `json:"units_per_day"`
	MedicationID *string `json:"medication_id,omitempty"`
}

func (s *Server) createEPrescription(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if !s.requireVerifiedProfessional(w, r, claims) {
		return
	}
	cred, err := s.store.GetProfessionalCredential(r.Context(), claims.Subject)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if cred.Specialization != "Sp.KJ" {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "E-Prescription hanya untuk Psikiater (Sp.KJ). Psikolog M.Psi tidak dapat membuat resep."})
		return
	}

	var req createEPrescriptionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	if len(req.Items) == 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "at least one medication item is required"})
		return
	}

	// Resep hanya boleh diterbitkan untuk pasien yang benar-benar terhubung
	// dengan psikiater ini. Tanpa cek ini, profesional mana pun bisa menulis
	// resep (dan mengirim notifikasi) ke pasien yang tak pernah ia tangani —
	// sekaligus membocorkan keberadaan akun pasien tersebut.
	if strings.TrimSpace(req.PatientID) == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "patient_id wajib diisi"})
		return
	}
	_, _, linkedToPatient, lerr := s.store.AreUsersLinked(r.Context(), req.PatientID, claims.Subject)
	if lerr != nil {
		writeError(w, http.StatusInternalServerError, lerr)
		return
	}
	if !linkedToPatient {
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error": "Pasien tidak terhubung dengan anda. Resep hanya untuk pasien yang pernah menjalani sesi dengan anda.",
		})
		return
	}

	sig := map[string]interface{}{
		"str_number":  cred.STRNumber,
		"sip_number":  cred.SIPNumber,
		"sipp_number": cred.SIPPNumber,
		"timestamp":   clock.Now().Format(time.RFC3339),
	}

	qrToken := fmt.Sprintf("RX-%s-%d", claims.Subject[:8], time.Now().UnixNano()/1e6)
	rx, err := s.store.CreateEPrescription(r.Context(), store.EPrescription{
		ProfessionalID: claims.Subject,
		PatientID:      req.PatientID,
		Notes:          req.Notes,
		Instructions:   req.Instructions,
		SignatureData:  sig,
		QRToken:        qrToken,
	}, rxItemsFromRequest(req.Items))
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	// Notifikasi pasien (best-effort; kegagalan TIDAK menggagalkan resep). AC-3.1.
	doctorName := "dokter"
	if user, uerr := s.store.GetUserByID(r.Context(), claims.Subject); uerr == nil && strings.TrimSpace(user.DisplayName) != "" {
		doctorName = strings.TrimSpace(user.DisplayName)
	}
	s.notifyPatient(r, rx.PatientID, "prescription_created",
		"Resep baru dari "+doctorName,
		"Resep elektronik barumu sudah tersedia. Buka Malva untuk melihat detail.",
		map[string]string{"prescription_id": rx.ID, "professional_id": claims.Subject})
	writeJSON(w, http.StatusCreated, map[string]interface{}{"prescription": rx})
}

func rxItemsFromRequest(items []eRxItemRequest) []store.EPrescriptionItem {
	out := make([]store.EPrescriptionItem, len(items))
	for i, item := range items {
		out[i] = store.EPrescriptionItem{
			MedicationID: item.MedicationID,
			Name:         item.Name,
			// Dosage WAJIB dipetakan: dulu field ini terbuang diam-diam sehingga
			// e_prescription_items.dosage selalu tersimpan kosong. Dampaknya
			// nyata — obat hasil resep yang disalin ke tabel `medications`
			// (lihat store.syncPrescriptionItemsToMedications) tampil dengan
			// dosis default "0 mg" di rekam medis & daily check-in pasien,
			// dan semua resep dengan nama obat sama saling menimpa saat dedup.
			Dosage:      item.Dosage,
			Frequency:   item.Frequency,
			Days:        item.Days,
			UnitsPerDay: item.UnitsPerDay,
		}
		if item.UnitsPerDay <= 0 {
			out[i].UnitsPerDay = 1
		}
		if item.Days <= 0 {
			out[i].Days = 30
		}
	}
	return out
}

func (s *Server) getEPrescription(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	rxID := r.PathValue("id")
	rx, err := s.store.GetEPrescription(r.Context(), rxID)
	if err != nil {
		writeError(w, http.StatusNotFound, err)
		return
	}
	isDoctor := claims.Role == "professional" && claims.Subject == rx.ProfessionalID
	isPatient := claims.Role == "patient" && claims.Subject == rx.PatientID
	if !isDoctor && !isPatient {
		if s.consentAllows(r, rx.PatientID, claims.Subject, "health_record") {
			// allowed
		} else {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "No consent to view this prescription"})
			return
		}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"prescription": rx})
}

func (s *Server) listEPrescriptions(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	rx, err := s.store.ListEPrescriptionsForUser(r.Context(), claims.Subject, claims.Role)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"prescriptions": rx})
}

func (s *Server) verifyEPrescriptionQR(w http.ResponseWriter, r *http.Request) {
	token := r.URL.Query().Get("token")
	if token == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "token is required"})
		return
	}
	rx, err := s.store.GetEPrescriptionByQR(r.Context(), token)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "Invalid prescription QR"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"valid":        true,
		"prescription": rx,
		"verified_by":  "Malva QR Verification",
	})
}
