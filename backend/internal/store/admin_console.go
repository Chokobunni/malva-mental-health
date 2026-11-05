package store

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/jackc/pgx/v5/pgconn"
)

// ============================================================
// KONSOL ADMIN (dashboard Flutter web)
//
// Lapisan data untuk panel admin baru: ringkasan beranda, riwayat &
// override pembayaran, ledger refund, harga profesional, serta pengelolaan
// akun (reset password, cabut sesi, ban/unban). Semua query memakai
// parameter terikat (parameterized). Timestamp bisnis memakai jam DB/WIB.
// ============================================================

// isUndefinedTable true bila galat berasal dari tabel yang belum ada
// (SQLSTATE 42P01). Dipakai untuk men-degrade endpoint agar tidak 500 pada DB
// lama yang belum menjalankan migrasi tabel opsional (care_refunds,
// payment_events, care_sessions).
func isUndefinedTable(err error) bool {
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) {
		return pgErr.Code == "42P01"
	}
	return false
}

// rowQuerier adalah irisan *sql.DB dan *sql.Tx yang cukup untuk cek to_regclass.
type rowQuerier interface {
	QueryRowContext(ctx context.Context, query string, args ...any) *sql.Row
}

// tableExists memeriksa keberadaan sebuah tabel via to_regclass. Dipakai
// sebelum menyisipkan ke tabel opsional agar transaksi tidak batal.
func tableExists(ctx context.Context, q rowQuerier, name string) (bool, error) {
	var reg *string
	if err := q.QueryRowContext(ctx, `SELECT to_regclass($1)::text`, name).Scan(&reg); err != nil {
		return false, err
	}
	return reg != nil, nil
}

// ------------------------------------------------------------
// Ringkasan beranda (GET /v1/admin/overview)
// ------------------------------------------------------------

type AdminOverviewUsers struct {
	Total         int64 `json:"total"`
	Patients      int64 `json:"patients"`
	Professionals int64 `json:"professionals"`
	Disabled      int64 `json:"disabled"`
}

type AdminOverviewPayments struct {
	PaidCount    int64 `json:"paid_count"`
	PendingCount int64 `json:"pending_count"`
	MonthRevenue int64 `json:"month_revenue"`
}

type AdminOverviewSessions struct {
	UpcomingToday int64 `json:"upcoming_today"`
}

type AdminOverviewCredentials struct {
	Pending int64 `json:"pending"`
}

// AdminOverview adalah payload ringkas untuk beranda konsol admin.
type AdminOverview struct {
	Users       AdminOverviewUsers       `json:"users"`
	Payments    AdminOverviewPayments    `json:"payments"`
	Sessions    AdminOverviewSessions    `json:"sessions"`
	Credentials AdminOverviewCredentials `json:"credentials"`
}

// AdminOverview menghitung metrik beranda admin. Tabel opsional (care_sessions,
// professional_credentials) yang belum ada di DB lama menghasilkan nilai 0,
// bukan galat.
func (s *Store) AdminOverview(ctx context.Context) (AdminOverview, error) {
	var ov AdminOverview
	if err := s.db.QueryRowContext(ctx, `
		SELECT COUNT(*),
		       COUNT(*) FILTER (WHERE role = 'patient'),
		       COUNT(*) FILTER (WHERE role = 'professional'),
		       COUNT(*) FILTER (WHERE disabled_at IS NOT NULL)
		FROM users
	`).Scan(&ov.Users.Total, &ov.Users.Patients, &ov.Users.Professionals, &ov.Users.Disabled); err != nil {
		return AdminOverview{}, err
	}

	// Pendapatan = SUM gross_amount pembayaran 'paid' dengan paid_at pada bulan
	// berjalan menurut WIB. Ekspresi AT TIME ZONE membuat batas bulan mengikuti
	// Asia/Jakarta walau session DB bukan WIB.
	if err := s.db.QueryRowContext(ctx, `
		SELECT COUNT(*) FILTER (WHERE status = 'paid'),
		       COUNT(*) FILTER (WHERE status = 'pending'),
		       COALESCE(SUM(gross_amount) FILTER (WHERE status = 'paid'
		           AND paid_at >= (date_trunc('month', now() AT TIME ZONE 'Asia/Jakarta') AT TIME ZONE 'Asia/Jakarta')
		           AND paid_at <  ((date_trunc('month', now() AT TIME ZONE 'Asia/Jakarta') + interval '1 month') AT TIME ZONE 'Asia/Jakarta')), 0)
		FROM payments
	`).Scan(&ov.Payments.PaidCount, &ov.Payments.PendingCount, &ov.Payments.MonthRevenue); err != nil {
		return AdminOverview{}, err
	}

	// Sesi terjadwal hari ini (WIB). Tabel bisa belum ada di DB lama.
	ov.Sessions.UpcomingToday = s.countOrZero(ctx, `
		SELECT COUNT(*) FROM care_sessions
		WHERE status = 'scheduled'
		  AND scheduled_at >= (date_trunc('day', now() AT TIME ZONE 'Asia/Jakarta') AT TIME ZONE 'Asia/Jakarta')
		  AND scheduled_at <  ((date_trunc('day', now() AT TIME ZONE 'Asia/Jakarta') + interval '1 day') AT TIME ZONE 'Asia/Jakarta')
	`)
	// Kredensial profesional menunggu verifikasi.
	ov.Credentials.Pending = s.countOrZero(ctx,
		`SELECT COUNT(*) FROM professional_credentials WHERE verification_status = 'PENDING'`)
	return ov, nil
}

