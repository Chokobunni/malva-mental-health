package server

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"database/sql"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgconn"

	"malva/backend/internal/auth"
	googlecal "malva/backend/internal/google"
	"malva/backend/internal/store"
)

var identityTestSigningKey *rsa.PrivateKey
var identityTestSigningKeyOnce sync.Once

type identityTestTransport func(*http.Request) (*http.Response, error)

func (f identityTestTransport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

// Verify real RSA signatures and token exchange through an intercepted HTTP boundary.
// No live Google accounts, network calls or production tokens are used.
func TestGoogleHTTPIdentityProtections(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	ctx := context.Background()
	identityTestSigningKeyOnce.Do(func() {
		var err error
		identityTestSigningKey, err = rsa.GenerateKey(rand.Reader, 2048)
		if err != nil {
			t.Fatal(err)
		}
	})
	key := identityTestSigningKey
	sign := func(subject, email string, verified bool) string {
		t.Helper()
		header, _ := json.Marshal(map[string]any{"alg": "RS256", "kid": "malva-identity-test"})
		payload, _ := json.Marshal(map[string]any{"iss": "https://accounts.google.com", "aud": "test-client", "sub": subject, "email": email, "email_verified": verified, "exp": time.Now().Add(time.Hour).Unix()})
		unsigned := base64.RawURLEncoding.EncodeToString(header) + "." + base64.RawURLEncoding.EncodeToString(payload)
		hash := sha256.Sum256([]byte(unsigned))
		sig, err := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, hash[:])
		if err != nil {
			t.Fatal(err)
		}
		return unsigned + "." + base64.RawURLEncoding.EncodeToString(sig)
	}
	response := func(body any) (*http.Response, error) {
		raw, _ := json.Marshal(body)
		return &http.Response{StatusCode: 200, Header: http.Header{"Content-Type": []string{"application/json"}, "Cache-Control": []string{"max-age=3600"}}, Body: io.NopCloser(strings.NewReader(string(raw)))}, nil
	}
	var exchangedToken, scope string
	oldTransport := http.DefaultTransport
	http.DefaultTransport = identityTestTransport(func(r *http.Request) (*http.Response, error) {
		switch r.URL.Host {
		case "www.googleapis.com":
			if r.URL.Path != "/oauth2/v3/certs" {
				return nil, errors.New("unexpected Google request")
			}
			return response(map[string]any{"keys": []any{map[string]string{"kty": "RSA", "alg": "RS256", "kid": "malva-identity-test", "n": base64.RawURLEncoding.EncodeToString(key.N.Bytes()), "e": base64.RawURLEncoding.EncodeToString(big.NewInt(int64(key.E)).Bytes())}}})
		case "oauth2.googleapis.com":
			return response(map[string]any{"access_token": "test-access", "refresh_token": "test-refresh", "token_type": "Bearer", "expires_in": 3600, "id_token": exchangedToken, "scope": scope})
		default:
			return nil, errors.New("network disabled in identity tests")
		}
	})
	t.Cleanup(func() { http.DefaultTransport = oldTransport })
	srv := newOnboardingTestServer(db)
	srv.cfg.GoogleClientID = "test-client"
	srv.cfg.GoogleClientSecret = "test-secret"
	suffix := fmt.Sprint(time.Now().UnixNano())
	subject := "http-" + suffix
	email := suffix + "@example.test"
	u := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{Specialization: "Sp.KJ"})
	claims := auth.Claims{Subject: u.ID, Role: "professional"}
	callBind := func(token string, legacy bool) *httptest.ResponseRecorder {
		raw, _ := json.Marshal(map[string]any{"id_token": token})
		req := httptest.NewRequest("POST", "/v1/auth/bind-google", strings.NewReader(string(raw)))
		rec := httptest.NewRecorder()
		if legacy {
			srv.linkGoogle(rec, req, claims)
		} else {
			srv.bindGoogle(rec, req, claims)
		}
		return rec
	}
	if rec := callBind(sign(subject, email, false), false); rec.Code != 401 {
		t.Fatalf("unverified email accepted: %d %s", rec.Code, rec.Body.String())
	}
	if rec := callBind(sign(subject, email, true), false); rec.Code != 200 {
		t.Fatalf("bind failed: %d %s", rec.Code, rec.Body.String())
	}
	if rec := callBind(sign(subject, email, true), true); rec.Code != 200 || !strings.Contains(rec.Body.String(), `"status":"linked"`) {
		t.Fatalf("legacy retry incompatible: %d %s", rec.Code, rec.Body.String())
	}
	if rec := callBind(sign("different-"+subject, "other-"+email, true), true); rec.Code != 409 {
		t.Fatalf("legacy overwrote identity: %d %s", rec.Code, rec.Body.String())
	}
	// Auto-email login must not overwrite an existing different subject either.
	auto, _ := json.Marshal(googleAuthRequest{IDToken: sign("different-"+subject, email, true), Role: "professional"})
	rec := httptest.NewRecorder()
	srv.googleLogin(rec, httptest.NewRequest("POST", "/v1/auth/google", strings.NewReader(string(auto))))
	if rec.Code != 409 {
		t.Fatalf("auto email link overwrote identity: %d %s", rec.Code, rec.Body.String())
	}
	for _, tc := range []struct {
		name, token, scope string
		status             int
	}{
		{"different account", sign("other-"+subject, "other-"+email, true), "https://www.googleapis.com/auth/calendar.events", 409},
		{"missing ID token", "", "https://www.googleapis.com/auth/calendar.events", 401},
		{"missing consent", sign(subject, email, true), "openid email", 403},
		{"matching account", sign(subject, email, true), "openid email https://www.googleapis.com/auth/calendar.events", 200},
	} {
		t.Run(tc.name, func(t *testing.T) {
			exchangedToken = tc.token
			scope = tc.scope
			rec := httptest.NewRecorder()
			srv.exchangeGoogleToken(rec, httptest.NewRequest("POST", "/v1/auth/google-token-exchange", strings.NewReader(`{"authorization_code":"test-code"}`)), claims)
			if rec.Code != tc.status {
				t.Fatalf("expected %d got %d %s", tc.status, rec.Code, rec.Body.String())
			}
			token, err := st.GetGoogleToken(ctx, u.ID)
			if tc.status != 200 && !errors.Is(err, sql.ErrNoRows) {
				t.Fatalf("rejected authorization stored tokens: %+v %v", token, err)
			}
			if tc.status == 200 && (err != nil || token.GoogleSubject != subject) {
				t.Fatalf("verified token not stored: %+v %v", token, err)
			}
		})
	}
}

