package server

import (
	"context"
	"database/sql"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"malva/backend/internal/clock"
	googlecal "malva/backend/internal/google"
	"malva/backend/internal/store"
)

// ============================================================
// AKTIVASI PEMBAYARAN SAAT GOOGLE PROFESIONAL BERMASALAH
//
// Aturan bisnis yang dikunci: pasien yang SUDAH MEMBAYAR tidak boleh
// kehilangan sesinya hanya karena akun Google profesional bermasalah.
// Webhook pembayaran yang gagal (5xx) akan dikirim ulang terus-menerus,
// sementara uang pasien sudah masuk dan paket tetap pending_payment.
//
// Perbaikan menyamakan semantik degradasi dengan jalur penjadwalan
// (prepareScheduledMeet): bila link belum bisa dibuat, sesi tetap dibuat
// "menunggu link" (AllowPendingMeet) dan link menyusul.
//
// PERBEDAAN yang disengaja: di jalur berbayar ini ErrMeetUnavailable
// (server belum dikonfigurasi Google) JUGA tidak menggagalkan aktivasi —
// uang sudah masuk, kehilangan sesi jauh lebih buruk daripada sesi tanpa
// link. Ini berbeda dari scheduleSession yang membalas 501 karena pasien
// belum membayar.
// ============================================================

// activationFixture menyiapkan pasien + profesional (+ sesi kalender fake)
// dan helper untuk membuat booking berstatus 'paid' beserta payment-nya.
type activationFixture struct {
	srv     *Server
	db      *sql.DB
	st      *store.Store
	patient store.User
	prof    store.User
	fake    *fakeMeetCalendar
}

func newActivationFixture(t *testing.T, db *sql.DB, st *store.Store, cal meetCalendar) activationFixture {
	t.Helper()
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      "STR-ACT-" + fmt.Sprint(time.Now().UnixNano()),
		SIPNumber:      "SIP-ACT-" + fmt.Sprint(time.Now().UnixNano()),
	})

	// Bersihkan tabel tanpa FK ke users SEBELUM user dihapus. bookings &
	// payments ikut terhapus via ON DELETE CASCADE dari users, tetapi
	// care_sessions/care_packages hanya menyimpan uuid tanpa FK, sehingga
	// harus dihapus manual agar tidak menggantung.
	t.Cleanup(func() {
		cctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		_, _ = db.ExecContext(cctx, `DELETE FROM care_sessions WHERE patient_id = $1`, patient.ID)
		_, _ = db.ExecContext(cctx, `DELETE FROM care_packages WHERE patient_id = $1`, patient.ID)
		_, _ = db.ExecContext(cctx, `DELETE FROM bookings WHERE patient_id = $1`, patient.ID)
	})

	srv := newOnboardingTestServer(db)
	srv.calendar = cal
	fake, _ := cal.(*fakeMeetCalendar)
	return activationFixture{srv: srv, db: db, st: st, patient: patient, prof: prof, fake: fake}
}

// paidBooking membuat booking berstatus 'paid' + payment lunas untuk satu
// slot 3 hari ke depan (aman dari aturan masa depan CreateCareSession).
func (f activationFixture) paidBooking(t *testing.T, serviceType, sessionType string, prices ...int64) (store.Booking, store.Payment) {
	t.Helper()
	ctx := context.Background()
	start := clock.Now().In(wibLoc).AddDate(0, 0, 3)
	dateStr := start.Format("2006-01-02")
	slotStr := start.Format("15:04")
	price := int64(100000)
	if len(prices) > 0 {
		price = prices[0]
	}

	b, err := f.st.CreateBooking(ctx, store.Booking{
		PatientID:       f.patient.ID,
		ProfessionalID:  f.prof.ID,
		ServiceType:     serviceType,
		SessionType:     sessionType,
		BookingDate:     dateStr,
		SlotTime:        slotStr,
		DurationMinutes: 30,
		Price:           price,
	})
	if err != nil {
		t.Fatalf("buat booking: %v", err)
	}
	p, err := f.st.CreatePayment(ctx, store.Payment{
		BookingID:         b.ID,
		PaymentMethod:     "qris",
		GrossAmount:       price,
		ServiceFeeAmount:  2000,
		PlatformFeeAmount: price / 10,
		NetAmount:         price - price/10,
		Reference:         "REF-ACT-" + fmt.Sprint(time.Now().UnixNano()),
	})
	if err != nil {
		t.Fatalf("buat payment: %v", err)
	}
	if _, err := f.st.MarkPaymentPaid(ctx, p.Reference, ""); err != nil {
		t.Fatalf("tandai payment paid: %v", err)
	}
	// Status booking dibaca ulang oleh activatePaidBooking via GetBooking.
	b.Status = "paid"
	return b, p
}

