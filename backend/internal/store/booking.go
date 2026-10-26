package store

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"

	"malva/backend/internal/clock"
)

// ErrPaymentNotFound menandai reference pembayaran yang tidak ada. Dipisahkan
// dari error otorisasi agar handler bisa membedakan 404 (tidak ditemukan)
// dengan 403 (bukan pemilik).
var ErrPaymentNotFound = errors.New("payment not found")

// ============================================================
// BOOKING & PAYMENT & EARNINGS
// ============================================================

type Booking struct {
	ID              string    `json:"id"`
	PatientID       string    `json:"patient_id"`
	ProfessionalID  string    `json:"professional_id"`
	PackageID       *string   `json:"package_id,omitempty"`
	ServiceType     string    `json:"service_type"`
	SessionType     string    `json:"session_type"`
	BookingDate     string    `json:"booking_date"`
	SlotTime        string    `json:"slot_time"`
	DurationMinutes int       `json:"duration_minutes"`
	Price           int64     `json:"price"`
	Status          string    `json:"status"`
	CreatedAt       time.Time `json:"created_at"`
}

type Payment struct {
	ID                string     `json:"id"`
	BookingID         string     `json:"booking_id"`
	PaymentMethod     string     `json:"payment_method"`
	GrossAmount       int64      `json:"gross_amount"`
	ServiceFeeAmount  int64      `json:"service_fee_amount"`
	PlatformFeeAmount int64      `json:"platform_fee_amount"`
	NetAmount         int64      `json:"net_amount"`
	Reference         string     `json:"reference"`
	ExternalID        string     `json:"external_id,omitempty"`
	Status            string     `json:"status"`
	Gateway           string     `json:"gateway,omitempty"`
	SnapToken         string     `json:"snap_token,omitempty"`
	RedirectURL       string     `json:"redirect_url,omitempty"`
	PaidAt            *time.Time `json:"paid_at,omitempty"`
	ExpiresAt         *time.Time `json:"expires_at,omitempty"`
	CreatedAt         time.Time  `json:"created_at"`
}

type EarningsSummary struct {
	TotalSessions int   `json:"total_sessions"`
	GrossAmount   int64 `json:"gross_amount"`
	PlatformFee   int64 `json:"platform_fee"`
	NetAmount     int64 `json:"net_amount"`
	// PendingNet adalah bagian yang benar-benar bisa dicairkan sekarang
	// (net dari earning berstatus 'pending'). Tanpa field ini UI memakai
	// NetAmount sebagai "Balance", padahal NetAmount adalah akumulasi
	// sepanjang waktu — angka yang ditampilkan jadi lebih besar daripada
	// yang bisa ditarik.
	PendingNet    int64  `json:"pending_net"`
	PayoutBalance string `json:"payout_balance"`
	PayoutAccount string `json:"payout_account"`
}

type EarningsTransaction struct {
	ID            string    `json:"id"`
	PaymentID     string    `json:"payment_id"`
	Reference     string    `json:"reference"`
	PaymentMethod string    `json:"payment_method"`
	Gross         int64     `json:"gross"`
	PlatformFee   int64     `json:"platform_fee"`
	Net           int64     `json:"net"`
	PaidAt        time.Time `json:"paid_at"`
	PayoutStatus  string    `json:"payout_status"`
}

type PayoutInfo struct {
	PayoutBank    string `json:"payout_bank"`
	PayoutAccount string `json:"payout_account"`
	PayoutBalance int64  `json:"payout_balance"`
}

func (s *Store) CreateBooking(ctx context.Context, b Booking) (Booking, error) {
	const q = `INSERT INTO bookings
		(patient_id, professional_id, package_id, service_type, session_type, booking_date, slot_time, duration_minutes, price, status)
		VALUES ($1, $2, $3, $4, $5, $6, NULLIF($7, '')::time, $8, $9, 'pending')
		RETURNING id, status, created_at`
	err := s.db.QueryRowContext(ctx, q, b.PatientID, b.ProfessionalID, b.PackageID, b.ServiceType, b.SessionType,
		b.BookingDate, b.SlotTime, b.DurationMinutes, b.Price).
		Scan(&b.ID, &b.Status, &b.CreatedAt)
	if err != nil {
		return Booking{}, err
	}
	_ = s.AddAuditLog(ctx, b.PatientID, b.PatientID, "booking.created", "bookings", b.ID,
		map[string]any{"professional_id": b.ProfessionalID, "price": b.Price})
	return b, nil
}

