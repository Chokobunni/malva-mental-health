package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
	googlecal "malva/backend/internal/google"
	"malva/backend/internal/store"
)

// ============================================================
// SESI VIDEO "MENUNGGU LINK" (BUG 2) & STATUS MEET PROFESIONAL
//
// Aturan bisnis yang dikunci:
//   - Kondisi Google milik PROFESIONAL tidak boleh memblokir PASIEN. Bila
//     link belum bisa dibuat, sesi video tetap dijadwalkan dan link dibuat
//     menyusul.
//   - Satu-satunya kegagalan keras adalah server yang belum dikonfigurasi
//     Google (ErrMeetUnavailable).
//   - Status Meet diklasifikasikan (ready / not_linked / no_calendar_scope /
//     token_expired / server_not_configured) agar UI bisa memberi tindakan
//     yang tepat.
// ============================================================

func meetTestOptions() googlecal.MeetEventOptions {
	start := clock.Now().Add(48 * time.Hour)
	return googlecal.MeetEventOptions{
		Summary:   "Sesi Malva - Pasien Uji",
		StartTime: start,
		EndTime:   start.Add(30 * time.Minute),
	}
}

// TestPrepareScheduledMeetServerNotConfigured memastikan server tanpa
// integrasi Google tetap melaporkan kegagalan keras (501 di handler), bukan
// diam-diam menjadwalkan sesi yang link-nya tidak akan pernah bisa dibuat.
func TestPrepareScheduledMeetServerNotConfigured(t *testing.T) {
	srv := &Server{} // calendar nil, store nil

	_, _, pending, err := srv.prepareScheduledMeet(t.Context(), "prof-1", meetTestOptions())
	if !errors.Is(err, ErrMeetUnavailable) {
		t.Fatalf("error = %v, mau ErrMeetUnavailable", err)
	}
	if pending {
		t.Errorf("pending = true, mau false saat server belum dikonfigurasi")
	}
}

// TestPrepareScheduledMeetNotReadySchedulesPending membuktikan profesional
// yang belum siap (di sini: identitas Google tidak terbaca) TIDAK membuat
// handler gagal — sesi dijadwalkan dengan status menunggu link, dan Google
// tidak dipanggil sama sekali.
func TestPrepareScheduledMeetNotReadySchedulesPending(t *testing.T) {
	fake := &fakeMeetCalendar{
		createEventID: "evt-1",
		createMeetURL: "https://meet.google.com/abc-defg-hij",
	}
	srv := &Server{calendar: fake} // store nil -> googleCalendarReady false

	meetURL, eventID, pending, err := srv.prepareScheduledMeet(t.Context(), "prof-1", meetTestOptions())
	if err != nil {
		t.Fatalf("tidak diharapkan error: %v", err)
	}
	if !pending {
		t.Fatalf("pending = false, mau true saat Google belum siap")
	}
	if meetURL != "" || eventID != "" {
		t.Errorf("link/event harus kosong saat menunggu link, dapat (%q, %q)", meetURL, eventID)
	}
	if fake.createCalls != 0 {
		t.Errorf("Google tidak boleh dipanggil saat belum siap, dapat %d panggilan", fake.createCalls)
	}
}

// TestPrepareScheduledMeetDegradesOnReauth: profesional SIAP (identitas +
// token lengkap) tetapi Google menolak refresh token. Sesi tetap dijadwalkan
// menunggu link — pasien tidak boleh menerima 401.
func TestPrepareScheduledMeetDegradesOnReauth(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      "STR-MEET-" + fmt.Sprint(time.Now().UnixNano()),
		SIPNumber:      "SIP-MEET-" + fmt.Sprint(time.Now().UnixNano()),
	})
	t.Cleanup(func() { cleanupTestUsers(t, db, prof.ID) })
	linkReadyProfessional(t, st, prof.ID)

	fake := &fakeMeetCalendar{createErr: googlecal.ErrReauthNeeded}
	srv := newOnboardingTestServer(db)
	srv.calendar = fake

	_, _, pending, err := srv.prepareScheduledMeet(t.Context(), prof.ID, meetTestOptions())
	if err != nil {
		t.Fatalf("ErrReauthNeeded tidak boleh menggagalkan penjadwalan: %v", err)
	}
	if !pending {
		t.Fatalf("pending = false, mau true saat Google menolak refresh token")
	}
}

// TestPrepareScheduledMeetDegradesOnGoogleFailure: galat Google lain (5xx /
// jaringan) juga hanya menghasilkan sesi "menunggu link".
func TestPrepareScheduledMeetDegradesOnGoogleFailure(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      "STR-MEET2-" + fmt.Sprint(time.Now().UnixNano()),
		SIPNumber:      "SIP-MEET2-" + fmt.Sprint(time.Now().UnixNano()),
	})
	t.Cleanup(func() { cleanupTestUsers(t, db, prof.ID) })
	linkReadyProfessional(t, st, prof.ID)

	fake := &fakeMeetCalendar{createErr: errors.New("google calendar 503")}
	srv := newOnboardingTestServer(db)
	srv.calendar = fake

	_, _, pending, err := srv.prepareScheduledMeet(t.Context(), prof.ID, meetTestOptions())
	if err != nil {
		t.Fatalf("galat Google tidak boleh menggagalkan penjadwalan: %v", err)
	}
	if !pending {
		t.Fatalf("pending = false, mau true saat Google gagal")
	}
}

