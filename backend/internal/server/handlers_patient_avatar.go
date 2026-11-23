package server

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"errors"
	"image"
	"net/http"
	"os"
	"path"
	"path/filepath"
	"strings"
	"sync"

	"malva/backend/internal/auth"
	"malva/backend/internal/store"
)

const maxPatientAvatarBytes = 192 << 10

type publicUploadsFS struct{ http.Dir }

func (fs publicUploadsFS) Open(name string) (http.File, error) {
	if strings.ContainsAny(name, `\:`) {
		return nil, os.ErrNotExist
	}
	clean := path.Clean("/" + name)
	first := strings.Split(strings.TrimPrefix(clean, "/"), "/")[0]
	if strings.EqualFold(strings.TrimRight(first, ". "), ".patient-avatars") {
		return nil, os.ErrNotExist
	}
	// Resolve aliases before serving: a public symlink or Windows short path
	// must not turn into a second route to the private directory.
	root, err := filepath.EvalSymlinks(string(fs.Dir))
	if err != nil {
		return nil, os.ErrNotExist
	}
	resolved, err := filepath.EvalSymlinks(filepath.Join(string(fs.Dir), filepath.FromSlash(strings.TrimPrefix(clean, "/"))))
	if err != nil {
		return nil, os.ErrNotExist
	}
	relative, err := filepath.Rel(root, resolved)
	if err != nil || relative == ".." || strings.HasPrefix(relative, ".."+string(filepath.Separator)) || strings.EqualFold(strings.Split(filepath.ToSlash(relative), "/")[0], ".patient-avatars") {
		return nil, os.ErrNotExist
	}
	file, err := fs.Dir.Open(clean)
	if err == nil {
		info, statErr := file.Stat()
		if statErr != nil || info.IsDir() {
			_ = file.Close()
			return nil, os.ErrNotExist
		}
	}
	return file, err
}

// The directory stays on the existing uploads volume, but Routes explicitly
// denies its public static path. Only the authenticated JSON endpoint reads it.
func (s *Server) patientAvatarPath(userID string) string {
	return filepath.Join(s.cfg.UploadDir, ".patient-avatars", userID+".json")
}

var patientAvatarWriteMu sync.Mutex

func validPatientAvatar(avatar string) bool {
	if avatar == "default" {
		return true
	}
	for _, name := range []string{"1", "2", "3", "4", "5"} {
		if avatar == "assets/reference/avatar-"+name+".png" {
			return true
		}
	}
	data, err := base64.StdEncoding.DecodeString(avatar)
	if err != nil || len(data) == 0 || len(data) > maxPatientAvatarBytes {
		return false
	}
	config, format, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil || (format != "png" && format != "jpeg") || config.Width <= 0 || config.Height <= 0 || config.Width > 4096 || config.Height > 4096 || int64(config.Width)*int64(config.Height) > 16_000_000 {
		return false
	}
	_, _, err = image.Decode(bytes.NewReader(data))
	return err == nil
}

type patientAvatarPayload struct {
	Avatar *string `json:"avatar"`
}

func (s *Server) readPatientAvatar(userID string) (patientAvatarPayload, error) {
	var payload patientAvatarPayload
	data, err := os.ReadFile(s.patientAvatarPath(userID))
	if errors.Is(err, os.ErrNotExist) {
		return payload, nil
	}
	if err != nil {
		return payload, err
	}
	err = json.Unmarshal(data, &payload)
	return payload, err
}

func (s *Server) getPatientAvatar(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	w.Header().Set("Cache-Control", "private, no-store")
	patientID := strings.TrimSpace(r.URL.Query().Get("patient_id"))
	if patientID == "" {
		patientID = claims.Subject
	}
	if !store.ValidClinicalClientID(patientID) {
		http.NotFound(w, r)
		return
	}
	allowed := claims.Role == "patient" && patientID == claims.Subject
	if !allowed && claims.Role == "professional" {
		links, err := s.store.ListPatientProfessionalLinks(r.Context(), claims.Subject, claims.Role)
		if err != nil {
			writeError(w, 500, errors.New("gagal memeriksa akses avatar"))
			return
		}
		for _, link := range links {
			if link.PatientID == patientID {
				allowed = true
				break
			}
		}
	}
	if !allowed {
		http.NotFound(w, r)
		return
	}
	payload, err := s.readPatientAvatar(patientID)
	if err != nil {
		writeError(w, 500, errors.New("gagal membaca avatar"))
		return
	}
	writeJSON(w, http.StatusOK, payload)
}

func (s *Server) putPatientAvatar(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	w.Header().Set("Cache-Control", "private, no-store")
	if claims.Role != "patient" || !store.ValidClinicalClientID(claims.Subject) {
		writeError(w, http.StatusForbidden, errors.New("hanya pasien dapat memperbarui avatarnya"))
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, (maxPatientAvatarBytes*4/3)+1024)
	var payload patientAvatarPayload
	if err := readJSON(r, &payload); err != nil || payload.Avatar == nil || !validPatientAvatar(*payload.Avatar) {
		writeError(w, http.StatusBadRequest, errors.New("avatar tidak valid; gunakan JPEG/PNG maksimal 192 KiB"))
		return
	}
	patientAvatarWriteMu.Lock()
	defer patientAvatarWriteMu.Unlock()
	if r.Header.Get("If-None-Match") == "*" {
		current, err := s.readPatientAvatar(claims.Subject)
		if err != nil {
			writeError(w, 500, errors.New("gagal membaca avatar"))
			return
		}
		if current.Avatar != nil {
			writeJSON(w, http.StatusOK, current)
			return
		}
	}
	path := s.patientAvatarPath(claims.Subject)
	if err := os.MkdirAll(filepath.Dir(path), 0700); err != nil {
		writeError(w, 500, errors.New("penyimpanan avatar tidak tersedia"))
		return
	}
	file, err := os.CreateTemp(filepath.Dir(path), ".avatar-*")
	if err != nil {
		writeError(w, 500, errors.New("gagal menyimpan avatar"))
		return
	}
	defer func() { _ = os.Remove(file.Name()) }()
	err = json.NewEncoder(file).Encode(payload)
	closeErr := file.Close()
	if err != nil || closeErr != nil || os.Rename(file.Name(), path) != nil {
		writeError(w, 500, errors.New("gagal menyimpan avatar"))
		return
	}
	writeJSON(w, http.StatusOK, payload)
}