// countOrZero menjalankan query COUNT dan mengembalikan 0 bila tabel belum ada.
func (s *Store) countOrZero(ctx context.Context, query string) int64 {
	var n int64
	if err := s.db.QueryRowContext(ctx, query).Scan(&n); err != nil {
		if isUndefinedTable(err) {
			return 0
		}
		return 0
	}
	return n
}

// ------------------------------------------------------------
// Riwayat pembayaran (GET /v1/admin/payments)
// ------------------------------------------------------------

// AdminPaymentItem satu baris transaksi untuk tabel admin.
type AdminPaymentItem struct {
	ID                string     `json:"id"`
	Reference         string     `json:"reference"`
	Status            string     `json:"status"`
	PaymentMethod     string     `json:"payment_method"`
	GrossAmount       int64      `json:"gross_amount"`
	ServiceFeeAmount  int64      `json:"service_fee_amount"`
	PlatformFeeAmount int64      `json:"platform_fee_amount"`
	NetAmount         int64      `json:"net_amount"`
	CreatedAt         time.Time  `json:"created_at"`
	PaidAt            *time.Time `json:"paid_at,omitempty"`
	BookingID         string     `json:"booking_id"`
	BookingStatus     string     `json:"booking_status"`
	SessionType       string     `json:"session_type"`
	BookingDate       string     `json:"booking_date"`
	SlotTime          string     `json:"slot_time"`
	PatientID         string     `json:"patient_id"`
	PatientName       string     `json:"patient_name"`
	PatientEmail      string     `json:"patient_email"`
	ProfessionalID    string     `json:"professional_id"`
	ProfessionalName  string     `json:"professional_name"`
}

// AdminPaymentSummary agregat status untuk filter yang sama (tanpa paginasi).
type AdminPaymentSummary struct {
	Pending   int64 `json:"pending"`
	Paid      int64 `json:"paid"`
	Failed    int64 `json:"failed"`
	Refunded  int64 `json:"refunded"`
	GrossPaid int64 `json:"gross_paid"`
}

// AdminPaymentFilter filter opsional daftar pembayaran admin.
type AdminPaymentFilter struct {
	Status string // pending|paid|failed|refunded (kosong = semua)
	Query  string // cocok ke reference / nama / email (ILIKE, sudah dipotong 100)
	From   string // YYYY-MM-DD (WIB) atau kosong
	To     string // YYYY-MM-DD (WIB) atau kosong
	Limit  int
	Offset int
}

