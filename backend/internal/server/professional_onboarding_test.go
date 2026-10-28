package server

import (
	"bytes"
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"strings"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"

	"malva/backend/internal/auth"
	"malva/backend/internal/config"
	"malva/backend/internal/store"
)

// ============================================================
// Regresi BUG E2 — sinkronisasi akun lama saat profesional yang
// SUDAH terdaftar (akun email) login Google lalu melengkapi profil.
//
// Dua hal yang dijaga:
//  1. display_name placeholder (kosong / berisi email) DISINKRONKAN dari nama
//     Google, sehingga pengguna tidak melihat alamat email sebagai nama.
//  2. display_name yang sudah diisi rapi TIDAK PERNAH ditimpa.
// ============================================================

// TestShouldSyncDisplayNameFromGoogle menguji aturan keputusan sinkronisasi
// nama tanpa butuh database (selalu jalan di CI).
func TestShouldSyncDisplayNameFromGoogle(t *testing.T) {
	cases := []struct {
		name        string
		current     string
		email       string
		googleName  string
		wantSync    bool
		description string
	}{
		{
			name:        "nama kosong disinkronkan",
			current:     "",
			email:       "lama@malva.web.id",
			googleName:  "dr. Ayu Pratama, Sp.KJ",
			wantSync:    true,
			description: "akun lama tanpa nama harus memakai nama Google",
		},
		{
			name:        "nama berupa email disinkronkan",
			current:     "lama@malva.web.id",
			email:       "lama@malva.web.id",
			googleName:  "dr. Ayu Pratama, Sp.KJ",
			wantSync:    true,
			description: "placeholder email harus diganti nama sebenarnya",
		},
		{
			name:        "nama mengandung @ disinkronkan",
			current:     "pro-123@placeholder",
			email:       "lama@malva.web.id",
			googleName:  "dr. Ayu Pratama, Sp.KJ",
			wantSync:    true,
			description: "nilai yang mengandung @ dianggap placeholder",
		},
		{
			name:        "nama rapi tidak ditimpa",
			current:     "dr. Ayu Pratama, Sp.KJ",
			email:       "ayu@malva.web.id",
			googleName:  "Ayu P",
			wantSync:    false,
			description: "nama yang sudah diisi rapi harus dipertahankan",
		},
		{
			name:        "nama google kosong tidak menimpa",
			current:     "lama@malva.web.id",
			email:       "lama@malva.web.id",
			googleName:  "   ",
			wantSync:    false,
			description: "tanpa nama Google, tidak ada yang boleh diubah",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := shouldSyncDisplayNameFromGoogle(tc.current, tc.email, tc.googleName)
			if got != tc.wantSync {
				t.Fatalf("%s: mau sync=%v, dapat %v", tc.description, tc.wantSync, got)
			}
		})
	}
}