func (s *Store) ListBookingsForUser(ctx context.Context, userID, role string, limit int) ([]Booking, error) {
	limit = normalizeLimit(limit, 20, 100)
	var q string
	var args []interface{}
	if role == "professional" {
		q = `SELECT id, patient_id, professional_id, package_id, service_type, session_type, booking_date::text, COALESCE(slot_time::text, ''), duration_minutes, price, status, created_at
			FROM bookings WHERE professional_id = $1 ORDER BY booking_date, slot_time LIMIT $2`
		args = []interface{}{userID, limit}
	} else {
		q = `SELECT id, patient_id, professional_id, package_id, service_type, session_type, booking_date::text, COALESCE(slot_time::text, ''), duration_minutes, price, status, created_at
			FROM bookings WHERE patient_id = $1 ORDER BY booking_date, slot_time LIMIT $2`
		args = []interface{}{userID, limit}
	}
	rows, err := s.db.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var out []Booking
	for rows.Next() {
		var b Booking
		if err := rows.Scan(&b.ID, &b.PatientID, &b.ProfessionalID, &b.PackageID, &b.ServiceType, &b.SessionType,
			&b.BookingDate, &b.SlotTime, &b.DurationMinutes, &b.Price, &b.Status, &b.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, b)
	}
	return out, rows.Err()
}

func (s *Store) GetBooking(ctx context.Context, bookingID string) (Booking, error) {
	const q = `SELECT id, patient_id, professional_id, package_id, service_type, session_type,
		booking_date::text, COALESCE(slot_time::text, ''), duration_minutes, price, status, created_at
		FROM bookings WHERE id = $1`
	var b Booking
	err := s.db.QueryRowContext(ctx, q, bookingID).
		Scan(&b.ID, &b.PatientID, &b.ProfessionalID, &b.PackageID, &b.ServiceType, &b.SessionType,
			&b.BookingDate, &b.SlotTime, &b.DurationMinutes, &b.Price, &b.Status, &b.CreatedAt)
	if err != nil {
		return Booking{}, err
	}
	return b, nil
}

// AuthorizePaymentOwner memastikan hanya pemilik booking yang
// mengonfirmasi pembayarannya (tidak bisa oleh pihak lain).
func (s *Store) AuthorizePaymentOwner(ctx context.Context, paymentID, subject, role string) error {
	var patientID string
	err := s.db.QueryRowContext(ctx, `SELECT b.patient_id FROM payments p
		JOIN bookings b ON b.id = p.booking_id WHERE p.id = $1`, paymentID).Scan(&patientID)
	if err != nil {
		return err
	}
	if role != "patient" || patientID != subject {
		return errors.New("only the booking owner can confirm this payment")
	}
	return nil
}

// AuthorizePaymentByReference memeriksa kepemilikan pembayaran DARI REFERENCE
// tanpa mengubah apa pun. Dipakai handler mark-paid agar otorisasi terjadi
// SEBELUM mutasi: sebelumnya payment sudah terlanjur berstatus 'paid' walau
// pemanggil akhirnya ditolak 403.
func (s *Store) AuthorizePaymentByReference(ctx context.Context, reference, subject, role string) error {
	var patientID string
	err := s.db.QueryRowContext(ctx, `SELECT b.patient_id FROM payments p
		JOIN bookings b ON b.id = p.booking_id WHERE p.reference = $1`, reference).Scan(&patientID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return ErrPaymentNotFound
		}
		return err
	}
	if role != "patient" || patientID != subject {
		return errors.New("only the booking owner can confirm this payment")
	}
	return nil
}

func (s *Store) UpdateBookingStatus(ctx context.Context, bookingID, status string) error {
	const q = `UPDATE bookings SET status = $1 WHERE id = $2`
	res, err := s.db.ExecContext(ctx, q, status, bookingID)
	if err != nil {
		return err
	}
	aff, _ := res.RowsAffected()
	if aff == 0 {
		return errors.New("booking not found")
	}
	return nil
}

