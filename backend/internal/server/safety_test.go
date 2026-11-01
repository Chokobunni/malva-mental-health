package server

import (
	"bytes"
	"context"
	"database/sql"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/config"
	"malva/backend/internal/store"

	_ "github.com/jackc/pgx/v5/stdlib"
)

func newSafetyTestServer() (*Server, string, string) {
	cfg := config.Config{
		AllowedOrigins: []string{"https://api.malva.id"},
	}
	logger := slog.New(slog.NewTextHandler(testWriter{}, nil))
	mgr := auth.NewManager("12345678901234567890123456789012")
	srv := New(cfg, mgr, nil, nil, logger)
	patientToken, _ := mgr.Issue("patient-1", "patient")
	proToken, _ := mgr.Issue("pro-1", "professional")
	return srv, patientToken, proToken
}

func doAuthed(t *testing.T, handler http.Handler, method, path, token, body string) *httptest.ResponseRecorder {
	t.Helper()
	var reader *bytes.Reader
	if body == "" {
		reader = bytes.NewReader(nil)
	} else {
		reader = bytes.NewReader([]byte(body))
	}
	req := httptest.NewRequest(method, path, reader)
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	handler.ServeHTTP(rec, req)
	return rec
}

func TestSafetyEndpointsRequireAuth(t *testing.T) {
	srv, _, _ := newSafetyTestServer()
	handler := srv.Routes()

	cases := []struct{ method, path string }{
		{"GET", "/v1/emergency-contacts"},
		{"POST", "/v1/emergency-contacts"},
		{"DELETE", "/v1/emergency-contacts/abc"},
		{"POST", "/v1/crisis-alerts"},
		{"GET", "/v1/crisis-incidents"},
		{"POST", "/v1/crisis-incidents/abc/resolve"},
		{"GET", "/v1/sos-blast-status?incident_id=x"},
		{"POST", "/v1/credentials"},
		{"GET", "/v1/credentials/me"},
		{"POST", "/v1/bookings"},
		{"POST", "/v1/payments"},
		{"POST", "/v1/payments/mark-paid"},
		{"GET", "/v1/bookings"},
		{"GET", "/v1/earnings"},
		{"POST", "/v1/earnings/e1/payout"},
		{"POST", "/v1/e-prescriptions"},
		{"GET", "/v1/e-prescriptions"},
		{"GET", "/v1/e-prescriptions/rx1"},
	}
	for _, tc := range cases {
		rec := doAuthed(t, handler, tc.method, tc.path, "", `{"x":1}`)
		if rec.Code != http.StatusUnauthorized {
			t.Errorf("%s %s: expected 401, got %d (%s)", tc.method, tc.path, rec.Code, rec.Body.String())
		}
	}
}

func TestDoctorDirectoryIsPublic(t *testing.T) {
	// Direktori profesional boleh diakses tanpa token (read-only).
	// Butuh DB (CI-safe: skip bila tidak tersedia).
	dsn := "postgres://malva:malva_dev_password@localhost:5432/malva?sslmode=disable"
	if v := os.Getenv("MALVA_TEST_DATABASE_URL"); v != "" {
		dsn = v
	} else if v := os.Getenv("MALVA_DATABASE_URL"); v != "" {
		dsn = v
	}
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Skipf("db unavailable: %v", err)
	}
	defer func() { _ = db.Close() }()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		t.Skipf("db unreachable (CI-safe): %v", err)
	}

	cfg := config.Config{AllowedOrigins: []string{"https://api.malva.id"}}
	logger := slog.New(slog.NewTextHandler(testWriter{}, nil))
	mgr := auth.NewManager("12345678901234567890123456789012")
	srv := New(cfg, mgr, store.New(db), nil, logger)
	handler := srv.Routes()

	// Difilter per spesialisasi + limit maksimum agar hasil TIDAK bergantung
	// pada jumlah baris di tabel: sebelumnya test ini pecah ketika data uji
	// menumpuk dan mendorong seed dokter keluar dari LIMIT 50.
	// Inti pengujian tetap sama: direktori bisa diakses TANPA token.
	rec := doAuthed(t, handler, "GET", "/v1/doctors/search?specialization=Sp.KJ&limit=100", "", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("GET /v1/doctors/search: expected 200 tanpa token, got %d (%s)",
			rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "dr. Hafid Algistian") {
		t.Errorf("expected seed doctor in response, got: %s", rec.Body.String())
	}

	// Profil & slot juga publik (bukan 401).
	for _, path := range []string{
		"/v1/doctors/u1",
		"/v1/doctors/u1/slots?date=2026-01-01",
	} {
		rec := doAuthed(t, handler, "GET", path, "", "")
		if rec.Code == http.StatusUnauthorized {
			t.Errorf("GET %s: direktori harus publik, got 401", path)
		}
	}

	// Filter BPJS + spesialisasi harus benar-benar memfilter.
	// Seed 008: Rina & Andi = M.Psi + BPJS; Hafid & Sinta = Sp.KJ.
	rec = doAuthed(t, handler, "GET",
		"/v1/doctors/search?specialization=M.Psi&is_bpjs_supported=true", "", "")
	if rec.Code != http.StatusOK {
		t.Fatalf("filter search: expected 200, got %d (%s)",
			rec.Code, rec.Body.String())
	}
	body := rec.Body.String()
	if !strings.Contains(body, "Rina Prasetyo") {
		t.Errorf("expected Rina (M.Psi + BPJS) in response, got: %s", body)
	}
	if !strings.Contains(body, "Andi Wijaya") {
		t.Errorf("expected Andi (M.Psi + BPJS) in response, got: %s", body)
	}
	if strings.Contains(body, "Hafid Algistian") {
		t.Errorf("Hafid (Sp.KJ) harus terfilter spesialisasi, got: %s", body)
	}
}

