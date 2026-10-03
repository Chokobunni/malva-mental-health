package store

import (
	"context"
	"errors"
	"time"
)

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
	ID                   string     `json:"id"`
	BookingID            string     `json:"booking_id"`
	PaymentMethod        string     `json:"payment_method"`
	GrossAmount          int64      `json:"gross_amount"`
	ServiceFeeAmount     int64      `json:"service_fee_amount"`
	PlatformFeeAmount    int64      `json:"platform_fee_amount"`
	NetAmount            int64      `json:"net_amount"`
	Reference            string     `json:"reference"`
	ExternalID           string     `json:"external_id,omitempty"`
	Status               string     `json:"status"`
	PaidAt               *time.Time `json:"paid_at,omitempty"`
	ExpiresAt            *time.Time `json:"expires_at,omitempty"`
	CreatedAt            time.Time  `json:"created_at"`
}

type EarningsSummary struct {
	TotalSessions  int    `json:"total_sessions"`
	GrossAmount    int64  `json:"gross_amount"`
	PlatformFee    int64  `json:"platform_fee"`
	NetAmount      int64  `json:"net_amount"`
	PayoutBalance  string `json:"payout_balance"`
	PayoutAccount  string `json:"payout_account"`
}

type EarningsTransaction struct {
	ID          string     `json:"id"`
	PaymentID   string     `json:"payment_id"`
	Reference   string     `json:"reference"`
	PaymentMethod string   `json:"payment_method"`
	Gross       int64      `json:"gross"`
	PlatformFee int64      `json:"platform_fee"`
	Net         int64      `json:"net"`
	PaidAt      time.Time  `json:"paid_at"`
	PayoutStatus string    `json:"payout_status"`
}

type PayoutInfo struct {
	PayoutBank     string `json:"payout_bank"`
	PayoutAccount  string `json:"payout_account"`
	PayoutBalance  int64  `json:"payout_balance"`
}

func (s *Store) CreateBooking(ctx context.Context, b Booking) (Booking, error) {
	const q = `INSERT INTO bookings
		(patient_id, professional_id, package_id, service_type, session_type, booking_date, slot_time, duration_minutes, price, status)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'pending')
		RETURNING id, status, created_at`
	err := s.db.QueryRowContext(ctx, q, b.PatientID, b.ProfessionalID, b.PackageID, b.ServiceType, b.SessionType,
		b.BookingDate, b.SlotTime, b.DurationMinutes, b.Price).
		Scan(&b.ID, &b.Status, &b.CreatedAt)
	if err != nil { return Booking{}, err }
	_ = s.AddAuditLog(ctx, b.PatientID, b.PatientID, "booking.created", "bookings", b.ID,
		map[string]any{"professional_id": b.ProfessionalID, "price": b.Price})
	return b, nil
}

