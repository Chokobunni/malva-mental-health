package logging

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

func TestNewProducesJSONWithService(t *testing.T) {
	var buf bytes.Buffer
	logger := New("debug", &buf)
	logger.Info("halo", "key", "value")

	out := buf.String()
	if !strings.Contains(out, `"service":"malva-api"`) {
		t.Fatalf("log harus memuat service=malva-api, dapat: %s", out)
	}
	if !strings.Contains(out, `"msg":"halo"`) {
		t.Fatalf("log harus memuat pesan, dapat: %s", out)
	}
	// Harus JSON valid per baris.
	var m map[string]any
	if err := json.Unmarshal(bytes.TrimSpace(buf.Bytes()), &m); err != nil {
		t.Fatalf("output bukan JSON valid: %v (%s)", err, out)
	}
	if m["service"] != "malva-api" {
		t.Fatalf("field service salah: %v", m["service"])
	}
}

func TestLevelErrorFiltersInfo(t *testing.T) {
	var buf bytes.Buffer
	logger := New("error", &buf)
	logger.Info("tidak-boleh-muncul")
	logger.Error("boom")

	out := buf.String()
	if strings.Contains(out, "tidak-boleh-muncul") {
		t.Fatalf("level error harus menyaring Info, dapat: %s", out)
	}
	if !strings.Contains(out, "boom") {
		t.Fatalf("level error harus meloloskan Error, dapat: %s", out)
	}
}

func TestErrAttrNilSafe(t *testing.T) {
	if attr := Err(nil); attr.Key != "error" {
		t.Fatalf("Err(nil) harus menghasilkan attr key=error, dapat %q", attr.Key)
	}
}