func TestValidateIndonesianPhone(t *testing.T) {
	// Format valid: 9-15 digit diawali 0 atau 62, boleh pakai awalan +62.
	ok := []string{"08123456789", "628123456789", "0812345678", "+628123456789", "62 812-3456-789"}
	for _, p := range ok {
		if !validateIndonesianPhone(p) {
			t.Errorf("expected valid: %s", p)
		}
	}
	bad := []string{"", "123", "08123456789012345", "07123456", "08abcd5678", "+123456789"}
	for _, p := range bad {
		if validateIndonesianPhone(p) {
			t.Errorf("expected invalid: %s", p)
		}
	}
}

func TestCrisisAlertRejectsInvalidTriggeredBy(t *testing.T) {
	srv, patientToken, _ := newSafetyTestServer()
	handler := srv.Routes()

	rec := doAuthed(t, handler, "POST", "/v1/crisis-alerts", patientToken,
		`{"triggered_by":"hack_the_system"}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid triggered_by, got %d: %s", rec.Code, rec.Body.String())
	}
	if !strings.Contains(rec.Body.String(), "triggered_by") {
		t.Fatalf("unexpected body: %s", rec.Body.String())
	}
}

func TestCrisisAlertRejectsInvalidCoordinates(t *testing.T) {
	srv, patientToken, _ := newSafetyTestServer()
	handler := srv.Routes()

	rec := doAuthed(t, handler, "POST", "/v1/crisis-alerts", patientToken,
		`{"triggered_by":"sos_button","latitude":999,"longitude":999}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for invalid coords, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestEmergencyContactRejectsTooManyDigits(t *testing.T) {
	srv, patientToken, _ := newSafetyTestServer()
	handler := srv.Routes()

	// Nomor terlalu panjang harus ditolak SEBELUM menyentuh store (nil).
	rec := doAuthed(t, handler, "POST", "/v1/emergency-contacts", patientToken,
		`{"contact_name":"Ibu","contact_phone":"08123456789012345"}`)
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for long phone, got %d: %s", rec.Code, rec.Body.String())
	}
}

func TestEmergencyContactRejectsEmptyName(t *testing.T) {
	srv, patientToken, _ := newSafetyTestServer()
	handler := srv.Routes()

	rec := doAuthed(t, handler, "POST", "/v1/emergency-contacts", patientToken,
		`{"contact_name":"  ","contact_phone":"08123456789"}`)
	// Nama kosong ditolak sebelum store (nil) — bukan 500.
	if rec.Code == http.StatusInternalServerError {
		t.Fatalf("empty name reached store layer: %s", rec.Body.String())
	}
	if rec.Code != http.StatusBadRequest {
		t.Fatalf("expected 400 for empty name, got %d: %s", rec.Code, rec.Body.String())
	}
}

// insertSafetyUser membuat user uji dengan role tertentu dan mengembalikan id.
func insertSafetyUser(t *testing.T, db *sql.DB, role, tag, suffix string) string {
	t.Helper()
	var id string
	if err := db.QueryRowContext(context.Background(),
		`INSERT INTO users (email,password_hash,role,display_name)
		 VALUES ($1,'test',$2::user_role,$3) RETURNING id`,
		"safety-"+tag+"-"+suffix+"@example.test", role, "Safety "+tag).Scan(&id); err != nil {
		t.Fatalf("buat user %s: %v", tag, err)
	}
	return id
}

// insertSafetyIncident membuat satu insiden krisis aktif milik patientID.
func insertSafetyIncident(t *testing.T, db *sql.DB, patientID string) string {
	t.Helper()
	var id string
	if err := db.QueryRowContext(context.Background(),
		`INSERT INTO crisis_incidents (patient_id,triggered_by) VALUES ($1,'manual') RETURNING id`,
		patientID).Scan(&id); err != nil {
		t.Fatalf("buat insiden: %v", err)
	}
	return id
}

// TestResolveCrisisIncidentAuthorization mengunci IDOR: pasien hanya boleh
// menyelesaikan insiden MILIKNYA sendiri; profesional hanya insiden pasien yang
// terhubung; role lain ditolak. Status insiden pasien lain TIDAK boleh berubah.
// Butuh Postgres (di-skip bila MALVA_TEST_DATABASE_URL kosong).
func TestResolveCrisisIncidentAuthorization(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	cfg := config.Config{AllowedOrigins: []string{"https://api.malva.id"}}
	logger := slog.New(slog.NewTextHandler(testWriter{}, nil))
	mgr := auth.NewManager("12345678901234567890123456789012")
	handler := New(cfg, mgr, st, nil, logger).Routes()
	ctx := context.Background()

	suffix := fmt.Sprint(time.Now().UnixNano())
	patA := insertSafetyUser(t, db, "patient", "A", suffix)
	patB := insertSafetyUser(t, db, "patient", "B", suffix)
	proLinked := insertSafetyUser(t, db, "professional", "Linked", suffix)
	proUnlinked := insertSafetyUser(t, db, "professional", "Unlinked", suffix)
	if _, err := db.ExecContext(ctx,
		`INSERT INTO patient_professional_links (patient_id,professional_id,status) VALUES ($1,$2,'active')`,
		patB, proLinked); err != nil {
		t.Fatalf("siapkan link: %v", err)
	}
	incA := insertSafetyIncident(t, db, patA) // milik pasien A
	incB := insertSafetyIncident(t, db, patB) // milik pasien B

	// Bersihkan insiden DULU (resolved_by FK NO ACTION), lalu link, lalu user.
	t.Cleanup(func() {
		_, _ = db.Exec(`DELETE FROM crisis_incidents WHERE id = ANY($1::uuid[])`, pqUUIDArray(incA, incB))
		_, _ = db.Exec(`DELETE FROM patient_professional_links WHERE patient_id = ANY($1::uuid[]) OR professional_id = ANY($1::uuid[])`,
			pqUUIDArray(patA, patB, proLinked, proUnlinked))
		cleanupTestUsers(t, db, patA, patB, proLinked, proUnlinked)
	})

	statusOf := func(id string) string {
		var s string
		if err := db.QueryRowContext(ctx, `SELECT status FROM crisis_incidents WHERE id=$1`, id).Scan(&s); err != nil {
			t.Fatalf("baca status: %v", err)
		}
		return s
	}
	resolve := func(token, incidentID string) *httptest.ResponseRecorder {
		return doAuthed(t, handler, "POST", "/v1/crisis-incidents/"+incidentID+"/resolve", token, `{}`)
	}

	tokPatA, _ := mgr.Issue(patA, "patient")
	tokProLinked, _ := mgr.Issue(proLinked, "professional")
	tokProUnlinked, _ := mgr.Issue(proUnlinked, "professional")

	// 1. Pasien A resolve insiden pasien B -> 403, status B tetap active.
	if rec := resolve(tokPatA, incB); rec.Code != http.StatusForbidden {
		t.Fatalf("pasien A resolve insiden B: mau 403, dapat %d (%s)", rec.Code, rec.Body.String())
	}
	if s := statusOf(incB); s != "active" {
		t.Fatalf("insiden B berubah jadi %q oleh pasien lain (harus tetap active)", s)
	}

	// 2. Profesional TIDAK terhubung resolve insiden B -> 403, tetap active.
	if rec := resolve(tokProUnlinked, incB); rec.Code != http.StatusForbidden {
		t.Fatalf("profesional tak terhubung: mau 403, dapat %d (%s)", rec.Code, rec.Body.String())
	}
	if s := statusOf(incB); s != "active" {
		t.Fatalf("insiden B berubah oleh profesional tak terhubung (harus tetap active)")
	}

	// 3. Profesional terhubung resolve insiden B -> 200, jadi resolved.
	if rec := resolve(tokProLinked, incB); rec.Code != http.StatusOK {
		t.Fatalf("profesional terhubung: mau 200, dapat %d (%s)", rec.Code, rec.Body.String())
	}
	if s := statusOf(incB); s != "resolved" {
		t.Fatalf("insiden B tidak jadi resolved oleh profesional terhubung: %q", s)
	}

	// 4. Pasien A resolve insidennya sendiri -> 200, jadi resolved.
	if rec := resolve(tokPatA, incA); rec.Code != http.StatusOK {
		t.Fatalf("pasien A resolve insiden sendiri: mau 200, dapat %d (%s)", rec.Code, rec.Body.String())
	}
	if s := statusOf(incA); s != "resolved" {
		t.Fatalf("insiden A tidak jadi resolved oleh pemiliknya: %q", s)
	}
}
