package server

import (
	"context"
	"encoding/json"
	"errors"
	"net"
	"os"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"malva/backend/internal/realtime"
	"malva/backend/internal/store"
)

func readPeerPresence(t *testing.T, conn *websocket.Conn, peerID string) bool {
	t.Helper()
	_ = conn.SetReadDeadline(time.Now().Add(2 * time.Second))
	for {
		var event struct {
			Type string `json:"type"`
			Data struct {
				UserID string `json:"user_id"`
				Online bool   `json:"online"`
			} `json:"data"`
		}
		if err := conn.ReadJSON(&event); err != nil {
			t.Fatalf("missing authoritative presence for linked peer: %v", err)
		}
		if event.Type == "presence" && event.Data.UserID == peerID {
			return event.Data.Online
		}
	}
}

func TestChatPresenceInitialSnapshotAndBothParticipants(t *testing.T) {
	f := clinicalFixture{therapyConsentFixture: newTherapyConsentFixture(t)}
	patient := clinicalSocket(t, f, f.patient.ID, "patient")
	if readPeerPresence(t, patient, f.prof.ID) {
		t.Fatal("offline professional was announced online")
	}
	professional := clinicalSocket(t, f, f.prof.ID, "professional")
	if !readPeerPresence(t, professional, f.patient.ID) {
		t.Fatal("professional did not receive online patient snapshot")
	}
	if !readPeerPresence(t, patient, f.prof.ID) {
		t.Fatal("patient did not receive professional connection update")
	}
}

func TestChatPresenceKeepsPeerOnlineUntilLastSocketCloses(t *testing.T) {
	f := clinicalFixture{therapyConsentFixture: newTherapyConsentFixture(t)}
	first := clinicalSocket(t, f, f.prof.ID, "professional")
	patient := clinicalSocket(t, f, f.patient.ID, "patient")
	if !readPeerPresence(t, patient, f.prof.ID) {
		t.Fatal("connected professional was not online")
	}
	second := clinicalSocket(t, f, f.prof.ID, "professional")
	if !readPeerPresence(t, second, f.patient.ID) {
		t.Fatal("second professional socket did not initialize")
	}
	updates := make(chan bool, 16)
	errors := make(chan error, 1)
	go func() {
		for {
			var event struct {
				Type string `json:"type"`
				Data struct {
					UserID string `json:"user_id"`
					Online bool   `json:"online"`
				} `json:"data"`
			}
			if err := patient.ReadJSON(&event); err != nil {
				errors <- err
				return
			}
			if event.Type == "presence" && event.Data.UserID == f.prof.ID {
				updates <- event.Data.Online
			}
		}
	}()
	// The same owner has a shell socket and a chat socket in the app. Closing
	// either must not send Offline while the other is still connected.
	_ = first.Close()
	quiet := time.NewTimer(200 * time.Millisecond)
	defer quiet.Stop()
observeFirstClose:
	for {
		select {
		case online := <-updates:
			if !online {
				t.Fatal("closing one socket announced Offline with another still connected")
			}
		case err := <-errors:
			t.Fatal(err)
		case <-quiet.C:
			break observeFirstClose
		}
	}
	_ = second.Close()
	select {
	case online := <-updates:
		if online {
			t.Fatal("peer did not go offline after its last socket closed")
		}
	case err := <-errors:
		t.Fatal(err)
	case <-time.After(time.Second):
		t.Fatal("missing last-socket Offline update")
	}
	if f.srv.hub.IsOnline(f.prof.ID) {
		t.Fatal("offline update preceded removal of the last professional socket")
	}
}

func TestChatPresenceDoesNotExposeUnlinkedUsers(t *testing.T) {
	f := clinicalFixture{therapyConsentFixture: newTherapyConsentFixture(t)}
	other := clinicalSocket(t, f, f.other.ID, "patient")
	_ = clinicalSocket(t, f, f.prof.ID, "professional")
	f.srv.hub.Publish(f.other.ID, realtime.Event{Type: "test.barrier"})
	_ = other.SetReadDeadline(time.Now().Add(2 * time.Second))
	var event struct {
		Type string          `json:"type"`
		Data json.RawMessage `json:"data"`
	}
	for {
		if err := other.ReadJSON(&event); err != nil {
			t.Fatal(err)
		}
		if event.Type == "presence" {
			t.Fatalf("unlinked user received private presence: %s", event.Data)
		}
		if event.Type == "test.barrier" {
			break
		}
	}
}

func TestChatPresenceInitialSnapshotExceedsLiveQueue(t *testing.T) {
	f := clinicalFixture{therapyConsentFixture: newTherapyConsentFixture(t)}
	peers := map[string]bool{f.patient.ID: false}
	for i := 0; i < 20; i++ {
		patient := createIdentityTestUser(t, f.db, f.st, "patient", nil)
		if _, err := f.st.LinkPatientToProfessional(context.Background(), patient.ID, f.prof.ID); err != nil {
			t.Fatal(err)
		}
		peers[patient.ID] = false
	}
	professional := clinicalSocket(t, f, f.prof.ID, "professional")
	_ = professional.SetReadDeadline(time.Now().Add(3 * time.Second))
	remaining := len(peers)
	for remaining > 0 {
		var event struct {
			Type string `json:"type"`
			Data struct {
				UserID string `json:"user_id"`
				Online bool   `json:"online"`
			} `json:"data"`
		}
		if err := professional.ReadJSON(&event); err != nil {
			t.Fatalf("initial snapshot omitted %d of 21 linked peers: %v", remaining, err)
		}
		if event.Type != "presence" {
			continue
		}
		seen, linked := peers[event.Data.UserID]
		if !linked || event.Data.Online {
			t.Fatalf("invalid initial peer presence: %+v", event.Data)
		}
		if !seen {
			peers[event.Data.UserID] = true
			remaining--
		}
	}
}

func TestChatPresenceSnapshotFailureClosesSocketForRetry(t *testing.T) {
	f := clinicalFixture{therapyConsentFixture: newTherapyConsentFixture(t)}
	brokenDB, err := store.OpenSQL(os.Getenv("MALVA_TEST_DATABASE_URL"))
	if err != nil {
		t.Fatal(err)
	}
	_ = brokenDB.Close()
	f.srv.hub = realtime.NewHub(f.srv.logger, func(string) bool { return true }, store.New(brokenDB))
	conn := clinicalSocket(t, f, f.patient.ID, "patient")
	var event struct{ Type string }
	if err := conn.ReadJSON(&event); err != nil || event.Type != "realtime.connected" {
		t.Fatalf("missing handshake acknowledgement: %s %v", event.Type, err)
	}
	_ = conn.SetReadDeadline(time.Now().Add(300 * time.Millisecond))
	_, _, err = conn.ReadMessage()
	var networkError net.Error
	if err == nil || (errors.As(err, &networkError) && networkError.Timeout()) {
		t.Fatalf("failed snapshot must close transport for reconnect, got %v", err)
	}
}
