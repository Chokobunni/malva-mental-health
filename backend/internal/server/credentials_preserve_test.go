package server

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/store"
)

func TestUploadCredentialsPracticeLocationsAndBPJSSearch(t *testing.T) {
	db, _ := openOnboardingTestStore(t)
	userID := seedProfessionalWithCoordinates(t, db)
	srv := newOnboardingTestServer(db)
	post := func(body string, want int) {
		t.Helper()
		rec := httptest.NewRecorder()
		req := httptest.NewRequest(http.MethodPost, "/v1/credentials", strings.NewReader(body))
		srv.uploadCredentials(rec, req, auth.Claims{Subject: userID, Role: "professional"})
		if rec.Code != want {
			t.Fatalf("want status %d, got %d: %s", want, rec.Code, rec.Body)
		}
	}
	post(`{"practice_locations":[{"name":"  Klinik Contoh Mandiri  ","address":"Jl. Klinik","accepts_bpjs":false},{"name":"RS Contoh Utama","address":"Jl. Rumah Sakit","accepts_bpjs":true}]}`, http.StatusCreated)
	post(`{"hospital_name":"Faskes dari klien lama","is_bpjs_supported":false,"bio":"Bio dari klien lama"}`, http.StatusCreated)
	post(`{"practice_locations":[{"name":"Tanpa alamat","accepts_bpjs":true}]}`, http.StatusBadRequest)

	credential, err := srv.store.GetProfessionalCredential(context.Background(), userID)
	if err != nil {
		t.Fatal(err)
	}
	if credential.VerificationStatus != "VERIFIED" || credential.DocumentURL != "/uploads/dokumen-lama.pdf" ||
		credential.Bio != "Bio dari klien lama" || credential.HospitalName != "Klinik Contoh Mandiri" ||
		len(credential.PracticeLocations) != 2 || credential.PracticeLocations[0].AcceptsBPJS ||
		credential.PracticeLocations[1].Name != "RS Contoh Utama" || !credential.PracticeLocations[1].AcceptsBPJS {
		t.Fatalf("locations or unrelated credential fields incorrect: %+v", credential)
	}
	bpjs := true
	found, err := srv.store.SearchDoctors(context.Background(), store.DoctorSearchParams{
		Specialization: "M.Psi", IsBPJSSupported: &bpjs, Limit: 100,
	})
	if err != nil {
		t.Fatal(err)
	}
	for _, result := range found {
		if result.UserID == userID && result.IsBPJSSupported {
			return
		}
	}
	t.Fatal("professional with a BPJS-accepting secondary location missing from search")
}

// ============================================================
// Regresi BUG C1 — menyimpan profil profesional dari form editor
// TIDAK boleh menghapus koordinat faskes / dokumen / foto.
//
// Form editor (professional_profile_editor_screen.dart) tidak punya kolom
// koordinat maupun dokumen, sehingga request datang tanpa hospital_lat/lng
// dan document_url kosong. Sebelum perbaikan, UpsertProfessionalCredential
// menulis NULL ke koordinat → profesional hilang dari "Cari Profesional".
// ============================================================

// seedProfessionalWithCoordinates menyiapkan satu profesional terverifikasi
// yang sudah punya koordinat faskes, dokumen, dan foto intro.
func seedProfessionalWithCoordinates(t *testing.T, db *sql.DB) string {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	email := "koordinat-" + suffix + "@malva.test"
	var userID string
	if err := db.QueryRowContext(ctx, `INSERT INTO users (email, password_hash, role, display_name)
		VALUES ($1,'test-hash','professional',$2) RETURNING id::text`,
		email, "dr. Koordinat "+suffix).Scan(&userID); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO professional_profiles (user_id, professional_id)
		VALUES ($1,$2)`, userID, "STR-KOORD-"+suffix); err != nil {
		t.Fatalf("insert professional_profiles: %v", err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO professional_credentials
		(user_id, str_number, sip_number, specialization, hospital_lat, hospital_lng,
		 hospital_name, photo_intro_url, document_url, verification_status)
		VALUES ($1,$2,$3,'Sp.KJ',-6.2,106.8166,'RS Malva','/uploads/foto-lama.jpg',
			'/uploads/dokumen-lama.pdf','VERIFIED')`,
		userID, "STR-KOORD-"+suffix, "SIP-KOORD-"+suffix); err != nil {
		t.Fatalf("insert credentials: %v", err)
	}
	t.Cleanup(func() { cleanupTestUsers(t, db, userID) })
	return userID
}

