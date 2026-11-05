package server

import (
	"bytes"
	"crypto/sha256"
	"database/sql"
	"encoding/binary"
	"encoding/hex"
	"encoding/json"
	"errors"
	"image"
	_ "image/jpeg"
	_ "image/png"
	"io"
	"mime"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
	"malva/backend/internal/realtime"
	"malva/backend/internal/store"
)

const maxChatAttachmentSize = 10 << 20

type chatAttachmentMetadata struct {
	SessionID     string `json:"session_id"`
	AttachmentID  string `json:"attachment_id"`
	Filename      string `json:"filename"`
	MIME          string `json:"mime"`
	Size          int    `json:"size"`
	ContentSHA256 string `json:"content_sha256"`
}

func (s *Server) privateChatDir() string { return filepath.Clean(s.cfg.UploadDir) + "-chat-private" }

func validateChatAttachment(filename string, data []byte) (string, error) {
	bad := errors.New("berkas harus JPEG, PNG, WebP, atau PDF yang valid (maksimal 10 MiB)")
	if len(data) == 0 || len(data) > maxChatAttachmentSize {
		return "", bad
	}
	ext := strings.ToLower(filepath.Ext(filename))
	want := map[string]string{".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".png": "image/png", ".webp": "image/webp", ".pdf": "application/pdf"}[ext]
	if want == "" || http.DetectContentType(data) != want {
		return "", bad
	}
	if want == "image/jpeg" || want == "image/png" {
		cfg, _, err := image.DecodeConfig(bytes.NewReader(data))
		if err != nil || cfg.Width <= 0 || cfg.Height <= 0 || int64(cfg.Width)*int64(cfg.Height) > 100_000_000 {
			return "", bad
		}
	}
	if want == "application/pdf" && !bytes.Contains(data[max(0, len(data)-1024):], []byte("%%EOF")) {
		return "", bad
	}
	if want == "image/webp" {
		if len(data) < 20 || int(binary.LittleEndian.Uint32(data[4:8])) != len(data)-8 {
			return "", bad
		}
		imageFound := false
		for pos := 12; pos < len(data); {
			if len(data)-pos < 8 {
				return "", bad
			}
			size := int(binary.LittleEndian.Uint32(data[pos+4 : pos+8]))
			if size > len(data)-pos-8 {
				return "", bad
			}
			chunk := data[pos+8 : pos+8+size]
			switch string(data[pos : pos+4]) {
			case "VP8 ":
				if size < 10 || !bytes.Equal(chunk[3:6], []byte{0x9d, 0x01, 0x2a}) {
					return "", bad
				}
				imageFound = true
			case "VP8L":
				if size < 5 || chunk[0] != 0x2f {
					return "", bad
				}
				imageFound = true
			}
			pos += 8 + size + (size % 2)
			if pos > len(data) {
				return "", bad
			}
		}
		if !imageFound {
			return "", bad
		}
	}
	return want, nil
}

func (s *Server) uploadChatAttachment(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if !s.requireVerifiedProfessional(w, r, claims) {
		return
	}
	r.Body = http.MaxBytesReader(w, r.Body, maxChatAttachmentSize+(1<<20))
	if err := r.ParseMultipartForm(maxChatAttachmentSize); err != nil {
		writeError(w, http.StatusRequestEntityTooLarge, errors.New("unggahan maksimal 10 MiB"))
		return
	}
	defer func() { _ = r.MultipartForm.RemoveAll() }()
	recipientID := strings.TrimSpace(r.FormValue("recipient_id"))
	patientID, err := s.authorizePatientAccess(r, claims, recipientID)
	if err != nil || recipientID == "" {
		writeError(w, http.StatusForbidden, errors.New("pasien tidak terhubung"))
		return
	}
	access, ok := s.requireClinicalSession(w, r, claims, patientID)
	if !ok {
		return
	}
	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, errors.New("file wajib diisi"))
		return
	}
	defer func() { _ = file.Close() }()
	data, err := io.ReadAll(io.LimitReader(file, maxChatAttachmentSize+1))
	if err != nil {
		writeError(w, http.StatusBadRequest, errors.New("gagal membaca berkas"))
		return
	}
	filename := filepath.Base(strings.ReplaceAll(header.Filename, "\\", "/"))
	if len(filename) > 200 || strings.ContainsAny(filename, "\r\n\x00") {
		writeError(w, http.StatusBadRequest, errors.New("nama berkas tidak valid"))
		return
	}
	contentType, err := validateChatAttachment(filename, data)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	messageID := generateChatMessageID()
	if clientID := r.FormValue("client_message_id"); clientID != "" {
		if !store.ValidClinicalClientID(clientID) {
			writeError(w, http.StatusBadRequest, errors.New("client_message_id harus UUID"))
			return
		}
		messageID = store.ClinicalRetryID("message", claims.Subject, clientID)
	}
	hash := sha256.Sum256(data)
	meta, _ := json.Marshal(chatAttachmentMetadata{SessionID: access.SessionID, AttachmentID: messageID, Filename: filename, MIME: contentType, Size: len(data), ContentSHA256: hex.EncodeToString(hash[:])})
	// Files are immutable; a retry can reuse a persisted message but cannot
	// overwrite bytes belonging to a previous request with the same key.
	if previous, err := s.store.GetChatAttachment(r.Context(), messageID, claims.Subject); err == nil {
		var previousMeta chatAttachmentMetadata
		_ = json.Unmarshal(previous.Metadata, &previousMeta)
		var incomingMeta chatAttachmentMetadata
		_ = json.Unmarshal(meta, &incomingMeta)
		if previous.PatientID != patientID || previous.ProfessionalID != claims.Subject || previousMeta != incomingMeta {
			writeError(w, http.StatusConflict, errors.New("kunci unggahan sudah digunakan untuk berkas lain"))
			return
		}
		writeJSON(w, http.StatusCreated, map[string]any{"message": previous})
		return
	} else if !errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusInternalServerError, errors.New("gagal memeriksa unggahan"))
		return
	}
	if err := os.MkdirAll(s.privateChatDir(), 0700); err != nil {
		writeError(w, http.StatusInternalServerError, errors.New("penyimpanan privat tidak tersedia"))
		return
	}
	dest := filepath.Join(s.privateChatDir(), messageID)
	out, err := os.CreateTemp(s.privateChatDir(), ".upload-*")
	if err != nil {
		writeError(w, http.StatusInternalServerError, errors.New("gagal membuat unggahan privat"))
		return
	}
	defer func() { _ = os.Remove(out.Name()) }()
	_, writeErr := out.Write(data)
	if writeErr == nil {
		writeErr = out.Sync()
	}
	closeErr := out.Close()
	if writeErr != nil || closeErr != nil {
		writeError(w, http.StatusInternalServerError, errors.New("gagal menyimpan berkas"))
		return
	}
	// A hard link publishes complete bytes without replacing an existing file.
	// A retry can also recover a completed file left before a process exit.
	linkErr := os.Link(out.Name(), dest)
	if linkErr != nil {
		if !errors.Is(linkErr, os.ErrExist) {
			writeError(w, http.StatusInternalServerError, errors.New("gagal menerbitkan berkas privat"))
			return
		}
		existing, readErr := os.ReadFile(dest)
		if readErr != nil || len(existing) != len(data) || sha256.Sum256(existing) != hash {
			writeError(w, http.StatusConflict, errors.New("kunci unggahan sudah digunakan untuk berkas lain"))
			return
		}
	}
	senderName := ""
	if user, err := s.store.GetUserByID(r.Context(), claims.Subject); err == nil {
		senderName = user.DisplayName
	}
	saved, err := s.store.CreateChatMessage(r.Context(), store.ChatMessage{ID: messageID, PatientID: patientID, ProfessionalID: claims.Subject, SenderID: claims.Subject, SenderName: senderName, Kind: "attachment", Text: filename, Metadata: meta, CreatedAt: clock.Now()})
	if err != nil {
		// Keep immutable bytes on an uncertain DB failure: another retry may
		// already have persisted this ID. Files without a message stay private.
		writeError(w, http.StatusConflict, errors.New("gagal menyimpan pesan unggahan"))
		return
	}
	if s.hub != nil {
		event := realtime.Event{Type: "chat_message", Data: map[string]any{"id": saved.ID, "sender_id": saved.SenderID, "sender_name": saved.SenderName, "recipient_id": patientID, "text": saved.Text, "kind": saved.Kind, "metadata": saved.Metadata, "timestamp": saved.CreatedAt.Format(time.RFC3339)}}
		s.hub.Publish(patientID, event)
		s.hub.Publish(claims.Subject, event)
	}
	writeJSON(w, http.StatusCreated, map[string]any{"message": saved})
}

func (s *Server) getChatAttachment(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	id := r.PathValue("attachment_id")
	if !store.ValidClinicalClientID(id) {
		http.NotFound(w, r)
		return
	}
	msg, err := s.store.GetChatAttachment(r.Context(), id, claims.Subject)
	if err != nil {
		http.NotFound(w, r)
		return
	}
	var meta chatAttachmentMetadata
	if json.Unmarshal(msg.Metadata, &meta) != nil {
		http.NotFound(w, r)
		return
	}
	file, err := os.Open(filepath.Join(s.privateChatDir(), id))
	if err != nil {
		http.NotFound(w, r)
		return
	}
	defer func() { _ = file.Close() }()
	info, err := file.Stat()
	if err != nil {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Cache-Control", "private, no-store")
	w.Header().Set("X-Content-Type-Options", "nosniff")
	w.Header().Set("Content-Type", meta.MIME)
	w.Header().Set("Content-Disposition", mime.FormatMediaType("attachment", map[string]string{"filename": meta.Filename}))
	http.ServeContent(w, r, meta.Filename, info.ModTime(), file)
}
