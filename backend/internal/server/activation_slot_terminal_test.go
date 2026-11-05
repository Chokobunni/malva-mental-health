package server

import (
	"context"
	"database/sql"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
	"malva/backend/internal/store"
)

// ============================================================
// PEMBAYARAN LUNAS YANG SLOTNYA TIDAK BISA DIPAKAI
//
// Dua kelas bug yang sama parahnya dengan "Google profesional bermasalah":
// uang pasien sudah masuk tetapi sesi tidak pernah ada.
//
//   C5 — slot sudah LEWAT saat webhook settle (VA/QRIS lunas beberapa menit
//        setelah jam mulai). Dulu: CreateCareSession menolak jadwal masa lalu →
//        webhook 500 → gateway mengulang selamanya.
//   C6 — slot keburu TERISI sesi lain. Dulu: booking dikembalikan ke 'pending'
//        padahal payments.status='paid', sehingga pasien bisa membayar LAGI
//        untuk sesi yang sama.
//
// Penanganan yang dikunci test di bawah: terminal (tanpa sesi, tanpa error,
// pembayaran tetap 'paid', kedua pihak dinotifikasi), dan idempoten.
// ============================================================

// pastSlotBooking membuat booking 'paid' + payment lunas, lalu menggeser
// jadwalnya ke beberapa saat yang lalu — meniru settlement yang baru masuk
// setelah jam sesi lewat.
func (f activationFixture) pastSlotBooking(t *testing.T, serviceType, sessionType string, ago time.Duration) (store.Booking, store.Payment) {
	t.Helper()
	booking, payment := f.paidBooking(t, serviceType, sessionType)
	past := clock.Now().In(wibLoc).Add(-ago)
	if _, err := f.db.ExecContext(context.Background(),
		`UPDATE bookings SET booking_date = $1, slot_time = $2 WHERE id = $3`,
		past.Format("2006-01-02"), past.Format("15:04"), booking.ID); err != nil {
		t.Fatalf("geser slot ke masa lalu: %v", err)
	}
	booking.BookingDate = past.Format("2006-01-02")
	booking.SlotTime = past.Format("15:04")
	return booking, payment
}

// assertRescheduleNotified memastikan pasien DAN profesional menerima
// notifikasi session_needs_reschedule untuk booking tersebut.
func assertRescheduleNotified(t *testing.T, st *store.Store, patientID, profID, bookingID string) {
	t.Helper()
	for _, userID := range []string{patientID, profID} {
		if n := countNotifications(t, st, userID, "session_needs_reschedule", bookingID); n != 1 {
			t.Errorf("notifikasi session_needs_reschedule untuk user %q = %d, mau 1", userID, n)
		}
	}
}

// countNotifications menghitung notifikasi bertipe kind untuk booking tertentu.
func countNotifications(t *testing.T, st *store.Store, userID, kind, bookingID string) int {
	t.Helper()
	items, err := st.ListNotifications(context.Background(), userID, 50)
	if err != nil {
		t.Fatalf("baca notifikasi %q: %v", kind, err)
	}
	n := 0
	for _, item := range items {
		if item.Type == kind && item.Data["booking_id"] == bookingID {
			n++
		}
	}
	return n
}

