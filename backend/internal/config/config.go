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
	MaxLoginAttempts   int
	LockoutDuration    int
	MaxRequestBodySize int64
	// GoogleClientID adalah Web OAuth Client ID untuk verifikasi Google Sign-In.
	// Kosong = endpoint /v1/auth/google nonaktif dengan pesan yang jelas.
	GoogleClientID string
	// PaymentMode memilih jalur pembayaran: "simulation" (default, dev/test)
	// atau "gateway" (produksi, wajib + server key Midtrans).
	PaymentMode string
	// Midtrans — kredensial gateway pembayaran produksi.
	MidtransServerKey string // auth Basic Snap + verifikasi signature
	MidtransClientKey string // dipakai klien (opsional di server)
	MidtransEnv       string // sandbox | production
	MidtransSnapBase  string // override base URL Snap (test/mock)
}

// PaymentModeSimulation / PaymentModeGateway nilai valid MALVA_PAYMENT_MODE.
const (
	PaymentModeSimulation = "simulation"
	PaymentModeGateway    = "gateway"
)

func Load() (Config, error) {
	cfg := Config{
		HTTPAddr:           getenv("MALVA_HTTP_ADDR", ":8080"),
		DatabaseURL:        os.Getenv("MALVA_DATABASE_URL"),
		JWTSecret:          os.Getenv("MALVA_JWT_SECRET"),
		AllowedOrigins:     splitCSV(getenv("MALVA_ALLOWED_ORIGINS", "http://localhost:3000,http://localhost:5173,http://localhost:8080")),
		FCMCredentialsFile: os.Getenv("MALVA_FCM_CREDENTIALS_FILE"),
		FCMCredentialsJSON: os.Getenv("MALVA_FCM_CREDENTIALS_JSON"),
		MaxLoginAttempts:   5,
		LockoutDuration:    15,
		MaxRequestBodySize: 1 << 20,
		GoogleClientID:     os.Getenv("MALVA_GOOGLE_CLIENT_ID"),
		PaymentMode:        strings.ToLower(getenv("MALVA_PAYMENT_MODE", PaymentModeSimulation)),
		MidtransServerKey:  os.Getenv("MALVA_MIDTRANS_SERVER_KEY"),
		MidtransClientKey:  os.Getenv("MALVA_MIDTRANS_CLIENT_KEY"),
		MidtransEnv:        strings.ToLower(getenv("MALVA_MIDTRANS_ENV", "sandbox")),
		MidtransSnapBase:   strings.TrimRight(os.Getenv("MALVA_MIDTRANS_SNAP_BASE"), "/"),
	}
	if cfg.DatabaseURL == "" {
		return Config{}, errors.New("MALVA_DATABASE_URL is required")
	}
	if len(cfg.JWTSecret) < 32 {
		return Config{}, errors.New("MALVA_JWT_SECRET must be at least 32 characters")
	}
	// Mode gateway wajib punya server key (dipakai auth Snap + verifikasi
	// signature webhook). Gagal saat boot agar salah konfigurasi terdeteksi dini.
	if cfg.PaymentMode == PaymentModeGateway && strings.TrimSpace(cfg.MidtransServerKey) == "" {
		return Config{}, errors.New("MALVA_MIDTRANS_SERVER_KEY is required when MALVA_PAYMENT_MODE=gateway")
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
