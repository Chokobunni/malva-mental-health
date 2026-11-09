package store

import (
	"context"
	"malva/backend/internal/clock"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"
)

func TestCareSessionRejectsDurationBelowHour(t *testing.T) {
	for _, duration := range []int{10, 30, 59} {
		_, err := New(nil).CreateCareSession(context.Background(), CareSession{ScheduledAt: clock.Now().Add(time.Hour), DurationMinutes: duration, SessionType: "video"})
		if err == nil || !strings.Contains(err.Error(), "60-180") {
			t.Fatalf("duration %d: expected hour validation, got %v", duration, err)
		}
	}
}

func TestMigration036BackfillsHoursIdempotently(t *testing.T) {
	_, db := openCareRescheduleTestStore(t)
	tx, err := db.BeginTx(context.Background(), nil)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = tx.Rollback() }()
	// Shadow only the duration tables, keeping the migration test isolated.
	for _, query := range []string{
		`CREATE TEMP TABLE care_sessions(duration_minutes integer DEFAULT 30) ON COMMIT DROP`,
		`CREATE TEMP TABLE bookings(duration_minutes integer DEFAULT 30) ON COMMIT DROP`,
		`CREATE TEMP TABLE professional_schedules(slot_duration_minutes integer DEFAULT 30) ON COMMIT DROP`,
		`INSERT INTO care_sessions VALUES(30),(45),(90)`, `INSERT INTO bookings VALUES(30),(45),(90)`, `INSERT INTO professional_schedules VALUES(30),(45),(90)`,
	} {
		if _, err := tx.Exec(query); err != nil {
			t.Fatal(err)
		}
	}
	raw, err := os.ReadFile("../../migrations/036_session_hour_backfill.sql")
	if err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ {
		if _, err := tx.Exec(string(raw)); err != nil {
			t.Fatal(err)
		}
	}
	for _, table := range []string{"care_sessions", "bookings", "professional_schedules"} {
		column := "duration_minutes"
		if table == "professional_schedules" {
			column = "slot_duration_minutes"
		}
		var total int
		if err := tx.QueryRow("SELECT sum(" + column + ") FROM " + table).Scan(&total); err != nil {
			t.Fatal(err)
		}
		if total != 210 {
			t.Fatalf("%s duration sum=%d want210", table, total)
		}
		if _, err := tx.Exec("INSERT INTO " + table + " DEFAULT VALUES"); err != nil {
			t.Fatal(err)
		}
		if err := tx.QueryRow("SELECT sum(" + column + ") FROM " + table).Scan(&total); err != nil {
			t.Fatal(err)
		}
		if total != 270 {
			t.Fatalf("%s default not60, total=%d", table, total)
		}
	}
}

func TestAvailabilityRejectsWindowShorterThanHour(t *testing.T) {
	s, db := openCareRescheduleTestStore(t)
	ctx := context.Background()
	prof := insertTestUser(t, db, ctx, "professional", "Short window doctor", "shortwindow")
	t.Cleanup(func() { cleanupTestUsers(t, db, prof) })
	err := s.UpsertSchedules(ctx, prof, []ProfessionalSchedule{{DayOfWeek: 1, StartTime: "09:00", EndTime: "09:30", SlotDurationMinutes: 60, IsActive: true}})
	if err == nil {
		t.Fatal("half-hour availability window accepted")
	}
}

