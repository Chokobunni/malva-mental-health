package realtime

import (
	"context"
	"encoding/json"
	"log/slog"
	"net/http"
	"strings"
	"sync"
	"time"

	"github.com/gorilla/websocket"
	"malva/backend/internal/clock"
	"malva/backend/internal/store"
)

const (
	writeWait  = 10 * time.Second
	pongWait   = 60 * time.Second
	pingPeriod = 45 * time.Second
)

type Hub struct {
	logger        *slog.Logger
	originAllowed func(string) bool
	store         *store.Store
	mu            sync.RWMutex
	clients       map[string]map[*client]struct{}
	// chatPush dipanggil saat pesan chat teks tersimpan & dipublikasikan, agar
	// lapisan server bisa mengirim push FCM (hanya saat sesi aktif & penerima
	// offline). Nil = tidak ada push. Di-set via SetChatPush untuk menghindari
	// import cycle (realtime tidak boleh mengimpor server).
	chatPush ChatPushFunc
}

// ChatPushFunc adalah callback push chat tanpa import cycle. Dipanggil dari
// jalur WebSocket setelah pesan tersimpan & dipublikasikan.
type ChatPushFunc func(ctx context.Context, recipientID, senderID, senderName, text, patientID, professionalID, sessionID string, inSession bool)

type Event struct {
	Type string `json:"type"`
	Data any    `json:"data"`
}

type client struct {
	userID string
	role   string
	conn   *websocket.Conn
	send   chan []byte
	hub    *Hub
}

type wsEnvelope struct {
	Type string          `json:"type"`
	Data json.RawMessage `json:"data"`
}

type chatMessageData struct {
	ClientMessageID string          `json:"client_message_id,omitempty"`
	ID              string          `json:"id"`
	SenderID        string          `json:"sender_id"`
	SenderName      string          `json:"sender_name"`
	RecipientID     string          `json:"recipient_id"`
	Text            string          `json:"text"`
	Kind            string          `json:"kind,omitempty"`
	Metadata        json.RawMessage `json:"metadata,omitempty"`
	Timestamp       string          `json:"timestamp"`
}

type typingIndicatorData struct {
	SenderID    string `json:"sender_id"`
	RecipientID string `json:"recipient_id,omitempty"`
	Typing      bool   `json:"typing"`
}

func NewHub(logger *slog.Logger, originAllowed func(string) bool, st *store.Store) *Hub {
	return &Hub{
		logger:        logger,
		originAllowed: originAllowed,
		store:         st,
		clients:       map[string]map[*client]struct{}{},
	}
}

// SetChatPush mendaftarkan callback push chat (dipanggil dari lapisan server
// agar tidak terjadi import cycle).
func (h *Hub) SetChatPush(fn ChatPushFunc) {
	h.chatPush = fn
}

// IsOnline melaporkan apakah user punya minimal satu koneksi WebSocket aktif.
// Dipakai untuk menahan push FCM ke pengguna yang sedang online (real-time
// sudah cukup).
func (h *Hub) IsOnline(userID string) bool {
	h.mu.RLock()
	defer h.mu.RUnlock()
	return len(h.clients[userID]) > 0
}

func (h *Hub) ServeWS(w http.ResponseWriter, r *http.Request, userID, role string) {
	upgrader := websocket.Upgrader{
		CheckOrigin: func(r *http.Request) bool {
			return h.originAllowed(r.Header.Get("Origin"))
		},
	}
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		h.logger.Warn("websocket upgrade failed", "error", err)
		return
	}
	c := &client{
		userID: userID,
		role:   role,
		conn:   conn,
		send:   make(chan []byte, 16),
		hub:    h,
	}
	h.register(c)
	go c.writePump()
	go c.readPump()
	h.sendPresenceToLinkedUsers(userID)
}

// sendExistingPresence runs only in writePump, before queued live events. Write
// each snapshot directly so linked peers cannot overflow the live-event queue.
func (h *Hub) sendExistingPresence(c *client) error {
	ctx := context.Background()
	linkedUsers, err := h.store.ListLinkedUsers(ctx, c.userID)
	if err != nil {
		h.logger.Warn("failed to list linked users for presence init", "error", err)
		return err
	}
	for _, uid := range linkedUsers {
		h.mu.RLock()
		online := len(h.clients[uid]) > 0
		h.mu.RUnlock()
		payload, _ := json.Marshal(Event{
			Type: "presence",
			Data: map[string]any{"user_id": uid, "online": online},
		})
		_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
		if err := c.conn.WriteMessage(websocket.TextMessage, payload); err != nil {
			return err
		}
	}
	return nil
}

