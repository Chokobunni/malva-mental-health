package store

import (
	"database/sql"
	"os"
	"path/filepath"
	"testing"
)

func TestMigration034RestoreCanonicalPracticeCoordinates(t *testing.T) {
	db, ctx := openMigrationTestDB(t)
	content, err := os.ReadFile(filepath.Join("..", "..", "migrations", "034_restore_canonical_practice_coordinates.sql"))
	if err != nil {
		t.Fatal(err)
	}
	const canonicalID = "a1111111-1111-4111-8111-111111111111"
	const otherID = "b1111111-1111-4111-8111-111111111111"
	const clinic = "RSI Jemursari Surabaya"
	const address = "Jl. Raya Jemursari No. 51-57, Surabaya"
	coordinate := func(value float64) sql.NullFloat64 {
		return sql.NullFloat64{Float64: value, Valid: true}
	}
	for _, tc := range []struct {
		name, hospital, address string
		lat, lng                sql.NullFloat64
		restore                 bool
	}{
		{name: "changed email still restores canonical clinic", hospital: clinic, address: address, restore: true},
		{name: "custom coordinates preserved", hospital: clinic, address: address, lat: coordinate(-7.31), lng: coordinate(112.73)},
		{name: "existing latitude preserved", hospital: clinic, address: address, lat: coordinate(-7.31)},
		{name: "existing longitude preserved", hospital: clinic, address: address, lng: coordinate(112.73)},
		{name: "moved clinic preserved", hospital: "Another clinic", address: address},
		{name: "changed address preserved", hospital: clinic, address: "Another address"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			tx, err := db.BeginTx(ctx, nil)
			if err != nil {
				t.Fatal(err)
			}
			defer tx.Rollback()
			// Temporary tables isolate the migration from real seeded credentials.
			if _, err := tx.ExecContext(ctx, `
				CREATE TEMP TABLE users (id uuid PRIMARY KEY, email text) ON COMMIT DROP;
				CREATE TEMP TABLE professional_credentials (
					user_id uuid PRIMARY KEY, hospital_name text, address_details text,
					hospital_lat double precision, hospital_lng double precision
				) ON COMMIT DROP;
			`); err != nil {
				t.Fatal(err)
			}
			if _, err := tx.ExecContext(ctx, `INSERT INTO users (id, email)
				VALUES ($1, 'changed-login@example.invalid'), ($2, 'other@example.invalid')`, canonicalID, otherID); err != nil {
				t.Fatal(err)
			}
			if _, err := tx.ExecContext(ctx, `INSERT INTO professional_credentials
				(user_id, hospital_name, address_details, hospital_lat, hospital_lng)
				VALUES ($1, $2, $3, $4, $5), ($6, $7, $8, NULL, NULL)`,
				canonicalID, tc.hospital, tc.address, tc.lat, tc.lng, otherID, clinic, address); err != nil {
				t.Fatal(err)
			}
			wantLat, wantLng := tc.lat, tc.lng
			if tc.restore {
				wantLat, wantLng = coordinate(-7.3197), coordinate(112.7378)
			}
			for iteration := 1; iteration <= 2; iteration++ {
				if _, err := tx.ExecContext(ctx, string(content)); err != nil {
					t.Fatalf("apply migration iteration %d: %v", iteration, err)
				}
				var lat, lng sql.NullFloat64
				if err := tx.QueryRowContext(ctx, `SELECT hospital_lat, hospital_lng
					FROM professional_credentials WHERE user_id = $1`, canonicalID).Scan(&lat, &lng); err != nil {
					t.Fatal(err)
				}
				if lat != wantLat || lng != wantLng {
					t.Errorf("iteration %d coordinates = (%v, %v), want (%v, %v)", iteration, lat, lng, wantLat, wantLng)
				}
				if err := tx.QueryRowContext(ctx, `SELECT hospital_lat, hospital_lng
					FROM professional_credentials WHERE user_id = $1`, otherID).Scan(&lat, &lng); err != nil {
					t.Fatal(err)
				}
				if lat.Valid || lng.Valid {
					t.Errorf("iteration %d modified a different professional", iteration)
				}
			}
		})
	}
}
