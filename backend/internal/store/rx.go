package store

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// ============================================================
// E-PRESCRIPTION (psikiater verified only)
// ============================================================

type EPrescription struct {
	ID             string      `json:"id"`
	ProfessionalID string      `json:"professional_id"`
	PatientID      string      `json:"patient_id"`
	Notes          string      `json:"notes"`
	Instructions   string      `json:"instructions"`
	SignatureData  interface{} `json:"signature_data"`
	QRToken        string      `json:"qr_token"`
	Status         string      `json:"status"`
	CreatedAt      time.Time   `json:"created_at"`
}

type EPrescriptionItem struct {
	ID             string  `json:"id"`
	PrescriptionID string  `json:"prescription_id"`
	MedicationID   *string `json:"medication_id,omitempty"`
	Name           string  `json:"name"`
	Form           string  `json:"form"`
	Dosage         string  `json:"dosage"`
	Frequency      string  `json:"frequency"`
	Days           int     `json:"days"`
	UnitsPerDay    int     `json:"units_per_day"`
	Unit           string  `json:"unit"`
}

type EPrescriptionFull struct {
	EPrescription
	Items []EPrescriptionItem `json:"items"`
}

func (s *Store) CreateEPrescription(ctx context.Context, rx EPrescription, items []EPrescriptionItem) (EPrescription, error) {
	ptx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return EPrescription{}, err
	}
	defer func() { _ = ptx.Rollback() }()

	sig, _ := json.Marshal(rx.SignatureData)
	const q = `INSERT INTO e_prescriptions (professional_id, patient_id, notes, instructions, signature_data, qr_token, status)
		VALUES ($1, $2, $3, $4, $5, $6, 'issued')
		RETURNING id, status, created_at`
	err = ptx.QueryRowContext(ctx, q, rx.ProfessionalID, rx.PatientID, rx.Notes, rx.Instructions, sig, rx.QRToken).
		Scan(&rx.ID, &rx.Status, &rx.CreatedAt)
	if err != nil {
		return EPrescription{}, err
	}

	for _, item := range items {
		const qi = `INSERT INTO e_prescription_items
			(prescription_id, medication_id, name, form, dosage, frequency, days, units_per_day, unit)
			VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`
		if _, err := ptx.ExecContext(ctx, qi, rx.ID, item.MedicationID, item.Name, item.Form, item.Dosage,
			item.Frequency, item.Days, item.UnitsPerDay, item.Unit); err != nil {
			return EPrescription{}, err
		}
	}

	if err := ptx.Commit(); err != nil {
		return EPrescription{}, err
	}
	_ = s.AddAuditLog(ctx, rx.ProfessionalID, rx.PatientID, "eprescription.issued", "e_prescriptions", rx.ID,
		map[string]any{"items_count": len(items)})
	return rx, nil
}

func (s *Store) GetEPrescriptionByQR(ctx context.Context, qrToken string) (EPrescriptionFull, error) {
	const q = `SELECT id, professional_id, patient_id, notes, instructions, signature_data, qr_token, status, created_at
		FROM e_prescriptions WHERE qr_token = $1`
	var rx EPrescriptionFull
	var sig []byte
	err := s.db.QueryRowContext(ctx, q, qrToken).
		Scan(&rx.ID, &rx.ProfessionalID, &rx.PatientID, &rx.Notes, &rx.Instructions, &sig, &rx.QRToken, &rx.Status, &rx.CreatedAt)
	if err != nil {
		return EPrescriptionFull{}, err
	}
	_ = json.Unmarshal(sig, &rx.SignatureData)

	const qi = `SELECT id, prescription_id, medication_id, name, form, dosage, frequency, days, units_per_day, unit
		FROM e_prescription_items WHERE prescription_id = $1 ORDER BY name`
	rows, err := s.db.QueryContext(ctx, qi, rx.ID)
	if err != nil {
		return EPrescriptionFull{}, err
	}
	defer func() { _ = rows.Close() }()
	for rows.Next() {
		var item EPrescriptionItem
		if err := rows.Scan(&item.ID, &item.PrescriptionID, &item.MedicationID, &item.Name, &item.Form, &item.Dosage,
			&item.Frequency, &item.Days, &item.UnitsPerDay, &item.Unit); err != nil {
			return EPrescriptionFull{}, err
		}
		rx.Items = append(rx.Items, item)
	}
	return rx, rows.Err()
}

func (s *Store) GetEPrescription(ctx context.Context, rxID string) (EPrescriptionFull, error) {
	const q = `SELECT id, professional_id, patient_id, notes, instructions, signature_data, qr_token, status, created_at
		FROM e_prescriptions WHERE id = $1`
	var rx EPrescriptionFull
	var sig []byte
	err := s.db.QueryRowContext(ctx, q, rxID).
		Scan(&rx.ID, &rx.ProfessionalID, &rx.PatientID, &rx.Notes, &rx.Instructions, &sig, &rx.QRToken, &rx.Status, &rx.CreatedAt)
	if err != nil {
		return EPrescriptionFull{}, err
	}
	_ = json.Unmarshal(sig, &rx.SignatureData)

	const qi = `SELECT id, prescription_id, medication_id, name, form, dosage, frequency, days, units_per_day, unit
		FROM e_prescription_items WHERE prescription_id = $1 ORDER BY name`
	rows, err := s.db.QueryContext(ctx, qi, rxID)
	if err != nil {
		return EPrescriptionFull{}, err
	}
	defer func() { _ = rows.Close() }()
	for rows.Next() {
		var item EPrescriptionItem
		if err := rows.Scan(&item.ID, &item.PrescriptionID, &item.MedicationID, &item.Name, &item.Form, &item.Dosage,
			&item.Frequency, &item.Days, &item.UnitsPerDay, &item.Unit); err != nil {
			return EPrescriptionFull{}, err
		}
		rx.Items = append(rx.Items, item)
	}
	return rx, rows.Err()
}