func TestBindGooglePreservesProfessionalAccount(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	ctx := context.Background()
	suffix := fmt.Sprint(time.Now().UnixNano())
	u := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		STRNumber: "STR-" + suffix, SIPNumber: "SIP-" + suffix, Specialization: "Sp.KJ", Bio: "Retain biography", HospitalName: "Retain hospital",
	})
	before, err := st.GetProfessionalCredential(ctx, u.ID)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := db.Exec(`UPDATE professional_credentials SET verification_status='VERIFIED' WHERE user_id=$1`, u.ID); err != nil {
		t.Fatal(err)
	}
	if err := st.AddAuditLog(ctx, u.ID, u.ID, "test.history", "user", u.ID, map[string]any{"preserve": true}); err != nil {
		t.Fatal(err)
	}
	email := "bound-" + suffix + "@example.test"
	identity, err := st.LinkGoogleIdentity(ctx, u.ID, "subject-"+suffix, "  "+strings.ToUpper(email)+"  ", false)
	if err != nil {
		t.Fatal(err)
	}
	if !identity.Linked || identity.Email != email || identity.LinkedAt == nil || identity.EmailIsPlaceholder {
		t.Fatalf("incorrect binding: %+v", identity)
	}
	afterUser, err := st.GetUserByID(ctx, u.ID)
	if err != nil || afterUser.ID != u.ID || afterUser.Email != email || afterUser.DisplayName != u.DisplayName || afterUser.PasswordHash != u.PasswordHash {
		t.Fatalf("account changed: %+v %v", afterUser, err)
	}
	after, err := st.GetProfessionalCredential(ctx, u.ID)
	if err != nil || after.ID != before.ID || after.STRNumber != before.STRNumber || after.SIPNumber != before.SIPNumber || after.Bio != before.Bio || after.HospitalName != before.HospitalName || after.VerificationStatus != "VERIFIED" {
		t.Fatalf("credentials changed: %+v %v", after, err)
	}
	var count int
	if err := db.QueryRow(`SELECT count(*) FROM audit_logs WHERE actor_id=$1 AND action='test.history'`, u.ID).Scan(&count); err != nil || count != 1 {
		t.Fatalf("history lost: %d %v", count, err)
	}
	retry, err := st.LinkGoogleIdentity(ctx, u.ID, "subject-"+suffix, email, true)
	if err != nil || !retry.LinkedAt.Equal(*identity.LinkedAt) {
		t.Fatalf("not idempotent: %+v %v", retry, err)
	}
	if _, err := st.LinkGoogleIdentity(ctx, u.ID, "different-"+suffix, "different-"+email, true); !errors.Is(err, store.ErrGoogleIdentityBound) {
		t.Fatalf("subject replacement permitted: %v", err)
	}
}

