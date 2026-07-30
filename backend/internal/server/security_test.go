package server

import (
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"malva/backend/internal/auth"
	"malva/backend/internal/config"
)

func newSecurityTestHandler() http.Handler {
	cfg := config.Config{
		AllowedOrigins: []string{"https://api.malva.id"},
	}
	logger := slog.New(slog.NewTextHandler(testWriter{}, nil))
	return New(cfg, auth.NewManager("12345678901234567890123456789012"), nil, nil, logger).Routes()
}

func TestSecurityHeadersAreSetOnRoot(t *testing.T) {
	handler := newSecurityTestHandler()
	request := httptest.NewRequest(http.MethodGet, "/", nil)
	response := httptest.NewRecorder()

	handler.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected status 200, got %d", response.Code)
	}
	headers := response.Header()
	assertHeader(t, headers, "X-Content-Type-Options", "nosniff")
	assertHeader(t, headers, "X-Frame-Options", "DENY")
	assertHeader(t, headers, "Referrer-Policy", "no-referrer")
	if headers.Get("Content-Security-Policy") == "" {
		t.Fatal("expected Content-Security-Policy header")
	}
}

func TestCORSAllowsOnlyConfiguredOrigin(t *testing.T) {
	handler := newSecurityTestHandler()

	allowed := httptest.NewRequest(http.MethodOptions, "/v1/auth/login", nil)
	allowed.Header.Set("Origin", "https://api.malva.id")
	allowedResponse := httptest.NewRecorder()
	handler.ServeHTTP(allowedResponse, allowed)

	assertHeader(t, allowedResponse.Header(), "Access-Control-Allow-Origin", "https://api.malva.id")

	blocked := httptest.NewRequest(http.MethodOptions, "/v1/auth/login", nil)
	blocked.Header.Set("Origin", "https://evil.example")
	blockedResponse := httptest.NewRecorder()
	handler.ServeHTTP(blockedResponse, blocked)

	if blockedResponse.Header().Get("Access-Control-Allow-Origin") != "" {
		t.Fatal("unexpected CORS allow header for unconfigured origin")
	}
}

func assertHeader(t *testing.T, headers http.Header, key string, expected string) {
	t.Helper()
	if got := headers.Get(key); got != expected {
		t.Fatalf("expected %s=%q, got %q", key, expected, got)
	}
}

type testWriter struct{}

func (testWriter) Write(p []byte) (int, error) {
	return len(p), nil
}