// openOnboardingTestStore membuka koneksi DB untuk test merge akun.
// Skip bila DB tidak tersedia atau migrasi belum diterapkan (CI-safe),
// mengikuti pola internal/store/care_refund_test.go.
//
// PENTING: koneksi ditutup lewat `t.Cleanup`, BUKAN `defer` di badan test.
// `t.Cleanup` bersifat LIFO, sehingga cleanup data (yang didaftarkan SETELAH
// fungsi ini) berjalan LEBIH DULU, baru koneksi ditutup. Dengan `defer`, DB
// sudah tertutup saat cleanup data berjalan → "sql: database is closed" dan
// data uji menumpuk di DB bersama (regresi yang pernah terjadi).
func openOnboardingTestStore(t *testing.T) (*sql.DB, *store.Store) {
	t.Helper()
	dsn := os.Getenv("MALVA_TEST_DATABASE_URL")
	if dsn == "" {
		dsn = "postgres://malva:malva_dev_password@localhost:5432/malva?sslmode=disable"
	}
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Skipf("db unavailable: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		_ = db.Close()
		t.Skipf("db unreachable (CI-safe): %v", err)
	}
	var n int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM information_schema.tables
		WHERE table_schema = 'public'
		  AND table_name IN ('users','professional_profiles','professional_credentials')`).Scan(&n); err != nil || n < 3 {
		_ = db.Close()
		t.Skip("skema dasar belum diterapkan (CI-safe)")
	}
	// Didaftarkan lebih dulu = dijalankan paling akhir (LIFO).
	t.Cleanup(func() { _ = db.Close() })
	return db, store.New(db)
}

// mergeFixture menyiapkan dua akun profesional:
//   - akun LAMA (email) dengan STR terdaftar
//   - akun PLACEHOLDER hasil login Google (professional_id "g-...")
type mergeFixture struct {
	oldUserID    string
	googleUserID string
	strNumber    string
	sipNumber    string
}

// testMergePassword adalah password akun LAMA pada fixture. Sejak perbaikan
// anti account-takeover, merge hanya boleh terjadi dengan bukti kepemilikan:
// email Google == email akun lama, atau password akun lama benar.
const testMergePassword = "RahasiaLama123!"

func seedMergeFixture(t *testing.T, db *sql.DB, oldDisplayName, googleName string) mergeFixture {
	t.Helper()
	return seedMergeFixtureEmails(t, db, oldDisplayName, googleName, false)
}

// seedMergeFixtureEmails menyiapkan fixture dengan pilihan email akun Google.
//
// sameEmailCase=true membuat email akun Google SAMA dengan email akun lama
// tetapi beda kapitalisasi. Ini kombinasi yang sah di database (unique index
// pada users.email bersifat case-sensitive) dan meniru kasus nyata: akun lama
// didaftarkan sebagai "Ayu@Malva.web.id" sementara Google melaporkan
// "ayu@malva.web.id". Dipakai untuk menguji bahwa pemilik sah (email sama)
// tidak terkena lockout.
func seedMergeFixtureEmails(t *testing.T, db *sql.DB, oldDisplayName, googleName string, sameEmailCase bool) mergeFixture {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	// Suffix unik agar test bisa dijalankan berulang tanpa bentrok.
	suffix := fmt.Sprintf("%d", time.Now().UnixNano())
	f := mergeFixture{
		strNumber: "STR-TEST-" + suffix,
		sipNumber: "SIP-TEST-" + suffix,
	}
	// Password akun lama harus hash bcrypt yang sah: handler memverifikasinya
	// lewat auth.CheckPassword sebagai bukti kepemilikan.
	oldHash, herr := auth.HashPassword(testMergePassword)
	if herr != nil {
		t.Fatalf("hash password fixture: %v", herr)
	}

	insertUser := func(email, displayName, passwordHash, ssoProvider, ssoID string) string {
		var id string
		if ssoProvider == "" {
			err := db.QueryRowContext(ctx, `INSERT INTO users (email, password_hash, role, display_name)
				VALUES ($1,$2,'professional',$3) RETURNING id::text`,
				email, passwordHash, displayName).Scan(&id)
			if err != nil {
				t.Fatalf("insert user %s: %v", email, err)
			}
			return id
		}
		err := db.QueryRowContext(ctx, `INSERT INTO users (email, password_hash, role, display_name, sso_provider, sso_id)
			VALUES ($1,$2,'professional',$3,$4,$5) RETURNING id::text`,
			email, passwordHash, displayName, ssoProvider, ssoID).Scan(&id)
		if err != nil {
			t.Fatalf("insert user %s: %v", email, err)
		}
		return id
	}

	oldEmail := "lama-" + suffix + "@malva.test"
	googleEmail := "placeholder-" + suffix + "@malva.test"
	if sameEmailCase {
		googleEmail = strings.ToUpper("lama-"+suffix) + "@malva.test"
	}

	// Akun Google placeholder memakai hash acak yang tidak bisa dipakai login
	// password (meniru googleLogin: hash acak untuk akun SSO baru).
	f.oldUserID = insertUser(oldEmail, oldDisplayName, oldHash, "", "")
	f.googleUserID = insertUser(googleEmail, googleName, "test-hash", "google", "google-sub-"+suffix)

	// Akun lama: professional_id = nomor STR + kredensial berisi STR tersebut.
	if _, err := db.ExecContext(ctx, `INSERT INTO professional_profiles (user_id, professional_id)
		VALUES ($1,$2)`, f.oldUserID, f.strNumber); err != nil {
		t.Fatalf("insert professional_profiles lama: %v", err)
	}
	if _, err := db.ExecContext(ctx, `INSERT INTO professional_credentials
		(user_id, str_number, sip_number, specialization, verification_status)
		VALUES ($1,$2,$3,'Sp.KJ','VERIFIED')`, f.oldUserID, f.strNumber, f.sipNumber); err != nil {
		t.Fatalf("insert credentials lama: %v", err)
	}
	// Placeholder Google: professional_id sementara "g-..." (syarat merge).
	if _, err := db.ExecContext(ctx, `INSERT INTO professional_profiles (user_id, professional_id)
		VALUES ($1,$2)`, f.googleUserID, "g-"+suffix); err != nil {
		t.Fatalf("insert professional_profiles placeholder: %v", err)
	}

	// Bersihkan setelah test (cascade menghapus profil & kredensial).
	t.Cleanup(func() { cleanupTestUsers(t, db, f.oldUserID, f.googleUserID) })
	return f
}

// pqUUIDArray menyusun literal array Postgres untuk daftar UUID.
func pqUUIDArray(ids ...string) string {
	return "{" + strings.Join(ids, ",") + "}"
}

// userChildRef adalah satu kolom FK yang menunjuk ke users(id).
type userChildRef struct {
	table  string
	column string
}

// discoverUserChildRefs menemukan SEMUA kolom FK yang menunjuk ke users(id)
// lewat information_schema — tidak menebak nama tabel/kolom, sehingga tabel
// baru (atau tabel yang lupa memakai ON DELETE CASCADE) otomatis tertangani.
func discoverUserChildRefs(t *testing.T, db *sql.DB) []userChildRef {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	const q = `
		SELECT tc.table_name, kcu.column_name
		FROM information_schema.table_constraints tc
		JOIN information_schema.key_column_usage kcu
		  ON kcu.constraint_name = tc.constraint_name
		 AND kcu.table_schema = tc.table_schema
		JOIN information_schema.constraint_column_usage ccu
		  ON ccu.constraint_name = tc.constraint_name
		 AND ccu.table_schema = tc.table_schema
		WHERE tc.constraint_type = 'FOREIGN KEY'
		  AND ccu.table_name = 'users'
		  AND tc.table_schema = 'public'
		ORDER BY tc.table_name, kcu.column_name`
	rows, err := db.QueryContext(ctx, q)
	if err != nil {
		t.Fatalf("gagal membaca daftar FK ke users: %v", err)
	}
	defer func() { _ = rows.Close() }()
	var refs []userChildRef
	for rows.Next() {
		var r userChildRef
		if err := rows.Scan(&r.table, &r.column); err != nil {
			t.Fatalf("scan FK users: %v", err)
		}
		refs = append(refs, r)
	}
	if err := rows.Err(); err != nil {
		t.Fatalf("iterasi FK users: %v", err)
	}
	return refs
}

// isForeignKeyViolation mendeteksi pelanggaran FK Postgres (SQLSTATE 23503).
func isForeignKeyViolation(err error) bool {
	if err == nil {
		return false
	}
	msg := err.Error()
	return strings.Contains(msg, "23503") || strings.Contains(msg, "foreign key constraint")
}

// cleanupTestUsers menghapus user uji beserta SELURUH baris anak yang
// menahannya, lalu MEMVERIFIKASI tidak ada sisa.
//
// Kenapa tidak cukup `DELETE FROM users`: beberapa FK ke users(id) tidak
// memakai ON DELETE CASCADE (mis. audit_logs.actor_id/patient_id), sehingga
// DELETE gagal. Kegagalan itu dulu ditelan diam-diam → data uji menumpuk di
// DB bersama dan memecahkan test direktori. Sekarang: setiap kegagalan
// dilaporkan, dan sisa baris diperiksa memakai koneksi yang PASTI masih
// terbuka (opener mendaftarkan penutupan lewat t.Cleanup, bukan defer).
func cleanupTestUsers(t *testing.T, db *sql.DB, ids ...string) {
	t.Helper()
	if len(ids) == 0 {
		return
	}
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	arr := pqUUIDArray(ids...)

	// 1) audit_logs & auth_sessions lebih dulu (paling sering menahan).
	if _, err := db.ExecContext(ctx,
		`DELETE FROM audit_logs WHERE actor_id = ANY($1::uuid[]) OR patient_id = ANY($1::uuid[])`, arr); err != nil {
		t.Logf("cleanup audit_logs gagal: %v", err)
	}
	if _, err := db.ExecContext(ctx, `DELETE FROM auth_sessions WHERE user_id = ANY($1::uuid[])`, arr); err != nil {
		t.Logf("cleanup auth_sessions gagal: %v", err)
	}

	// 2) Semua tabel lain yang punya FK ke users. Diulang beberapa pass agar
	//    dependensi antar-anak (anak punya anak) tidak perlu ditebak.
	pending := discoverUserChildRefs(t, db)
	for pass := 0; pass < 5 && len(pending) > 0; pass++ {
		var next []userChildRef
		progress := false
		for _, ref := range pending {
			stmt := fmt.Sprintf(`DELETE FROM "%s" WHERE "%s" = ANY($1::uuid[])`, ref.table, ref.column)
			if _, err := db.ExecContext(ctx, stmt, arr); err != nil {
				if isForeignKeyViolation(err) {
					// Masih ditahan tabel lain: coba lagi pada pass berikutnya.
					next = append(next, ref)
					continue
				}
				t.Errorf("cleanup %s.%s gagal: %v", ref.table, ref.column, err)
				continue
			}
			progress = true
		}
		pending = next
		if !progress {
			break
		}
	}
	for _, ref := range pending {
		t.Errorf("cleanup tidak selesai untuk %s.%s (masih ditahan FK lain)", ref.table, ref.column)
	}

	// 3) Baris user-nya sendiri.
	if _, err := db.ExecContext(ctx, `DELETE FROM users WHERE id = ANY($1::uuid[])`, arr); err != nil {
		t.Errorf("cleanup users gagal: %v", err)
	}

	// 4) Verifikasi WAJIB memakai koneksi yang masih terbuka.
	var remaining int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM users WHERE id = ANY($1::uuid[])`, arr).Scan(&remaining); err != nil {
		t.Errorf("verifikasi cleanup tidak bisa dijalankan: %v", err)
		return
	}
	if remaining != 0 {
		t.Errorf("cleanup: %d user uji masih tersisa di DB", remaining)
	}
}

