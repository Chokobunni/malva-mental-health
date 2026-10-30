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
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	_ "github.com/jackc/pgx/v5/stdlib"

	"malva/backend/internal/auth"
	"malva/backend/internal/config"
	"malva/backend/internal/store"
)

// These tests require an explicit local test database, never the app DSN.
func openOnboardingTestStore(t *testing.T) (*sql.DB, *store.Store) {
	t.Helper()
	dsn := os.Getenv("MALVA_TEST_DATABASE_URL")
	if dsn == "" {
		t.Skip("MALVA_TEST_DATABASE_URL is not configured")
	}
	u, err := url.Parse(dsn)
	if err != nil || (u.Hostname() != "localhost" && u.Hostname() != "127.0.0.1" && u.Hostname() != "::1") {
		t.Fatal("identity tests require a local test database")
	}
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = db.Close() })
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := db.PingContext(ctx); err != nil {
		t.Fatalf("configured test DB unavailable: %v", err)
	}
	var n int
	if err := db.QueryRowContext(ctx, `SELECT count(*) FROM information_schema.columns WHERE table_schema = current_schema() AND table_name = 'users' AND column_name = 'sso_email'`).Scan(&n); err != nil || n != 1 {
		t.Fatalf("test DB must have migration 021: count=%d, err=%v", n, err)
	}
	return db, store.New(db)
}

func pqUUIDArray(ids ...string) string { return "{" + strings.Join(ids, ",") + "}" }

func cleanupTestUsers(t *testing.T, db *sql.DB, ids ...string) {
	t.Helper()
	ctx := context.Background()
	arr := pqUUIDArray(ids...)
	for _, q := range []string{
		`DELETE FROM audit_logs WHERE actor_id = ANY($1::uuid[]) OR patient_id = ANY($1::uuid[])`,
		`DELETE FROM auth_sessions WHERE user_id = ANY($1::uuid[])`,
		`DELETE FROM users WHERE id = ANY($1::uuid[])`,
	} {
		if _, err := db.ExecContext(ctx, q, arr); err != nil {
			t.Errorf("cleanup test users: %v", err)
		}
	}
	var n int
	if err := db.QueryRowContext(ctx, `SELECT count(*) FROM users WHERE id = ANY($1::uuid[])`, arr).Scan(&n); err != nil || n != 0 {
		t.Errorf("test users remain: count=%d, err=%v", n, err)
	}
}

func newOnboardingTestServer(db *sql.DB) *Server {
	cfg := config.Config{AllowedOrigins: []string{"https://api.malva.id"}}
	logger := slog.New(slog.NewTextHandler(testWriter{}, nil))
	mgr := auth.NewManager("12345678901234567890123456789012")
	return New(cfg, mgr, store.New(db), nil, logger)
}

func createIdentityTestUser(t *testing.T, db *sql.DB, st *store.Store, role string, credential *store.ProfessionalCredential) store.User {
	t.Helper()
	suffix := fmt.Sprint(time.Now().UnixNano())
	u, err := st.CreateUser(context.Background(), store.CreateUserParams{
		Email: suffix + "@professional.malva.local", PasswordHash: "test-hash", Role: role,
		DisplayName: "Original Name", ProfessionalID: "profile-" + suffix, Credential: credential,
	})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { cleanupTestUsers(t, db, u.ID) })
	return u
}

