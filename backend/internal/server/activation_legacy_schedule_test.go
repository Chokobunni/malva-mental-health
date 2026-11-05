package server

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"malva/backend/internal/clock"
	"malva/backend/internal/store"
)

// ============================================================
// D2 — PAKET LEGACY TANPA JAM (bookings.slot_time NULLABLE)
// D3 — DEDUPE NOTIFIKASI HARUS PER PENERIMA
// ============================================================

// findBookingNotification mengembalikan notifikasi bertipe kind untuk booking
// tertentu beserta isinya (untuk memeriksa data.cause dsb).
func findBookingNotification(t *testing.T, st *store.Store, userID, kind, bookingID string) (store.Notification, bool) {
	t.Helper()
	items, err := st.ListNotifications(context.Background(), userID, 50)
	if err != nil {
		t.Fatalf("baca notifikasi %q: %v", kind, err)
	}
	for _, n := range items {
		if n.Type == kind && n.Data["booking_id"] == bookingID {
			return n, true
		}
	}
	return store.Notification{}, false
}

// TestActivatePackageLegacyNoSlotTimeIsTerminal mengunci D2: booking paket
// legacy tanpa slot_time (kolomnya NULLABLE) TIDAK boleh membuat webhook 5xx
// selamanya. Paket tetap aktif (kuota utuh), sesi pertama tidak dibuat dengan
// jam tebakan, dan kedua pihak diminta menjadwalkan.
func TestActivatePackageLegacyNoSlotTimeIsTerminal(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	fake := &fakeMeetCalendar{createEventID: "evt-x", createMeetURL: "https://meet.google.com/x"}
	f := newActivationFixture(t, db, st, fake)
	linkReadyProfessional(t, st, f.prof.ID)
	ctx := context.Background()

	pkg := f.pendingPackage(t)
	bookingDate := clock.Now().In(wibLoc).AddDate(0, 0, 3).Format("2006-01-02")
	// SlotTime kosong -> kolom slot_time menjadi NULL (warisan continuous lama).
	booking, err := st.CreateBooking(ctx, store.Booking{
		PatientID:       f.patient.ID,
		ProfessionalID:  f.prof.ID,
		ServiceType:     "package_session",
		SessionType:     "video",
		BookingDate:     bookingDate,
		SlotTime:        "",
		DurationMinutes: 30,
		Price:           100000,
	})
	if err != nil {
		t.Fatalf("buat booking paket tanpa jam: %v", err)
	}
	booking.Status = "paid"
	payment, err := st.CreatePayment(ctx, store.Payment{
		BookingID:         booking.ID,
		PaymentMethod:     "qris",
		GrossAmount:       100000,
		ServiceFeeAmount:  2000,
		PlatformFeeAmount: 10000,
		NetAmount:         90000,
		Reference:         "REF-LEGACY-" + fmt.Sprint(time.Now().UnixNano()),
	})
	if err != nil {
		t.Fatalf("buat payment: %v", err)
	}
	if _, err := st.MarkPaymentPaid(ctx, payment.Reference, ""); err != nil {
		t.Fatalf("tandai payment paid: %v", err)
	}

	req := httptest.NewRequest(http.MethodPost, "/v1/payments/webhook", nil)
	if _, err := f.srv.activatePaidBooking(req, payment); err != nil {
		t.Fatalf("jadwal legacy tidak boleh membuat webhook 5xx selamanya: %v", err)
	}

	// Paket tetap aktif & kuota utuh: pasien tidak kehilangan apa pun.
	activated, err := st.GetCarePackage(ctx, pkg.ID)
	if err != nil {
		t.Fatalf("baca paket: %v", err)
	}
	if activated.Status != "active" {
		t.Errorf("status paket = %q, mau \"active\"", activated.Status)
	}
	if activated.UsedSessions != 0 {
		t.Errorf("used_sessions = %d, mau 0 (tidak ada sesi yang dibuat)", activated.UsedSessions)
	}
	// Tidak ada sesi dengan jam tebakan.
	if _, err := st.GetCareSessionByBookingID(ctx, booking.ID); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("tidak boleh ada sesi tanpa jam, dapat err = %v", err)
	}
	if fake.createCalls != 0 {
		t.Errorf("Google tidak boleh dipanggil, dapat %d panggilan", fake.createCalls)
	}

	// Kedua pihak diminta menjadwalkan sesi pertama.
	for _, userID := range []string{f.patient.ID, f.prof.ID} {
		note, ok := findBookingNotification(t, st, userID, notifNeedsReschedule, booking.ID)
		if !ok {
			t.Fatalf("user %q tidak menerima notifikasi %s", userID, notifNeedsReschedule)
		}
		if note.Data["cause"] != slotCauseNoSchedule {
			t.Errorf("data.cause user %q = %q, mau %q", userID, note.Data["cause"], slotCauseNoSchedule)
		}
	}
}

// TestSlotUnusableNotifiesEachRecipientIndependently mengunci D3: dedupe
// notifikasi harus PER PENERIMA. Bila proses mati setelah notifikasi pasien
// terkirim tetapi sebelum notifikasi profesional, percobaan ulang harus tetap
// mengirim notifikasi profesional — dan tidak mengulang notifikasi pasien.
func TestSlotUnusableNotifiesEachRecipientIndependently(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	fake := &fakeMeetCalendar{createEventID: "evt-x", createMeetURL: "https://meet.google.com/x"}
	f := newActivationFixture(t, db, st, fake)
	linkReadyProfessional(t, st, f.prof.ID)
	ctx := context.Background()

	booking, payment := f.pastSlotBooking(t, "quick_consult", "chat", 2*time.Hour)

	if err := f.activate(t, payment); err != nil {
		t.Fatalf("aktivasi pertama tidak boleh error: %v", err)
	}
	assertRescheduleNotified(t, st, f.patient.ID, f.prof.ID, booking.ID)

	// Simulasi proses mati setelah notifikasi pasien terkirim: notifikasi
	// profesional belum sempat dibuat.
	if _, err := db.ExecContext(ctx,
		`DELETE FROM notifications
		 WHERE user_id = $1 AND type = $2 AND data->>'booking_id' = $3`,
		f.prof.ID, notifNeedsReschedule, booking.ID); err != nil {
		t.Fatalf("hapus notifikasi profesional: %v", err)
	}
	if n := countNotifications(t, st, f.prof.ID, notifNeedsReschedule, booking.ID); n != 0 {
		t.Fatalf("prasyarat gagal: notifikasi profesional masih %d", n)
	}

	// Pengulangan webhook: penerima yang belum dinotifikasi HARUS dinotifikasi.
	if err := f.activate(t, payment); err != nil {
		t.Fatalf("pengulangan tidak boleh error: %v", err)
	}
	if n := countNotifications(t, st, f.prof.ID, notifNeedsReschedule, booking.ID); n != 1 {
		t.Errorf("notifikasi profesional = %d, mau 1 (dikirim ulang untuk penerima yang terlewat)", n)
	}
	if n := countNotifications(t, st, f.patient.ID, notifNeedsReschedule, booking.ID); n != 1 {
		t.Errorf("notifikasi pasien = %d, mau 1 (tidak boleh berlipat)", n)
	}
}
