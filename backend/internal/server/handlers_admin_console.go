package server

import (
	"database/sql"
	"errors"
	"net/http"
	"strconv"
	"strings"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
	"malva/backend/internal/security"
	"malva/backend/internal/store"
)

// ============================================================
// KONSOL ADMIN (dashboard Flutter web)
//
// Handler tipis untuk endpoint panel admin baru: ringkasan beranda, riwayat &
// override pembayaran (Midtrans telat/galat), ledger refund, harga profesional,
// serta pengelolaan akun (reset password, cabut sesi, ban/unban). Seluruh rute
// berada di belakang s.requireAdmin (lihat Routes()).
// ============================================================

// queryInt membaca parameter query bilangan bulat dengan batas aman.
func queryInt(raw string, def, min, max int) int {
	raw = strings.TrimSpace(raw)
	if raw == "" {
		return def
	}
	n, err := strconv.Atoi(raw)
	if err != nil {
		return def
	}
	if n < min {
		return min
	}
	if n > max {
		return max
	}
	return n
}

// validDateWIB memvalidasi tanggal bisnis YYYY-MM-DD memakai zona WIB.
func validDateWIB(raw string) bool {
	if strings.TrimSpace(raw) == "" {
		return true
	}
	_, err := time.ParseInLocation("2006-01-02", strings.TrimSpace(raw), clock.Location())
	return err == nil
}

// adminOverview menangani GET /v1/admin/overview.
func (s *Server) adminOverview(w http.ResponseWriter, r *http.Request, _ auth.Claims) {
	overview, err := s.store.AdminOverview(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"overview": overview})
}

// listAdminPayments menangani GET /v1/admin/payments.
func (s *Server) listAdminPayments(w http.ResponseWriter, r *http.Request, _ auth.Claims) {
	q := r.URL.Query()
	from := strings.TrimSpace(q.Get("from"))
	to := strings.TrimSpace(q.Get("to"))
	if !validDateWIB(from) || !validDateWIB(to) {
		writeError(w, http.StatusBadRequest, errors.New("format tanggal harus YYYY-MM-DD"))
		return
	}
	status := strings.ToLower(strings.TrimSpace(q.Get("status")))
	if status != "" && !oneOf(status, "pending", "paid", "failed", "refunded", "cancelled") {
		writeError(w, http.StatusBadRequest, errors.New("status tidak dikenal"))
		return
	}
	items, total, summary, err := s.store.ListAdminPayments(r.Context(), store.AdminPaymentFilter{
		Status: status,
		Query:  trimMax(q.Get("q"), 100),
		From:   from,
		To:     to,
		Limit:  queryInt(q.Get("limit"), 50, 1, 200),
		Offset: queryInt(q.Get("offset"), 0, 0, 1<<30),
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"payments": items,
		"total":    total,
		"summary":  summary,
	})
}

// getAdminPayment menangani GET /v1/admin/payments/{payment_id}.
func (s *Server) getAdminPayment(w http.ResponseWriter, r *http.Request, _ auth.Claims) {
	paymentID := strings.TrimSpace(r.PathValue("payment_id"))
	if paymentID == "" {
		writeError(w, http.StatusBadRequest, errors.New("payment_id wajib diisi"))
		return
	}
	item, err := s.store.AdminPaymentByID(r.Context(), paymentID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, errors.New("pembayaran tidak ditemukan"))
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	// Booking opsional: pembayaran lama bisa tanpa baris booking yang terbaca.
	var booking any
	if item.BookingID != "" {
		if b, berr := s.store.GetBooking(r.Context(), item.BookingID); berr == nil {
			booking = b
		}
	}
	events, err := s.store.ListAdminPaymentEvents(r.Context(), item.ID, item.Reference)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	refunds, err := s.store.ListAdminRefundsForPayment(r.Context(), item.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"payment": item,
		"booking": booking,
		"events":  events,
		"refunds": refunds,
	})
}

type adminPaymentOverrideRequest struct {
	Status string `json:"status"`
	Reason string `json:"reason"`
}

