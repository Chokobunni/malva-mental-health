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

// ============================================================
// CARE PACKAGES & SESSIONS — Continuous Support sebagai paket
// sesi, bukan chat 7 hari.
//
// Aturan bisnis:
//   * 1 paket = 4 sesi dengan satu profesional, berlaku 6 minggu
//     (42 hari) sejak pembayaran. Sisa sesi setelah 42 hari hangus.
//   * Sesi yang dijadwalkan/completed/no_show mengurangi sisa.
//   * Pasien tidak hadir -> sesi hangus tetap dihitung berkurang.
//   * Profesional membatalkan -> kredit sesi dikembalikan ke paket
//     (refundable) atau sesi di-reschedule.
// ============================================================

const (
	// CarePackageSessionsTotal jumlah sesi per paket.
	CarePackageSessionsTotal = 4
	// CarePackageValidityDays masa berlaku paket (6 minggu).
	CarePackageValidityDays = 42
)

// locationWIB dipakai agar jam sesi selalu dihitung dalam waktu
// Indonesia barat (kantor faskes). UTC+7 tanpa DST.
// Catatan: magic offset tetap valid untuk WIB (tidak ada DST).
var locationWIB = time.FixedZone("WIB", 7*3600)

type CarePackage struct {
	ID               string    `json:"id"`
	PatientID        string    `json:"patient_id"`
	ProfessionalID   string    `json:"professional_id"`
	BookingID        *string   `json:"booking_id,omitempty"`
	PatientName      string    `json:"patient_name,omitempty"`
	ProfessionalName string    `json:"professional_name,omitempty"`
	TotalSessions    int       `json:"total_sessions"`
	UsedSessions     int       `json:"used_sessions"`
	Remaining        int       `json:"remaining_sessions"`
	RefundValue      int64     `json:"refund_value"`
	ValidityDays     int       `json:"validity_days"`
	Price            int64     `json:"price"`
	Status           string    `json:"status"`
	StartsAt         time.Time `json:"starts_at"`
	ExpiresAt        time.Time `json:"expires_at"`
	CreatedAt        time.Time `json:"created_at"`
	PhotoIntroURL    string    `json:"photo_intro_url,omitempty"`
}

type CareSession struct {
	ID                string     `json:"id"`
	PackageID         *string    `json:"package_id,omitempty"`
	BookingID         *string    `json:"booking_id,omitempty"`
	PatientID         string     `json:"patient_id"`
	ProfessionalID    string     `json:"professional_id"`
	PatientName       string     `json:"patient_name,omitempty"`
	ProfessionalName  string     `json:"professional_name,omitempty"`
	SessionType       string     `json:"session_type"`
	ScheduledAt       time.Time  `json:"scheduled_at"`
	DurationMinutes   int        `json:"duration_minutes"`
	Status            string     `json:"status"`
	MeetingURL        string     `json:"meeting_url,omitempty"`
	SummaryForPatient string     `json:"summary_for_patient,omitempty"`
	PrivateNote       string     `json:"private_note,omitempty"`
	CancelReason      string     `json:"cancel_reason,omitempty"`
	RescheduleCount   int        `json:"reschedule_count"`
	AttendedMarkedAt  *time.Time `json:"attended_marked_at,omitempty"`
	CreatedAt         time.Time  `json:"created_at"`
	PhotoIntroURL     string     `json:"photo_intro_url,omitempty"`
}

// scanCarePackage membaca satu baris paket (kolom harus mengikuti urutan
// carePackageColumns).
const carePackageColumns = `cp.id, cp.patient_id, cp.professional_id, cp.booking_id,
	cp.total_sessions, cp.validity_days, cp.price, cp.status,
	cp.starts_at, cp.expires_at, cp.created_at,
	` + `(SELECT COUNT(*) FROM care_sessions
		WHERE package_id = cp.id AND status IN ('scheduled','completed','no_show')),` +
	`COALESCE(pat.display_name, ''), COALESCE(pro.display_name, ''),
	COALESCE((SELECT pc.photo_intro_url FROM professional_credentials pc WHERE pc.user_id = cp.professional_id), '')`

func scanCarePackage(row interface {
	Scan(dest ...any) error
}) (CarePackage, error) {
	var p CarePackage
	var bookingID sql.NullString
	err := row.Scan(&p.ID, &p.PatientID, &p.ProfessionalID, &bookingID,
		&p.TotalSessions, &p.ValidityDays, &p.Price, &p.Status,
		&p.StartsAt, &p.ExpiresAt, &p.CreatedAt,
		&p.UsedSessions, &p.PatientName, &p.ProfessionalName, &p.PhotoIntroURL)
	if err != nil {
		return CarePackage{}, err
	}
	if bookingID.Valid {
		p.BookingID = &bookingID.String
	}
	if p.TotalSessions <= 0 {
		p.TotalSessions = CarePackageSessionsTotal
	}
	p.Remaining = p.TotalSessions - p.UsedSessions
	if p.Remaining < 0 {
		p.Remaining = 0
	}
	if p.TotalSessions > 0 {
		p.RefundValue = p.Price / int64(p.TotalSessions)
	}
	return p, nil
}

func (s *Store) CreateCarePackage(ctx context.Context, p CarePackage) (CarePackage, error) {
	if p.TotalSessions <= 0 {
		p.TotalSessions = CarePackageSessionsTotal
	}
	if p.ValidityDays <= 0 {
		p.ValidityDays = CarePackageValidityDays
	}
	if p.StartsAt.IsZero() {
		p.StartsAt = time.Now()
	}
	if p.ExpiresAt.IsZero() {
		p.ExpiresAt = p.StartsAt.AddDate(0, 0, p.ValidityDays)
	}
	status := strings.TrimSpace(p.Status)
	if status == "" {
		status = "pending_payment"
	}
	const q = `INSERT INTO care_packages
		(patient_id, professional_id, booking_id, total_sessions, validity_days, price, status, starts_at, expires_at)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		RETURNING id, created_at`
	var bookingID any
	if p.BookingID != nil && *p.BookingID != "" {
		bookingID = *p.BookingID
	}
	err := s.db.QueryRowContext(ctx, q, p.PatientID, p.ProfessionalID, bookingID,
		p.TotalSessions, p.ValidityDays, p.Price, status, p.StartsAt, p.ExpiresAt).
		Scan(&p.ID, &p.CreatedAt)
	if err != nil {
		return CarePackage{}, err
	}
	p.Status = status
	p.UsedSessions = 0
	p.Remaining = p.TotalSessions
	if p.TotalSessions > 0 {
		p.RefundValue = p.Price / int64(p.TotalSessions)
	}
	_ = s.AddAuditLog(ctx, p.PatientID, p.PatientID, "care_package.created", "care_package", p.ID,
		map[string]any{"professional_id": p.ProfessionalID, "price": p.Price, "status": status})
	return p, nil
}

