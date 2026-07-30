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
}

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
	ID          string `json:"id"`
	SenderID    string `json:"sender_id"`
	SenderName  string `json:"sender_name"`
	RecipientID string `json:"recipient_id"`
	Text        string `json:"text"`
	Timestamp   string `json:"timestamp"`
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
	h.Publish(userID, Event{Type: "realtime.connected", Data: map[string]string{"status": "ok"}})
	h.sendPresenceToLinkedUsers(userID, true)
	h.sendExistingPresence(c)
}

func (h *Hub) sendExistingPresence(c *client) {
	ctx := context.Background()
	linkedUsers, err := h.store.ListLinkedUsers(ctx, c.userID)
	if err != nil {
		h.logger.Warn("failed to list linked users for presence init", "error", err)
		return
	}
	for _, uid := range linkedUsers {
		h.mu.RLock()
		online := len(h.clients[uid]) > 0
		h.mu.RUnlock()
		if online {
			payload, _ := json.Marshal(Event{
				Type: "presence",
				Data: map[string]any{"user_id": uid, "online": true},
			})
			select {
			case c.send <- payload:
			default:
			}
		}
	}
}

func (h *Hub) sendPresenceToLinkedUsers(userID string, online bool) {
	ctx := context.Background()
	linkedUsers, err := h.store.ListLinkedUsers(ctx, userID)
	if err != nil {
		h.logger.Warn("failed to list linked users for presence", "error", err)
		return
	}
	event := Event{
		Type: "presence",
		Data: map[string]any{"user_id": userID, "online": online},
	}
	for _, uid := range linkedUsers {
		h.Publish(uid, event)
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
	defer h.mu.Unlock()
	if _, ok := h.clients[c.userID][c]; ok {
		delete(h.clients[c.userID], c)
		close(c.send)
	}
	if len(h.clients[c.userID]) == 0 {
		delete(h.clients, c.userID)
	}
	c.conn.Close()
}

func (c *client) readPump() {
	defer func() {
		c.hub.sendPresenceToLinkedUsers(c.userID, false)
		c.hub.unregister(c)
	}()
	c.conn.SetReadLimit(8192)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
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
	if msg.Text == "" || msg.ID == "" || msg.RecipientID == "" {
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
		c.hub.logger.Warn("ws: users not linked", "sender", c.userID, "recipient", msg.RecipientID)
		return
	}
	timestamp := time.Now()
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
			Timestamp:   saved.CreatedAt.Format(time.RFC3339),
		},
	}
	c.hub.Publish(c.userID, outEvent)
	c.hub.Publish(msg.RecipientID, outEvent)
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
	for {
		select {
		case message, ok := <-c.send:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if !ok {
				c.conn.WriteMessage(websocket.CloseMessage, []byte{})
				return
			}
			if err := c.conn.WriteMessage(websocket.TextMessage, message); err != nil {
				return
			}
		case <-ticker.C:
			c.conn.SetWriteDeadline(time.Now().Add(writeWait))
			if err := c.conn.WriteMessage(websocket.PingMessage, nil); err != nil {
				return
			}
		}
	}
}