// ListEPrescriptionsForUser mengembalikan resep milik user BESERTA item obatnya.
//
// Sebelumnya fungsi ini hanya mengembalikan kepala resep tanpa item, sehingga
// aplikasi selalu menampilkan "0 item obat" pada setiap kartu resep di daftar
// (detail resep tidak terpengaruh karena memakai GetEPrescription).
func (s *Store) ListEPrescriptionsForUser(ctx context.Context, userID, role string) ([]EPrescriptionFull, error) {
	var q string
	var args []interface{}
	if role == "professional" {
		q = `SELECT id, professional_id, patient_id, notes, instructions, signature_data, qr_token, status, created_at
			FROM e_prescriptions WHERE professional_id = $1 ORDER BY created_at DESC LIMIT 100`
		args = []interface{}{userID}
	} else {
		q = `SELECT id, professional_id, patient_id, notes, instructions, signature_data, qr_token, status, created_at
			FROM e_prescriptions WHERE patient_id = $1 ORDER BY created_at DESC LIMIT 100`
		args = []interface{}{userID}
	}
	rows, err := s.db.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	var out []EPrescriptionFull
	for rows.Next() {
		var rx EPrescription
		var sig []byte
		if err := rows.Scan(&rx.ID, &rx.ProfessionalID, &rx.PatientID, &rx.Notes, &rx.Instructions, &sig, &rx.QRToken, &rx.Status, &rx.CreatedAt); err != nil {
			_ = rows.Close()
			return nil, err
		}
		_ = json.Unmarshal(sig, &rx.SignatureData)
		out = append(out, EPrescriptionFull{EPrescription: rx, Items: []EPrescriptionItem{}})
	}
	if err := rows.Err(); err != nil {
		_ = rows.Close()
		return nil, err
	}
	// Tutup sebelum query kedua: pool bisa punya koneksi terbatas.
	if err := rows.Close(); err != nil {
		return nil, err
	}
	if len(out) == 0 {
		return out, nil
	}

	// Satu query untuk item semua resep (bukan satu query per resep).
	holders := make([]string, len(out))
	itemArgs := make([]interface{}, len(out))
	positions := make(map[string]int, len(out))
	for i := range out {
		holders[i] = fmt.Sprintf("$%d", i+1)
		itemArgs[i] = out[i].ID
		positions[out[i].ID] = i
	}
	itemQuery := fmt.Sprintf(`SELECT prescription_id, id, medication_id, name, form, dosage, frequency, days, units_per_day, unit
		FROM e_prescription_items WHERE prescription_id IN (%s) ORDER BY name`,
		strings.Join(holders, ","))
	itemRows, err := s.db.QueryContext(ctx, itemQuery, itemArgs...)
	if err != nil {
		return nil, err
	}
	defer func() { _ = itemRows.Close() }()
	for itemRows.Next() {
		var item EPrescriptionItem
		if err := itemRows.Scan(&item.PrescriptionID, &item.ID, &item.MedicationID, &item.Name, &item.Form,
			&item.Dosage, &item.Frequency, &item.Days, &item.UnitsPerDay, &item.Unit); err != nil {
			return nil, err
		}
		if idx, ok := positions[item.PrescriptionID]; ok {
			out[idx].Items = append(out[idx].Items, item)
		}
	}
	return out, itemRows.Err()
}

func (s *Store) ListActiveEPrescriptionsForProfessionalPatients(ctx context.Context, professionalID string) ([]EPrescription, error) {
	const q = `SELECT id, professional_id, patient_id, notes, instructions, signature_data, qr_token, status, created_at
		FROM e_prescriptions
		WHERE professional_id = $1 AND status = 'issued'
		ORDER BY created_at DESC`
	rows, err := s.db.QueryContext(ctx, q, professionalID)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var out []EPrescription
	for rows.Next() {
		var rx EPrescription
		var sig []byte
		if err := rows.Scan(&rx.ID, &rx.ProfessionalID, &rx.PatientID, &rx.Notes, &rx.Instructions, &sig, &rx.QRToken, &rx.Status, &rx.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, rx)
	}
	return out, rows.Err()
}

// AddDoctorReview menyimpan ulasan (bentuk lama, dipertahankan untuk kompatibilitas).
func (s *Store) AddDoctorReview(ctx context.Context, r DoctorReview) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	pct := r.Stars * 20
	if pct <= 0 {
		pct = 100
	}
	const q = `INSERT INTO doctor_reviews (professional_id, patient_id, helpfulness_percent, review_text, helpful)
		VALUES ($1, $2, $3, $4, $5)`
	if _, err := tx.ExecContext(ctx, q, r.ProfessionalID, r.PatientID, pct, r.ReviewText, r.Helpful); err != nil {
		return err
	}

	if r.Helpful {
		if _, err := tx.ExecContext(ctx,
			`UPDATE professional_credentials SET helpfulness_count = helpfulness_count + 1 WHERE user_id = $1`,
			r.ProfessionalID); err != nil {
			return err
		}
	}
	if _, err := tx.ExecContext(ctx,
		`UPDATE professional_credentials SET review_count = review_count + 1 WHERE user_id = $1`,
		r.ProfessionalID); err != nil {
		return err
	}

	return tx.Commit()
}
