package config

import (
	"errors"
	"os"
	"strings"
)

type Config struct {
	HTTPAddr           string
	LogLevel           string
	DatabaseURL        string
	JWTSecret          string
	AllowedOrigins     []string
	FCMCredentialsFile string
	FCMCredentialsJSON string
	// FCMProjectID adalah Firebase project ID untuk push notification.
	// Kosong = otomatis dibaca dari `project_id` pada kredensial service
	// account, sehingga backend selalu sinkron dengan project Firebase.
	FCMProjectID       string
	MaxLoginAttempts   int
	LockoutDuration    int
	MaxRequestBodySize int64
	// GoogleClientID adalah Web OAuth Client ID untuk verifikasi Google Sign-In.
	// Kosong = endpoint /v1/auth/google nonaktif dengan pesan yang jelas.
	GoogleClientID string
	// GoogleClientSecret adalah OAuth client secret untuk pertukaran token
	// (authorization code -> refresh/access token) dan akses Google Calendar API.
	GoogleClientSecret string
	// PaymentMode memilih jalur pembayaran: "simulation" (default, dev/test)
	// atau "gateway" (produksi, wajib + server key Midtrans).
	PaymentMode string
	// Midtrans — kredensial gateway pembayaran produksi.
	MidtransServerKey string // auth Basic Snap + verifikasi signature
	MidtransClientKey string // dipakai klien (opsional di server)
	MidtransEnv       string // sandbox | production
	MidtransSnapBase  string // override base URL Snap (test/mock)
	// Fonnte — gateway WhatsApp untuk blast SOS ke kontak darurat. Kosong =
	// kanal keluar belum aktif; SOS tetap tercatat tetapi tidak mengklaim
	// "terkirim".
	FonnteToken   string
	FonnteBaseURL string
	// Upload — konfigurasi unggah berkas (foto/video profil profesional).
	UploadDir    string // direktori penyimpanan berkas unggahan
	MaxImageSize int64  // batas ukuran gambar (byte)
	MaxVideoSize int64  // batas ukuran video (byte)
}

// PaymentModeSimulation / PaymentModeGateway nilai valid MALVA_PAYMENT_MODE.
const (
	PaymentModeSimulation = "simulation"
	PaymentModeGateway    = "gateway"
)

func Load() (Config, error) {
	cfg := Config{
		HTTPAddr:           getenv("MALVA_HTTP_ADDR", ":8080"),
		LogLevel:           strings.ToLower(getenv("MALVA_LOG_LEVEL", "info")),
		DatabaseURL:        os.Getenv("MALVA_DATABASE_URL"),
		JWTSecret:          os.Getenv("MALVA_JWT_SECRET"),
		AllowedOrigins:     splitCSV(getenv("MALVA_ALLOWED_ORIGINS", "http://localhost:3000,http://localhost:5173,http://localhost:8080")),
		FCMCredentialsFile: os.Getenv("MALVA_FCM_CREDENTIALS_FILE"),
		FCMCredentialsJSON: os.Getenv("MALVA_FCM_CREDENTIALS_JSON"),
		FCMProjectID:       os.Getenv("MALVA_FCM_PROJECT_ID"),
		MaxLoginAttempts:   5,
		LockoutDuration:    15,
		MaxRequestBodySize: 1 << 20,
		GoogleClientID:     os.Getenv("MALVA_GOOGLE_CLIENT_ID"),
		GoogleClientSecret: os.Getenv("MALVA_GOOGLE_CLIENT_SECRET"),
		PaymentMode:        strings.ToLower(getenv("MALVA_PAYMENT_MODE", PaymentModeSimulation)),
		MidtransServerKey:  os.Getenv("MALVA_MIDTRANS_SERVER_KEY"),
		MidtransClientKey:  os.Getenv("MALVA_MIDTRANS_CLIENT_KEY"),
		MidtransEnv:        strings.ToLower(getenv("MALVA_MIDTRANS_ENV", "sandbox")),
		MidtransSnapBase:   strings.TrimRight(os.Getenv("MALVA_MIDTRANS_SNAP_BASE"), "/"),
		FonnteToken:        strings.TrimSpace(os.Getenv("MALVA_FONNTE_TOKEN")),
		FonnteBaseURL:      strings.TrimRight(getenv("MALVA_FONNTE_BASE_URL", "https://api.fonnte.com"), "/"),
		UploadDir:          getenv("MALVA_UPLOAD_DIR", "./uploads"),
		MaxImageSize:       5 << 20,  // 5 MB
		MaxVideoSize:       20 << 20, // 20 MB
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

// DatabaseURL mengembalikan URL koneksi database dari environment
// (MALVA_DATABASE_URL). Helper ini untuk CLI seperti cmd/admin dan cmd/promote
// yang hanya butuh URL database dan tidak perlu memuat Config penuh
// (yang mewajibkan MALVA_JWT_SECRET). Kode aplikasi utama tetap memakai
// config.Load().
func DatabaseURL() string {
	return os.Getenv("MALVA_DATABASE_URL")
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
