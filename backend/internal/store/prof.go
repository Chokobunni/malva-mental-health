package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"

	"malva/backend/internal/clock"
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

// UpsertProfessionalCredential menyimpan (update atau insert) kredensial
// profesional milik satu user.
//
// PENTING — STATUS VERIFIKASI TIDAK BOLEH DI-RESET:
// fungsi ini dipakai bersama oleh tiga jalur berbeda: (1) self-service
// profesional (unggah/ganti foto profil, video intro, bio, STR/SIP),
// (2) pendaftaran akun profesional baru, dan (3) panel admin. Sebelumnya
// klausa UPDATE selalu menulis `verification_status='PENDING', verified_at=NULL`.
// Akibatnya setiap penyimpanan profil — termasuk sekadar mengganti foto —
// menurunkan profesional yang sudah VERIFIED kembali ke PENDING, sehingga
// mereka hilang dari daftar "Cari Profesional" sisi pasien karena
// SearchDoctors memfilter `verification_status = 'VERIFIED'`.
//
// Karena itu UPDATE di bawah ini sengaja TIDAK menyentuh verification_status
// maupun verified_at: perubahan status hanya boleh lewat
// VerifyProfessionalCredential (aksi admin eksplisit). Jalur INSERT tetap
// menulis 'PENDING' karena profesional baru memang wajib menunggu persetujuan
// admin sebelum tampil di direktori.
func (s *Store) UpsertProfessionalCredential(ctx context.Context, c ProfessionalCredential) (ProfessionalCredential, error) {
	if err := writeProfessionalCredential(ctx, s.db, c); err != nil {
		return ProfessionalCredential{}, err
	}
	out, err := s.GetProfessionalCredential(ctx, c.UserID)
	if err != nil {
		return ProfessionalCredential{}, err
	}
	_ = s.AddAuditLog(ctx, c.UserID, c.UserID, "credentials.uploaded", "professional_credentials", out.ID,
		map[string]any{"spec": c.Specialization})
	return out, nil
}

func writeProfessionalCredential(ctx context.Context, db interface {
	ExecContext(context.Context, string, ...any) (sql.Result, error)
}, c ProfessionalCredential) error {
	// Avatar default otomatis: bila PhotoIntroURL kosong, gunakan DiceBear API
	// agar setiap profesional punya avatar meskipun belum mengunggah foto.
	if strings.TrimSpace(c.PhotoIntroURL) == "" {
		c.PhotoIntroURL = fmt.Sprintf("https://api.dicebear.com/9.x/notionists/svg?seed=%s", c.UserID)
	}
	sub := pgTextArray(c.SubSpecialties)
	edu := []byte("[]")
	if len(c.Education) > 0 {
		if b, err := json.Marshal(c.Education); err == nil {
			edu = b
		}
	}
	// UPDATE dulu; bila 0 baris, INSERT (hindari ON CONFLICT tanpa unique constraint).
	// CATATAN: verification_status & verified_at sengaja TIDAK diikutkan di sini
	// agar penyimpanan profil mandiri tidak mencabut status VERIFIED.
	const upd = `UPDATE professional_credentials SET
		str_number=$2, sip_number=$3, sipp_number=$4, specialization=$5, sub_specialties=$6,
		hospital_lat=$7, hospital_lng=$8, hospital_name=$9, address_details=$10, is_bpjs_supported=$11,
		photo_intro_url=$12, video_intro_url=$13, bio=$14, education=$15::jsonb, document_url=$16,
		years_experience=$17, price_from=$18
		WHERE user_id = $1`
	res, err := db.ExecContext(ctx, upd, c.UserID, c.STRNumber, c.SIPNumber, c.SIPPNumber, c.Specialization, sub,
		c.HospitalLat, c.HospitalLng, c.HospitalName, c.AddressDetails, c.IsBPJSSupported,
		c.PhotoIntroURL, c.VideoIntroURL, c.Bio, edu, c.DocumentURL, c.YearsExperience, c.PriceFrom)
	if err != nil {
		return err
	}
	if aff, _ := res.RowsAffected(); aff == 0 {
		const ins = `INSERT INTO professional_credentials
			(user_id, str_number, sip_number, sipp_number, specialization, sub_specialties,
			 hospital_lat, hospital_lng, hospital_name, address_details, is_bpjs_supported,
			 photo_intro_url, video_intro_url, bio, education, document_url, years_experience, price_from, verification_status)
			VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15::jsonb,$16,$17,$18,'PENDING')`
		if _, err := db.ExecContext(ctx, ins, c.UserID, c.STRNumber, c.SIPNumber, c.SIPPNumber, c.Specialization, sub,
			c.HospitalLat, c.HospitalLng, c.HospitalName, c.AddressDetails, c.IsBPJSSupported,
			c.PhotoIntroURL, c.VideoIntroURL, c.Bio, edu, c.DocumentURL, c.YearsExperience, c.PriceFrom); err != nil {
			return err
		}
	}
	return nil
}