// CancelPendingBooking membatalkan booking pending beserta payment pending
// yang terkait dalam satu transaksi. Dipakai ketika pasien membatalkan paket
// pending_payment — tanpa ini booking & payment menggantung selamanya.
func (s *Store) CancelPendingBooking(ctx context.Context, bookingID string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	// Batalkan semua payment pending untuk booking ini.
	if _, err := tx.ExecContext(ctx,
		`UPDATE payments SET status = 'cancelled' WHERE booking_id = $1 AND status = 'pending'`,
		bookingID); err != nil {
		return err
	}
	// Batalkan booking.
	res, err := tx.ExecContext(ctx,
		`UPDATE bookings SET status = 'cancelled' WHERE id = $1 AND status = 'pending'`,
		bookingID)
	if err != nil {
		return err
	}
	aff, _ := res.RowsAffected()
	if aff == 0 {
		return errors.New("booking not found or already processed")
	}
	return tx.Commit()
}

func (s *Store) CreatePayment(ctx context.Context, p Payment) (Payment, error) {
	// platform_fee_pct SMALLINT (maks 32767): fee 10% disimpan sebagai 10,
	// bukan nominal rupiah (nominal ada di platform_fee_amount BIGINT).
	const q = `INSERT INTO payments
		(booking_id, payment_method, gross_amount, service_fee_amount, platform_fee_pct, platform_fee_amount, net_amount, reference, status)
		VALUES ($1, $2, $3, $4, 10, $5, $6, $7, 'pending')
		RETURNING id, status, created_at`
	err := s.db.QueryRowContext(ctx, q, p.BookingID, p.PaymentMethod, p.GrossAmount, p.ServiceFeeAmount,
		p.PlatformFeeAmount, p.NetAmount, p.Reference).
		Scan(&p.ID, &p.Status, &p.CreatedAt)
	if err != nil {
		return Payment{}, err
	}
	return p, nil
}

func (s *Store) MarkPaymentPaid(ctx context.Context, reference, externalID string) (Payment, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return Payment{}, err
	}
	defer func() { _ = tx.Rollback() }()

	var p Payment
	const q = `UPDATE payments
		SET status = 'paid', paid_at = now(), external_id = COALESCE(NULLIF($1,''), external_id)
		WHERE reference = $2 AND status = 'pending'
		RETURNING id, booking_id, payment_method, gross_amount, service_fee_amount, platform_fee_amount, net_amount, created_at`
	err = tx.QueryRowContext(ctx, q, externalID, reference).
		Scan(&p.ID, &p.BookingID, &p.PaymentMethod, &p.GrossAmount, &p.ServiceFeeAmount, &p.PlatformFeeAmount, &p.NetAmount, &p.CreatedAt)
	if err != nil {
		return Payment{}, errors.New("payment not found or already paid")
	}

	// Pastikan booking benar-benar ada sebelum statusnya diubah. professionalID
	// tidak lagi dibaca di sini: pendapatan dicatat saat sesi selesai, bukan
	// saat pembayaran lunas (lihat catatan di bawah).
	var bookingExists bool
	err = tx.QueryRowContext(ctx,
		`SELECT EXISTS (SELECT 1 FROM bookings WHERE id = $1)`, p.BookingID).Scan(&bookingExists)
	if err != nil {
		return Payment{}, err
	}
	if !bookingExists {
		return Payment{}, errors.New("booking untuk pembayaran ini tidak ditemukan")
	}

	if _, err := tx.ExecContext(ctx, `UPDATE bookings SET status = 'paid' WHERE id = $1`, p.BookingID); err != nil {
		return Payment{}, err
	}

	// Pendapatan profesional TIDAK dicatat di sini.
	//
	// Keputusan pemilik produk: earning diakui saat SESI SELESAI, bukan saat
	// pembayaran lunas. Sebelumnya baris earnings dibuat di titik ini, sehingga
	// sesi yang kemudian dibatalkan/di-reschedule tetap tercatat sebagai
	// pendapatan dan harus dikoreksi manual. Lihat
	// store.recognizeEarningForSession (dipanggil dari UpdateCareSessionStatus)
	// dan migrasi 016_earnings_session.sql.
	//
	// Kasus khusus: pembayaran yang memang tidak akan pernah menghasilkan sesi
	// (booking warisan tanpa jam) diakui lewat RecognizeEarningForPayment, yang
	// dipanggil activatePaidBooking pada cabang tersebut.

	if err := tx.Commit(); err != nil {
		return Payment{}, err
	}
	p.Reference = reference
	p.Status = "paid"
	now := clock.Now()
	p.PaidAt = &now
	return p, nil
}

