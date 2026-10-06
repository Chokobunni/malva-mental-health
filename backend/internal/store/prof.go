package store

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// ============================================================
// PROFESSIONAL: Credentials, Discovery, Schedules, Packages
// ============================================================

type ProfessionalCredential struct {
	ID                 string        `json:"id"`
	UserID             string        `json:"user_id"`
	STRNumber          string        `json:"str_number"`
	SIPNumber          string        `json:"sip_number"`
	SIPPNumber         string        `json:"sipp_number"`
	Specialization     string        `json:"specialization"`
	SubSpecialties     []string      `json:"sub_specialties"`
	HospitalLat        *float64      `json:"hospital_lat,omitempty"`
	HospitalLng        *float64      `json:"hospital_lng,omitempty"`
	HospitalName       string        `json:"hospital_name"`
	AddressDetails     string        `json:"address_details"`
	IsBPJSSupported    bool          `json:"is_bpjs_supported"`
	PhotoIntroURL      string        `json:"photo_intro_url,omitempty"`
	VideoIntroURL      string        `json:"video_intro_url,omitempty"`
	Bio                string        `json:"bio,omitempty"`
	Education          []interface{} `json:"education"`
	VerificationStatus string        `json:"verification_status"`
	RejectionReason    string        `json:"rejection_reason,omitempty"`
	DocumentURL        string        `json:"document_url,omitempty"`
	LegacyCount        int           `json:"legacy_count"`
	HelpfulnessCount   int           `json:"helpfulness_count"`
	ReviewCount        int           `json:"review_count"`
	YearsExperience    int           `json:"years_experience"`
	PatientCount       int           `json:"patient_count"`
	PriceFrom          int64         `json:"price_from"`
	CreatedAt          time.Time     `json:"created_at"`
}

type DoctorSearchResult struct {
	ProfessionalCredential
	DisplayName      string   `json:"display_name"`
	DistanceKM       *float64 `json:"distance_km,omitempty"`
	IsAvailableToday bool     `json:"is_available_today"`
}

// parsePGTextArray parses Postgres text[] literals like {a,"b,c"} into []string.
func parsePGTextArray(raw []byte, out *[]string) {
	s := strings.TrimSpace(string(raw))
	if s == "" || s == "{}" || s == "[]" || strings.EqualFold(s, "null") {
		*out = nil
		return
	}
	if strings.HasPrefix(s, "[") {
		var j []string
		if err := json.Unmarshal([]byte(s), &j); err == nil {
			*out = j
			return
		}
	}
	// Strip { } then split respecting quotes (values are plain tags here).
	s = strings.TrimPrefix(strings.TrimSuffix(s, "}"), "{")
	var cur strings.Builder
	inQuotes := false
	var res []string
	for _, r := range s {
		switch r {
		case '"':
			inQuotes = !inQuotes
		case ',':
			if inQuotes {
				cur.WriteRune(r)
			} else {
				res = append(res, cur.String())
				cur.Reset()
			}
		default:
			cur.WriteRune(r)
		}
	}
	res = append(res, cur.String())
	*out = res
}

func pgTextArray(values []string) string {
	if len(values) == 0 {
		return "{}"
	}
	// Quote tiap elemen agar koma di dalam nilai aman.
	quoted := make([]string, len(values))
	for i, v := range values {
		escaped := strings.ReplaceAll(v, `"`, `\"`)
		quoted[i] = `"` + escaped + `"`
	}
	return "{" + strings.Join(quoted, ",") + "}"
}

