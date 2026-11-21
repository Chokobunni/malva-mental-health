package store

import (
	"context"
	"database/sql"
	"errors"

	"malva/backend/internal/clock"
)

type DiaryRecipient struct {
	ProfessionalID string `json:"professional_id"`
	DisplayName    string `json:"display_name"`
}

type DiaryAccess struct {
	Recipients []DiaryRecipient `json:"recipients"`
	Eligible   []DiaryRecipient `json:"eligible"`
}

var ErrDiaryRecipientIneligible = errors.New("profesional tidak terhubung dengan pasien")

const diaryLinkedProfessionals = `patient_professional_links l
	JOIN users p ON p.id = l.professional_id`

const diaryActiveLink = `l.status = 'active' AND p.role = 'professional' AND p.disabled_at IS NULL`

// Preserve the category consent and care window used by broad diary shares.
const diaryLegacyAccess = `EXISTS (
	SELECT 1 FROM patient_data_consents c
	WHERE c.patient_id = l.patient_id AND c.professional_id = l.professional_id
	AND c.share_mood_diary
) AND (
	EXISTS (SELECT 1 FROM care_packages cp
		WHERE cp.patient_id = l.patient_id AND cp.professional_id = l.professional_id
		AND cp.status = 'active' AND cp.expires_at > $3)
	OR EXISTS (SELECT 1 FROM care_sessions cs
		WHERE cs.patient_id = l.patient_id AND cs.professional_id = l.professional_id
		AND cs.status = 'scheduled' AND cs.scheduled_at <= $3
		AND cs.scheduled_at + make_interval(mins => cs.duration_minutes) > $3)
)`

// The caller supplies the prospective reader as $2 and the current time as $3.
const diaryProfessionalAccess = `EXISTS (
	SELECT 1 FROM ` + diaryLinkedProfessionals + `
	LEFT JOIN diary_recipients r ON r.diary_id = d.id AND r.professional_id = l.professional_id
	WHERE l.patient_id = d.patient_id AND l.professional_id = $2 AND ` + diaryActiveLink + `
	AND (
		(r.professional_id IS NOT NULL AND NOT r.requires_legacy_consent)
		OR ((d.shared_with_professionals OR r.requires_legacy_consent) AND ` + diaryLegacyAccess + `)
	)
)`

const diarySelect = `SELECT d.id, d.patient_id, d.mood, d.title, d.note,
	d.shared_with_professionals, d.professional_feedback, d.occurred_at, d.created_at, d.updated_at
	FROM diary_entries d WHERE d.deleted_at IS NULL`

func scanDiaryEntry(row interface{ Scan(...any) error }) (DiaryEntry, error) {
	var diary DiaryEntry
	var feedback sql.NullString
	if err := row.Scan(&diary.ID, &diary.PatientID, &diary.Mood, &diary.Title, &diary.Note,
		&diary.SharedWithProfessionals, &feedback, &diary.OccurredAt, &diary.CreatedAt, &diary.UpdatedAt); err != nil {
		return DiaryEntry{}, err
	}
	diary.ProfessionalFeedback = feedback.String
	return diary, nil
}

func (s *Store) GetDiaryEntry(ctx context.Context, patientID, diaryID string) (DiaryEntry, error) {
	return scanDiaryEntry(s.db.QueryRowContext(ctx, diarySelect+`
		AND d.id = $1 AND d.patient_id = $2`, diaryID, patientID))
}

func (s *Store) GetDiaryEntryForProfessional(ctx context.Context, professionalID, diaryID string) (DiaryEntry, error) {
	return scanDiaryEntry(s.db.QueryRowContext(ctx, diarySelect+`
		AND d.id = $1 AND `+diaryProfessionalAccess, diaryID, professionalID, clock.Now()))
}

func (s *Store) ListDiaryEntriesForProfessional(ctx context.Context, patientID, professionalID string, limit int) ([]DiaryEntry, error) {
	rows, err := s.db.QueryContext(ctx, diarySelect+`
		AND d.patient_id = $1 AND `+diaryProfessionalAccess+`
		ORDER BY d.occurred_at DESC LIMIT $4`, patientID, professionalID, clock.Now(), historyQueryLimit(limit))
	if err != nil {
		return nil, err
	}
	return scanDiaryEntries(rows)
}

func scanDiaryEntries(rows *sql.Rows) ([]DiaryEntry, error) {
	defer func() { _ = rows.Close() }()
	items := make([]DiaryEntry, 0)
	for rows.Next() {
		item, err := scanDiaryEntry(rows)
		if err != nil {
			return nil, err
		}
		items = append(items, item)
	}
	return items, rows.Err()
}

type diaryAccessQueries interface {
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
}

func (s *Store) ListDiaryRecipients(ctx context.Context, patientID string, diaryIDs []string) (map[string][]DiaryRecipient, error) {
	return listDiaryRecipients(ctx, s.db, patientID, diaryIDs)
}