// TestActivatePaidBookingSlotPassedIsTerminal adalah inti C5: slot sudah lewat
// 2 jam saat webhook tiba. Aktivasi harus SELESAI tanpa error (webhook 200),
// tanpa membuat sesi, tanpa memanggil Google, dan memberi tahu kedua pihak.
func TestActivatePaidBookingSlotPassedIsTerminal(t *testing.T) {
	for _, tc := range []struct {
		name        string
		serviceType string
		sessionType string
	}{
		{"video", "quick_consult_video", "video"},
		{"chat", "quick_consult", "chat"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			db, st := openOnboardingTestStore(t)
			fake := &fakeMeetCalendar{createEventID: "evt-x", createMeetURL: "https://meet.google.com/x"}
			f := newActivationFixture(t, db, st, fake)
			linkReadyProfessional(t, st, f.prof.ID)

			booking, payment := f.pastSlotBooking(t, tc.serviceType, tc.sessionType, 2*time.Hour)

			if err := f.activate(t, payment); err != nil {
				t.Fatalf("slot lewat tidak boleh membuat webhook 5xx (uang sudah masuk): %v", err)
			}

			// Tidak ada sesi dibuat: sesi bertanggal masa lalu akan ditandai
			// no_show dan memalsukan riwayat pasien.
			if _, err := st.GetCareSessionByBookingID(context.Background(), booking.ID); !errors.Is(err, sql.ErrNoRows) {
				t.Fatalf("tidak boleh ada sesi untuk slot yang sudah lewat, dapat err = %v", err)
			}
			if fake.createCalls != 0 {
				t.Errorf("Google tidak boleh dipanggil, dapat %d panggilan", fake.createCalls)
			}

			assertRescheduleNotified(t, st, f.patient.ID, f.prof.ID, booking.ID)

			saved, err := st.GetBooking(context.Background(), booking.ID)
			if err != nil {
				t.Fatalf("baca booking: %v", err)
			}
			if saved.Status != "paid" {
				t.Errorf("status booking = %q, mau tetap \"paid\" untuk rekonsiliasi manual", saved.Status)
			}
		})
	}
}

// TestActivatePaidBookingSlotPassedIsIdempotent memastikan pengulangan webhook
// pada jalur terminal tidak membuat apa pun lagi (termasuk tidak menduplikasi
// notifikasi) dan tetap tidak error.
func TestActivatePaidBookingSlotPassedIsIdempotent(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	fake := &fakeMeetCalendar{createEventID: "evt-x", createMeetURL: "https://meet.google.com/x"}
	f := newActivationFixture(t, db, st, fake)
	linkReadyProfessional(t, st, f.prof.ID)

	booking, payment := f.pastSlotBooking(t, "quick_consult_video", "video", 2*time.Hour)

	for i := 0; i < 3; i++ {
		if err := f.activate(t, payment); err != nil {
			t.Fatalf("pengulangan webhook ke-%d tidak boleh error: %v", i+1, err)
		}
	}

	if _, err := st.GetCareSessionByBookingID(context.Background(), booking.ID); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("pengulangan webhook tidak boleh membuat sesi, dapat err = %v", err)
	}
	// Notifikasi tidak boleh berlipat tiap pengulangan.
	assertRescheduleNotified(t, st, f.patient.ID, f.prof.ID, booking.ID)
	if fake.createCalls != 0 {
		t.Errorf("Google tidak boleh dipanggil, dapat %d panggilan", fake.createCalls)
	}
}