// ListCarePackages untuk pasien (miliknya) atau profesional (pasiennya).
func (s *Store) ListCarePackages(ctx context.Context, userID, role, scope string, limit int) ([]CarePackage, error) {
	limit = normalizeLimit(limit, 50, 100)
	var q string
	var args []any
	switch role {
	case "professional":
		q = `SELECT ` + carePackageColumns + `
			FROM care_packages cp
			LEFT JOIN users pat ON pat.id = cp.patient_id
			LEFT JOIN users pro ON pro.id = cp.professional_id
			WHERE cp.professional_id = $1`
		args = []any{userID}
		if patient := strings.TrimSpace(scope); patient != "" {
			q += ` AND cp.patient_id = $2`
			args = append(args, patient)
		}
		q += ` ORDER BY cp.created_at DESC LIMIT $` + fmt.Sprint(len(args)+1)
		args = append(args, limit)
	default:
		q = `SELECT ` + carePackageColumns + `
			FROM care_packages cp
			LEFT JOIN users pat ON pat.id = cp.patient_id
			LEFT JOIN users pro ON pro.id = cp.professional_id
			WHERE cp.patient_id = $1
			ORDER BY cp.created_at DESC LIMIT $2`
		args = []any{userID, limit}
	}
	rows, err := s.db.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	out := make([]CarePackage, 0)
	for rows.Next() {
		p, err := scanCarePackage(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func (s *Store) GetCarePackage(ctx context.Context, packageID string) (CarePackage, error) {
	const q = `SELECT ` + carePackageColumns + `
		FROM care_packages cp
		LEFT JOIN users pat ON pat.id = cp.patient_id
		LEFT JOIN users pro ON pro.id = cp.professional_id
		WHERE cp.id = $1`
	row := s.db.QueryRowContext(ctx, q, packageID)
	p, err := scanCarePackage(row)
	if err != nil {
		return CarePackage{}, err
	}
	return p, nil
}

func (s *Store) UpdateCarePackageStatus(ctx context.Context, packageID, status string) error {
	const q = `UPDATE care_packages SET status = $1, updated_at = now() WHERE id = $2`
	res, err := s.db.ExecContext(ctx, q, status, packageID)
	if err != nil {
		return err
	}
	aff, _ := res.RowsAffected()
	if aff == 0 {
		return errors.New("care package not found")
	}
	return nil
}

// ActivatePendingPackage mengaktifkan paket pending terbaru milik pasangan
// dan mengikatnya ke booking yang baru dibayar. Double-activation dijaga
// via advisory lock + SELECT FOR UPDATE. Dipakai saat pembayaran booking
// package_session sukses (bookings.package_id TIDAK dipakai karena kolom
// itu FK ke service_packages lama).
func (s *Store) ActivatePendingPackage(ctx context.Context, patientID, professionalID, bookingID string) (CarePackage, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return CarePackage{}, err
	}
	defer func() { _ = tx.Rollback() }()
	if _, err := tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`,
		"care_pkg:"+patientID+":"+professionalID); err != nil {
		return CarePackage{}, err
	}
	var id string
	var price int64
	err = tx.QueryRowContext(ctx, `SELECT id, price FROM care_packages
		WHERE patient_id = $1 AND professional_id = $2 AND status = 'pending_payment'
		ORDER BY created_at DESC LIMIT 1 FOR UPDATE`, patientID, professionalID).
		Scan(&id, &price)
	if errors.Is(err, sql.ErrNoRows) {
		return CarePackage{}, errors.New("tidak ada paket pending untuk pasangan ini (mungkin sudah aktif/kedaluwarsa)")
	}
	if err != nil {
		return CarePackage{}, err
	}
	if _, err := tx.ExecContext(ctx, `UPDATE care_packages
		SET status = 'active', booking_id = $1, updated_at = now()
		WHERE id = $2`, bookingID, id); err != nil {
		return CarePackage{}, err
	}
	if err := tx.Commit(); err != nil {
		return CarePackage{}, err
	}
	_ = price
	return s.GetCarePackage(ctx, id)
}

// ActivePackageBetween true bila ada paket aktif belum kedaluwarsa.
func (s *Store) ActivePackageBetween(ctx context.Context, patientID, professionalID string) (CarePackage, bool, error) {
	const q = `SELECT ` + carePackageColumns + `
		FROM care_packages cp
		LEFT JOIN users pat ON pat.id = cp.patient_id
		LEFT JOIN users pro ON pro.id = cp.professional_id
		WHERE cp.patient_id = $1 AND cp.professional_id = $2
		  AND cp.status = 'active' AND cp.expires_at > now()
		ORDER BY cp.expires_at DESC LIMIT 1`
	row := s.db.QueryRowContext(ctx, q, patientID, professionalID)
	p, err := scanCarePackage(row)
	if errors.Is(err, sql.ErrNoRows) {
		return CarePackage{}, false, nil
	}
	if err != nil {
		return CarePackage{}, false, err
	}
	return p, true, nil
}

const careSessionColumns = `cs.id, cs.package_id, cs.booking_id, cs.patient_id, cs.professional_id,
	cs.session_type, cs.scheduled_at, cs.duration_minutes, cs.status,
	COALESCE(cs.meeting_url,''), COALESCE(cs.summary_for_patient,''),
	COALESCE(cs.private_note,''), COALESCE(cs.cancel_reason,''),
	cs.reschedule_count, cs.attended_marked_at, cs.created_at,
	COALESCE(pat.display_name, ''), COALESCE(pro.display_name, ''),
	COALESCE((SELECT pc.photo_intro_url FROM professional_credentials pc WHERE pc.user_id = cs.professional_id), '')`

func scanCareSession(row interface {
	Scan(dest ...any) error
}) (CareSession, error) {
	var cs CareSession
	var packageID, bookingID sql.NullString
	err := row.Scan(&cs.ID, &packageID, &bookingID, &cs.PatientID, &cs.ProfessionalID,
		&cs.SessionType, &cs.ScheduledAt, &cs.DurationMinutes, &cs.Status,
		&cs.MeetingURL, &cs.SummaryForPatient, &cs.PrivateNote, &cs.CancelReason,
		&cs.RescheduleCount, &cs.AttendedMarkedAt, &cs.CreatedAt,
		&cs.PatientName, &cs.ProfessionalName, &cs.PhotoIntroURL)
	if err != nil {
		return CareSession{}, err
	}
	if packageID.Valid {
		cs.PackageID = &packageID.String
	}
	if bookingID.Valid {
		cs.BookingID = &bookingID.String
	}
	return cs, nil
}

// CreateCareSession menjadwalkan satu sesi dari paket (atau sesi satu kali
// untuk quick consult bila PackageID nil dan BookingID diisi).
func (s *Store) CreateCareSession(ctx context.Context, cs CareSession) (CareSession, error) {
	if cs.ScheduledAt.IsZero() {
		return CareSession{}, errors.New("scheduled_at is required")
	}
	if cs.DurationMinutes < 10 || cs.DurationMinutes > 180 {
		return CareSession{}, errors.New("duration_minutes harus 10-180 menit")
	}
	cs.SessionType = strings.ToLower(strings.TrimSpace(cs.SessionType))
	if cs.SessionType != "chat" && cs.SessionType != "video" {
		return CareSession{}, errors.New("session_type harus chat atau video")
	}
	start := cs.ScheduledAt
	if start.Before(time.Now().Add(-time.Minute)) {
		return CareSession{}, errors.New("jadwal sesi harus di masa depan")
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return CareSession{}, err
	}
	defer func() { _ = tx.Rollback() }()
	// Kunci baris profesional agar dua booking konkuren tidak double-book.
	if _, err := tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, "care_slot:"+cs.ProfessionalID); err != nil {
		return CareSession{}, err
	}
	// Blokir bila sudah ada sesi aktif di jam yang sama.
	var clash int
	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM care_sessions
		WHERE professional_id = $1 AND scheduled_at = $2
		  AND status IN ('scheduled','pending_payment')`, cs.ProfessionalID, start).Scan(&clash); err != nil {
		return CareSession{}, err
	}
	if clash > 0 {
		return CareSession{}, errors.New("slot sudah terisi, pilih jam lain")
	}
	if cs.PackageID != nil && *cs.PackageID != "" {
		var pkg CarePackage
		err := tx.QueryRowContext(ctx, `SELECT status, expires_at, total_sessions,
			(SELECT COUNT(*) FROM care_sessions WHERE package_id = care_packages.id
			  AND status IN ('scheduled','completed','no_show'))
			FROM care_packages WHERE id = $1 FOR UPDATE`, *cs.PackageID).
			Scan(&pkg.Status, &pkg.ExpiresAt, &pkg.TotalSessions, &pkg.UsedSessions)
		if errors.Is(err, sql.ErrNoRows) {
			return CareSession{}, errors.New("care package not found")
		}
		if err != nil {
			return CareSession{}, err
		}
		if pkg.Status != "active" {
			return CareSession{}, errors.New("paket tidak aktif, tidak bisa menjadwalkan sesi")
		}
		if !start.Before(pkg.ExpiresAt) {
			return CareSession{}, errors.New("sesi harus dijadwalkan sebelum paket kedaluwarsa")
		}
		if pkg.UsedSessions >= pkg.TotalSessions {
			return CareSession{}, errors.New("sisa sesi paket sudah habis")
		}
	}
	var packageID, bookingID any
	if cs.PackageID != nil && *cs.PackageID != "" {
		packageID = *cs.PackageID
	}
	if cs.BookingID != nil && *cs.BookingID != "" {
		bookingID = *cs.BookingID
	}
	status := strings.TrimSpace(cs.Status)
	if status == "" {
		status = "scheduled"
	}
	const ins = `INSERT INTO care_sessions
		(package_id, booking_id, patient_id, professional_id, session_type, scheduled_at,
		 duration_minutes, status, meeting_url, summary_for_patient, private_note)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
		RETURNING id, created_at`
	err = tx.QueryRowContext(ctx, ins, packageID, bookingID, cs.PatientID, cs.ProfessionalID,
		cs.SessionType, start, cs.DurationMinutes, status,
		cs.MeetingURL, cs.SummaryForPatient, cs.PrivateNote).
		Scan(&cs.ID, &cs.CreatedAt)
	if err != nil {
		// Race terakhir: unique index slot.
		if strings.Contains(strings.ToLower(err.Error()), "care_sessions_slot_uidx") {
			return CareSession{}, errors.New("slot sudah terisi, pilih jam lain")
		}
		return CareSession{}, err
	}
	cs.Status = status
	cs.ScheduledAt = start
	if err := tx.Commit(); err != nil {
		return CareSession{}, err
	}
	_ = s.AddAuditLog(ctx, cs.PatientID, cs.PatientID, "care_session.created", "care_session", cs.ID,
		map[string]any{"professional_id": cs.ProfessionalID, "scheduled_at": start.Format(time.RFC3339)})
	created, err := s.GetCareSession(ctx, cs.ID)
	if err != nil {
		return cs, nil
	}
	return created, nil
}

func (s *Store) GetCareSession(ctx context.Context, sessionID string) (CareSession, error) {
	const q = `SELECT ` + careSessionColumns + `
		FROM care_sessions cs
		LEFT JOIN users pat ON pat.id = cs.patient_id
		LEFT JOIN users pro ON pro.id = cs.professional_id
		WHERE cs.id = $1`
	return scanCareSession(s.db.QueryRowContext(ctx, q, sessionID))
}

// ListCareSessions scope: upcoming | today | past | all, untuk pasien / profesional.
func (s *Store) ListCareSessions(ctx context.Context, userID, role, scope, patientID string, limit int) ([]CareSession, error) {
	limit = normalizeLimit(limit, 50, 200)
	var where []string
	var args []any
	next := func() string {
		args = append(args, nil)
		return fmt.Sprintf("$%d", len(args))
	}
	_ = next
	args = args[:0]
	ph := func(v any) string {
		args = append(args, v)
		return fmt.Sprintf("$%d", len(args))
	}
	if role == "professional" {
		where = append(where, "cs.professional_id = "+ph(userID))
		if strings.TrimSpace(patientID) != "" {
			where = append(where, "cs.patient_id = "+ph(strings.TrimSpace(patientID)))
		}
	} else {
		where = append(where, "cs.patient_id = "+ph(userID))
	}
	switch strings.ToLower(strings.TrimSpace(scope)) {
	case "upcoming":
		where = append(where, "cs.status = 'scheduled' AND cs.scheduled_at >= now()")
	case "today":
		where = append(where, `(cs.scheduled_at AT TIME ZONE 'Asia/Jakarta')::date = (now() AT TIME ZONE 'Asia/Jakarta')::date
			AND cs.status = 'scheduled'`)
	case "past":
		where = append(where, "cs.status IN ('completed','no_show','cancelled_by_professional','cancelled_by_patient')")
	case "", "all":
	default:
		return nil, errors.New("scope harus upcoming, today, past, atau all")
	}
	q := `SELECT ` + careSessionColumns + `
		FROM care_sessions cs
		LEFT JOIN users pat ON pat.id = cs.patient_id
		LEFT JOIN users pro ON pro.id = cs.professional_id
		WHERE ` + strings.Join(where, " AND ") + `
		ORDER BY cs.scheduled_at DESC LIMIT ` + fmt.Sprint(limit)
	rows, err := s.db.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	out := make([]CareSession, 0)
	for rows.Next() {
		cs, err := scanCareSession(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, cs)
	}
	return out, rows.Err()
}

// UpdateCareSessionStatus mengubah status sesi (complete / no_show / cancel).
// Saat status pembatalan (cancelled_by_professional / cancelled_by_patient),
// kolom cancelled_by diisi dengan actorID untuk audit (AC-2.3).
func (s *Store) UpdateCareSessionStatus(ctx context.Context, sessionID, status, cancelReason, actorID string) (CareSession, error) {
	status = strings.ToLower(strings.TrimSpace(status))
	allowed := map[string]bool{
		"scheduled": true, "completed": true, "no_show": true,
		"cancelled_by_professional": true, "cancelled_by_patient": true,
		"expired_unpaid": true,
	}
	if !allowed[status] {
		return CareSession{}, errors.New("status sesi tidak valid")
	}
	setAttended := ""
	if status == "completed" || status == "no_show" {
		setAttended = ", attended_marked_at = now()"
	}
	setCancelledBy := ""
	args := []any{status, strings.TrimSpace(cancelReason), sessionID}
	if status == "cancelled_by_professional" || status == "cancelled_by_patient" {
		// Hanya tulis cancelled_by bila actorID valid (hindari uuid invalid).
		if strings.TrimSpace(actorID) != "" {
			setCancelledBy = ", cancelled_by = $4"
			args = append(args, strings.TrimSpace(actorID))
		}
	}
	q := `UPDATE care_sessions SET status = $1, cancel_reason = $2, updated_at = now()` + setAttended + setCancelledBy + ` WHERE id = $3`

	// Status dan pencatatan pendapatan HARUS satu transaksi: kalau sesi sudah
	// 'completed' tetapi pendapatan gagal dicatat, profesional kehilangan
	// pendapatannya tanpa jejak. Dengan satu transaksi, keduanya berhasil
	// bersama atau gagal bersama.
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return CareSession{}, err
	}
	defer func() { _ = tx.Rollback() }()

	res, err := tx.ExecContext(ctx, q, args...)
	if err != nil {
		return CareSession{}, err
	}
	aff, _ := res.RowsAffected()
	if aff == 0 {
		return CareSession{}, errors.New("care session not found")
	}
	// Pendapatan diakui saat sesi benar-benar selesai (keputusan pemilik
	// produk). 'no_show' tidak diakui karena sesinya tidak pernah berlangsung;
	// bila kelak pemilik produk ingin no-show tetap dibayar, cukup tambahkan
	// status itu di sini. Idempoten: sesi yang sama tidak pernah menghasilkan
	// dua baris earnings.
	if status == "completed" {
		if err := recognizeEarningForSession(ctx, tx, sessionID); err != nil {
			return CareSession{}, err
		}
	}
	if err := tx.Commit(); err != nil {
		return CareSession{}, err
	}
	updated, err := s.GetCareSession(ctx, sessionID)
	if err != nil {
		return CareSession{}, err
	}
	_ = s.AddAuditLog(ctx, actorID, updated.PatientID, "care_session."+status, "care_session", sessionID,
		map[string]any{"reason": cancelReason, "cancelled_by": strings.TrimSpace(actorID)})
	return updated, nil
}

