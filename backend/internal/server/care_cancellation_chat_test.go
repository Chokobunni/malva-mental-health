package server

import (
	"encoding/json"
	"testing"
	"time"

	"malva/backend/internal/clock"
	"malva/backend/internal/store"
)

func TestCancelledSessionAppearsInBothChatHistories(t *testing.T) {
	for _, tc := range []struct {
		role    string
		lead    time.Duration
		outcome string
		pack    bool
	}{
		{"patient", 2 * time.Hour, "refund", false},
		{"patient", 30 * time.Minute, "penalty", false},
		{"professional", 30 * time.Minute, "refund", false},
		{"patient", -time.Minute, "penalty", false},
		{"patient", 2 * time.Hour, "credit", true},
		{"patient", 30 * time.Minute, "penalty", true},
		{"professional", 30 * time.Minute, "credit", true},
		{"professional", -time.Minute, "credit", true},
	} {
		t.Run(tc.role+"/"+tc.outcome, func(t *testing.T) {
			f := newClinicalFixture(t)
			t.Cleanup(func() { _, _ = f.db.Exec(`DELETE FROM care_refunds WHERE session_id=$1`, f.sessionID) })
			if _, err := f.db.Exec(`UPDATE care_sessions SET scheduled_at=$2 WHERE id=$1`, f.sessionID, clock.Now().Add(tc.lead)); err != nil {
				t.Fatal(err)
			}
			if tc.pack {
				var id string
				err := f.db.QueryRow(`INSERT INTO care_packages(patient_id,professional_id,price,status,expires_at)
					VALUES($1,$2,600000,'active',$3) RETURNING id`, f.patient.ID, f.prof.ID, clock.Now().Add(24*time.Hour)).Scan(&id)
				if err != nil {
					t.Fatal(err)
				}
				if _, err = f.db.Exec(`UPDATE care_sessions SET package_id=$2 WHERE id=$1`, f.sessionID, id); err != nil {
					t.Fatal(err)
				}
			} else {
				var id string
				err := f.db.QueryRow(`INSERT INTO bookings(patient_id,professional_id,service_type,session_type,booking_date,slot_time,price,status)
					VALUES($1,$2,'quick','chat',$3,'14:00',148000,'paid') RETURNING id`, f.patient.ID, f.prof.ID, clock.Now()).Scan(&id)
				if err != nil {
					t.Fatal(err)
				}
				if _, err = f.db.Exec(`INSERT INTO payments(booking_id,payment_method,gross_amount,platform_fee_amount,net_amount,reference,status)
					VALUES($1,'transfer',148000,0,148000,$2,'paid')`, id, "cancel-test-"+id); err != nil {
					t.Fatal(err)
				}
				if _, err = f.db.Exec(`UPDATE care_sessions SET booking_id=$2 WHERE id=$1`, f.sessionID, id); err != nil {
					t.Fatal(err)
				}
			}
			actor := f.patient.ID
			if tc.role == "professional" {
				actor = f.prof.ID
			}
			patientSocket := clinicalSocket(t, f, f.patient.ID, "patient")
			professionalSocket := clinicalSocket(t, f, f.prof.ID, "professional")
			for range 2 {
				resp := f.call(t, "PATCH", "/v1/care-sessions/"+f.sessionID, tc.role, actor,
					map[string]any{"status": "cancelled_by_" + tc.role, "cancel_reason": "Jadwal berubah"})
				if resp.Code != 200 {
					t.Fatalf("cancellation: %d %s", resp.Code, resp.Body)
				}
			}
			path := "/v1/messages?patient_id=" + f.patient.ID + "&professional_id=" + f.prof.ID
			for _, socket := range []interface{ ReadJSON(any) error }{patientSocket, professionalSocket} {
				for {
					var event struct {
						Type string         `json:"type"`
						Data map[string]any `json:"data"`
					}
					if err := socket.ReadJSON(&event); err != nil {
						t.Fatal(err)
					}
					if event.Type != "chat_message" {
						continue
					}
					if event.Data["kind"] != "session_cancellation" || event.Data["sender_id"] != actor {
						t.Fatalf("unexpected realtime event: %+v", event)
					}
					break
				}
			}
			for role, viewer := range map[string]string{"patient": f.patient.ID, "professional": f.prof.ID} {
				resp := f.call(t, "GET", path, role, viewer, nil)
				var payload struct {
					Messages []store.ChatMessage `json:"messages"`
				}
				if resp.Code != 200 || json.Unmarshal(resp.Body.Bytes(), &payload) != nil || len(payload.Messages) != 1 {
					t.Fatalf("%s history: %d %s", role, resp.Code, resp.Body)
				}
				message := payload.Messages[0]
				var metadata map[string]any
				if message.Kind != "session_cancellation" || message.SenderID != actor ||
					json.Unmarshal(message.Metadata, &metadata) != nil || metadata["outcome"] != tc.outcome || metadata["reason"] != "Jadwal berubah" || metadata["package"] != tc.pack {
					t.Fatalf("unexpected message: %+v, metadata=%v", message, metadata)
				}
				if tc.outcome == "refund" && metadata["refund_amount"] != float64(150000) {
					t.Fatalf("wrong refund amount: %v", metadata)
				}
			}
		})
	}
}
