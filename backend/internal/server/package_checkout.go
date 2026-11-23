package server

import (
	"context"
	"errors"
	"net/http"
	"slices"
	"time"

	"malva/backend/internal/clock"
	"malva/backend/internal/store"
)

func bookingServiceCategory(serviceType, sessionType string) string {
	if serviceType == "package_session" {
		return "package"
	}
	if sessionType == "chat" {
		return "quick_chat"
	}
	return "quick_video"
}

func sessionServiceCategory(session store.CareSession) string {
	if session.PackageID != nil && *session.PackageID != "" {
		return "package"
	}
	return bookingServiceCategory("", session.SessionType)
}

func (s *Server) validatePackageCheckoutSlots(ctx context.Context, pkg store.CarePackage, first time.Time, firstDuration int, requested []string) ([]store.PackageCheckoutSlot, error) {
	if len(requested) > min(3, pkg.TotalSessions-1) {
		return nil, errors.New("maksimal tiga sesi tambahan sebelum pembayaran")
	}
	active, found, err := s.store.ActivePackageBetween(ctx, pkg.PatientID, pkg.ProfessionalID)
	if err != nil {
		return nil, err
	}
	base := clock.Now()
	if found {
		base = active.ExpiresAt
	}
	expires := base.AddDate(0, 0, pkg.ValidityDays)
	slots := make([]store.PackageCheckoutSlot, 0, len(requested))
	for _, raw := range requested {
		start, err := parseWIBDateTime(raw)
		if err != nil || start.Format("2006-01-02T15:04") != raw {
			return nil, errors.New("jadwal sesi tambahan harus format YYYY-MM-DDTHH:mm WIB")
		}
		duration := s.slotDurationFor(ctx, pkg.ProfessionalID, start, "package")
		if !start.Before(expires) {
			return nil, store.ErrCarePackageExpired
		}
		if err := s.validateSlotFor(ctx, pkg.ProfessionalID, "package", start, duration, true); err != nil {
			return nil, err
		}
		slots = append(slots, store.PackageCheckoutSlot{ScheduledAt: start, DurationMinutes: duration})
	}
	slices.SortFunc(slots, func(a, b store.PackageCheckoutSlot) int { return a.ScheduledAt.Compare(b.ScheduledAt) })
	end := first.Add(time.Duration(firstDuration) * time.Minute)
	for _, slot := range slots {
		if slot.ScheduledAt.Before(end) {
			return nil, errors.New("sesi tambahan harus setelah sesi pertama dan tidak boleh bertabrakan")
		}
		end = slot.ScheduledAt.Add(time.Duration(slot.DurationMinutes) * time.Minute)
	}
	return slots, nil
}

func (s *Server) activatePackageCheckoutSlots(r *http.Request, booking store.Booking, pkg store.CarePackage) error {
	ctx := r.Context()
	slots, err := s.store.ListPackageCheckoutSlots(ctx, booking.ID)
	if err != nil {
		return err
	}
	missed := false
	for _, slot := range slots {
		if slot.Resolved {
			missed = missed || slot.Missed
			continue
		}
		start := slot.ScheduledAt
		if slotAlreadyPassed(start) || !start.Before(pkg.ExpiresAt) {
			if err := s.store.SkipPackageCheckoutSlot(ctx, slot.ID); err != nil {
				return err
			}
			missed = true
			continue
		}
		err := s.validateSlotFor(ctx, booking.ProfessionalID, "package", start, slot.DurationMinutes, false)
		if err == nil {
			err = s.createPaidPackageCheckoutSession(r, booking, pkg, slot)
		}
		switch {
		case err == nil, errors.Is(err, store.ErrCheckoutSlotResolved):
		case errors.Is(err, store.ErrCareSlotTaken), errors.Is(err, errPracticeWindow),
			errors.Is(err, errPracticeDayOff), errors.Is(err, store.ErrCarePackageInactive),
			errors.Is(err, store.ErrCarePackageExpired), errors.Is(err, store.ErrCarePackageExhausted):
			if err := s.store.SkipPackageCheckoutSlot(ctx, slot.ID); err != nil {
				return err
			}
			missed = true
		default:
			return err
		}
	}
	const kind = "package_checkout_slots_unavailable"
	if missed && !s.alreadyNotifiedForBooking(ctx, booking.PatientID, kind, booking.ID) {
		s.notifyPatient(r, booking.PatientID, kind, "Pilih kembali jadwal sesi",
			"Sebagian jadwal tambahan sudah tidak tersedia. Sisa kredit sesi dapat digunakan di My Care.",
			map[string]string{"booking_id": booking.ID, "package_id": pkg.ID})
	}
	return nil
}

func (s *Server) createPaidPackageCheckoutSession(r *http.Request, booking store.Booking, pkg store.CarePackage, slot store.PackageCheckoutSlot) error {
	ctx := r.Context()
	meet, event, pending, err := s.prepareMeetEventFor(ctx, booking.PatientID, booking.ProfessionalID, slot.ScheduledAt, slot.DurationMinutes)
	if err != nil && !errors.Is(err, ErrMeetUnavailable) {
		return err
	}
	cs, err := s.store.CreateCareSession(ctx, store.CareSession{
		PackageID: &pkg.ID, PatientID: booking.PatientID, ProfessionalID: booking.ProfessionalID,
		CheckoutSlotID: slot.ID, SessionType: "video", ScheduledAt: slot.ScheduledAt,
		DurationMinutes: slot.DurationMinutes, Status: "scheduled",
		MeetingURL: meet, GoogleEventID: event, AllowPendingMeet: pending || errors.Is(err, ErrMeetUnavailable),
	})
	if err != nil {
		if event != "" {
			s.cancelMeetEventBestEffort(ctx, s.calendar, booking.ProfessionalID, event)
		}
		return err
	}
	s.notifyPatient(r, booking.PatientID, "session_scheduled", "Sesi tambahan terjadwal",
		slot.ScheduledAt.In(wibLoc).Format("02 Jan 2006 15:04")+" WIB",
		map[string]string{"session_id": cs.ID, "package_id": pkg.ID})
	return nil
}