// TestPrepareScheduledMeetReturnsLinkWhenReady: jalur normal tetap membuat
// event dan mengembalikan link untuk disimpan ke care_sessions.
func TestPrepareScheduledMeetReturnsLinkWhenReady(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      "STR-MEET3-" + fmt.Sprint(time.Now().UnixNano()),
		SIPNumber:      "SIP-MEET3-" + fmt.Sprint(time.Now().UnixNano()),
	})
	t.Cleanup(func() { cleanupTestUsers(t, db, prof.ID) })
	linkReadyProfessional(t, st, prof.ID)

	const wantURL = "https://meet.google.com/abc-defg-hij"
	fake := &fakeMeetCalendar{createEventID: "evt-siap", createMeetURL: wantURL}
	srv := newOnboardingTestServer(db)
	srv.calendar = fake

	meetURL, eventID, pending, err := srv.prepareScheduledMeet(t.Context(), prof.ID, meetTestOptions())
	if err != nil {
		t.Fatalf("jalur siap tidak boleh error: %v", err)
	}
	if pending {
		t.Errorf("pending = true, mau false saat link berhasil dibuat")
	}
	if meetURL != wantURL || eventID != "evt-siap" {
		t.Errorf("hasil = (%q, %q), mau (%q, %q)", meetURL, eventID, wantURL, "evt-siap")
	}
}

// linkReadyProfessional menautkan identitas Google + token Calendar lengkap
// agar googleCalendarReady(prof) = true.
func linkReadyProfessional(t *testing.T, st *store.Store, userID string) {
	t.Helper()
	suffix := fmt.Sprint(time.Now().UnixNano())
	subject := "sub-meet-" + suffix
	if _, err := st.LinkGoogleIdentity(context.Background(), userID, subject,
		"meet"+suffix+"@example.test", false); err != nil {
		t.Fatalf("tautkan identitas Google: %v", err)
	}
	if err := st.UpsertGoogleToken(context.Background(), userID, "refresh-token", "access-token",
		time.Now().Add(time.Hour),
		"https://www.googleapis.com/auth/calendar.events", subject, true); err != nil {
		t.Fatalf("simpan token Google: %v", err)
	}
}

// TestMeetStatusHandlerServerNotConfigured: server tanpa integrasi Google
// melaporkan `server_not_configured` (masalah deployment, bukan akun).
func TestMeetStatusHandlerServerNotConfigured(t *testing.T) {
	srv := &Server{}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/v1/professionals/prof-1/meet-status", nil)
	req.SetPathValue("professional_id", "prof-1")
	srv.meetStatusHandler(rec, req, auth.Claims{Subject: "pasien-1", Role: "patient"})

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, mau %d (body: %s)", rec.Code, http.StatusOK, rec.Body.String())
	}
	var payload map[string]any
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("body bukan JSON: %v", err)
	}
	if payload["ready"] != false {
		t.Errorf("ready = %v, mau false", payload["ready"])
	}
	if payload["reason"] != meetReasonServerNotConfigured {
		t.Errorf("reason = %v, mau %q", payload["reason"], meetReasonServerNotConfigured)
	}
}

// TestMeetStatusHandlerProfessionalCannotInspectOthers: profesional hanya
// boleh memeriksa status akunnya sendiri.
func TestMeetStatusHandlerProfessionalCannotInspectOthers(t *testing.T) {
	srv := &Server{}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/v1/professionals/prof-lain/meet-status", nil)
	req.SetPathValue("professional_id", "prof-lain")
	srv.meetStatusHandler(rec, req, auth.Claims{Subject: "prof-saya", Role: "professional"})

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, mau %d", rec.Code, http.StatusForbidden)
	}
}

// TestMeetStatusHandlerRejectsUnsupportedRole memastikan peran lain (admin)
// tidak memakai endpoint ini.
func TestMeetStatusHandlerRejectsUnsupportedRole(t *testing.T) {
	srv := &Server{}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodGet, "/v1/professionals/prof-1/meet-status", nil)
	req.SetPathValue("professional_id", "prof-1")
	srv.meetStatusHandler(rec, req, auth.Claims{Subject: "admin-1", Role: "admin"})

	if rec.Code != http.StatusForbidden {
		t.Fatalf("status = %d, mau %d", rec.Code, http.StatusForbidden)
	}
}