func TestGoogleBindingOwnershipChecks(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	ctx := context.Background()
	owner := createIdentityTestUser(t, db, st, "patient", nil)
	caller := createIdentityTestUser(t, db, st, "patient", nil)
	suffix := fmt.Sprint(time.Now().UnixNano())
	googleEmail := "identity-" + suffix + "@example.test"
	if _, err := st.LinkGoogleIdentity(ctx, owner.ID, "owner-"+suffix, googleEmail, true); err != nil {
		t.Fatal(err)
	}
	unchanged, err := st.GetUserByID(ctx, owner.ID)
	if err != nil || unchanged.Email != owner.Email {
		t.Fatalf("patient email was overwritten: %+v %v", unchanged, err)
	}
	for _, tc := range []struct {
		name, subject, email string
		want                 error
	}{
		{"subject owned", "owner-" + suffix, "other-" + googleEmail, store.ErrGoogleAlreadyLinked},
		{"SSO email owned", "other-" + suffix, "  " + strings.ToUpper(googleEmail) + " ", store.ErrEmailOwnedByOther},
		{"account email owned", "another-" + suffix, strings.ToUpper(owner.Email), store.ErrEmailOwnedByOther},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if _, err := st.LinkGoogleIdentity(ctx, caller.ID, tc.subject, tc.email, false); !errors.Is(err, tc.want) {
				t.Fatalf("expected %v, got %v", tc.want, err)
			}
		})
	}
	if _, err := db.Exec(`UPDATE users SET disabled_at = now() WHERE id=$1`, owner.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := st.LinkGoogleIdentity(ctx, caller.ID, "owner-"+suffix, googleEmail, false); !errors.Is(err, store.ErrGoogleAlreadyLinked) {
		t.Fatalf("disabled identity could be reused: %v", err)
	}
	identity, err := st.GetGoogleIdentity(ctx, caller.ID)
	if err != nil || identity.Linked {
		t.Fatalf("rejected binding modified caller: %+v %v", identity, err)
	}
}

