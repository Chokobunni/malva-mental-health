package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"

	"strings"
	"time"
)

type EPrescription struct {
	ID             string      `json:"id"`
	ProfessionalID string      `json:"professional_id"`
	PatientID      string      `json:"patient_id"`
	Diagnosis      string      `json:"diagnosis"`
	Notes          string      `json:"notes"`
	Instructions   string      `json:"instructions"`
	SignatureData  interface{} `json:"signature_data"`
	QRToken        string      `json:"qr_token"`
	Status         string      `json:"status"`
	CreatedAt      time.Time   `json:"created_at"`
}
type EPrescriptionItem struct {
	Schedule       json.RawMessage `json:"schedule"`
	CurrentStock   int             `json:"current_stock"`
	RemainingStock int             `json:"remaining_stock"`
	AlertBelow     int             `json:"alert_below"`
	ID             string          `json:"id"`
	PrescriptionID string          `json:"prescription_id"`
	MedicationID   *string         `json:"medication_id,omitempty"`
	Name           string          `json:"name"`
	Form           string          `json:"form"`
	Dosage         string          `json:"dosage"`
	Frequency      string          `json:"frequency"`
	Days           int             `json:"days"`
	UnitsPerDay    int             `json:"units_per_day"`
	Unit           string          `json:"unit"`
}
type EPrescriptionFull struct {
	EPrescription
	Items []EPrescriptionItem `json:"items"`
}

var ErrPrescriptionNotFound = errors.New("resep tidak ditemukan")
var ErrPrescriptionConflict = errors.New("item resep tidak valid atau pasien berbeda")

type prescriptionScanner interface{ Scan(...any) error }

const prescriptionColumns = `id,professional_id,patient_id,diagnosis,COALESCE(notes,''),COALESCE(instructions,''),signature_data,qr_token,status,created_at`
const prescriptionItemColumns = `i.id,i.prescription_id,i.medication_id,i.name,COALESCE(i.form,''),COALESCE(i.dosage,''),COALESCE(i.frequency,''),i.days,i.units_per_day,i.unit,i.schedule,i.current_stock,i.alert_below,COALESCE(m.current_stock,0)`

