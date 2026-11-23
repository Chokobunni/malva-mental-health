package store

import (
	"context"
	"errors"
	"testing"

	"malva/backend/internal/clock"
)

func TestPackagePatientCapacityAdmission(t *testing.T) {
	s, db, ctx := attendedTestStore(t)
	professional := mustUUID(t, db, ctx)
	patients := []string{mustUUID(t, db, ctx), mustUUID(t, db, ctx)}
	t.Cleanup(func() {
		cleanup := context.Background()
		_, _ = db.ExecContext(cleanup, "DELETE FROM care_packages WHERE professional_id=$1", professional)
		_, _ = db.ExecContext(cleanup, "DELETE FROM professional_pricing WHERE professional_id=$1", professional)
		_, _ = db.ExecContext(cleanup, "DELETE FROM users WHERE id IN ($1,$2,$3)", professional, patients[0], patients[1])
	})
	for i, id := range append([]string{professional}, patients...) {
		role := "patient"
		if i == 0 {
			role = "professional"
		}
		if _, err := db.ExecContext(ctx, "INSERT INTO users(id,email,password_hash,role,display_name) VALUES($1,$2,'x',$3,'Test')", id, id+"@capacity.test", role); err != nil {
			t.Fatal(err)
		}
	}
	seed := func(patient string) Payment {
		t.Helper()
		var booking string
		if err := db.QueryRowContext(ctx,
			"INSERT INTO bookings(patient_id,professional_id,service_type,session_type,booking_date,slot_time,price) VALUES($1,$2,'package_session','chat',current_date,'10:00',100000) RETURNING id",
			patient, professional).Scan(&booking); err != nil {
			t.Fatal(err)
		}
		if _, err := db.ExecContext(ctx,
			"INSERT INTO care_packages(patient_id,professional_id,booking_id,expires_at) VALUES($1,$2,$3,$4)",
			patient, professional, booking, clock.Now().AddDate(0, 0, 42)); err != nil {
			t.Fatal(err)
		}
		return Payment{BookingID: booking, Reference: booking, PaymentMethod: "qris", Gateway: "midtrans", GrossAmount: 100000, ServiceFeeAmount: 2000, PlatformFeeAmount: 10000, NetAmount: 90000}
	}
	capacity := 1
	pricingBefore, err := s.GetProfessionalPricing(ctx, professional)
	if err != nil || pricingBefore.PatientCapacity == nil || *pricingBefore.PatientCapacity != 2 {
		t.Fatalf("missing pricing should have finite default: %+v err=%v", pricingBefore, err)
	}
	if remaining, _, _, err := s.PackagePatientAvailability(ctx, professional, patients[0]); err != nil || remaining == nil || *remaining != 2 {
		t.Fatalf("missing pricing admission: remaining=%v err=%v", remaining, err)
	}
	writeCapacity := func(value *int) {
		t.Helper()
		if _, err := s.UpsertProfessionalPricing(ctx, ProfessionalPricing{ProfessionalID: professional, PatientCapacity: value, PatientCapacitySet: true, KeepExistingPrices: true}); err != nil {
			t.Fatal(err)
		}
	}
	writeCapacity(&capacity)
	options := []Payment{seed(patients[0]), seed(patients[1])}
	type outcome struct {
		index   int
		payment Payment
		err     error
	}
	outcomes := make(chan outcome, 2)
	start := make(chan struct{})
	for i, input := range options {
		go func() {
			<-start
			p, err := s.CreatePayment(ctx, input)
			outcomes <- outcome{i, p, err}
		}()
	}
	close(start)
	winner, loser := <-outcomes, <-outcomes
	if winner.err != nil {
		winner, loser = loser, winner
	}
	if winner.err != nil || !errors.Is(loser.err, ErrPackageCapacity) {
		t.Fatalf("two simultaneous payments at capacity one: winner=%v loser=%v", winner.err, loser.err)
	}
	zero := 0
	writeCapacity(&zero)
	if remaining, renew, resume, err := s.PackagePatientAvailability(ctx, professional, patients[winner.index]); err != nil || remaining == nil || *remaining != 0 || renew || !resume {
		t.Fatalf("pending occupant: remaining=%v renew=%v resume=%v err=%v", remaining, renew, resume, err)
	}
	retry := options[winner.index]
	retry.Reference += "-retry"
	if existing, err := s.CreatePayment(ctx, retry); err != nil || existing.Reference != winner.payment.Reference {
		t.Fatalf("idempotent payment: %s, %v", existing.Reference, err)
	}
	writeCapacity(&capacity)
	if _, err := db.ExecContext(ctx, "UPDATE payments SET created_at=$1 WHERE reference=$2",
		clock.Now().AddDate(0, 0, -1), winner.payment.Reference); err != nil {
		t.Fatal(err)
	}
	other, err := s.CreatePayment(ctx, options[loser.index])
	if err != nil {
		t.Fatalf("payment without a page kept an abandoned reservation: %v", err)
	}
	calls := 0
	gateway := func() (string, string, error) {
		calls++
		return "snap-token", "https://payment.example.test", nil
	}
	if _, err := s.InitializePaymentGateway(ctx, winner.payment.Reference, "midtrans", gateway); !errors.Is(err, ErrPackageCapacity) || calls != 0 {
		t.Fatalf("retry exceeded capacity: calls=%d err=%v", calls, err)
	}
	if _, err := s.InitializePaymentGateway(ctx, other.Reference, "midtrans", gateway); err != nil || calls != 1 {
		t.Fatalf("admitted checkout did not get a payment page: calls=%d err=%v", calls, err)
	}
	if _, err := db.ExecContext(ctx, "UPDATE payments SET created_at=$1 WHERE reference=$2",
		clock.Now().AddDate(0, 0, -1), other.Reference); err != nil {
		t.Fatal(err)
	}
	if remaining, _, resume, err := s.PackagePatientAvailability(ctx, professional, patients[loser.index]); err != nil || remaining == nil || *remaining != 0 || !resume {
		t.Fatalf("checkout with a payment page lost its reservation: remaining=%v resume=%v err=%v", remaining, resume, err)
	}
	if err := s.SetPaymentTerminal(ctx, other.Reference, "expired"); err != nil {
		t.Fatal(err)
	}
	if err := s.SetPaymentTerminal(ctx, winner.payment.Reference, "expired"); err != nil {
		t.Fatal(err)
	}
	writeCapacity(&capacity)
	if remaining, renew, resume, err := s.PackagePatientAvailability(ctx, professional, patients[winner.index]); err != nil || remaining == nil || *remaining != 1 || renew || resume {
		t.Fatalf("released expired reservation: remaining=%v renew=%v resume=%v err=%v", remaining, renew, resume, err)
	}
	next := options[loser.index]
	next.Reference += "-next"
	if _, err := s.CreatePayment(ctx, next); err != nil {
		t.Fatalf("released slot unavailable: %v", err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE care_packages SET status='active' WHERE booking_id=$1`, options[loser.index].BookingID); err != nil {
		t.Fatal(err)
	}
	if remaining, renew, resume, err := s.PackagePatientAvailability(ctx, professional, patients[loser.index]); err != nil || remaining == nil || *remaining != 0 || !renew || resume {
		t.Fatalf("active occupant: remaining=%v renew=%v resume=%v err=%v", remaining, renew, resume, err)
	}
	if _, err := s.CreatePayment(ctx, seed(patients[loser.index])); err != nil {
		t.Fatalf("active patient could not renew at capacity: %v", err)
	}
	if remaining, renew, resume, err := s.PackagePatientAvailability(ctx, professional, patients[loser.index]); err != nil || remaining == nil || *remaining != 0 || !renew || !resume {
		t.Fatalf("renewing occupant: remaining=%v renew=%v resume=%v err=%v", remaining, renew, resume, err)
	}
	capacity = 2
	writeCapacity(&capacity)
	if remaining, _, _, err := s.PackagePatientAvailability(ctx, professional, patients[winner.index]); err != nil || remaining == nil || *remaining != 1 {
		t.Fatalf("one distinct occupant should leave one place at capacity two: remaining=%v err=%v", remaining, err)
	}
	if _, err := s.UpsertProfessionalPricing(ctx, ProfessionalPricing{ProfessionalID: professional, PackagePrice: 70000}); err != nil {
		t.Fatal(err)
	}
	pricing, err := s.GetProfessionalPricing(ctx, professional)
	if err != nil || pricing.PatientCapacity == nil || *pricing.PatientCapacity != 2 || pricing.PackagePrice != 70000 {
		t.Fatalf("price update changed capacity: %+v, %v", pricing, err)
	}
	writeCapacity(nil)
	pricing, err = s.GetProfessionalPricing(ctx, professional)
	if err != nil || pricing.PatientCapacity == nil || *pricing.PatientCapacity != 2 || pricing.PackagePrice != 70000 {
		t.Fatalf("capacity clear changed price: %+v, %v", pricing, err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE professional_pricing SET patient_capacity=NULL WHERE professional_id=$1`, professional); err != nil {
		t.Fatal(err)
	}
	pricing, err = s.GetProfessionalPricing(ctx, professional)
	if err != nil || pricing.PatientCapacity == nil || *pricing.PatientCapacity != 2 {
		t.Fatalf("legacy null pricing: %+v err=%v", pricing, err)
	}
	if remaining, _, _, err := s.PackagePatientAvailability(ctx, professional, patients[winner.index]); err != nil || remaining == nil || *remaining != 1 {
		t.Fatalf("null capacity must apply finite default and count legacy patients: remaining=%v err=%v", remaining, err)
	}
}
