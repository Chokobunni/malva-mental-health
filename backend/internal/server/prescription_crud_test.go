package server

import (
	"context"
	"database/sql"
	"encoding/json"
	"fmt"
	"malva/backend/internal/store"
	"net/http/httptest"
	"os"
	"testing"
	"time"
)

func prescriptionCRUDPayload(patient string, qty int) map[string]any {
	return map[string]any{"patient_id": patient, "status": "issued", "diagnosis": "F41.1", "notes": "Follow-up", "instructions": "After meal", "items": []any{map[string]any{"name": "Prescription CRUD", "dosage": "10 mg", "form": "Tablet", "unit": "mg", "current_stock": qty, "alert_below": 3, "schedule": map[string]any{"times": []string{"08:00"}, "weekdays": []int{1, 2, 3, 4, 5, 6, 7}, "start_at": "2026-11-10T08:00:00+07:00", "units_per_dose": 1, "refill_enabled": true, "relation_to_meal": "Sesudah makan", "instructions": "Minum air"}}}}
}
func prescriptionJSON(t *testing.T, out *httptest.ResponseRecorder, code int) map[string]any {
	t.Helper()
	if out.Code != code {
		t.Fatalf("status%d want%d: %s", out.Code, code, out.Body)
	}
	var p struct {
		Prescription map[string]any `json:"prescription"`
	}
	if err := json.Unmarshal(out.Body.Bytes(), &p); err != nil {
		t.Fatal(err)
	}
	return p.Prescription
}