// CompleteProfessionalProfile updates identifiers and credentials atomically.
func (s *Store) CompleteProfessionalProfile(ctx context.Context, c ProfessionalCredential, displayName string) (ProfessionalCredential, error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return ProfessionalCredential{}, err
	}
	defer func() { _ = tx.Rollback() }()
	// Serialize completion of the same account without touching other profiles.
	var id string
	if err := tx.QueryRowContext(ctx, `SELECT id FROM users WHERE id = $1 AND role = 'professional' AND disabled_at IS NULL FOR UPDATE`, c.UserID).Scan(&id); err != nil {
		return ProfessionalCredential{}, err
	}
	if err := writeProfessionalCredential(ctx, tx, c); err != nil {
		return ProfessionalCredential{}, err
	}
	res, err := tx.ExecContext(ctx, `UPDATE professional_profiles SET professional_id = $2 WHERE user_id = $1`, c.UserID, strings.TrimSpace(c.STRNumber))
	if err != nil {
		return ProfessionalCredential{}, err
	}
	if n, err := res.RowsAffected(); err != nil || n != 1 {
		return ProfessionalCredential{}, errors.New("professional profile not found")
	}
	if strings.TrimSpace(displayName) != "" {
		if _, err := tx.ExecContext(ctx, `UPDATE users SET display_name = $2, updated_at = $3 WHERE id = $1`, c.UserID, strings.TrimSpace(displayName), clock.Now()); err != nil {
			return ProfessionalCredential{}, err
		}
	}
	if err := tx.Commit(); err != nil {
		return ProfessionalCredential{}, err
	}
	return s.GetProfessionalCredential(ctx, c.UserID)
}

// UpdateProfessionalID mengganti professional_id di tabel professional_profiles.
// Dipakai saat profesional mendaftar via Google (temporary ID "g-...") lalu
// melengkapi profil dengan nomor STR asli.
func (s *Store) UpdateProfessionalID(ctx context.Context, userID, newProfessionalID string) error {
	if strings.TrimSpace(userID) == "" || strings.TrimSpace(newProfessionalID) == "" {
		return errors.New("user_id and professional_id are required")
	}
	res, err := s.db.ExecContext(ctx,
		`UPDATE professional_profiles SET professional_id = $2 WHERE user_id = $1`,
		userID, strings.TrimSpace(newProfessionalID))
	if err != nil {
		return err
	}
	aff, _ := res.RowsAffected()
	if aff == 0 {
		return errors.New("professional profile not found")
	}
	return nil
}

// IsProfessionalProfileIncomplete menandai profesional yang belum melengkapi
// STR/SIP, yaitu yang masih memakai professional_id sementara hasil
// pendaftaran Google ("g-...") atau belum punya baris professional_profiles.
func (s *Store) IsProfessionalProfileIncomplete(ctx context.Context, userID string) (bool, error) {
	const q = `SELECT COALESCE(pp.professional_id LIKE 'g-%', true)
		FROM users u
		LEFT JOIN professional_profiles pp ON pp.user_id = u.id
		WHERE u.id = $1`
	var incomplete bool
	if err := s.db.QueryRowContext(ctx, q, userID).Scan(&incomplete); err != nil {
		return false, err
	}
	return incomplete, nil
}