// adminPaymentSelect adalah proyeksi kolom bersama untuk daftar & detail.
// COALESCE dipakai agar baris lama tanpa booking tetap tampil (LEFT JOIN).
const adminPaymentSelect = `SELECT p.id, p.reference, p.status, p.payment_method,
		p.gross_amount, p.service_fee_amount, p.platform_fee_amount, p.net_amount,
		p.created_at, p.paid_at,
		COALESCE(b.id::text, ''), COALESCE(b.status, ''), COALESCE(b.session_type, ''),
		COALESCE(b.booking_date::text, ''), COALESCE(b.slot_time::text, ''),
		COALESCE(b.patient_id::text, ''), COALESCE(pu.display_name, ''), COALESCE(pu.email, ''),
		COALESCE(b.professional_id::text, ''), COALESCE(du.display_name, '')
	FROM payments p
	LEFT JOIN bookings b ON b.id = p.booking_id
	LEFT JOIN users pu ON pu.id = b.patient_id
	LEFT JOIN users du ON du.id = b.professional_id`

func scanAdminPaymentItem(row interface{ Scan(...any) error }) (AdminPaymentItem, error) {
	var it AdminPaymentItem
	err := row.Scan(&it.ID, &it.Reference, &it.Status, &it.PaymentMethod,
		&it.GrossAmount, &it.ServiceFeeAmount, &it.PlatformFeeAmount, &it.NetAmount,
		&it.CreatedAt, &it.PaidAt,
		&it.BookingID, &it.BookingStatus, &it.SessionType,
		&it.BookingDate, &it.SlotTime,
		&it.PatientID, &it.PatientName, &it.PatientEmail,
		&it.ProfessionalID, &it.ProfessionalName)
	if err != nil {
		return AdminPaymentItem{}, err
	}
	return it, nil
}

// ListAdminPayments mengembalikan daftar pembayaran + total + ringkasan status
// memakai filter yang sama (paginasi hanya berlaku pada daftar).
func (s *Store) ListAdminPayments(ctx context.Context, f AdminPaymentFilter) ([]AdminPaymentItem, int, AdminPaymentSummary, error) {
	var where []string
	var args []any
	ph := func(v any) string {
		args = append(args, v)
		return fmt.Sprintf("$%d", len(args))
	}
	if st := strings.TrimSpace(f.Status); st != "" {
		where = append(where, "p.status = "+ph(st))
	}
	if q := strings.TrimSpace(f.Query); q != "" {
		like := "%" + q + "%"
		p := ph(like)
		where = append(where, fmt.Sprintf(
			"(p.reference ILIKE %s OR pu.display_name ILIKE %s OR pu.email ILIKE %s OR du.display_name ILIKE %s)",
			p, p, p, p))
	}
	if from := strings.TrimSpace(f.From); from != "" {
		where = append(where, "p.created_at >= ("+ph(from)+"::date) AT TIME ZONE 'Asia/Jakarta'")
	}
	if to := strings.TrimSpace(f.To); to != "" {
		where = append(where, "p.created_at < ((("+ph(to)+"::date) + interval '1 day') AT TIME ZONE 'Asia/Jakarta')")
	}
	whereClause := ""
	if len(where) > 0 {
		whereClause = " WHERE " + strings.Join(where, " AND ")
	}
	whereArgs := append([]any(nil), args...)

	var summary AdminPaymentSummary
	var total int64
	sumQ := `SELECT COUNT(*),
			COUNT(*) FILTER (WHERE p.status = 'pending'),
			COUNT(*) FILTER (WHERE p.status = 'paid'),
			COUNT(*) FILTER (WHERE p.status = 'failed'),
			COUNT(*) FILTER (WHERE p.status = 'refunded'),
			COALESCE(SUM(p.gross_amount) FILTER (WHERE p.status = 'paid'), 0)
		FROM payments p
		LEFT JOIN bookings b ON b.id = p.booking_id
		LEFT JOIN users pu ON pu.id = b.patient_id
		LEFT JOIN users du ON du.id = b.professional_id` + whereClause
	if err := s.db.QueryRowContext(ctx, sumQ, whereArgs...).Scan(
		&total, &summary.Pending, &summary.Paid, &summary.Failed, &summary.Refunded, &summary.GrossPaid); err != nil {
		return nil, 0, AdminPaymentSummary{}, err
	}

	limit := f.Limit
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	offset := f.Offset
	if offset < 0 {
		offset = 0
	}
	itemQ := adminPaymentSelect + whereClause +
		fmt.Sprintf(" ORDER BY p.created_at DESC LIMIT $%d OFFSET $%d", len(whereArgs)+1, len(whereArgs)+2)
	itemArgs := append(append([]any{}, whereArgs...), limit, offset)
	rows, err := s.db.QueryContext(ctx, itemQ, itemArgs...)
	if err != nil {
		return nil, 0, AdminPaymentSummary{}, err
	}
	defer func() { _ = rows.Close() }()
	out := make([]AdminPaymentItem, 0)
	for rows.Next() {
		it, err := scanAdminPaymentItem(rows)
		if err != nil {
			return nil, 0, AdminPaymentSummary{}, err
		}
		out = append(out, it)
	}
	if err := rows.Err(); err != nil {
		return nil, 0, AdminPaymentSummary{}, err
	}
	return out, int(total), summary, nil
}