func TestPrescriptionReadNeverMixesIssuedHeaderWithDraftItems(t *testing.T) {
	for _, mode := range []string{"detail", "list", "qr"} {
		t.Run(mode, func(t *testing.T) {
			f := newClinicalFixture(t)
			rx := prescriptionJSON(t, f.call(t, "POST", "/v1/e-prescriptions", "professional", f.prof.ID, prescriptionCRUDPayload(f.patient.ID, 30)), 201)
			ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
			defer cancel()
			readerDB, err := sql.Open("pgx", os.Getenv("MALVA_TEST_DATABASE_URL"))
			if err != nil {
				t.Fatal(err)
			}
			defer func() {
				if err := readerDB.Close(); err != nil {
					t.Errorf("close reader database: %v", err)
				}
			}()
			readerDB.SetMaxOpenConns(1)
			var pid int
			if err := readerDB.QueryRowContext(ctx, `SELECT pg_backend_pid()`).Scan(&pid); err != nil {
				t.Fatal(err)
			}
			reader := store.New(readerDB)
			blocker, err := f.db.BeginTx(ctx, nil)
			if err != nil {
				t.Fatal(err)
			}
			defer func() { _ = blocker.Rollback() }()
			if _, err := blocker.ExecContext(ctx, `LOCK TABLE e_prescription_items IN ACCESS EXCLUSIVE MODE`); err != nil {
				t.Fatal(err)
			}
			type result struct {
				rx  store.EPrescriptionFull
				err error
			}
			finished := make(chan result, 1)
			go func() {
				var out store.EPrescriptionFull
				var readErr error
				switch mode {
				case "list":
					var list []store.EPrescriptionFull
					list, readErr = reader.ListEPrescriptionsForUser(ctx, f.patient.ID, "patient")
					if readErr == nil && len(list) > 0 {
						out = list[0]
					}
				case "qr":
					out, readErr = reader.GetEPrescriptionByQR(ctx, rx["qr_token"].(string))
				default:
					out, readErr = reader.GetEPrescription(ctx, rx["id"].(string))
				}
				finished <- result{out, readErr}
			}()
			// The header has been read once the item SELECT waits on our table lock.
			for {
				var waiting bool
				if err := f.db.QueryRowContext(ctx, `SELECT EXISTS(SELECT 1 FROM pg_stat_activity WHERE pid=$1 AND wait_event_type='Lock')`, pid).Scan(&waiting); err != nil {
					t.Fatal(err)
				}
				if waiting {
					break
				}
				select {
				case <-ctx.Done():
					t.Fatal("reader did not reach item query")
				case <-time.After(5 * time.Millisecond):
				}
			}
			if _, err := blocker.ExecContext(ctx, `UPDATE e_prescriptions SET status='draft',qr_token=qr_token||'-revised' WHERE id=$1`, rx["id"]); err != nil {
				t.Fatal(err)
			}
			if _, err := blocker.ExecContext(ctx, `UPDATE e_prescription_items SET name='Private draft revision' WHERE prescription_id=$1`, rx["id"]); err != nil {
				t.Fatal(err)
			}
			if err := blocker.Commit(); err != nil {
				t.Fatal(err)
			}
			got := <-finished
			if got.err != nil {
				t.Fatal(got.err)
			}
			if got.rx.Status != "issued" || len(got.rx.Items) != 1 || got.rx.Items[0].Name != "Prescription CRUD" {
				t.Fatalf("read mixed revisions: %+v", got.rx)
			}
		})
	}
}
func TestPrescriptionCRUDPreservesConsumptionAndInvalidatesQR(t *testing.T) {
	f := newClinicalFixture(t)
	body := prescriptionCRUDPayload(f.patient.ID, 30)
	rx := prescriptionJSON(t, f.call(t, "POST", "/v1/e-prescriptions", "professional", f.prof.ID, body), 201)
	id := rx["id"].(string)
	originalQR := rx["qr_token"].(string)
	persisted, err := f.st.GetEPrescription(context.Background(), id)
	if err != nil {
		t.Fatal(err)
	}
	item := persisted.Items[0]
	medID := *item.MedicationID
	for i := 0; i < 5; i++ {
		if _, err := f.st.CreateMedicationLog(context.Background(), store.MedicationLog{PatientID: f.patient.ID, MedicationID: medID, MedicationName: item.Name, Status: "taken"}); err != nil {
			t.Fatal(err)
		}
	}
	itemBody := body["items"].([]any)[0].(map[string]any)
	itemBody["id"] = item.ID
	itemBody["medication_id"] = medID
	itemBody["name"] = "Prescription edited"
	body["diagnosis"] = "F41.0"
	rx = prescriptionJSON(t, f.call(t, "PUT", "/v1/e-prescriptions/"+id, "professional", f.prof.ID, body), 200)
	if rx["diagnosis"] != "F41.0" || rx["qr_token"] == originalQR {
		t.Fatalf("update lost diagnosis or QR rotation %+v", rx)
	}
	items := rx["items"].([]any)
	updated := items[0].(map[string]any)
	if updated["id"] != item.ID || updated["medication_id"] != medID || updated["remaining_stock"] != float64(25) {
		t.Fatalf("edit reset identity/consumption %+v", updated)
	}
	itemBody["current_stock"] = 40
	rx = prescriptionJSON(t, f.call(t, "PUT", "/v1/e-prescriptions/"+id, "professional", f.prof.ID, body), 200)
	if rx["items"].([]any)[0].(map[string]any)["remaining_stock"] != float64(35) {
		t.Fatal("supply edit reset consumed stock")
	}
	if out := f.call(t, "GET", "/v1/e-prescriptions/verify?token="+originalQR, "patient", f.patient.ID, nil); out.Code != 404 {
		t.Fatalf("old QR valid%d", out.Code)
	}
	body["status"] = "draft"
	prescriptionJSON(t, f.call(t, "PUT", "/v1/e-prescriptions/"+id, "professional", f.prof.ID, body), 200)
	if meds, err := f.st.ListMedications(context.Background(), f.patient.ID, 50); err != nil || len(meds) != 0 {
		t.Fatalf("draft medication active%+v %v", meds, err)
	}
	if out := f.call(t, "GET", "/v1/e-prescriptions/"+id, "patient", f.patient.ID, nil); out.Code != 404 {
		t.Fatalf("patient saw draft%d", out.Code)
	}
	body["status"] = "issued"
	rx = prescriptionJSON(t, f.call(t, "PUT", "/v1/e-prescriptions/"+id, "professional", f.prof.ID, body), 200)
	if rx["items"].([]any)[0].(map[string]any)["remaining_stock"] != float64(35) {
		t.Fatal("reissue reset consumption")
	}
	if out := f.call(t, "DELETE", "/v1/e-prescriptions/"+id, "professional", f.prof.ID, nil); out.Code != 200 {
		t.Fatalf("delete%d %s", out.Code, out.Body)
	}
	var count int
	if err := f.db.QueryRow(`SELECT count(*) FROM medication_logs WHERE medication_id=$1`, medID).Scan(&count); err != nil || count != 5 {
		t.Fatalf("clinical logs lost%d %v", count, err)
	}
	if meds, err := f.st.ListMedications(context.Background(), f.patient.ID, 50); err != nil || len(meds) != 0 {
		t.Fatalf("deleted meds active%+v %v", meds, err)
	}
	if out := f.call(t, "PUT", "/v1/e-prescriptions/"+id, "professional", f.prof.ID, body); out.Code != 404 {
		t.Fatalf("deleted resurrected%d", out.Code)
	}
}
func TestPrescriptionDraftIsPrivateAndAuthorCRUDOnly(t *testing.T) {
	f := newClinicalFixture(t)
	body := prescriptionCRUDPayload(f.patient.ID, 30)
	body["status"] = "draft"
	rx := prescriptionJSON(t, f.call(t, "POST", "/v1/e-prescriptions", "professional", f.prof.ID, body), 201)
	id := rx["id"].(string)
	if rx["status"] != "draft" {
		t.Fatalf("draft not retained%+v", rx)
	}
	if meds, err := f.st.ListMedications(context.Background(), f.patient.ID, 50); err != nil || len(meds) != 0 {
		t.Fatalf("draft sent meds%+v %v", meds, err)
	}
	for _, method := range []string{"PUT", "DELETE"} {
		if out := f.call(t, method, "/v1/e-prescriptions/"+id, "patient", f.patient.ID, body); out.Code != 403 {
			t.Fatalf("patient%s permitted%d", method, out.Code)
		}
	}
	other := verifiedProfessional(t, f.db, f.st)
	if out := f.call(t, "PUT", "/v1/e-prescriptions/"+id, "professional", other.ID, body); out.Code != 404 {
		t.Fatalf("foreign author edit%d", out.Code)
	}
	if out := f.call(t, "DELETE", "/v1/e-prescriptions/"+id, "professional", other.ID, nil); out.Code != 404 {
		t.Fatalf("foreign author delete%d", out.Code)
	}
}