// overrideAdminPayment menangani POST /v1/admin/payments/{payment_id}/override.
//
// Verifikasi/override manual saat webhook Midtrans telat atau galat. Transisi
// dijaga ketat di server:
//   - paid     : dari pending atau failed (aktivasi booking best-effort)
//   - failed   : hanya dari pending
//   - pending  : hanya dari failed
//   - refunded : hanya dari paid (menulis ledger care_refunds)
//
// Status tujuan yang sama dengan status saat ini = no-op (changed:false).
func (s *Server) overrideAdminPayment(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	paymentID := strings.TrimSpace(r.PathValue("payment_id"))
	if paymentID == "" {
		writeError(w, http.StatusBadRequest, errors.New("payment_id wajib diisi"))
		return
	}
	var req adminPaymentOverrideRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	target := strings.ToLower(strings.TrimSpace(req.Status))
	if !oneOf(target, "paid", "failed", "refunded", "pending") {
		writeError(w, http.StatusBadRequest, errors.New("status harus paid, failed, refunded, atau pending"))
		return
	}
	reason := trimMax(req.Reason, 500)
	if len(reason) < 3 {
		writeError(w, http.StatusBadRequest, errors.New("alasan wajib diisi (3-500 karakter)"))
		return
	}

	current, err := s.store.AdminPaymentByID(r.Context(), paymentID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, errors.New("pembayaran tidak ditemukan"))
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	// Sudah pada status tujuan: tidak ada perubahan, tidak diaudit ulang.
	if current.Status == target {
		writeJSON(w, http.StatusOK, map[string]any{"payment": current, "changed": false})
		return
	}

	switch target {
	case "paid":
		if !oneOf(current.Status, "pending", "failed") {
			writeError(w, http.StatusBadRequest,
				errors.New("hanya pembayaran pending atau gagal yang bisa ditandai lunas"))
			return
		}
		var updated store.Payment
		if current.Status == "pending" {
			// Jalur kanonik (sama dengan webhook) agar semantik tidak berubah.
			updated, err = s.store.MarkPaymentPaid(r.Context(), current.Reference, "admin:"+claims.Subject)
		} else {
			updated, err = s.store.AdminMarkFailedPaymentPaid(r.Context(), paymentID)
		}
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		// Aktivasi best-effort: kegagalan TIDAK membatalkan status lunas (sama
		// seperti markPaymentPaid); cukup dicatat.
		if _, aerr := s.activatePaidBooking(r, updated); aerr != nil && s.logger != nil {
			s.logger.Warn("aktivasi setelah override lunas admin gagal",
				"payment", paymentID, "error", aerr)
		}
		s.auditAdminAction(r, claims.Subject, "admin.payment.override", "payments", paymentID,
			map[string]any{"from": current.Status, "to": target, "reason": reason})

	case "failed":
		if current.Status != "pending" {
			writeError(w, http.StatusBadRequest,
				errors.New("hanya pembayaran pending yang bisa ditandai gagal"))
			return
		}
		ok, err := s.store.AdminSetPaymentStatus(r.Context(), paymentID, "pending", "failed")
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		if !ok {
			s.writeAdminUnchanged(w, r, paymentID)
			return
		}
		s.auditAdminAction(r, claims.Subject, "admin.payment.override", "payments", paymentID,
			map[string]any{"from": current.Status, "to": target, "reason": reason})

	case "pending":
		if current.Status != "failed" {
			writeError(w, http.StatusBadRequest,
				errors.New("hanya pembayaran gagal yang bisa dikembalikan ke pending"))
			return
		}
		ok, err := s.store.AdminSetPaymentStatus(r.Context(), paymentID, "failed", "pending")
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		if !ok {
			s.writeAdminUnchanged(w, r, paymentID)
			return
		}
		s.auditAdminAction(r, claims.Subject, "admin.payment.override", "payments", paymentID,
			map[string]any{"from": current.Status, "to": target, "reason": reason})

	case "refunded":
		if current.Status != "paid" {
			writeError(w, http.StatusBadRequest,
				errors.New("hanya pembayaran lunas yang bisa direfund"))
			return
		}
		changed, ledger, err := s.store.AdminRefundPayment(r.Context(), paymentID, reason, claims.Subject)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		if !changed {
			s.writeAdminUnchanged(w, r, paymentID)
			return
		}
		if !ledger && s.logger != nil {
			s.logger.Warn("ledger refund tidak tercatat (tabel care_refunds/booking tidak lengkap); status refunded tetap disimpan",
				"payment", paymentID)
		}
		s.auditAdminAction(r, claims.Subject, "admin.payment.refund", "payments", paymentID,
			map[string]any{"from": current.Status, "to": target, "reason": reason, "ledger": ledger})
	}

	fresh, err := s.store.AdminPaymentByID(r.Context(), paymentID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"payment": fresh, "changed": true})
}

// writeAdminUnchanged membalas 200 dengan pembayaran terkini (changed:false),
// dipakai saat transisi kalah balapan sehingga tidak ada baris yang berubah.
func (s *Server) writeAdminUnchanged(w http.ResponseWriter, r *http.Request, paymentID string) {
	fresh, err := s.store.AdminPaymentByID(r.Context(), paymentID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"payment": fresh, "changed": false})
}

// auditAdminAction mencatat aksi admin. Best-effort: kegagalan audit tidak
// menggagalkan aksi yang sudah berhasil (hanya dicatat).
func (s *Server) auditAdminAction(r *http.Request, actorID, action, entityType, entityID string, metadata map[string]any) {
	if err := s.store.AddAuditLog(r.Context(), actorID, "", action, entityType, entityID, metadata); err != nil && s.logger != nil {
		s.logger.Warn("gagal mencatat audit admin", "action", action, "entity", entityID, "error", err)
	}
}

// listAdminPricing menangani GET /v1/admin/pricing.
func (s *Server) listAdminPricing(w http.ResponseWriter, r *http.Request, _ auth.Claims) {
	items, err := s.store.ListAdminPricing(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"items": items})
}

// maxAdminPrice batas atas harga layanan yang boleh diatur admin.
const maxAdminPrice = 100_000_000