// completeProfileForMerge memanggil handler merge secara langsung (tanpa HTTP
// routing) dan mengembalikan response recorder + body terurai.
// existingPassword adalah bukti kepemilikan akun lama; kosong berarti pemanggil
// mengandalkan kesamaan email.
func completeProfileForMerge(t *testing.T, srv *Server, googleUserID, strNumber, sipNumber, displayName, existingPassword string) (*httptest.ResponseRecorder, map[string]any) {
	t.Helper()
	body := map[string]string{
		"str_number":     strNumber,
		"sip_number":     sipNumber,
		"specialization": "Sp.KJ",
		"display_name":   displayName,
	}
	if existingPassword != "" {
		body["existing_password"] = existingPassword
	}
	raw, err := json.Marshal(body)
	if err != nil {
		t.Fatalf("marshal body: %v", err)
	}
	req := httptest.NewRequest(http.MethodPost, "/v1/auth/complete-professional", bytes.NewReader(raw))
	req.Header.Set("Content-Type", "application/json")
	rec := httptest.NewRecorder()
	srv.completeProfessionalProfile(rec, req, auth.Claims{Subject: googleUserID, Role: "professional"})

	decoded := map[string]any{}
	_ = json.Unmarshal(rec.Body.Bytes(), &decoded)
	return rec, decoded
}

