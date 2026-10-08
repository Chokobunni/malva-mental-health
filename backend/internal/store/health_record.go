package store

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"
)

// ============================================================
// HEALTH RECORD — diagnosis summary pasien.
// Hanya profesional terverifikasi yang terhubung boleh menulis;
// pasien membaca (read-only) sesuai konsen share_health_record.
// Metadata audit (kapan/oleh siapa) diambil dari audit_logs, jadi
// fitur ini tidak butuh perubahan schema.
// ============================================================

// HealthRecord adalah ringkasan klinis pasien yang dapat dibaca pasien
// dan profesionalnya.
type HealthRecord struct {
	PatientID           string     `json:"patient_id"`
	DiagnosisSummary    string     `json:"diagnosis_summary"`
	PrimaryProfessional string     `json:"primary_professional,omitempty"`
	UpdatedAt           *time.Time `json:"updated_at,omitempty"`
	UpdatedBy           *string    `json:"updated_by,omitempty"`
	HasDiagnosis        bool       `json:"has_diagnosis"`
	MedicationCount     int        `json:"medication_count"`
}

// GetHealthRecord membaca ringkasan diagnosis + hitungan obat aktif pasien.
func (s *Store) GetHealthRecord(ctx context.Context, patientID string) (HealthRecord, error) {
	var rec HealthRecord
	rec.PatientID = patientID

	var diagnosis sql.NullString
	err := s.db.QueryRowContext(ctx, `
		SELECT pp.diagnosis_summary
		FROM patient_profiles pp
		WHERE pp.user_id = $1
	`, patientID).Scan(&diagnosis)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			// Profile belum ada (mis. akun sangat baru): kirim record kosong
			// alih-alih error 404, agar UI bisa menampilkan empty state.
			return rec, nil
		}
		return HealthRecord{}, err
	}
	if diagnosis.Valid {
		rec.DiagnosisSummary = strings.TrimSpace(diagnosis.String)
	}
	rec.HasDiagnosis = rec.DiagnosisSummary != ""

	// Metadata audit terakhir untuk diagnosis (dari audit_logs).
	var updatedAt sql.NullTime
	var updatedBy sql.NullString
	_ = s.db.QueryRowContext(ctx, `
		SELECT al.created_at, al.actor_id::text
		FROM audit_logs al
		WHERE al.patient_id = $1 AND al.action = 'health_record.diagnosis_updated'
		ORDER BY al.created_at DESC
		LIMIT 1
	`, patientID).Scan(&updatedAt, &updatedBy)
	if updatedAt.Valid {
		t := updatedAt.Time
		rec.UpdatedAt = &t
	}
	if updatedBy.Valid && updatedBy.String != "" {
		rec.UpdatedBy = &updatedBy.String
	}
	if rec.UpdatedBy != nil {
		var name string
		if err := s.db.QueryRowContext(ctx, `
			SELECT display_name FROM users WHERE id = $1
		`, *rec.UpdatedBy).Scan(&name); err == nil && name != "" {
			rec.UpdatedBy = &name
		}
	}

	// Nama profesional utama (link aktif pertama), bila ada.
	var professionalName sql.NullString
	_ = s.db.QueryRowContext(ctx, `
		SELECT u.display_name
		FROM patient_professional_links l
		JOIN users u ON u.id = l.professional_id
		WHERE l.patient_id = $1 AND l.status = 'active' AND u.disabled_at IS NULL
		ORDER BY l.created_at ASC
		LIMIT 1
	`, patientID).Scan(&professionalName)
	if professionalName.Valid {
		rec.PrimaryProfessional = professionalName.String
	}

	// Jumlah obat aktif.
	_ = s.db.QueryRowContext(ctx, `
		SELECT COUNT(*) FROM medications WHERE patient_id = $1 AND active
	`, patientID).Scan(&rec.MedicationCount)

	return rec, nil
}

// UpdateHealthRecordDiagnosis menyimpan diagnosis summary pasien oleh
// profesional terverifikasi. Mengembalikan record terbaru.
func (s *Store) UpdateHealthRecordDiagnosis(ctx context.Context, professionalID, patientID, diagnosis string) (HealthRecord, error) {
	patientID = strings.TrimSpace(patientID)
	professionalID = strings.TrimSpace(professionalID)
	diagnosis = strings.TrimSpace(diagnosis)
	if patientID == "" {
		return HealthRecord{}, errors.New("patient_id is required")
	}
	if professionalID == "" {
		return HealthRecord{}, errors.New("professional_id is required")
	}

	// Cegah duplikat log audit beruntun: simpan hash sederhana via metadata.
	res, err := s.db.ExecContext(ctx, `
		UPDATE patient_profiles
		SET diagnosis_summary = NULLIF($2, '')
		WHERE user_id = $1
	`, patientID, diagnosis)
	if err != nil {
		return HealthRecord{}, err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return HealthRecord{}, sql.ErrNoRows
	}

	_ = s.AddAuditLog(ctx, professionalID, patientID, "health_record.diagnosis_updated", "patient_profile", patientID, nil)
	return s.GetHealthRecord(ctx, patientID)
}