func TestGoogleIdentityAndRegistrationRaces(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	ctx := context.Background()
	for _, sameSubject := range []bool{true, false} {
		t.Run(fmt.Sprintf("same-subject-%v", sameSubject), func(t *testing.T) {
			a := createIdentityTestUser(t, db, st, "patient", nil)
			b := createIdentityTestUser(t, db, st, "patient", nil)
			suffix := fmt.Sprint(time.Now().UnixNano())
			start := make(chan struct{})
			errs := make(chan error, 2)
			for i, user := range []store.User{a, b} {
				go func(i int, user store.User) {
					<-start
					subject := "racing-" + suffix
					if !sameSubject {
						subject += fmt.Sprint(i)
					}
					_, err := st.LinkGoogleIdentity(ctx, user.ID, subject, "race-"+suffix+"@example.test", false)
					errs <- err
				}(i, user)
			}
			close(start)
			success, conflicts := 0, 0
			for i := 0; i < 2; i++ {
				err := <-errs
				if err == nil {
					success++
				} else if errors.Is(err, store.ErrGoogleAlreadyLinked) || errors.Is(err, store.ErrEmailOwnedByOther) {
					conflicts++
				} else {
					t.Fatal(err)
				}
			}
			if success != 1 || conflicts != 1 {
				t.Fatalf("success=%d conflicts=%d", success, conflicts)
			}
		})
	}
	// A bind using a separate sso_email races with password registration.
	u := createIdentityTestUser(t, db, st, "patient", nil)
	suffix := fmt.Sprint(time.Now().UnixNano())
	email := "register-race-" + suffix + "@example.test"
	start := make(chan struct{})
	var wg sync.WaitGroup
	wg.Add(2)
	var bindErr, registerErr error
	var registered store.User
	go func() {
		defer wg.Done()
		<-start
		_, bindErr = st.LinkGoogleIdentity(ctx, u.ID, "register-race-"+suffix, email, false)
	}()
	go func() {
		defer wg.Done()
		<-start
		registered, registerErr = st.CreateUser(ctx, store.CreateUserParams{Email: email, PasswordHash: "hash", Role: "patient", DisplayName: "Race"})
	}()
	close(start)
	wg.Wait()
	if registered.ID != "" {
		t.Cleanup(func() { cleanupTestUsers(t, db, registered.ID) })
	}
	if (bindErr == nil) == (registerErr == nil) {
		t.Fatalf("exactly one must win: bind=%v registration=%v", bindErr, registerErr)
	}
	for _, err := range []error{bindErr, registerErr} {
		if err != nil && !errors.Is(err, store.ErrEmailOwnedByOther) {
			t.Fatal(err)
		}
	}
}

func TestIdentifierRegistrationAtomicityAndNamespaces(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	ctx := context.Background()
	suffix := fmt.Sprint(time.Now().UnixNano())
	owner := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{STRNumber: "STR-" + suffix, SIPNumber: "SIP-" + suffix, Specialization: "Sp.KJ"})
	for _, tc := range []struct{ str, sip string }{{" str-" + suffix + " ", "new-sip-" + suffix}, {"new-str-" + suffix, " sip-" + suffix + " "}} {
		email := fmt.Sprint(time.Now().UnixNano()) + "@example.test"
		_, err := st.CreateUser(ctx, store.CreateUserParams{Email: email, PasswordHash: "hash", Role: "professional", DisplayName: "Duplicate", ProfessionalID: "new-" + email, Credential: &store.ProfessionalCredential{STRNumber: tc.str, SIPNumber: tc.sip, Specialization: "Sp.KJ"}})
		if !store.IsUniqueViolation(err) {
			t.Fatalf("DB accepted normalized duplicate: %v", err)
		}
		var n int
		if err := db.QueryRow(`SELECT count(*) FROM users WHERE email=$1`, email).Scan(&n); err != nil || n != 0 {
			t.Fatalf("partial user persisted: %d %v", n, err)
		}
	}
	// Cross-kind equality is allowed; ambiguous identifier login is refused.
	createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{STRNumber: "SIP-" + suffix, SIPNumber: "STR-" + suffix, Specialization: "Sp.KJ"})
	if _, err := st.FindUserByProfessionalIdentifier(ctx, "STR-"+suffix); !errors.Is(err, sql.ErrNoRows) {
		t.Fatalf("ambiguous login selected an owner: %v", err)
	}
	if taken, err := st.ProfessionalIdentifierTaken(ctx, "str", " str-"+suffix+" ", ""); err != nil || !taken {
		t.Fatalf("empty exclude query failed: %v %v", taken, err)
	}
	if taken, err := st.ProfessionalIdentifierTaken(ctx, "str", " str-"+suffix+" ", owner.ID); err != nil || taken {
		t.Fatalf("own STR rejected: %v %v", taken, err)
	}
}