func newOnboardingTestServer(db *sql.DB) *Server {
	cfg := config.Config{AllowedOrigins: []string{"https://api.malva.id"}}
	logger := slog.New(slog.NewTextHandler(testWriter{}, nil))
	mgr := auth.NewManager("12345678901234567890123456789012")
	return New(cfg, mgr, store.New(db), nil, logger)
}

// TestMergeSyncsPlaceholderDisplayName: akun lama yang namanya masih berupa
// email harus memakai nama dari akun Google setelah merge, dan respons harus
// membawa token baru + credential.
func TestMergeSyncsPlaceholderDisplayName(t *testing.T) {
	db, _ := openOnboardingTestStore(t)
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	const googleName = "dr. Ayu Pratama, Sp.KJ"
	f := seedMergeFixture(t, db, "lama@malva.test", googleName)
	srv := newOnboardingTestServer(db)

	rec, decoded := completeProfileForMerge(t, srv, f.googleUserID, f.strNumber, f.sipNumber, googleName, testMergePassword)
	if rec.Code != http.StatusOK {
		t.Fatalf("mau 200 hasil merge, dapat %d: %s", rec.Code, rec.Body.String())
	}

	var displayName string
	if err := db.QueryRowContext(ctx, `SELECT display_name FROM users WHERE id = $1`, f.oldUserID).Scan(&displayName); err != nil {
		t.Fatalf("baca display_name: %v", err)
	}
	if displayName != googleName {
		t.Fatalf("display_name akun lama harus tersinkron menjadi %q, dapat %q", googleName, displayName)
	}
	// Token baru wajib ada agar klien berpindah akun.
	if _, ok := decoded["access_token"]; !ok {
		t.Fatalf("respons merge harus memuat access_token: %s", rec.Body.String())
	}
	if _, ok := decoded["refresh_token"]; !ok {
		t.Fatalf("respons merge harus memuat refresh_token: %s", rec.Body.String())
	}
	// Detail tersinkronisasi (credential) ikut dikirim.
	if _, ok := decoded["credential"]; !ok {
		t.Fatalf("respons merge harus memuat credential: %s", rec.Body.String())
	}
}

// TestMergeKeepsGoodDisplayName: nama akun lama yang sudah rapi TIDAK boleh
// ditimpa oleh nama Google yang berbeda.
func TestMergeKeepsGoodDisplayName(t *testing.T) {
	db, _ := openOnboardingTestStore(t)
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	const oldName = "dr. Ayu Pratama, Sp.KJ"
	f := seedMergeFixture(t, db, oldName, "Ayu P")
	srv := newOnboardingTestServer(db)

	rec, _ := completeProfileForMerge(t, srv, f.googleUserID, f.strNumber, f.sipNumber, "Ayu P", testMergePassword)
	if rec.Code != http.StatusOK {
		t.Fatalf("mau 200 hasil merge, dapat %d: %s", rec.Code, rec.Body.String())
	}

	var displayName string
	if err := db.QueryRowContext(ctx, `SELECT display_name FROM users WHERE id = $1`, f.oldUserID).Scan(&displayName); err != nil {
		t.Fatalf("baca display_name: %v", err)
	}
	if displayName != oldName {
		t.Fatalf("display_name yang sudah rapi tidak boleh berubah: mau %q, dapat %q", oldName, displayName)
	}
}

// ============================================================
// Regresi TEMUAN KEAMANAN (HIGH) — account takeover lewat merge STR.
//
// Sebelum perbaikan: penyerang login Google dengan akunnya sendiri
// (role=professional) -> dapat placeholder "g-<sub>" -> POST
// /v1/auth/complete-professional dengan STR MILIK KORBAN ->
// CanAbsorbGoogleLink hanya memeriksa BENTUK akun (bukan kepemilikan) ->
// MoveGoogleLink mengikat Google penyerang ke akun korban -> respons berisi
// sesi + kredensial korban.
//
// Penjaga baru: merge hanya boleh bila email Google == email akun lama ATAU
// password akun lama benar.
// ============================================================