// pendingPackage membuat paket pending_payment untuk pasangan ini.
func (f activationFixture) pendingPackage(t *testing.T) store.CarePackage {
	t.Helper()
	pkg, err := f.st.CreateCarePackage(context.Background(), store.CarePackage{
		PatientID:      f.patient.ID,
		ProfessionalID: f.prof.ID,
		Status:         "pending_payment",
		TotalSessions:  4,
		ValidityDays:   42,
		Price:          100000,
	})
	if err != nil {
		t.Fatalf("buat paket pending: %v", err)
	}
	return pkg
}

// activate memanggil activatePaidBooking persis seperti webhook gateway.
func (f activationFixture) activate(t *testing.T, p store.Payment) error {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/v1/payments/webhook", nil)
	_, err := f.srv.activatePaidBooking(req, p)
	return err
}

// TestActivatePackageVideoPendingOnReauth adalah inti bug: paket berbayar
// dengan sesi video, profesional SIAP tetapi Google menolak refresh token
// (ErrReauthNeeded). Aktivasi TIDAK boleh error; sesi tetap dibuat tanpa
// meeting_url dan paket teraktivasi.
func TestActivatePackageVideoPendingOnReauth(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	fake := &fakeMeetCalendar{createErr: googlecal.ErrReauthNeeded}
	f := newActivationFixture(t, db, st, fake)
	// Profesional siap agar kalender benar-benar dipanggil dan mengembalikan
	// ErrReauthNeeded (bukan sekadar "belum siap").
	linkReadyProfessional(t, st, f.prof.ID)
	pkg := f.pendingPackage(t)

	booking, payment := f.paidBooking(t, "package_session", "video")

	if err := f.activate(t, payment); err != nil {
		t.Fatalf("aktivasi paket berbayar tidak boleh gagal saat Google bermasalah: %v", err)
	}

	// Sesi harus benar-benar tersimpan: video, tanpa link.
	session, err := st.GetCareSessionByBookingID(context.Background(), booking.ID)
	if err != nil {
		t.Fatalf("sesi paket tidak tersimpan: %v", err)
	}
	if session.SessionType != "video" {
		t.Errorf("session_type = %q, mau video", session.SessionType)
	}
	if strings.TrimSpace(session.MeetingURL) != "" {
		t.Errorf("meeting_url = %q, mau kosong saat menunggu link", session.MeetingURL)
	}
	if session.PackageID == nil || *session.PackageID != pkg.ID {
		t.Errorf("session.package_id = %v, mau %q", session.PackageID, pkg.ID)
	}

	// Paket harus teraktivasi (bukan tetap pending_payment).
	activated, err := st.GetCarePackage(context.Background(), pkg.ID)
	if err != nil {
		t.Fatalf("baca paket: %v", err)
	}
	if activated.Status != "active" {
		t.Errorf("status paket = %q, mau active", activated.Status)
	}

	// Notifikasi: profesional diminta membuat link, pasien diberi tahu link
	// menyusul.
	assertMeetMissingNotified(t, st, f.prof.ID, session.ID)
}

// TestActivateQuickConsultVideoPendingOnReauth: cabang quick consult video
// harus berperilaku sama — tidak error, sesi dibuat tanpa link.
func TestActivateQuickConsultVideoPendingOnReauth(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	fake := &fakeMeetCalendar{createErr: googlecal.ErrReauthNeeded}
	f := newActivationFixture(t, db, st, fake)
	linkReadyProfessional(t, st, f.prof.ID)

	booking, payment := f.paidBooking(t, "quick_consult_video", "video")

	if err := f.activate(t, payment); err != nil {
		t.Fatalf("aktivasi quick consult berbayar tidak boleh gagal saat Google bermasalah: %v", err)
	}

	session, err := st.GetCareSessionByBookingID(context.Background(), booking.ID)
	if err != nil {
		t.Fatalf("sesi quick consult tidak tersimpan: %v", err)
	}
	if session.SessionType != "video" || strings.TrimSpace(session.MeetingURL) != "" {
		t.Errorf("sesi = %+v, mau video tanpa meeting_url", session)
	}
	assertMeetMissingNotified(t, st, f.prof.ID, session.ID)
}

