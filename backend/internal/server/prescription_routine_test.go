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
