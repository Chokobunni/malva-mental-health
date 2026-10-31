package server

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"malva/backend/internal/clock"
	"malva/backend/internal/payment"
	"malva/backend/internal/store"
)

// ============================================================
// WEBHOOK PEMBAYARAN — TEMUAN QA (task #11)
//
// Berkas ini mengunci perilaku webhook yang ditemukan saat audit independen.
// Dua celah yang DULU ditulis sebagai karakterisasi (lulus terhadap perilaku
// lama) kini SUDAH DITUTUP (2026-07-10) dan test-nya mengunci perilaku BARU:
//
// (a) gross_amount dari payload kini DIBANDINGKAN dengan
//     payments.gross_amount + service_fee_amount milik kita. Bila tidak cocok,
//     payment TIDAK ditandai lunas, sesi TIDAK dibuat, event ditandai
//     'rejected', dan handler membalas 200 {"status":"mismatch"} (uang sudah
//     masuk; retry gateway tidak mengubah nominal -> rekonsiliasi manual).
// (c) Settlement yang di-replay setelah aktivasi gagal kini MENJALANKAN ulang
//     aktivasi (idempoten) sehingga sesi benar-benar dibuat dan event ditandai
//     'processed' — bukan lagi berhenti tanpa sesi.
// ============================================================

// postPaymentNotification mengirim notifikasi Midtrans generik dengan
// signature SHA-512 yang SAH (dihitung dari webhookTestServerKey), supaya
// yang diuji adalah perilaku handler, bukan penolakan signature.
func postPaymentNotification(t *testing.T, srv *Server, reference, gross, txStatus, statusCode, fraudStatus string) *httptest.ResponseRecorder {
	t.Helper()
	evt := map[string]string{
		"order_id":           reference,
		"status_code":        statusCode,
		"gross_amount":       gross,
		"transaction_status": txStatus,
		"transaction_id":     "txn-" + reference,
		"fraud_status":       fraudStatus,
		"signature_key":      payment.MidtransSignature(reference, statusCode, gross, webhookTestServerKey),
	}
	body, err := json.Marshal(evt)
	if err != nil {
		t.Fatalf("marshal webhook: %v", err)
	}
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/webhooks/payment", bytes.NewReader(body))
	srv.paymentWebhook(rec, req)
	return rec
}

// ---- (a) GROSS AMOUNT DICOCOKKAN (celah DITUTUP) ---------------------