// TestAllowProfessionalMerge menguji keputusan bukti kepemilikan (murni).
func TestAllowProfessionalMerge(t *testing.T) {
	cases := []struct {
		name         string
		callerEmail  string
		existingMail string
		passwordOK   bool
		want         bool
		description  string
	}{
		{
			name:         "email sama",
			callerEmail:  "ayu@malva.web.id",
			existingMail: "ayu@malva.web.id",
			passwordOK:   false,
			want:         true,
			description:  "email Google sama dengan email akun lama = bukti kepemilikan",
		},
		{
			name:         "email beda tanpa password",
			callerEmail:  "penyerang@gmail.com",
			existingMail: "ayu@malva.web.id",
			passwordOK:   false,
			want:         false,
			description:  "inilah celah account takeover yang ditutup",
		},
		{
			name:         "email beda dengan password benar",
			callerEmail:  "penyerang@gmail.com",
			existingMail: "ayu@malva.web.id",
			passwordOK:   true,
			want:         true,
			description:  "password akun lama adalah bukti kepemilikan yang sah",
		},
		{
			name:         "email pemanggil kosong",
			callerEmail:  "",
			existingMail: "ayu@malva.web.id",
			passwordOK:   false,
			want:         false,
			description:  "tanpa email tepercaya, merge harus ditolak",
		},
		{
			name:         "beda kapitalisasi dan spasi",
			callerEmail:  "  Ayu@Malva.Web.ID  ",
			existingMail: "ayu@malva.web.id",
			passwordOK:   false,
			want:         true,
			description:  "perbandingan email harus case-insensitive dan trim",
		},
		{
			name:         "email lama kosong tanpa password",
			callerEmail:  "ayu@malva.web.id",
			existingMail: "",
			passwordOK:   false,
			want:         false,
			description:  "email lama kosong tidak boleh dianggap cocok",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := allowProfessionalMerge(tc.callerEmail, tc.existingMail, tc.passwordOK)
			if got != tc.want {
				t.Fatalf("%s: mau %v, dapat %v", tc.description, tc.want, got)
			}
		})
	}
}

// TestMergeVerificationRequiredBody: klien mengenali balasan 409 lewat field
// `code`, jadi nilainya tidak boleh berubah sembarangan.
func TestMergeVerificationRequiredBody(t *testing.T) {
	body := mergeVerificationRequiredBody()
	if body["code"] != mergeVerificationRequiredCode {
		t.Fatalf("code harus %q, dapat %q", mergeVerificationRequiredCode, body["code"])
	}
	if mergeVerificationRequiredCode != "str_terdaftar_perlu_verifikasi" {
		t.Fatalf("kode yang dipakai klien berubah: %q", mergeVerificationRequiredCode)
	}
	msg := strings.TrimSpace(body["error"])
	if msg == "" {
		t.Fatal("pesan error tidak boleh kosong")
	}
	// Pesan harus memberi jalan keluar kepada pengguna sah.
	for _, want := range []string{"password akun lama", "Hubungkan Google"} {
		if !strings.Contains(msg, want) {
			t.Errorf("pesan harus menyebut %q, dapat %q", want, msg)
		}
	}
}

// TestMergeWithoutOwnershipProofRejected: permintaan merge TANPA bukti
// kepemilikan harus ditolak 409 dan TIDAK mengubah apa pun (tautan Google tidak
// berpindah, akun lama tetap tanpa SSO, nama tidak tersinkron).
func TestMergeWithoutOwnershipProofRejected(t *testing.T) {
	db, _ := openOnboardingTestStore(t)
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()

	const oldName = "dr. Ayu Pratama, Sp.KJ"
	f := seedMergeFixture(t, db, oldName, "Penyerang")
	srv := newOnboardingTestServer(db)

	// Tanpa existing_password, dan email akun Google (placeholder-...) berbeda
	// dari email akun lama (lama-...) -> harus ditolak.
	rec, decoded := completeProfileForMerge(t, srv, f.googleUserID, f.strNumber, f.sipNumber, "Penyerang", "")
	if rec.Code != http.StatusConflict {
		t.Fatalf("mau 409 tanpa bukti kepemilikan, dapat %d: %s", rec.Code, rec.Body.String())
	}
	if decoded["code"] != mergeVerificationRequiredCode {
		t.Fatalf("body 409 harus memuat code %q, dapat %v", mergeVerificationRequiredCode, decoded["code"])
	}
	if _, hasToken := decoded["access_token"]; hasToken {
		t.Fatal("respons 409 tidak boleh membocorkan access_token")
	}
	if _, hasCred := decoded["credential"]; hasCred {
		t.Fatal("respons 409 tidak boleh membocorkan credential korban")
	}

	// Tautan Google TIDAK boleh berpindah ke akun korban.
	var oldSSO sql.NullString
	if err := db.QueryRowContext(ctx, `SELECT sso_provider FROM users WHERE id = $1`, f.oldUserID).Scan(&oldSSO); err != nil {
		t.Fatalf("baca sso_provider akun lama: %v", err)
	}
	if oldSSO.Valid && strings.TrimSpace(oldSSO.String) != "" {
		t.Fatalf("akun lama tidak boleh mendapat tautan SSO, dapat %q", oldSSO.String)
	}
	// Nama akun lama tidak boleh berubah.
	var displayName string
	if err := db.QueryRowContext(ctx, `SELECT display_name FROM users WHERE id = $1`, f.oldUserID).Scan(&displayName); err != nil {
		t.Fatalf("baca display_name: %v", err)
	}
	if displayName != oldName {
		t.Fatalf("display_name akun lama tidak boleh berubah, dapat %q", displayName)
	}
	// Akun placeholder penyerang tetap aktif (tidak dinonaktifkan MoveGoogleLink).
	var disabled sql.NullTime
	if err := db.QueryRowContext(ctx, `SELECT disabled_at FROM users WHERE id = $1`, f.googleUserID).Scan(&disabled); err != nil {
		t.Fatalf("baca disabled_at: %v", err)
	}
	if disabled.Valid {
		t.Fatal("akun penyerang tidak boleh dinonaktifkan karena merge tidak terjadi")
	}
}