func (h *Hub) sendPresenceToLinkedUsers(userID string) {
	ctx := context.Background()
	linkedUsers, err := h.store.ListLinkedUsers(ctx, userID)
	if err != nil {
		h.logger.Warn("failed to list linked users for presence", "error", err)
		return
	}
	// Read membership and enqueue its status under the same lock so a delayed
	// disconnect cannot overwrite a newer reconnect's presence.
	h.mu.RLock()
	defer h.mu.RUnlock()
	payload, _ := json.Marshal(Event{
		Type: "presence",
		Data: map[string]any{"user_id": userID, "online": len(h.clients[userID]) > 0},
	})
	for _, uid := range linkedUsers {
		for c := range h.clients[uid] {
			select {
			case c.send <- payload:
			default:
				go h.unregister(c)
			}
		}
	}
}

func (h *Hub) Publish(userID string, event Event) {
	payload, err := json.Marshal(event)
	if err != nil {
		h.logger.Warn("realtime event marshal failed", "error", err)
		return
	}
	h.mu.RLock()
	defer h.mu.RUnlock()
	for c := range h.clients[userID] {
		select {
		case c.send <- payload:
		default:
			go h.unregister(c)
		}
	}
}

func (h *Hub) Broadcast(msg interface{}) {
	payload, err := json.Marshal(msg)
	if err != nil {
		h.logger.Warn("broadcast marshal failed", "error", err)
		return
	}
	h.mu.RLock()
	defer h.mu.RUnlock()
	for _, clients := range h.clients {
		for c := range clients {
			select {
			case c.send <- payload:
			default:
			}
		}
	}
}

func (h *Hub) register(c *client) {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.clients[c.userID] == nil {
		h.clients[c.userID] = map[*client]struct{}{}
	}
	h.clients[c.userID][c] = struct{}{}
}

func (h *Hub) unregister(c *client) {
	h.mu.Lock()
	lastConnection := false
	if _, ok := h.clients[c.userID][c]; ok {
		delete(h.clients[c.userID], c)
		close(c.send)
		if len(h.clients[c.userID]) == 0 {
			delete(h.clients, c.userID)
			lastConnection = true
		}
	}
	h.mu.Unlock()
	_ = c.conn.Close()
	if lastConnection {
		h.sendPresenceToLinkedUsers(c.userID)
	}
}

func (c *client) readPump() {
	defer c.hub.unregister(c)
	c.conn.SetReadLimit(8192)
	_ = c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		_ = c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})
	for {
		_, raw, err := c.conn.ReadMessage()
		if err != nil {
			return
		}
		var env wsEnvelope
		if err := json.Unmarshal(raw, &env); err != nil {
			c.hub.logger.Warn("ws: invalid envelope", "user", c.userID, "error", err)
			continue
		}
		switch env.Type {
		case "chat_message":
			c.handleChatMessage(env.Data)
		case "typing_indicator":
			c.handleTypingIndicator(env.Data)
		default:
			c.hub.logger.Warn("ws: unknown type", "user", c.userID, "type", env.Type)
		}
	}
}