// TestMeetStatusReasonStates mengunci pemetaan keadaan -> reason yang dipakai
// UI untuk memilih pesan & tindakan.
func TestMeetStatusReasonStates(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	ctx := context.Background()

	linked := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      "STR-STAT-" + fmt.Sprint(time.Now().UnixNano()),
		SIPNumber:      "SIP-STAT-" + fmt.Sprint(time.Now().UnixNano()),
	})
	unlinked := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      "STR-STAT2-" + fmt.Sprint(time.Now().UnixNano()),
		SIPNumber:      "SIP-STAT2-" + fmt.Sprint(time.Now().UnixNano()),
	})
	t.Cleanup(func() { cleanupTestUsers(t, db, linked.ID, unlinked.ID) })

	srv := newOnboardingTestServer(db)
	srv.calendar = &fakeMeetCalendar{}

	// 1. Belum menautkan Gmail.
	if got := srv.meetStatusReason(ctx, unlinked.ID); got != meetReasonNotLinked {
		t.Errorf("tanpa tautan Google: reason = %q, mau %q", got, meetReasonNotLinked)
	}

	// 2. Gmail tertaut tetapi belum ada izin Calendar (belum ada baris token).
	subject := "sub-stat-" + fmt.Sprint(time.Now().UnixNano())
	if _, err := st.LinkGoogleIdentity(ctx, linked.ID, subject, "stat"+fmt.Sprint(time.Now().UnixNano())+"@example.test", false); err != nil {
		t.Fatalf("tautkan identitas: %v", err)
	}
	if got := srv.meetStatusReason(ctx, linked.ID); got != meetReasonNoCalendarScope {
		t.Errorf("tanpa token: reason = %q, mau %q", got, meetReasonNoCalendarScope)
	}

	// 3. Token ada tetapi tanpa scope calendar.
	if err := st.UpsertGoogleToken(ctx, linked.ID, "refresh", "access",
		time.Now().Add(time.Hour), "openid email", subject, true); err != nil {
		t.Fatalf("simpan token: %v", err)
	}
	if got := srv.meetStatusReason(ctx, linked.ID); got != meetReasonNoCalendarScope {
		t.Errorf("tanpa scope calendar: reason = %q, mau %q", got, meetReasonNoCalendarScope)
	}

	// 4. Refresh token hilang -> perlu tautkan ulang.
	if err := st.UpsertGoogleToken(ctx, linked.ID, "", "access",
		time.Now().Add(time.Hour),
		"https://www.googleapis.com/auth/calendar.events", subject, true); err != nil {
		t.Fatalf("simpan token tanpa refresh: %v", err)
	}
	if got := srv.meetStatusReason(ctx, linked.ID); got != meetReasonTokenExpired {
		t.Errorf("tanpa refresh token: reason = %q, mau %q", got, meetReasonTokenExpired)
	}

	// 5. Lengkap -> ready.
	if err := st.UpsertGoogleToken(ctx, linked.ID, "refresh", "access",
		time.Now().Add(time.Hour),
		"https://www.googleapis.com/auth/calendar.events", subject, true); err != nil {
		t.Fatalf("simpan token lengkap: %v", err)
	}
	if got := srv.meetStatusReason(ctx, linked.ID); got != meetReasonReady {
		t.Errorf("token lengkap: reason = %q, mau %q", got, meetReasonReady)
	}
}

// TestEnsureMeetLinkHandlerConflictWhenNotReady: profesional belum aktif ->
// 409 dengan kode mesin `meet_belum_aktif` (bukan 401 generik), dan pesan
// pasien tidak menyuruh memperbaiki akun Google orang lain.
func TestEnsureMeetLinkHandlerConflictWhenNotReady(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	ctx := context.Background()
	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      "STR-LINK-" + fmt.Sprint(time.Now().UnixNano()),
		SIPNumber:      "SIP-LINK-" + fmt.Sprint(time.Now().UnixNano()),
	})
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	t.Cleanup(func() { cleanupTestUsers(t, db, prof.ID, patient.ID) })

	session, err := st.CreateCareSession(ctx, store.CareSession{
		PatientID:        patient.ID,
		ProfessionalID:   prof.ID,
		SessionType:      "video",
		ScheduledAt:      clock.Now().Add(72 * time.Hour),
		DurationMinutes:  60,
		Status:           "scheduled",
		AllowPendingMeet: true,
	})
	if err != nil {
		t.Fatalf("buat sesi menunggu link: %v", err)
	}
	t.Cleanup(func() {
		cctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		_, _ = db.ExecContext(cctx, `DELETE FROM care_sessions WHERE id = $1`, session.ID)
	})

	srv := newOnboardingTestServer(db)
	srv.calendar = &fakeMeetCalendar{}

	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/care-sessions/x/meet-link", nil)
	req.SetPathValue("session_id", session.ID)
	srv.ensureMeetLinkHandler(rec, req, auth.Claims{Subject: patient.ID, Role: "patient"})

	if rec.Code != http.StatusConflict {
		t.Fatalf("status = %d, mau %d (body: %s)", rec.Code, http.StatusConflict, rec.Body.String())
	}
	var payload map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("body bukan JSON: %v", err)
	}
	if payload["code"] != meetPendingCode {
		t.Errorf("code = %q, mau %q", payload["code"], meetPendingCode)
	}
	if strings.Contains(strings.ToLower(payload["error"]), "tautkan ulang") {
		t.Errorf("pesan untuk pasien tidak boleh menyuruh menautkan ulang akun profesional: %q", payload["error"])
	}
}
