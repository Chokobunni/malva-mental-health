package config

import (
	"errors"
	"os"
	"strings"
)

type Config struct {
	HTTPAddr           string
	DatabaseURL        string
	JWTSecret          string
	AllowedOrigins     []string
	FCMCredentialsFile string
	FCMCredentialsJSON string
}

func Load() (Config, error) {
	cfg := Config{
		HTTPAddr:           getenv("MALVA_HTTP_ADDR", ":8080"),
		DatabaseURL:        os.Getenv("MALVA_DATABASE_URL"),
		JWTSecret:          os.Getenv("MALVA_JWT_SECRET"),
		AllowedOrigins:     splitCSV(getenv("MALVA_ALLOWED_ORIGINS", "http://localhost:3000,http://localhost:5173,http://localhost:8080")),
		FCMCredentialsFile: os.Getenv("MALVA_FCM_CREDENTIALS_FILE"),
		FCMCredentialsJSON: os.Getenv("MALVA_FCM_CREDENTIALS_JSON"),
	}
	if cfg.DatabaseURL == "" {
		return Config{}, errors.New("MALVA_DATABASE_URL is required")
	}
	if len(cfg.JWTSecret) < 32 {
		return Config{}, errors.New("MALVA_JWT_SECRET must be at least 32 characters")
	}
	return cfg, nil
}

func (c Config) OriginAllowed(origin string) bool {
	if origin == "" {
		return true
	}
	for _, allowed := range c.AllowedOrigins {
		if allowed == "*" || allowed == origin {
			return true
		}
	}
	return false
}

func getenv(key, fallback string) string {
	value := os.Getenv(key)
	if value == "" {
		return fallback
	}
	return value
}

func splitCSV(value string) []string {
	parts := strings.Split(value, ",")
	out := make([]string, 0, len(parts))
	for _, part := range parts {
		part = strings.TrimSpace(part)
		if part != "" {
			out = append(out, part)
		}
	}
	return out
}