func TestAvailabilityRecognizesPartialSessionOverlap(t *testing.T) {
	s, db := openCareRescheduleTestStore(t)
	ctx := context.Background()
	patient := insertTestUser(t, db, ctx, "patient", "Partial patient", "partialp")
	prof := insertTestUser(t, db, ctx, "professional", "Partial doctor", "partiald")
	t.Cleanup(func() {
		if _, err := db.Exec(`DELETE FROM care_sessions WHERE patient_id=$1`, patient); err != nil {
			t.Errorf("cleanup fixture: %v", err)
		}
		cleanupTestUsers(t, db, patient, prof)
	})
	start := clock.Now().Add(96 * time.Hour).Truncate(time.Minute)
	if _, err := s.CreateCareSession(ctx, CareSession{PatientID: patient, ProfessionalID: prof, SessionType: "chat", ScheduledAt: start, DurationMinutes: 60}); err != nil {
		t.Fatal(err)
	}
	candidate := start.Add(30 * time.Minute)
	if busy, err := s.IsSlotBooked(ctx, prof, candidate); err != nil || !busy {
		t.Errorf("partial slot busy=%v err=%v", busy, err)
	}
	busy, err := s.CountBookedSessions(ctx, prof, []time.Time{candidate, start.Add(time.Hour)})
	if err != nil {
		t.Fatal(err)
	}
	if !busy[strconv.FormatInt(candidate.Unix(), 10)] || busy[strconv.FormatInt(start.Add(time.Hour).Unix(), 10)] {
		t.Fatalf("partial overlap availability: %v", busy)
	}
}

func TestRescheduleSynchronizesBookingAndRejectsOverlap(t *testing.T) {
	s, db := openCareRescheduleTestStore(t)
	ctx := context.Background()
	patient := insertTestUser(t, db, ctx, "patient", "Hour patient", "hourpat")
	prof := insertTestUser(t, db, ctx, "professional", "Hour doctor", "hourpro")
	t.Cleanup(func() {
		if _, err := db.Exec(`DELETE FROM care_sessions WHERE patient_id=$1`, patient); err != nil {
			t.Errorf("cleanup fixture: %v", err)
		}
		cleanupTestUsers(t, db, patient, prof)
	})
	start := clock.Now().Add(96 * time.Hour).Truncate(time.Minute)
	booking, err := s.CreateBooking(ctx, Booking{PatientID: patient, ProfessionalID: prof, ServiceType: "quick_consult", SessionType: "chat", BookingDate: start.Format("2006-01-02"), SlotTime: start.Format("15:04"), DurationMinutes: 60, Price: 100000})
	if err != nil {
		t.Fatal(err)
	}
	session, err := s.CreateCareSession(ctx, CareSession{PatientID: patient, ProfessionalID: prof, BookingID: &booking.ID, SessionType: "chat", ScheduledAt: start, DurationMinutes: 60})
	if err != nil {
		t.Fatal(err)
	}
	target := start.Add(24 * time.Hour)
	got, err := s.RescheduleCareSession(ctx, session.ID, target)
	if err != nil {
		t.Fatal(err)
	}
	updated, err := s.GetBooking(ctx, booking.ID)
	if err != nil {
		t.Fatal(err)
	}
	if updated.BookingDate != target.Format("2006-01-02") || updated.SlotTime[:5] != target.Format("15:04") || !got.ScheduledAt.Equal(target) {
		t.Errorf("reschedule left stale booking: %+v; session %v", updated, got.ScheduledAt)
	}
	_, err = s.CreateCareSession(ctx, CareSession{PatientID: patient, ProfessionalID: prof, SessionType: "chat", ScheduledAt: target.Add(30 * time.Minute), DurationMinutes: 60})
	if err == nil {
		t.Fatal("overlapping hour session accepted")
	}
	neighbor, err := s.CreateCareSession(ctx, CareSession{PatientID: patient, ProfessionalID: prof, SessionType: "chat", ScheduledAt: target.Add(time.Hour), DurationMinutes: 60})
	if err != nil {
		t.Fatal(err)
	}
	if _, err = s.RescheduleCareSession(ctx, session.ID, neighbor.ScheduledAt.Add(30*time.Minute)); err == nil {
		t.Fatal("reschedule overlap accepted")
	}
}