func TestCompleteProfessionalRejectsExistingIdentifierWithoutMerge(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	suffix := fmt.Sprint(time.Now().UnixNano())
	owner := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{STRNumber: "STR-" + suffix, SIPNumber: "SIP-" + suffix, Specialization: "Sp.KJ", Bio: "Preserved biography"})
	caller := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{Specialization: "M.Psi"})
	if _, err := st.LinkGoogleIdentity(context.Background(), caller.ID, "caller-"+suffix, "caller-"+suffix+"@example.test", false); err != nil {
		t.Fatal(err)
	}
	srv := newOnboardingTestServer(db)
	for _, tc := range []struct{ name, str, sip, password string }{
		{"duplicate STR", " str-" + suffix + " ", "new-sip-" + suffix, ""},
		{"duplicate SIP", "new-str-" + suffix, " sip-" + suffix + " ", ""},
		{"old password cannot authorize merge", "STR-" + suffix, "SIP-" + suffix, "CorrectOldPassword123!"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if tc.password != "" {
				hash, err := auth.HashPassword(tc.password)
				if err != nil {
					t.Fatal(err)
				}
				if _, err := db.Exec(`UPDATE users SET password_hash = $2 WHERE id = $1`, owner.ID, hash); err != nil {
					t.Fatal(err)
				}
			}
			raw, _ := json.Marshal(completeProfessionalRequest{STRNumber: tc.str, SIPNumber: tc.sip, Specialization: "Sp.KJ", DisplayName: "Replacement", ExistingPassword: tc.password})
			rec := httptest.NewRecorder()
			srv.completeProfessionalProfile(rec, httptest.NewRequest("POST", "/v1/auth/complete-professional", bytes.NewReader(raw)), auth.Claims{Subject: caller.ID, Role: "professional"})
			var body map[string]any
			_ = json.Unmarshal(rec.Body.Bytes(), &body)
			if rec.Code != 409 || body["code"] != professionalIdentifierTakenCode {
				t.Fatalf("expected identifier conflict: %d %s", rec.Code, rec.Body.String())
			}
			for _, field := range []string{"access_token", "refresh_token", "credential", "user"} {
				if _, ok := body[field]; ok {
					t.Fatalf("conflict leaked %s", field)
				}
			}
		})
	}
	original, err := st.GetUserByID(context.Background(), owner.ID)
	if err != nil || original.DisplayName != owner.DisplayName {
		t.Fatalf("owner changed: %+v %v", original, err)
	}
	identity, err := st.GetGoogleIdentity(context.Background(), owner.ID)
	if err != nil || identity.Linked {
		t.Fatalf("owner acquired caller identity: %+v %v", identity, err)
	}
	cred, err := st.GetProfessionalCredential(context.Background(), owner.ID)
	if err != nil || cred.Bio != "Preserved biography" {
		t.Fatalf("owner credentials changed: %+v %v", cred, err)
	}
}

func TestCompleteProfessionalPreservesDetailsAndUUID(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	u := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{Specialization: "M.Psi", Bio: "Keep bio", HospitalName: "Keep hospital"})
	suffix := fmt.Sprint(time.Now().UnixNano())
	raw, _ := json.Marshal(completeProfessionalRequest{STRNumber: "STR-" + suffix, SIPNumber: "SIP-" + suffix, Specialization: "Sp.KJ"})
	rec := httptest.NewRecorder()
	newOnboardingTestServer(db).completeProfessionalProfile(rec, httptest.NewRequest("POST", "/v1/auth/complete-professional", bytes.NewReader(raw)), auth.Claims{Subject: u.ID, Role: "professional"})
	if rec.Code != 200 {
		t.Fatalf("completion failed: %d %s", rec.Code, rec.Body.String())
	}
	cred, err := st.GetProfessionalCredential(context.Background(), u.ID)
	if err != nil || cred.UserID != u.ID || cred.Bio != "Keep bio" || cred.HospitalName != "Keep hospital" || cred.STRNumber != "STR-"+suffix {
		t.Fatalf("lost details: %+v %v", cred, err)
	}
}

func TestCompleteProfessionalStillRequiresAuth(t *testing.T) {
	srv, _, _ := newSafetyTestServer()
	rec := doAuthed(t, srv.Routes(), "POST", "/v1/auth/complete-professional", "", `{"str_number":"STR-X","sip_number":"SIP-X","specialization":"Sp.KJ"}`)
	if rec.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", rec.Code)
	}
}
