package server

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/store"
)

// ============================================================
// CONSENT KATEGORI "THERAPY RECORD"
//
// Sebelumnya pasien hanya bisa membagikan worksheet terapi satu per satu
// (POST /v1/therapy-submissions/{id}/share). Sekarang ada izin kategori di
// Manage Data (kolom share_therapy_records, migrasi 023):
//   - MATI (default) -> profesional hanya melihat worksheet yang dibagikan
//     individual (perilaku lama dipertahankan),
//   - HIDUP           -> profesional melihat SEMUA worksheet pasien itu.
// Izin hanya berlaku untuk pasangan pasien-profesional yang terhubung.
// ============================================================

type therapyConsentFixture struct {
	srv     *Server
	db      *sql.DB
	st      *store.Store
	patient store.User
	prof    store.User
	other   store.User
}

func newTherapyConsentFixture(t *testing.T) therapyConsentFixture {
	t.Helper()
	db, st := openOnboardingTestStore(t)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      fmt.Sprint("STR-TC-", time.Now().UnixNano()),
		SIPNumber:      fmt.Sprint("SIP-TC-", time.Now().UnixNano()),
	})
	other := createIdentityTestUser(t, db, st, "patient", nil)
	// Profesional harus terhubung dengan pasien (syarat resolvePatientScope).
	if _, err := st.LinkPatientToProfessional(context.Background(), patient.ID, prof.ID); err != nil {
		t.Fatalf("hubungkan pasien-profesional: %v", err)
	}
	return therapyConsentFixture{
		srv:     newOnboardingTestServer(db),
		db:      db,
		st:      st,
		patient: patient,
		prof:    prof,
		other:   other,
	}
}

// seedSubmissions membuat 2 worksheet: satu dibagikan ke profesional, satu
// tidak dibagikan ke siapa pun.
func (f therapyConsentFixture) seedSubmissions(t *testing.T) (shared, private store.TherapySubmission) {
	t.Helper()
	ctx := context.Background()
	profID := f.prof.ID
	shared, err := f.st.CreateTherapySubmission(ctx, f.patient.ID, "cbt-abcde",
		"ABCDE — dibagikan", json.RawMessage(`{"a":"x"}`), "ringkasan", &profID)
	if err != nil {
		t.Fatalf("buat submission dibagikan: %v", err)
	}
	private, err = f.st.CreateTherapySubmission(ctx, f.patient.ID, "dbt-tipp",
		"TIPP — privat", json.RawMessage(`{"b":"y"}`), "ringkasan", nil)
	if err != nil {
		t.Fatalf("buat submission privat: %v", err)
	}
	return shared, private
}

// listForProfessional memanggil handler sebagai profesional yang menelusuri
// worksheet satu pasien.
func (f therapyConsentFixture) listForProfessional(t *testing.T, patientID string) []store.TherapySubmission {
	t.Helper()
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet,
		"/v1/therapy-submissions?patient_id="+patientID, nil)
	f.srv.listTherapySubmissions(rec, req, auth.Claims{Subject: f.prof.ID, Role: "professional"})
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, mau 200 (body: %s)", rec.Code, rec.Body.String())
	}
	var payload struct {
		Submissions []store.TherapySubmission `json:"submissions"`
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("body bukan JSON: %v", err)
	}
	return payload.Submissions
}

// TestTherapyRecordsConsentOffShowsOnlyShared: tanpa izin kategori, perilaku
// lama berlaku — profesional hanya melihat worksheet yang dibagikan ke dirinya.
func TestTherapyRecordsConsentOffShowsOnlyShared(t *testing.T) {
	f := newTherapyConsentFixture(t)
	shared, private := f.seedSubmissions(t)

	got := f.listForProfessional(t, f.patient.ID)
	if len(got) != 1 || got[0].ID != shared.ID {
		t.Fatalf("submissions = %+v, mau hanya yang dibagikan (%q)", got, shared.ID)
	}
	for _, sub := range got {
		if sub.ID == private.ID {
			t.Fatalf("worksheet privat tidak boleh terlihat tanpa izin kategori")
		}
	}
}

// TestTherapyRecordsConsentOnShowsAll: izin kategori aktif -> profesional
// melihat SEMUA worksheet pasien, termasuk yang tidak dibagikan individual.
func TestTherapyRecordsConsentOnShowsAll(t *testing.T) {
	f := newTherapyConsentFixture(t)
	shared, private := f.seedSubmissions(t)
	ctx := context.Background()

	if _, err := f.st.UpdatePatientDataConsent(ctx, store.PatientDataConsent{
		PatientID:           f.patient.ID,
		ProfessionalID:      f.prof.ID,
		ShareTherapyRecords: true,
	}); err != nil {
		t.Fatalf("simpan consent: %v", err)
	}

	got := f.listForProfessional(t, f.patient.ID)
	if len(got) != 2 {
		t.Fatalf("submissions = %d, mau 2 (semua worksheet pasien)", len(got))
	}
	ids := map[string]bool{}
	for _, sub := range got {
		ids[sub.ID] = true
	}
	if !ids[shared.ID] || !ids[private.ID] {
		t.Errorf("submissions = %+v, mau memuat %q dan %q", got, shared.ID, private.ID)
	}
}