func TestCancelledOneTimeDisconnectsUnlessOtherCareActive(t *testing.T) {
	for _, otherCare := range []bool{false, true} {
		t.Run(map[bool]string{false: "single", true: "other-session"}[otherCare], func(t *testing.T) {
			s, db := openCareRescheduleTestStore(t)
			ctx := context.Background()
			patient := insertTestUser(t, db, ctx, "patient", "Cancel patient", "cancelp")
			prof := insertTestUser(t, db, ctx, "professional", "Cancel doctor", "canceld")
			t.Cleanup(func() {
				if _, err := db.Exec(`DELETE FROM care_sessions WHERE patient_id=$1`, patient); err != nil {
					t.Errorf("cleanup fixture: %v", err)
				}
				cleanupTestUsers(t, db, patient, prof)
			})
			if err := s.EnsurePatientProfessionalLink(ctx, patient, prof); err != nil {
				t.Fatal(err)
			}
			cs, err := s.CreateCareSession(ctx, CareSession{PatientID: patient, ProfessionalID: prof, SessionType: "chat", ScheduledAt: clock.Now().Add(96 * time.Hour), DurationMinutes: 60})
			if err != nil {
				t.Fatal(err)
			}
			if otherCare {
				_, err = s.CreateCareSession(ctx, CareSession{PatientID: patient, ProfessionalID: prof, SessionType: "chat", ScheduledAt: clock.Now().Add(120 * time.Hour), DurationMinutes: 60})
				if err != nil {
					t.Fatal(err)
				}
			}
			if _, err = s.UpdateCareSessionStatus(ctx, cs.ID, "cancelled_by_patient", "", patient); err != nil {
				t.Fatal(err)
			}
			linked, err := s.ProfessionalLinkedToPatient(ctx, prof, patient)
			if err != nil {
				t.Fatal(err)
			}
			if linked != otherCare {
				t.Fatalf("linked=%v want %v", linked, otherCare)
			}
		})
	}
}

func TestMigration038CancelsOnlyUnsupportedOneTimeLinks(t *testing.T) {
	s, db := openCareRescheduleTestStore(t)
	ctx := context.Background()
	raw, err := os.ReadFile("../../migrations/038_cancelled_one_time_links.sql")
	if err != nil {
		t.Fatal(err)
	}
	type scenario struct {
		kind, patient, professional string
		keep                        bool
	}
	var scenarios []scenario
	for _, kind := range []string{"cancelled-only", "manual-only", "other-session", "active-package", "pending-booking"} {
		patient := insertTestUser(t, db, ctx, "patient", "Legacy cancellation", "legacyp")
		prof := insertTestUser(t, db, ctx, "professional", "Legacy cancellation", "legacyd")
		t.Cleanup(func() {
			if _, err := db.Exec(`DELETE FROM care_sessions WHERE patient_id=$1`, patient); err != nil {
				t.Errorf("cleanup fixture: %v", err)
			}
			if _, err := db.Exec(`DELETE FROM care_packages WHERE patient_id=$1`, patient); err != nil {
				t.Errorf("cleanup fixture: %v", err)
			}
			cleanupTestUsers(t, db, patient, prof)
		})
		if err := s.EnsurePatientProfessionalLink(ctx, patient, prof); err != nil {
			t.Fatal(err)
		}
		if kind != "manual-only" {
			if _, err := db.Exec(`INSERT INTO care_sessions(patient_id,professional_id,session_type,scheduled_at,duration_minutes,status) VALUES($1,$2,'chat',$3,60,'cancelled_by_patient')`, patient, prof, clock.Now().Add(96*time.Hour)); err != nil {
				t.Fatal(err)
			}
		}
		switch kind {
		case "other-session":
			if _, err := db.Exec(`INSERT INTO care_sessions(patient_id,professional_id,session_type,scheduled_at,duration_minutes,status) VALUES($1,$2,'chat',$3,60,'scheduled')`, patient, prof, clock.Now().Add(120*time.Hour)); err != nil {
				t.Fatal(err)
			}
		case "active-package":
			if _, err := db.Exec(`INSERT INTO care_packages(patient_id,professional_id,total_sessions,validity_days,price,status,expires_at) VALUES($1,$2,4,42,100000,'active',$3)`, patient, prof, clock.Now().Add(30*24*time.Hour)); err != nil {
				t.Fatal(err)
			}
		case "pending-booking":
			if _, err := s.CreateBooking(ctx, Booking{PatientID: patient, ProfessionalID: prof, ServiceType: "quick_consult", SessionType: "video", BookingDate: clock.Now().Add(96 * time.Hour).Format("2006-01-02"), SlotTime: "10:00", DurationMinutes: 60, Price: 100000}); err != nil {
				t.Fatal(err)
			}
		}
		scenarios = append(scenarios, scenario{kind, patient, prof, kind != "cancelled-only"})
	}
	for iteration := 0; iteration < 2; iteration++ {
		if _, err := db.Exec(string(raw)); err != nil {
			t.Fatal(err)
		}
		for _, tc := range scenarios {
			linked, err := s.ProfessionalLinkedToPatient(ctx, tc.professional, tc.patient)
			if err != nil || linked != tc.keep {
				t.Errorf("%s iteration%d: linked=%v want%v err%v", tc.kind, iteration, linked, tc.keep, err)
			}
		}
	}
}

