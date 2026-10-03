package store

import (
	"context"
	"errors"
	"fmt"
	"time"
)

// ============================================================
// SAFETY: Emergency Contacts, Crisis Incidents, SOS Blast
// ============================================================

type EmergencyContact struct {
	ID           string `json:"id"`
	PatientID    string `json:"patient_id"`
	ContactName  string `json:"contact_name"`
	ContactPhone string `json:"contact_phone"`
	Relationship string `json:"relationship"`
	IsDefault    bool   `json:"is_default"`
}

type CrisisIncident struct {
	ID               string     `json:"id"`
	PatientID        string     `json:"patient_id"`
	TriggeredBy      string     `json:"triggered_by"`
	PHQ9Q9Score      *int       `json:"phq9_q9_score,omitempty"`
	Latitude         *float64   `json:"latitude,omitempty"`
	Longitude        *float64   `json:"longitude,omitempty"`
	Status           string     `json:"status"`
	ResolutionNotes  string     `json:"resolution_notes"`
	ResponsibleBy    string     `json:"resolved_by"`
	DoctorNotifiedAt *time.Time `json:"doctor_notified_at,omitempty"`
	CreatedAt        time.Time  `json:"created_at"`
	ResolvedAt       *time.Time `json:"resolved_at,omitempty"`
	PatientName      string     `json:"patient_name,omitempty"`
	PatientNameDisplay string     `json:"patient_display_name,omitempty"`
}

type SOSBlastLog struct {
	ID                string     `json:"id"`
	CrisisIncidentID  string     `json:"crisis_incident_id"`
	ContactPhone      string     `json:"contact_phone"`
	Channel           string     `json:"channel"`
	Status            string     `json:"status"`
	MessageID         string     `json:"message_id,omitempty"`
	CreatedAt         time.Time  `json:"created_at"`
	DeliveredAt       *time.Time `json:"delivered_at,omitempty"`
}

type SOSBlastStatus struct {
	Total      int `json:"total"`
	Sent       int `json:"sent"`
	Delivered  int `json:"delivered"`
	Pending    int `json:"pending"`
	Failed     int `json:"failed"`
}

// CreateEmergencyContact menambahkan kontak (max 5 per pasien, enforced di handler).
func (s *Store) CreateEmergencyContact(ctx context.Context, c EmergencyContact) (EmergencyContact, error) {
	const q = `INSERT INTO emergency_contacts (patient_id, contact_name, contact_phone, relationship, is_default)
		VALUES ($1, $2, $3, $4, $5) RETURNING id`
	err := s.db.QueryRowContext(ctx, q, c.PatientID, c.ContactName, c.ContactPhone, c.Relationship, c.IsDefault).Scan(&c.ID)
	if err != nil {
		return EmergencyContact{}, err
	}
	_ = s.AddAuditLog(ctx, c.PatientID, c.PatientID, "emergency_contact.created", "emergency_contacts", c.ID, map[string]any{"name": c.ContactName})
	return c, nil
}

func (s *Store) ListEmergencyContacts(ctx context.Context, patientID string) ([]EmergencyContact, error) {
	const q = `SELECT id, patient_id, contact_name, contact_phone, relationship, is_default
		FROM emergency_contacts WHERE patient_id = $1 ORDER BY is_default DESC, created_at ASC`
	rows, err := s.db.QueryContext(ctx, q, patientID)
	if err != nil { return nil, err }
	defer rows.Close()
	var out []EmergencyContact
	for rows.Next() {
		var c EmergencyContact
		if err := rows.Scan(&c.ID, &c.PatientID, &c.ContactName, &c.ContactPhone, &c.Relationship, &c.IsDefault); err != nil {
			return nil, err
		}
		out = append(out, c)
	}
	return out, rows.Err()
}

func (s *Store) DeleteEmergencyContact(ctx context.Context, patientID, contactID string) error {
	const q = `DELETE FROM emergency_contacts WHERE patient_id = $1 AND id = $2`
	res, err := s.db.ExecContext(ctx, q, patientID, contactID)
	if err != nil { return err }
	aff, _ := res.RowsAffected()
	if aff == 0 { return errors.New("contact not found") }
	_ = s.AddAuditLog(ctx, patientID, patientID, "emergency_contact.deleted", "emergency_contacts", contactID, nil)
	return nil
}

func (s *Store) UpdateEmergencyContact(ctx context.Context, c EmergencyContact) error {
	const q = `UPDATE emergency_contacts SET contact_name = $1, contact_phone = $2, relationship = $3, is_default = $4
		WHERE id = $5 AND patient_id = $6`
	res, err := s.db.ExecContext(ctx, q, c.ContactName, c.ContactPhone, c.Relationship, c.IsDefault, c.ID, c.PatientID)
	if err != nil { return err }
	aff, _ := res.RowsAffected()
	if aff == 0 { return errors.New("contact not found") }
	return nil
}

