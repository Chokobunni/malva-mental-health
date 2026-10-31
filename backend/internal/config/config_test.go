package config

import "testing"

func TestLoadRequiresDatabaseURL(t *testing.T) {
	t.Setenv("MALVA_DATABASE_URL", "")
	t.Setenv("MALVA_JWT_SECRET", "12345678901234567890123456789012")

	if _, err := Load(); err == nil {
		t.Fatal("expected missing database URL to fail")
	}
}

func TestLoadRequiresStrongJWTSecret(t *testing.T) {
	t.Setenv("MALVA_DATABASE_URL", "postgres://malva:pass@127.0.0.1:5432/malva?sslmode=disable")
	t.Setenv("MALVA_JWT_SECRET", "short")

	if _, err := Load(); err == nil {
		t.Fatal("expected short JWT secret to fail")
	}
}

func TestLoadGatewayModeRequiresMidtransServerKey(t *testing.T) {
	t.Setenv("MALVA_DATABASE_URL", "postgres://malva:pass@127.0.0.1:5432/malva?sslmode=disable")
	t.Setenv("MALVA_JWT_SECRET", "12345678901234567890123456789012")
	t.Setenv("MALVA_PAYMENT_MODE", "gateway")
	t.Setenv("MALVA_MIDTRANS_SERVER_KEY", "")

	if _, err := Load(); err == nil {
		t.Fatal("expected gateway mode without server key to fail")
	}
}

func TestLoadDefaultsToSimulationMode(t *testing.T) {
	t.Setenv("MALVA_DATABASE_URL", "postgres://malva:pass@127.0.0.1:5432/malva?sslmode=disable")
	t.Setenv("MALVA_JWT_SECRET", "12345678901234567890123456789012")
	t.Setenv("MALVA_PAYMENT_MODE", "")
	t.Setenv("MALVA_MIDTRANS_SERVER_KEY", "")

	cfg, err := Load()
	if err != nil {
		t.Fatalf("simulation mode should load: %v", err)
	}
	if cfg.PaymentMode != PaymentModeSimulation {
		t.Fatalf("expected simulation mode, got %q", cfg.PaymentMode)
	}
}

func TestOriginAllowedUsesExactConfiguredOrigins(t *testing.T) {
	cfg := Config{
		AllowedOrigins: []string{
			"https://api.malva.id",
			"https://malva.id",
		},
	}

	if !cfg.OriginAllowed("") {
		t.Fatal("mobile/native requests without Origin should be allowed")
	}
	if !cfg.OriginAllowed("https://api.malva.id") {
		t.Fatal("configured origin should be allowed")
	}
	if cfg.OriginAllowed("https://evil.example") {
		t.Fatal("unconfigured origin should not be allowed")
	}
}

// TestLoadGoogleRefreshTokenTTLDays memastikan MALVA_GOOGLE_REFRESH_TOKEN_TTL_DAYS
// diparse sebagai int, default 7, dan nilai tidak valid jatuh ke default.
func TestLoadGoogleRefreshTokenTTLDays(t *testing.T) {
	base := func(t *testing.T) {
		t.Setenv("MALVA_DATABASE_URL", "postgres://malva:pass@127.0.0.1:5432/malva?sslmode=disable")
		t.Setenv("MALVA_JWT_SECRET", "12345678901234567890123456789012")
		t.Setenv("MALVA_PAYMENT_MODE", "")
	}

	t.Run("default 7 saat kosong", func(t *testing.T) {
		base(t)
		t.Setenv("MALVA_GOOGLE_REFRESH_TOKEN_TTL_DAYS", "")
		cfg, err := Load()
		if err != nil {
			t.Fatalf("load: %v", err)
		}
		if cfg.GoogleRefreshTokenTTLDays != 7 {
			t.Fatalf("TTL default = %d, mau 7", cfg.GoogleRefreshTokenTTLDays)
		}
	})

	t.Run("nilai valid dipakai", func(t *testing.T) {
		base(t)
		t.Setenv("MALVA_GOOGLE_REFRESH_TOKEN_TTL_DAYS", "14")
		cfg, err := Load()
		if err != nil {
			t.Fatalf("load: %v", err)
		}
		if cfg.GoogleRefreshTokenTTLDays != 14 {
			t.Fatalf("TTL = %d, mau 14", cfg.GoogleRefreshTokenTTLDays)
		}
	})

	t.Run("nilai tidak valid jatuh ke default", func(t *testing.T) {
		base(t)
		t.Setenv("MALVA_GOOGLE_REFRESH_TOKEN_TTL_DAYS", "tujuh")
		cfg, err := Load()
		if err != nil {
			t.Fatalf("load: %v", err)
		}
		if cfg.GoogleRefreshTokenTTLDays != 7 {
			t.Fatalf("TTL = %d, mau 7 (fallback)", cfg.GoogleRefreshTokenTTLDays)
		}
	})
}
