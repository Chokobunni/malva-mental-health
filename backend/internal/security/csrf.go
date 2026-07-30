package security

import (
	"crypto/rand"
	"crypto/subtle"
	"encoding/base64"
	"net/http"
	"strings"
	"time"
)

const (
	csrfTokenLength = 32
	csrfCookieName  = "malva_csrf"
	csrfHeaderName  = "X-CSRF-Token"
	csrfMaxAge      = 24 * time.Hour
)

func GenerateCSRFToken() (string, error) {
	bytes := make([]byte, csrfTokenLength)
	if _, err := rand.Read(bytes); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(bytes), nil
}

func CSRFMiddleware(next http.Handler, allowedOrigins []string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet || r.Method == http.MethodHead || r.Method == http.MethodOptions {
			next.ServeHTTP(w, r)
			return
		}
		origin := r.Header.Get("Origin")
		if origin != "" {
			allowed := false
			for _, ao := range allowedOrigins {
				if ao == "*" || ao == origin {
					allowed = true
					break
				}
			}
			if !allowed {
				http.Error(w, "origin not allowed", http.StatusForbidden)
				return
			}
		}
		referer := r.Header.Get("Referer")
		if referer != "" && origin == "" {
			allowed := false
			for _, ao := range allowedOrigins {
				if ao == "*" || strings.HasPrefix(referer, ao) {
					allowed = true
					break
				}
			}
			if !allowed {
				http.Error(w, "referer not allowed", http.StatusForbidden)
				return
			}
		}
		token := r.Header.Get(csrfHeaderName)
		if token == "" {
			cookie, err := r.Cookie(csrfCookieName)
			if err == nil {
				token = cookie.Value
			}
		}
		if token == "" {
			http.Error(w, "missing CSRF token", http.StatusForbidden)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func SetCSRFTokenCookie(w http.ResponseWriter, token string) {
	http.SetCookie(w, &http.Cookie{
		Name:     csrfCookieName,
		Value:    token,
		Path:     "/",
		HttpOnly: false,
		Secure:   true,
		SameSite: http.SameSiteStrictMode,
		MaxAge:   int(csrfMaxAge.Seconds()),
	})
}

func ValidateCSRFToken(provided, expected string) bool {
	return subtle.ConstantTimeCompare([]byte(provided), []byte(expected)) == 1
}