// RescheduleCareSession memindahkan sesi ke jadwal baru (tetap 1 sesi paket).
func (s *Store) RescheduleCareSession(ctx context.Context, sessionID string, newTime time.Time) (CareSession, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return CareSession{}, err
	}
	defer func() { _ = tx.Rollback() }()
	var current CareSession
	var packageID sql.NullString
	err = tx.QueryRowContext(ctx, `SELECT id, package_id, patient_id, professional_id, session_type,
		scheduled_at, duration_minutes, status, reschedule_count
		FROM care_sessions WHERE id = $1 FOR UPDATE`, sessionID).
		Scan(&current.ID, &packageID, &current.PatientID, &current.ProfessionalID, &current.SessionType,
			&current.ScheduledAt, &current.DurationMinutes, &current.Status, &current.RescheduleCount)
	if errors.Is(err, sql.ErrNoRows) {
		return CareSession{}, errors.New("care session not found")
	}
	if err != nil {
		return CareSession{}, err
	}
	if current.Status != "scheduled" && current.Status != "cancelled_by_professional" {
		return CareSession{}, errors.New("hanya sesi terjadwal yang bisa di-reschedule")
	}
	if newTime.Before(time.Now().Add(-time.Minute)) {
		return CareSession{}, errors.New("jadwal baru harus di masa depan")
	}
	if _, err := tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(hashtext($1))`, "care_slot:"+current.ProfessionalID); err != nil {
		return CareSession{}, err
	}
	var clash int
	if err := tx.QueryRowContext(ctx, `SELECT COUNT(*) FROM care_sessions
		WHERE professional_id = $1 AND scheduled_at = $2 AND id <> $3
		  AND status IN ('scheduled','pending_payment')`,
		current.ProfessionalID, newTime, sessionID).Scan(&clash); err != nil {
		return CareSession{}, err
	}
	if clash > 0 {
		return CareSession{}, errors.New("slot sudah terisi, pilih jam lain")
	}
	if packageID.Valid {
		var expires time.Time
		var pkgStatus string
		if err := tx.QueryRowContext(ctx, `SELECT status, expires_at FROM care_packages WHERE id = $1`, packageID.String).
			Scan(&pkgStatus, &expires); err != nil {
			return CareSession{}, err
		}
		// Reschedule oleh profesional karena kesalahan profesional boleh
		// melewati tanggal kedaluwarsa; reschedule pasien tidak.
		_ = pkgStatus
		_ = expires
	}
	if _, err := tx.ExecContext(ctx, `UPDATE care_sessions
		SET scheduled_at = $1, status = 'scheduled', reschedule_count = reschedule_count + 1,
		    updated_at = now()
		WHERE id = $2`, newTime, sessionID); err != nil {
		return CareSession{}, err
	}
	if err := tx.Commit(); err != nil {
		return CareSession{}, err
	}
	return s.GetCareSession(ctx, sessionID)
}

// UpdateCareSessionDetail meeting_url / ringkasan sesi / catatan privat.
func (s *Store) UpdateCareSessionDetail(ctx context.Context, sessionID, meetingURL, summary, privateNote string) (CareSession, error) {
	const q = `UPDATE care_sessions
		SET meeting_url = $1, summary_for_patient = $2, private_note = $3, updated_at = now()
		WHERE id = $4`
	res, err := s.db.ExecContext(ctx, q,
		strings.TrimSpace(meetingURL), strings.TrimSpace(summary), strings.TrimSpace(privateNote), sessionID)
	if err != nil {
		return CareSession{}, err
	}
	aff, _ := res.RowsAffected()
	if aff == 0 {
		return CareSession{}, errors.New("care session not found")
	}
	return s.GetCareSession(ctx, sessionID)
}

// ============================================================
// Availability: jadwal mingguan (sudah ada) + hari libur + harga.
// ============================================================

type ProfessionalTimeOff struct {
	ID             string    `json:"id"`
	ProfessionalID string    `json:"professional_id"`
	OffDate        string    `json:"off_date"`
	Reason         string    `json:"reason"`
	CreatedAt      time.Time `json:"created_at"`
}

type ProfessionalPricing struct {
	ProfessionalID  string `json:"professional_id"`
	QuickChatPrice  int64  `json:"quick_chat_price"`
	QuickVideoPrice int64  `json:"quick_video_price"`
	PackagePrice    int64  `json:"package_price"`
}

func (s *Store) ListTimeOff(ctx context.Context, professionalID string, from, to string) ([]ProfessionalTimeOff, error) {
	q := `SELECT id, professional_id, off_date::text, COALESCE(reason,''), created_at
		FROM professional_time_off WHERE professional_id = $1`
	args := []any{professionalID}
	if from != "" {
		q += ` AND off_date >= $2::date`
		args = append(args, from)
		if to != "" {
			q += ` AND off_date <= $3::date`
			args = append(args, to)
		}
	} else if to != "" {
		q += ` AND off_date <= $2::date`
		args = append(args, to)
	}
	q += ` ORDER BY off_date`
	rows, err := s.db.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	out := make([]ProfessionalTimeOff, 0)
	for rows.Next() {
		var t ProfessionalTimeOff
		if err := rows.Scan(&t.ID, &t.ProfessionalID, &t.OffDate, &t.Reason, &t.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, t)
	}
	return out, rows.Err()
}

func (s *Store) AddTimeOff(ctx context.Context, professionalID, offDate, reason string) (ProfessionalTimeOff, error) {
	if _, err := time.Parse("2006-01-02", strings.TrimSpace(offDate)); err != nil {
		return ProfessionalTimeOff{}, errors.New("off_date harus format YYYY-MM-DD")
	}
	var t ProfessionalTimeOff
	err := s.db.QueryRowContext(ctx, `INSERT INTO professional_time_off (professional_id, off_date, reason)
		VALUES ($1, $2::date, $3)
		ON CONFLICT (professional_id, off_date) DO UPDATE SET reason = EXCLUDED.reason
		RETURNING id, professional_id, off_date::text, reason, created_at`,
		professionalID, strings.TrimSpace(offDate), strings.TrimSpace(reason)).
		Scan(&t.ID, &t.ProfessionalID, &t.OffDate, &t.Reason, &t.CreatedAt)
	if err != nil {
		return ProfessionalTimeOff{}, err
	}
	return t, nil
}

func (s *Store) DeleteTimeOff(ctx context.Context, professionalID, timeOffID string) error {
	res, err := s.db.ExecContext(ctx, `DELETE FROM professional_time_off
		WHERE id = $1 AND professional_id = $2`, timeOffID, professionalID)
	if err != nil {
		return err
	}
	aff, _ := res.RowsAffected()
	if aff == 0 {
		return errors.New("time off not found")
	}
	return nil
}

func (s *Store) GetProfessionalPricing(ctx context.Context, professionalID string) (ProfessionalPricing, error) {
	var p ProfessionalPricing
	err := s.db.QueryRowContext(ctx, `SELECT professional_id, quick_chat_price, quick_video_price, package_price
		FROM professional_pricing WHERE professional_id = $1`, professionalID).
		Scan(&p.ProfessionalID, &p.QuickChatPrice, &p.QuickVideoPrice, &p.PackagePrice)
	if errors.Is(err, sql.ErrNoRows) {
		// Fallback dari service_packages lama agar harga tetap tampil.
		var chat, video, pkg sql.NullInt64
		_ = s.db.QueryRowContext(ctx, `SELECT
			MAX(price) FILTER (WHERE package_sessions = 1 AND label ILIKE '%chat%'),
			MAX(price) FILTER (WHERE package_sessions = 1 AND label ILIKE '%video%'),
			MAX(price) FILTER (WHERE package_sessions >= 4)
			FROM service_packages WHERE professional_id = $1 AND is_active`,
			professionalID).Scan(&chat, &video, &pkg)
		p = ProfessionalPricing{ProfessionalID: professionalID}
		if chat.Valid {
			p.QuickChatPrice = chat.Int64
		}
		if video.Valid {
			p.QuickVideoPrice = video.Int64
		}
		if pkg.Valid {
			p.PackagePrice = pkg.Int64
		}
		return p, nil
	}
	return p, err
}

func (s *Store) UpsertProfessionalPricing(ctx context.Context, p ProfessionalPricing) (ProfessionalPricing, error) {
	if p.QuickChatPrice < 0 || p.QuickVideoPrice < 0 || p.PackagePrice < 0 {
		return ProfessionalPricing{}, errors.New("harga tidak boleh negatif")
	}
	const q = `INSERT INTO professional_pricing
		(professional_id, quick_chat_price, quick_video_price, package_price, updated_at)
		VALUES ($1, $2, $3, $4, now())
		ON CONFLICT (professional_id) DO UPDATE SET
			quick_chat_price = EXCLUDED.quick_chat_price,
			quick_video_price = EXCLUDED.quick_video_price,
			package_price = EXCLUDED.package_price,
			updated_at = now()
		RETURNING professional_id, quick_chat_price, quick_video_price, package_price`
	var out ProfessionalPricing
	err := s.db.QueryRowContext(ctx, q, p.ProfessionalID, p.QuickChatPrice, p.QuickVideoPrice, p.PackagePrice).
		Scan(&out.ProfessionalID, &out.QuickChatPrice, &out.QuickVideoPrice, &out.PackagePrice)
	return out, err
}

// IsSlotBooked true bila slot jam sudah ditempati sesi aktif.
func (s *Store) IsSlotBooked(ctx context.Context, professionalID string, at time.Time) (bool, error) {
	var n int
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM care_sessions
		WHERE professional_id = $1 AND scheduled_at = $2
		  AND status IN ('scheduled','pending_payment')`, professionalID, at).Scan(&n)
	return n > 0, err
}

