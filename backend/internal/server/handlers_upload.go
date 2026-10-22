package server

// Handler unggah berkas (foto/video) untuk profil profesional.
// Endpoint: POST /v1/upload — menerima multipart/form-data dengan field "file".
// Validasi MIME type dan ukuran dilakukan server-side; nama berkas dibuat unik
// agar tidak bisa ditebak atau ditimpa oleh pengguna lain.

import (
	"crypto/rand"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"malva/backend/internal/auth"
)

// mimeTypesAllowed memetakan ekstensi yang diizinkan beserta MIME type-nya.
var mimeTypesAllowed = map[string]string{
	".jpg":  "image/jpeg",
	".jpeg": "image/jpeg",
	".png":  "image/png",
	".webp": "image/webp",
	".mp4":  "video/mp4",
}

// isImageExt mengembalikan true bila ekstensi termasuk gambar.
func isImageExt(ext string) bool {
	switch ext {
	case ".jpg", ".jpeg", ".png", ".webp":
		return true
	}
	return false
}

// uploadFile menangani POST /v1/upload — menyimpan berkas ke disk lokal.
func (s *Server) uploadFile(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	// Batasi ukuran body permintaan agar tidak memakan memori berlebihan.
	maxBody := s.cfg.MaxVideoSize + 1024 // toleransi overhead multipart
	r.Body = http.MaxBytesReader(w, r.Body, maxBody)

	if err := r.ParseMultipartForm(maxBody); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "Gagal memproses unggahan. Pastikan ukuran berkas tidak melebihi batas.",
		})
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": "Field 'file' wajib diisi dalam form-data.",
		})
		return
	}
	defer func() { _ = file.Close() }()

	// Ekstrak ekstensi dari nama berkas asli.
	ext := strings.ToLower(filepath.Ext(header.Filename))
	expectedMIME, ok := mimeTypesAllowed[ext]
	if !ok {
		writeJSON(w, http.StatusBadRequest, map[string]string{
			"error": fmt.Sprintf("Format berkas '%s' tidak didukung. Gunakan JPEG, PNG, WebP, atau MP4.", ext),
		})
		return
	}

	// Validasi ukuran berdasarkan tipe media.
	maxSize := s.cfg.MaxImageSize
	if !isImageExt(ext) {
		maxSize = s.cfg.MaxVideoSize
	}
	if header.Size > maxSize {
		writeJSON(w, http.StatusRequestEntityTooLarge, map[string]string{
			"error": fmt.Sprintf("Ukuran berkas (%d byte) melebihi batas %d byte.", header.Size, maxSize),
		})
		return
	}

	// Buat direktori tujuan per-pengguna: uploads/{userID}/
	userDir := filepath.Join(s.cfg.UploadDir, claims.Subject)
	if err := os.MkdirAll(userDir, 0o755); err != nil {
		s.logger.Error("gagal membuat direktori unggahan", "path", userDir, "err", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "Gagal menyimpan berkas. Silakan coba lagi.",
		})
		return
	}

	// Nama berkas unik: {timestamp}_{random}.{ext}
	randomBytes := make([]byte, 8)
	if _, err := rand.Read(randomBytes); err != nil {
		s.logger.Error("gagal menghasilkan nama acak", "err", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "Gagal menyimpan berkas. Silakan coba lagi.",
		})
		return
	}
	filename := fmt.Sprintf("%d_%s%s", time.Now().UnixMilli(), hex.EncodeToString(randomBytes), ext)
	destPath := filepath.Join(userDir, filename)

	dst, err := os.Create(destPath)
	if err != nil {
		s.logger.Error("gagal membuat berkas tujuan", "path", destPath, "err", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "Gagal menyimpan berkas. Silakan coba lagi.",
		})
		return
	}
	defer func() { _ = dst.Close() }()

	written, err := io.Copy(dst, file)
	if err != nil {
		s.logger.Error("gagal menulis berkas", "path", destPath, "err", err)
		// Bersihkan berkas parsial.
		_ = os.Remove(destPath)
		writeJSON(w, http.StatusInternalServerError, map[string]string{
			"error": "Gagal menyimpan berkas. Silakan coba lagi.",
		})
		return
	}

	// URL relatif yang bisa diakses lewat static file server.
	urlPath := fmt.Sprintf("/uploads/%s/%s", claims.Subject, filename)

	writeJSON(w, http.StatusOK, map[string]interface{}{
		"url":      urlPath,
		"filename": filename,
		"size":     written,
		"mime":     expectedMIME,
	})
}