// TestPaymentWebhookRejectsGrossAmountMismatch membuktikan bahwa settlement
// dengan gross_amount JAUH LEBIH KECIL daripada tagihan kita TIDAK lagi
// menandai payment LUNAS dan TIDAK membuat sesi.
//
// Kenapa dulu berbahaya: signature Midtrans mengikat gross_amount pada server
// key, sehingga penyerang tanpa server key tidak bisa memalsukan payload.
// Namun bila nominal transaksi di sisi Midtrans berbeda dari tagihan kita
// (harga diubah setelah token dibuat, salah konfigurasi item_details, atau
// transaksi Rp1.000 dibuat manual lewat dashboard untuk order_id yang
// ditebak), dulu pasien mendapat sesi penuh meski membayar jauh lebih sedikit.
//
// Perilaku baru (2026-07-10): bila parseGrossAmount(evt.GrossAmount) !=
// payments.gross_amount + service_fee_amount, handler membalas 200
// {"status":"mismatch"}, payment tetap 'pending', tidak ada sesi, dan event
// ditandai 'rejected' untuk rekonsiliasi manual. Balasan 200 (bukan 5xx)
// karena uang sudah masuk dan retry gateway tidak akan mengubah nominal.
func TestPaymentWebhookRejectsGrossAmountMismatch(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	srv := newWebhookServer(t, db, nil)
	ctx := context.Background()

	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      fmt.Sprint("STR-GA-", time.Now().UnixNano()),
		SIPNumber:      fmt.Sprint("SIP-GA-", time.Now().UnixNano()),
	})
	// Fixture: harga booking 100000 + service fee 2000 => tagihan 102000.
	start := clock.Now().In(wibLoc).AddDate(0, 0, 3)
	booking, pay := createPendingBookingAt(t, db, st, patient.ID, prof.ID, "quick_consult", "chat", start)
	if pay.GrossAmount != 100000 || pay.ServiceFeeAmount != 2000 {
		t.Fatalf("prasyarat fixture berubah: gross=%d service_fee=%d", pay.GrossAmount, pay.ServiceFeeAmount)
	}

	// Notifikasi sah (signature benar) tetapi nominalnya Rp1.000.
	rec := postPaymentNotification(t, srv, pay.Reference, "1000.00", "settlement", "200", "accept")
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, mau 200: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), `"status":"mismatch"`) {
		t.Fatalf("respons = %s, mau memuat status mismatch", rec.Body.String())
	}

	// Payment TIDAK boleh ditandai lunas.
	status, err := st.PaymentStatusByReference(ctx, pay.Reference)
	if err != nil {
		t.Fatalf("baca status: %v", err)
	}
	if status != "pending" {
		t.Fatalf("payment berubah menjadi %q, mau tetap \"pending\"", status)
	}
	// Tidak boleh ada sesi.
	if _, serr := st.GetCareSessionByBookingID(ctx, booking.ID); !errors.Is(serr, sql.ErrNoRows) {
		t.Fatalf("sesi dibuat padahal nominal tidak cocok: err = %v", serr)
	}
	// Event ditandai 'rejected' agar terlihat di audit/rekonsiliasi.
	evtStatus, found, eerr := st.PaymentEventStatus(ctx, "midtrans", pay.Reference, "settlement")
	if eerr != nil || !found {
		t.Fatalf("event tidak tercatat: found=%v err=%v", found, eerr)
	}
	if evtStatus != "rejected" {
		t.Fatalf("status event = %q, mau \"rejected\"", evtStatus)
	}
}

// ---- (c) REPLAY EVENT BERTIPE LAIN SETELAH PAID ----------------------

// TestPaymentWebhookDowngradeEventsDoNotRevokePaid (AMAN) mengunci bahwa
// notifikasi expire/cancel/deny/pending yang tiba SETELAH settlement tidak
// menurunkan payments.status ('paid') maupun bookings.status.
//
// Ini celah yang paling mudah terlewat: event tipe lain dicatat 'ignored',
// dan karena idempotensi di-key pada (gateway, external_id, event_type),
// event expire adalah baris BARU sehingga benar-benar diproses — bukan
// di-short-circuit. Yang menyelamatkan kita adalah default-branch yang tidak
// pernah menyentuh payments. Test ini menjaga agar tetap begitu.
func TestPaymentWebhookDowngradeEventsDoNotRevokePaid(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	srv := newWebhookServer(t, db, nil)
	ctx := context.Background()

	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      fmt.Sprint("STR-DG-", time.Now().UnixNano()),
		SIPNumber:      fmt.Sprint("SIP-DG-", time.Now().UnixNano()),
	})
	start := clock.Now().In(wibLoc).AddDate(0, 0, 3)
	booking, pay := createPendingBookingAt(t, db, st, patient.ID, prof.ID, "quick_consult", "chat", start)

	if rec := postPaymentNotification(t, srv, pay.Reference, "102000.00", "settlement", "200", "accept"); rec.Code != http.StatusOK {
		t.Fatalf("settlement = %d: %s", rec.Code, rec.Body.String())
	}
	sessionBefore, err := st.GetCareSessionByBookingID(ctx, booking.ID)
	if err != nil {
		t.Fatalf("sesi setelah settlement tidak ada: %v", err)
	}

	for _, other := range []string{"expire", "cancel", "deny", "pending"} {
		rec := postPaymentNotification(t, srv, pay.Reference, "102000.00", other, "200", "accept")
		if rec.Code != http.StatusOK {
			t.Fatalf("event %q sesudah paid = %d, mau 200: %s", other, rec.Code, rec.Body.String())
		}
		ps, err := st.PaymentStatusByReference(ctx, pay.Reference)
		if err != nil {
			t.Fatalf("baca status payment: %v", err)
		}
		if ps != "paid" {
			t.Fatalf("REGRESI: event %q menurunkan payments.status menjadi %q (harus tetap \"paid\")", other, ps)
		}
		b, err := st.GetBooking(ctx, booking.ID)
		if err != nil {
			t.Fatalf("baca booking: %v", err)
		}
		if b.Status != "paid" {
			t.Fatalf("REGRESI: event %q menurunkan bookings.status menjadi %q (harus tetap \"paid\")", other, b.Status)
		}
		// Sesi yang sudah dibuat tidak boleh dihapus/diubah diam-diam.
		sess, serr := st.GetCareSessionByBookingID(ctx, booking.ID)
		if serr != nil {
			t.Fatalf("REGRESI: event %q menghilangkan sesi (%v)", other, serr)
		}
		if sess.ID != sessionBefore.ID || sess.Status != sessionBefore.Status {
			t.Fatalf("REGRESI: event %q mengubah sesi: id %q->%q status %q->%q",
				other, sessionBefore.ID, sess.ID, sessionBefore.Status, sess.Status)
		}
		// Event tipe lain dicatat 'ignored' (bukan processed/received).
		evtStatus, found, eerr := st.PaymentEventStatus(ctx, "midtrans", pay.Reference, other)
		if eerr != nil || !found {
			t.Fatalf("event %q tidak tercatat: found=%v err=%v", other, found, eerr)
		}
		if evtStatus != "ignored" {
			t.Errorf("status event %q = %q, mau \"ignored\"", other, evtStatus)
		}
	}
}