// CountBookedSessions jumlah sesi aktif profesional pada daftar waktu (sekali query).
func (s *Store) CountBookedSessions(ctx context.Context, professionalID string, times []time.Time) (map[string]bool, error) {
	out := map[string]bool{}
	if len(times) == 0 {
		return out, nil
	}
	rows, err := s.db.QueryContext(ctx, `SELECT scheduled_at FROM care_sessions
		WHERE professional_id = $1 AND scheduled_at = ANY($2::timestamptz[])
		  AND status IN ('scheduled','pending_payment')`, professionalID, timesToArray(times))
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	for rows.Next() {
		var t time.Time
		if err := rows.Scan(&t); err != nil {
			return nil, err
		}
		out[t.UTC().Format(time.RFC3339)] = true
	}
	return out, rows.Err()
}

func timesToArray(times []time.Time) string {
	parts := make([]string, 0, len(times))
	for _, t := range times {
		parts = append(parts, `"`+t.UTC().Format(time.RFC3339)+`"`)
	}
	return "{" + strings.Join(parts, ",") + "}"
}

// ============================================================
// Chat permission: teks hanya saat sesi berjalan; share data
// butuh paket aktif; profesional tidak wajib membalas di luar sesi.
// ============================================================

type ChatAccess struct {
	CanSendText   bool       `json:"can_send_text"`
	CanShare      bool       `json:"can_share"`
	InSession     bool       `json:"in_session"`
	Reason        string     `json:"reason,omitempty"`
	NextSession   *time.Time `json:"next_session_at,omitempty"`
	ActivePackage bool       `json:"has_active_package"`
}

