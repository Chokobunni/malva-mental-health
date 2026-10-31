package server

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"

	"malva/backend/internal/clock"
	"malva/backend/internal/store"
)

// ============================================================
// DANA MASUK UNTUK PEMBAYARAN YANG SUDAH DIBATALKAN (D1)
//
// Skenario nyata: pasien menekan "Batalkan" (booking masih pending di lokal)
// -> CancelPendingBooking menyetel payments.status='cancelled' -> VA/QRIS yang
// sudah terbuka tetap dibayar -> webhook settlement tiba. MarkPaymentPaid
// gagal (bukan 'pending') dan dulu handler membalas 5xx SELAMANYA: uang masuk,
// tidak ada yang tahu, tidak ada yang diberi tahu.
//
// Yang dikunci di sini (level HTTP, bukan helper):
//   - balasan 200 (gateway berhenti mengulang),
//   - payment_events.status='ignored',
//   - tidak ada sesi/booking yang dihidupkan kembali,
//   - pasien menerima TEPAT SATU notifikasi payment_needs_reconciliation
//     walau webhook dikirim 3x (event 'ignored' tidak menghentikan replay,
//     jadi dedupe harus berdasarkan reference).
// ============================================================

func TestPaymentWebhookCancelledPaymentIsTerminal(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	srv := newWebhookServer(t, db, nil) // chat: tidak butuh kalender
	ctx := context.Background()

	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      fmt.Sprint("STR-RC-", time.Now().UnixNano()),
		SIPNumber:      fmt.Sprint("SIP-RC-", time.Now().UnixNano()),
	})

	start := clock.Now().In(wibLoc).AddDate(0, 0, 3)
	booking, pay := createPendingBookingAt(t, db, st, patient.ID, prof.ID, "quick_consult", "chat", start)

	// Pasien membatalkan sesi lewat app: payment & booking menjadi 'cancelled',
	// tetapi transaksi VA/QRIS yang sudah terbuka tetap bisa dibayar.
	if err := st.CancelPendingBooking(ctx, booking.ID); err != nil {
		t.Fatalf("batalkan booking pending: %v", err)
	}
	if st, err := st.PaymentStatusByReference(ctx, pay.Reference); err != nil || st != "cancelled" {
		t.Fatalf("prasyarat gagal: status payment = %q (err=%v), mau \"cancelled\"", st, err)
	}

	for i := 0; i < 3; i++ {
		rec := postSettlement(t, srv, pay.Reference, "102000.00")
		if rec.Code != http.StatusOK {
			t.Fatalf("kiriman ke-%d status = %d, mau 200 (uang sudah masuk, 5xx = retry selamanya): %s",
				i+1, rec.Code, rec.Body.String())
		}
	}

	// Event dicatat 'ignored': bukan 'received' (menggantung) dan bukan
	// 'processed' (tidak ada yang selesai diproses).
	status, found, err := st.PaymentEventStatus(ctx, "midtrans", pay.Reference, "settlement")
	if err != nil || !found {
		t.Fatalf("event payment tidak tercatat: found=%v err=%v", found, err)
	}
	if status != "ignored" {
		t.Errorf("status event = %q, mau \"ignored\"", status)
	}

	// Tidak ada sesi yang dibuat untuk pembayaran yang sudah dibatalkan.
	if _, err := st.GetCareSessionByBookingID(ctx, booking.ID); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("tidak boleh ada sesi untuk pembayaran yang sudah dibatalkan, dapat err = %v", err)
	}
	// Booking TIDAK dihidupkan kembali (keputusan produk: bukan wewenang webhook).
	saved, err := st.GetBooking(ctx, booking.ID)
	if err != nil {
		t.Fatalf("baca booking: %v", err)
	}
	if saved.Status != "cancelled" {
		t.Errorf("status booking = %q, mau tetap \"cancelled\"", saved.Status)
	}

	// Notifikasi rekonsiliasi: tepat satu untuk pasien walau webhook 3x.
	if n := countNotifications(t, st, patient.ID, notifPaymentReconciliation, booking.ID); n != 1 {
		t.Errorf("notifikasi %s pasien = %d, mau 1 (dedupe berdasarkan reference)", notifPaymentReconciliation, n)
	}
	note, ok := findBookingNotification(t, st, patient.ID, notifPaymentReconciliation, booking.ID)
	if !ok {
		t.Fatalf("pasien tidak menerima notifikasi %s", notifPaymentReconciliation)
	}
	if note.Data["reference"] != pay.Reference {
		t.Errorf("data.reference = %q, mau %q", note.Data["reference"], pay.Reference)
	}
	if !strings.Contains(note.Body, "pengembalian dana") || !strings.Contains(note.Body, "jangan membayar lagi") {
		t.Errorf("pesan pasien harus menyebut pengembalian dana & larangan membayar lagi: %q", note.Body)
	}
	// Profesional bukan pihak rekonsiliasi dana ini.
	if n := countNotifications(t, st, prof.ID, notifPaymentReconciliation, booking.ID); n != 0 {
		t.Errorf("profesional tidak seharusnya menerima notifikasi rekonsiliasi, dapat %d", n)
	}
}

