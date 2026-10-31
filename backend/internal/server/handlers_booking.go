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
			return "", errors.New("slot sesi pertama paket tidak valid")
		}
		duration := booking.DurationMinutes
		if duration <= 0 {
			duration = s.slotDurationFor(ctx, booking.ProfessionalID, start)
		}
		// Sesi pertama paket bisa bertipe video. Link Google Meet WAJIB dibuat
		// SEBELUM baris sesi disimpan: store menolak sesi video tanpa link, dan
		// kegagalan Google tidak boleh menyisakan sesi yang tidak bisa dipakai.
		meetingURL, googleEventID := "", ""
		if isVideoSession(booking.SessionType) {
			eventID, meetURL, merr := s.createMeetEventFor(ctx, booking.PatientID, booking.ProfessionalID, start, duration)
			if merr != nil {
				return "", merr
			}
			meetingURL, googleEventID = meetURL, eventID
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
		})
		if cerr != nil {
			// Event sudah lahir di kalender profesional; jangan biarkan
			// menggantung tanpa sesi yang menunjuknya.
			if googleEventID != "" {
				s.cancelMeetEventBestEffort(ctx, s.calendar, booking.ProfessionalID, googleEventID)
			}
			return "", cerr
		}
		s.notifyPatient(r, booking.ProfessionalID, "package_activated",
			"Paket baru aktif", "Pasien membeli paket 4 sesi.",
			map[string]string{"package_id": pkg.ID, "patient_id": booking.PatientID})
		pkgBody := "Paket 4 sesi / 6 minggu aktif. Sesi pertama: " + start.In(wibLoc).Format("02 Jan 2006 15:04") + "."
		if strings.TrimSpace(cs.MeetingURL) != "" {
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
	if booked, berr := s.store.IsSlotBooked(ctx, booking.ProfessionalID, start); berr != nil || booked {
		// Slot keburu diambil saat pembayaran: kembalikan ke pending agar
		// pasien memilih ulang (pembayaran tetap tercatat untuk refund manual).
		_ = s.store.UpdateBookingStatus(ctx, booking.ID, "pending")
		return "", errors.New("slot keburu terisi saat pembayaran; booking dikembalikan ke pending")
	}
	// Quick consult video: link WAJIB ada sebelum sesi disimpan (lihat catatan
	// pada alur aktivasi paket di atas).
	meetingURL, googleEventID := "", ""
	if isVideoSession(booking.SessionType) {
		eventID, meetURL, merr := s.createMeetEventFor(ctx, booking.PatientID, booking.ProfessionalID, start, duration)
		if merr != nil {
			return "", merr
		}
		meetingURL, googleEventID = meetURL, eventID
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
	})
	if cerr != nil {
		if googleEventID != "" {
			s.cancelMeetEventBestEffort(ctx, s.calendar, booking.ProfessionalID, googleEventID)
		}
		return "", cerr
	}
	// Quick consult: buat relasi agar chat sesi bisa dipakai (tanpa data sharing).
	_, _ = s.store.LinkPatientToProfessional(ctx, booking.PatientID, booking.ProfessionalID)
	s.notifyPatient(r, booking.ProfessionalID, "session_scheduled",
		"Sesi baru dijadwalkan", "Ada sesi quick consult baru.",
		map[string]string{"session_id": cs.ID, "patient_id": booking.PatientID})
	quickBody := "Sesi pada " + start.In(wibLoc).Format("02 Jan 2006 15:04") + "."
	if strings.TrimSpace(cs.MeetingURL) != "" {
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
		p, perr := s.store.MarkPaymentPaid(r.Context(), evt.OrderID, evt.TransactionID)
		if perr != nil {
			// Notifikasi settlement ganda untuk payment yang sudah lunas bukan
			// kegagalan: cukup tandai event selesai lalu balas 200.
			if st, serr := s.store.PaymentStatusByReference(r.Context(), evt.OrderID); serr == nil && st == "paid" {
				_ = s.store.UpdatePaymentEventStatus(r.Context(), "midtrans", evt.OrderID, eventType, "processed", "", "")
				writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
				return
			}
			// Kegagalan sesungguhnya (mis. DB sedang tidak tersedia). Dulu
			// handler membalas 200 + menandai 'ignored' sehingga gateway tidak
			// pernah mengulang dan pembayaran hilang. Sekarang balas 5xx dan
			// biarkan status event tetap 'received' agar percobaan ulang
			// gateway benar-benar diproses.
			s.logger.Error("webhook mark paid failed", "order_id", evt.OrderID, "error", perr)
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