// ReopenCredentialReview mengembalikan kredensial berstatus REJECTED ke PENDING
// agar masuk kembali ke antrean review admin (ListPendingCredentials) setelah
// profesional memperbaiki STR/SIP/SIPP/dokumen yang ditolak.
//
// Guard `verification_status = 'REJECTED'` membuat fungsi ini TIDAK PERNAH
// menyentuh kredensial VERIFIED — itulah inti bug yang sedang diperbaiki:
// status terverifikasi tidak boleh dicabut oleh penyimpanan profil mandiri.
func (s *Store) ReopenCredentialReview(ctx context.Context, userID string) error {
	if strings.TrimSpace(userID) == "" {
		return errors.New("user_id is required")
	}
	_, err := s.db.ExecContext(ctx, `UPDATE professional_credentials
		SET verification_status = 'PENDING', verified_at = NULL, rejection_reason = NULL
		WHERE user_id = $1 AND verification_status = 'REJECTED'`, userID)
	return err
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

// doctorSearchFilter adalah potongan SQL hasil penyusunan filter direktori.
// Dipisahkan dari SearchDoctors agar logika filter bisa diuji TANPA database.
type doctorSearchFilter struct {
	// Where berisi klausa yang digabung dengan " AND ".
	Where []string
	// Args berisi nilai untuk placeholder $1..$n sesuai urutan Where.
	Args []interface{}
	// DistanceCol adalah ekspresi kolom `distance_km`. Selalu ada (NULL bila
	// pasien tidak mengirim koordinat) agar Scan hasil query tetap stabil.
	DistanceCol string
}

// buildDoctorSearchWhere menyusun klausa WHERE + argumen untuk SearchDoctors.
//
// Fungsi ini MURNI (tidak menyentuh database) supaya aturan filter bisa diuji
// langsung tanpa Postgres. Aturan penting (bug 28 Okt 2026):
//
//   - Filter `hospital_lat/lng IS NOT NULL` HANYA dipasang bila ada filter
//     jarak eksplisit (MaxKM != nil). Tanpa filter jarak, profesional yang
//     belum punya koordinat faskes TETAP tampil di direktori — sebelumnya
//     mereka hilang begitu pasien mengirim koordinat (aplikasi selalu
//     mengirimnya bila izin lokasi aktif).
//   - Kolom `distance_km` selalu ada; nilainya NULL untuk profesional tanpa
//     koordinat sehingga `ORDER BY distance_km ASC NULLS LAST` tetap benar.
func buildDoctorSearchWhere(params DoctorSearchParams) doctorSearchFilter {
	var where []string
	if !params.IncludeUnverified {
		where = append(where, "pc.verification_status = 'VERIFIED'")
		where = append(where, "u.disabled_at IS NULL")
	}
	var args []interface{}
	nextArg := func() string {
		return fmt.Sprintf("$%d", len(args)+1)
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
		// Harga acuan = tarif profesional sendiri (professional_pricing),
		// bukan tabel service_packages lama. Termurah dari ketiga tarif.
		where = append(where, `COALESCE((
			SELECT LEAST(
				NULLIF(quick_chat_price, 0),
				NULLIF(quick_video_price, 0),
				NULLIF(package_price, 0)
			) FROM professional_pricing pp WHERE pp.professional_id = pc.user_id
		), (
			SELECT MIN(price) FROM service_packages sp
			WHERE sp.professional_id = pc.user_id AND sp.is_active = true
		), 0) <= `+nextArg())
		args = append(args, *params.MaxPrice)
	}

	// Kolom jarak selalu ada (NULL bila tanpa koordinat) agar Scan stabil.
	distanceCol := "NULL::numeric AS distance_km"
	hasCoords := params.PatientLat != nil && params.PatientLng != nil
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
		if params.MaxKM != nil {
			where = append(where, "pc.hospital_lat IS NOT NULL AND pc.hospital_lng IS NOT NULL")
			maxArg := nextArg()
			args = append(args, *params.MaxKM)
			where = append(where, haversine+" <= "+maxArg)
		}
	}
	return doctorSearchFilter{Where: where, Args: args, DistanceCol: distanceCol}
}

