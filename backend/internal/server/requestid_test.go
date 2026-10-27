package server

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// captureID menjalankan middleware requestID dengan header tertentu dan
// mengembalikan id dari context, ok, serta nilai header respons.
func captureID(t *testing.T, header string) (ctxID string, ok bool, respHeader string) {
	t.Helper()
	s := &Server{}
	h := s.requestID(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		ctxID, ok = RequestIDFromContext(r.Context())
	}))
	req := httptest.NewRequest(http.MethodGet, "/v1/me", nil)
	if header != "" {
		req.Header.Set("X-Request-Id", header)
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return ctxID, ok, rec.Header().Get("X-Request-Id")
}

func isHex32(s string) bool {
	if len(s) != 32 {
		return false
	}
	for _, c := range s {
		if (c < '0' || c > '9') && (c < 'a' || c > 'f') {
			return false
		}
	}
	return true
}

func TestRequestIDPreservesValidHeader(t *testing.T) {
	const valid = "abc-123_DEF.4"
	ctxID, ok, respHeader := captureID(t, valid)
	if !ok {
		t.Fatal("RequestIDFromContext harus ok=true di dalam handler")
	}
	if ctxID != valid {
		t.Fatalf("id valid harus dipertahankan, dapat %q", ctxID)
	}
	if respHeader != valid {
		t.Fatalf("header respons harus sama, dapat %q", respHeader)
	}
}

func TestRequestIDGeneratedWhenAbsent(t *testing.T) {
	ctxID, ok, respHeader := captureID(t, "")
	if !ok {
		t.Fatal("RequestIDFromContext harus ok=true")
	}
	if !isHex32(ctxID) {
		t.Fatalf("id ter-generate harus 32 hex, dapat %q", ctxID)
	}
	if respHeader != ctxID {
		t.Fatalf("header respons harus sama dengan id context: %q vs %q", respHeader, ctxID)
	}
}

func TestRequestIDRegeneratedWhenInvalid(t *testing.T) {
	cases := []string{
		"<script>alert(1)</script>",
		strings.Repeat("a", 100), // melebihi 64 karakter
		"has space",
	}
	for _, bad := range cases {
		ctxID, ok, _ := captureID(t, bad)
		if !ok {
			t.Fatalf("RequestIDFromContext harus ok=true untuk input %q", bad)
		}
		if ctxID == bad {
			t.Fatalf("header tidak valid %q seharusnya di-regenerate", bad)
		}
		if !isHex32(ctxID) {
			t.Fatalf("id hasil regenerate harus 32 hex, dapat %q", ctxID)
		}
	}
}

func TestRequestIDUniquePerRequest(t *testing.T) {
	first, _, _ := captureID(t, "")
	second, _, _ := captureID(t, "")
	if first == second {
		t.Fatalf("dua request berbeda harus menghasilkan id berbeda: %q", first)
	}
}
