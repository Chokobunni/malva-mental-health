package store

import (
	"context"
	"database/sql"
	"errors"
	"strings"
	"time"

	"malva/backend/internal/clock"
)

var ErrReviewNotEligible = errors.New("sesi atau paket belum selesai, sudah diulas, atau bukan milik akun ini")

type ReviewEntitlement struct {
	SessionID        string    `json:"session_id,omitempty"`
	CarePackageID    string    `json:"care_package_id,omitempty"`
	ProfessionalID   string    `json:"professional_id"`
	ProfessionalName string    `json:"professional_name"`
	CompletedAt      time.Time `json:"completed_at"`
}

// Scheduled ends stay stable after terminal detail edits; updated_at does not.
// Legacy units lack a separate immutable completion-confirmation timestamp.
// Merged purchases keep their IDs/quotas: allocate counted meetings to purchase
// ranges in calendar order, while renewals append after existing purchase rows.
// Ambiguous ownership, nested merges or invalid quota reconciliation fail closed.
const reviewEntitlementsSQL = `WITH package_roots AS (
 SELECT cp.*, cp.total_sessions-COALESCE((SELECT SUM(child.total_sessions)
   FROM care_packages child WHERE child.merged_into=cp.id AND child.status='merged'),0) AS original_quota
 FROM care_packages cp
 WHERE cp.patient_id=$1 AND cp.status IN ('active','completed','expired') AND cp.merged_into IS NULL
   AND NOT EXISTS (SELECT 1 FROM care_packages child WHERE child.merged_into=cp.id
     AND (child.status<>'merged' OR child.patient_id<>cp.patient_id OR child.professional_id<>cp.professional_id
       OR EXISTS (SELECT 1 FROM care_packages nested WHERE nested.merged_into=child.id)))
   AND NOT EXISTS (SELECT 1 FROM care_sessions cs WHERE cs.package_id=cp.id
     AND (cs.patient_id<>cp.patient_id OR cs.professional_id<>cp.professional_id))
   AND (SELECT COUNT(*) FROM care_sessions cs WHERE cs.package_id=cp.id
     AND cs.status IN ('completed','no_show','scheduled','pending_payment'))<=cp.total_sessions
), purchases AS (
 SELECT cp.id,cp.id AS root_id,cp.patient_id,cp.professional_id,cp.original_quota AS quota,
   0 AS renewal,NULL::timestamptz AS merged_at,cp.created_at
 FROM package_roots cp WHERE cp.original_quota>0
 UNION ALL
 SELECT child.id,cp.id,cp.patient_id,cp.professional_id,child.total_sessions,
   1,child.merged_at,child.created_at
 FROM package_roots cp JOIN care_packages child ON child.merged_into=cp.id AND child.status='merged'
 WHERE cp.original_quota>0
), purchase_ranges AS (
 SELECT purchases.*, SUM(quota) OVER (PARTITION BY root_id ORDER BY renewal,merged_at NULLS FIRST,created_at,id ROWS UNBOUNDED PRECEDING) AS quota_end
 FROM purchases
), counted_meetings AS (
 SELECT cs.*, ROW_NUMBER() OVER (PARTITION BY package_id ORDER BY scheduled_at,id) AS meeting_number
 FROM care_sessions cs WHERE cs.patient_id=$1 AND cs.status IN ('completed','no_show','scheduled','pending_payment')
), units AS (
 SELECT cs.id AS session_id, NULL::uuid AS care_package_id, cs.patient_id, cs.professional_id,
   cs.scheduled_at + cs.duration_minutes * interval '1 minute' AS completed_at
 FROM care_sessions cs WHERE cs.patient_id=$1 AND cs.package_id IS NULL AND cs.status='completed'
 UNION ALL
 SELECT NULL::uuid,p.id,p.patient_id,p.professional_id,
   MAX(cs.scheduled_at + cs.duration_minutes * interval '1 minute')
 FROM purchase_ranges p JOIN counted_meetings cs ON cs.package_id=p.root_id
   AND cs.meeting_number>p.quota_end-p.quota AND cs.meeting_number<=p.quota_end
 WHERE NOT EXISTS (SELECT 1 FROM counted_meetings preceding
   WHERE preceding.package_id=p.root_id AND preceding.meeting_number<=p.quota_end
     AND preceding.status NOT IN ('completed','no_show'))
 GROUP BY p.id,p.patient_id,p.professional_id,p.quota
 HAVING COUNT(*)=p.quota AND bool_and(cs.status IN ('completed','no_show'))
   AND COUNT(*) FILTER (WHERE cs.status='completed')>0
)
SELECT COALESCE(units.session_id::text,''), COALESCE(units.care_package_id::text,''),
 units.professional_id, COALESCE(u.display_name,'Profesional'), units.completed_at
FROM units LEFT JOIN users u ON u.id=units.professional_id
WHERE ($2='' OR units.professional_id::text=$2)
 AND NOT EXISTS (SELECT 1 FROM doctor_reviews r WHERE r.session_id=units.session_id OR r.care_package_id=units.care_package_id)
 AND NOT EXISTS (SELECT 1 FROM doctor_reviews r WHERE r.patient_id=units.patient_id
   AND r.professional_id=units.professional_id AND r.session_id IS NULL AND r.care_package_id IS NULL
   AND (r.created_at IS NULL OR r.created_at >= units.completed_at))
ORDER BY units.completed_at, units.session_id, units.care_package_id`