func (s *Store) CountEmergencyContacts(ctx context.Context, patientID string) (int, error) {
	const q = `SELECT COUNT(*) FROM emergency_contacts WHERE patient_id = $1`
	var n int
	err := s.db.QueryRowContext(ctx, q, patientID).Scan(&n)
	return n, err
}

// CreateCrisisIncident mencatat incident dan menutup incident lama yang masih aktif.
func (s *Store) CreateCrisisIncident(ctx context.Context, in CrisisIncident) (CrisisIncident, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return CrisisIncident{}, err }
	defer tx.Rollback()

	_, err = tx.ExecContext(ctx, `UPDATE crisis_incidents
		SET status = 'resolved', resolved_at = now(), resolution_notes = 'superseded oleh incident baru'
		WHERE patient_id = $1 AND status = 'active'`, in.PatientID)
	if err != nil { return CrisisIncident{}, err }

	const q = `INSERT INTO crisis_incidents
		(patient_id, triggered_by, phq9_q9_score, latitude, longitude, doctor_notified_at, contacts_notified_at, status)
		VALUES ($1, $2, $3, $4, $5, now(), now(), 'active')
		RETURNING id, status, created_at`
	err = tx.QueryRowContext(ctx, q, in.PatientID, in.TriggeredBy, in.PHQ9Q9Score, in.Latitude, in.Longitude).
		Scan(&in.ID, &in.Status, &in.CreatedAt)
	if err != nil { return CrisisIncident{}, err }

	if err := tx.Commit(); err != nil { return CrisisIncident{}, err }
	return in, nil
}

func (s *Store) ListCrisisIncidents(ctx context.Context, patientID string, limit int) ([]CrisisIncident, error) {
	limit = normalizeLimit(limit, 20, 100)
	const q = `SELECT i.id, i.patient_id, i.triggered_by, i.phq9_q9_score, i.latitude, i.longitude, i.status,
		COALESCE(i.resolution_notes, ''), COALESCE(i.resolved_by::text, ''), i.doctor_notified_at, i.created_at, i.resolved_at,
		u.display_name AS patient_name, u.display_name AS patient_name_display
		FROM crisis_incidents i
		JOIN users u ON u.id = i.patient_id
		WHERE i.patient_id = $1
		ORDER BY i.created_at DESC
		LIMIT $2`
	rows, err := s.db.QueryContext(ctx, q, patientID, limit)
	if err != nil { return nil, err }
	defer rows.Close()
	var out []CrisisIncident
	for rows.Next() {
		var in CrisisIncident
		if err := rows.Scan(&in.ID, &in.PatientID, &in.TriggeredBy, &in.PHQ9Q9Score, &in.Latitude, &in.Longitude,
			&in.Status, &in.ResolutionNotes, &in.ResponsibleBy, &in.DoctorNotifiedAt, &in.CreatedAt, &in.ResolvedAt,
			&in.PatientName, &in.PatientNameDisplay); err != nil {
			return nil, err
		}
		out = append(out, in)
	}
	return out, rows.Err()
}

func (s *Store) ListActiveCrisisIncidentsForProfessional(ctx context.Context, professionalID string) ([]CrisisIncident, error) {
	const q = `SELECT i.id, i.patient_id, i.triggered_by, i.phq9_q9_score, i.latitude, i.longitude, i.status,
		COALESCE(i.resolution_notes, ''), COALESCE(i.resolved_by::text, ''), i.doctor_notified_at, i.created_at, i.resolved_at,
		u.display_name AS patient_name, u.display_name AS patient_name_display
		FROM crisis_incidents i
		JOIN patient_professional_links l ON l.patient_id = i.patient_id
		JOIN users u ON u.id = i.patient_id
		WHERE l.professional_id = $1 AND i.status = 'active'
		ORDER BY i.created_at DESC`
	rows, err := s.db.QueryContext(ctx, q, professionalID)
	if err != nil { return nil, err }
	defer rows.Close()
	var out []CrisisIncident
	for rows.Next() {
		var in CrisisIncident
		if err := rows.Scan(&in.ID, &in.PatientID, &in.TriggeredBy, &in.PHQ9Q9Score, &in.Latitude, &in.Longitude,
			&in.Status, &in.ResolutionNotes, &in.ResponsibleBy, &in.DoctorNotifiedAt, &in.CreatedAt, &in.ResolvedAt,
			&in.PatientName, &in.PatientNameDisplay); err != nil {
			return nil, err
		}
		out = append(out, in)
	}
	return out, rows.Err()
}