func TestProfessionalIdentifierGuardFailsClosed(t *testing.T) {
	db, err := sql.Open("pgx", "postgres://unused:unused@127.0.0.1:1/unused?sslmode=disable")
	if err != nil {
		t.Fatal(err)
	}
	_ = db.Close()
	srv := &Server{store: store.New(db)}
	err = srv.rejectTakenProfessionalIdentifier(httptest.NewRequest("POST", "/", nil), "STR", "SIP", "")
	if err == nil {
		t.Fatal("database error was ignored")
	}
	rec := httptest.NewRecorder()
	writeProfessionalError(rec, err)
	if rec.Code != 500 || strings.Contains(rec.Body.String(), "database is closed") {
		t.Fatalf("unsafe database failure: %d %s", rec.Code, rec.Body.String())
	}
}

func TestGoogleStatusSeparatesIdentityAndCalendar(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	ctx := context.Background()
	u := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{Specialization: "Sp.KJ"})
	srv := newOnboardingTestServer(db)
	srv.calendar = googlecal.NewCalendarService(srv.cfg, st)
	status := func() map[string]any {
		t.Helper()
		rec := httptest.NewRecorder()
		srv.googleStatusHandler(rec, httptest.NewRequest("GET", "/v1/google/status", nil), auth.Claims{Subject: u.ID, Role: "professional"})
		if rec.Code != 200 {
			t.Fatalf("status: %d %s", rec.Code, rec.Body.String())
		}
		var body map[string]any
		_ = json.Unmarshal(rec.Body.Bytes(), &body)
		for _, secret := range []string{"refresh_token", "access_token", "google_subject"} {
			if _, ok := body[secret]; ok {
				t.Fatalf("status exposed %s", secret)
			}
		}
		return body
	}
	if got := status(); got["identity_bound"] != false || got["calendar_ready"] != false {
		t.Fatal(got)
	}
	suffix := fmt.Sprint(time.Now().UnixNano())
	subject := "status-" + suffix
	if _, err := st.LinkGoogleIdentity(ctx, u.ID, subject, suffix+"@example.test", false); err != nil {
		t.Fatal(err)
	}
	if got := status(); got["identity_bound"] != true || got["connected"] != false {
		t.Fatal(got)
	}
	for _, tc := range []struct {
		scope, sub string
		ready      bool
	}{
		{"openid email", subject, false},
		{"https://www.googleapis.com/auth/calendar.events", "", false},
		{"https://www.googleapis.com/auth/calendar.events", "other", false},
		{"https://www.googleapis.com/auth/calendar.events", subject, true},
	} {
		if err := st.UpsertGoogleToken(ctx, u.ID, "test-refresh", "test-access", time.Now().Add(time.Hour), tc.scope, tc.sub); err != nil {
			t.Fatal(err)
		}
		got := status()
		if got["calendar_ready"] != tc.ready || got["connected"] != tc.ready {
			t.Fatalf("scope=%s subject=%s status=%v", tc.scope, tc.sub, got)
		}
	}
}

func TestGoogleBindingRoutesRequireAuthentication(t *testing.T) {
	srv, _, _ := newSafetyTestServer()
	for _, tc := range []struct{ method, path string }{{"POST", "/v1/auth/bind-google"}, {"POST", "/v1/auth/link-google"}, {"GET", "/v1/auth/google-identity"}} {
		rec := doAuthed(t, srv.Routes(), tc.method, tc.path, "", `{"id_token":"test"}`)
		if rec.Code != http.StatusUnauthorized {
			t.Fatalf("%s: %d", tc.path, rec.Code)
		}
	}
	rec := httptest.NewRecorder()
	srv.Routes().ServeHTTP(rec, httptest.NewRequest("DELETE", "/v1/auth/bind-google", nil))
	if rec.Code != http.StatusMethodNotAllowed {
		t.Fatalf("unlink route still exists: %d", rec.Code)
	}
}

