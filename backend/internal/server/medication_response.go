package server

import (
	"encoding/json"
	"malva/backend/internal/store"
)

// monthlyScheduleForResponse hides dose times from clients that do not understand
// calendar months. Canonical request/storage schedules retain their actual times.
func monthlyScheduleForResponse(raw json.RawMessage) (json.RawMessage, bool) {
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(raw, &fields); err != nil {
		return raw, false
	}
	var months int
	if err := json.Unmarshal(fields["interval_months"], &months); err != nil || months <= 0 {
		return raw, false
	}
	fields["monthly_times"] = fields["times"]
	fields["times"] = json.RawMessage(`[]`)
	projected, err := json.Marshal(fields)
	if err != nil {
		return raw, false
	}
	return projected, true
}

func medicationForResponse(item store.Medication) store.Medication {
	var monthly bool
	item.Schedule, monthly = monthlyScheduleForResponse(item.Schedule)
	if monthly {
		item.ReminderTime = ""
	}
	return item
}

func medicationsForResponse(items []store.Medication) []store.Medication {
	if items == nil {
		return nil
	}
	out := make([]store.Medication, len(items))
	for i, item := range items {
		out[i] = medicationForResponse(item)
	}
	return out
}

func prescriptionForResponse(rx store.EPrescriptionFull) store.EPrescriptionFull {
	if rx.Items != nil {
		items := make([]store.EPrescriptionItem, len(rx.Items))
		copy(items, rx.Items)
		for i := range items {
			items[i].Schedule, _ = monthlyScheduleForResponse(items[i].Schedule)
		}
		rx.Items = items
	}
	return rx
}

func prescriptionsForResponse(items []store.EPrescriptionFull) []store.EPrescriptionFull {
	if items == nil {
		return nil
	}
	out := make([]store.EPrescriptionFull, len(items))
	for i, item := range items {
		out[i] = prescriptionForResponse(item)
	}
	return out
}