// TestPrivacyConsentRoundTripsTherapyRecords: PUT menyimpan dan GET
// mengembalikan share_therapy_records apa adanya (kontrak HTTP).
func TestPrivacyConsentRoundTripsTherapyRecords(t *testing.T) {
	f := newTherapyConsentFixture(t)

	body := map[string]any{
		"professional_id":       f.prof.ID,
		"share_screenings":      true,
		"share_mood_diary":      false,
		"share_medications":     false,
		"share_timeline":        false,
		"share_health_record":   false,
		"share_goals":           false,
		"share_therapy_records": true,
	}
	raw, _ := json.Marshal(body)
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPut, "/v1/privacy/consents", bytes.NewReader(raw))
	f.srv.updatePrivacyConsent(rec, req, auth.Claims{Subject: f.patient.ID, Role: "patient"})
	if rec.Code != http.StatusOK {
		t.Fatalf("PUT status = %d, mau 200 (body: %s)", rec.Code, rec.Body.String())
	}

	getRec := httptest.NewRecorder()
	getReq := httptest.NewRequest(http.MethodGet,
		"/v1/privacy/consents?professional_id="+f.prof.ID, nil)
	f.srv.getPrivacyConsent(getRec, getReq, auth.Claims{Subject: f.patient.ID, Role: "patient"})
	if getRec.Code != http.StatusOK {
		t.Fatalf("GET status = %d, mau 200 (body: %s)", getRec.Code, getRec.Body.String())
	}
	var payload struct {
		Consent store.PatientDataConsent `json:"consent"`
	}
	if err := json.Unmarshal(getRec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("body bukan JSON: %v", err)
	}
	if !payload.Consent.ShareTherapyRecords {
		t.Errorf("share_therapy_records = false, mau true setelah PUT")
	}
	if !payload.Consent.ShareScreenings {
		t.Errorf("share_screenings = false, mau true (kategori lain tidak boleh ikut berubah)")
	}

	// Default MATI: pasangan lain belum pernah menyimpan consent.
	otherConsent, err := f.st.GetPatientDataConsent(context.Background(), f.patient.ID, f.other.ID)
	if err != nil {
		t.Fatalf("baca consent default: %v", err)
	}
	if otherConsent.ShareTherapyRecords {
		t.Error("share_therapy_records default harus MATI (opt-in)")
	}
}

// TestTherapyRecordsOtherPatientCannotSee: parameter `patient_id` diabaikan
// untuk peran pasien (endpoint selalu memakai klaim subjek), sehingga pasien
// lain hanya menerima daftarnya sendiri — bukan 403, dan yang penting tidak
// ada worksheet pasien lain yang bocor.
func TestTherapyRecordsOtherPatientCannotSee(t *testing.T) {
	f := newTherapyConsentFixture(t)
	f.seedSubmissions(t)

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet,
		"/v1/therapy-submissions?patient_id="+f.patient.ID, nil)
	f.srv.listTherapySubmissions(rec, req, auth.Claims{Subject: f.other.ID, Role: "patient"})
	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, mau 200 (pasien selalu melihat daftarnya sendiri): %s",
			rec.Code, rec.Body.String())
	}
	if bytes.Contains(rec.Body.Bytes(), []byte("cbt-abcde")) ||
		bytes.Contains(rec.Body.Bytes(), []byte("dbt-tipp")) {
		t.Fatalf("body tidak boleh membocorkan worksheet pasien lain: %s", rec.Body.String())
	}
}

// TestTherapyRecordsUnlinkedProfessionalForbidden: profesional yang tidak
// terhubung dengan pasien tidak boleh menelusuri worksheet pasien itu.
func TestTherapyRecordsUnlinkedProfessionalForbidden(t *testing.T) {
	f := newTherapyConsentFixture(t)
	f.seedSubmissions(t)
	// Profesional lain, tidak punya relasi dengan pasien ini.
	unlinked := createIdentityTestUser(t, f.db, f.st, "professional",
		&store.ProfessionalCredential{
			Specialization: "Sp.KJ",
			STRNumber:      fmt.Sprint("STR-TC2-", time.Now().UnixNano()),
			SIPNumber:      fmt.Sprint("SIP-TC2-", time.Now().UnixNano()),
		})

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet,
		"/v1/therapy-submissions?patient_id="+f.patient.ID, nil)
	f.srv.listTherapySubmissions(rec, req, auth.Claims{Subject: unlinked.ID, Role: "professional"})
	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, mau 403 (body: %s)", rec.Code, rec.Body.String())
	}
	if bytes.Contains(rec.Body.Bytes(), []byte("cbt-abcde")) {
		t.Errorf("body tidak boleh membocorkan worksheet: %s", rec.Body.String())
	}
}
