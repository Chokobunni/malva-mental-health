package server

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
	"malva/backend/internal/payment"
	"malva/backend/internal/store"
)

func TestPackageBookingUsesSelectedPackageAndRetries(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := verifiedProfessional(t, db, st)
	srv := newOnboardingTestServer(db)
	start := clock.Now().AddDate(0, 0, 4)
	if _, err := db.Exec(`INSERT INTO professional_schedules(professional_id,day_of_week,start_time,end_time) VALUES($1,$2,'00:00','23:59')`, prof.ID, int(start.Weekday())); err != nil {
		t.Fatal(err)
	}
	pkg, err := st.CreateCarePackage(context.Background(), store.CarePackage{PatientID: patient.ID, ProfessionalID: prof.ID, Price: 100000})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = db.Exec(`DELETE FROM care_packages WHERE patient_id=$1`, patient.ID) })
	body := fmt.Sprintf(`{"package_id":%q,"service_type":"package_session","session_type":"chat","booking_date":%q,"slot_time":"10:00","duration_minutes":30}`, pkg.ID, start.Format("2006-01-02"))
	var id string
	for i := 0; i < 2; i++ {
		rec := httptest.NewRecorder()
		srv.createBooking(rec, httptest.NewRequest("POST", "/v1/bookings", strings.NewReader(body)), auth.Claims{Subject: patient.ID, Role: "patient"})
		if rec.Code < 200 || rec.Code >= 300 {
			t.Fatalf("retry %d: %d %s", i, rec.Code, rec.Body.String())
		}
		var result struct {
			Booking store.Booking `json:"booking"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &result); err != nil {
			t.Fatal(err)
		}
		if i == 0 {
			id = result.Booking.ID
		} else if id != result.Booking.ID {
			t.Fatal("retry created a different booking")
		}
	}
	fresh, err := st.GetCarePackage(context.Background(), pkg.ID)
	if err != nil || fresh.BookingID == nil || *fresh.BookingID != id {
		t.Fatalf("package not linked to booking: %+v %v", fresh, err)
	}
}

func TestLegacyResumeBindsSelectedPackageAmongDuplicatePendingPurchases(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := verifiedProfessional(t, db, st)
	start := clock.Now().AddDate(0, 0, 4)
	if _, err := db.Exec(`INSERT INTO professional_schedules(professional_id,day_of_week,start_time,end_time) VALUES($1,$2,'00:00','23:59')`, prof.ID, int(start.Weekday())); err != nil {
		t.Fatal(err)
	}
	booking, pay := createPendingBookingAt(t, db, st, patient.ID, prof.ID, "package_session", "chat", start)
	selected, err := st.CreateCarePackage(context.Background(), store.CarePackage{PatientID: patient.ID, ProfessionalID: prof.ID, Price: 100000})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = db.Exec(`DELETE FROM care_packages WHERE patient_id=$1`, patient.ID) })
	var duplicateID string
	if err := db.QueryRow(`INSERT INTO care_packages(patient_id,professional_id,price,expires_at) VALUES($1,$2,100000,$3) RETURNING id`, patient.ID, prof.ID, start.AddDate(0, 0, 42)).Scan(&duplicateID); err != nil {
		t.Fatal(err)
	}
	body := fmt.Sprintf(`{"package_id":%q,"service_type":"package_session","session_type":"chat","booking_date":%q,"slot_time":%q,"duration_minutes":30}`, selected.ID, booking.BookingDate, booking.SlotTime)
	srv := newOnboardingTestServer(db)
	for i := 0; i < 2; i++ {
		rec := httptest.NewRecorder()
		srv.createBooking(rec, httptest.NewRequest("POST", "/v1/bookings", strings.NewReader(body)), auth.Claims{Subject: patient.ID, Role: "patient"})
		if rec.Code < 200 || rec.Code >= 300 {
			t.Fatalf("bind legacy purchase: %d %s", rec.Code, rec.Body.String())
		}
		var result struct {
			Booking store.Booking `json:"booking"`
		}
		if err := json.Unmarshal(rec.Body.Bytes(), &result); err != nil {
			t.Fatal(err)
		}
		if result.Booking.ID != booking.ID {
			t.Fatal("legacy resume created another booking")
		}
	}
	if _, err := st.MarkPaymentPaid(context.Background(), pay.Reference, ""); err != nil {
		t.Fatal(err)
	}
	activated, _, err := st.ActivatePendingPackage(context.Background(), patient.ID, prof.ID, booking.ID)
	if err != nil {
		t.Fatal(err)
	}
	if activated.ID != selected.ID {
		t.Fatal("paid another legacy purchase")
	}
	duplicate, err := st.GetCarePackage(context.Background(), duplicateID)
	if err != nil || duplicate.Status != "pending_payment" || duplicate.BookingID != nil {
		t.Fatalf("duplicate purchase changed: %+v %v", duplicate, err)
	}
}

func TestPendingPackageCreationConcurrentRetry(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := verifiedProfessional(t, db, st)
	t.Cleanup(func() { _, _ = db.Exec(`DELETE FROM care_packages WHERE patient_id=$1`, patient.ID) })
	var wg sync.WaitGroup
	ids := make(chan string, 6)
	errs := make(chan error, 6)
	for i := 0; i < 6; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			p, e := st.CreateCarePackage(context.Background(), store.CarePackage{PatientID: patient.ID, ProfessionalID: prof.ID, Price: 100000})
			if e != nil {
				errs <- e
			} else {
				ids <- p.ID
			}
		}()
	}
	wg.Wait()
	close(ids)
	close(errs)
	for err := range errs {
		t.Fatal(err)
	}
	first := ""
	for id := range ids {
		if first == "" {
			first = id
		}
		if id != first {
			t.Fatal("concurrent retry created duplicate packages")
		}
	}
}

func TestPaymentCreationConcurrentRetryKeepsReference(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := verifiedProfessional(t, db, st)
	booking, initial := createPendingBookingAt(t, db, st, patient.ID, prof.ID, "quick_consult", "chat", clock.Now().AddDate(0, 0, 4))
	var wg sync.WaitGroup
	ids := make(chan string, 5)
	errs := make(chan error, 5)
	for i := 0; i < 5; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			p, e := st.CreatePayment(context.Background(), store.Payment{BookingID: booking.ID, PaymentMethod: "qris", GrossAmount: 100000, ServiceFeeAmount: 2000, PlatformFeeAmount: 10000, NetAmount: 90000, Reference: fmt.Sprintf("RETRY-%d-%d", time.Now().UnixNano(), i)})
			if e != nil {
				errs <- e
			} else {
				ids <- p.Reference
			}
		}(i)
	}
	wg.Wait()
	close(ids)
	close(errs)
	for e := range errs {
		t.Fatal(e)
	}
	for id := range ids {
		if id != initial.Reference {
			t.Fatal("retry created a second gateway reference")
		}
	}
}

func TestPaidPackageReplayDoesNotConsumeAnotherPending(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := verifiedProfessional(t, db, st)
	t.Cleanup(func() { _, _ = db.Exec(`DELETE FROM care_packages WHERE patient_id=$1`, patient.ID) })
	booking, pay := createPendingBookingAt(t, db, st, patient.ID, prof.ID, "package_session", "chat", clock.Now().AddDate(0, 0, 4))
	if _, err := st.MarkPaymentPaid(context.Background(), pay.Reference, ""); err != nil {
		t.Fatal(err)
	}
	old, err := st.CreateCarePackage(context.Background(), store.CarePackage{PatientID: patient.ID, ProfessionalID: prof.ID, Price: 100000, BookingID: &booking.ID})
	if err != nil {
		t.Fatal(err)
	}
	first, _, err := st.ActivatePendingPackage(context.Background(), patient.ID, prof.ID, booking.ID)
	if err != nil {
		t.Fatal(err)
	}
	if first.ID != old.ID {
		t.Fatal("activated wrong package")
	}
	next, err := st.CreateCarePackage(context.Background(), store.CarePackage{PatientID: patient.ID, ProfessionalID: prof.ID, Price: 100000})
	if err != nil {
		t.Fatal(err)
	}
	_, _, err = st.ActivatePendingPackage(context.Background(), patient.ID, prof.ID, booking.ID)
	if err != nil {
		t.Fatal(err)
	}
	fresh, _ := st.GetCarePackage(context.Background(), next.ID)
	if fresh.Status != "pending_payment" {
		t.Fatalf("replay consumed later purchase: %s", fresh.Status)
	}
}

func TestStatusReconciliationRejectsAmountMismatch(t *testing.T) {
	gw := &fakeStatusGateway{status: payment.GatewayStatus{Status: "settlement", GrossAmount: "1.00", TransactionID: "wrong-amount"}}
	f := newReconcileFixture(t, gw)
	booking, p := f.pendingPayment(t, 10*time.Second)
	code, result := f.statusResult(t, p.Reference)
	if code != http.StatusOK || paymentStatusOf(t, result) != "pending" {
		t.Fatalf("wrong amount marked paid: %d %+v", code, result)
	}
	if n := countSessionsForBooking(t, f.db, booking.ID); n != 0 {
		t.Fatal("wrong amount activated session")
	}
}

func TestStatusReconciliationPersistsTerminalGatewayStatus(t *testing.T) {
	for _, status := range []string{"expire", "cancel", "deny"} {
		t.Run(status, func(t *testing.T) {
			f := newReconcileFixture(t, &fakeStatusGateway{status: payment.GatewayStatus{Status: status}})
			_, p := f.pendingPayment(t, 10*time.Second)
			_, result := f.statusResult(t, p.Reference)
			if paymentStatusOf(t, result) == "pending" {
				t.Fatal("terminal gateway status remained pending")
			}
		})
	}
}

func TestCancelPendingPackageCancelsLinkedPayment(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := verifiedProfessional(t, db, st)
	booking, pay := createPendingBookingAt(t, db, st, patient.ID, prof.ID, "package_session", "chat", clock.Now().AddDate(0, 0, 4))
	pkg, err := st.CreateCarePackage(context.Background(), store.CarePackage{PatientID: patient.ID, ProfessionalID: prof.ID, Price: 100000, BookingID: &booking.ID})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = db.Exec(`DELETE FROM care_packages WHERE patient_id=$1`, patient.ID) })
	req := httptest.NewRequest("POST", "/v1/care-packages/"+pkg.ID+"/cancel", nil)
	req.SetPathValue("package_id", pkg.ID)
	rec := httptest.NewRecorder()
	newOnboardingTestServer(db).cancelPendingCarePackage(rec, req, auth.Claims{Subject: patient.ID, Role: "patient"})
	if rec.Code != 200 {
		t.Fatalf("cancel: %d %s", rec.Code, rec.Body.String())
	}
	fresh, _ := st.GetPaymentByReference(context.Background(), pay.Reference)
	b, _ := st.GetBooking(context.Background(), booking.ID)
	if fresh.Status != "cancelled" || b.Status != "cancelled" {
		t.Fatalf("cancel left payable state: payment=%s booking=%s", fresh.Status, b.Status)
	}
}

func TestQuickBookingConcurrentRetry(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := verifiedProfessional(t, db, st)
	b := store.Booking{PatientID: patient.ID, ProfessionalID: prof.ID, ServiceType: "quick_consult", SessionType: "chat", BookingDate: clock.Now().AddDate(0, 0, 5).Format("2006-01-02"), SlotTime: "12:00", DurationMinutes: 30, Price: 100000}
	var wg sync.WaitGroup
	ids := make(chan string, 4)
	errs := make(chan error, 4)
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			request := b
			if i%2 == 1 {
				request.SlotTime = "12:00:00"
			}
			created, err := st.CreateBooking(context.Background(), request)
			if err != nil {
				errs <- err
			} else {
				ids <- created.ID
			}
		}(i)
	}
	wg.Wait()
	close(ids)
	close(errs)
	for e := range errs {
		t.Fatal(e)
	}
	first := ""
	for id := range ids {
		if first == "" {
			first = id
		}
		if first != id {
			t.Fatal("retry created a duplicate one-off booking")
		}
	}
}

func TestPackageCancellationLateSettlementNeedsReconciliation(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := verifiedProfessional(t, db, st)
	booking, pay := createPendingBookingAt(t, db, st, patient.ID, prof.ID, "package_session", "chat", clock.Now().AddDate(0, 0, 4))
	pkg, err := st.CreateCarePackage(context.Background(), store.CarePackage{PatientID: patient.ID, ProfessionalID: prof.ID, Price: 100000, BookingID: &booking.ID})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = db.Exec(`DELETE FROM care_packages WHERE patient_id=$1`, patient.ID) })
	if err := st.CancelPendingCarePackage(context.Background(), pkg.ID, patient.ID); err != nil {
		t.Fatal(err)
	}
	srv := newWebhookServer(t, db, nil)
	for i := 0; i < 2; i++ {
		rec := postSettlement(t, srv, pay.Reference, "102000.00")
		if rec.Code != http.StatusOK {
			t.Fatalf("late settlement: %d %s", rec.Code, rec.Body.String())
		}
	}
	freshPackage, _ := st.GetCarePackage(context.Background(), pkg.ID)
	freshPayment, _ := st.GetPaymentByReference(context.Background(), pay.Reference)
	freshBooking, _ := st.GetBooking(context.Background(), booking.ID)
	if freshPackage.Status != "cancelled" || freshPayment.Status != "cancelled" || freshBooking.Status != "cancelled" {
		t.Fatalf("late payment revived purchase: package=%s booking=%s payment=%s", freshPackage.Status, freshBooking.Status, freshPayment.Status)
	}
	if n := countSessionsForBooking(t, db, booking.ID); n != 0 {
		t.Fatalf("late payment created %d sessions", n)
	}
	var notifications int
	if err := db.QueryRow(`SELECT count(*) FROM notifications WHERE user_id=$1 AND type=$2`, patient.ID, notifPaymentReconciliation).Scan(&notifications); err != nil || notifications != 1 {
		t.Fatalf("reconciliation notifications=%d err=%v", notifications, err)
	}
}

func TestGatewayInitializationConcurrentRetryAndFailure(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := verifiedProfessional(t, db, st)
	_, pay := createPendingBookingAt(t, db, st, patient.ID, prof.ID, "quick_consult", "chat", clock.Now().AddDate(0, 0, 5))
	_, err := st.InitializePaymentGateway(context.Background(), pay.Reference, "midtrans", func() (string, string, error) { return "", "", fmt.Errorf("gateway timeout") })
	if err == nil {
		t.Fatal("timeout was hidden")
	}
	var wg sync.WaitGroup
	var mu sync.Mutex
	calls := 0
	errs := make(chan error, 4)
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			p, e := st.InitializePaymentGateway(context.Background(), pay.Reference, "midtrans", func() (string, string, error) {
				mu.Lock()
				calls++
				mu.Unlock()
				return "snap", "https://gateway.test/pay", nil
			})
			if e != nil {
				errs <- e
			} else if p.Reference != pay.Reference || p.SnapToken != "snap" {
				errs <- fmt.Errorf("payment identity/token lost")
			}
		}()
	}
	wg.Wait()
	close(errs)
	for e := range errs {
		t.Fatal(e)
	}
	if calls != 1 {
		t.Fatalf("gateway called %d times", calls)
	}
}

func TestPackageBookingRejectsChangedIntentAndOtherOwner(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	other := createIdentityTestUser(t, db, st, "patient", nil)
	prof := verifiedProfessional(t, db, st)
	pkg, err := st.CreateCarePackage(context.Background(), store.CarePackage{PatientID: patient.ID, ProfessionalID: prof.ID, Price: 100000})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = db.Exec(`DELETE FROM care_packages WHERE patient_id=$1`, patient.ID) })
	b := store.Booking{PatientID: patient.ID, ProfessionalID: prof.ID, ServiceType: "package_session", SessionType: "chat", BookingDate: clock.Now().AddDate(0, 0, 4).Format("2006-01-02"), SlotTime: "12:00", DurationMinutes: 30, Price: 100000}
	if _, err := st.CreatePackageBooking(context.Background(), pkg.ID, b); err != nil {
		t.Fatal(err)
	}
	b.SlotTime = "13:00"
	if _, err := st.CreatePackageBooking(context.Background(), pkg.ID, b); err == nil {
		t.Fatal("changed slot reused existing payment booking")
	}
	b.PatientID = other.ID
	if _, err := st.CreatePackageBooking(context.Background(), pkg.ID, b); err == nil {
		t.Fatal("other patient acquired package")
	}
}

func TestPaymentRetryAfterSettlementReturnsSamePaidPayment(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := verifiedProfessional(t, db, st)
	booking, pay := createPendingBookingAt(t, db, st, patient.ID, prof.ID, "quick_consult", "chat", clock.Now().AddDate(0, 0, 5))
	if _, err := st.MarkPaymentPaid(context.Background(), pay.Reference, "settled"); err != nil {
		t.Fatal(err)
	}
	rec := httptest.NewRecorder()
	newOnboardingTestServer(db).createPayment(rec, httptest.NewRequest("POST", "/v1/payments", strings.NewReader(fmt.Sprintf(`{"booking_id":%q,"payment_method":"qris"}`, booking.ID))), auth.Claims{Subject: patient.ID, Role: "patient"})
	if rec.Code < 200 || rec.Code >= 300 {
		t.Fatalf("paid retry: %d %s", rec.Code, rec.Body.String())
	}
	var result struct {
		Payment store.Payment `json:"payment"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &result); err != nil {
		t.Fatal(err)
	}
	if result.Payment.Reference != pay.Reference || result.Payment.Status != "paid" {
		t.Fatalf("lost settled payment identity: %+v", result.Payment)
	}
}

