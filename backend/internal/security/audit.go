package security

import (
	"log/slog"
	"net/http"
	"time"
)

type SecurityEvent struct {
	Timestamp  time.Time `json:"timestamp"`
	EventType  string    `json:"event_type"`
	Severity   string    `json:"severity"`
	UserID     string    `json:"user_id,omitempty"`
	IP         string    `json:"ip"`
	UserAgent  string    `json:"user_agent,omitempty"`
	Path       string    `json:"path,omitempty"`
	Method     string    `json:"method,omitempty"`
	Details    string    `json:"details,omitempty"`
	Blocked    bool      `json:"blocked"`
}

type SecurityLogger struct {
	logger *slog.Logger
}

func NewSecurityLogger(logger *slog.Logger) *SecurityLogger {
	return &SecurityLogger{logger: logger}
}

func (sl *SecurityLogger) LogAuthFailure(r *http.Request, email, reason string) {
	sl.logger.Warn("auth_failure",
		"event_type", "auth_failure",
		"severity", "medium",
		"ip", clientIP(r),
		"user_agent", r.UserAgent(),
		"path", r.URL.Path,
		"method", r.Method,
		"email", email,
		"reason", reason,
		"blocked", false,
	)
}

func (sl *SecurityLogger) LogAuthSuccess(r *http.Request, userID string) {
	sl.logger.Info("auth_success",
		"event_type", "auth_success",
		"severity", "low",
		"user_id", userID,
		"ip", clientIP(r),
		"user_agent", r.UserAgent(),
		"path", r.URL.Path,
	)
}

func (sl *SecurityLogger) LogAccountLocked(r *http.Request, email string) {
	sl.logger.Warn("account_locked",
		"event_type", "account_locked",
		"severity", "high",
		"ip", clientIP(r),
		"user_agent", r.UserAgent(),
		"email", email,
		"blocked", true,
	)
}

func (sl *SecurityLogger) LogSuspiciousInput(r *http.Request, input, reason string) {
	sl.logger.Warn("suspicious_input",
		"event_type", "suspicious_input",
		"severity", "medium",
		"ip", clientIP(r),
		"user_agent", r.UserAgent(),
		"path", r.URL.Path,
		"method", r.Method,
		"reason", reason,
		"input", input,
		"blocked", true,
	)
}

func (sl *SecurityLogger) LogRateLimitExceeded(r *http.Request) {
	sl.logger.Warn("rate_limit_exceeded",
		"event_type", "rate_limit_exceeded",
		"severity", "medium",
		"ip", clientIP(r),
		"user_agent", r.UserAgent(),
		"path", r.URL.Path,
		"method", r.Method,
		"blocked", true,
	)
}

func (sl *SecurityLogger) LogUnauthorizedAccess(r *http.Request, userID, resource string) {
	sl.logger.Warn("unauthorized_access",
		"event_type", "unauthorized_access",
		"severity", "high",
		"user_id", userID,
		"ip", clientIP(r),
		"user_agent", r.UserAgent(),
		"path", r.URL.Path,
		"method", r.Method,
		"resource", resource,
		"blocked", true,
	)
}

func (sl *SecurityLogger) LogSessionInvalidated(r *http.Request, userID, reason string) {
	sl.logger.Info("session_invalidated",
		"event_type", "session_invalidated",
		"severity", "medium",
		"user_id", userID,
		"ip", clientIP(r),
		"reason", reason,
	)
}

func (sl *SecurityLogger) LogCSRFViolation(r *http.Request) {
	sl.logger.Warn("csrf_violation",
		"event_type", "csrf_violation",
		"severity", "high",
		"ip", clientIP(r),
		"user_agent", r.UserAgent(),
		"path", r.URL.Path,
		"method", r.Method,
		"blocked", true,
	)
}

func (sl *SecurityLogger) LogPrivilegeEscalation(r *http.Request, userID, attemptedAction string) {
	sl.logger.Error("privilege_escalation",
		"event_type", "privilege_escalation",
		"severity", "critical",
		"user_id", userID,
		"ip", clientIP(r),
		"user_agent", r.UserAgent(),
		"path", r.URL.Path,
		"method", r.Method,
		"action", attemptedAction,
		"blocked", true,
	)
}

func clientIP(r *http.Request) string {
	if forwarded := r.Header.Get("X-Forwarded-For"); forwarded != "" {
		first := forwarded
		for i, ch := range forwarded {
			if ch == ',' {
				first = forwarded[:i]
				break
			}
		}
		return first
	}
	if realIP := r.Header.Get("X-Real-IP"); realIP != "" {
		return realIP
	}
	host := r.RemoteAddr
	for i := len(host) - 1; i >= 0; i-- {
		if host[i] == ':' {
			return host[:i]
		}
	}
	return host
}