// TestWriteGoogleIdentityErrorCodes mengunci pemetaan sentinel store ke
// respons HTTP + kode mesin yang dikonsumsi UI Flutter. Test ini murni
// (tanpa database) sehingga selalu berjalan di CI.
func TestWriteGoogleIdentityErrorCodes(t *testing.T) {
	cases := []struct {
		name   string
		err    error
		status int
		code   string
		msg    string
	}{
		{
			"google already linked", store.ErrGoogleAlreadyLinked,
			http.StatusConflict, googleAlreadyLinkedCode,
			"Akun Google ini sudah terhubung ke akun Malva lain.",
		},
		{
			"email owned by other", store.ErrEmailOwnedByOther,
			http.StatusConflict, googleEmailTakenCode,
			"Email Google ini sudah dipakai akun Malva lain.",
		},
		{
			"identity bound to another google", store.ErrGoogleIdentityBound,
			http.StatusConflict, googleIdentityBoundCode,
			"Akun ini sudah terhubung ke akun Google lain. Hubungi admin bila ingin mengganti.",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			rec := httptest.NewRecorder()
			writeGoogleIdentityError(rec, tc.err)
			var body map[string]string
			if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil {
				t.Fatalf("respons bukan JSON: %v", err)
			}
			if rec.Code != tc.status || body["code"] != tc.code || body["error"] != tc.msg {
				t.Fatalf("dapat %d %+v, ingin %d code=%s", rec.Code, body, tc.status, tc.code)
			}
		})
	}

	// Raw unique violation pada index SSO -> google_sudah_tertaut.
	rec := httptest.NewRecorder()
	writeGoogleIdentityError(rec, &pgconn.PgError{Code: "23505", ConstraintName: "users_sso_unique"})
	var body map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil || body["code"] != googleAlreadyLinkedCode {
		t.Fatalf("unique users_sso_unique: %d %+v %v", rec.Code, body, err)
	}
	// Unique violation lain -> email_sudah_dipakai.
	rec = httptest.NewRecorder()
	writeGoogleIdentityError(rec, &pgconn.PgError{Code: "23505", ConstraintName: "users_email_key"})
	if err := json.Unmarshal(rec.Body.Bytes(), &body); err != nil || body["code"] != googleEmailTakenCode {
		t.Fatalf("unique email: %d %+v %v", rec.Code, body, err)
	}
	// Akun tidak ditemukan -> 404 tanpa kode mesin.
	rec = httptest.NewRecorder()
	writeGoogleIdentityError(rec, sql.ErrNoRows)
	if rec.Code != http.StatusNotFound {
		t.Fatalf("no rows: %d", rec.Code)
	}
	// Error tak dikenal -> 500.
	rec = httptest.NewRecorder()
	writeGoogleIdentityError(rec, errors.New("boom"))
	if rec.Code != http.StatusInternalServerError {
		t.Fatalf("unknown error: %d", rec.Code)
	}
}

// signIdentityToken menandatangani JWT Google palsu dengan kunci uji agar
// idtoken.Validate sungguhan bisa memverifikasi tanda tangan.
func signIdentityToken(t *testing.T, key *rsa.PrivateKey, subject, email string, verified bool) string {
	t.Helper()
	header, _ := json.Marshal(map[string]any{"alg": "RS256", "kid": "malva-identity-test"})
	payload, _ := json.Marshal(map[string]any{
		"iss": "https://accounts.google.com", "aud": "test-client", "sub": subject,
		"email": email, "email_verified": verified, "exp": time.Now().Add(time.Hour).Unix(),
	})
	unsigned := base64.RawURLEncoding.EncodeToString(header) + "." + base64.RawURLEncoding.EncodeToString(payload)
	hash := sha256.Sum256([]byte(unsigned))
	sig, err := rsa.SignPKCS1v15(rand.Reader, key, crypto.SHA256, hash[:])
	if err != nil {
		t.Fatal(err)
	}
	return unsigned + "." + base64.RawURLEncoding.EncodeToString(sig)
}

