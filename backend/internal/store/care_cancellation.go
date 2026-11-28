package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"strings"
	"time"

	"malva/backend/internal/clock"
)

var ErrCareCancellationEnded = errors.New("sesi sudah berakhir dan tidak bisa dibatalkan")
var ErrCareCancellationRefundManual = errors.New("refund sesi memerlukan penanganan manual")

const automaticRefundPrefix = "auto:session-cancellation:"
const automaticCreditPrefix = "credit:session-cancellation:"
const forfeitedCreditPrefix = "forfeited:session-cancellation:"

func IsCareCancellationLedgerKey(key string) bool {
	return strings.HasPrefix(key, automaticRefundPrefix) || strings.HasPrefix(key, automaticCreditPrefix) ||
		strings.HasPrefix(key, forfeitedCreditPrefix)
}

func cancellationHasPenalty(status string, now, start time.Time) bool {
	return status == "cancelled_by_patient" && start.Sub(now) < time.Hour
}

// CancelCareSession commits the cancellation and its financial outcome together.
func (s *Store) CancelCareSession(ctx context.Context, sessionID, role, actorID, reason string) (CareSession, CareRefund, *ChatMessage, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return CareSession{}, CareRefund{}, nil, err
	}
	defer func() { _ = tx.Rollback() }()
	var current, patient, professional, method string
	var bookingID, packageID sql.NullString
	var start time.Time
	var duration int
	if err := tx.QueryRowContext(ctx, `SELECT status, patient_id, professional_id, scheduled_at, duration_minutes, booking_id, package_id, session_type
		FROM care_sessions WHERE id=$1 FOR UPDATE`, sessionID).Scan(&current, &patient, &professional, &start, &duration, &bookingID, &packageID, &method); err != nil {
		return CareSession{}, CareRefund{}, nil, err
	}
	isPatient := role == "patient" && actorID == patient
	isProfessional := role == "professional" && actorID == professional
	if !isPatient && !isProfessional {
		return CareSession{}, CareRefund{}, nil, errors.New("anda tidak berhak atas sesi ini")
	}
	status := "cancelled_by_" + role
	if current == status {
		refund, err := scanCareRefund(tx.QueryRowContext(ctx, `SELECT `+careRefundColumns+` FROM care_refunds
			WHERE session_id=$1 AND (idempotency_key LIKE $2 OR idempotency_key=$3
				OR (kind='credit' AND status='recorded' AND package_id=$4))
			ORDER BY (idempotency_key=$3) DESC,created_at,id LIMIT 1`, sessionID,
			automaticRefundPrefix+sessionID+":%", forfeitedCreditPrefix+sessionID, packageID))
		if err != nil && !errors.Is(err, sql.ErrNoRows) {
			return CareSession{}, CareRefund{}, nil, err
		}
		if err := tx.Commit(); err != nil {
			return CareSession{}, CareRefund{}, nil, err
		}
		cs, err := s.GetCareSession(ctx, sessionID)
		return cs, refund, nil, err
	}
	if current != "scheduled" {
		return CareSession{}, CareRefund{}, nil, ErrCareSessionTerminal
	}
	now := clock.Now()
	if !now.Before(start.Add(time.Duration(duration) * time.Minute)) {
		return CareSession{}, CareRefund{}, nil, ErrCareCancellationEnded
	}
	if _, err := tx.ExecContext(ctx, `UPDATE care_sessions SET status=$2,cancel_reason=$3,cancelled_by=$4,updated_at=$5
		WHERE id=$1`, sessionID, status, strings.TrimSpace(reason), actorID, now); err != nil {
		return CareSession{}, CareRefund{}, nil, err
	}
	penalty := cancellationHasPenalty(status, now, start)
	refund, err := recordCancellationOutcome(ctx, tx, sessionID, patient, professional, actorID,
		packageID, bookingID, penalty, now)
	if err != nil {
		return CareSession{}, CareRefund{}, nil, err
	}
	if err := deactivateCancelledOneTimeLink(ctx, tx, sessionID); err != nil {
		return CareSession{}, CareRefund{}, nil, err
	}
	outcome := "none"
	switch {
	case penalty:
		outcome = "penalty"
	case refund.Kind != "":
		outcome = refund.Kind
	}
	metadata, err := json.Marshal(map[string]any{
		"session_id": sessionID, "actor_role": role, "package": packageID.Valid,
		"session_type": method, "scheduled_at": start, "reason": strings.TrimSpace(reason),
		"outcome": outcome, "refund_amount": refund.Amount,
	})
	if err != nil {
		return CareSession{}, CareRefund{}, nil, err
	}
	message := &ChatMessage{
		ID:        ClinicalRetryID("session_cancellation", actorID, sessionID),
		PatientID: patient, ProfessionalID: professional, SenderID: actorID,
		Text: "Sesi Dibatalkan oleh Profesional", Kind: "session_cancellation", Metadata: metadata,
	}
	if isPatient {
		message.Text = "Sesi Dibatalkan oleh Pasien"
	}
	err = tx.QueryRowContext(ctx, `INSERT INTO chat_messages
		(id, patient_id, professional_id, sender_id, sender_name, text, kind, attachment_meta, created_at)
		VALUES ($1,$2,$3,$4,(SELECT display_name FROM users WHERE id=$4),$5,$6,$7::jsonb,$8)
		RETURNING sender_name, created_at`, message.ID, patient, professional, actorID,
		message.Text, message.Kind, string(metadata), now).Scan(&message.SenderName, &message.CreatedAt)
	if err != nil {
		return CareSession{}, CareRefund{}, nil, err
	}
	if err := tx.Commit(); err != nil {
		return CareSession{}, CareRefund{}, nil, err
	}
	_ = s.AddAuditLog(ctx, actorID, patient, "care_session."+status, "care_session", sessionID, nil)
	cs, err := s.GetCareSession(ctx, sessionID)
	return cs, refund, message, err
}