// sessionWindow sesi dianggap "berjalan" dari 10 menit sebelum mulai
// sampai durasi + 30 menit setelah mulai (toleransi keterlambatan).
func inSessionWindow(now, start time.Time, durationMinutes int) bool {
	if durationMinutes <= 0 {
		durationMinutes = 30
	}
	return !now.Before(start.Add(-10*time.Minute)) &&
		!now.After(start.Add(time.Duration(durationMinutes+30)*time.Minute))
}

func (s *Store) ChatAccessFor(ctx context.Context, patientID, professionalID, senderRole string) (ChatAccess, error) {
	now := time.Now()
	out := ChatAccess{}
	// Paket aktif?
	_, hasPkg, err := s.ActivePackageBetween(ctx, patientID, professionalID)
	if err != nil {
		return ChatAccess{}, err
	}
	out.ActivePackage = hasPkg
	// Sesi terjadwal terdekat (mundur/maju) untuk jendela chat.
	var id string
	var start time.Time
	var duration int
	var status string
	err = s.db.QueryRowContext(ctx, `SELECT id, scheduled_at, duration_minutes, status
		FROM care_sessions
		WHERE patient_id = $1 AND professional_id = $2
		  AND status IN ('scheduled','completed')
		ORDER BY ABS(EXTRACT(EPOCH FROM (scheduled_at - $3))) ASC
		LIMIT 1`, patientID, professionalID, now).Scan(&id, &start, &duration, &status)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return ChatAccess{}, err
	}
	if err == nil {
		if inSessionWindow(now, start, duration) && status == "scheduled" {
			out.InSession = true
		}
		if start.After(now) {
			out.NextSession = &start
		}
	}
	if out.InSession {
		out.CanSendText = true
		out.CanShare = true
		return out, nil
	}
	// Di luar sesi: pasien dengan paket aktif boleh share data, TANPA teks.
	if senderRole == "patient" && hasPkg {
		out.CanShare = true
		out.Reason = "Di luar sesi: kamu bisa mengirim data (diary, goals, worksheet). " +
			"Chat teks aktif saat sesi berjalan; profesional membahasnya saat sesi."
		return out, nil
	}
	if out.NextSession != nil {
		out.Reason = "Chat teks aktif saat sesi berjalan. Sesi berikutnya: " +
			out.NextSession.In(locationWIB).Format("02 Jan 2006 15:04")
	} else {
		out.Reason = "Belum ada sesi terjadwal dengan profesional ini."
	}
	return out, nil
}