// TestMergeWithWrongPasswordRejected: password salah tetap ditolak.
func TestMergeWithWrongPasswordRejected(t *testing.T) {
	db, _ := openOnboardingTestStore(t)

	f := seedMergeFixture(t, db, "lama@malva.test", "Penyerang")
	srv := newOnboardingTestServer(db)

	rec, decoded := completeProfileForMerge(t, srv, f.googleUserID, f.strNumber, f.sipNumber, "Penyerang", "PasswordSalah999!")
	if rec.Code != http.StatusConflict {
		t.Fatalf("mau 409 untuk password salah, dapat %d: %s", rec.Code, rec.Body.String())
	}
	if decoded["code"] != mergeVerificationRequiredCode {
		t.Fatalf("body 409 harus memuat code %q, dapat %v", mergeVerificationRequiredCode, decoded["code"])
	}
}

// TestCompleteProfessionalStillRequiresAuth: route kini dibungkus rateLimit di
// luar requireAuth — pastikan token tetap WAJIB (bukan malah jadi publik).
func TestCompleteProfessionalStillRequiresAuth(t *testing.T) {
	srv, _, _ := newSafetyTestServer()
	handler := srv.Routes()
	rec := doAuthed(t, handler, "POST", "/v1/auth/complete-professional", "",
		`{"str_number":"STR-X","sip_number":"SIP-X","specialization":"Sp.KJ"}`)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("mau 401 tanpa token, dapat %d: %s", rec.Code, rec.Body.String())
	}
}

// ============================================================
// Paritas LOCKOUT pada jalur merge.
//
// Endpoint complete-professional kini memverifikasi password akun lama, jadi
// kegagalan berulang harus menaikkan lockout per-akun seperti jalur login —
// bukan hanya dibatasi rateLimit per-IP.
//
// PENTING: MaxLoginAttempts == 0 berarti lockout NONAKTIF (config kosong pada
// test lama). Jangan sampai satu kegagalan langsung mengunci.
// ============================================================

// newOnboardingTestServerWithLockout membangun server dengan lockout AKTIF.
// Sengaja terpisah dari newOnboardingTestServer/newSafetyTestServer agar test
// lama tetap berjalan dengan lockout nonaktif.
func newOnboardingTestServerWithLockout(db *sql.DB, maxAttempts int) *Server {
	return newOnboardingTestServerWithCfg(db, config.Config{
		AllowedOrigins:   []string{"https://api.malva.id"},
		MaxLoginAttempts: maxAttempts,
		LockoutDuration:  15,
	})
}

// newOnboardingTestServerWithCfg membangun server dengan konfigurasi eksplisit.
func newOnboardingTestServerWithCfg(db *sql.DB, cfg config.Config) *Server {
	logger := slog.New(slog.NewTextHandler(testWriter{}, nil))
	mgr := auth.NewManager("12345678901234567890123456789012")
	return New(cfg, mgr, store.New(db), nil, logger)
}

// TestMergeLockoutApplies: aturan kapan lockout diperiksa (murni, tanpa DB).
func TestMergeLockoutApplies(t *testing.T) {
	cases := []struct {
		name         string
		sameEmail    bool
		lockoutAktif bool
		want         bool
		description  string
	}{
		{
			name:         "email beda + lockout aktif",
			sameEmail:    false,
			lockoutAktif: true,
			want:         true,
			description:  "penyerang yang salah password berulang harus terkunci",
		},
		{
			name:         "email sama + lockout aktif",
			sameEmail:    true,
			lockoutAktif: true,
			want:         false,
			description:  "pemilik sah tidak boleh terkunci oleh percobaan penyerang",
		},
		{
			name:         "email beda + lockout nonaktif",
			sameEmail:    false,
			lockoutAktif: false,
			want:         false,
			description:  "MaxLoginAttempts == 0 berarti lockout dimatikan",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := mergeLockoutApplies(tc.sameEmail, tc.lockoutAktif)
			if got != tc.want {
				t.Fatalf("%s: mau %v, dapat %v", tc.description, tc.want, got)
			}
		})
	}
}

// TestMergeTooManyAttemptsBody: klien mengenali balasan 429 lewat field `code`.
func TestMergeTooManyAttemptsBody(t *testing.T) {
	body := mergeTooManyAttemptsBody()
	if body["code"] != mergeTooManyAttemptsCode {
		t.Fatalf("code harus %q, dapat %q", mergeTooManyAttemptsCode, body["code"])
	}
	if mergeTooManyAttemptsCode != "terlalu_banyak_percobaan" {
		t.Fatalf("kode yang dipakai klien berubah: %q", mergeTooManyAttemptsCode)
	}
	if strings.TrimSpace(body["error"]) == "" {
		t.Fatal("pesan error tidak boleh kosong")
	}
}

