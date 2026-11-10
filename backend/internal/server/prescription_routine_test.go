package server

import (
	"context"
	"encoding/json"
	"malva/backend/internal/store"
	"testing"
)

func TestPrescriptionItemPreservesRoutineAndStock(t *testing.T) {
	var items []eRxItemRequest
	if err := json.Unmarshal([]byte(`[{"name":"Aripiprazole","dosage":"10 mg","form":"Tablet","unit":"mg","current_stock":30,"alert_below":3,"days":30,"units_per_day":4,"schedule":{"times":["08:00","20:00"],"weekdays":[1,2,3,4,5],"start_at":"2026-11-10T08:00:00+07:00","units_per_dose":2,"refill_enabled":true}}]`), &items); err != nil {
		t.Fatal(err)
	}
	out := rxItemsFromRequest(items)
	b, _ := json.Marshal(out[0])
	var got map[string]any
	_ = json.Unmarshal(b, &got)
	if got["form"] != "Tablet" || got["unit"] != "mg" || got["current_stock"] != float64(30) || got["alert_below"] != float64(3) {
		t.Fatalf("discarded drug fields: %s", b)
	}
	schedule, ok := got["schedule"].(map[string]any)
	if !ok || schedule["units_per_dose"] != float64(2) || len(schedule["times"].([]any)) != 2 {
		t.Fatalf("discarded routine: %s", b)
	}
}

func TestPrescriptionRoutineReachesPatientAndConsumesConfiguredUnits(t *testing.T) {
	f := newClinicalFixture(t)
	body := map[string]any{"patient_id": f.patient.ID, "instructions": "Setelah makan", "items": []any{map[string]any{"name": "Aripiprazole", "dosage": "10 mg", "form": "Tablet", "unit": "mg", "current_stock": 5, "alert_below": 3, "schedule": map[string]any{"times": []string{"08:00", "20:00"}, "weekdays": []int{1, 2, 3, 4, 5, 6, 7}, "start_at": "2026-11-10T08:00:00+07:00", "units_per_dose": 2, "refill_enabled": true}}}}
	out := f.call(t, "POST", "/v1/e-prescriptions", "professional", f.prof.ID, body)
	if out.Code != 201 {
		t.Fatalf("issue %d %s", out.Code, out.Body)
	}
	var created struct {
		Prescription store.EPrescription `json:"prescription"`
	}
	if err := json.Unmarshal(out.Body.Bytes(), &created); err != nil {
		t.Fatal(err)
	}
	rx, err := f.st.GetEPrescription(context.Background(), created.Prescription.ID)
	if err != nil {
		t.Fatal(err)
	}
	if len(rx.Items) != 1 || rx.Items[0].MedicationID == nil || rx.Items[0].CurrentStock != 5 || rx.Items[0].Form != "Tablet" {
		t.Fatalf("rx lost fields %+v", rx.Items)
	}
	meds, err := f.st.ListMedications(context.Background(), f.patient.ID, 50)
	if err != nil || len(meds) != 1 {
		t.Fatalf("patient meds %+v %v", meds, err)
	}
	med := meds[0]
	if med.ID != *rx.Items[0].MedicationID || med.CurrentStock != 5 || med.AlertBelow != 3 || med.ReminderTime != "08:00" || med.RelationToMeal != "Setelah makan" {
		t.Fatalf("patient medication lost prescription %+v", med)
	}
	var schedule map[string]any
	_ = json.Unmarshal(med.Schedule, &schedule)
	if schedule["units_per_dose"] != float64(2) || len(schedule["times"].([]any)) != 2 {
		t.Fatalf("lost routine %s", med.Schedule)
	}
	for _, status := range []string{"missed", "taken"} {
		out = f.call(t, "POST", "/v1/medication-logs", "patient", f.patient.ID, map[string]any{"medication_id": med.ID, "medication_name": med.Name, "status": status})
		if out.Code != 201 {
			t.Fatalf("log %d %s", out.Code, out.Body)
		}
	}
	meds, err = f.st.ListMedications(context.Background(), f.patient.ID, 50)
	if err != nil || meds[0].CurrentStock != 3 {
		t.Fatalf("expected 5-2 stock3, got %+v %v", meds, err)
	}
	// An invalid routine cannot leave either a signed prescription or patient medication.
	body["items"] = []any{map[string]any{"name": "Invalid", "dosage": "5 mg", "schedule": map[string]any{"times": []string{"29:00"}}}}
	if out = f.call(t, "POST", "/v1/e-prescriptions", "professional", f.prof.ID, body); out.Code != 400 {
		t.Fatalf("bad routine accepted %d %s", out.Code, out.Body)
	}
	var count int
	if err = f.db.QueryRow(`SELECT count(*) FROM medications WHERE patient_id=$1`, f.patient.ID).Scan(&count); err != nil || count != 1 {
		t.Fatalf("invalid routine persisted %d %v", count, err)
	}
}

