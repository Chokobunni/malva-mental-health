package store

import (
	"context"
	"database/sql"
	"errors"
	"slices"
	"time"

	"malva/backend/internal/clock"
)

var (
	ErrCheckoutSlotResolved = errors.New("slot paket sudah diproses")
	ErrCareSlotTaken        = errors.New("slot sudah terisi, pilih jam lain")
	ErrCarePackageInactive  = errors.New("paket tidak aktif, tidak bisa menjadwalkan sesi")
	ErrCarePackageExpired   = errors.New("sesi harus dijadwalkan sebelum paket kedaluwarsa")
	ErrCarePackageExhausted = errors.New("sisa sesi paket sudah habis")
)

type PackageCheckoutSlot struct {
	ID              string
	ScheduledAt     time.Time
	DurationMinutes int
	Resolved        bool
	Missed          bool
}

func listPackageCheckoutSlots(ctx context.Context, db interface {
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
}, bookingID string) ([]PackageCheckoutSlot, error) {
	rows, err := db.QueryContext(ctx, `SELECT id, scheduled_at, duration_minutes,
		resolved_at IS NOT NULL, resolved_at IS NOT NULL AND session_id IS NULL
		FROM package_checkout_slots WHERE booking_id=$1 ORDER BY scheduled_at`, bookingID)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var slots []PackageCheckoutSlot
	for rows.Next() {
		var slot PackageCheckoutSlot
		if err := rows.Scan(&slot.ID, &slot.ScheduledAt, &slot.DurationMinutes, &slot.Resolved, &slot.Missed); err != nil {
			return nil, err
		}
		slots = append(slots, slot)
	}
	return slots, rows.Err()
}

func (s *Store) ListPackageCheckoutSlots(ctx context.Context, bookingID string) ([]PackageCheckoutSlot, error) {
	return listPackageCheckoutSlots(ctx, s.db, bookingID)
}

func (s *Store) SkipPackageCheckoutSlot(ctx context.Context, id string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE package_checkout_slots SET resolved_at=$2
		WHERE id=$1 AND resolved_at IS NULL`, id, clock.Now())
	return err
}

func persistPackageCheckoutSlots(ctx context.Context, tx *sql.Tx, bookingID string, replay bool, slots []PackageCheckoutSlot) error {
	if slots == nil {
		return nil
	}
	if replay {
		existing, err := listPackageCheckoutSlots(ctx, tx, bookingID)
		if err != nil {
			return err
		}
		if !slices.EqualFunc(existing, slots, func(a, b PackageCheckoutSlot) bool {
			return a.ScheduledAt.Equal(b.ScheduledAt) && a.DurationMinutes == b.DurationMinutes
		}) {
			return ErrPurchaseConflict
		}
		return nil
	}
	for _, slot := range slots {
		if _, err := tx.ExecContext(ctx, `INSERT INTO package_checkout_slots
			(booking_id,scheduled_at,duration_minutes) VALUES ($1,$2,$3)`,
			bookingID, slot.ScheduledAt, slot.DurationMinutes); err != nil {
			return err
		}
	}
	return nil
}
