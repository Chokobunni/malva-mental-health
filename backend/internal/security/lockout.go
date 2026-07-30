package security

import (
	"sync"
	"time"
)

type AccountLockout struct {
	mu             sync.Mutex
	maxAttempts    int
	lockoutWindow  time.Duration
	lockoutDuration time.Duration
	attempts       map[string]*attemptRecord
}

type attemptRecord struct {
	count     int
	firstAt   time.Time
	lockedUntil time.Time
}

func NewAccountLockout(maxAttempts int, lockoutWindow, lockoutDuration time.Duration) *AccountLockout {
	l := &AccountLockout{
		maxAttempts:     maxAttempts,
		lockoutWindow:   lockoutWindow,
		lockoutDuration: lockoutDuration,
		attempts:        make(map[string]*attemptRecord),
	}
	go l.cleanup()
	return l
}

func (l *AccountLockout) IsLocked(key string) bool {
	l.mu.Lock()
	defer l.mu.Unlock()
	rec, ok := l.attempts[key]
	if !ok {
		return false
	}
	if !rec.lockedUntil.IsZero() && time.Now().Before(rec.lockedUntil) {
		return true
	}
	if time.Since(rec.firstAt) > l.lockoutWindow {
		delete(l.attempts, key)
		return false
	}
	return false
}

func (l *AccountLockout) RecordFailure(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	rec, ok := l.attempts[key]
	if !ok || time.Since(rec.firstAt) > l.lockoutWindow {
		l.attempts[key] = &attemptRecord{count: 1, firstAt: time.Now()}
		return
	}
	rec.count++
	if rec.count >= l.maxAttempts {
		rec.lockedUntil = time.Now().Add(l.lockoutDuration)
	}
}

func (l *AccountLockout) Reset(key string) {
	l.mu.Lock()
	defer l.mu.Unlock()
	delete(l.attempts, key)
}

func (l *AccountLockout) RemainingAttempts(key string) int {
	l.mu.Lock()
	defer l.mu.Unlock()
	rec, ok := l.attempts[key]
	if !ok {
		return l.maxAttempts
	}
	if time.Since(rec.firstAt) > l.lockoutWindow {
		delete(l.attempts, key)
		return l.maxAttempts
	}
	remaining := l.maxAttempts - rec.count
	if remaining < 0 {
		return 0
	}
	return remaining
}

func (l *AccountLockout) cleanup() {
	ticker := time.NewTicker(10 * time.Minute)
	defer ticker.Stop()
	for range ticker.C {
		l.mu.Lock()
		now := time.Now()
		for key, rec := range l.attempts {
			if !rec.lockedUntil.IsZero() && now.After(rec.lockedUntil) {
				delete(l.attempts, key)
			} else if time.Since(rec.firstAt) > 2*l.lockoutWindow {
				delete(l.attempts, key)
			}
		}
		l.mu.Unlock()
	}
}