func (c *client) handleChatMessage(raw json.RawMessage) {
	var msg chatMessageData
	if err := json.Unmarshal(raw, &msg); err != nil {
		c.hub.logger.Warn("ws: bad chat_message payload", "user", c.userID, "error", err)
		return
	}
	msg.Text = strings.TrimSpace(msg.Text)
	hasMetadata := len(msg.Metadata) > 0 && string(msg.Metadata) != "null"
	if (msg.Text == "" && !hasMetadata) || msg.ID == "" || msg.RecipientID == "" {
		return
	}
	if msg.SenderID != c.userID {
		c.hub.logger.Warn("ws: sender_id mismatch", "expected", c.userID, "got", msg.SenderID)
		return
	}
	if len(msg.Text) > 5000 {
		msg.Text = msg.Text[:5000]
	}
	ctx := context.Background()
	patientID, professionalID, linked, err := c.hub.store.AreUsersLinked(ctx, c.userID, msg.RecipientID)
	if err != nil {
		c.hub.logger.Warn("ws: link check failed", "error", err)
		return
	}
	if !linked {
		// Relasi longgar (sesi/paket) tetap diizinkan untuk dibaca di REST;
		// WS hanya menyimpan bila ada relasi apa pun.
		rel, rerr := c.hub.store.PairRelation(ctx, c.userID, msg.RecipientID)
		if rerr != nil || !rel {
			c.hub.logger.Warn("ws: users not linked", "sender", c.userID, "recipient", msg.RecipientID)
			return
		}
		if c.role == "patient" {
			patientID, professionalID = c.userID, msg.RecipientID
		} else {
			patientID, professionalID = msg.RecipientID, c.userID
		}
	}
	// Kebijakan chat: teks hanya saat sesi berjalan; share data milik
	// pasien butuh paket aktif; profesional tidak membalas di luar sesi.
	kindLower := strings.ToLower(strings.TrimSpace(msg.Kind))
	if c.role != "professional" && (kindLower == "attachment" || kindLower == "assessment_request" || kindLower == "session_summary") {
		return
	}
	isShare := kindLower != "" && kindLower != "text"
	access, aerr := c.hub.store.ChatAccessFor(ctx, patientID, professionalID, c.role)
	if aerr != nil {
		c.hub.logger.Warn("ws: chat access check failed", "error", aerr)
		return
	}
	if isShare {
		if c.role == "professional" {
			metadata, err := c.hub.store.ValidateProfessionalChatCard(ctx, patientID, professionalID, kindLower, msg.Metadata, access)
			if err != nil {
				return
			}
			msg.Metadata = metadata
		} else if c.role != "patient" || !access.CanShare {
			c.hub.logger.Warn("ws: share rejected", "sender", c.userID)
			return
		}
	} else if !access.CanSendText {
		c.hub.logger.Warn("ws: text rejected outside session", "sender", c.userID)
		return
	}
	if msg.ClientMessageID != "" {
		if !store.ValidClinicalClientID(msg.ClientMessageID) {
			return
		}
		msg.ID = store.ClinicalRetryID("message", c.userID, msg.ClientMessageID)
	}
	timestamp := clock.Now()
	if msg.Timestamp != "" {
		if t, err := time.Parse(time.RFC3339, msg.Timestamp); err == nil {
			timestamp = t
		}
	}
	senderName := strings.TrimSpace(msg.SenderName)
	if senderName == "" {
		user, err := c.hub.store.GetUserByID(ctx, c.userID)
		if err == nil {
			senderName = user.DisplayName
		}
	}
	saved, err := c.hub.store.CreateChatMessage(ctx, store.ChatMessage{
		ID:             msg.ID,
		PatientID:      patientID,
		ProfessionalID: professionalID,
		SenderID:       c.userID,
		SenderName:     senderName,
		Text:           msg.Text,
		Kind:           msg.Kind,
		Metadata:       msg.Metadata,
		CreatedAt:      timestamp,
	})
	if err != nil {
		c.hub.logger.Warn("ws: persist chat message failed", "error", err)
		return
	}
	outEvent := Event{
		Type: "chat_message",
		Data: chatMessageData{
			ID:          saved.ID,
			SenderID:    saved.SenderID,
			SenderName:  saved.SenderName,
			RecipientID: msg.RecipientID,
			Text:        saved.Text,
			Kind:        saved.Kind,
			Metadata:    saved.Metadata,
			Timestamp:   saved.CreatedAt.Format(time.RFC3339),
		},
	}
	c.hub.Publish(c.userID, outEvent)
	c.hub.Publish(msg.RecipientID, outEvent)

	// Push FCM ke penerima — hanya pesan teks percakapan (kartu share tidak
	// memicu push). inSession & sessionID diambil dari ChatAccess yang sudah
	// dihitung di atas. notifyChatPush (lapisan server) menahan push bila sesi
	// tidak aktif, penerima sedang online, atau dalam cooldown.
	if !isShare && c.hub.chatPush != nil {
		c.hub.chatPush(ctx, msg.RecipientID, c.userID, senderName, saved.Text,
			patientID, professionalID, access.SessionID, access.InSession)
	}
}

func (c *client) handleTypingIndicator(raw json.RawMessage) {
	var msg typingIndicatorData
	if err := json.Unmarshal(raw, &msg); err != nil {
		c.hub.logger.Warn("ws: bad typing_indicator payload", "user", c.userID, "error", err)
		return
	}
	msg.SenderID = c.userID
	event := Event{
		Type: "typing_indicator",
		Data: typingIndicatorData{
			SenderID: c.userID,
			Typing:   msg.Typing,
		},
	}
	if msg.RecipientID != "" {
		c.hub.Publish(msg.RecipientID, event)
		return
	}
	ctx := context.Background()
	linkedUsers, err := c.hub.store.ListLinkedUsers(ctx, c.userID)
	if err != nil {
		c.hub.logger.Warn("ws: list linked users for typing failed", "error", err)
		return
	}
	for _, uid := range linkedUsers {
		c.hub.Publish(uid, event)
	}
}

func (c *client) writePump() {
	ticker := time.NewTicker(pingPeriod)
	defer func() {
		ticker.Stop()
		c.hub.unregister(c)
	}()
	_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
	if err := c.conn.WriteJSON(Event{Type: "realtime.connected", Data: map[string]string{"status": "ok"}}); err != nil {
		return
	}
	if err := c.hub.sendExistingPresence(c); err != nil {
		return
	}
	for {
		select {
		case message, ok := <-c.send:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				_ = c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}
		case <-ticker.C:
			_ = c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