// installIdentityCertsTransport hanya melayani endpoint sertifikat Google;
// semua trafik lain ditolak agar test tidak pernah menyentuh jaringan nyata.
func installIdentityCertsTransport(t *testing.T, key *rsa.PrivateKey) {
	t.Helper()
	oldTransport := http.DefaultTransport
	http.DefaultTransport = identityTestTransport(func(r *http.Request) (*http.Response, error) {
		if r.URL.Host == "www.googleapis.com" && r.URL.Path == "/oauth2/v3/certs" {
			raw, _ := json.Marshal(map[string]any{"keys": []any{map[string]string{
				"kty": "RSA", "alg": "RS256", "kid": "malva-identity-test",
				"n": base64.RawURLEncoding.EncodeToString(key.N.Bytes()),
				"e": base64.RawURLEncoding.EncodeToString(big.NewInt(int64(key.E)).Bytes()),
			}}})
			return &http.Response{
				StatusCode: 200,
				Header:     http.Header{"Content-Type": []string{"application/json"}, "Cache-Control": []string{"max-age=3600"}},
				Body:       io.NopCloser(strings.NewReader(string(raw))),
			}, nil
		}
		return nil, errors.New("network disabled in identity tests")
	})
	t.Cleanup(func() { http.DefaultTransport = oldTransport })
}

// TestBindGoogleHTTPErrorCodes memverifikasi kode mesin pada route
// POST /v1/auth/bind-google untuk tiap konflik kepemilikan (butuh Postgres).
func TestBindGoogleHTTPErrorCodes(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	identityTestSigningKeyOnce.Do(func() {
		var err error
		identityTestSigningKey, err = rsa.GenerateKey(rand.Reader, 2048)
		if err != nil {
			t.Fatal(err)
		}
	})
	key := identityTestSigningKey
	installIdentityCertsTransport(t, key)
	srv := newOnboardingTestServer(db)
	srv.cfg.GoogleClientID = "test-client"
	suffix := fmt.Sprint(time.Now().UnixNano())
	a := createIdentityTestUser(t, db, st, "patient", nil)
	b := createIdentityTestUser(t, db, st, "patient", nil)
	subject := "shared-" + suffix
	emailA := "a-" + suffix + "@example.test"
	callBind := func(userID, token string) *httptest.ResponseRecorder {
		raw, _ := json.Marshal(map[string]any{"id_token": token})
		rec := httptest.NewRecorder()
		srv.bindGoogle(rec, httptest.NewRequest("POST", "/v1/auth/bind-google", strings.NewReader(string(raw))),
			auth.Claims{Subject: userID, Role: "patient"})
		return rec
	}
	codeOf := func(rec *httptest.ResponseRecorder) string {
		var body map[string]string
		_ = json.Unmarshal(rec.Body.Bytes(), &body)
		return body["code"]
	}
	if rec := callBind(a.ID, signIdentityToken(t, key, subject, emailA, true)); rec.Code != http.StatusOK {
		t.Fatalf("bind pemilik gagal: %d %s", rec.Code, rec.Body.String())
	}
	if rec := callBind(b.ID, signIdentityToken(t, key, subject, "b-"+suffix+"@example.test", true)); rec.Code != http.StatusConflict || codeOf(rec) != googleAlreadyLinkedCode {
		t.Fatalf("konflik subject: %d %s", rec.Code, rec.Body.String())
	}
	if rec := callBind(b.ID, signIdentityToken(t, key, "s2-"+suffix, emailA, true)); rec.Code != http.StatusConflict || codeOf(rec) != googleEmailTakenCode {
		t.Fatalf("konflik email: %d %s", rec.Code, rec.Body.String())
	}
	if rec := callBind(b.ID, signIdentityToken(t, key, "b-subject-"+suffix, "b3-"+suffix+"@example.test", true)); rec.Code != http.StatusOK {
		t.Fatalf("bind B gagal: %d %s", rec.Code, rec.Body.String())
	}
	if rec := callBind(b.ID, signIdentityToken(t, key, "b-other-"+suffix, "b4-"+suffix+"@example.test", true)); rec.Code != http.StatusConflict || codeOf(rec) != googleIdentityBoundCode {
		t.Fatalf("akun sudah tertaut google lain: %d %s", rec.Code, rec.Body.String())
	}
}
