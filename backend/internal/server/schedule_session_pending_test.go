package server

import (
	"bytes"
	"context"
	"database/sql"
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
// KONTRAK HTTP scheduleSession SAAT GOOGLE PROFESIONAL BELUM SIAP (BUG 2)
//
// Test di berkas ini sengaja memanggil handler HTTP, bukan helper
// prepareScheduledMeet. Bug yang dilaporkan pengguna adalah pasien menerima
// 401 dari endpoint ini, sehingga yang harus dikunci adalah kode status &
// bentuk respons — bukan hanya nilai kembalian helper.
//
// Aturan bisnis:
//   - Kondisi Google milik PROFESIONAL tidak boleh memblokir PASIEN.
//   - Sesi video tetap 201 + meet_pending=true bila link belum bisa dibuat.
//   - Hanya server tanpa konfigurasi Google (ErrMeetUnavailable) yang 501.
// ============================================================

// scheduleFixture menyiapkan profesional + pasien + paket aktif + jadwal
// praktik, lalu mengembalikan server dan slot yang PASTI lolos validasi
// (di dalam jam praktik, >24 jam ke depan, sebelum paket kedaluwarsa).
type scheduleFixture struct {
	srv       *Server
	db        *sql.DB
	patient   store.User
	prof      store.User
	pkg       store.CarePackage
	at        time.Time
	scheduled string
}

func newScheduleFixture(t *testing.T, db *sql.DB, st *store.Store, cal meetCalendar) scheduleFixture {
	t.Helper()
	ctx := context.Background()

	prof := createIdentityTestUser(t, db, st, "professional", &store.ProfessionalCredential{
		Specialization: "Sp.KJ",
		STRNumber:      "STR-SCH-" + fmt.Sprint(time.Now().UnixNano()),
		SIPNumber:      "SIP-SCH-" + fmt.Sprint(time.Now().UnixNano()),
	})
	patient := createIdentityTestUser(t, db, st, "patient", nil)

	// Slot 10:00 WIB, tiga hari ke depan (aman dari aturan lead time 24 jam).
	base := clock.Now().In(wibLoc).AddDate(0, 0, 3)
	at := time.Date(base.Year(), base.Month(), base.Day(), 10, 0, 0, 0, wibLoc)

	if err := st.UpsertSchedules(ctx, prof.ID, []store.ProfessionalSchedule{{
		DayOfWeek:           int(at.Weekday()),
		StartTime:           "09:00",
		EndTime:             "17:00",
		SlotDurationMinutes: 60,
		IsActive:            true,
	}}); err != nil {
		t.Fatalf("simpan jadwal profesional: %v", err)
	}

	pkg, err := st.CreateCarePackage(ctx, store.CarePackage{
		PatientID:      patient.ID,
		ProfessionalID: prof.ID,
		Status:         "active",
		TotalSessions:  4,
		ValidityDays:   42,
		Price:          100000,
		StartsAt:       clock.Now(),
		ExpiresAt:      clock.Now().AddDate(0, 0, 30),
	})
	if err != nil {
		t.Fatalf("buat paket aktif: %v", err)
	}

	// Bersihkan sesi & paket SEBELUM user dihapus oleh cleanupTestUsers
	// (t.Cleanup berjalan LIFO, jadi cleanup ini didaftarkan sesudahnya).
	t.Cleanup(func() {
		cctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
		defer cancel()
		_, _ = db.ExecContext(cctx, `DELETE FROM care_sessions WHERE package_id = $1`, pkg.ID)
		_, _ = db.ExecContext(cctx, `DELETE FROM care_packages WHERE id = $1`, pkg.ID)
		_, _ = db.ExecContext(cctx, `DELETE FROM professional_schedules WHERE professional_id = $1`, prof.ID)
	})

	srv := newOnboardingTestServer(db)
	srv.calendar = cal

	return scheduleFixture{
		srv:       srv,
		db:        db,
		patient:   patient,
		prof:      prof,
		pkg:       pkg,
		at:        at,
		scheduled: at.Format("2006-01-02T15:04"),
	}
}

// schedule performs the HTTP call as the patient (the role that reported
// the bug) and returns the recorder plus the decoded payload.
func (f scheduleFixture) schedule(t *testing.T, sessionType, meetingURL string) (*httptest.ResponseRecorder, map[string]any) {
	t.Helper()
	body, _ := json.Marshal(map[string]any{
		"package_id":   f.pkg.ID,
		"scheduled_at": f.scheduled,
		"session_type": sessionType,
		"meeting_url":  meetingURL,
	})
	rec := httptest.NewRecorder()
	req := httptest.NewRequest(http.MethodPost, "/v1/care-sessions", bytes.NewReader(body))
	f.srv.scheduleSession(rec, req, auth.Claims{Subject: f.patient.ID, Role: "patient"})
	var payload map[string]any
	_ = json.Unmarshal(rec.Body.Bytes(), &payload)
	return rec, payload
}

// TestScheduleSessionVideoPendingWhenGoogleNotReady adalah inti Bug 2:
// profesional belum menautkan Google → pasien TETAP mendapat 201 (bukan 401),
// meet_pending=true, meeting_url kosong, dan baris sesi benar-benar tersimpan.
func TestScheduleSessionVideoPendingWhenGoogleNotReady(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	fake := &fakeMeetCalendar{createEventID: "evt-x", createMeetURL: "https://meet.google.com/x"}
	// Profesional baru tidak punya identitas Google -> googleCalendarReady false.
	f := newScheduleFixture(t, db, st, fake)

	rec, payload := f.schedule(t, "video", "")

	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, mau %d (body: %s)", rec.Code, http.StatusCreated, rec.Body.String())
	}
	if rec.Code == http.StatusUnauthorized {
		t.Fatal("pasien tidak boleh menerima 401 karena akun Google profesional")
	}
	if payload["meet_pending"] != true {
		t.Errorf("meet_pending = %v, mau true (body: %s)", payload["meet_pending"], rec.Body.String())
	}
	session, ok := payload["session"].(map[string]any)
	if !ok {
		t.Fatalf("respons tidak memuat objek session: %s", rec.Body.String())
	}
	// meeting_url memakai omitempty: kunci boleh tidak ada, tetapi tidak boleh
	// berisi URL apa pun saat link belum dibuat.
	if raw, ok := session["meeting_url"]; ok && strings.TrimSpace(fmt.Sprint(raw)) != "" {
		t.Errorf("meeting_url = %v, mau kosong saat menunggu link", raw)
	}
	if fake.createCalls != 0 {
		t.Errorf("Google tidak boleh dipanggil saat profesional belum siap, dapat %d", fake.createCalls)
	}

	// Baris harus benar-benar tersimpan sebagai sesi video tanpa link.
	saved, err := st.GetCareSession(context.Background(), fmt.Sprint(session["id"]))
	if err != nil {
		t.Fatalf("sesi tidak tersimpan: %v", err)
	}
	if saved.SessionType != "video" || strings.TrimSpace(saved.MeetingURL) != "" {
		t.Errorf("baris tersimpan = %+v, mau video tanpa meeting_url", saved)
	}
}