// UpdatePaymentGateway menyimpan referensi gateway (token/redirect) ke payment.
func (s *Store) UpdatePaymentGateway(ctx context.Context, reference, gateway, snapToken, redirectURL string) (Payment, error) {
	const q = `UPDATE payments
		SET gateway = $2, snap_token = $3, redirect_url = $4
		WHERE reference = $1
		RETURNING id, booking_id, payment_method, gross_amount, service_fee_amount,
			platform_fee_amount, net_amount, reference, COALESCE(external_id, ''), status,
			COALESCE(gateway, ''), COALESCE(snap_token, ''), COALESCE(redirect_url, ''),
			paid_at, created_at`
	var p Payment
	err := s.db.QueryRowContext(ctx, q, reference, gateway, snapToken, redirectURL).
		Scan(&p.ID, &p.BookingID, &p.PaymentMethod, &p.GrossAmount, &p.ServiceFeeAmount,
			&p.PlatformFeeAmount, &p.NetAmount, &p.Reference, &p.ExternalID, &p.Status,
			&p.Gateway, &p.SnapToken, &p.RedirectURL, &p.PaidAt, &p.CreatedAt)
	if err != nil {
		return Payment{}, err
	}
	return p, nil
}

// PaymentStatusByReference mengembalikan status pembayaran ('pending'/'paid'/…)
// tanpa mengubah apa pun. Dipakai webhook agar notifikasi settlement ganda
// tidak diperlakukan sebagai kegagalan.
func (s *Store) PaymentStatusByReference(ctx context.Context, reference string) (string, error) {
	var status string
	err := s.db.QueryRowContext(ctx,
		`SELECT status FROM payments WHERE reference = $1`, reference).Scan(&status)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", ErrPaymentNotFound
		}
		return "", err
	}
	return status, nil
}

// ensureEarningRow mencatat satu baris pendapatan untuk sebuah pembayaran bila
// pembayaran itu belum pernah dicatat.
//
// WAJIB dipanggil di dalam transaksi yang sudah mengunci baris pembayaran
// (SELECT … FOR UPDATE). Tanpa kunci itu, dua sesi dari paket yang sama yang
// diselesaikan hampir bersamaan bisa sama-sama lolos pemeriksaan EXISTS dan
// menghasilkan pendapatan ganda.
//
// sessionID boleh kosong ("") untuk pembayaran yang tidak punya sesi
// (booking warisan tanpa jam); kolomnya menjadi NULL.
func ensureEarningRow(ctx context.Context, tx *sql.Tx, professionalID, paymentID, sessionID string,
	gross, platformFee, net int64) error {
	var exists bool
	if err := tx.QueryRowContext(ctx,
		`SELECT EXISTS (SELECT 1 FROM earnings WHERE payment_id = $1)`, paymentID).Scan(&exists); err != nil {
		return err
	}
	if exists {
		return nil
	}
	var sessionArg any
	if strings.TrimSpace(sessionID) != "" {
		sessionArg = strings.TrimSpace(sessionID)
	}
	_, err := tx.ExecContext(ctx, `INSERT INTO earnings
		(professional_id, payment_id, session_id, gross, platform_fee, net)
		VALUES ($1, $2, $3, $4, $5, $6)`,
		professionalID, paymentID, sessionArg, gross, platformFee, net)
	return err
}