func (s *Store) UpsertProfessionalCredential(ctx context.Context, c ProfessionalCredential) (ProfessionalCredential, error) {
	sub := pgTextArray(c.SubSpecialties)
	edu := []byte("[]")
	if len(c.Education) > 0 {
		if b, err := json.Marshal(c.Education); err == nil {
			edu = b
		}
	}
	// UPDATE dulu; bila 0 baris, INSERT (hindari ON CONFLICT tanpa unique constraint).
	const upd = `UPDATE professional_credentials SET
		str_number=$2, sip_number=$3, sipp_number=$4, specialization=$5, sub_specialties=$6,
		hospital_lat=$7, hospital_lng=$8, hospital_name=$9, address_details=$10, is_bpjs_supported=$11,
		photo_intro_url=$12, video_intro_url=$13, bio=$14, education=$15::jsonb, document_url=$16,
		years_experience=$17, price_from=$18,
		verification_status='PENDING', verified_at=NULL
		WHERE user_id = $1`
	res, err := s.db.ExecContext(ctx, upd, c.UserID, c.STRNumber, c.SIPNumber, c.SIPPNumber, c.Specialization, sub,
		c.HospitalLat, c.HospitalLng, c.HospitalName, c.AddressDetails, c.IsBPJSSupported,
		c.PhotoIntroURL, c.VideoIntroURL, c.Bio, edu, c.DocumentURL, c.YearsExperience, c.PriceFrom)
	if err != nil {
		return ProfessionalCredential{}, err
	}
	if aff, _ := res.RowsAffected(); aff == 0 {
		const ins = `INSERT INTO professional_credentials
			(user_id, str_number, sip_number, sipp_number, specialization, sub_specialties,
			 hospital_lat, hospital_lng, hospital_name, address_details, is_bpjs_supported,
			 photo_intro_url, video_intro_url, bio, education, document_url, years_experience, price_from, verification_status)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15::jsonb,$16,$17,$18,'PENDING')`
		if _, err := s.db.ExecContext(ctx, ins, c.UserID, c.STRNumber, c.SIPNumber, c.SIPPNumber, c.Specialization, sub,
			c.HospitalLat, c.HospitalLng, c.HospitalName, c.AddressDetails, c.IsBPJSSupported,
			c.PhotoIntroURL, c.VideoIntroURL, c.Bio, edu, c.DocumentURL, c.YearsExperience, c.PriceFrom); err != nil {
			return ProfessionalCredential{}, err
		}
	}
	var out ProfessionalCredential
	out, err = s.GetProfessionalCredential(ctx, c.UserID)
	if err != nil {
		return ProfessionalCredential{}, err
	}
	_ = s.AddAuditLog(ctx, c.UserID, c.UserID, "credentials.uploaded", "professional_credentials", out.ID,
		map[string]any{"spec": c.Specialization})
	return out, nil
}

func (s *Store) GetProfessionalCredential(ctx context.Context, userID string) (ProfessionalCredential, error) {
	const q = `SELECT id, user_id, COALESCE(str_number,''), COALESCE(sip_number,''), COALESCE(sipp_number,''),
		specialization, COALESCE(sub_specialties,'{}'), hospital_lat, hospital_lng, COALESCE(hospital_name,''),
		COALESCE(address_details,''), is_bpjs_supported, COALESCE(photo_intro_url,''), COALESCE(video_intro_url,''),
		COALESCE(bio,''), COALESCE(education,'[]'::jsonb), verification_status, COALESCE(rejection_reason,''),
		COALESCE(document_url,''), legacy_count, helpfulness_count, review_count, years_experience, COALESCE(price_from, 0),
		(SELECT COUNT(*) FROM patient_professional_links WHERE professional_id = professional_credentials.user_id AND status='active') AS patient_count,
		created_at
		FROM professional_credentials WHERE user_id = $1`
	var c ProfessionalCredential
	var sub, edu []byte
	err := s.db.QueryRowContext(ctx, q, userID).Scan(&c.ID, &c.UserID, &c.STRNumber, &c.SIPNumber, &c.SIPPNumber,
		&c.Specialization, &sub, &c.HospitalLat, &c.HospitalLng, &c.HospitalName, &c.AddressDetails, &c.IsBPJSSupported,
		&c.PhotoIntroURL, &c.VideoIntroURL, &c.Bio, &edu, &c.VerificationStatus, &c.RejectionReason, &c.DocumentURL,
		&c.LegacyCount, &c.HelpfulnessCount, &c.ReviewCount, &c.YearsExperience, &c.PriceFrom, &c.PatientCount, &c.CreatedAt)
	if err != nil {
		return ProfessionalCredential{}, err
	}
	parsePGTextArray(sub, &c.SubSpecialties)
	_ = json.Unmarshal(edu, &c.Education)
	return c, nil
}