// TestActivatePaidBookingSlotTakenDoesNotRevertToPending adalah inti C6:
// slot keburu terisi sesi lain saat pembayaran settle. Booking TIDAK boleh
// kembali ke 'pending' (itu yang membuat pasien bisa membayar dua kali), dan
// pembuatan payment baru untuk booking yang sama harus ditolak handler.
func TestActivatePaidBookingSlotTakenDoesNotRevertToPending(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	fake := &fakeMeetCalendar{createEventID: "evt-x", createMeetURL: "https://meet.google.com/x"}
	f := newActivationFixture(t, db, st, fake)
	linkReadyProfessional(t, st, f.prof.ID)

	booking, payment := f.paidBooking(t, "quick_consult_video", "video")
	start, err := parseWIBDateTime(booking.BookingDate + "T" + booking.SlotTime)
	if err != nil {
		t.Fatalf("parse slot booking: %v", err)
	}

	// Sesi lain sudah menempati slot itu (mis. profesional menjadwalkan manual,
	// atau pasien lain memenangkan balapan).
	other := createIdentityTestUser(t, db, st, "patient", nil)
	t.Cleanup(func() {
		cctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		_, _ = db.ExecContext(cctx, `DELETE FROM care_sessions WHERE patient_id = $1`, other.ID)
	})
	if _, err := st.CreateCareSession(context.Background(), store.CareSession{
		PatientID:       other.ID,
		ProfessionalID:  f.prof.ID,
		SessionType:     "chat",
		ScheduledAt:     start,
		DurationMinutes: 30,
		Status:          "scheduled",
	}); err != nil {
		t.Fatalf("buat sesi yang menempati slot: %v", err)
	}

	if err := f.activate(t, payment); err != nil {
		t.Fatalf("slot terisi tidak boleh membuat webhook 5xx: %v", err)
	}

	if _, err := st.GetCareSessionByBookingID(context.Background(), booking.ID); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("tidak boleh ada sesi kedua di slot yang sama, dapat err = %v", err)
	}
	saved, err := st.GetBooking(context.Background(), booking.ID)
	if err != nil {
		t.Fatalf("baca booking: %v", err)
	}
	if saved.Status != "paid" {
		t.Fatalf("status booking = %q, mau tetap \"paid\" (dulu dikembalikan ke pending sehingga bisa dibayar dua kali)", saved.Status)
	}
	assertRescheduleNotified(t, st, f.patient.ID, f.prof.ID, booking.ID)

	// Bukti tidak bisa bayar dua kali: handler createPayment menolak booking
	// yang bukan 'pending'. Dengan perilaku lama (revert ke pending) request
	// ini akan membuat payment baru.
	rec := httptest.NewRecorder()
	body := `{"booking_id":"` + booking.ID + `","payment_method":"qris"}`
	req := httptest.NewRequest(http.MethodPost, "/v1/payments", strings.NewReader(body))
	f.srv.createPayment(rec, req, auth.Claims{Subject: f.patient.ID, Role: "patient"})
	if rec.Code != http.StatusCreated || !strings.Contains(rec.Body.String(), payment.Reference) || !strings.Contains(rec.Body.String(), `"status":"paid"`) {
		t.Fatalf("retry must return the existing paid payment: %d %s", rec.Code, rec.Body.String())
	}
	var count int
	if err := db.QueryRowContext(context.Background(), `SELECT count(*) FROM payments WHERE booking_id=$1`, booking.ID).Scan(&count); err != nil || count != 1 {
		t.Fatalf("retry duplicated payment: count=%d err=%v", count, err)
	}
}

// TestSlotAlreadyPassedTolerance mengunci batas toleransi 1 MENIT yang dipakai
// bersama oleh handler (slotAlreadyPassed) dan store (CreateCareSession):
// slot <= ~1 menit lalu masih boleh dibuat sesinya, di atas itu terminal.
// Batas ini paling mudah "berbeda pendapat" antara handler & store.
func TestSlotAlreadyPassedTolerance(t *testing.T) {
	now := clock.Now()
	for _, tc := range []struct {
		name string
		at   time.Time
		want bool
	}{
		{"30 detik lalu", now.Add(-30 * time.Second), false},
		{"59 detik lalu", now.Add(-59 * time.Second), false},
		{"61 detik lalu", now.Add(-61 * time.Second), true},
		{"90 detik lalu", now.Add(-90 * time.Second), true},
		{"2 menit lalu", now.Add(-2 * time.Minute), true},
		{"10 menit ke depan", now.Add(10 * time.Minute), false},
	} {
		if got := slotAlreadyPassed(tc.at); got != tc.want {
			t.Errorf("%s: slotAlreadyPassed=%v, mau %v", tc.name, got, tc.want)
		}
	}
}