type reviewQuerier interface {
	QueryContext(context.Context, string, ...any) (*sql.Rows, error)
}

func listReviewEntitlements(ctx context.Context, db reviewQuerier, patientID, professionalID string) ([]ReviewEntitlement, error) {
	rows, err := db.QueryContext(ctx, reviewEntitlementsSQL, patientID, professionalID)
	if err != nil {
		return nil, err
	}
	defer func() { _ = rows.Close() }()
	out := make([]ReviewEntitlement, 0)
	for rows.Next() {
		var e ReviewEntitlement
		if err := rows.Scan(&e.SessionID, &e.CarePackageID, &e.ProfessionalID, &e.ProfessionalName, &e.CompletedAt); err != nil {
			return nil, err
		}
		out = append(out, e)
	}
	return out, rows.Err()
}

func (s *Store) ListReviewEntitlements(ctx context.Context, patientID, professionalID string) ([]ReviewEntitlement, error) {
	return listReviewEntitlements(ctx, s.db, patientID, professionalID)
}

func (s *Store) CreateDoctorReviewForEntitlement(ctx context.Context, professionalID, patientID string, stars int, reviewText string, helpful bool, sessionID, packageID string) (DoctorReview, error) {
	if err := ValidateDoctorReview(stars, reviewText); err != nil {
		return DoctorReview{}, err
	}
	if sessionID != "" && packageID != "" {
		return DoctorReview{}, ErrReviewNotEligible
	}
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return DoctorReview{}, err
	}
	defer func() { _ = tx.Rollback() }()
	// Serialize old and new clients before checking eligibility; uniqueness also
	// protects each unit independently of the patient/professional lock.
	if _, err = tx.ExecContext(ctx, `SELECT pg_advisory_xact_lock(hashtextextended($1,0))`, patientID+":"+professionalID); err != nil {
		return DoctorReview{}, err
	}
	eligible, err := listReviewEntitlements(ctx, tx, patientID, professionalID)
	if err != nil {
		return DoctorReview{}, err
	}
	var selected *ReviewEntitlement
	for i := range eligible {
		e := &eligible[i]
		if (sessionID == "" && packageID == "") || (sessionID != "" && e.SessionID == sessionID) || (packageID != "" && e.CarePackageID == packageID) {
			selected = e
			break
		}
	}
	if selected == nil {
		return DoctorReview{}, ErrReviewNotEligible
	}
	var rv DoctorReview
	err = tx.QueryRowContext(ctx, `INSERT INTO doctor_reviews(professional_id,patient_id,helpfulness_percent,review_text,helpful,session_id,care_package_id,created_at)
 VALUES($1,$2,$3,$4,$5,NULLIF($6,'')::uuid,NULLIF($7,'')::uuid,$8) RETURNING id,created_at`, professionalID, patientID, stars*20, strings.TrimSpace(reviewText), helpful, selected.SessionID, selected.CarePackageID, clock.Now()).Scan(&rv.ID, &rv.CreatedAt)
	if err != nil {
		return DoctorReview{}, err
	}
	if err = tx.Commit(); err != nil {
		return DoctorReview{}, err
	}
	rv.ProfessionalID = professionalID
	rv.PatientID = patientID
	rv.Stars = stars
	rv.ReviewText = strings.TrimSpace(reviewText)
	rv.Helpful = helpful
	return rv, nil
}