// TestActivateChatSessionDoesNotTouchCalendar: sesi chat tidak butuh ruang
// pertemuan, sehingga kalender tidak boleh dipanggil sama sekali.
func TestActivateChatSessionDoesNotTouchCalendar(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	fake := &fakeMeetCalendar{createEventID: "evt-x", createMeetURL: "https://meet.google.com/x"}
	f := newActivationFixture(t, db, st, fake)

	booking, payment := f.paidBooking(t, "quick_consult", "chat")

	if err := f.activate(t, payment); err != nil {
		t.Fatalf("aktivasi sesi chat tidak boleh gagal: %v", err)
	}

	session, err := st.GetCareSessionByBookingID(context.Background(), booking.ID)
	if err != nil {
		t.Fatalf("sesi chat tidak tersimpan: %v", err)
	}
	if session.SessionType != "chat" {
		t.Errorf("session_type = %q, mau chat", session.SessionType)
	}
	if fake.createCalls != 0 {
		t.Errorf("sesi chat tidak boleh memanggil kalender, dapat %d panggilan", fake.createCalls)
	}
}

// TestActivateVideoPendingWhenServerNotConfigured membuktikan pembedaan dari
// jalur penjadwalan: server tanpa konfigurasi Google (ErrMeetUnavailable) TIDAK
// menggagalkan aktivasi berbayar. Uang pasien sudah masuk, jadi sesi tetap
// dibuat "menunggu link" dan kegagalan hanya dicatat.
func TestActivateVideoPendingWhenServerNotConfigured(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	// calendar nil -> prepareScheduledMeet mengembalikan ErrMeetUnavailable.
	f := newActivationFixture(t, db, st, nil)

	booking, payment := f.paidBooking(t, "quick_consult_video", "video")

	if err := f.activate(t, payment); err != nil {
		t.Fatalf("ErrMeetUnavailable tidak boleh menggagalkan aktivasi berbayar: %v", err)
	}

	session, err := st.GetCareSessionByBookingID(context.Background(), booking.ID)
	if err != nil {
		t.Fatalf("sesi berbayar tidak tersimpan meski server tanpa Google: %v", err)
	}
	if session.SessionType != "video" || strings.TrimSpace(session.MeetingURL) != "" {
		t.Errorf("sesi = %+v, mau video tanpa meeting_url", session)
	}
	assertMeetMissingNotified(t, st, f.prof.ID, session.ID)
}

// TestActivateVideoSucceedsWhenReady: jalur normal (Google siap) tetap
// menyimpan link Meet yang dibuat.
func TestActivateVideoSucceedsWhenReady(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	const wantURL = "https://meet.google.com/abc-defg-hij"
	fake := &fakeMeetCalendar{createEventID: "evt-ok", createMeetURL: wantURL}
	f := newActivationFixture(t, db, st, fake)
	linkReadyProfessional(t, st, f.prof.ID)

	booking, payment := f.paidBooking(t, "quick_consult_video", "video")

	if err := f.activate(t, payment); err != nil {
		t.Fatalf("aktivasi jalur siap tidak boleh error: %v", err)
	}
	session, err := st.GetCareSessionByBookingID(context.Background(), booking.ID)
	if err != nil {
		t.Fatalf("sesi tidak tersimpan: %v", err)
	}
	if session.MeetingURL != wantURL {
		t.Errorf("meeting_url = %q, mau %q", session.MeetingURL, wantURL)
	}
}

// assertMeetMissingNotified memastikan profesional menerima notifikasi
// session_meet_missing untuk sesi tertentu.
func assertMeetMissingNotified(t *testing.T, st *store.Store, profID, sessionID string) {
	t.Helper()
	items, err := st.ListNotifications(context.Background(), profID, 50)
	if err != nil {
		t.Fatalf("baca notifikasi profesional: %v", err)
	}
	for _, n := range items {
		if n.Type == "session_meet_missing" && n.Data["session_id"] == sessionID {
			return
		}
	}
	t.Errorf("profesional tidak menerima notifikasi session_meet_missing untuk sesi %q", sessionID)
}

// findNotification mengembalikan notifikasi bertipe kind milik userID.
// Dipakai test pesan: yang diuji adalah isi teks yang dibaca pengguna.
func findNotification(t *testing.T, st *store.Store, userID, kind string) store.Notification {
	t.Helper()
	items, err := st.ListNotifications(context.Background(), userID, 50)
	if err != nil {
		t.Fatalf("baca notifikasi %q: %v", kind, err)
	}
	for _, n := range items {
		if n.Type == kind {
			return n
		}
	}
	t.Fatalf("notifikasi bertipe %q untuk user %q tidak ditemukan", kind, userID)
	return store.Notification{}
}

