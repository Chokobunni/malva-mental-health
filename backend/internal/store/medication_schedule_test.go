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