func TestLegacyPaidPaymentWinsOverNewerPending(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := verifiedProfessional(t, db, st)
	booking, pay := createPendingBookingAt(t, db, st, patient.ID, prof.ID, "quick_consult", "chat", clock.Now().AddDate(0, 0, 5))
	if _, err := st.MarkPaymentPaid(context.Background(), pay.Reference, "settled"); err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`INSERT INTO payments(booking_id,payment_method,gross_amount,service_fee_amount,platform_fee_amount,net_amount,reference,status,created_at) VALUES($1,'qris',100000,2000,10000,90000,$2,'pending',now()+interval '1 second')`, booking.ID, pay.Reference+"-legacy"); err != nil {
		t.Fatal(err)
	}
	p, err := st.CreatePayment(context.Background(), store.Payment{BookingID: booking.ID, GrossAmount: 100000, ServiceFeeAmount: 2000, Reference: "must-not-create"})
	if err != nil {
		t.Fatal(err)
	}
	if p.Reference != pay.Reference || p.Status != "paid" {
		t.Fatalf("newer pending payment won over already paid one: %+v", p)
	}
}

func TestLegacyPackageActivationRejectsDifferentPrice(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := verifiedProfessional(t, db, st)
	booking, pay := createPendingBookingAt(t, db, st, patient.ID, prof.ID, "package_session", "chat", clock.Now().AddDate(0, 0, 5))
	pkg, err := st.CreateCarePackage(context.Background(), store.CarePackage{PatientID: patient.ID, ProfessionalID: prof.ID, Price: 200000})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = db.Exec(`DELETE FROM care_packages WHERE patient_id=$1`, patient.ID) })
	if _, err := st.MarkPaymentPaid(context.Background(), pay.Reference, "settled"); err != nil {
		t.Fatal(err)
	}
	if _, _, err := st.ActivatePendingPackage(context.Background(), patient.ID, prof.ID, booking.ID); err == nil {
		t.Fatal("low-value legacy booking activated a different purchase")
	}
	fresh, _ := st.GetCarePackage(context.Background(), pkg.ID)
	if fresh.Status != "pending_payment" {
		t.Fatal("legacy mismatch changed package")
	}
}