func TestPrescriptionFlexibleRoutinePreservesEmptyReminderAndStock(t *testing.T) {
	f := newClinicalFixture(t)
	body := prescriptionCRUDPayload(f.patient.ID, 30)
	item := body["items"].([]any)[0].(map[string]any)
	routine := map[string]any{"times": []string{}, "weekdays": []int{1, 2, 3, 4, 5, 6, 7}, "start_at": "2026-11-10T00:00:00+07:00", "interval_hours": 0, "interval_days": 0, "units_per_dose": 2, "refill_enabled": true}
	item["schedule"] = routine
	item["frequency"] = "Fleksibel"
	rx := prescriptionJSON(t, f.call(t, "POST", "/v1/e-prescriptions", "professional", f.prof.ID, body), 201)
	rxID := rx["id"].(string)
	var itemID, medID string
	assertFlexible := func(wantStock int, refill bool) {
		t.Helper()
		out := f.call(t, "GET", "/v1/e-prescriptions/"+rxID, "patient", f.patient.ID, nil)
		patientRx := prescriptionJSON(t, out, 200)
		items := patientRx["items"].([]any)
		if len(items) != 1 {
			t.Fatalf("expected one item, got %+v", items)
		}
		got := items[0].(map[string]any)
		if got["current_stock"] != float64(30) || got["remaining_stock"] != float64(wantStock) || got["alert_below"] != float64(3) {
			t.Fatalf("prescription lost supply/remaining/threshold: %+v", got)
		}
		itemID = got["id"].(string)
		medID = got["medication_id"].(string)
		raw := got["schedule"].(map[string]any)
		if times, ok := raw["times"].([]any); !ok || len(times) != 0 || raw["start_at"] != "2026-11-10T00:00:00+07:00" || raw["refill_enabled"] != refill {
			t.Fatalf("flexible prescription manufactured reminder/lost options: %+v", raw)
		}
		meds, err := f.st.ListMedications(context.Background(), f.patient.ID, 50)
		if err != nil || len(meds) != 1 {
			t.Fatalf("patient medicines %+v: %v", meds, err)
		}
		med := meds[0]
		var schedule map[string]any
		if err := json.Unmarshal(med.Schedule, &schedule); err != nil {
			t.Fatal(err)
		}
		if med.ID != medID || med.CurrentStock != wantStock || med.AlertBelow != 3 || med.ReminderTime != "" {
			t.Fatalf("flexible medicine lost identity/stock or invented reminder: %+v", med)
		}
		if times, ok := schedule["times"].([]any); !ok || len(times) != 0 || schedule["units_per_dose"] != float64(2) || schedule["refill_enabled"] != refill {
			t.Fatalf("patient medicine lost flexible routine: %s", med.Schedule)
		}
	}
	assertFlexible(30, true)
	for _, status := range []string{"missed", "taken"} {
		out := f.call(t, "POST", "/v1/medication-logs", "patient", f.patient.ID, map[string]any{"medication_id": medID, "medication_name": "Prescription CRUD", "status": status})
		if out.Code != 201 {
			t.Fatalf("log %s: %d %s", status, out.Code, out.Body)
		}
	}
	assertFlexible(28, true)
	item["id"] = itemID
	item["medication_id"] = medID
	routine["times"] = []string{"08:00"}
	prescriptionJSON(t, f.call(t, "PUT", "/v1/e-prescriptions/"+rxID, "professional", f.prof.ID, body), 200)
	meds, err := f.st.ListMedications(context.Background(), f.patient.ID, 50)
	if err != nil || len(meds) != 1 || meds[0].ReminderTime != "08:00" {
		t.Fatalf("scheduled control reminder missing: %+v %v", meds, err)
	}
	routine["times"] = []string{}
	routine["refill_enabled"] = false
	prescriptionJSON(t, f.call(t, "PUT", "/v1/e-prescriptions/"+rxID, "professional", f.prof.ID, body), 200)
	assertFlexible(28, false)
}

