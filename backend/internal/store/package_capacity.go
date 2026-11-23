package store

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"malva/backend/internal/clock"
)

var ErrPackageCapacity = errors.New("kapasitas pasien paket penuh")

const packagePaymentInitializationWindow = 2 * time.Minute

func lockPackageCapacity(ctx context.Context, tx *sql.Tx, professionalID string) error {
	_, err := tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,0))`, "care_capacity:"+professionalID)
	return err
}

// An unfinished gateway initialization reserves capacity briefly. A payable
// checkout keeps its place until the gateway reports a terminal status.
const packagePatientAvailabilityQuery = `
    WITH active AS (
        SELECT DISTINCT patient_id
        FROM care_packages
        WHERE professional_id = $1 AND status = 'active' AND expires_at > $3
    ), reserved AS (
        SELECT DISTINCT cp.patient_id
        FROM care_packages cp
        JOIN bookings b ON b.id = cp.booking_id
        WHERE cp.professional_id = $1 AND cp.status = 'pending_payment'
          AND b.patient_id = cp.patient_id AND b.professional_id = cp.professional_id
          AND b.status IN ('pending', 'paid')
          AND EXISTS (
            SELECT 1 FROM payments p
            WHERE p.booking_id = b.id AND (
                p.status = 'paid' OR (p.status = 'pending' AND (
                    p.gateway <> 'midtrans' OR NULLIF(p.snap_token, '') IS NOT NULL OR p.created_at > $4
                ))
            )
          )
    ), occupied AS (
        SELECT patient_id FROM active
        UNION
        SELECT patient_id FROM reserved
    )
    SELECT (SELECT patient_capacity FROM professional_pricing WHERE professional_id = $1),
           (SELECT COUNT(*) FROM occupied),
           EXISTS (SELECT 1 FROM active WHERE patient_id::text = $2),
           EXISTS (SELECT 1 FROM reserved WHERE patient_id::text = $2)
`

type packageCapacityQueryer interface {
	QueryRowContext(context.Context, string, ...any) *sql.Row
}

func packagePatientAvailability(ctx context.Context, q packageCapacityQueryer, professionalID, patientID string, now time.Time) (remaining *int, canRenew, canResume bool, err error) {
	var capacity *int
	var occupied int
	err = q.QueryRowContext(ctx, packagePatientAvailabilityQuery, professionalID, patientID, now, now.Add(-packagePaymentInitializationWindow)).
		Scan(&capacity, &occupied, &canRenew, &canResume)
	if err != nil {
		return nil, false, false, err
	}
	left := max(0, effectivePackagePatientCapacity(capacity)-occupied)
	remaining = &left
	return remaining, canRenew, canResume, nil
}

// A missing legacy value uses the same finite default as the editor.
func effectivePackagePatientCapacity(capacity *int) int {
	if capacity == nil {
		return 2
	}
	return *capacity
}

func (s *Store) PackagePatientAvailability(ctx context.Context, professionalID, patientID string) (remaining *int, canRenew, canResume bool, err error) {
	return packagePatientAvailability(ctx, s.db, professionalID, patientID, clock.Now())
}
