package server

import (
	"errors"
	"net/http"
	"strings"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/payment"
	"malva/backend/internal/store"
)

// ============================================================
// STATUS PEMBAYARAN & KONFIGURASI PEMBAYARAN (mode gateway)
//
// Latar belakang: di mode gateway (Midtrans) klien TIDAK boleh mengonfirmasi
// pembayaran sendiri (mark-paid membalas 410), dan webhook gateway bisa
// terlambat beberapa detik sampai menit. Tanpa endpoint status, aplikasi tidak
// punya cara mengetahui pembayaran sudah lunas setelah pengguna kembali dari
// halaman Midtrans.
// ============================================================

// getPaymentStatus menangani GET /v1/payments/{reference}.
//
// Hanya pasien pemilik pembayaran. Reference milik orang lain dibalas 404
// (bukan 403) agar keberadaan pembayaran orang lain tidak bisa ditebak.
//
// Bila pembayaran sudah 'paid' tetapi sesinya belum ada (webhook belum tiba),
// aktivasi dijalankan best-effort: pasien yang sudah membayar tetap menemukan
// sesinya di MyCare tanpa menunggu webhook. Idempoten — activatePaidBooking
// sudah menjaga lewat GetCareSessionByBookingID.
func (s *Server) getPaymentStatus(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	reference := strings.TrimSpace(r.PathValue("reference"))
	if reference == "" {
		writeError(w, http.StatusBadRequest, errors.New("reference is required"))
		return
	}
	if claims.Role != "patient" {
		writeError(w, http.StatusForbidden, errors.New("endpoint ini hanya untuk pasien"))
		return
	}
	payment, err := s.store.GetPaymentByReference(r.Context(), reference)
	if err != nil {
		if errors.Is(err, store.ErrPaymentNotFound) {
			writeError(w, http.StatusNotFound, errors.New("pembayaran tidak ditemukan"))
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	booking, err := s.store.GetBooking(r.Context(), payment.BookingID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if booking.PatientID != claims.Subject {
		// 404, bukan 403: jangan bocorkan keberadaan pembayaran pasien lain.
		writeError(w, http.StatusNotFound, errors.New("pembayaran tidak ditemukan"))
		return
	}
	if payment.Status == "pending" {
		// Webhook bisa telat (atau URL notifikasi belum diisi di dashboard
		// gateway). Tanya langsung ke gateway agar pasien yang SUDAH membayar
		// tidak menunggu 5 menit lalu menyerah. Best-effort: apa pun yang
		// gagal di sini tidak boleh menggagalkan respons.
		payment = s.reconcilePendingPayment(r, payment)
	}
	if payment.Status == "paid" {
		// Best-effort: kegagalan aktivasi TIDAK menggagalkan pemeriksaan status
		// (webhook tetap jalur utama dan akan mengulang sendiri). Hanya dicatat.
		if _, aerr := s.activatePaidBooking(r, payment); aerr != nil {
			if s.logger != nil {
				s.logger.Warn("aktivasi dari cek status pembayaran gagal",
					"reference", reference, "error", aerr)
			}
		}
	}
	sessionID := ""
	if cs, serr := s.store.GetCareSessionByBookingID(r.Context(), booking.ID); serr == nil {
		sessionID = cs.ID
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"payment":    payment,
		"session_id": sessionID,
	})
}

// paymentReconcileMinAge menunda pemeriksaan ke gateway beberapa detik setelah
// payment dibuat, agar tidak berlomba dengan pembuatan transaksi Snap (token
// baru saja dibuat dan transaksi mungkin belum terdaftar di gateway).
const paymentReconcileMinAge = 5 * time.Second

// reconcilePendingPayment menanyakan status transaksi langsung ke gateway
// (otoritatif) untuk pembayaran yang masih `pending` di DB.
//
// Kenapa perlu: status `paid` di DB hanya lahir dari webhook. Bila notifikasi
// gateway telat atau URL notifikasi belum dikonfigurasi, pasien yang sudah
// membayar akan terus melihat "Menunggu pembayaran" padahal uangnya masuk.
//
// Aturan aman:
//   - hanya untuk gateway yang mengimplementasikan payment.StatusFetcher;
//   - hanya untuk payment ber-gateway "midtrans" dan berumur > 5 detik;
//   - settlement/capture (fraud kosong/accept) -> tandai lunas + aktivasi;
//   - status lain (pending/expire/cancel/deny, fraud challenge) -> TIDAK
//     mengubah apa pun; webhook tetap yang menangani;
//   - semua kegagalan hanya dicatat, respons tetap memakai status DB.
//
// Idempoten: MarkPaymentPaid menolak payment yang bukan `pending`, dan
// activatePaidBooking menjaga sesi lewat GetCareSessionByBookingID.
func (s *Server) reconcilePendingPayment(r *http.Request, p store.Payment) store.Payment {
	if s.payment == nil {
		return p
	}
	fetcher, ok := s.payment.(payment.StatusFetcher)
	if !ok {
		return p
	}
	if !strings.EqualFold(strings.TrimSpace(p.Gateway), "midtrans") {
		return p
	}
	if p.CreatedAt.IsZero() || time.Since(p.CreatedAt) < paymentReconcileMinAge {
		return p
	}
	status, err := fetcher.FetchStatus(r.Context(), p.Reference)
	if err != nil {
		// Endpoint ini dipanggil klien tiap 3 detik: jangan pernah jadi sumber
		// error. Cukup dicatat.
		if s.logger != nil {
			s.logger.Warn("cek status ke gateway gagal; memakai status DB",
				"reference", p.Reference, "error", err)
		}
		return p
	}
	switch strings.ToLower(strings.TrimSpace(status.Status)) {
	case "settlement", "capture":
		// fraud_status kosong atau "accept" = sah. challenge/deny tidak boleh
		// menandai lunas.
		if fs := strings.ToLower(strings.TrimSpace(status.FraudStatus)); fs != "" && fs != "accept" {
			return p
		}
		if parseGrossAmount(status.GrossAmount) != p.GrossAmount+p.ServiceFeeAmount {
			return p
		}
	case "expire", "cancel", "deny":
		terminal := map[string]string{"expire": "expired", "cancel": "cancelled", "deny": "deny"}[strings.ToLower(strings.TrimSpace(status.Status))]
		if err := s.store.SetPaymentTerminal(r.Context(), p.Reference, terminal); err != nil {
			return p
		}
		fresh, err := s.store.GetPaymentByReference(r.Context(), p.Reference)
		if err != nil {
			return p
		}
		return fresh
	default:
		// pending / expire / cancel / deny: biarkan webhook yang memutuskan.
		return p
	}
	if _, err := s.store.MarkPaymentPaid(r.Context(), p.Reference, status.TransactionID); err != nil {
		if s.logger != nil {
			s.logger.Warn("tandai lunas dari cek status gateway gagal",
				"reference", p.Reference, "error", err)
		}
		return p
	}
	// MarkPaymentPaid tidak mengembalikan seluruh kolom: baca ulang agar
	// respons memuat status/gateway/redirect_url yang sebenarnya.
	fresh, err := s.store.GetPaymentByReference(r.Context(), p.Reference)
	if err != nil {
		if s.logger != nil {
			s.logger.Warn("baca ulang payment setelah cek status gagal",
				"reference", p.Reference, "error", err)
		}
		return p
	}
	if _, aerr := s.activatePaidBooking(r, fresh); aerr != nil && s.logger != nil {
		s.logger.Warn("aktivasi setelah cek status gateway gagal",
			"reference", p.Reference, "error", aerr)
	}
	return fresh
}

// paymentConfigHandler menangani GET /v1/config/payment (publik).
//
// Klien memakainya untuk menyembunyikan pilihan metode pembayaran palsu
// (simulasi) dan menampilkan "metode dipilih di halaman Midtrans" saat mode
// gateway aktif. TIDAK pernah menyertakan server/client key.
func (s *Server) paymentConfigHandler(w http.ResponseWriter, r *http.Request) {
	mode := strings.ToLower(strings.TrimSpace(s.cfg.PaymentMode))
	if mode == "" {
		mode = "simulation"
	}
	env := strings.ToLower(strings.TrimSpace(s.cfg.MidtransEnv))
	if env == "" {
		env = "sandbox"
	}
	writeJSON(w, http.StatusOK, map[string]string{
		"mode":     mode,
		"provider": "midtrans",
		"env":      env,
	})
}