func scanPrescription(row prescriptionScanner) (EPrescription, error) {
	var rx EPrescription
	var sig []byte
	err := row.Scan(&rx.ID, &rx.ProfessionalID, &rx.PatientID, &rx.Diagnosis, &rx.Notes, &rx.Instructions, &sig, &rx.QRToken, &rx.Status, &rx.CreatedAt)
	if len(sig) > 0 {
		_ = json.Unmarshal(sig, &rx.SignatureData)
	}
	return rx, err
}
func scanPrescriptionItem(row prescriptionScanner) (EPrescriptionItem, error) {
	var i EPrescriptionItem
	err := row.Scan(&i.ID, &i.PrescriptionID, &i.MedicationID, &i.Name, &i.Form, &i.Dosage, &i.Frequency, &i.Days, &i.UnitsPerDay, &i.Unit, &i.Schedule, &i.CurrentStock, &i.AlertBelow, &i.RemainingStock)
	return i, err
}
func (s *Store) CreateEPrescription(ctx context.Context, rx EPrescription, items []EPrescriptionItem) (EPrescription, error) {
	return s.saveEPrescription(ctx, rx, items, false)
}
func (s *Store) UpdateEPrescription(ctx context.Context, rx EPrescription, items []EPrescriptionItem) (EPrescription, error) {
	return s.saveEPrescription(ctx, rx, items, true)
}
func (s *Store) saveEPrescription(ctx context.Context, rx EPrescription, items []EPrescriptionItem, update bool) (EPrescription, error) {
	if rx.Status == "" {
		rx.Status = "issued"
	}
	if rx.Status != "issued" && rx.Status != "draft" {
		return EPrescription{}, ErrPrescriptionConflict
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return EPrescription{}, err
	}
	defer func() { _ = tx.Rollback() }()
	previous := map[string]EPrescriptionItem{}
	var before json.RawMessage
	if update {
		old, err := scanPrescription(tx.QueryRowContext(ctx, `SELECT `+prescriptionColumns+` FROM e_prescriptions WHERE id=$1 AND professional_id=$2 AND status<>'deleted' FOR UPDATE`, rx.ID, rx.ProfessionalID))
		if errors.Is(err, sql.ErrNoRows) {
			return EPrescription{}, ErrPrescriptionNotFound
		}
		if err != nil {
			return EPrescription{}, err
		}
		if old.PatientID != rx.PatientID {
			return EPrescription{}, ErrPrescriptionConflict
		}
		rows, err := tx.QueryContext(ctx, `SELECT `+prescriptionItemColumns+` FROM e_prescription_items i LEFT JOIN medications m ON m.id=i.medication_id WHERE i.prescription_id=$1 AND i.active ORDER BY i.id`, rx.ID)
		if err != nil {
			return EPrescription{}, err
		}
		var oldItems []EPrescriptionItem
		for rows.Next() {
			i, err := scanPrescriptionItem(rows)
			if err != nil {
				_ = rows.Close()
				return EPrescription{}, err
			}
			previous[i.ID] = i
			oldItems = append(oldItems, i)
		}
		err = rows.Err()
		closeErr := rows.Close()
		if err == nil {
			err = closeErr
		}
		if err != nil {
			return EPrescription{}, err
		}
		before, _ = json.Marshal(EPrescriptionFull{EPrescription: old, Items: oldItems})
	}
	sig, _ := json.Marshal(rx.SignatureData)
	if rx.Status == "draft" {
		sig = []byte(`null`)
	}
	if update {
		_, err = tx.ExecContext(ctx, `UPDATE e_prescriptions SET diagnosis=$3,notes=$4,instructions=$5,signature_data=$6,qr_token=$7,status=$8 WHERE id=$1 AND professional_id=$2`, rx.ID, rx.ProfessionalID, rx.Diagnosis, rx.Notes, rx.Instructions, sig, rx.QRToken, rx.Status)
	} else {
		err = tx.QueryRowContext(ctx, `INSERT INTO e_prescriptions(professional_id,patient_id,diagnosis,notes,instructions,signature_data,qr_token,status) VALUES($1,$2,$3,$4,$5,$6,$7,$8) RETURNING id,created_at`, rx.ProfessionalID, rx.PatientID, rx.Diagnosis, rx.Notes, rx.Instructions, sig, rx.QRToken, rx.Status).Scan(&rx.ID, &rx.CreatedAt)
	}
	if err != nil {
		return EPrescription{}, err
	}
	seen := map[string]bool{}
	for _, item := range items {
		if item.ID != "" {
			if !update || seen[item.ID] {
				return EPrescription{}, ErrPrescriptionConflict
			}
			seen[item.ID] = true
		}
		old, exists := previous[item.ID]
		if item.ID != "" && !exists {
			return EPrescription{}, ErrPrescriptionConflict
		}
		if exists && item.MedicationID != nil && (old.MedicationID == nil || *item.MedicationID != *old.MedicationID) {
			return EPrescription{}, ErrPrescriptionConflict
		}
		schedule := item.Schedule
		if len(schedule) == 0 {
			schedule = json.RawMessage(`{}`)
		}
		var routine struct {
			Times        []string `json:"times"`
			Meal         string   `json:"relation_to_meal"`
			Instructions string   `json:"instructions"`
		}
		_ = json.Unmarshal(schedule, &routine)
		reminder := ""
		if len(routine.Times) > 0 {
			reminder = routine.Times[0]
		}
		meal := strings.TrimSpace(strings.TrimSpace(routine.Meal) + " " + strings.TrimSpace(routine.Instructions))
		if meal == "" {
			meal = rx.Instructions
		}
		medID := ""
		if exists && old.MedicationID != nil {
			medID = *old.MedicationID
		}
		if medID == "" {
			err = tx.QueryRowContext(ctx, `INSERT INTO medications(patient_id,name,dosage,form,reminder_time,relation_to_meal,current_stock,alert_below,source,schedule,active) VALUES($1,$2,$3,$4,$5,$6,$7,$8,'prescription',$9,$10) RETURNING id`, rx.PatientID, item.Name, item.Dosage, item.Form, reminder, meal, item.CurrentStock, item.AlertBelow, schedule, rx.Status == "issued").Scan(&medID)
		} else {
			// Delta supply preserves consumption and explicit patient stock adjustments.
			var result sql.Result
			result, err = tx.ExecContext(ctx, `UPDATE medications SET name=$3,dosage=$4,form=$5,reminder_time=$6,relation_to_meal=$7,current_stock=GREATEST(current_stock+$8,0),alert_below=$9,schedule=$10,active=$11,updated_at=now() WHERE id=$1 AND patient_id=$2`, medID, rx.PatientID, item.Name, item.Dosage, item.Form, reminder, meal, item.CurrentStock-old.CurrentStock, item.AlertBelow, schedule, rx.Status == "issued")
			if err == nil {
				n, _ := result.RowsAffected()
				if n != 1 {
					return EPrescription{}, ErrPrescriptionConflict
				}
			}
		}
		if err != nil {
			return EPrescription{}, err
		}
		if exists {
			_, err = tx.ExecContext(ctx, `UPDATE e_prescription_items SET name=$2,form=$3,dosage=$4,frequency=$5,days=$6,units_per_day=$7,unit=$8,schedule=$9,current_stock=$10,alert_below=$11,medication_id=$12 WHERE id=$1`, item.ID, item.Name, item.Form, item.Dosage, item.Frequency, item.Days, item.UnitsPerDay, item.Unit, schedule, item.CurrentStock, item.AlertBelow, medID)
		} else {
			_, err = tx.ExecContext(ctx, `INSERT INTO e_prescription_items(prescription_id,medication_id,name,form,dosage,frequency,days,units_per_day,unit,schedule,current_stock,alert_below) VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)`, rx.ID, medID, item.Name, item.Form, item.Dosage, item.Frequency, item.Days, item.UnitsPerDay, item.Unit, schedule, item.CurrentStock, item.AlertBelow)
		}
		if err != nil {
			return EPrescription{}, err
		}
	}
	for id, item := range previous {
		if !seen[id] {
			if item.MedicationID != nil {
				if _, err := tx.ExecContext(ctx, `UPDATE medications SET active=false,updated_at=now() WHERE id=$1 AND patient_id=$2`, *item.MedicationID, rx.PatientID); err != nil {
					return EPrescription{}, err
				}
			}
			if _, err := tx.ExecContext(ctx, `UPDATE e_prescription_items SET active=false WHERE id=$1`, id); err != nil {
				return EPrescription{}, err
			}
		}
	}
	metadata, _ := json.Marshal(map[string]any{"before": before, "status": rx.Status, "items_count": len(items)})
	if _, err := tx.ExecContext(ctx, `INSERT INTO audit_logs(actor_id,patient_id,action,entity_type,entity_id,metadata) VALUES($1,$2,$3,'e_prescriptions',$4,$5)`, rx.ProfessionalID, rx.PatientID, "eprescription.saved", rx.ID, metadata); err != nil {
		return EPrescription{}, err
	}
	if err := tx.Commit(); err != nil {
		return EPrescription{}, err
	}
	full, err := s.GetEPrescription(ctx, rx.ID)
	return full.EPrescription, err
}
func (s *Store) DeleteEPrescription(ctx context.Context, rxID, authorID, newQR string) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()
	rx, err := scanPrescription(tx.QueryRowContext(ctx, `SELECT `+prescriptionColumns+` FROM e_prescriptions WHERE id=$1 AND professional_id=$2 FOR UPDATE`, rxID, authorID))
	if errors.Is(err, sql.ErrNoRows) {
		return ErrPrescriptionNotFound
	}
	if err != nil {
		return err
	}
	if rx.Status == "deleted" {
		return tx.Commit()
	}
	if _, err = tx.ExecContext(ctx, `UPDATE medications SET active=false,updated_at=now() WHERE id IN (SELECT medication_id FROM e_prescription_items WHERE prescription_id=$1) AND patient_id=$2`, rxID, rx.PatientID); err != nil {
		return err
	}
	if _, err = tx.ExecContext(ctx, `UPDATE e_prescriptions SET status='deleted',signature_data=NULL,qr_token=$2 WHERE id=$1`, rxID, newQR); err != nil {
		return err
	}
	before, _ := json.Marshal(rx)
	if _, err = tx.ExecContext(ctx, `INSERT INTO audit_logs(actor_id,patient_id,action,entity_type,entity_id,metadata) VALUES($1,$2,'eprescription.deleted','e_prescriptions',$3,$4)`, authorID, rx.PatientID, rxID, before); err != nil {
		return err
	}
	return tx.Commit()
}
func (s *Store) GetEPrescription(ctx context.Context, id string) (EPrescriptionFull, error) {
	// Header status/token and item contents must belong to the same revision.
	// Otherwise an issued read can disclose items saved concurrently as a draft.
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelRepeatableRead, ReadOnly: true})
	if err != nil {
		return EPrescriptionFull{}, err
	}
	defer func() { _ = tx.Rollback() }()
	rx, err := scanPrescription(tx.QueryRowContext(ctx, `SELECT `+prescriptionColumns+` FROM e_prescriptions WHERE id=$1 AND status<>'deleted'`, id))
	if err != nil {
		return EPrescriptionFull{}, err
	}
	out := EPrescriptionFull{EPrescription: rx, Items: []EPrescriptionItem{}}
	rows, err := tx.QueryContext(ctx, `SELECT `+prescriptionItemColumns+` FROM e_prescription_items i LEFT JOIN medications m ON m.id=i.medication_id WHERE i.prescription_id=$1 AND i.active ORDER BY i.id`, id)
	if err != nil {
		return EPrescriptionFull{}, err
	}
	defer func() { _ = rows.Close() }()
	for rows.Next() {
		item, err := scanPrescriptionItem(rows)
		if err != nil {
			return EPrescriptionFull{}, err
		}
		out.Items = append(out.Items, item)
	}
	if err := rows.Err(); err != nil {
		return EPrescriptionFull{}, err
	}
	if err := rows.Close(); err != nil {
		return EPrescriptionFull{}, err
	}
	return out, tx.Commit()
}
func (s *Store) GetEPrescriptionByQR(ctx context.Context, token string) (EPrescriptionFull, error) {
	var id string
	err := s.db.QueryRowContext(ctx, `SELECT id FROM e_prescriptions WHERE qr_token=$1 AND status='issued'`, token).Scan(&id)
	if err != nil {
		return EPrescriptionFull{}, err
	}
	rx, err := s.GetEPrescription(ctx, id)
	if err == nil && (rx.QRToken != token || rx.Status != "issued") {
		return EPrescriptionFull{}, sql.ErrNoRows
	}
	return rx, err
}
func (s *Store) ListEPrescriptionsForUser(ctx context.Context, userID, role string) ([]EPrescriptionFull, error) {
	tx, err := s.db.BeginTx(ctx, &sql.TxOptions{Isolation: sql.LevelRepeatableRead, ReadOnly: true})
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback() }()
	filter := `patient_id=$1 AND status='issued'`
	if role == "professional" {
		filter = `professional_id=$1 AND status IN ('issued','draft')`
	}
	rows, err := tx.QueryContext(ctx, `SELECT `+prescriptionColumns+` FROM e_prescriptions WHERE `+filter+` ORDER BY created_at DESC LIMIT 100`, userID)
	if err != nil {
		return nil, err
	}
	out := make([]EPrescriptionFull, 0)
	args := []any{}
	holders := []string{}
	positions := map[string]int{}
	for rows.Next() {
		rx, err := scanPrescription(rows)
		if err != nil {
			_ = rows.Close()
			return nil, err
		}
		positions[rx.ID] = len(out)
		out = append(out, EPrescriptionFull{EPrescription: rx, Items: []EPrescriptionItem{}})
		args = append(args, rx.ID)
		holders = append(holders, fmt.Sprintf("$%d", len(args)))
	}
	err = rows.Err()
	closeErr := rows.Close()
	if err == nil {
		err = closeErr
	}
	if err != nil {
		return nil, err
	}
	if len(args) == 0 {
		return out, tx.Commit()
	}
	itemRows, err := tx.QueryContext(ctx, `SELECT `+prescriptionItemColumns+` FROM e_prescription_items i LEFT JOIN medications m ON m.id=i.medication_id WHERE i.active AND i.prescription_id IN (`+strings.Join(holders, ",")+`) ORDER BY i.id`, args...)
	if err != nil {
		return nil, err
	}
	defer func() { _ = itemRows.Close() }()
	for itemRows.Next() {
		item, err := scanPrescriptionItem(itemRows)
		if err != nil {
			return nil, err
		}
		idx := positions[item.PrescriptionID]
		out[idx].Items = append(out[idx].Items, item)
	}
	if err := itemRows.Err(); err != nil {
		return nil, err
	}
	if err := itemRows.Close(); err != nil {
		return nil, err
	}
	return out, tx.Commit()
}
func (s *Store) ListActiveEPrescriptionsForProfessionalPatients(ctx context.Context, professionalID string) ([]EPrescription, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT `+prescriptionColumns+` FROM e_prescriptions WHERE professional_id=$1 AND status='issued' ORDER BY created_at DESC`, professionalID)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var out []EPrescription
	for rows.Next() {
		rx, err := scanPrescription(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, rx)
	}
	return out, rows.Err()
}

// AddDoctorReview menyimpan ulasan (bentuk lama, dipertahankan untuk kompatibilitas).
func (s *Store) AddDoctorReview(ctx context.Context, r DoctorReview) error {
	stars := r.Stars
	if stars <= 0 {
		stars = 5
	}
	_, err := s.CreateDoctorReview(ctx, r.ProfessionalID, r.PatientID, stars, r.ReviewText, r.Helpful)
	return err
}
