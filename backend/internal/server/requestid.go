package server

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"net/http"
)

// requestIDKey adalah tipe kunci context untuk Request ID. Memakai tipe
// privat (bukan string) agar tidak bentrok dengan nilai context lain.
type requestIDKey struct{}

// RequestIDFromContext mengambil Request ID dari context dengan pola
// "comma-ok". Mengembalikan ok=false bila tidak ada (mis. di luar middleware).
func RequestIDFromContext(ctx context.Context) (string, bool) {
	id, ok := ctx.Value(requestIDKey{}).(string)
	return id, ok
}

// requestID adalah middleware yang memastikan setiap request memiliki
// X-Request-Id yang valid, menyimpannya ke context, dan mengembalikannya
// di header respons. Nilai dari klien dipertahankan bila valid; bila tidak,
// dibuat baru (16 byte acak -> hex 32 karakter).
func (s *Server) requestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		id := r.Header.Get("X-Request-Id")
		if !validRequestID(id) {
			id = newRequestID()
		}
		w.Header().Set("X-Request-Id", id)
		ctx := context.WithValue(r.Context(), requestIDKey{}, id)
		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// validRequestID menerima panjang 1..64 karakter dan hanya karakter
// [A-Za-z0-9._-]. Nilai lain dianggap tidak valid dan akan di-regenerate.
func validRequestID(id string) bool {
	if len(id) < 1 || len(id) > 64 {
		return false
	}
	for i := 0; i < len(id); i++ {
		c := id[i]
		switch {
		case c >= 'A' && c <= 'Z':
		case c >= 'a' && c <= 'z':
		case c >= '0' && c <= '9':
		case c == '.' || c == '_' || c == '-':
		default:
			return false
		}
	}
	return true
}

// newRequestID menghasilkan 16 byte acak dalam bentuk hex (32 karakter).
func newRequestID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		// crypto/rand praktis tak pernah gagal; bila gagal, pakai nilai
		// deterministik agar header tetap terisi (tidak panik).
		return "00000000000000000000000000000000"
	}
	return hex.EncodeToString(b[:])
}