type adminPricingRequest struct {
	QuickChatPrice  *int64 `json:"quick_chat_price"`
	QuickVideoPrice *int64 `json:"quick_video_price"`
	PackagePrice    *int64 `json:"package_price"`
}

// updateAdminPricing menangani PUT /v1/admin/pricing/{professional_id}.
func (s *Server) updateAdminPricing(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	professionalID := strings.TrimSpace(r.PathValue("professional_id"))
	if professionalID == "" {
		writeError(w, http.StatusBadRequest, errors.New("professional_id wajib diisi"))
		return
	}
	var req adminPricingRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	for _, v := range []*int64{req.QuickChatPrice, req.QuickVideoPrice, req.PackagePrice} {
		if v != nil && (*v < 0 || *v > maxAdminPrice) {
			writeError(w, http.StatusBadRequest, errors.New("harga harus antara 0 dan 100.000.000"))
			return
		}
	}
	user, err := s.store.GetUserByID(r.Context(), professionalID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, errors.New("pengguna tidak ditemukan"))
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if user.Role != "professional" {
		writeError(w, http.StatusBadRequest, errors.New("akun ini bukan profesional"))
		return
	}
	current, err := s.store.GetProfessionalPricing(r.Context(), professionalID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if req.QuickChatPrice != nil {
		current.QuickChatPrice = *req.QuickChatPrice
	}
	if req.QuickVideoPrice != nil {
		current.QuickVideoPrice = *req.QuickVideoPrice
	}
	if req.PackagePrice != nil {
		current.PackagePrice = *req.PackagePrice
	}
	current.ProfessionalID = professionalID
	if _, err := s.store.UpsertProfessionalPricing(r.Context(), current); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	s.auditAdminAction(r, claims.Subject, "admin.pricing.update", "professional_pricing", professionalID,
		map[string]any{
			"quick_chat_price":  current.QuickChatPrice,
			"quick_video_price": current.QuickVideoPrice,
			"package_price":     current.PackagePrice,
		})
	item, err := s.store.AdminPricingByProfessional(r.Context(), professionalID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"pricing": item})
}

// listAdminRefunds menangani GET /v1/admin/refunds.
func (s *Server) listAdminRefunds(w http.ResponseWriter, r *http.Request, _ auth.Claims) {
	q := r.URL.Query()
	status := strings.ToLower(strings.TrimSpace(q.Get("status")))
	if status != "" && !oneOf(status, "recorded", "processing", "processed", "paid", "failed", "cancelled") {
		writeError(w, http.StatusBadRequest, errors.New("status refund tidak dikenal"))
		return
	}
	refunds, total, err := s.store.ListAdminRefunds(r.Context(), status,
		queryInt(q.Get("limit"), 50, 1, 200), queryInt(q.Get("offset"), 0, 0, 1<<30))
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"refunds": refunds, "total": total})
}

type adminResetPasswordRequest struct {
	NewPassword string `json:"new_password"`
}

// resetAdminUserPassword menangani POST /v1/admin/users/{user_id}/reset-password.
// Password baru divalidasi kebijakan, di-hash, disimpan, lalu SEMUA sesi aktif
// pengguna dicabut. Password TIDAK pernah dikembalikan atau dicatat di log.
func (s *Server) resetAdminUserPassword(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	userID := strings.TrimSpace(r.PathValue("user_id"))
	if userID == "" {
		writeError(w, http.StatusBadRequest, errors.New("user_id wajib diisi"))
		return
	}
	var req adminResetPasswordRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	user, err := s.store.GetUserByID(r.Context(), userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, errors.New("pengguna tidak ditemukan"))
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if err := security.ValidatePassword(req.NewPassword, user.Email); err != nil {
		writeError(w, http.StatusBadRequest, errors.New(security.IndonesianMessage(err)))
		return
	}
	hash, err := auth.HashPassword(req.NewPassword)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if err := s.store.SetUserPasswordAdmin(r.Context(), userID, hash); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, errors.New("pengguna tidak ditemukan"))
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	revoked, rerr := s.store.RevokeAllSessionsForUser(r.Context(), userID)
	if rerr != nil && s.logger != nil {
		s.logger.Warn("gagal mencabut sesi setelah reset password", "user", userID, "error", rerr)
	}
	s.auditAdminAction(r, claims.Subject, "admin.user.password_reset", "users", userID,
		map[string]any{"revoked_sessions": revoked})
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// revokeAdminUserSessions menangani POST /v1/admin/users/{user_id}/revoke-sessions.
func (s *Server) revokeAdminUserSessions(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	userID := strings.TrimSpace(r.PathValue("user_id"))
	if userID == "" {
		writeError(w, http.StatusBadRequest, errors.New("user_id wajib diisi"))
		return
	}
	revoked, err := s.store.RevokeAllSessionsForUser(r.Context(), userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	s.auditAdminAction(r, claims.Subject, "admin.user.revoke_sessions", "users", userID,
		map[string]any{"revoked_sessions": revoked})
	writeJSON(w, http.StatusOK, map[string]any{"status": "ok", "revoked": revoked})
}