// TestCreateCareSessionPastToleranceMatchesHandler membuktikan STORE memakai
// ambang yang SAMA dengan handler: now-30s diterima (dibuat sesinya), now-2m
// ditolak. Bila suatu saat keduanya berbeda, pasien bisa lolos dari cek
// handler lalu gagal di store (atau sebaliknya) → 5xx berulang.
func TestCreateCareSessionPastToleranceMatchesHandler(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      "STR-TOL-" + time.Now().Format("150405.000000000"),
		SIPNumber:      "SIP-TOL-" + time.Now().Format("150405.000000000"),
	})
	ctx := context.Background()
	t.Cleanup(func() {
		cctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		_, _ = db.ExecContext(cctx, `DELETE FROM care_sessions WHERE patient_id = $1`, patient.ID)
	})

	mk := func(at time.Time) store.CareSession {
		return store.CareSession{
			PatientID:       patient.ID,
			ProfessionalID:  prof.ID,
			SessionType:     "chat",
			ScheduledAt:     at,
			DurationMinutes: 30,
			Status:          "scheduled",
		}
	}
	// now-30s: di dalam toleransi → store menerima (sesi dibuat).
	if _, err := st.CreateCareSession(ctx, mk(clock.Now().Add(-30*time.Second))); err != nil {
		t.Fatalf("store harus menerima slot now-30s (dalam toleransi 1 menit): %v", err)
	}
	if slotAlreadyPassed(clock.Now().Add(-30 * time.Second)) {
		t.Error("handler menganggap now-30s sudah lewat padahal store menerimanya — TIDAK konsisten")
	}
	// now-2m: di luar toleransi → store menolak, handler juga menganggap lewat.
	if _, err := st.CreateCareSession(ctx, mk(clock.Now().Add(-2*time.Minute))); err == nil {
		t.Fatal("store harus menolak slot now-2m (di luar toleransi)")
	}
	if !slotAlreadyPassed(clock.Now().Add(-2 * time.Minute)) {
		t.Error("handler menganggap now-2m belum lewat padahal store menolaknya — TIDAK konsisten")
	}
}

// TestActivatePaidBookingPackageSlotPassedKeepsQuota mengunci cabang paket +
// slot lewat: paket harus tetap AKTIF dengan kuota UTUH (4 sesi, 0 terpakai),
// hanya sesi pertama yang tidak dibuat, dan kedua pihak dinotifikasi.
func TestActivatePaidBookingPackageSlotPassedKeepsQuota(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	fake := &fakeMeetCalendar{createEventID: "evt-x", createMeetURL: "https://meet.google.com/x"}
	f := newActivationFixture(t, db, st, fake)
	linkReadyProfessional(t, st, f.prof.ID)
	pkg := f.pendingPackage(t) // 4 sesi, pending_payment

	booking, payment := f.pastSlotBooking(t, "package_session", "video", 2*time.Hour)

	if err := f.activate(t, payment); err != nil {
		t.Fatalf("paket + slot lewat tidak boleh membuat webhook 5xx: %v", err)
	}
	// Tidak ada sesi pertama (slot lewat).
	if _, err := st.GetCareSessionByBookingID(context.Background(), booking.ID); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("tidak boleh ada sesi untuk slot lewat, dapat err = %v", err)
	}
	// Paket tetap aktif & kuota utuh (4 sesi, 0 terpakai).
	var status string
	var total, used int
	if err := db.QueryRowContext(context.Background(),
		`SELECT status, total_sessions,
		   (SELECT COUNT(*) FROM care_sessions WHERE package_id = care_packages.id
		     AND status IN ('scheduled','completed','no_show'))
		 FROM care_packages WHERE id = $1`, pkg.ID).Scan(&status, &total, &used); err != nil {
		t.Fatalf("baca paket: %v", err)
	}
	if status != "active" {
		t.Errorf("status paket = %q, mau \"active\" (paket tetap aktif walau sesi pertama tak dibuat)", status)
	}
	if total != 4 {
		t.Errorf("total_sessions = %d, mau 4", total)
	}
	if used != 0 {
		t.Errorf("used sessions = %d, mau 0 (kuota tidak boleh terpakai oleh sesi yang tak dibuat)", used)
	}
	assertRescheduleNotified(t, st, f.patient.ID, f.prof.ID, booking.ID)
}