type uncertainSnapGateway struct{ refs []string }

func (g *uncertainSnapGateway) CreateTransaction(_ context.Context, reference string, _ int64, _ map[string]any) (payment.PaymentIntent, error) {
	g.refs = append(g.refs, reference)
	if len(g.refs) == 1 {
		return payment.PaymentIntent{}, fmt.Errorf("response lost after gateway accepted order")
	}
	return payment.PaymentIntent{}, fmt.Errorf("duplicate order")
}
func (g *uncertainSnapGateway) ParseWebhook([]byte, http.Header) (payment.WebhookEvent, error) {
	return payment.WebhookEvent{}, nil
}
func (g *uncertainSnapGateway) VerifySignature(payment.WebhookEvent) bool { return false }
func TestUncertainGatewayRetryRetainsReconcilablePayment(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := verifiedProfessional(t, db, st)
	booking, err := st.CreateBooking(context.Background(), store.Booking{PatientID: patient.ID, ProfessionalID: prof.ID, ServiceType: "quick_consult", SessionType: "chat", BookingDate: clock.Now().AddDate(0, 0, 5).Format("2006-01-02"), SlotTime: "12:00", DurationMinutes: 30, Price: 100000})
	if err != nil {
		t.Fatal(err)
	}
	srv := newOnboardingTestServer(db)
	srv.cfg.PaymentMode = "gateway"
	gw := &uncertainSnapGateway{}
	srv.payment = gw
	for i := 0; i < 2; i++ {
		rec := httptest.NewRecorder()
		srv.createPayment(rec, httptest.NewRequest("POST", "/v1/payments", strings.NewReader(fmt.Sprintf(`{"booking_id":%q,"payment_method":"qris"}`, booking.ID))), auth.Claims{Subject: patient.ID, Role: "patient"})
		if rec.Code < 200 || rec.Code >= 300 {
			t.Fatalf("lost payment identity on uncertain gateway: %d %s", rec.Code, rec.Body.String())
		}
		var result struct {
			Payment store.Payment `json:"payment"`
		}
		_ = json.Unmarshal(rec.Body.Bytes(), &result)
		if result.Payment.Gateway != "midtrans" || result.Payment.Status != "pending" || result.Payment.Reference == "" {
			t.Fatalf("unreconcilable payment: %+v", result.Payment)
		}
	}
	if len(gw.refs) != 2 || gw.refs[0] != gw.refs[1] {
		t.Fatalf("created another order after uncertainty: %v", gw.refs)
	}
	var n int
	if err := db.QueryRow(`SELECT count(*) FROM payments WHERE booking_id=$1`, booking.ID).Scan(&n); err != nil || n != 1 {
		t.Fatalf("payment count=%d err=%v", n, err)
	}
}
