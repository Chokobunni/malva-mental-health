package server

import (
	"bytes"
	"encoding/json"
	"malva/backend/internal/store"
	"net/http/httptest"
	"testing"
)

func TestScheduleResponsesProtectLegacyClientsAcrossAllReadPaths(t *testing.T) {
	for _, mode := range []string{"monthly", "daily", "flexible"} {
		t.Run(mode, func(t *testing.T) {
			f := newClinicalFixture(t)
			times := []string{"09:00"}
			months := 0
			if mode == "monthly" {
				months = 1
			}
			if mode == "flexible" {
				times = []string{}
			}
			schedule := map[string]any{"times": times, "weekdays": []int{1, 2, 3, 4, 5, 6, 7}, "start_at": "2027-01-31T09:00:00+07:00", "interval_hours": 0, "interval_days": 0, "interval_months": months, "units_per_dose": 1, "refill_enabled": true}
			decode := func(out *httptest.ResponseRecorder, status int) map[string]any {
				t.Helper()
				if out.Code != status {
					t.Fatalf("status%d want%d: %s", out.Code, status, out.Body)
				}
				var value map[string]any
				if err := json.Unmarshal(out.Body.Bytes(), &value); err != nil {
					t.Fatal(err)
				}
				return value
			}
			assertSchedule := func(path string, value map[string]any) {
				t.Helper()
				s := value["schedule"].(map[string]any)
				gotTimes, ok := s["times"].([]any)
				wantTimes := len(times)
				if mode == "monthly" {
					wantTimes = 0
				}
				if !ok || len(gotTimes) != wantTimes || s["interval_months"] != float64(months) || s["refill_enabled"] != true {
					t.Errorf("%s: unsafe/changed schedule %+v", path, s)
				}
				if mode == "daily" && len(gotTimes) == 1 && gotTimes[0] != "09:00" {
					t.Errorf("%s: changed daily reminder time %+v", path, s)
				}
				if mode == "monthly" {
					actual, ok := s["monthly_times"].([]any)
					if !ok || len(actual) != 1 || actual[0] != "09:00" {
						t.Errorf("%s: lost monthly times %+v", path, s)
					}
					if reminder, exists := value["reminder_time"]; exists && reminder != "" {
						t.Errorf("%s: legacy fallback reminder remains %v", path, reminder)
					}
				} else if _, exists := s["monthly_times"]; exists {
					t.Errorf("%s: projected nonmonthly schedule %+v", path, s)
				}
			}
			rxBody := prescriptionCRUDPayload(f.patient.ID, 30)
			rxItem := rxBody["items"].([]any)[0].(map[string]any)
			rxItem["schedule"] = schedule
			rx := decode(f.call(t, "POST", "/v1/e-prescriptions", "professional", f.prof.ID, rxBody), 201)["prescription"].(map[string]any)
			rxID := rx["id"].(string)
			first := rx["items"].([]any)[0].(map[string]any)
			assertSchedule("Rx POST", first)
			rxItem["id"] = first["id"]
			rxItem["medication_id"] = first["medication_id"]
			get := decode(f.call(t, "GET", "/v1/e-prescriptions/"+rxID, "patient", f.patient.ID, nil), 200)["prescription"].(map[string]any)
			assertSchedule("Rx detail GET", get["items"].([]any)[0].(map[string]any))
			list := decode(f.call(t, "GET", "/v1/e-prescriptions", "patient", f.patient.ID, nil), 200)["prescriptions"].([]any)
			assertSchedule("Rx list GET", list[0].(map[string]any)["items"].([]any)[0].(map[string]any))
			rx = decode(f.call(t, "PUT", "/v1/e-prescriptions/"+rxID, "professional", f.prof.ID, rxBody), 200)["prescription"].(map[string]any)
			assertSchedule("Rx PUT", rx["items"].([]any)[0].(map[string]any))
			public := httptest.NewRecorder()
			f.srv.Routes().ServeHTTP(public, httptest.NewRequest("GET", "/v1/e-prescriptions/verify?token="+rx["qr_token"].(string), nil))
			verified := decode(public, 200)["prescription"].(map[string]any)
			assertSchedule("public QR GET", verified["items"].([]any)[0].(map[string]any))
			medBody := map[string]any{"name": "Compatibility medicine", "dosage": "10 mg", "form": "Tablet", "reminder_time": "09:00", "current_stock": 30, "alert_below": 3, "source": "patient", "schedule": schedule}
			med := decode(f.call(t, "POST", "/v1/medications", "patient", f.patient.ID, medBody), 201)["medication"].(map[string]any)
			assertSchedule("medication POST", med)
			med = decode(f.call(t, "PUT", "/v1/medications/"+med["id"].(string), "patient", f.patient.ID, medBody), 200)["medication"].(map[string]any)
			assertSchedule("medication PUT", med)
			meds := decode(f.call(t, "GET", "/v1/medications", "patient", f.patient.ID, nil), 200)["medications"].([]any)
			for _, m := range meds {
				assertSchedule("medications GET", m.(map[string]any))
			}
			// Projection must never rewrite canonical DB data or audit snapshots.
			for label, query := range map[string]string{
				"medication storage": `SELECT schedule FROM medications WHERE id=$1`,
				"item storage":       `SELECT schedule FROM e_prescription_items WHERE medication_id=$1`,
				"audit before":       `SELECT metadata->'before'->'items'->0->'schedule' FROM audit_logs WHERE entity_id=(SELECT prescription_id FROM e_prescription_items WHERE medication_id=$1) AND action='eprescription.saved' AND metadata->'before' IS NOT NULL ORDER BY created_at DESC LIMIT 1`,
			} {
				var raw []byte
				if err := f.db.QueryRow(query, first["medication_id"]).Scan(&raw); err != nil {
					t.Fatalf("%s: %v", label, err)
				}
				var stored map[string]any
				if err := json.Unmarshal(raw, &stored); err != nil {
					t.Fatal(err)
				}
				if len(stored["times"].([]any)) != len(times) {
					t.Errorf("%s: canonical times changed %s", label, raw)
				}
				if _, exists := stored["monthly_times"]; exists {
					t.Errorf("%s: response-only key persisted %s", label, raw)
				}
			}
		})
	}
}

func TestMonthlyResponseCopiesSharedStoreValues(t *testing.T) {
	raw := json.RawMessage(`{"times":["09:00"],"interval_months":1,"weekdays":[1,2,3,4,5,6,7],"start_at":"2027-01-31T09:00:00+07:00","units_per_dose":1,"refill_enabled":true}`)
	before := append([]byte(nil), raw...)
	meds := []store.Medication{{Schedule: raw, ReminderTime: "09:00"}}
	rx := store.EPrescriptionFull{Items: []store.EPrescriptionItem{{Schedule: raw}}}
	medOut := medicationsForResponse(meds)
	rxOut := prescriptionsForResponse([]store.EPrescriptionFull{rx})
	if !bytes.Equal(raw, before) || !bytes.Equal(meds[0].Schedule, before) || !bytes.Equal(rx.Items[0].Schedule, before) || meds[0].ReminderTime != "09:00" {
		t.Fatal("response projection mutated canonical source values")
	}
	// Even callers mutating returned values must not alter a shared source slice.
	medOut[0].Schedule[0] = '['
	rxOut[0].Items[0].Schedule[0] = '['
	rxOut[0].Items[0].Name = "response copy"
	if !bytes.Equal(raw, before) || rx.Items[0].Name != "" {
		t.Fatal("response shares mutable storage with source")
	}
}
