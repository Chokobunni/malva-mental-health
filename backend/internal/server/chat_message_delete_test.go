package server

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"testing"
	"time"

	"malva/backend/internal/clock"
	"malva/backend/internal/store"
)

func TestDeleteChatMessageForEveryone(t *testing.T) {
	f := newClinicalFixture(t)
	const clientID = "c0851fe0-0b7c-42fa-8f64-c1680665986a"
	id := store.ClinicalRetryID("message", f.prof.ID, clientID)
	path := "/v1/messages/" + id
	chatPath := "/v1/messages?patient_id=" + f.patient.ID + "&professional_id=" + f.prof.ID
	body := map[string]any{"recipient_id": f.patient.ID, "kind": "assessment_request", "client_message_id": clientID, "metadata": map[string]string{"session_id": f.sessionID, "module_id": "who5"}}
	if out := f.call(t, http.MethodPost, "/v1/messages", "professional", f.prof.ID, body); out.Code != http.StatusCreated {
		t.Fatalf("initial send failed: %d %s", out.Code, out.Body)
	}
	if out := doAuthed(t, f.srv.Routes(), http.MethodDelete, path, "", ""); out.Code != http.StatusUnauthorized {
		t.Fatalf("anonymous deletion status %d: %s", out.Code, out.Body)
	}
	if out := f.call(t, http.MethodDelete, path, "admin", f.prof.ID, nil); out.Code != http.StatusForbidden {
		t.Fatalf("unsupported role deletion status %d: %s", out.Code, out.Body)
	}
	for _, user := range []struct{ id, role string }{{f.patient.ID, "patient"}, {f.other.ID, "patient"}, {f.prof.ID, "patient"}} {
		if out := f.call(t, http.MethodDelete, path, user.role, user.id, nil); out.Code != http.StatusNotFound {
			t.Fatalf("non-owner or incorrect role deletion status %d: %s", out.Code, out.Body)
		}
	}
	if _, err := f.db.Exec(`UPDATE care_sessions SET scheduled_at=$2 WHERE id=$1`, f.sessionID, clock.Now().Add(-2*time.Hour)); err != nil {
		t.Fatal(err)
	}
	sender := clinicalSocket(t, f, f.prof.ID, "professional")
	receiver := clinicalSocket(t, f, f.patient.ID, "patient")
	if out := f.call(t, http.MethodDelete, path, "professional", f.prof.ID, nil); out.Code != http.StatusNoContent {
		t.Fatalf("sender could not delete outside the session: %d %s", out.Code, out.Body)
	}
	for _, stream := range []interface{ ReadJSON(any) error }{sender, receiver} {
		for {
			var event struct {
				Type string            `json:"type"`
				Data map[string]string `json:"data"`
			}
			var raw json.RawMessage
			if err := stream.ReadJSON(&raw); err != nil {
				t.Fatal(err)
			}
			if err := json.Unmarshal(raw, &event); err != nil || event.Type != "chat_message_deleted" {
				continue
			}
			if event.Data["id"] != id || event.Data["patient_id"] != f.patient.ID || event.Data["professional_id"] != f.prof.ID || len(event.Data) != 3 {
				t.Fatalf("unexpected scoped event: %s", raw)
			}
			break
		}
	}
	if out := f.call(t, http.MethodDelete, path, "professional", f.prof.ID, nil); out.Code != http.StatusNoContent {
		t.Fatalf("delete retry status %d: %s", out.Code, out.Body)
	}
	if _, err := f.db.Exec(`UPDATE care_sessions SET scheduled_at=$2 WHERE id=$1`, f.sessionID, clock.Now().Add(-time.Minute)); err != nil {
		t.Fatal(err)
	}
	if out := f.call(t, http.MethodPost, "/v1/messages", "professional", f.prof.ID, body); out.Code < 400 {
		t.Fatalf("send retry returned deleted content: %d %s", out.Code, out.Body)
	}
	for _, user := range []struct{ id, role string }{{f.patient.ID, "patient"}, {f.prof.ID, "professional"}} {
		out := f.call(t, http.MethodGet, chatPath, user.role, user.id, nil)
		var history struct{ Messages []store.ChatMessage }
		if err := json.Unmarshal(out.Body.Bytes(), &history); err != nil || out.Code != http.StatusOK || len(history.Messages) != 0 {
			t.Fatalf("deleted card remains in history: %d %s", out.Code, out.Body)
		}
	}
	var wiped bool
	if err := f.db.QueryRow(`SELECT text='' AND sender_name='' AND attachment_meta IS NULL AND deleted_at IS NOT NULL FROM chat_messages WHERE id=$1`, id).Scan(&wiped); err != nil || !wiped {
		t.Fatalf("message tombstone retains content: wiped=%v err=%v", wiped, err)
	}
}

func TestPatientChatDeletionWinsConcurrentSendRetry(t *testing.T) {
	f := newClinicalFixture(t)
	message := store.ChatMessage{
		ID: generateChatMessageID(), PatientID: f.patient.ID, ProfessionalID: f.prof.ID,
		SenderID: f.patient.ID, Kind: "text", Text: "Synthetic message",
	}
	if _, err := f.st.CreateChatMessage(t.Context(), message); err != nil {
		t.Fatal(err)
	}
	retried := make(chan error, 1)
	go func() {
		_, err := f.st.CreateChatMessage(t.Context(), message)
		retried <- err
	}()
	out := f.call(t, http.MethodDelete, "/v1/messages/"+message.ID, "patient", f.patient.ID, nil)
	if out.Code != http.StatusNoContent {
		t.Fatalf("patient delete status %d: %s", out.Code, out.Body)
	}
	// A retry may complete before the delete, or be rejected afterwards.
	err := <-retried
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		t.Fatal(err)
	}
	messages, err := f.st.ListChatMessages(t.Context(), f.patient.ID, f.prof.ID, 100)
	if err != nil || len(messages) != 0 {
		t.Fatalf("delete and retry left visible messages: count=%d err=%v", len(messages), err)
	}
}