// TestActivateVideoServerNotConfiguredDoesNotAskProfessionalToPressButton
// mengunci celah C3: saat integrasi Google di SERVER mati (ErrMeetUnavailable),
// tombol "Buat link Meet" akan membalas 501. Karena itu profesional tidak boleh
// disuruh menekannya, dan pasien tidak boleh dijanjikan link "sebelum sesi
// dimulai" — janji yang tidak bisa dipenuhi siapa pun sampai admin
// mengaktifkan integrasi. Sesi & uang tetap aman (tidak ada kegagalan).
func TestActivateVideoServerNotConfiguredDoesNotAskProfessionalToPressButton(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	f := newActivationFixture(t, db, st, nil) // calendar nil = server belum dikonfigurasi

	booking, payment := f.paidBooking(t, "quick_consult_video", "video")

	if err := f.activate(t, payment); err != nil {
		t.Fatalf("ErrMeetUnavailable tidak boleh menggagalkan aktivasi berbayar: %v", err)
	}
	session, err := st.GetCareSessionByBookingID(context.Background(), booking.ID)
	if err != nil {
		t.Fatalf("sesi berbayar tidak tersimpan: %v", err)
	}
	if session.SessionType != "video" || strings.TrimSpace(session.MeetingURL) != "" {
		t.Errorf("sesi = %+v, mau video tanpa meeting_url", session)
	}

	profNote := findNotification(t, st, f.prof.ID, "session_meet_missing")
	for _, forbidden := range []string{"Buat link Meet", "tekan"} {
		if strings.Contains(profNote.Body, forbidden) {
			t.Errorf("pesan profesional memuat %q padahal tombolnya akan 501: %q", forbidden, profNote.Body)
		}
	}
	if !strings.Contains(strings.ToLower(profNote.Body), "integrasi") {
		t.Errorf("pesan profesional harus menjelaskan integrasi server belum aktif: %q", profNote.Body)
	}

	patientNote := findNotification(t, st, f.patient.ID, "session_scheduled")
	if strings.Contains(patientNote.Body, "sebelum sesi dimulai") {
		t.Errorf("pesan pasien menjanjikan link sebelum sesi padahal integrasi server mati: %q", patientNote.Body)
	}
	// Tetap menenangkan: sesi & pembayaran tidak hangus.
	if !strings.Contains(patientNote.Body, "Sesi pada") {
		t.Errorf("pesan pasien harus tetap menyebut sesi terjadwal: %q", patientNote.Body)
	}
}

// TestActivatePackageNotifiesActualSessionCount mengunci celah C4: paket bisa
// DIGABUNG (store.ActivatePendingPackage menjumlahkan total_sessions), sehingga
// teks "Paket 4 sesi / 6 minggu" hardcoded menyesatkan. Pesan harus memakai
// jumlah sesi sebenarnya dari paket.
func TestActivatePackageNotifiesActualSessionCount(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	const wantURL = "https://meet.google.com/eig-hts-ok"
	fake := &fakeMeetCalendar{createEventID: "evt-8", createMeetURL: wantURL}
	f := newActivationFixture(t, db, st, fake)
	linkReadyProfessional(t, st, f.prof.ID)

	// Paket hasil penggabungan: 8 sesi, bukan 4.
	if _, err := st.CreateCarePackage(context.Background(), store.CarePackage{
		PatientID:      f.patient.ID,
		ProfessionalID: f.prof.ID,
		Status:         "pending_payment",
		TotalSessions:  8,
		ValidityDays:   42,
		Price:          200000,
	}); err != nil {
		t.Fatalf("buat paket 8 sesi: %v", err)
	}
	_, payment := f.paidBooking(t, "package_session", "video", 200000)

	if err := f.activate(t, payment); err != nil {
		t.Fatalf("aktivasi paket tidak boleh error: %v", err)
	}

	profNote := findNotification(t, st, f.prof.ID, "package_activated")
	if !strings.Contains(profNote.Body, "paket 8 sesi") {
		t.Errorf("pesan profesional = %q, mau menyebut \"paket 8 sesi\"", profNote.Body)
	}
	if strings.Contains(profNote.Body, "paket 4 sesi") {
		t.Errorf("pesan profesional masih memakai angka hardcoded 4: %q", profNote.Body)
	}

	patientNote := findNotification(t, st, f.patient.ID, "package_activated")
	if !strings.Contains(patientNote.Body, "Paket 8 sesi") {
		t.Errorf("pesan pasien = %q, mau menyebut \"Paket 8 sesi\"", patientNote.Body)
	}
	if strings.Contains(patientNote.Body, "Paket 4 sesi") {
		t.Errorf("pesan pasien masih memakai angka hardcoded 4: %q", patientNote.Body)
	}
}