func recordCancellationOutcome(ctx context.Context, tx *sql.Tx, sessionID, patient, professional, actorID string,
	packageID, bookingID sql.NullString, penalty bool, now time.Time) (CareRefund, error) {
	kind, state, note, key := "credit", "recorded", "Kredit sesi dikembalikan", automaticCreditPrefix+sessionID
	var amount int64
	var pkg any
	if packageID.Valid {
		pkg = packageID.String
		if penalty {
			state, note, key = "cancelled", "Kredit sesi hangus karena pembatalan kurang dari satu jam", forfeitedCreditPrefix+sessionID
		} else {
			existing, err := scanCareRefund(tx.QueryRowContext(ctx, `SELECT `+careRefundColumns+` FROM care_refunds
				WHERE session_id=$1 AND package_id=$2 AND kind='credit' AND status='recorded' ORDER BY created_at,id LIMIT 1`, sessionID, pkg))
			if !errors.Is(err, sql.ErrNoRows) {
				return existing, err
			}
			if err := tx.QueryRowContext(ctx, `SELECT price / NULLIF(total_sessions,0) FROM care_packages WHERE id=$1`, pkg).Scan(&amount); err != nil {
				return CareRefund{}, err
			}
		}
	} else {
		var paymentID string
		if bookingID.Valid {
			// Lock payment before booking, in the same order as payment completion.
			err := tx.QueryRowContext(ctx, `SELECT id, gross_amount+service_fee_amount FROM payments WHERE booking_id=$1 AND status='paid'
				ORDER BY paid_at DESC NULLS LAST, id LIMIT 1 FOR UPDATE`, bookingID.String).Scan(&paymentID, &amount)
			if err != nil && !errors.Is(err, sql.ErrNoRows) {
				return CareRefund{}, err
			}
			if _, err := tx.ExecContext(ctx, `UPDATE bookings SET status='cancelled' WHERE id=$1 AND status='paid'`, bookingID.String); err != nil {
				return CareRefund{}, err
			}
		}
		if penalty || amount <= 0 {
			return CareRefund{}, nil
		}
		kind, state, note, key = "refund", "processing", "Refund penuh sesi sekali bayar", automaticRefundPrefix+sessionID+":"+paymentID
	}
	return scanCareRefund(tx.QueryRowContext(ctx, `INSERT INTO care_refunds
		(package_id, session_id, patient_id, professional_id, amount, kind, status, reason, idempotency_key, created_by, created_at, updated_at)
		VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$11) RETURNING `+careRefundColumns,
		pkg, sessionID, patient, professional, amount, kind, state, note, key, actorID, now))
}

func (s *Store) PendingCareCancellationRefunds(ctx context.Context) ([]string, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT id FROM care_refunds
		WHERE status='processing' AND idempotency_key LIKE $1 ORDER BY updated_at,id LIMIT 20`, automaticRefundPrefix+"%")
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var ids []string
	for rows.Next() {
		var id string
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}
	return ids, rows.Err()
}

// ProcessCareCancellationRefund serializes dispatch with payment updates. Replaying the
// same gateway key after a timeout or a failed local commit is safe.
func (s *Store) ProcessCareCancellationRefund(ctx context.Context, refundID string,
	dispatch func(context.Context, string, string, int64) (string, error)) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()
	var orderID, paymentID string
	var amount int64
	err = tx.QueryRowContext(ctx, `SELECT p.id, p.reference, r.amount FROM care_refunds r
		JOIN care_sessions cs ON cs.id=r.session_id
		JOIN payments p ON p.booking_id=cs.booking_id
		WHERE r.id=$1 AND r.status='processing' AND r.idempotency_key=$2 || cs.id::text || ':' || p.id::text
		  AND cs.status IN ('cancelled_by_patient','cancelled_by_professional')
		  AND p.status='paid' AND p.gross_amount+p.service_fee_amount=r.amount
		FOR UPDATE OF p, r SKIP LOCKED`,
		refundID, automaticRefundPrefix).Scan(&paymentID, &orderID, &amount)
	if errors.Is(err, sql.ErrNoRows) {
		return nil
	}
	if err != nil {
		return err
	}
	externalID, err := dispatch(ctx, orderID, refundID, amount)
	if errors.Is(err, ErrCareCancellationRefundManual) {
		if _, err := tx.ExecContext(ctx, `UPDATE care_refunds SET status='failed',
			reason='Metode pembayaran memerlukan pengembalian manual',updated_at=$2 WHERE id=$1`, refundID, clock.Now()); err != nil {
			return err
		}
		return tx.Commit()
	}
	if err != nil {
		if _, updateErr := tx.ExecContext(ctx, `UPDATE care_refunds SET updated_at=$2 WHERE id=$1`, refundID, clock.Now()); updateErr != nil {
			return errors.Join(err, updateErr)
		}
		return errors.Join(err, tx.Commit())
	}
	if _, err := tx.ExecContext(ctx, `UPDATE payments SET status='refunded' WHERE id=$1`, paymentID); err != nil {
		return err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE care_refunds SET status='paid',external_id=$2,updated_at=$3 WHERE id=$1`,
		refundID, externalID, clock.Now()); err != nil {
		return err
	}
	return tx.Commit()
}