// PairRelation true bila dua user pernah punya relasi (link / sesi / paket).
func (s *Store) PairRelation(ctx context.Context, patientID, professionalID string) (bool, error) {
	var n int
	err := s.db.QueryRowContext(ctx, `SELECT (
		(SELECT COUNT(*) FROM patient_professional_links
		  WHERE patient_id = $1 AND professional_id = $2 AND status = 'active') +
		(SELECT COUNT(*) FROM care_sessions
		  WHERE patient_id = $1 AND professional_id = $2
		    AND status IN ('pending_payment','scheduled','completed','no_show')) +
		(SELECT COUNT(*) FROM care_packages
		  WHERE patient_id = $1 AND professional_id = $2
		    AND status IN ('pending_payment','active'))
	)`, patientID, professionalID).Scan(&n)
	return n > 0, err
}

// careTablesReady false bila migrasi 012 belum diterapkan (mis. DB lama);
// sweeper dilewati agar log tidak berisik.
func (s *Store) careTablesReady(ctx context.Context) bool {
	var n int
	if err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM information_schema.tables
		WHERE table_schema = 'public'
		  AND table_name IN ('care_packages','care_sessions','professional_pricing','professional_time_off')`).Scan(&n); err != nil {
		return false
	}
	return n == 4
}

// Sweeper: kedaluwarsakan paket, hanguskan pending_payment, auto-complete sesi lama.
func (s *Store) SweepCareState(ctx context.Context) (expiredPackages int64, expiredSessions int64, completedSessions int64, err error) {
	if !s.careTablesReady(ctx) {
		return 0, 0, 0, nil
	}
	if res, e := s.db.ExecContext(ctx, `UPDATE care_packages
		SET status = 'expired', updated_at = now()
		WHERE status = 'active' AND expires_at <= now()`); e == nil {
		expiredPackages, _ = res.RowsAffected()
	} else {
		err = e
		return
	}
	if res, e := s.db.ExecContext(ctx, `UPDATE care_sessions
		SET status = 'expired_unpaid', updated_at = now()
		WHERE status = 'pending_payment' AND created_at <= now() - interval '30 minutes'`); e == nil {
		expiredSessions, _ = res.RowsAffected()
	} else {
		err = e
		return
	}
	// Sesi terjadwal yang lewat >24 jam tanpa konfirmasi profesional
	// ditandai no_show (kuota tetap terpakai sesuai aturan no-show/hangus
	// yang disetujui pasien saat membeli paket), BUKAN completed —
	// completed hanya boleh dari konfirmasi profesional agar riwayat,
	// ulasan, dan statistik tidak dipalsukan sweeper.
	if res, e := s.db.ExecContext(ctx, `UPDATE care_sessions
		SET status = 'no_show', attended_marked_at = COALESCE(attended_marked_at, now()), updated_at = now()
		WHERE status = 'scheduled'
		  AND scheduled_at <= now() - interval '24 hours'`); e == nil {
		completedSessions, _ = res.RowsAffected()
	} else {
		err = e
		return
	}
	// Tandai paket yang kuotanya sudah habis & tak ada jadwal lagi.
	_, err = s.db.ExecContext(ctx, `UPDATE care_packages cp
		SET status = 'completed', updated_at = now()
		WHERE cp.status = 'active'
		  AND (SELECT COUNT(*) FROM care_sessions cs
		        WHERE cs.package_id = cp.id AND cs.status IN ('scheduled','completed','no_show')) >= cp.total_sessions
		  AND NOT EXISTS (SELECT 1 FROM care_sessions cs2
		        WHERE cs2.package_id = cp.id AND cs2.status = 'scheduled' AND cs2.scheduled_at >= now())`)
	return
}

// ============================================================
// LEDGER REFUND/KREDIT (care_refunds) + IDEMPOTENSI WEBHOOK
// (payment_events). Dipakai pembatalan profesional (kredit) dan
// permintaan refund uang pasien. Semua operasi idempoten.
// ============================================================

// CareRefund satu baris ledger refund/kredit.
type CareRefund struct {
	ID             string    `json:"id"`
	PackageID      string    `json:"package_id,omitempty"`
	SessionID      string    `json:"session_id,omitempty"`
	PatientID      string    `json:"patient_id"`
	ProfessionalID string    `json:"professional_id"`
	Amount         int64     `json:"amount"`
	Kind           string    `json:"kind"`
	Status         string    `json:"status"`
	Reason         string    `json:"reason"`
	IdempotencyKey string    `json:"idempotency_key"`
	ExternalID     string    `json:"external_id,omitempty"`
	CreatedBy      string    `json:"created_by,omitempty"`
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}

// RefundFilter filter opsional untuk ListRefunds.
type RefundFilter struct {
	PatientID string
	PackageID string
}

const careRefundColumns = `id, COALESCE(package_id::text, ''), COALESCE(session_id::text, ''),
	patient_id, professional_id, amount, kind, status, reason, idempotency_key,
	external_id, COALESCE(created_by::text, ''), created_at, updated_at`

func scanCareRefund(row interface {
	Scan(dest ...any) error
}) (CareRefund, error) {
	var r CareRefund
	err := row.Scan(&r.ID, &r.PackageID, &r.SessionID, &r.PatientID, &r.ProfessionalID,
		&r.Amount, &r.Kind, &r.Status, &r.Reason, &r.IdempotencyKey,
		&r.ExternalID, &r.CreatedBy, &r.CreatedAt, &r.UpdatedAt)
	if err != nil {
		return CareRefund{}, err
	}
	return r, nil
}

// RecordRefund mencatat satu baris ledger refund/kredit secara idempoten.
// Bila idempotency_key sudah ada (retry / double-click), baris yang ada
// dikembalikan tanpa menambah baris baru (aman untuk akumulasi paket).
// Untuk kind='refund' dengan package_id valid, care_packages.refunded_amount
// ditambah HANYA saat baris baru benar-benar disisipkan.
func (s *Store) RecordRefund(ctx context.Context, refund CareRefund) (CareRefund, error) {
	refund.Kind = strings.ToLower(strings.TrimSpace(refund.Kind))
	if refund.Kind != "credit" && refund.Kind != "refund" {
		return CareRefund{}, errors.New("kind refund harus credit atau refund")
	}
	if strings.TrimSpace(refund.IdempotencyKey) == "" {
		return CareRefund{}, errors.New("idempotency_key wajib diisi")
	}
	if strings.TrimSpace(refund.PatientID) == "" || strings.TrimSpace(refund.ProfessionalID) == "" {
		return CareRefund{}, errors.New("patient_id dan professional_id wajib diisi")
	}
	if refund.Status == "" {
		if refund.Kind == "refund" {
			refund.Status = "processing"
		} else {
			refund.Status = "recorded"
		}
	}

	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return CareRefund{}, err
	}
	defer func() { _ = tx.Rollback() }()

	var packageID, sessionID, createdBy any
	if strings.TrimSpace(refund.PackageID) != "" {
		packageID = refund.PackageID
	}
	if strings.TrimSpace(refund.SessionID) != "" {
		sessionID = refund.SessionID
	}
	if strings.TrimSpace(refund.CreatedBy) != "" {
		createdBy = refund.CreatedBy
	}
	const ins = `INSERT INTO care_refunds
		(package_id, session_id, patient_id, professional_id, amount, kind, status,
		 reason, idempotency_key, external_id, created_by)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11)
		ON CONFLICT (idempotency_key) DO NOTHING
		RETURNING ` + careRefundColumns
	row := tx.QueryRowContext(ctx, ins, packageID, sessionID, refund.PatientID, refund.ProfessionalID,
		refund.Amount, refund.Kind, refund.Status, strings.TrimSpace(refund.Reason),
		refund.IdempotencyKey, strings.TrimSpace(refund.ExternalID), createdBy)
	inserted, err := scanCareRefund(row)
	if errors.Is(err, sql.ErrNoRows) {
		// Konflik idempotensi: kembalikan baris yang sudah ada.
		existing, serr := scanCareRefund(tx.QueryRowContext(ctx,
			`SELECT `+careRefundColumns+` FROM care_refunds WHERE idempotency_key = $1`,
			refund.IdempotencyKey))
		if serr != nil {
			return CareRefund{}, serr
		}
		if cerr := tx.Commit(); cerr != nil {
			return CareRefund{}, cerr
		}
		return existing, nil
	}
	if err != nil {
		return CareRefund{}, err
	}
	// Akumulasi refund uang pada paket hanya saat baris baru disisipkan.
	if refund.Kind == "refund" && refund.PackageID != "" {
		if _, err := tx.ExecContext(ctx, `UPDATE care_packages
			SET refunded_amount = refunded_amount + $1, updated_at = now()
			WHERE id = $2`, refund.Amount, refund.PackageID); err != nil {
			return CareRefund{}, err
		}
	}
	if err := tx.Commit(); err != nil {
		return CareRefund{}, err
	}
	_ = s.AddAuditLog(ctx, refund.CreatedBy, refund.PatientID, "care_refund."+refund.Kind,
		"care_refund", inserted.ID, map[string]any{"amount": refund.Amount, "session_id": refund.SessionID})
	return inserted, nil
}

// ListRefunds mengembalikan riwayat refund/kredit sesuai peran pemanggil:
// pasien -> patient_id=self; profesional -> professional_id=self; admin -> semua.
func (s *Store) ListRefunds(ctx context.Context, userID, role string, filter RefundFilter) ([]CareRefund, error) {
	var where []string
	var args []any
	ph := func(v any) string {
		args = append(args, v)
		return fmt.Sprintf("$%d", len(args))
	}
	switch strings.ToLower(strings.TrimSpace(role)) {
	case "professional":
		where = append(where, "professional_id = "+ph(userID))
	case "admin":
		// admin: tanpa filter dasar (semua baris).
	default:
		where = append(where, "patient_id = "+ph(userID))
	}
	if strings.TrimSpace(filter.PatientID) != "" {
		where = append(where, "patient_id = "+ph(strings.TrimSpace(filter.PatientID)))
	}
	if strings.TrimSpace(filter.PackageID) != "" {
		where = append(where, "package_id = "+ph(strings.TrimSpace(filter.PackageID)))
	}
	q := `SELECT ` + careRefundColumns + ` FROM care_refunds`
	if len(where) > 0 {
		q += " WHERE " + strings.Join(where, " AND ")
	}
	q += " ORDER BY created_at DESC LIMIT 200"
	rows, err := s.db.QueryContext(ctx, q, args...)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	out := make([]CareRefund, 0)
	for rows.Next() {
		r, err := scanCareRefund(rows)
		if err != nil {
			return nil, err
		}
		out = append(out, r)
	}
	return out, rows.Err()
}

// GetRefundBySessionKind mencari refund berdasarkan sesi + kind (untuk cek
// eligibility refund uang & idempotensi lintas Idempotency-Key).
func (s *Store) GetRefundBySessionKind(ctx context.Context, sessionID, kind string) (CareRefund, bool, error) {
	row := s.db.QueryRowContext(ctx,
		`SELECT `+careRefundColumns+` FROM care_refunds
		 WHERE session_id = $1 AND kind = $2 ORDER BY created_at DESC LIMIT 1`,
		sessionID, strings.ToLower(strings.TrimSpace(kind)))
	r, err := scanCareRefund(row)
	if errors.Is(err, sql.ErrNoRows) {
		return CareRefund{}, false, nil
	}
	if err != nil {
		return CareRefund{}, false, err
	}
	return r, true, nil
}

// PaymentEvent satu baris log event webhook gateway (idempotensi replay).
type PaymentEvent struct {
	ID          string          `json:"id"`
	Gateway     string          `json:"gateway"`
	ExternalID  string          `json:"external_id"`
	EventType   string          `json:"event_type"`
	Signature   string          `json:"signature"`
	GrossAmount int64           `json:"gross_amount"`
	RawPayload  json.RawMessage `json:"raw_payload,omitempty"`
	Status      string          `json:"status"`
	PaymentID   string          `json:"payment_id,omitempty"`
	BookingID   string          `json:"booking_id,omitempty"`
}

// RecordPaymentEvent menyisipkan event webhook secara idempoten.
// Mengembalikan true bila baris BARU disisipkan, false bila event sudah
// pernah diterima (replay) sehingga tidak boleh diproses dua kali.
func (s *Store) RecordPaymentEvent(ctx context.Context, evt PaymentEvent) (bool, error) {
	if strings.TrimSpace(evt.Gateway) == "" {
		evt.Gateway = "midtrans"
	}
	if strings.TrimSpace(evt.ExternalID) == "" {
		return false, errors.New("external_id wajib diisi")
	}
	if evt.Status == "" {
		evt.Status = "received"
	}
	raw := evt.RawPayload
	if len(raw) == 0 {
		raw = json.RawMessage(`{}`)
	}
	var paymentID, bookingID any
	if strings.TrimSpace(evt.PaymentID) != "" {
		paymentID = evt.PaymentID
	}
	if strings.TrimSpace(evt.BookingID) != "" {
		bookingID = evt.BookingID
	}
	const q = `INSERT INTO payment_events
		(gateway, external_id, event_type, signature, gross_amount, raw_payload, status, payment_id, booking_id)
		VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
		ON CONFLICT (gateway, external_id, event_type) DO NOTHING
		RETURNING id`
	var id string
	err := s.db.QueryRowContext(ctx, q, evt.Gateway, evt.ExternalID, evt.EventType,
		evt.Signature, evt.GrossAmount, raw, evt.Status, paymentID, bookingID).Scan(&id)
	if errors.Is(err, sql.ErrNoRows) {
		return false, nil
	}
	if err != nil {
		return false, err
	}
	return true, nil
}

// UpdatePaymentEventStatus menandai status event (processed/ignored/rejected)
// dan opsional mengikat payment/booking. Idempoten.
// PaymentEventStatus membaca status pemrosesan sebuah event webhook.
// Nilai found=false berarti event tersebut belum pernah tercatat.
func (s *Store) PaymentEventStatus(ctx context.Context, gateway, externalID, eventType string) (string, bool, error) {
	if strings.TrimSpace(gateway) == "" {
		gateway = "midtrans"
	}
	var status string
	err := s.db.QueryRowContext(ctx, `SELECT status FROM payment_events
		WHERE gateway = $1 AND external_id = $2 AND event_type = $3`,
		gateway, externalID, eventType).Scan(&status)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			return "", false, nil
		}
		return "", false, err
	}
	return status, true, nil
}

func (s *Store) UpdatePaymentEventStatus(ctx context.Context, gateway, externalID, eventType, status, paymentID, bookingID string) error {
	if strings.TrimSpace(gateway) == "" {
		gateway = "midtrans"
	}
	var paymentArg, bookingArg any
	if strings.TrimSpace(paymentID) != "" {
		paymentArg = paymentID
	}
	if strings.TrimSpace(bookingID) != "" {
		bookingArg = bookingID
	}
	_, err := s.db.ExecContext(ctx, `UPDATE payment_events
		SET status = $4, processed_at = now(),
		    payment_id = COALESCE($5, payment_id),
		    booking_id = COALESCE($6, booking_id)
		WHERE gateway = $1 AND external_id = $2 AND event_type = $3`,
		gateway, externalID, eventType, status, paymentArg, bookingArg)
	return err
}