func (s *Store) ListBookingsForUser(ctx context.Context, userID, role string, limit int) ([]Booking, error) {
	limit = normalizeLimit(limit, 20, 100)
	var q string
	var args []interface{}
	if role == "professional" {
		q = `SELECT id, patient_id, professional_id, package_id, service_type, session_type, booking_date::text, slot_time::text, duration_minutes, price, status, created_at
			FROM bookings WHERE professional_id = $1 ORDER BY booking_date, slot_time LIMIT $2`
		args = []interface{}{userID, limit}
	} else {
		q = `SELECT id, patient_id, professional_id, package_id, service_type, session_type, booking_date::text, slot_time::text, duration_minutes, price, status, created_at
			FROM bookings WHERE patient_id = $1 ORDER BY booking_date, slot_time LIMIT $2`
		args = []interface{}{userID, limit}
	}
	rows, err := s.db.QueryContext(ctx, q, args...)
	if err != nil { return nil, err }
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

func (s *Store) UpdateBookingStatus(ctx context.Context, bookingID, status string) error {
	const q = `UPDATE bookings SET status = $1 WHERE id = $2`
	res, err := s.db.ExecContext(ctx, q, status, bookingID)
	if err != nil { return err }
	aff, _ := res.RowsAffected()
	if aff == 0 { return errors.New("booking not found") }
	return nil
}

func (s *Store) CreatePayment(ctx context.Context, p Payment) (Payment, error) {
	const q = `INSERT INTO payments
		(booking_id, payment_method, gross_amount, service_fee_amount, platform_fee_pct, platform_fee_amount, net_amount, reference, status)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, 'pending')
		RETURNING id, status, created_at`
	err := s.db.QueryRowContext(ctx, q, p.BookingID, p.PaymentMethod, p.GrossAmount, p.ServiceFeeAmount, p.PlatformFeeAmount,
		p.PlatformFeeAmount, p.NetAmount, p.Reference).
		Scan(&p.ID, &p.Status, &p.CreatedAt)
	if err != nil { return Payment{}, err }
	return p, nil
}

func (s *Store) MarkPaymentPaid(ctx context.Context, reference, externalID string) (Payment, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return Payment{}, err }
	defer func() { _ = tx.Rollback() }()

	var p Payment
	const q = `UPDATE payments
		SET status = 'paid', paid_at = now(), external_id = COALESCE(NULLIF($1,''), external_id)
		WHERE reference = $2 AND status = 'pending'
		RETURNING id, booking_id, payment_method, gross_amount, service_fee_amount, platform_fee_amount, net_amount, created_at`
	err = tx.QueryRowContext(ctx, q, externalID, reference).
		Scan(&p.ID, &p.BookingID, &p.PaymentMethod, &p.GrossAmount, &p.ServiceFeeAmount, &p.PlatformFeeAmount, &p.NetAmount, &p.CreatedAt)
	if err != nil { return Payment{}, errors.New("payment not found or already paid") }

	var professionalID string
	err = tx.QueryRowContext(ctx, `SELECT professional_id FROM bookings WHERE id = $1`, p.BookingID).Scan(&professionalID)
	if err != nil { return Payment{}, err }

	if _, err := tx.ExecContext(ctx, `UPDATE bookings SET status = 'paid' WHERE id = $1`, p.BookingID); err != nil {
		return Payment{}, err
	}

	const eq = `INSERT INTO earnings (professional_id, payment_id, gross, platform_fee, net)
		VALUES ($1, $2, $3, $4, $5)`
	if _, err := tx.ExecContext(ctx, eq, professionalID, p.ID, p.GrossAmount, p.PlatformFeeAmount, p.NetAmount); err != nil {
		return Payment{}, err
	}

	if err := tx.Commit(); err != nil { return Payment{}, err }
	p.Reference = reference
	p.Status = "paid"
	now := time.Now()
	p.PaidAt = &now
	return p, nil
}

func (s *Store) CreateEarning(ctx context.Context, professionalID string, p Payment) (string, error) {
	const q = `INSERT INTO earnings (professional_id, payment_id, gross, platform_fee, net)
		VALUES ($1, $2, $3, $4, $5) RETURNING id`
	var id string
	err := s.db.QueryRowContext(ctx, q, professionalID, p.ID, p.GrossAmount, p.PlatformFeeAmount, p.NetAmount).Scan(&id)
	return id, err
}

func (s *Store) EarningsSummary(ctx context.Context, professionalID string) (EarningsSummary, error) {
	const q = `SELECT COALESCE(COUNT(*),0), COALESCE(SUM(gross),0), COALESCE(SUM(platform_fee),0), COALESCE(SUM(net),0)
		FROM earnings WHERE professional_id = $1`
	var e EarningsSummary
	err := s.db.QueryRowContext(ctx, q, professionalID).
		Scan(&e.TotalSessions, &e.GrossAmount, &e.PlatformFee, &e.NetAmount)
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
	if err != nil { return nil, err }
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

func (s *Store) RequestPayout(ctx context.Context, earningID, bank, account string) error {
	const q = `UPDATE earnings
		SET payout_status = 'payout_requested', payout_bank = $1, payout_account = $2, payout_requested_at = now()
		WHERE id = $3 AND payout_status = 'pending'`
	res, err := s.db.ExecContext(ctx, q, bank, account, earningID)
	if err != nil { return err }
	aff, _ := res.RowsAffected()
	if aff == 0 { return errors.New("earning not found or already requested") }
	return nil
}

func (s *Store) MarkEarningPayoutPaid(ctx context.Context, earningID string) error {
	const q = `UPDATE earnings
		SET payout_status = 'paid_out', paid_out_at = now()
		WHERE id = $1 AND payout_status = 'payout_requested'`
	res, err := s.db.ExecContext(ctx, q, earningID)
	if err != nil { return err }
	aff, _ := res.RowsAffected()
	if aff == 0 { return errors.New("earning not found or not in payout queue") }
	return nil
}