func (s *Store) ListPendingCredentials(ctx context.Context) ([]ProfessionalCredential, error) {
	const q = `SELECT id, user_id, COALESCE(str_number,''), COALESCE(sip_number,''), COALESCE(sipp_number,''),
		specialization, COALESCE(sub_specialties,'{}'), hospital_lat, hospital_lng, COALESCE(hospital_name,''),
		COALESCE(address_details,''), is_bpjs_supported, COALESCE(photo_intro_url,''), COALESCE(video_intro_url,''),
		COALESCE(bio,''), COALESCE(education,'[]'::jsonb), verification_status, COALESCE(rejection_reason,''),
		COALESCE(document_url,''), legacy_count, helpfulness_count, review_count, years_experience, COALESCE(price_from, 0), 0, created_at
		FROM professional_credentials WHERE verification_status = 'PENDING'
		ORDER BY created_at ASC`
	rows, err := s.db.QueryContext(ctx, q)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var out []ProfessionalCredential
	for rows.Next() {
		var c ProfessionalCredential
		var sub, edu []byte
		if err := rows.Scan(&c.ID, &c.UserID, &c.STRNumber, &c.SIPNumber, &c.SIPPNumber, &c.Specialization, &sub,
			&c.HospitalLat, &c.HospitalLng, &c.HospitalName, &c.AddressDetails, &c.IsBPJSSupported, &c.PhotoIntroURL,
			&c.VideoIntroURL, &c.Bio, &edu, &c.VerificationStatus, &c.RejectionReason, &c.DocumentURL,
			&c.LegacyCount, &c.HelpfulnessCount, &c.ReviewCount, &c.YearsExperience, &c.PriceFrom, &c.PatientCount, &c.CreatedAt); err != nil {
			return nil, err
		}
		parsePGTextArray(sub, &c.SubSpecialties)
		_ = json.Unmarshal(edu, &c.Education)
		out = append(out, c)
	}
	return out, rows.Err()
}

func (s *Store) VerifyProfessionalCredential(ctx context.Context, credentialID, adminID, action, rejectionReason string) error {
	var status string
	switch action {
	case "approve":
		status = "VERIFIED"
	case "reject":
		status = "REJECTED"
	default:
		return errors.New("action must be approve or reject")
	}
	const q = `UPDATE professional_credentials
		SET verification_status = $1, verified_by = $2, verified_at = now(),
			rejection_reason = COALESCE(NULLIF($3,''), rejection_reason)
		WHERE id = $4`
	res, err := s.db.ExecContext(ctx, q, status, adminID, rejectionReason, credentialID)
	if err != nil {
		return err
	}
	aff, _ := res.RowsAffected()
	if aff == 0 {
		return errors.New("credential not found")
	}
	return nil
}

