package notify

import (
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"testing"

	"malva/backend/internal/config"
)

func discardLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
}

// Regresi: NewProvider tanpa ProjectID menyebabkan crash-loop
// ("project ID is required to access Firebase Cloud Messaging client").
func TestNewProviderMendeteksiProjectID(t *testing.T) {
	// 1) Tanpa kredensial -> no-op provider (API tetap hidup).
	p, err := NewProvider(t.Context(), config.Config{}, discardLogger())
	if err != nil {
		t.Fatalf("tanpa kredensial harus no-op, bukan error: %v", err)
	}
	if _, ok := p.(noopProvider); !ok {
		t.Fatalf("tanpa kredensial harus noopProvider, dapat %T", p)
	}

	// 2) Kredensial JSON inline lengkap -> NewProvider TIDAK boleh gagal
	// dengan error "project ID is required" (uji tanpa akses jaringan).
	jsonKey := `{"type":"service_account","project_id":"malva-7084e",` +
		`"private_key_id":"abc","private_key":"-----BEGIN PRIVATE KEY-----\nfake\n-----END PRIVATE KEY-----\n",` +
		`"client_email":"fake@malva-7084e.iam.gserviceaccount.com"}`
	if got := detectProjectID(config.Config{FCMCredentialsJSON: jsonKey}); got != "malva-7084e" {
		t.Errorf("detectProjectID JSON = %q, want malva-7084e", got)
	}

	// 3) File kredensial ada -> terbaca project_id-nya.
	path := filepath.Join(t.TempDir(), "sa.json")
	if err := os.WriteFile(path, []byte(jsonKey), 0600); err != nil {
		t.Fatal(err)
	}
	if got := detectProjectID(config.Config{FCMCredentialsFile: path}); got != "malva-7084e" {
		t.Errorf("detectProjectID file = %q, want malva-7084e", got)
	}

	// 4) File hilang -> "" (bukan crash), NewProvider mengembalikan
	// errNoProjectID yang jelas, bukan error samar dari SDK.
	if got := detectProjectID(config.Config{FCMCredentialsFile: "/tidak/ada.json"}); got != "" {
		t.Errorf("detectProjectID file hilang = %q, want \"\"", got)
	}
	if p, perr := NewProvider(t.Context(), config.Config{FCMCredentialsFile: "/tidak/ada.json"}, discardLogger()); perr == nil {
		t.Errorf("file hilang harus gagal, dapat %T", p)
	}

	// 5) JSON bukan service account (tanpa project_id) -> errNoProjectID.
	p, err = NewProvider(t.Context(), config.Config{FCMCredentialsJSON: `{"type":"authorized_user"}`}, discardLogger())
	if err == nil {
		t.Fatal("kredensial tanpa project_id harus gagal")
	}
	// 6) ENV eksplisit menang atas kredensial (operator override).
	over := config.Config{FCMProjectID: "override-proj", FCMCredentialsJSON: jsonKey}
	if got := over.FCMProjectID; got != "override-proj" {
		t.Errorf("config FCMProjectID = %q, want override-proj", got)
	}

	_ = p
}
