package store

import (
	"context"
	"database/sql"
	"errors"
	"time"

	"malva/backend/internal/clock"
)

type ClinicalAllergy struct {
	ID           string    `json:"id"`
	ReactionType string    `json:"reaction_type"`
	Substance    string    `json:"substance"`
	Symptoms     string    `json:"symptoms"`
	Severity     string    `json:"severity"`
	OccurredWhen string    `json:"occurred_when"`
	ReportedBy   string    `json:"reported_by"`
	CreatedAt    time.Time `json:"created_at"`
}

const clinicalAllergyColumns = `id,reaction_type,substance,symptoms,severity,occurred_when,reported_by,created_at`

func scanClinicalAllergy(row interface{ Scan(...any) error }) (ClinicalAllergy, error) {
	var item ClinicalAllergy
	err := row.Scan(&item.ID, &item.ReactionType, &item.Substance, &item.Symptoms,
		&item.Severity, &item.OccurredWhen, &item.ReportedBy, &item.CreatedAt)
	item.CreatedAt = item.CreatedAt.In(clock.Location())
	return item, err
}

func (s *Store) ListClinicalAllergies(ctx context.Context, patientID string) ([]ClinicalAllergy, error) {
	rows, err := s.db.QueryContext(ctx, `SELECT `+clinicalAllergyColumns+`
		FROM clinical_allergies WHERE patient_id=$1 ORDER BY created_at DESC,id DESC`, patientID)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	items := make([]ClinicalAllergy, 0)
	for rows.Next() {
		item, err := scanClinicalAllergy(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

var ErrClinicalAllergyRetryConflict = errors.New("catatan berbeda untuk permintaan yang sama")

func (s *Store) CreateClinicalAllergy(ctx context.Context, patientID string, item ClinicalAllergy) (ClinicalAllergy, error) {
	created, err := scanClinicalAllergy(s.db.QueryRowContext(ctx, `INSERT INTO clinical_allergies
		(id,patient_id,reaction_type,substance,symptoms,severity,occurred_when,reported_by,created_at)
		VALUES(COALESCE(NULLIF($1,'')::uuid,gen_random_uuid()),$2,$3,$4,$5,$6,$7,'patient',$8)
		ON CONFLICT(id) DO UPDATE SET id=EXCLUDED.id
		WHERE clinical_allergies.patient_id=EXCLUDED.patient_id
		  AND clinical_allergies.reaction_type=EXCLUDED.reaction_type
		  AND clinical_allergies.substance=EXCLUDED.substance
		  AND clinical_allergies.symptoms=EXCLUDED.symptoms
		  AND clinical_allergies.severity=EXCLUDED.severity
		  AND clinical_allergies.occurred_when=EXCLUDED.occurred_when
		  AND clinical_allergies.reported_by=EXCLUDED.reported_by
		RETURNING `+clinicalAllergyColumns, item.ID, patientID, item.ReactionType, item.Substance,
		item.Symptoms, item.Severity, item.OccurredWhen, clock.Now()))
	if errors.Is(err, sql.ErrNoRows) {
		return ClinicalAllergy{}, ErrClinicalAllergyRetryConflict
	}
	return created, err
}