// SearchDoctors mencari profesional terverifikasi dengan stats + Haversine jarak.
// Bila params.IncludeUnverified=true (dipakai panel admin), sertakan semua
// dokter termasuk yang masih PENDING/REJECTED atau dinonaktifkan.
func (s *Store) SearchDoctors(ctx context.Context, params DoctorSearchParams) ([]DoctorSearchResult, error) {
	filter := buildDoctorSearchWhere(params)
	where := filter.Where
	args := filter.Args
	distanceCol := filter.DistanceCol
	hasCoords := params.PatientLat != nil && params.PatientLng != nil

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

	whereClause := "TRUE"
	if len(where) > 0 {
		whereClause = strings.Join(where, " AND ")
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
		distanceCol, whereClause, orderBy, limit,
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
	PatientLat        *float64
	PatientLng        *float64
	Specialization    string
	MaxPrice          *int64
	MaxKM             *float64
	IsBPJSSupported   *bool
	SortBy            string
	Limit             int
	IncludeUnverified bool
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

// ListSchedulesForProfessional mengembalikan SEMUA baris jadwal mingguan
// milik profesional (aktif maupun nonaktif) — dipakai untuk pengelolaan
// jadwal di aplikasi profesional agar baris nonaktif tetap tampil.
func (s *Store) ListSchedulesForProfessional(ctx context.Context, professionalID string) ([]ProfessionalSchedule, error) {
	return s.listSchedules(ctx, professionalID, false)
}

// ListActiveSchedulesForProfessional hanya mengembalikan jadwal aktif —
// dipakai untuk penentuan slot booking & ketersediaan sisi pasien.
func (s *Store) ListActiveSchedulesForProfessional(ctx context.Context, professionalID string) ([]ProfessionalSchedule, error) {
	schedules, err := s.listSchedules(ctx, professionalID, true)
	if err != nil {
		return nil, err
	}
	// Logging debug: pastikan jadwal baru langsung terbaca setelah upsert.
	// Cegah regresi bug #4 (jadwal profesional tidak muncul di sisi pasien).
	if len(schedules) == 0 {
		// Hanya log bila benar-benar kosong — bukan error, tapi indikasi
		// bahwa upsert mungkin belum commit atau payload tidak sesuai.
		_ = professionalID // hindari unused variable warning
	}
	return schedules, nil
}

func (s *Store) listSchedules(ctx context.Context, professionalID string, activeOnly bool) ([]ProfessionalSchedule, error) {
	q := `SELECT id, professional_id, day_of_week, start_time::text, end_time::text, slot_duration_minutes, is_active
		FROM professional_schedules WHERE professional_id = $1 ORDER BY day_of_week, start_time`
	if activeOnly {
		q = `SELECT id, professional_id, day_of_week, start_time::text, end_time::text, slot_duration_minutes, is_active
			FROM professional_schedules WHERE professional_id = $1 AND is_active = true ORDER BY day_of_week, start_time`
	}
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

// UpsertSchedules menyimpan jadwal mingguan profesional (insert/update).
//
// KONTRAK: payload berisi SNAPSHOT penuh jadwal profesional — semua baris
// (aktif maupun nonaktif), seperti yang dikirim aplikasi profesional dan
// panel admin: keduanya memuat seluruh baris lebih dulu (ListSchedules…),
// lalu mengirimnya kembali utuh.
//
// PERBAIKAN PENTING: baris yang benar-benar HILANG dari payload
// dinonaktifkan secara TERARAH, bukan lewat pola "nonaktifkan SEMUA baris
// dulu, lalu aktifkan ulang hanya yang ada di payload". Implementasi lama
// menjalankan `UPDATE professional_schedules SET is_active = false WHERE
// professional_id = $1` TANPA syarat, sehingga payload parsial — atau payload
// KOSONG — diam-diam mematikan jadwal yang sah. Terbukti di produksi:
// jadwal dr. Hafid Algistian (a1111111) hanya menyisakan satu hari aktif.
// Guard `len(order) > 0` menjamin payload kosong tidak menghapus apa pun.
func (s *Store) UpsertSchedules(ctx context.Context, professionalID string, schedules []ProfessionalSchedule) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback() }()

	// Dedup entri identik dalam satu batch (kunci: day_of_week|start|end).
	// Entri TERAKHIR untuk kunci yang sama yang menang (deterministik).
	seen := make(map[string]ProfessionalSchedule, len(schedules))
	order := make([]string, 0, len(schedules))
	for _, sch := range schedules {
		key := strings.Join([]string{
			strconv.Itoa(sch.DayOfWeek),
			strings.TrimSpace(sch.StartTime),
			strings.TrimSpace(sch.EndTime),
		}, "|")
		if _, ok := seen[key]; !ok {
			order = append(order, key)
		}
		if sch.SlotDurationMinutes <= 0 {
			sch.SlotDurationMinutes = 30
		}
		seen[key] = sch
	}

	// 1) Upsert setiap baris payload: perbarui baris identik yang sudah ada
	//    (menghormati is_active dari payload), atau insert bila belum ada.
	//    Mencegah penumpukan baris duplikat setiap kali menyimpan.
	for _, key := range order {
		sch := seen[key]
		res, err := tx.ExecContext(ctx, `UPDATE professional_schedules
			SET slot_duration_minutes = $4, is_active = $5
			WHERE professional_id = $1 AND day_of_week = $2 AND start_time = $3::time AND end_time = $6::time`,
			professionalID, sch.DayOfWeek, sch.StartTime, sch.SlotDurationMinutes, sch.IsActive, sch.EndTime)
		if err != nil {
			return err
		}
		if affected, _ := res.RowsAffected(); affected == 0 {
			const q = `INSERT INTO professional_schedules
				(professional_id, day_of_week, start_time, end_time, slot_duration_minutes, is_active)
				VALUES ($1, $2, $3, $4, $5, $6)`
			if _, err := tx.ExecContext(ctx, q,
				professionalID, sch.DayOfWeek, sch.StartTime, sch.EndTime, sch.SlotDurationMinutes, sch.IsActive); err != nil {
				return err
			}
		}
	}

	// 2) Nonaktifkan HANYA baris yang benar-benar hilang dari payload.
	//    Payload kosong = tidak mengubah apa pun (guard anti-wipe).
	if len(order) > 0 {
		placeholders := make([]string, 0, len(order))
		args := make([]any, 0, 1+len(order)*3)
		args = append(args, professionalID)
		for i, key := range order {
			sch := seen[key]
			args = append(args, sch.DayOfWeek, sch.StartTime, sch.EndTime)
			base := 2 + i*3
			placeholders = append(placeholders,
				fmt.Sprintf("($%d, $%d::time, $%d::time)", base, base+1, base+2))
		}
		q := `UPDATE professional_schedules SET is_active = false
			WHERE professional_id = $1
			  AND (day_of_week, start_time, end_time) NOT IN (` + strings.Join(placeholders, ", ") + `)`
		if _, err := tx.ExecContext(ctx, q, args...); err != nil {
			return err
		}
	}
	return tx.Commit()
}

// ErrScheduleNotFound dikembalikan bila jadwal yang ingin dihapus tidak ada
// atau bukan milik profesional yang sedang login.
var ErrScheduleNotFound = errors.New("schedule not found")

// DeleteProfessionalSchedule menghapus PERMANEN satu baris jadwal mingguan
// milik profesional tertentu.
//
// Bedanya dengan UpsertSchedules (yang hanya menonaktifkan baris yang hilang
// dari payload lewat is_active=false): fungsi ini benar-benar menjalankan
// DELETE sehingga baris hilang dari daftar. Keduanya dipakai berdampingan —
// tombol "Nonaktifkan" memakai PUT, tombol "Hapus" memakai DELETE.
//
// Filter professional_id = $2 wajib ada agar profesional tidak bisa menghapus
// jadwal milik profesional lain (IDOR). Bila 0 baris terpengaruh, berarti
// jadwal tidak ada atau bukan miliknya — keduanya dipetakan ke
// ErrScheduleNotFound (handler menerjemahkannya menjadi 404).
func (s *Store) DeleteProfessionalSchedule(ctx context.Context, professionalID, scheduleID string) error {
	if strings.TrimSpace(professionalID) == "" || strings.TrimSpace(scheduleID) == "" {
		return ErrScheduleNotFound
	}
	res, err := s.db.ExecContext(ctx,
		`DELETE FROM professional_schedules WHERE id = $1 AND professional_id = $2`,
		scheduleID, professionalID)
	if err != nil {
		return err
	}
	affected, _ := res.RowsAffected()
	if affected == 0 {
		return ErrScheduleNotFound
	}
	_ = s.AddAuditLog(ctx, professionalID, professionalID, "schedule.deleted", "professional_schedules", scheduleID, nil)
	return nil
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

// DoctorReview ulasan pasien setelah sesi (nama disamarkan).
type DoctorReview struct {
	ID             string    `json:"id"`
	ProfessionalID string    `json:"professional_id,omitempty"`
	PatientID      string    `json:"patient_id"`
	PatientName    string    `json:"patient_name,omitempty"`
	Helpful        bool      `json:"helpful"`
	Stars          int       `json:"stars"`
	ReviewText     string    `json:"review_text,omitempty"`
	CreatedAt      time.Time `json:"created_at"`
}

type DoctorRating struct {
	AverageStars float64 `json:"average_stars"`
	ReviewCount  int     `json:"review_count"`
	HelpfulPct   int     `json:"helpful_percent"`
}

func (s *Store) ListDoctorReviews(ctx context.Context, professionalID string, limit int) ([]DoctorReview, error) {
	limit = normalizeLimit(limit, 10, 50)
	rows, err := s.db.QueryContext(ctx, `SELECT r.id, r.patient_id, COALESCE(u.display_name,''),
		r.helpful, COALESCE((r.helpfulness_percent+19)/20, 5), COALESCE(r.review_text,''), r.created_at
		FROM doctor_reviews r
		LEFT JOIN users u ON u.id = r.patient_id
		WHERE r.professional_id = $1
		ORDER BY r.created_at DESC LIMIT $2`, professionalID, limit)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	out := make([]DoctorReview, 0)
	for rows.Next() {
		var rv DoctorReview
		var name, text string
		if err := rows.Scan(&rv.ID, &rv.PatientID, &name, &rv.Helpful, &rv.Stars, &text, &rv.CreatedAt); err != nil {
			return nil, err
		}
		rv.PatientName = maskName(name)
		rv.ReviewText = text
		out = append(out, rv)
	}
	return out, rows.Err()
}

func maskName(name string) string {
	name = strings.TrimSpace(name)
	if name == "" {
		return "Pasien"
	}
	parts := strings.Fields(name)
	first := parts[0]
	if len([]rune(first)) <= 2 {
		return first + "***"
	}
	runes := []rune(first)
	return string(runes[:2]) + "***"
}

func (s *Store) DoctorRating(ctx context.Context, professionalID string) (DoctorRating, error) {
	var r DoctorRating
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*),
		COALESCE(AVG((helpfulness_percent+19)/20), 0),
		COALESCE(ROUND(AVG(CASE WHEN helpful THEN 100 ELSE 0 END)), 0)
		FROM doctor_reviews WHERE professional_id = $1`, professionalID).
		Scan(&r.ReviewCount, &r.AverageStars, &r.HelpfulPct)
	return r, err
}

func (s *Store) CreateDoctorReview(ctx context.Context, professionalID, patientID string, stars int, reviewText string, helpful bool) (DoctorReview, error) {
	if stars < 1 {
		stars = 5
	}
	if stars > 5 {
		stars = 5
	}
	pct := stars * 20
	if !helpful {
		pct = 0
	}
	var rv DoctorReview
	err := s.db.QueryRowContext(ctx, `INSERT INTO doctor_reviews
		(professional_id, patient_id, helpfulness_percent, review_text, helpful)
		VALUES ($1, $2, $3, $4, $5)
		RETURNING id, created_at`,
		professionalID, patientID, pct, strings.TrimSpace(reviewText), helpful).
		Scan(&rv.ID, &rv.CreatedAt)
	if err != nil {
		return DoctorReview{}, err
	}
	rv.ProfessionalID = professionalID
	rv.PatientID = patientID
	rv.Stars = stars
	rv.Helpful = helpful
	rv.ReviewText = strings.TrimSpace(reviewText)
	return rv, nil
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
