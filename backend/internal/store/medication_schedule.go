package store

import (
	"encoding/json"
	"errors"
	"fmt"
	"malva/backend/internal/clock"
	"time"
)

// ValidateMedicationSchedule keeps legacy daily reminders compatible while rejecting malformed clinical routines.
func ValidateMedicationSchedule(raw json.RawMessage) error {
	if len(raw) == 0 || string(raw) == "{}" {
		return nil
	}
	var v struct {
		Times         []string `json:"times"`
		Weekdays      []int    `json:"weekdays"`
		StartAt       string   `json:"start_at"`
		IntervalHours int      `json:"interval_hours"`
		IntervalDays  int      `json:"interval_days"`
		UnitsPerDose  int      `json:"units_per_dose"`
		RefillEnabled bool     `json:"refill_enabled"`
	}
	if err := json.Unmarshal(raw, &v); err != nil {
		return errors.New("jadwal obat tidak valid")
	}
	if len(v.Times) < 1 || len(v.Times) > 10 || len(v.Weekdays) < 1 || v.UnitsPerDose < 1 || v.UnitsPerDose > 1000 || v.IntervalHours < 0 || v.IntervalHours > 168 || v.IntervalDays < 0 || v.IntervalDays > 365 || (v.IntervalHours > 0 && v.IntervalDays > 0) {
		return errors.New("jadwal, hari, dan jumlah per dosis wajib valid")
	}
	seen := map[string]bool{}
	for _, t := range v.Times {
		var h, m int
		if _, err := fmt.Sscanf(t, "%02d:%02d", &h, &m); err != nil || h < 0 || h > 23 || m < 0 || m > 59 || fmt.Sprintf("%02d:%02d", h, m) != t || seen[t] {
			return errors.New("jam obat tidak valid atau berulang")
		}
		seen[t] = true
	}
	days := map[int]bool{}
	for _, d := range v.Weekdays {
		if d < 1 || d > 7 || days[d] {
			return errors.New("hari obat tidak valid")
		}
		days[d] = true
	}
	t, err := time.ParseInLocation(time.RFC3339, v.StartAt, clock.Location())
	if err != nil {
		return errors.New("tanggal mulai obat tidak valid")
	}
	_, offset := t.Zone()
	if offset != 7*3600 {
		return errors.New("tanggal mulai obat wajib WIB")
	}

	weekday := int(t.Weekday())
	if weekday == 0 {
		weekday = 7
	}
	if (v.IntervalHours == 168 || (v.IntervalDays > 0 && v.IntervalDays%7 == 0)) && !days[weekday] {
		return errors.New("hari terpilih tidak sesuai tanggal mulai dan interval obat")
	}
	return nil
}
