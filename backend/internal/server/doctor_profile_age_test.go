package server

import (
	"encoding/json"
	"testing"
	"time"

	"malva/backend/internal/clock"
)

func TestProfessionalAgeUsesCalendarBirthday(t *testing.T) {
	today := time.Date(2026, time.November, 24, 0, 0, 0, 0, clock.Location())
	for _, tc := range []struct {
		birth string
		age   int
		ok    bool
	}{
		{"1986-11-24", 40, true},
		{"1986-11-25", 39, true},
		{"2026-11-25", 0, false},
		{"1986-02-30", 0, false},
	} {
		if age, ok := professionalAge(tc.birth, today); age != tc.age || ok != tc.ok {
			t.Errorf("professionalAge(%q) = %d, %v; want %d, %v", tc.birth, age, ok, tc.age, tc.ok)
		}
	}
}

func TestPublicDoctorProfileReturnsAgeWithoutBirthDate(t *testing.T) {
	f := newTherapyConsentFixture(t)
	if _, err := f.db.Exec("UPDATE professional_credentials SET verification_status='VERIFIED' WHERE user_id=$1", f.prof.ID); err != nil {
		t.Fatal(err)
	}
	load := func() map[string]json.RawMessage {
		t.Helper()
		rec := doAuthed(t, f.srv.Routes(), "GET", "/v1/doctors/"+f.prof.ID, "", "")
		if rec.Code != 200 {
			t.Fatalf("profile returned %d: %s", rec.Code, rec.Body.String())
		}
		var result map[string]json.RawMessage
		if err := json.Unmarshal(rec.Body.Bytes(), &result); err != nil {
			t.Fatal(err)
		}
		return result
	}
	if _, present := load()["age_years"]; present {
		t.Fatal("age must be omitted when no birth date was provided")
	}
	if _, err := f.db.Exec("UPDATE users SET date_of_birth=$2::date WHERE id=$1",
		f.prof.ID, clock.Now().AddDate(-40, 0, -1).Format("2006-01-02")); err != nil {
		t.Fatal(err)
	}
	got := load()
	if string(got["age_years"]) != "40" {
		t.Fatalf("expected derived age 40, got %q", got["age_years"])
	}
	if _, present := got["date_of_birth"]; present {
		t.Fatal("public profile exposed the date of birth")
	}
}