// TestPaymentWebhookAlreadyPaidSettlementIsProcessed200 (REGRESI D1): settlement
// untuk payment yang SUDAH 'paid' tetapi event-nya belum tercatat 'processed'
// (mis. dilunasi lewat jalur lain) HARUS diklasifikasikan 'processed' + 200,
// BUKAN masuk jalur 'ignored' rekonsiliasi. Ini memastikan D1 tidak menelan
// settlement sah sebagai "dana yatim".
func TestPaymentWebhookAlreadyPaidSettlementIsProcessed200(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	srv := newWebhookServer(t, db, nil)
	ctx := context.Background()

	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      fmt.Sprint("STR-AP-", time.Now().UnixNano()),
		SIPNumber:      fmt.Sprint("SIP-AP-", time.Now().UnixNano()),
	})
	start := clock.Now().In(wibLoc).AddDate(0, 0, 3)
	booking, pay := createPendingBookingAt(t, db, st, patient.ID, prof.ID, "quick_consult", "chat", start)

	// Payment sudah lunas (mis. lewat mark-paid admin) dan booking paid, tetapi
	// event 'settlement' ini BELUM pernah tercatat.
	if _, err := db.ExecContext(ctx, `UPDATE payments SET status = 'paid' WHERE id = $1`, pay.ID); err != nil {
		t.Fatalf("tandai payment paid: %v", err)
	}
	if _, err := db.ExecContext(ctx, `UPDATE bookings SET status = 'paid' WHERE id = $1`, booking.ID); err != nil {
		t.Fatalf("tandai booking paid: %v", err)
	}

	rec := postSettlement(t, srv, pay.Reference, "102000.00")
	if rec.Code != http.StatusOK {
		t.Fatalf("settlement untuk payment yang sudah paid = %d, mau 200: %s", rec.Code, rec.Body.String())
	}
	status, found, err := st.PaymentEventStatus(ctx, "midtrans", pay.Reference, "settlement")
	if err != nil || !found {
		t.Fatalf("event tidak tercatat: found=%v err=%v", found, err)
	}
	if status != "processed" {
		t.Errorf("status event = %q, mau \"processed\" (settlement sah, bukan 'ignored' rekonsiliasi)", status)
	}
	if n := countNotifications(t, st, patient.ID, notifPaymentReconciliation, booking.ID); n != 0 {
		t.Errorf("notifikasi rekonsiliasi = %d, mau 0 (payment sudah lunas, bukan dana yatim)", n)
	}
}

// TestPaymentWebhookUnknownReferenceStays5xx (KARAKTERISASI): settlement untuk
// order_id yang tidak pernah kita terbitkan (mis. salah konfigurasi environment
// gateway) saat ini dibalas 5xx, sehingga gateway terus mengulang. Ini SENGAJA
// didokumentasikan: payment row tidak pernah dihapus pada alur normal (batal =
// 'cancelled', bukan DELETE), jadi reference tak dikenal = kesalahan
// konfigurasi, bukan kehilangan data. Lihat catatan risiko di laporan QA.
func TestPaymentWebhookUnknownReferenceStays5xx(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	srv := newWebhookServer(t, db, nil)
	ref := fmt.Sprintf("REF-UNKNOWN-%d", time.Now().UnixNano())
	t.Cleanup(func() {
		cctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		_, _ = db.ExecContext(cctx, `DELETE FROM payment_events WHERE external_id = $1`, ref)
	})

	rec := postSettlement(t, srv, ref, "102000.00")
	if rec.Code < 500 {
		t.Fatalf("reference tak dikenal = %d, karakterisasi saat ini 5xx (gateway mengulang): %s", rec.Code, rec.Body.String())
	}
	_ = st
}