// TestMergeLockoutAfterRepeatedFailures: setelah MaxLoginAttempts kegagalan,
// permintaan berikutnya untuk STR yang sama harus 429 (bukan 409), tanpa
// membocorkan sesi/kredensial, dan akun korban tetap utuh.
func TestMergeLockoutAfterRepeatedFailures(t *testing.T) {
	db, _ := openOnboardingTestStore(t)
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()

	const maxAttempts = 3
	const oldName = "dr. Ayu Pratama, Sp.KJ"
	f := seedMergeFixture(t, db, oldName, "Penyerang")
	srv := newOnboardingTestServerWithLockout(db, maxAttempts)

	// Percobaan 1..maxAttempts: email beda + password salah -> 409.
	for i := 1; i <= maxAttempts; i++ {
		rec, decoded := completeProfileForMerge(t, srv, f.googleUserID, f.strNumber, f.sipNumber, "Penyerang", "PasswordSalah999!")
		if rec.Code != http.StatusConflict {
			t.Fatalf("percobaan ke-%d: mau 409, dapat %d: %s", i, rec.Code, rec.Body.String())
		}
		if decoded["code"] != mergeVerificationRequiredCode {
			t.Fatalf("percobaan ke-%d: code harus %q, dapat %v", i, mergeVerificationRequiredCode, decoded["code"])
		}
	}

	// Percobaan berikutnya harus 429 karena lockout per-akun aktif.
	rec, decoded := completeProfileForMerge(t, srv, f.googleUserID, f.strNumber, f.sipNumber, "Penyerang", "PasswordSalah999!")
	if rec.Code != http.StatusTooManyRequests {
		t.Fatalf("setelah %d kegagalan, mau 429, dapat %d: %s", maxAttempts, rec.Code, rec.Body.String())
	}
	if decoded["code"] != mergeTooManyAttemptsCode {
		t.Fatalf("body 429 harus memuat code %q, dapat %v", mergeTooManyAttemptsCode, decoded["code"])
	}
	if _, hasToken := decoded["access_token"]; hasToken {
		t.Fatal("respons 429 tidak boleh membocorkan access_token")
	}
	if _, hasCred := decoded["credential"]; hasCred {
		t.Fatal("respons 429 tidak boleh membocorkan credential korban")
	}

	// Akun korban tetap utuh: tidak ada tautan SSO, nama tidak berubah.
	var oldSSO sql.NullString
	if err := db.QueryRowContext(ctx, `SELECT sso_provider FROM users WHERE id = $1`, f.oldUserID).Scan(&oldSSO); err != nil {
		t.Fatalf("baca sso_provider: %v", err)
	}
	if oldSSO.Valid && strings.TrimSpace(oldSSO.String) != "" {
		t.Fatalf("akun korban tidak boleh mendapat tautan SSO, dapat %q", oldSSO.String)
	}
	var displayName string
	if err := db.QueryRowContext(ctx, `SELECT display_name FROM users WHERE id = $1`, f.oldUserID).Scan(&displayName); err != nil {
		t.Fatalf("baca display_name: %v", err)
	}
	if displayName != oldName {
		t.Fatalf("display_name akun korban tidak boleh berubah, dapat %q", displayName)
	}
}

// TestMergeLockoutDoesNotBlockSameEmail: pemilik sah (email Google == email
// akun lama) TIDAK boleh ikut terkunci gara-gara percobaan penyerang pada STR
// yang sama. Ia tetap bisa merge (200) dan menerima token.
func TestMergeLockoutDoesNotBlockSameEmail(t *testing.T) {
	db, _ := openOnboardingTestStore(t)
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()

	const maxAttempts = 3
	const googleName = "dr. Ayu Pratama, Sp.KJ"
	// Email akun Google SAMA dengan akun lama (beda kapitalisasi).
	f := seedMergeFixtureEmails(t, db, "lama@malva.test", googleName, true)
	srv := newOnboardingTestServerWithLockout(db, maxAttempts)

	// Simulasi: penyerang sudah menghabiskan jatah percobaan untuk STR ini.
	key := mergeLockoutKey(httptest.NewRequest(http.MethodPost, "/v1/auth/complete-professional", nil), f.strNumber)
	for i := 0; i < maxAttempts; i++ {
		srv.lockout.RecordFailure(key)
	}
	if !srv.lockout.IsLocked(key) {
		t.Fatalf("prasyarat test gagal: kunci %q seharusnya sudah terkunci", key)
	}

	// Pemilik sah (email sama) tidak perlu password dan tidak boleh terblokir.
	rec, decoded := completeProfileForMerge(t, srv, f.googleUserID, f.strNumber, f.sipNumber, googleName, "")
	if rec.Code != http.StatusOK {
		t.Fatalf("pemilik sah dengan email sama harus tetap bisa merge (200), dapat %d: %s", rec.Code, rec.Body.String())
	}
	if _, hasToken := decoded["access_token"]; !hasToken {
		t.Fatalf("respons merge harus memuat access_token: %s", rec.Body.String())
	}
	// Merge benar-benar terjadi: akun lama kini bertautan Google.
	var sso sql.NullString
	if err := db.QueryRowContext(ctx, `SELECT sso_provider FROM users WHERE id = $1`, f.oldUserID).Scan(&sso); err != nil {
		t.Fatalf("baca sso_provider: %v", err)
	}
	if !sso.Valid || strings.ToLower(strings.TrimSpace(sso.String)) != "google" {
		t.Fatalf("akun lama harus bertautan Google setelah merge, dapat %v", sso)
	}
	// Lockout dibersihkan setelah bukti kepemilikan sah.
	if srv.lockout.IsLocked(key) {
		t.Fatal("lockout harus di-reset setelah merge berhasil")
	}
}

