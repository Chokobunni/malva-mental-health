package server

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"image"
	"io"
	"net/http"
	"net/url"
	"os"
	"path/filepath"
	"strings"

	"malva/backend/internal/auth"
	"malva/backend/internal/store"
)

const maxDiaryImageSize = 5 << 20

func (s *Server) privateDiaryDir() string { return filepath.Clean(s.cfg.UploadDir) + "-diary-private" }

// Diary media is intentionally separate from the public professional uploads.
// The existing diary note carries references; no file name supplied by a user
// becomes part of a stored path.
func (s *Server) uploadDiaryImage(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	w.Header().Set("Cache-Control", "private, no-store")
	if claims.Role != "patient" || !store.ValidClinicalClientID(claims.Subject) {
		writeError(w, http.StatusForbidden, errors.New("hanya pasien dapat mengunggah gambar diary"))
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxDiaryImageSize+(1<<20))
	if err := r.ParseMultipartForm(maxDiaryImageSize); err != nil {
		writeError(w, http.StatusRequestEntityTooLarge, errors.New("gambar maksimal 5 MiB"))
		return
	}
	defer func() { _ = r.MultipartForm.RemoveAll() }()
	file, _, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, errors.New("file wajib diisi"))
		return
	}
	defer func() { _ = file.Close() }()
	data, err := io.ReadAll(io.LimitReader(file, maxDiaryImageSize+1))
	if err != nil {
		writeError(w, http.StatusBadRequest, errors.New("gagal membaca gambar"))
		return
	}
	if len(data) > maxDiaryImageSize {
		writeError(w, http.StatusRequestEntityTooLarge, errors.New("gambar maksimal 5 MiB"))
		return
	}
	mimeType := http.DetectContentType(data)
	ext := map[string]string{"image/jpeg": ".jpg", "image/png": ".png"}[mimeType]
	config, format, configErr := image.DecodeConfig(bytes.NewReader(data))
	if ext == "" || configErr != nil || (format != "jpeg" && format != "png") || config.Width <= 0 || config.Height <= 0 || config.Width > 4096 || config.Height > 4096 || int64(config.Width)*int64(config.Height) > 16_000_000 {
		writeError(w, http.StatusBadRequest, errors.New("gunakan gambar JPEG atau PNG valid, maksimal 4096 piksel per sisi dan 16 megapiksel"))
		return
	}
	// Decode only after bounding allocation, rejecting truncated/corrupt pixels
	// that a valid header alone cannot detect.
	if _, _, err := image.Decode(bytes.NewReader(data)); err != nil {
		writeError(w, http.StatusBadRequest, errors.New("gambar rusak atau tidak lengkap"))
		return
	}
	randomBytes := make([]byte, 16)
	if _, err := rand.Read(randomBytes); err != nil {
		writeError(w, http.StatusInternalServerError, errors.New("gagal membuat nama gambar privat"))
		return
	}
	filename := hex.EncodeToString(randomBytes) + ext
	dir := filepath.Join(s.privateDiaryDir(), claims.Subject)
	if err := os.MkdirAll(dir, 0700); err != nil {
		writeError(w, http.StatusInternalServerError, errors.New("penyimpanan privat tidak tersedia"))
		return
	}
	dest := filepath.Join(dir, filename)
	out, err := os.OpenFile(dest, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		writeError(w, http.StatusInternalServerError, errors.New("gagal menyimpan gambar privat"))
		return
	}
	_, writeErr := out.Write(data)
	closeErr := out.Close()
	if writeErr != nil || closeErr != nil {
		_ = os.Remove(dest)
		writeError(w, http.StatusInternalServerError, errors.New("gagal menyimpan gambar privat"))
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{
		"url":      "/v1/diary-media/" + claims.Subject + "/" + filename,
		"filename": filename, "size": len(data), "mime": mimeType,
	})
}

func diaryNoteReferencesMedia(note, mediaPath string) bool {
	const marker = "<!--malva-diary-v1:"
	start := strings.LastIndex(note, marker)
	if start < 0 || !strings.HasSuffix(note, "-->") {
		return false
	}
	if start > 0 && (start < 2 || note[start-2:start] != "\n\n") {
		return false
	}
	encoded := note[start+len(marker) : len(note)-3]
	data, err := base64.RawURLEncoding.DecodeString(strings.TrimRight(encoded, "="))
	if err != nil {
		return false
	}
	var metadata struct {
		Media []struct {
			URL string `json:"url"`
		} `json:"media"`
	}
	if json.Unmarshal(data, &metadata) != nil {
		return false
	}
	for _, media := range metadata.Media {
		u, err := url.Parse(media.URL)
		if err == nil && (u.Scheme == "" || u.Scheme == "http" || u.Scheme == "https") && u.Path == mediaPath && u.RawQuery == "" && u.Fragment == "" {
			return true
		}
	}
	return false
}

func (s *Server) getDiaryImage(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	w.Header().Set("Cache-Control", "private, no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	patientID, filename := r.PathValue("patient_id"), r.PathValue("filename")
	ext := filepath.Ext(filename)
	randomPart := strings.TrimSuffix(filename, ext)
	decoded, err := hex.DecodeString(randomPart)
	if !store.ValidClinicalClientID(patientID) || len(decoded) != 16 || err != nil || (ext != ".jpg" && ext != ".png") || filename != strings.ToLower(filename) {
		http.NotFound(w, r)
		return
	}
	if claims.Role != "patient" || claims.Subject != patientID {
		if claims.Role != "professional" {
			http.NotFound(w, r)
			return
		}
		if _, err := s.authorizePatientAccess(r, claims, patientID); err != nil || !s.consentAllows(r, patientID, claims.Subject, "mood_diary") {
			http.NotFound(w, r)
			return
		}
		entries, err := s.store.ListDiaryEntries(r.Context(), patientID, true, 0)
		if err != nil {
			writeError(w, http.StatusInternalServerError, errors.New("gagal memeriksa akses gambar diary"))
			return
		}
		referenced := false
		for _, entry := range entries {
			if diaryNoteReferencesMedia(entry.Note, r.URL.Path) {
				referenced = true
				break
			}
		}
		if !referenced {
			http.NotFound(w, r)
			return
		}
	}
	file, err := os.Open(filepath.Join(s.privateDiaryDir(), patientID, filename))
	if err != nil {
		http.NotFound(w, r)
		return
	}
	defer func() { _ = file.Close() }()
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", map[string]string{".jpg": "image/jpeg", ".png": "image/png"}[ext])
	w.Header().Set("Content-Disposition", "inline")
	http.ServeContent(w, r, filename, info.ModTime(), file)
}