func TestPrescriptionMultiItemEditsKeepHistoryAndRejectForeignItem(t *testing.T) {
	f := newClinicalFixture(t)
	body := prescriptionCRUDPayload(f.patient.ID, 30)
	second := prescriptionCRUDPayload(f.patient.ID, 20)["items"].([]any)[0].(map[string]any)
	second["name"] = "Second medicine"
	body["items"] = append(body["items"].([]any), second)
	rx := prescriptionJSON(t, f.call(t, "POST", "/v1/e-prescriptions", "professional", f.prof.ID, body), 201)
	id := rx["id"].(string)
	items := rx["items"].([]any)
	removed := items[0].(map[string]any)
	kept := items[1].(map[string]any)
	if out := f.call(t, "POST", "/v1/medication-logs", "patient", f.patient.ID, map[string]any{"medication_id": removed["medication_id"], "medication_name": removed["name"], "status": "taken"}); out.Code != 201 {
		t.Fatal(out.Body)
	}
	replacement := prescriptionCRUDPayload(f.patient.ID, 15)["items"].([]any)[0].(map[string]any)
	replacement["name"] = "Third medicine"
	body["items"] = []any{kept, replacement}
	updated := prescriptionJSON(t, f.call(t, "PUT", "/v1/e-prescriptions/"+id, "professional", f.prof.ID, body), 200)
	if len(updated["items"].([]any)) != 2 {
		t.Fatal("wrong itemcount")
	}
	var active bool
	var count int
	if err := f.db.QueryRow(`SELECT active FROM medications WHERE id=$1`, removed["medication_id"]).Scan(&active); err != nil || active {
		t.Fatalf("removed medicine remainsactive%v %v", active, err)
	}
	if err := f.db.QueryRow(`SELECT count(*) FROM medication_logs WHERE medication_id=$1`, removed["medication_id"]).Scan(&count); err != nil || count != 1 {
		t.Fatalf("removed item lost logs%d %v", count, err)
	}
	// A forged foreign item cannot partially update the first item or rotate QR.
	beforeQR := updated["qr_token"]
	kept["name"] = "Must rollback"
	replacement["id"] = "00112233-4455-6677-8899-aabbccddeeff"
	if out := f.call(t, "PUT", "/v1/e-prescriptions/"+id, "professional", f.prof.ID, body); out.Code != 409 {
		t.Fatalf("forgeditem%d %s", out.Code, out.Body)
	}
	after := prescriptionJSON(t, f.call(t, "GET", "/v1/e-prescriptions/"+id, "professional", f.prof.ID, nil), 200)
	if after["qr_token"] != beforeQR {
		t.Fatal("failed edit rotatedQR")
	}
	for _, item := range after["items"].([]any) {
		if item.(map[string]any)["name"] == "Must rollback" {
			t.Fatal("failed edit partiallysaved")
		}
	}
}
func TestPrescriptionExplicitLegacySupplyAndZeroAreNotInferredFromDays(t *testing.T) {
	f := newClinicalFixture(t)
	for _, qty := range []int{0, 30} {
		body := map[string]any{"patient_id": f.patient.ID, "items": []any{map[string]any{"name": "Legacy explicit", "dosage": "5 mg", "days": 20, "units_per_day": 2, "current_stock": qty}}}
		rx := prescriptionJSON(t, f.call(t, "POST", "/v1/e-prescriptions", "professional", f.prof.ID, body), 201)
		item := rx["items"].([]any)[0].(map[string]any)
		if item["current_stock"] != float64(qty) || item["remaining_stock"] != float64(qty) {
			t.Fatalf("supply%d inferred %+v", qty, item)
		}
	}
}
func TestPrescriptionPatientListsExcludeDraftAndDeleted(t *testing.T) {
	f := newClinicalFixture(t)
	for _, status := range []string{"draft", "issued"} {
		body := prescriptionCRUDPayload(f.patient.ID, 30)
		body["status"] = status
		prescriptionJSON(t, f.call(t, "POST", "/v1/e-prescriptions", "professional", f.prof.ID, body), 201)
	}
	out := f.call(t, "GET", "/v1/e-prescriptions", "patient", f.patient.ID, nil)
	var p struct {
		Prescriptions []store.EPrescriptionFull `json:"prescriptions"`
	}
	if err := json.Unmarshal(out.Body.Bytes(), &p); err != nil {
		t.Fatal(err)
	}
	if len(p.Prescriptions) != 1 || p.Prescriptions[0].Status != "issued" || len(p.Prescriptions[0].Items) != 1 {
		t.Fatalf("patientlist%+v", p)
	}
}