// TestMergeLockoutDisabledWhenConfigZero: dengan MaxLoginAttempts == 0 (config
// kosong, seperti newSafetyTestServer) lockout NONAKTIF — satu kegagalan tidak
// boleh langsung mengunci. Ini menjaga test lama tetap berperilaku sama.
func TestMergeLockoutDisabledWhenConfigZero(t *testing.T) {
	db, _ := openOnboardingTestStore(t)

	f := seedMergeFixture(t, db, "lama@malva.test", "Penyerang")
	// Kombinasi PALING berbahaya: lockout dimatikan lewat MaxLoginAttempts=0
	// tetapi durasi tetap diisi. Tanpa guard `MaxLoginAttempts > 0`, dua
	// kegagalan sudah cukup mengunci (count >= 0).
	srv := newOnboardingTestServerWithCfg(db, config.Config{
		AllowedOrigins:   []string{"https://api.malva.id"},
		MaxLoginAttempts: 0,
		LockoutDuration:  15,
	})
	if srv.cfg.MaxLoginAttempts != 0 {
		t.Fatalf("prasyarat: MaxLoginAttempts harus 0, dapat %d", srv.cfg.MaxLoginAttempts)
	}

	// Lima kegagalan berturut-turut tetap harus 409 (bukan 429).
	for i := 1; i <= 5; i++ {
		rec, decoded := completeProfileForMerge(t, srv, f.googleUserID, f.strNumber, f.sipNumber, "Penyerang", "PasswordSalah999!")
		if rec.Code != http.StatusConflict {
			t.Fatalf("kegagalan ke-%d dengan lockout nonaktif: mau 409, dapat %d: %s", i, rec.Code, rec.Body.String())
		}
		if decoded["code"] != mergeVerificationRequiredCode {
			t.Fatalf("kegagalan ke-%d: code harus %q, dapat %v", i, mergeVerificationRequiredCode, decoded["code"])
		}
	}
}

// TestFixtureCleanupLeavesNoRows menjaga agar fixture test TIDAK membocorkan
// baris ke DB bersama.
//
// Regresi yang dijaga: cleanup fixture dulu dijalankan setelah `defer
// db.Close()` sehingga selalu gagal dengan "sql: database is closed" dan
// errornya ditelan — test tetap PASS sambil menambah ~18 user per run. Test
// ini menjalankan cleanup secara eksplisit lalu memastikan 0 baris tersisa di
// users DAN di tabel anaknya.
func TestFixtureCleanupLeavesNoRows(t *testing.T) {
	db, _ := openOnboardingTestStore(t)
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	f := seedMergeFixture(t, db, "lama@malva.test", "Penyerang")
	arr := pqUUIDArray(f.oldUserID, f.googleUserID)

	// Prasyarat: fixture benar-benar membuat 2 user.
	var before int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM users WHERE id = ANY($1::uuid[])`, arr).Scan(&before); err != nil {
		t.Fatalf("hitung user fixture: %v", err)
	}
	if before != 2 {
		t.Fatalf("fixture harus membuat 2 user, dapat %d", before)
	}

	// Jalankan cleanup secara eksplisit (yang di t.Cleanup akan jalan lagi
	// setelah ini dan harus aman/idempoten).
	cleanupTestUsers(t, db, f.oldUserID, f.googleUserID)

	var after int
	if err := db.QueryRowContext(ctx, `SELECT COUNT(*) FROM users WHERE id = ANY($1::uuid[])`, arr).Scan(&after); err != nil {
		t.Fatalf("verifikasi user setelah cleanup: %v", err)
	}
	if after != 0 {
		t.Fatalf("cleanup menyisakan %d user uji", after)
	}
	for _, table := range []string{"professional_profiles", "professional_credentials", "audit_logs"} {
		column := "user_id"
		if table == "audit_logs" {
			column = "actor_id"
		}
		var n int
		q := fmt.Sprintf(`SELECT COUNT(*) FROM "%s" WHERE "%s" = ANY($1::uuid[])`, table, column)
		if err := db.QueryRowContext(ctx, q, arr).Scan(&n); err != nil {
			t.Errorf("hitung sisa %s: %v", table, err)
			continue
		}
		if n != 0 {
			t.Errorf("cleanup menyisakan %d baris di %s", n, table)
		}
	}
}