func listDiaryRecipients(ctx context.Context, queries diaryAccessQueries, patientID string, diaryIDs []string) (map[string][]DiaryRecipient, error) {
	byDiary := make(map[string][]DiaryRecipient)
	if len(diaryIDs) == 0 {
		return byDiary, nil
	}
	rows, err := queries.QueryContext(ctx, `
		SELECT d.id, u.id, u.display_name
		FROM diary_entries d
		JOIN LATERAL (
			SELECT r.professional_id FROM diary_recipients r WHERE r.diary_id = d.id
			UNION
			SELECT l.professional_id FROM `+diaryLinkedProfessionals+`
			WHERE l.patient_id = d.patient_id AND d.shared_with_professionals
			AND `+diaryActiveLink+` AND `+diaryLegacyAccess+`
		) AS recipients ON true
		JOIN users u ON u.id = recipients.professional_id
		WHERE d.patient_id = $1 AND d.id = ANY($2::uuid[]) AND d.deleted_at IS NULL
		ORDER BY u.display_name, u.id`, patientID, diaryIDs, clock.Now())
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	for rows.Next() {
		var id string
		var recipient DiaryRecipient
		if err := rows.Scan(&id, &recipient.ProfessionalID, &recipient.DisplayName); err != nil {
			return nil, err
		}
		byDiary[id] = append(byDiary[id], recipient)
	}
	return byDiary, rows.Err()
}

func (s *Store) GetDiaryAccess(ctx context.Context, patientID, diaryID string) (DiaryAccess, error) {
	var exists bool
	if err := s.db.QueryRowContext(ctx, `SELECT true FROM diary_entries
		WHERE patient_id = $1 AND id = $2 AND deleted_at IS NULL`, patientID, diaryID).Scan(&exists); err != nil {
		return DiaryAccess{}, err
	}
	return getDiaryAccess(ctx, s.db, patientID, diaryID)
}

func getDiaryAccess(ctx context.Context, queries diaryAccessQueries, patientID, diaryID string) (DiaryAccess, error) {
	recipients, err := listDiaryRecipients(ctx, queries, patientID, []string{diaryID})
	if err != nil {
		return DiaryAccess{}, err
	}
	rows, err := queries.QueryContext(ctx, `SELECT l.professional_id, p.display_name
		FROM `+diaryLinkedProfessionals+`
		WHERE l.patient_id = $1 AND `+diaryActiveLink+`
		ORDER BY p.display_name, l.professional_id`, patientID)
	if err != nil {
		return DiaryAccess{}, err
	}
	defer func() { _ = rows.Close() }()
	access := DiaryAccess{
		Recipients: append([]DiaryRecipient{}, recipients[diaryID]...),
		Eligible:   make([]DiaryRecipient, 0),
	}
	for rows.Next() {
		var recipient DiaryRecipient
		if err := rows.Scan(&recipient.ProfessionalID, &recipient.DisplayName); err != nil {
			return DiaryAccess{}, err
		}
		access.Eligible = append(access.Eligible, recipient)
	}
	return access, rows.Err()
}

func (s *Store) SetDiaryRecipient(ctx context.Context, patientID, diaryID, professionalID string, grant bool) (DiaryAccess, bool, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return DiaryAccess{}, false, err
	}
	defer func() { _ = tx.Rollback() }()

	var legacy bool
	if err := tx.QueryRowContext(ctx, `SELECT shared_with_professionals FROM diary_entries
		WHERE patient_id = $1 AND id = $2 AND deleted_at IS NULL FOR UPDATE`, patientID, diaryID).Scan(&legacy); err != nil {
		return DiaryAccess{}, false, err
	}
	if grant {
		var eligible bool
		err := tx.QueryRowContext(ctx, `SELECT EXISTS (
			SELECT 1 FROM `+diaryLinkedProfessionals+`
			WHERE l.patient_id = $1 AND l.professional_id = $2 AND `+diaryActiveLink+`
		)`, patientID, professionalID).Scan(&eligible)
		if err != nil {
			return DiaryAccess{}, false, err
		}
		if !eligible {
			return DiaryAccess{}, false, ErrDiaryRecipientIneligible
		}
	}
	if legacy {
		// Keep each inherited reader subject to the previous consent and care window.
		if _, err := tx.ExecContext(ctx, `
			INSERT INTO diary_recipients (diary_id, professional_id, requires_legacy_consent)
			SELECT $2, l.professional_id, true FROM `+diaryLinkedProfessionals+`
			WHERE l.patient_id = $1 AND `+diaryActiveLink+` AND `+diaryLegacyAccess+`
			ON CONFLICT (diary_id, professional_id) DO NOTHING`, patientID, diaryID, clock.Now()); err != nil {
			return DiaryAccess{}, false, err
		}
		if _, err := tx.ExecContext(ctx, `
			UPDATE diary_entries SET shared_with_professionals = false WHERE id = $1`, diaryID); err != nil {
			return DiaryAccess{}, false, err
		}
	}

	var result sql.Result
	if grant {
		result, err = tx.ExecContext(ctx, `
			INSERT INTO diary_recipients (diary_id, professional_id) VALUES ($1, $2)
			ON CONFLICT (diary_id, professional_id) DO UPDATE SET requires_legacy_consent = false
			WHERE diary_recipients.requires_legacy_consent`, diaryID, professionalID)
	} else {
		result, err = tx.ExecContext(ctx, `
			DELETE FROM diary_recipients WHERE diary_id = $1 AND professional_id = $2`, diaryID, professionalID)
	}
	if err != nil {
		return DiaryAccess{}, false, err
	}
	changed, err := result.RowsAffected()
	if err != nil {
		return DiaryAccess{}, false, err
	}
	access, err := getDiaryAccess(ctx, tx, patientID, diaryID)
	if err != nil {
		return DiaryAccess{}, false, err
	}
	if err := tx.Commit(); err != nil {
		return DiaryAccess{}, false, err
	}
	if changed > 0 {
		action := "diary.access_revoked"
		if grant {
			action = "diary.access_granted"
		}
		_ = s.AddAuditLog(ctx, patientID, patientID, action, "diary_entry", diaryID, nil)
	}
	return access, changed > 0, nil
}
