package store

import (
	"encoding/json"
	"testing"
)

func TestMedicationScheduleValidation(t *testing.T) {
	valid := map[string]any{"times": []string{"08:00", "20:00"}, "weekdays": []int{1, 2, 3, 4, 5, 6, 7}, "start_at": "2026-11-10T08:00:00+07:00", "units_per_dose": 2, "refill_enabled": true}
	for _, tc := range []struct {
		name, key string
		value     any
	}{
		{"zero dose", "units_per_dose", 0}, {"invalid time", "times", []string{"24:00"}}, {"non canonical time", "times", []string{" 8:00"}}, {"duplicate times", "times", []string{"08:00", "08:00"}}, {"empty weekdays", "weekdays", []int{}}, {"invalid weekday", "weekdays", []int{8}}, {"other zone", "start_at", "2026-11-10T08:00:00+08:00"}, {"conflicting interval", "interval_hours", -1}, {"invalid refill flag", "refill_enabled", "yes"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			copy := map[string]any{}
			for k, v := range valid {
				copy[k] = v
			}
			copy[tc.key] = tc.value
			raw, _ := json.Marshal(copy)
			if ValidateMedicationSchedule(raw) == nil {
				t.Fatalf("invalid %s accepted", tc.key)
			}
		})
	}
	raw, _ := json.Marshal(valid)
	if err := ValidateMedicationSchedule(raw); err != nil {
		t.Fatal(err)
	}
	for _, legacy := range []json.RawMessage{nil, json.RawMessage(`{}`)} {
		if err := ValidateMedicationSchedule(legacy); err != nil {
			t.Fatal(err)
		}
	}
}

func TestMedicationScheduleFlexibleRequiresExplicitEmptyTimesWithoutIntervals(t *testing.T) {
	valid := map[string]any{"times": []string{}, "weekdays": []int{1, 2, 3, 4, 5, 6, 7}, "start_at": "2026-11-10T00:00:00+07:00", "interval_hours": 0, "interval_days": 0, "units_per_dose": 2, "refill_enabled": true}
	for _, enabled := range []bool{true, false} {
		valid["refill_enabled"] = enabled
		raw, err := json.Marshal(valid)
		if err != nil {
			t.Fatal(err)
		}
		if err := ValidateMedicationSchedule(raw); err != nil {
			t.Errorf("explicit flexible routine with refill=%v rejected: %v", enabled, err)
		}
	}
	for _, tc := range []struct {
		name, key string
		value     any
	}{
		{"missing times", "times", nil},
		{"null times", "times", nil},
		{"hours need times", "interval_hours", 8},
		{"days need times", "interval_days", 2},
		{"months need times", "interval_months", 1},
		{"invalid dose", "units_per_dose", 0},
		{"missing weekdays", "weekdays", nil},
		{"invalid weekday", "weekdays", []int{8}},
		{"duplicate weekday", "weekdays", []int{1, 1}},
		{"invalid date", "start_at", "2026-02-30T00:00:00+07:00"},
		{"other timezone", "start_at", "2026-11-10T00:00:00+08:00"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			input := map[string]any{}
			for key, value := range valid {
				input[key] = value
			}
			input[tc.key] = tc.value
			if tc.name == "missing times" {
				delete(input, "times")
			}
			raw, err := json.Marshal(input)
			if err != nil {
				t.Fatal(err)
			}
			if err := ValidateMedicationSchedule(raw); err == nil {
				t.Fatal("malformed flexible routine accepted")
			}
		})
	}
}

func TestMedicationScheduleMonthlyIntervalValidation(t *testing.T) {
	valid := map[string]any{"times": []string{"09:00"}, "weekdays": []int{1, 2, 3, 4, 5, 6, 7}, "start_at": "2027-01-31T09:00:00+07:00", "interval_hours": 0, "interval_days": 0, "interval_months": 1, "units_per_dose": 1, "refill_enabled": true}
	for _, months := range []int{0, 1, 12} {
		valid["interval_months"] = months
		raw, err := json.Marshal(valid)
		if err != nil {
			t.Fatal(err)
		}
		if err := ValidateMedicationSchedule(raw); err != nil {
			t.Errorf("valid interval_months=%d rejected: %v", months, err)
		}
	}
	valid["interval_months"] = 1
	for _, tc := range []struct {
		name, key string
		value     any
	}{
		{"negative month interval", "interval_months", -1},
		{"month interval above year", "interval_months", 13},
		{"string month interval", "interval_months", "1"},
		{"null month interval", "interval_months", nil},
		{"fractional month interval", "interval_months", 1.5},
		{"month and hours conflict", "interval_hours", 8},
		{"month and days conflict", "interval_days", 30},
		{"monthly needs times", "times", []string{}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			input := map[string]any{}
			for key, value := range valid {
				input[key] = value
			}
			input[tc.key] = tc.value
			raw, err := json.Marshal(input)
			if err != nil {
				t.Fatal(err)
			}
			if err := ValidateMedicationSchedule(raw); err == nil {
				t.Fatal("invalid monthly routine accepted")
			}
		})
	}
	delete(valid, "interval_months")
	raw, err := json.Marshal(valid)
	if err != nil {
		t.Fatal(err)
	}
	if err := ValidateMedicationSchedule(raw); err != nil {
		t.Fatalf("legacy routine without months rejected: %v", err)
	}
}