// TestScheduleSessionVideoPendingOnReauth: profesional SIAP tetapi Google
// menolak refresh token (ErrReauthNeeded) → tetap 201 + meet_pending, bukan
// 401/502.
func TestScheduleSessionVideoPendingOnReauth(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	fake := &fakeMeetCalendar{createErr: googlecal.ErrReauthNeeded}
	f := newScheduleFixture(t, db, st, fake)
	linkReadyProfessional(t, st, f.prof.ID)

	rec, payload := f.schedule(t, "video", "")

	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, mau %d (body: %s)", rec.Code, http.StatusCreated, rec.Body.String())
	}
	if payload["meet_pending"] != true {
		t.Errorf("meet_pending = %v, mau true saat Google menolak refresh token", payload["meet_pending"])
	}
	if fake.createCalls != 1 {
		t.Errorf("Google harus dipanggil sekali saat profesional siap, dapat %d", fake.createCalls)
	}
}

// Patient requests always schedule video, including legacy chat input.
func TestPatientScheduleSessionChatInputBecomesVideo(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	fake := &fakeMeetCalendar{createEventID: "evt-y", createMeetURL: "https://meet.google.com/y"}
	f := newScheduleFixture(t, db, st, fake)

	rec, payload := f.schedule(t, "chat", "")

	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, mau %d (body: %s)", rec.Code, http.StatusCreated, rec.Body.String())
	}
	if payload["meet_pending"] != true {
		t.Errorf("meet_pending = %v, mau true untuk sesi video yang menunggu link", payload["meet_pending"])
	}
	if fake.createCalls != 0 {
		t.Errorf("sesi chat tidak boleh memanggil kalender, dapat %d", fake.createCalls)
	}
}

// TestScheduleSessionServerNotConfigured: tanpa integrasi Google di server,
// penjadwalan video adalah kegagalan keras (501) — bukan sesi tanpa link.
func TestScheduleSessionServerNotConfigured(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	f := newScheduleFixture(t, db, st, nil)

	rec, _ := f.schedule(t, "video", "")

	if rec.Code != http.StatusNotImplemented {
		t.Fatalf("status = %d, mau %d (body: %s)", rec.Code, http.StatusNotImplemented, rec.Body.String())
	}
}

// TestScheduleSessionRejectsNonGoogleMeetingURL: aturan lama "link harus
// Google Meet" tidak boleh bocor lewat jalur manual.
func TestScheduleSessionRejectsNonGoogleMeetingURL(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	fake := &fakeMeetCalendar{}
	f := newScheduleFixture(t, db, st, fake)

	rec, _ := f.schedule(t, "video", "https://zoom.us/j/123456789")

	if rec.Code != http.StatusBadRequest {
		t.Fatalf("status = %d, mau %d (body: %s)", rec.Code, http.StatusBadRequest, rec.Body.String())
	}
}

// TestAllowPendingMeetNotSettableFromJSON memastikan pengecualian invarian
// tidak bisa diaktifkan klien lewat body JSON (field bertanda json:"-").
func TestAllowPendingMeetNotSettableFromJSON(t *testing.T) {
	var cs store.CareSession
	if err := json.Unmarshal([]byte(`{"session_type":"video","allow_pending_meet":true}`), &cs); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if cs.AllowPendingMeet {
		t.Fatal("AllowPendingMeet tidak boleh bisa di-set dari JSON klien")
	}
}

// TestScheduleSessionVideoPendingNoErrorForPatient memastikan tidak ada jalur
// yang mengembalikan 401 untuk kegagalan Google yang bukan ErrMeetUnavailable.
func TestScheduleSessionVideoPendingNoErrorForPatient(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	fake := &fakeMeetCalendar{createErr: errors.New("google calendar 500")}
	f := newScheduleFixture(t, db, st, fake)
	linkReadyProfessional(t, st, f.prof.ID)

	rec, payload := f.schedule(t, "video", "")

	if rec.Code != http.StatusCreated {
		t.Fatalf("status = %d, mau %d (body: %s)", rec.Code, http.StatusCreated, rec.Body.String())
	}
	if payload["meet_pending"] != true {
		t.Errorf("meet_pending = %v, mau true saat Google gagal 5xx", payload["meet_pending"])
	}
}
