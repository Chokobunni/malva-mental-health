package store

import (
	"context"
	"os"
	"testing"
)

func TestMigration040RepairsOnlyProvenUntouchedSupply(t *testing.T) {
	_, db := openCareRescheduleTestStore(t)
	tx, err := db.BeginTx(context.Background(), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = tx.Rollback() }()
	for _, q := range []string{
		`CREATE TEMP TABLE e_prescriptions(id text PRIMARY KEY,status text) ON COMMIT DROP`,
		`CREATE TEMP TABLE e_prescription_items(id text,medication_id text,prescription_id text,current_stock integer) ON COMMIT DROP`,
		`CREATE TEMP TABLE medications(id text,patient_id text,source text,active bool,current_stock integer,created_at timestamptz,updated_at timestamptz) ON COMMIT DROP`,
		`ALTER TABLE e_prescriptions ADD COLUMN patient_id text`,
		`CREATE TEMP TABLE medication_logs(medication_id text,status text) ON COMMIT DROP`,
	} {
		if _, err := tx.Exec(q); err != nil {
			t.Fatal(err)
		}
	}
	for _, kind := range []string{"proven", "unknown", "edited", "consumed", "draft", "ambiguous"} {
		if _, err := tx.Exec(`INSERT INTO e_prescriptions VALUES($1,$2,'patient')`, kind, map[bool]string{true: "draft", false: "issued"}[kind == "draft"]); err != nil {
			t.Fatal(err)
		}
		if _, err := tx.Exec(`INSERT INTO medications VALUES($1,'patient','prescription',true,0,now(),now())`, kind); err != nil {
			t.Fatal(err)
		}
		qty := 30
		if kind == "unknown" {
			qty = 0
		}
		if _, err := tx.Exec(`INSERT INTO e_prescription_items VALUES($1,$1,$1,$2)`, kind, qty); err != nil {
			t.Fatal(err)
		}
		if kind == "edited" {
			if _, err := tx.Exec(`UPDATE medications SET updated_at=created_at+interval '1 second' WHERE id=$1`, kind); err != nil {
				t.Fatal(err)
			}
		}
		if kind == "consumed" {
			if _, err := tx.Exec(`INSERT INTO medication_logs VALUES($1,'taken')`, kind); err != nil {
				t.Fatal(err)
			}
		}
		if kind == "ambiguous" {
			if _, err := tx.Exec(`INSERT INTO e_prescription_items VALUES('duplicate',$1,$1,30)`, kind); err != nil {
				t.Fatal(err)
			}
		}
	}
	ddl, err := os.ReadFile("../../migrations/039_prescription_crud.sql")
	if err != nil {
		t.Fatal(err)
	}
	raw, err := os.ReadFile("../../migrations/040_prescription_known_supply_backfill.sql")
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ {
		if _, err := tx.Exec(string(ddl)); err != nil {
			t.Fatal(err)
		}
		if _, err := tx.Exec(string(raw)); err != nil {
			t.Fatal(err)
		}
	}
	rows, err := tx.Query(`SELECT id,current_stock FROM medications`)
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		if err := rows.Close(); err != nil {
			t.Errorf("close rows: %v", err)
		}
	}()
	for rows.Next() {
		var id string
		var qty int
		if err := rows.Scan(&id, &qty); err != nil {
			t.Fatal(err)
		}
		want := 0
		if id == "proven" {
			want = 30
		}
		if qty != want {
			t.Errorf("%s stock%d want%d", id, qty, want)
		}
	}
	if err := rows.Err(); err != nil {
		t.Fatal(err)
	}
}