// SearchDoctors mencari profesional terverifikasi dengan stats + Haversine jarak.
func (s *Store) SearchDoctors(ctx context.Context, params DoctorSearchParams) ([]DoctorSearchResult, error) {
	var where []string
	where = append(where, "pc.verification_status = 'VERIFIED'")
	where = append(where, "u.disabled_at IS NULL")
	var args []interface{}
	nextArg := func() string {
		arg := fmt.Sprintf("$%d", len(args)+1)
		return arg
	}

	if params.Specialization != "" {
		where = append(where, "pc.specialization = "+nextArg())
		args = append(args, params.Specialization)
	}
	if params.IsBPJSSupported != nil {
		where = append(where, "pc.is_bpjs_supported = "+nextArg())
		args = append(args, *params.IsBPJSSupported)
	}
	if params.MaxPrice != nil {
		where = append(where, `EXISTS (
			SELECT 1 FROM service_packages sp WHERE sp.professional_id = pc.user_id
			AND sp.price <= `+nextArg()+` AND sp.is_active = true
		)`)
		args = append(args, *params.MaxPrice)
	}

	hasCoords := params.PatientLat != nil && params.PatientLng != nil

	// Kolom jarak selalu ada (NULL bila tanpa koordinat) agar Scan stabil.
	distanceCol := "NULL::numeric AS distance_km"
	if hasCoords {
		latArg := nextArg()
		args = append(args, *params.PatientLat)
		lngArg := nextArg()
		args = append(args, *params.PatientLng)
		haversine := fmt.Sprintf(`ROUND(6371 * 2 * ASIN(SQRT(
			POWER(SIN(RADIANS((%s - pc.hospital_lat)/2.0)), 2) +
			COS(RADIANS(pc.hospital_lat)) * COS(RADIANS(%s)) *
			POWER(SIN(RADIANS((%s - pc.hospital_lng)/2.0)), 2)
		))::numeric, 2)`, latArg, latArg, lngArg)
		distanceCol = haversine + " AS distance_km"
		where = append(where, "pc.hospital_lat IS NOT NULL AND pc.hospital_lng IS NOT NULL")
		if params.MaxKM != nil {
			maxArg := nextArg()
			args = append(args, *params.MaxKM)
			where = append(where, haversine+" <= "+maxArg)
		}
	}

	orderBy := "u.display_name ASC"
	switch params.SortBy {
	case "name_desc":
		orderBy = "u.display_name DESC"
	case "sessions":
		orderBy = "pc.legacy_count DESC"
	case "popular":
		orderBy = "pc.review_count DESC"
	case "distance":
		if hasCoords {
			orderBy = "distance_km ASC NULLS LAST"
		}
	case "availability":
		orderBy = "is_available_today DESC"
	}

	limit := params.Limit
	if limit <= 0 || limit > 100 {
		limit = 50
	}

	query := fmt.Sprintf(`SELECT pc.id, pc.user_id, u.display_name, COALESCE(pc.str_number,''), COALESCE(pc.sip_number,''), COALESCE(pc.sipp_number,''),
		pc.specialization, COALESCE(pc.sub_specialties,'{}'), pc.hospital_lat, pc.hospital_lng, COALESCE(pc.hospital_name,''),
		COALESCE(pc.address_details,''), pc.is_bpjs_supported, COALESCE(pc.photo_intro_url,''), COALESCE(pc.video_intro_url,''),
		COALESCE(pc.bio,''), COALESCE(pc.education,'[]'::jsonb), pc.legacy_count, pc.helpfulness_count, pc.review_count, pc.years_experience,
		COALESCE(pc.price_from, 0),
		(SELECT COUNT(*) FROM patient_professional_links WHERE professional_id = pc.user_id AND status='active') AS patient_count,
		CASE WHEN EXISTS (SELECT 1 FROM professional_schedules ps WHERE ps.professional_id = pc.user_id AND ps.day_of_week = EXTRACT(dow FROM CURRENT_DATE)::int AND ps.is_active = true) THEN 1 ELSE 0 END AS is_available_today,
		%s
		FROM professional_credentials pc
		JOIN users u ON u.id = pc.user_id
		WHERE %s
		ORDER BY %s
		LIMIT %d`,
		distanceCol, strings.Join(where, " AND "), orderBy, limit,
	)

	rows, err := s.db.QueryContext(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var out []DoctorSearchResult
	for rows.Next() {
		var r DoctorSearchResult
		var sub, edu []byte
		var available int
		if err := rows.Scan(&r.ID, &r.UserID, &r.DisplayName, &r.STRNumber, &r.SIPNumber, &r.SIPPNumber,
			&r.Specialization, &sub, &r.HospitalLat, &r.HospitalLng, &r.HospitalName, &r.AddressDetails,
			&r.IsBPJSSupported, &r.PhotoIntroURL, &r.VideoIntroURL, &r.Bio, &edu, &r.LegacyCount,
			&r.HelpfulnessCount, &r.ReviewCount, &r.YearsExperience, &r.PriceFrom, &r.PatientCount, &available,
			&r.DistanceKM); err != nil {
			return nil, err
		}
		r.IsAvailableToday = available == 1
		parsePGTextArray(sub, &r.SubSpecialties)
		_ = json.Unmarshal(edu, &r.Education)
		out = append(out, r)
	}
	return out, rows.Err()
}

type DoctorSearchParams struct {
	PatientLat      *float64
	PatientLng      *float64
	Specialization  string
	MaxPrice        *int64
	MaxKM           *float64
	IsBPJSSupported *bool
	SortBy          string // name_asc|name_desc|sessions|popular|distance|availability
	Limit           int
}

// Availability scheduling
type ProfessionalSchedule struct {
	ID                  string `json:"id"`
	ProfessionalID      string `json:"professional_id"`
	DayOfWeek           int    `json:"day_of_week"`
	StartTime           string `json:"start_time"`
	EndTime             string `json:"end_time"`
	SlotDurationMinutes int    `json:"slot_duration_minutes"`
	IsActive            bool   `json:"is_active"`
}

func (s *Store) ListSchedulesForProfessional(ctx context.Context, professionalID string) ([]ProfessionalSchedule, error) {
	const q = `SELECT id, professional_id, day_of_week, start_time::text, end_time::text, slot_duration_minutes, is_active
		FROM professional_schedules WHERE professional_id = $1 AND is_active = true ORDER BY day_of_week, start_time`
	rows, err := s.db.QueryContext(ctx, q, professionalID)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var out []ProfessionalSchedule
	for rows.Next() {
		var sch ProfessionalSchedule
		if err := rows.Scan(&sch.ID, &sch.ProfessionalID, &sch.DayOfWeek, &sch.StartTime, &sch.EndTime, &sch.SlotDurationMinutes, &sch.IsActive); err != nil {
			return nil, err
		}
		out = append(out, sch)
	}
	return out, rows.Err()
}

func (s *Store) UpsertSchedules(ctx context.Context, professionalID string, schedules []ProfessionalSchedule) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	if _, err := tx.ExecContext(ctx, `UPDATE professional_schedules SET is_active = false WHERE professional_id = $1`, professionalID); err != nil {
		return err
	}
	// Dedup entri identik dalam satu batch (tidak ada unique constraint di DB).
	seen := make(map[string]ProfessionalSchedule)
	var order []string
	for _, sch := range schedules {
		key := strings.Join([]string{strconv.Itoa(sch.DayOfWeek), strings.TrimSpace(sch.StartTime), strings.TrimSpace(sch.EndTime)}, "|")
		if _, ok := seen[key]; !ok {
			order = append(order, key)
		}
		if sch.SlotDurationMinutes <= 0 {
			sch.SlotDurationMinutes = 30
		}
		seen[key] = sch
	}
	for _, key := range order {
		sch := seen[key]
		const q = `INSERT INTO professional_schedules (professional_id, day_of_week, start_time, end_time, slot_duration_minutes, is_active)
			VALUES ($1, $2, $3, $4, $5, true)`
		if _, err := tx.ExecContext(ctx, q, professionalID, sch.DayOfWeek, sch.StartTime, sch.EndTime, sch.SlotDurationMinutes); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// Service packages
type ServicePackage struct {
	ID                  string `json:"id"`
	ProfessionalID      string `json:"professional_id"`
	PackageSessions     int    `json:"package_sessions"`
	PackageDurationDays int    `json:"package_duration_days"`
	Price               int64  `json:"price"`
	Label               string `json:"label"`
	IsActive            bool   `json:"is_active"`
}

func (s *Store) ListServicePackages(ctx context.Context, professionalID string) ([]ServicePackage, error) {
	const q = `SELECT id, professional_id, package_sessions, package_duration_days, price, label, is_active
		FROM service_packages WHERE professional_id = $1 AND is_active = true ORDER BY package_sessions`
	rows, err := s.db.QueryContext(ctx, q, professionalID)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	var out []ServicePackage
	for rows.Next() {
		var p ServicePackage
		if err := rows.Scan(&p.ID, &p.ProfessionalID, &p.PackageSessions, &p.PackageDurationDays, &p.Price, &p.Label, &p.IsActive); err != nil {
			return nil, err
		}
		out = append(out, p)
	}
	return out, rows.Err()
}

func (s *Store) UpsertServicePackages(ctx context.Context, professionalID string, packages []ServicePackage) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()
	if _, err := tx.ExecContext(ctx, `DELETE FROM service_packages WHERE professional_id = $1`, professionalID); err != nil {
		return err
	}
	for _, p := range packages {
		const q = `INSERT INTO service_packages (professional_id, package_sessions, package_duration_days, price, label)
			VALUES ($1, $2, $3, $4, $5)`
		if _, err := tx.ExecContext(ctx, q, professionalID, p.PackageSessions, p.PackageDurationDays, p.Price, p.Label); err != nil {
			return err
		}
	}
	return tx.Commit()
}