func TestPrescriptionConcurrentDoseAndSupplyEditPreserveBoth(t *testing.T) {
	f := newClinicalFixture(t)
	body := prescriptionCRUDPayload(f.patient.ID, 30)
	rx := prescriptionJSON(t, f.call(t, "POST", "/v1/e-prescriptions", "professional", f.prof.ID, body), 201)
	id := rx["id"].(string)
	item := rx["items"].([]any)[0].(map[string]any)
	medID := item["medication_id"].(string)
	item["current_stock"] = 40
	body["items"] = []any{item}
	start := make(chan struct{})
	results := make(chan error, 11)
	for i := 0; i < 10; i++ {
		go func() {
			<-start
			_, err := f.st.CreateMedicationLog(context.Background(), store.MedicationLog{PatientID: f.patient.ID, MedicationID: medID, MedicationName: "Prescription CRUD", Status: "taken"})
			results <- err
		}()
	}
	go func() {
		<-start
		out := f.call(t, "PUT", "/v1/e-prescriptions/"+id, "professional", f.prof.ID, body)
		if out.Code != 200 {
			results <- fmt.Errorf("update%d %s", out.Code, out.Body)
			return
		}
		results <- nil
	}()
	close(start)
	for i := 0; i < 11; i++ {
		if err := <-results; err != nil {
			t.Fatal(err)
		}
	}
	meds, err := f.st.ListMedications(context.Background(), f.patient.ID, 50)
	if err != nil || len(meds) != 1 || meds[0].CurrentStock != 30 {
		t.Fatalf("concurrent supply/dose=%+v %v", meds, err)
	}
}
