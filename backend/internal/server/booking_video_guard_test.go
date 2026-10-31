package server

import (
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

// verifiedProfessional membuat profesional yang lolos pemeriksaan kredensial
// di createBooking (butuh verification_status = 'VERIFIED').
func verifiedProfessional(t *testing.T, db *sql.DB, st *store.Store) store.User {
	t.Helper()
	suffix := fmt.Sprint(time.Now().UnixNano())
	u := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      "STR-" + suffix,
		SIPNumber:      "SIP-" + suffix,
	})
	if _, err := db.Exec(
		`UPDATE professional_credentials SET verification_status='VERIFIED', verified_at=now() WHERE user_id=$1`,
		u.ID); err != nil {
		t.Fatalf("tandai profesional terverifikasi: %v", err)
	}
	return u
}

// bookingVideoBody menyusun payload booking sesi video untuk [profID].
func bookingVideoBody(profID string) string {
	return fmt.Sprintf(
		`{"professional_id":%q,"service_type":"quick_consult_video","session_type":"video",`+
			`"booking_date":%q,"slot_time":"10:00","duration_minutes":30}`,
		profID, time.Now().Add(72*time.Hour).Format("2006-01-02"))
}

// TestCreateBookingRejectsVideoWhenMeetNotReady membuktikan pasien TIDAK bisa
// memesan (dan membayar) sesi video bila profesional belum bisa membuat link
// Meet — server tanpa konfigurasi Google pada kasus ini.
//
// Tanpa penjagaan ini, pasien membayar lalu aktivasi gagal membuat ruang
// pertemuan, dan uangnya sudah masuk.
func TestCreateBookingRejectsVideoWhenMeetNotReady(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	prof := verifiedProfessional(t, db, st)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	// newOnboardingTestServer membuat Server tanpa calendar (client secret kosong).
	srv := newOnboardingTestServer(db)

	rec := httptest.NewRecorder()
	srv.createBooking(rec,
		httptest.NewRequest(http.MethodPost, "/v1/bookings", strings.NewReader(bookingVideoBody(prof.ID))),
		auth.Claims{Subject: patient.ID, Role: "patient"})

	if rec.Code != http.StatusConflict {
		t.Fatalf("status = %d, mau %d (body: %s)", rec.Code, http.StatusConflict, rec.Body.String())
	}
	var payload map[string]string
	if err := json.Unmarshal(rec.Body.Bytes(), &payload); err != nil {
		t.Fatalf("body bukan JSON: %v (%s)", err, rec.Body.String())
	}
	if payload["code"] != "meet_belum_aktif" {
		t.Fatalf("code = %q, mau \"meet_belum_aktif\" (body: %s)", payload["code"], rec.Body.String())
	}
}

// TestCreateBookingAllowsVideoWhenMeetReady membuktikan penjagaan di atas
// tidak menolak profesional yang SUDAH siap: identitas tertaut, token dengan
// refresh token, dan izin calendar.events.
//
// Request tetap gagal setelah penjagaan (profesional belum mengatur harga),
// jadi yang diperiksa adalah kode `meet_belum_aktif` TIDAK muncul.
func TestCreateBookingAllowsVideoWhenMeetReady(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	ctx := context.Background()
	prof := verifiedProfessional(t, db, st)
	patient := createIdentityTestUser(t, db, st, "patient", nil)

	subject := "sub-siap-" + fmt.Sprint(time.Now().UnixNano())
	if _, err := st.LinkGoogleIdentity(ctx, prof.ID, subject, "siap"+fmt.Sprint(time.Now().UnixNano())+"@example.test", false); err != nil {
		t.Fatalf("tautkan identitas: %v", err)
	}
	if err := st.UpsertGoogleToken(ctx, prof.ID, "refresh-token", "access-token",
		time.Now().Add(time.Hour),
		"https://www.googleapis.com/auth/calendar.events", subject); err != nil {
		t.Fatalf("simpan token: %v", err)
	}

	srv := newOnboardingTestServer(db)
	srv.calendar = &fakeMeetCalendar{}

	rec := httptest.NewRecorder()
	srv.createBooking(rec,
		httptest.NewRequest(http.MethodPost, "/v1/bookings", strings.NewReader(bookingVideoBody(prof.ID))),
		auth.Claims{Subject: patient.ID, Role: "patient"})

	var payload map[string]string
	_ = json.Unmarshal(rec.Body.Bytes(), &payload)
	if payload["code"] == "meet_belum_aktif" {
		t.Fatalf("profesional yang sudah siap tidak boleh ditolak: %d %s", rec.Code, rec.Body.String())
	}
}