func TestPrescriptionMonthlyInjectionRoundTripAndFlexibleUpdate(t *testing.T) {
	f := newClinicalFixture(t)
	body := prescriptionCRUDPayload(f.patient.ID, 30)
	item := body["items"].([]any)[0].(map[string]any)
	item["form"] = "Injeksi"
	item["frequency"] = "Setiap 1 bulan"
	routine := map[string]any{"times": []string{"09:00"}, "weekdays": []int{1, 2, 3, 4, 5, 6, 7}, "start_at": "2027-01-31T09:00:00+07:00", "interval_hours": 0, "interval_days": 0, "interval_months": 1, "units_per_dose": 1, "refill_enabled": true}
	item["schedule"] = routine
	rx := prescriptionJSON(t, f.call(t, "POST", "/v1/e-prescriptions", "professional", f.prof.ID, body), 201)
	rxID := rx["id"].(string)
	patientRx := prescriptionJSON(t, f.call(t, "GET", "/v1/e-prescriptions/"+rxID, "patient", f.patient.ID, nil), 200)
	got := patientRx["items"].([]any)[0].(map[string]any)
	if got["form"] != "Injeksi" || got["current_stock"] != float64(30) || got["schedule"].(map[string]any)["interval_months"] != float64(1) {
		t.Fatalf("patient prescription lost monthly injection: %+v", got)
	}
	item["id"] = got["id"]
	item["medication_id"] = got["medication_id"]
	medID := got["medication_id"].(string)
	meds, err := f.st.ListMedications(context.Background(), f.patient.ID, 50)
	if err != nil || len(meds) != 1 {
		t.Fatalf("patient medicines: %+v %v", meds, err)
	}
	var saved map[string]any
	if err := json.Unmarshal(meds[0].Schedule, &saved); err != nil {
		t.Fatal(err)
	}
	if meds[0].ID != medID || meds[0].Form != "Injeksi" || meds[0].CurrentStock != 30 || meds[0].AlertBelow != 3 || meds[0].ReminderTime != "09:00" || saved["interval_months"] != float64(1) || saved["start_at"] != "2027-01-31T09:00:00+07:00" {
		t.Fatalf("patient medicine lost monthly details: %+v / %s", meds[0], meds[0].Schedule)
	}
	routine["interval_months"] = 13
	if out := f.call(t, "PUT", "/v1/e-prescriptions/"+rxID, "professional", f.prof.ID, body); out.Code != 400 {
		t.Fatalf("invalid monthly update accepted: %d %s", out.Code, out.Body)
	}
	for _, status := range []string{"missed", "taken"} {
		out := f.call(t, "POST", "/v1/medication-logs", "patient", f.patient.ID, map[string]any{"medication_id": medID, "medication_name": "Prescription CRUD", "status": status})
		if out.Code != 201 {
			t.Fatalf("log %s: %d %s", status, out.Code, out.Body)
		}
	}
	routine["interval_months"] = 0
	routine["times"] = []string{}
	routine["start_at"] = "2027-01-31T00:00:00+07:00"
	item["frequency"] = "Fleksibel"
	prescriptionJSON(t, f.call(t, "PUT", "/v1/e-prescriptions/"+rxID, "professional", f.prof.ID, body), 200)
	meds, err = f.st.ListMedications(context.Background(), f.patient.ID, 50)
	if err != nil || len(meds) != 1 {
		t.Fatalf("patient medicines after flexible update: %+v %v", meds, err)
	}
	if err := json.Unmarshal(meds[0].Schedule, &saved); err != nil {
		t.Fatal(err)
	}
	if meds[0].ID != medID || meds[0].CurrentStock != 29 || meds[0].ReminderTime != "" || saved["interval_months"] != float64(0) || len(saved["times"].([]any)) != 0 {
		t.Fatalf("flexible update retained monthly reminder or reset stock: %+v / %s", meds[0], meds[0].Schedule)
	}
}
