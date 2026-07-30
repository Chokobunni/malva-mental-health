package security

import (
	"sync"
	"time"
)

type SessionManager struct {
	mu              sync.RWMutex
	invalidatedUser map[string]time.Time
	sessionVersion  map[string]int64
}

func NewSessionManager() *SessionManager {
	sm := &SessionManager{
		invalidatedUser: make(map[string]time.Time),
		sessionVersion:  make(map[string]int64),
	}
	go sm.cleanup()
	return sm
}

func (sm *SessionManager) InvalidateUserSessions(userID string) {
	sm.mu.Lock()
	defer sm.mu.Unlock()
	sm.invalidatedUser[userID] = time.Now()
	if v, ok := sm.sessionVersion[userID]; ok {
		sm.sessionVersion[userID] = v + 1
	} else {
		sm.sessionVersion[userID] = 1
	}
}

func (sm *SessionManager) IsSessionValid(userID string, issuedAt int64) bool {
	sm.mu.RLock()
	defer sm.mu.RUnlock()
	invalidatedAt, ok := sm.invalidatedUser[userID]
	if !ok {
		return true
	}
	return time.Unix(issuedAt, 0).After(invalidatedAt)
}

func (sm *SessionManager) GetSessionVersion(userID string) int64 {
	sm.mu.RLock()
	defer sm.mu.RUnlock()
	return sm.sessionVersion[userID]
}

func (sm *SessionManager) cleanup() {
	ticker := time.NewTicker(1 * time.Hour)
	defer ticker.Stop()
	for range ticker.C {
		sm.mu.Lock()
		cutoff := time.Now().Add(-24 * time.Hour)
		for userID, t := range sm.invalidatedUser {
			if t.Before(cutoff) {
				delete(sm.invalidatedUser, userID)
				delete(sm.sessionVersion, userID)
			}
		}
		sm.mu.Unlock()
	}
}

type IPWhitelist struct {
	mu       sync.RWMutex
	whitelist map[string]bool
}

func NewIPWhitelist() *IPWhitelist {
	return &IPWhitelist{
		whitelist: make(map[string]bool),
	}
}

func (w *IPWhitelist) Add(ip string) {
	w.mu.Lock()
	defer w.mu.Unlock()
	w.whitelist[ip] = true
}

func (w *IPWhitelist) Remove(ip string) {
	w.mu.Lock()
	defer w.mu.Unlock()
	delete(w.whitelist, ip)
}

func (w *IPWhitelist) IsAllowed(ip string) bool {
	w.mu.RLock()
	defer w.mu.RUnlock()
	if len(w.whitelist) == 0 {
		return true
	}
	return w.whitelist[ip]
}

type RequestSizeLimiter struct {
	maxBodySize int64
}

func NewRequestSizeLimiter(maxBodySize int64) *RequestSizeLimiter {
	return &RequestSizeLimiter{maxBodySize: maxBodySize}
}

func (r *RequestSizeLimiter) MaxBodySize() int64 {
	return r.maxBodySize
}