// TestUploadCredentialsPreservesHiddenFields memastikan field yang tidak
// dikirim form editor tetap utuh setelah simpan.
func TestUploadCredentialsPreservesHiddenFields(t *testing.T) {
	db, _ := openOnboardingTestStore(t)
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	userID := seedProfessionalWithCoordinates(t, db)
	srv := newOnboardingTestServer(db)

	// Body persis seperti yang dikirim form editor: tanpa hospital_lat/lng,
	// tanpa document_url, photo_intro_url dikosongkan.
	body := map[string]any{
		"str_number":        "STR-KOORD-BARU",
		"sip_number":        "SIP-KOORD-BARU",
		"sipp_number":       "SIPP-KOORD-BARU",
		"specialization":    "Sp.KJ",
		"hospital_name":     "RS Malva",
		"address_details":   "Jl. Contoh 1",
		"is_bpjs_supported": true,
		"bio":               "Bio baru",
		"photo_intro_url":   "",
		"video_intro_url":   "",
		"education":         []any{},
	}
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal body: %v", err)
	}
	req := httptest.NewRequest(http.MethodPost, "/v1/credentials", bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	srv.uploadCredentials(rec, req, auth.Claims{Subject: userID, Role: "professional"})
	if rec.Code != http.StatusCreated {
		t.Fatalf("mau 201, dapat %d: %s", rec.Code, rec.Body.String())
	}

	var lat, lng sql.NullFloat64
	var photo, document string
	if err := db.QueryRowContext(ctx, `SELECT hospital_lat, hospital_lng,
		COALESCE(photo_intro_url,''), COALESCE(document_url,'')
		FROM professional_credentials WHERE user_id = $1`, userID).Scan(&lat, &lng, &photo, &document); err != nil {
		t.Fatalf("baca kredensial: %v", err)
	}
	if !lat.Valid || !lng.Valid {
		t.Fatalf("koordinat faskes terhapus oleh simpan profil parsial (lat=%v lng=%v)", lat, lng)
	}
	if lat.Float64 != -6.2 || lng.Float64 != 106.8166 {
		t.Errorf("koordinat berubah: dapat lat=%v lng=%v", lat.Float64, lng.Float64)
	}
	if document != "/uploads/dokumen-lama.pdf" {
		t.Errorf("document_url harus dipertahankan, dapat %q", document)
	}
	if photo != "/uploads/foto-lama.jpg" {
		t.Errorf("photo_intro_url lama tidak boleh diganti avatar default, dapat %q", photo)
	}
	// Data yang memang dikirim klien harus tersimpan.
	var str, bio string
	if err := db.QueryRowContext(ctx, `SELECT COALESCE(str_number,''), COALESCE(bio,'')
		FROM professional_credentials WHERE user_id = $1`, userID).Scan(&str, &bio); err != nil {
		t.Fatalf("baca kredensial: %v", err)
	}
	if str != "STR-KOORD-BARU" || bio != "Bio baru" {
		t.Errorf("perubahan dari klien tidak tersimpan: str=%q bio=%q", str, bio)
	}
}

// TestUploadCredentialsRejectsPartialCoordinates: koordinat faskes harus
// dikirim berpasangan. Request yang hanya mengirim salah satu (mis. lat saja)
// harus ditolak 400 — sebelumnya lolos validasi (validateLatLng hanya jalan
// bila keduanya terisi) dan menyimpan koordinat setengah jadi.
func TestUploadCredentialsRejectsPartialCoordinates(t *testing.T) {
	db, _ := openOnboardingTestStore(t)
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	userID := seedProfessionalWithCoordinates(t, db)
	srv := newOnboardingTestServer(db)

	body := map[string]any{
		"str_number":        "STR-KOORD-BARU",
		"sip_number":        "SIP-KOORD-BARU",
		"specialization":    "Sp.KJ",
		"hospital_lat":      -7.25,
		"is_bpjs_supported": false,
	}
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal body: %v", err)
	}
	req := httptest.NewRequest(http.MethodPost, "/v1/credentials", bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	srv.uploadCredentials(rec, req, auth.Claims{Subject: userID, Role: "professional"})
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("mau 400 untuk koordinat tidak berpasangan, dapat %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "berpasangan") {
		t.Fatalf("pesan 400 harus menjelaskan pasangan koordinat: %s", rec.Body.String())
	}

	// Data lama tidak boleh berubah sama sekali.
	var lat sql.NullFloat64
	if err := db.QueryRowContext(ctx, `SELECT hospital_lat FROM professional_credentials WHERE user_id = $1`, userID).Scan(&lat); err != nil {
		t.Fatalf("baca koordinat: %v", err)
	}
	if !lat.Valid || lat.Float64 != -6.2 {
		t.Fatalf("koordinat lama harus utuh setelah request ditolak, dapat %v", lat)
	}
}
