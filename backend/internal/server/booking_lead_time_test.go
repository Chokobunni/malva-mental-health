package server

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
)

func TestPatientBookingLeadTime(t *testing.T) {
	now := time.Date(2026, 11, 28, 10, 0, 0, 0, wibLoc)
	for _, tc := range []struct {
		name  string
		start time.Time
		want  bool
	}{
		{"past", now.Add(-time.Minute), false},
		{"inside two hours", now.Add(2*time.Hour - time.Nanosecond), false},
		{"exactly two hours", now.Add(2 * time.Hour), true},
		{"same day later", now.Add(3 * time.Hour), true},
		{"tomorrow", now.AddDate(0, 0, 1), true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := patientBookingStartAllowed(tc.start, now); got != tc.want {
				t.Fatalf("allowed=%v want=%v", got, tc.want)
			}
		})
	}
}

func TestAvailabilityMatchesTwoHourSlotsAcrossServices(t *testing.T) {
	db, st := openOnboardingTestStore(t)
	prof := createIdentityTestUser(t, db, st, "professional", nil)
	for _, category := range []string{"quick_chat", "quick_video", "package"} {
		for weekday := 0; weekday < 7; weekday++ {
			if _, err := db.ExecContext(context.Background(), `INSERT INTO professional_schedules
			(professional_id, service_category, day_of_week, start_time, end_time, slot_duration_minutes, is_active)
			VALUES ($1,$2,$3,'00:00','23:00',60,true)`, prof.ID, category, weekday); err != nil {
				t.Fatal(err)
			}
		}
	}
	srv := &Server{store: st}
	for _, category := range []string{"quick_chat", "quick_video", "package"} {
		t.Run(category, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/?service_category="+category, nil)
			req.SetPathValue("user_id", prof.ID)
			rr := httptest.NewRecorder()
			srv.getDoctorAvailability(rr, req, auth.Claims{})
			if rr.Code != 200 || rr.Header().Get("Cache-Control") != "private, no-store" {
				t.Fatalf("availability: %d %s", rr.Code, rr.Body.String())
			}
			var availability struct {
				Days []struct {
					Date string `json:"date"`
					Free int    `json:"free_slots"`
				} `json:"days"`
			}
			if err := json.Unmarshal(rr.Body.Bytes(), &availability); err != nil {
				t.Fatal(err)
			}
			for _, day := range availability.Days[:2] {
				req := httptest.NewRequest(http.MethodGet, "/?service_category="+category+"&date="+day.Date, nil)
				req.SetPathValue("user_id", prof.ID)
				rr := httptest.NewRecorder()
				before := clock.Now()
				srv.getDoctorAvailableSlots(rr, req, auth.Claims{})
				if rr.Code != 200 || rr.Header().Get("Cache-Control") != "private, no-store" {
					t.Fatalf("slots: %d %s", rr.Code, rr.Body.String())
				}
				var response struct {
					Slots []struct {
						Time      string `json:"time"`
						Available bool   `json:"available"`
					} `json:"slots"`
				}
				if err := json.Unmarshal(rr.Body.Bytes(), &response); err != nil {
					t.Fatal(err)
				}
				free := 0
				for _, slot := range response.Slots {
					at, err := time.ParseInLocation("2006-01-02 15:04", day.Date+" "+slot.Time, wibLoc)
					if err != nil {
						t.Fatal(err)
					}
					if slot.Available {
						free++
						if !patientBookingStartAllowed(at, before) {
							t.Fatalf("too-soon slot %s", slot.Time)
						}
						if err := srv.validateSlotFor(context.Background(), prof.ID, category, at, 60, true); err != nil {
							t.Fatalf("advertised slot rejected: %v", err)
						}
					}
				}
				if free != day.Free {
					t.Fatalf("%s slots=%d availability=%d", day.Date, free, day.Free)
				}
			}
			tooSoon := clock.Now().Add(119 * time.Minute)
			if err := srv.validateSlotFor(context.Background(), prof.ID, category, tooSoon, 60, true); err == nil || err.Error() != "booking minimal 2 jam sebelum sesi" {
				t.Fatalf("short lead time accepted: %v", err)
			}
		})
	}
}
