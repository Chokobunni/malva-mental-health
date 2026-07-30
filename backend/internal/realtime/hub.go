package realtime

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"sync"
	"time"

	"github.com/gorilla/websocket"
)

const (
	writeWait  = 10 * time.Second
	pongWait   = 60 * time.Second
	pingPeriod = 45 * time.Second
)

type Hub struct {
	logger        *slog.Logger
	originAllowed func(string) bool
	mu            sync.RWMutex
	clients       map[string]map[*client]struct{}
}

type Event struct {
	Type string `json:"type"`
	Data any    `json:"data"`
}

type client struct {
	userID string
	conn   *websocket.Conn
	send   chan []byte
	hub    *Hub
}

func NewHub(logger *slog.Logger, originAllowed func(string) bool) *Hub {
	return &Hub{
		logger:        logger,
		originAllowed: originAllowed,
		clients:       map[string]map[*client]struct{}{},
	}
}

func (h *Hub) ServeWS(w http.ResponseWriter, r *http.Request, userID string) {
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
		conn:   conn,
		send:   make(chan []byte, 16),
		hub:    h,
	}
	h.register(c)
	go c.writePump()
	go c.readPump()
	h.Publish(userID, Event{Type: "realtime.connected", Data: map[string]string{"status": "ok"}})
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
	defer c.hub.unregister(c)
	c.conn.SetReadLimit(1024)
	c.conn.SetReadDeadline(time.Now().Add(pongWait))
	c.conn.SetPongHandler(func(string) error {
		c.conn.SetReadDeadline(time.Now().Add(pongWait))
		return nil
	})
	for {
		if _, _, err := c.conn.NextReader(); err != nil {
			return
		}
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