// recognizeEarningForSession mencatat pendapatan profesional ketika sebuah sesi
// berstatus 'completed' (dipanggil dari UpdateCareSessionStatus).
//
// Pemetaan sesi -> pembayaran:
//   - quick consult  : care_sessions.booking_id -> payments.booking_id
//   - paket, sesi 1  : care_sessions.booking_id = booking pembayaran paket
//   - paket, sesi 2+ : booking_id NULL, jadi lewat care_packages.booking_id
//
// COALESCE menangani ketiganya sekaligus. Sesi tanpa pembayaran (mis. sesi
// bonus/kompensasi) tidak menghasilkan earning dan BUKAN error.
//
// Satu pembayaran hanya menghasilkan satu baris earnings walaupun paketnya
// berisi 4 sesi: nilai paket tidak dipecah per sesi, karena pemecahan itu akan
// mengubah nominal yang diterima profesional dan bukan bagian dari keputusan
// "kapan pendapatan diakui". Pembayaran model lama yang sudah punya baris
// earnings (session_id NULL) juga dilewati, sehingga tidak terjadi hitung ganda.
func recognizeEarningForSession(ctx context.Context, tx *sql.Tx, sessionID string) error {
	// Langkah 1: cari pembayaran yang membiayai sesi ini (tanpa kunci).
	const findQ = `SELECT p.id
		FROM care_sessions cs
		LEFT JOIN care_packages cp ON cp.id = cs.package_id
		JOIN payments p
		  ON p.booking_id = COALESCE(cs.booking_id, cp.booking_id)
		 AND p.status = 'paid'
		WHERE cs.id = $1
		ORDER BY p.created_at DESC
		LIMIT 1`
	var paymentID string
	err := tx.QueryRowContext(ctx, findQ, sessionID).Scan(&paymentID)
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}

	// Langkah 2: kunci baris pembayaran, lalu ambil data pendapatan.
	// Kunci dipisah dari langkah 1 karena PostgreSQL tidak mengizinkan
	// FOR UPDATE pada sisi yang bisa NULL dari outer join (care_packages
	// selalu ikut di-LEFT JOIN, baik sesi paket maupun quick consult).
	const lockQ = `SELECT b.professional_id,
			p.gross_amount, p.platform_fee_amount, p.net_amount
		FROM payments p
		JOIN bookings b ON b.id = p.booking_id
		WHERE p.id = $1 AND p.status = 'paid'
		FOR UPDATE OF p`
	var professionalID string
	var gross, platformFee, net int64
	err = tx.QueryRowContext(ctx, lockQ, paymentID).
		Scan(&professionalID, &gross, &platformFee, &net)
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	return ensureEarningRow(ctx, tx, professionalID, paymentID, sessionID, gross, platformFee, net)
}

// RecognizeEarningForPayment mencatat pendapatan untuk pembayaran yang memang
// tidak akan pernah menghasilkan sesi. Saat ini hanya dipakai untuk booking
// warisan yang tidak punya jam (jalur "hanya link" di activatePaidBooking);
// tanpa ini pendapatan profesional pada data lama tidak akan pernah tercatat
// setelah aturan "earning saat sesi selesai" berlaku.
func (s *Store) RecognizeEarningForPayment(ctx context.Context, paymentID string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	var professionalID string
	var gross, platformFee, net int64
	err = tx.QueryRowContext(ctx, `SELECT b.professional_id,
			p.gross_amount, p.platform_fee_amount, p.net_amount
		FROM payments p
		JOIN bookings b ON b.id = p.booking_id
		WHERE p.id = $1 AND p.status = 'paid'
		FOR UPDATE OF p`, paymentID).
		Scan(&professionalID, &gross, &platformFee, &net)
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	if err := ensureEarningRow(ctx, tx, professionalID, paymentID, "", gross, platformFee, net); err != nil {
		return err
	}
	return tx.Commit()
}

func (s *Store) EarningsSummary(ctx context.Context, professionalID string) (EarningsSummary, error) {
	const q = `SELECT COALESCE(COUNT(*),0), COALESCE(SUM(gross),0), COALESCE(SUM(platform_fee),0),
			COALESCE(SUM(net),0),
			COALESCE(SUM(net) FILTER (WHERE payout_status = 'pending'), 0)
		FROM earnings WHERE professional_id = $1`
	var e EarningsSummary
	err := s.db.QueryRowContext(ctx, q, professionalID).
		Scan(&e.TotalSessions, &e.GrossAmount, &e.PlatformFee, &e.NetAmount, &e.PendingNet)
	return e, err
}

