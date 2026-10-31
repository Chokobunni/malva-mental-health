package server

import (
	"errors"
	"net/http"
	"strings"

	"malva/backend/internal/auth"
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
