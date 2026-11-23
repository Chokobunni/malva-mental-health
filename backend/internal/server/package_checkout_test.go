package server

import (
	"context"
	"errors"
	"fmt"
	"testing"
	"time"

	"malva/backend/internal/clock"
	"malva/backend/internal/store"
)

func TestPackageCheckoutKeepsUnusableCreditAndReplaysSafely(t *testing.T) {
	ctx := context.Background()
	db, st := openOnboardingTestStore(t)
	f := newActivationFixture(t, db, st, nil)
	pkg := f.pendingPackage(t)
	day := clock.Now().AddDate(0, 0, 4)
	first := time.Date(day.Year(), day.Month(), day.Day(), 10, 0, 0, 0, wibLoc)
	if err := st.UpsertSchedules(ctx, f.prof.ID, []store.ProfessionalSchedule{{
		ServiceCategory: "package", DayOfWeek: int(first.Weekday()),
		StartTime: "10:00", EndTime: "14:00", SlotDurationMinutes: 60, IsActive: true,
	}}); err != nil {
		t.Fatal(err)
	}
	second := first.Add(time.Hour)
	third := first.Add(2 * time.Hour)
	if _, err := f.srv.validatePackageCheckoutSlots(ctx, pkg, first, 60,
		[]string{first.Format("2006-01-02T15:04")}); err == nil {
		t.Fatal("checkout accepted an overlapping session")
	}
	slots, err := f.srv.validatePackageCheckoutSlots(ctx, pkg, first, 60,
		[]string{third.Format("2006-01-02T15:04"), second.Format("2006-01-02T15:04")})
	if err != nil {
		t.Fatal(err)
	}
	input := store.Booking{PatientID: f.patient.ID, ProfessionalID: f.prof.ID,
		ServiceType: "package_session", SessionType: "video", DurationMinutes: 60,
		BookingDate: first.Format("2006-01-02"), SlotTime: first.Format("15:04"), Price: pkg.Price}
	booking, err := st.CreatePackageBooking(ctx, pkg.ID, input, slots...)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		_, _ = db.ExecContext(ctx, `DELETE FROM package_checkout_slots WHERE booking_id=$1`, booking.ID)
	})
	if again, err := st.CreatePackageBooking(ctx, pkg.ID, input, slots...); err != nil || again.ID != booking.ID {
		t.Fatalf("identical checkout retry = %v, %v", again.ID, err)
	}
	if _, err := st.CreatePackageBooking(ctx, pkg.ID, input, slots[:1]...); !errors.Is(err, store.ErrPurchaseConflict) {
		t.Fatalf("changing stored intent = %v", err)
	}
	if _, err := st.CreatePackageBooking(ctx, pkg.ID, input, slots[:0]...); !errors.Is(err, store.ErrPurchaseConflict) {
		t.Fatalf("clearing stored intent = %v", err)
	}
	if _, err := st.CreateCareSession(ctx, store.CareSession{PatientID: f.patient.ID,
		ProfessionalID: f.prof.ID, SessionType: "chat", ScheduledAt: third,
		DurationMinutes: 60}); err != nil {
		t.Fatal(err)
	}
	payment, err := st.CreatePayment(ctx, store.Payment{BookingID: booking.ID,
		GrossAmount: pkg.Price, Reference: fmt.Sprintf("optional-%d", time.Now().UnixNano())})
	if err != nil {
		t.Fatal(err)
	}
	payment, err = st.MarkPaymentPaid(ctx, payment.Reference, "")
	if err != nil {
		t.Fatal(err)
	}
	if err := f.activate(t, payment); err != nil {
		t.Fatal(err)
	}
	if err := f.activate(t, payment); err != nil {
		t.Fatal(err)
	}
	result, err := st.GetCarePackage(ctx, pkg.ID)
	if err != nil || result.UsedSessions != 2 || result.TotalSessions-result.UsedSessions != 2 {
		t.Fatalf("paid package after replay = %+v, %v", result, err)
	}
	saved, err := st.ListPackageCheckoutSlots(ctx, booking.ID)
	if err != nil || len(saved) != 2 || !saved[0].Resolved || saved[0].Missed || !saved[1].Missed {
		t.Fatalf("checkout outcomes = %+v, %v", saved, err)
	}
}