func (s *Store) ListEarningsTransactions(ctx context.Context, professionalID string, limit int) ([]EarningsTransaction, error) {
	limit = normalizeLimit(limit, 20, 100)
	const q = `SELECT e.id, e.payment_id, p.reference, p.payment_method, e.gross, e.platform_fee, e.net, p.paid_at, e.payout_status
		FROM earnings e
		JOIN payments p ON p.id = e.payment_id
		WHERE e.professional_id = $1
		ORDER BY e.created_at DESC
		LIMIT $2`
	rows, err := s.db.QueryContext(ctx, q, professionalID, limit)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var out []EarningsTransaction
	for rows.Next() {
		var t EarningsTransaction
		if err := rows.Scan(&t.ID, &t.PaymentID, &t.Reference, &t.PaymentMethod, &t.Gross, &t.PlatformFee, &t.Net, &t.PaidAt, &t.PayoutStatus); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

// RequestPayout menandai earning sebagai payout_requested beserta rekening tujuan.
// professionalID WAJIB ikut difilter agar profesional tidak bisa meminta payout
// atas earning milik profesional lain (IDOR) sekaligus menimpa rekening korban.
func (s *Store) RequestPayout(ctx context.Context, earningID, professionalID, bank, account string) error {
	const q = `UPDATE earnings
		SET payout_status = 'payout_requested', payout_bank = $1, payout_account = $2, payout_requested_at = now()
		WHERE id = $3 AND professional_id = $4 AND payout_status = 'pending'`
	res, err := s.db.ExecContext(ctx, q, bank, account, earningID, professionalID)
	if err != nil {
		return err
	}
	aff, _ := res.RowsAffected()
	if aff == 0 {
		return errors.New("earning not found or already requested")
	}
	return nil
}

// PayoutAllPending mencairkan SELURUH earning berstatus 'pending' milik satu
// profesional dalam satu pernyataan.
//
// Model "saldo gabungan": satu permintaan payout mewakili semua transaksi yang
// belum dicairkan. Sebelumnya UI mengirim hanya earning pertama
// (pending.first.id), sehingga nominal "Balance" yang ditampilkan tidak sama
// dengan yang benar-benar diminta — sisanya tertinggal tanpa penjelasan.
//
// Filter professional_id mencegah pencairan milik profesional lain, dan
// filter payout_status = 'pending' membuat pemanggilan berulang tidak menimpa
// bank/rekening pada permintaan yang sudah berjalan.
func (s *Store) PayoutAllPending(ctx context.Context, professionalID, bank, account string) (int64, int64, error) {
	const q = `WITH target AS (
			UPDATE earnings
			SET payout_status = 'payout_requested', payout_bank = $1,
			    payout_account = $2, payout_requested_at = now()
			WHERE professional_id = $3 AND payout_status = 'pending'
			RETURNING net
		)
		SELECT COUNT(*), COALESCE(SUM(net), 0) FROM target`
	var count, total int64
	err := s.db.QueryRowContext(ctx, q, bank, account, professionalID).Scan(&count, &total)
	return count, total, err
}

// MarkEarningPayoutPaid menandai satu earning sudah benar-benar ditransfer
// admin (pending -> payout_requested -> paid_out) beserta stempel paid_out_at.
//
// BELUM ADA PEMANGGIL: belum ada endpoint admin untuk menyelesaikan payout.
// Saat ini transfer dilakukan manual dan status di DB tidak ikut berubah,
// sehingga paid_out_at tidak pernah terisi. Fungsi ini sengaja dipertahankan
// sebagai titik masuk yang sudah teruji (WHERE payout_status =
// 'payout_requested' mencegah penandaan ganda) untuk endpoint admin berikutnya.
func (s *Store) MarkEarningPayoutPaid(ctx context.Context, earningID string) error {
	const q = `UPDATE earnings
		SET payout_status = 'paid_out', paid_out_at = now()
		WHERE id = $1 AND payout_status = 'payout_requested'`
	res, err := s.db.ExecContext(ctx, q, earningID)
	if err != nil {
		return err
	}
	aff, _ := res.RowsAffected()
	if aff == 0 {
		return errors.New("earning not found or not in payout queue")
	}
	return nil
}