// TestPaymentWebhookSettlementReplayCreatesSession (celah (c) DITUTUP)
// mengunci jalur retry gateway setelah aktivasi gagal.
//
// Alur yang diuji adalah state NYATA setelah settlement #1 membalas 5xx:
// MarkPaymentPaid sudah commit (payments='paid', bookings='paid'), tetapi
// activatePaidBooking gagal sehingga payment_events tetap 'received' dan
// TIDAK ada care_session. Gateway lalu mengirim ulang notifikasi yang SAMA.
//
// Perilaku baru (2026-07-10): cabang "payment sudah paid" kini memanggil
// activatePaidBooking untuk payment tersebut. Aktivasi idempoten (dijaga
// GetCareSessionByBookingID), jadi sesi dibuat tepat sekali dan event ditandai
// 'processed'. Bila aktivasi gagal, handler balas 5xx dan JANGAN menandai
// 'processed' agar gateway mengulang.
func TestPaymentWebhookSettlementReplayCreatesSession(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	srv := newWebhookServer(t, db, nil)
	ctx := context.Background()

	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      fmt.Sprint("STR-RT-", time.Now().UnixNano()),
		SIPNumber:      fmt.Sprint("SIP-RT-", time.Now().UnixNano()),
	})
	start := clock.Now().In(wibLoc).AddDate(0, 0, 3)
	booking, pay := createPendingBookingAt(t, db, st, patient.ID, prof.ID, "quick_consult", "chat", start)
	const gross = "102000.00"

	// State pasca-5xx: uang tertandai lunas, aktivasi belum jalan.
	if _, err := db.ExecContext(ctx, `UPDATE payments SET status='paid', paid_at=now() WHERE id=$1`, pay.ID); err != nil {
		t.Fatalf("tandai payment paid: %v", err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE bookings SET status='paid' WHERE id=$1`, booking.ID); err != nil {
		t.Fatalf("tandai booking paid: %v", err)
	}
	if _, err := st.RecordPaymentEvent(ctx, store.PaymentEvent{
		Gateway: "midtrans", ExternalID: pay.Reference, EventType: "settlement",
		Signature:   payment.MidtransSignature(pay.Reference, "200", gross, webhookTestServerKey),
		GrossAmount: 102000, Status: "received",
	}); err != nil {
		t.Fatalf("catat event 'received': %v", err)
	}
	if _, serr := st.GetCareSessionByBookingID(ctx, booking.ID); !errors.Is(serr, sql.ErrNoRows) {
		t.Fatalf("prasyarat: seharusnya belum ada sesi, dapat err = %v", serr)
	}

	// Retry gateway.
	rec := postPaymentNotification(t, srv, pay.Reference, gross, "settlement", "200", "accept")
	if rec.Code != http.StatusOK {
		t.Fatalf("retry = %d, mau 200: %s", rec.Code, rec.Body.String())
	}

	// Sesi HARUS kini ada — pembayaran lunas tidak boleh berakhir tanpa sesi.
	if _, serr := st.GetCareSessionByBookingID(ctx, booking.ID); serr != nil {
		t.Fatalf("sesi TIDAK dibuat setelah replay (celah (c) kembali): %v", serr)
	}
	// Event ditandai 'processed' karena aktivasi berhasil.
	evtStatus, found, err := st.PaymentEventStatus(ctx, "midtrans", pay.Reference, "settlement")
	if err != nil || !found {
		t.Fatalf("event tidak tercatat: found=%v err=%v", found, err)
	}
	if evtStatus != "processed" {
		t.Fatalf("status event = %q, mau \"processed\"", evtStatus)
	}
}

// TestPaymentWebhookUnknownOrderIDCreatesNoGhostData (AMAN) memastikan
// order_id yang tidak pernah kita terbitkan TIDAK membuat baris payments,
// bookings, atau care_sessions. Hanya payment_events yang dicatat, sebagai
// jejak audit untuk rekonsiliasi.
func TestPaymentWebhookUnknownOrderIDCreatesNoGhostData(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	srv := newWebhookServer(t, db, nil)
	ctx := context.Background()
	ref := fmt.Sprintf("REF-GHOST-%d", time.Now().UnixNano())
	t.Cleanup(func() {
		c, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		_, _ = db.ExecContext(c, `DELETE FROM payment_events WHERE external_id = $1`, ref)
	})

	count := func(table string) int {
		var n int
		if err := db.QueryRowContext(ctx, `SELECT count(*) FROM `+table).Scan(&n); err != nil {
			t.Fatalf("hitung %s: %v", table, err)
		}
		return n
	}
	payBefore, bookBefore, sessBefore := count("payments"), count("bookings"), count("care_sessions")

	rec := postPaymentNotification(t, srv, ref, "102000.00", "settlement", "200", "accept")
	// 5xx memang karakterisasi yang sudah ada (gateway retry). Yang diuji di
	// sini adalah TIDAK ADA data hantu.
	if rec.Code < 500 {
		t.Fatalf("order_id tak dikenal = %d, karakterisasi saat ini 5xx: %s", rec.Code, rec.Body.String())
	}
	if got := count("payments"); got != payBefore {
		t.Errorf("payments bertambah %d -> %d; order_id tak dikenal tidak boleh membuat payment", payBefore, got)
	}
	if got := count("bookings"); got != bookBefore {
		t.Errorf("bookings bertambah %d -> %d; order_id tak dikenal tidak boleh membuat booking", bookBefore, got)
	}
	if got := count("care_sessions"); got != sessBefore {
		t.Errorf("care_sessions bertambah %d -> %d; order_id tak dikenal tidak boleh membuat sesi", sessBefore, got)
	}
	var evtN int
	if err := db.QueryRowContext(ctx, `SELECT count(*) FROM payment_events WHERE external_id = $1`, ref).Scan(&evtN); err != nil {
		t.Fatalf("hitung payment_events: %v", err)
	}
	if evtN != 1 {
		t.Errorf("payment_events untuk order_id tak dikenal = %d, mau 1 (jejak audit)", evtN)
	}
	_ = st
}