// AdminPaymentByID membaca satu pembayaran untuk halaman detail admin.
// sql.ErrNoRows dikembalikan apa adanya agar handler membalas 404.
func (s *Store) AdminPaymentByID(ctx context.Context, paymentID string) (AdminPaymentItem, error) {
	return scanAdminPaymentItem(s.db.QueryRowContext(ctx, adminPaymentSelect+` WHERE p.id = $1`, paymentID))
}

// AdminPaymentEvent satu baris log webhook untuk detail pembayaran admin.
type AdminPaymentEvent struct {
	Gateway    string    `json:"gateway"`
	ExternalID string    `json:"external_id"`
	EventType  string    `json:"event_type"`
	Status     string    `json:"status"`
	CreatedAt  time.Time `json:"created_at"`
}

// ListAdminPaymentEvents mengembalikan event gateway sebuah pembayaran. Bila
// tabel payment_events belum ada, hasilnya array kosong (bukan galat).
func (s *Store) ListAdminPaymentEvents(ctx context.Context, paymentID, reference string) ([]AdminPaymentEvent, error) {
	out := make([]AdminPaymentEvent, 0)
	rows, err := s.db.QueryContext(ctx, `
		SELECT gateway, external_id, event_type, status, created_at
		FROM payment_events
		WHERE payment_id = $1 OR external_id = $2
		ORDER BY created_at DESC`, paymentID, reference)
	if err != nil {
		if isUndefinedTable(err) {
			return out, nil
		}
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	for rows.Next() {
		var e AdminPaymentEvent
		if err := rows.Scan(&e.Gateway, &e.ExternalID, &e.EventType, &e.Status, &e.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

// AdminRefundItem ringkasan refund untuk detail pembayaran admin.
type AdminRefundItem struct {
	ID        string    `json:"id"`
	Amount    int64     `json:"amount"`
	Kind      string    `json:"kind"`
	Status    string    `json:"status"`
	Reason    string    `json:"reason"`
	CreatedAt time.Time `json:"created_at"`
}

// adminRefundKey menyusun kunci idempotensi ledger refund dari id pembayaran.
// Deterministik sehingga override refund ganda tidak menambah baris.
func adminRefundKey(paymentID string) string {
	return "admin:payment:" + strings.TrimSpace(paymentID) + ":refund"
}

// ListAdminRefundsForPayment mengembalikan baris ledger refund milik sebuah
// pembayaran (berdasarkan kunci idempotensi deterministik). Degradasi ke array
// kosong bila tabel care_refunds belum ada.
func (s *Store) ListAdminRefundsForPayment(ctx context.Context, paymentID string) ([]AdminRefundItem, error) {
	out := make([]AdminRefundItem, 0)
	rows, err := s.db.QueryContext(ctx, `
		SELECT id, amount, kind, status, reason, created_at
		FROM care_refunds
		WHERE idempotency_key = $1
		ORDER BY created_at DESC`, adminRefundKey(paymentID))
	if err != nil {
		if isUndefinedTable(err) {
			return out, nil
		}
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	for rows.Next() {
		var it AdminRefundItem
		if err := rows.Scan(&it.ID, &it.Amount, &it.Kind, &it.Status, &it.Reason, &it.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

// ------------------------------------------------------------
// Mutasi status pembayaran (POST /v1/admin/payments/{id}/override)
// ------------------------------------------------------------

// AdminMarkFailedPaymentPaid menandai pembayaran berstatus 'failed' menjadi
// 'paid'. Dipakai jalur override admin failed->paid; jalur pending->paid tetap
// memakai MarkPaymentPaid agar semantik webhook tidak berubah. Mengembalikan
// payment lengkap; sql.ErrNoRows bila status tidak memenuhi.
func (s *Store) AdminMarkFailedPaymentPaid(ctx context.Context, paymentID string) (Payment, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Payment{}, err
	}
	defer func() { _ = tx.Rollback() }()

	var p Payment
	err = tx.QueryRowContext(ctx, `
		UPDATE payments
		SET status = 'paid', paid_at = now(),
		    external_id = COALESCE(NULLIF(external_id, ''), 'admin-override')
		WHERE id = $1 AND status = 'failed'
		RETURNING id, booking_id, payment_method, gross_amount, service_fee_amount,
		          platform_fee_amount, net_amount, reference, COALESCE(external_id, ''),
		          status, COALESCE(gateway, ''), COALESCE(snap_token, ''), COALESCE(redirect_url, ''),
		          paid_at, expires_at, created_at`, paymentID).
		Scan(&p.ID, &p.BookingID, &p.PaymentMethod, &p.GrossAmount, &p.ServiceFeeAmount,
			&p.PlatformFeeAmount, &p.NetAmount, &p.Reference, &p.ExternalID,
			&p.Status, &p.Gateway, &p.SnapToken, &p.RedirectURL,
			&p.PaidAt, &p.ExpiresAt, &p.CreatedAt)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return Payment{}, sql.ErrNoRows
		}
		return Payment{}, err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE bookings SET status = 'paid' WHERE id = $1`, p.BookingID); err != nil {
		return Payment{}, err
	}
	if err := tx.Commit(); err != nil {
		return Payment{}, err
	}
	return p, nil
}

// AdminSetPaymentStatus memindahkan status pembayaran bila status saat ini
// sama dengan fromStatus. Mengembalikan true bila baris berubah.
func (s *Store) AdminSetPaymentStatus(ctx context.Context, paymentID, fromStatus, toStatus string) (bool, error) {
	res, err := s.db.ExecContext(ctx,
		`UPDATE payments SET status = $3 WHERE id = $1 AND status = $2`,
		paymentID, fromStatus, toStatus)
	if err != nil {
		return false, err
	}
	aff, _ := res.RowsAffected()
	return aff > 0, nil
}

// AdminRefundPayment menandai pembayaran lunas sebagai 'refunded' dan mencatat
// baris ledger care_refunds dalam SATU transaksi.
//
// Kembalian:
//   - changed=false bila pembayaran tidak ada / bukan 'paid' (transisi ditolak).
//   - ledger=true bila baris care_refunds berhasil ditulis (atau sudah ada).
//   - ledger=false bila tabel care_refunds belum ada / data booking tidak
//     lengkap; status pembayaran tetap diperbarui (handler mencatat peringatan).
func (s *Store) AdminRefundPayment(ctx context.Context, paymentID, reason, actorID string) (changed bool, ledger bool, err error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return false, false, err
	}
	defer func() { _ = tx.Rollback() }()

	var gross int64
	var bookingID string
	err = tx.QueryRowContext(ctx,
		`SELECT gross_amount, booking_id FROM payments WHERE id = $1 AND status = 'paid' FOR UPDATE`,
		paymentID).Scan(&gross, &bookingID)
	if errors.Is(err, sql.ErrNoRows) {
		return false, false, nil
	}
	if err != nil {
		return false, false, err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE payments SET status = 'refunded' WHERE id = $1`, paymentID); err != nil {
		return false, false, err
	}

	// Ambil pemilik dari booking; boleh kosong bila booking warisan hilang.
	var patientID, professionalID string
	if err := tx.QueryRowContext(ctx,
		`SELECT patient_id::text, professional_id::text FROM bookings WHERE id = $1`, bookingID).
		Scan(&patientID, &professionalID); err != nil && !errors.Is(err, sql.ErrNoRows) {
		return false, false, err
	}

	hasLedger, terr := tableExists(ctx, tx, "public.care_refunds")
	if terr != nil {
		return false, false, terr
	}
	if hasLedger && strings.TrimSpace(patientID) != "" && strings.TrimSpace(professionalID) != "" {
		var createdBy any
		if strings.TrimSpace(actorID) != "" {
			createdBy = strings.TrimSpace(actorID)
		}
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO care_refunds
				(patient_id, professional_id, amount, kind, status, reason, idempotency_key, created_by)
			VALUES ($1, $2, $3, 'refund', 'paid', $4, $5, $6)
			ON CONFLICT (idempotency_key) DO NOTHING`,
			patientID, professionalID, gross, strings.TrimSpace(reason), adminRefundKey(paymentID), createdBy); err != nil {
			return false, false, err
		}
		ledger = true
	}
	if err := tx.Commit(); err != nil {
		return false, false, err
	}
	return true, ledger, nil
}

// ------------------------------------------------------------
// Harga profesional (GET/PUT /v1/admin/pricing)
// ------------------------------------------------------------

// AdminPricingItem satu baris harga layanan profesional untuk admin.
type AdminPricingItem struct {
	ProfessionalID  string     `json:"professional_id"`
	Name            string     `json:"name"`
	Email           string     `json:"email"`
	Specialization  string     `json:"specialization"`
	QuickChatPrice  int64      `json:"quick_chat_price"`
	QuickVideoPrice int64      `json:"quick_video_price"`
	PackagePrice    int64      `json:"package_price"`
	UpdatedAt       *time.Time `json:"updated_at,omitempty"`
}

const adminPricingSelect = `SELECT u.id, u.display_name, u.email,
		COALESCE(c.specialization, ''),
		COALESCE(pp.quick_chat_price, 0), COALESCE(pp.quick_video_price, 0), COALESCE(pp.package_price, 0),
		pp.updated_at
	FROM users u
	LEFT JOIN professional_pricing pp ON pp.professional_id = u.id
	LEFT JOIN professional_credentials c ON c.user_id = u.id
	WHERE u.role = 'professional'`

func scanAdminPricingItem(row interface{ Scan(...any) error }) (AdminPricingItem, error) {
	var it AdminPricingItem
	err := row.Scan(&it.ProfessionalID, &it.Name, &it.Email, &it.Specialization,
		&it.QuickChatPrice, &it.QuickVideoPrice, &it.PackagePrice, &it.UpdatedAt)
	if err != nil {
		return AdminPricingItem{}, err
	}
	return it, nil
}

// ListAdminPricing mengembalikan harga semua profesional. Profesional tanpa
// baris harga tetap muncul dengan nilai 0 (LEFT JOIN).
func (s *Store) ListAdminPricing(ctx context.Context) ([]AdminPricingItem, error) {
	rows, err := s.db.QueryContext(ctx, adminPricingSelect+` ORDER BY u.display_name`)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	out := make([]AdminPricingItem, 0)
	for rows.Next() {
		it, err := scanAdminPricingItem(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, it)
	}
	return out, rows.Err()
}

// AdminPricingByProfessional membaca satu baris harga profesional (untuk
// respons PUT). sql.ErrNoRows bila bukan profesional / tidak ditemukan.
func (s *Store) AdminPricingByProfessional(ctx context.Context, professionalID string) (AdminPricingItem, error) {
	return scanAdminPricingItem(s.db.QueryRowContext(ctx, adminPricingSelect+` AND u.id = $1`, professionalID))
}

// ------------------------------------------------------------
// Ledger refund admin (GET /v1/admin/refunds)
// ------------------------------------------------------------

// ListAdminRefunds mengembalikan seluruh baris ledger refund/kredit (admin),
// dengan filter status opsional. Degradasi ke daftar kosong bila tabel belum ada.
func (s *Store) ListAdminRefunds(ctx context.Context, status string, limit, offset int) ([]CareRefund, int, error) {
	out := make([]CareRefund, 0)
	status = strings.ToLower(strings.TrimSpace(status))
	if limit <= 0 || limit > 200 {
		limit = 50
	}
	if offset < 0 {
		offset = 0
	}
	where := ""
	var args []any
	if status != "" {
		args = append(args, status)
		where = " WHERE status = $1"
	}
	// Total dengan filter yang sama.
	countQ := "SELECT COUNT(*) FROM care_refunds" + where
	var total int64
	if err := s.db.QueryRowContext(ctx, countQ, args...).Scan(&total); err != nil {
		if isUndefinedTable(err) {
			return out, 0, nil
		}
		return nil, 0, err
	}
	listArgs := append([]any{}, args...)
	listArgs = append(listArgs, limit, offset)
	listQ := "SELECT " + careRefundColumns + " FROM care_refunds" + where +
		fmt.Sprintf(" ORDER BY created_at DESC LIMIT $%d OFFSET $%d", len(args)+1, len(args)+2)
	rows, err := s.db.QueryContext(ctx, listQ, listArgs...)
	if err != nil {
		if isUndefinedTable(err) {
			return out, int(total), nil
		}
		return nil, 0, err
	}
	defer func() { _ = rows.Close() }()
	for rows.Next() {
		r, err := scanCareRefund(rows)
		if err != nil {
			return nil, 0, err
		}
		out = append(out, r)
	}
	return out, int(total), rows.Err()
}

// ------------------------------------------------------------
// Pengelolaan akun (reset password, cabut sesi, daftar pengguna terfilter)
// ------------------------------------------------------------

// SetUserPasswordAdmin mengganti hash password TANPA memeriksa status nonaktif
// (admin berhak memulihkan akun yang sedang dibanned). Mengembalikan sql.ErrNoRows
// bila pengguna tidak ada.
func (s *Store) SetUserPasswordAdmin(ctx context.Context, userID, passwordHash string) error {
	if strings.TrimSpace(userID) == "" || strings.TrimSpace(passwordHash) == "" {
		return errors.New("user_id dan password_hash wajib diisi")
	}
	res, err := s.db.ExecContext(ctx,
		`UPDATE users SET password_hash = $2, updated_at = now() WHERE id = $1`,
		userID, passwordHash)
	if err != nil {
		return err
	}
	aff, _ := res.RowsAffected()
	if aff == 0 {
		return sql.ErrNoRows
	}
	return nil
}

// RevokeAllSessionsForUser mencabut SEMUA sesi aktif milik seorang pengguna.
// Mengembalikan jumlah sesi yang baru dicabut.
func (s *Store) RevokeAllSessionsForUser(ctx context.Context, userID string) (int64, error) {
	res, err := s.db.ExecContext(ctx, `
		UPDATE auth_sessions
		SET revoked_at = now()
		WHERE user_id = $1 AND revoked_at IS NULL AND expires_at > now()`, userID)
	if err != nil {
		return 0, err
	}
	aff, _ := res.RowsAffected()
	return aff, nil
}

// AdminUserFilter filter opsional daftar pengguna admin.
type AdminUserFilter struct {
	Query  string // nama/email ILIKE (kosong = semua)
	Role   string // patient|professional|admin (kosong = semua)
	Status string // active|disabled (kosong = semua)
	Limit  int
}

// ListAdminUsersFiltered mengembalikan pengguna sesuai filter opsional.
// Bentuk baris (AdminUser) sama dengan ListUsers agar respons klien tidak berubah.
func (s *Store) ListAdminUsersFiltered(ctx context.Context, f AdminUserFilter) ([]AdminUser, error) {
	limit := f.Limit
	if limit <= 0 || limit > 500 {
		limit = 200
	}
	q := strings.TrimSpace(f.Query)
	role := strings.ToLower(strings.TrimSpace(f.Role))
	status := strings.ToLower(strings.TrimSpace(f.Status))
	rows, err := s.db.QueryContext(ctx, `
		SELECT `+adminUserColumns+`, created_at
		FROM users
		WHERE ($1 = '' OR display_name ILIKE '%' || $1 || '%' OR email ILIKE '%' || $1 || '%')
		  AND ($2 = '' OR role::text = $2)
		  AND ($3 = '' OR ($3 = 'disabled' AND disabled_at IS NOT NULL)
		                OR ($3 = 'active' AND disabled_at IS NULL))
		ORDER BY created_at DESC
		LIMIT $4`, q, role, status, limit)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var out []AdminUser
	for rows.Next() {
		u, err := scanAdminUser(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, u)
	}
	return out, rows.Err()
}