func TestConcurrentOverlappingReschedulesHaveOneWinner(t *testing.T) {
	s, db := openCareRescheduleTestStore(t)
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	patient := insertTestUser(t, db, ctx, "patient", "Concurrent reschedule", "concurrentp")
	prof := insertTestUser(t, db, ctx, "professional", "Concurrent reschedule", "concurrentd")
	t.Cleanup(func() {
		if _, err := db.Exec(`DELETE FROM care_sessions WHERE patient_id=$1`, patient); err != nil {
			t.Errorf("cleanup fixture: %v", err)
		}
		cleanupTestUsers(t, db, patient, prof)
	})
	initial := clock.Now().Add(96 * time.Hour).Truncate(time.Minute)
	var sessions []CareSession
	for _, offset := range []time.Duration{0, 3 * time.Hour} {
		cs, err := s.CreateCareSession(ctx, CareSession{PatientID: patient, ProfessionalID: prof, SessionType: "chat", ScheduledAt: initial.Add(offset), DurationMinutes: 60})
		if err != nil {
			t.Fatal(err)
		}
		sessions = append(sessions, cs)
	}
	start := make(chan struct{})
	results := make(chan error, 2)
	for i, cs := range sessions {
		go func(i int, cs CareSession) {
			<-start
			_, err := s.RescheduleCareSession(ctx, cs.ID, initial.Add(24*time.Hour+time.Duration(i)*30*time.Minute))
			results <- err
		}(i, cs)
	}
	close(start)
	successes := 0
	for i := 0; i < 2; i++ {
		err := <-results
		if err == nil {
			successes++
		} else if !strings.Contains(err.Error(), "slot sudah terisi") {
			t.Fatalf("unexpected conflict: %v", err)
		}
	}
	if successes != 1 {
		t.Fatalf("concurrent overlap winners=%d want1", successes)
	}
}

func TestProfessionalAbsenceDisconnectsOneTimeCare(t *testing.T) {
	s, db := openCareRescheduleTestStore(t)
	ctx := context.Background()
	patient := insertTestUser(t, db, ctx, "patient", "Absent consultation", "absentp")
	prof := insertTestUser(t, db, ctx, "professional", "Absent consultation", "absentd")
	t.Cleanup(func() {
		if _, err := db.Exec(`DELETE FROM care_sessions WHERE patient_id=$1`, patient); err != nil {
			t.Errorf("cleanup fixture: %v", err)
		}
		cleanupTestUsers(t, db, patient, prof)
	})
	if err := s.EnsurePatientProfessionalLink(ctx, patient, prof); err != nil {
		t.Fatal(err)
	}
	cs, err := s.CreateCareSession(ctx, CareSession{PatientID: patient, ProfessionalID: prof, SessionType: "chat", ScheduledAt: clock.Now().Add(5 * time.Minute), DurationMinutes: 60})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := s.MarkCareSessionAttendance(ctx, cs.ID, "professional", prof, "absent"); err != nil {
		t.Fatal(err)
	}
	linked, err := s.ProfessionalLinkedToPatient(ctx, prof, patient)
	if err != nil || linked {
		t.Fatalf("absent professional remains linked=%v err=%v", linked, err)
	}
}