func (s *Store) GetCrisisIncident(ctx context.Context, incidentID string) (CrisisIncident, error) {
	const q = `SELECT id, patient_id, triggered_by, phq9_q9_score, latitude, longitude, status,
		COALESCE(resolution_notes, ''), COALESCE(resolved_by::text, ''), doctor_notified_at, created_at, resolved_at
		FROM crisis_incidents WHERE id = $1`
	var in CrisisIncident
	err := s.db.QueryRowContext(ctx, q, incidentID).Scan(&in.ID, &in.PatientID, &in.TriggeredBy,
		&in.PHQ9Q9Score, &in.Latitude, &in.Longitude, &in.Status, &in.ResolutionNotes,
		&in.ResponsibleBy, &in.DoctorNotifiedAt, &in.CreatedAt, &in.ResolvedAt)
	if err != nil {
		return CrisisIncident{}, err
	}
	return in, nil
}

func (s *Store) ResolveCrisisIncident(ctx context.Context, incidentID, professionalID, resolutionNotes string) (CrisisIncident, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil { return CrisisIncident{}, err }
	defer tx.Rollback()

	var patientID string
	const q = `UPDATE crisis_incidents
		SET status = 'resolved', resolved_by = $1, resolution_notes = $2, resolved_at = now()
		WHERE id = $3
		RETURNING patient_id`
	err = tx.QueryRowContext(ctx, q, professionalID, resolutionNotes, incidentID).Scan(&patientID)
	if err != nil {
		return CrisisIncident{}, errors.New("incident not found")
	}

	// Purge GPS: privacy setelah resolved
	if _, err = tx.ExecContext(ctx, `UPDATE crisis_incidents SET latitude = NULL, longitude = NULL WHERE id = $1`, incidentID); err != nil {
		return CrisisIncident{}, err
	}

	if err := tx.Commit(); err != nil { return CrisisIncident{}, err }
	return CrisisIncident{ID: incidentID, PatientID: patientID, Status: "resolved"}, nil
}

func (s *Store) ListActiveCrisisIncidentsOlderThan(ctx context.Context, olderThan time.Duration) ([]CrisisIncident, error) {
	const q = `SELECT i.id, i.patient_id, u.display_name AS patient_name, u.display_name AS patient_name_display
		FROM crisis_incidents i
		JOIN users u ON u.id = i.patient_id
		WHERE i.status = 'active' AND i.created_at < now() - $1::interval
		ORDER BY i.created_at ASC`
	interval := fmt.Sprintf("%d seconds", int(olderThan.Seconds()))
	rows, err := s.db.QueryContext(ctx, q, interval)
	if err != nil { return nil, err }
	defer rows.Close()
	var out []CrisisIncident
	for rows.Next() {
		var in CrisisIncident
		if err := rows.Scan(&in.ID, &in.PatientID, &in.PatientName, &in.PatientNameDisplay); err != nil {
			return nil, err
		}
		out = append(out, in)
	}
	return out, rows.Err()
}

func (s *Store) PurgeResolvedCrisisGPS(ctx context.Context, olderThan time.Duration) (int64, error) {
	const q = `UPDATE crisis_incidents SET latitude = NULL, longitude = NULL
		WHERE status = 'resolved' AND resolved_at < now() - $1::interval AND latitude IS NOT NULL`
	interval := fmt.Sprintf("%d seconds", int(olderThan.Seconds()))
	res, err := s.db.ExecContext(ctx, q, interval)
	if err != nil { return 0, err }
	return res.RowsAffected()
}

func (s *Store) CreateSOSBlastLog(ctx context.Context, incidentID, contactPhone, channel string) (string, error) {
	const q = `INSERT INTO sos_blast_log (crisis_incident_id, contact_phone, channel) VALUES ($1, $2, $3) RETURNING id`
	var id string
	err := s.db.QueryRowContext(ctx, q, incidentID, contactPhone, channel).Scan(&id)
	return id, err
}

func (s *Store) UpdateSOSBlastStatus(ctx context.Context, logID, status, messageID string) error {
	const q = `UPDATE sos_blast_log SET status = $1, message_id = $2, delivered_at = $3 WHERE id = $4`
	var deliveredAt any
	if status == "delivered" {
		deliveredAt = time.Now()
	}
	_, err := s.db.ExecContext(ctx, q, status, messageID, deliveredAt, logID)
	return err
}

func (s *Store) SOSBlastStatusForIncident(ctx context.Context, incidentID string) (SOSBlastStatus, error) {
	const q = `SELECT COUNT(*),
		COUNT(*) FILTER (WHERE status = 'sent'),
		COUNT(*) FILTER (WHERE status = 'delivered'),
		COUNT(*) FILTER (WHERE status = 'pending'),
		COUNT(*) FILTER (WHERE status = 'failed')
		FROM sos_blast_log WHERE crisis_incident_id = $1`
	var st SOSBlastStatus
	err := s.db.QueryRowContext(ctx, q, incidentID).
		Scan(&st.Total, &st.Sent, &st.Delivered, &st.Pending, &st.Failed)
	return st, err
}
