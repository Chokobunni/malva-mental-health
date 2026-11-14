package server

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/binary"
	"encoding/json"
	"hash/crc32"
	"image"
	"image/jpeg"
	"image/png"
	"mime/multipart"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"

	"malva/backend/internal/store"
)

const diaryMediaPatient = "11111111-1111-4111-8111-111111111111"

func diaryTestPNG(t *testing.T) []byte {
	t.Helper()
	var b bytes.Buffer
	if err := png.Encode(&b, image.NewNRGBA(image.Rect(0, 0, 2, 2))); err != nil {
		t.Fatal(err)
	}
	return b.Bytes()
}

func uploadDiaryTestImage(t *testing.T, s *Server, token, name string, data []byte) *httptest.ResponseRecorder {
	t.Helper()
	var b bytes.Buffer
	mw := multipart.NewWriter(&b)
	part, err := mw.CreateFormFile("file", name)
	if err != nil {
		t.Fatal(err)
	}
	_, _ = part.Write(data)
	_ = mw.Close()
	req := httptest.NewRequest("POST", "/v1/diary-media", &b)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	out := httptest.NewRecorder()
	s.Routes().ServeHTTP(out, req)
	return out
}

func diaryUploadURL(t *testing.T, out *httptest.ResponseRecorder) string {
	t.Helper()
	if out.Code != 201 {
		t.Fatalf("upload %d: %s", out.Code, out.Body)
	}
	var body struct {
		URL string `json:"url"`
	}
	if err := json.Unmarshal(out.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	return body.URL
}

func TestDiaryMediaPrivateUploadAndOwnerRead(t *testing.T) {
	s, _, professional := newSafetyTestServer()
	s.cfg.UploadDir = filepath.Join(t.TempDir(), "public")
	owner, _ := s.auth.Issue(diaryMediaPatient, "patient")
	data := diaryTestPNG(t)
	url := diaryUploadURL(t, uploadDiaryTestImage(t, s, owner, "private-original-name.png", data))
	if !strings.HasPrefix(url, "/v1/diary-media/"+diaryMediaPatient+"/") || strings.Contains(url, "original") {
		t.Fatalf("unsafe URL %s", url)
	}
	if _, err := os.Stat(filepath.Join(s.cfg.UploadDir, diaryMediaPatient)); !os.IsNotExist(err) {
		t.Fatalf("file stored in public dir: %v", err)
	}
	got := doAuthed(t, s.Routes(), "GET", url, owner, "")
	if got.Code != 200 || !bytes.Equal(got.Body.Bytes(), data) {
		t.Fatalf("owner read %d: %s", got.Code, got.Body)
	}
	if got.Header().Get("Cache-Control") != "private, no-store" || got.Header().Get("X-Content-Type-Options") != "nosniff" || got.Header().Get("Content-Type") != "image/png" {
		t.Fatalf("unsafe headers %v", got.Header())
	}
	other, _ := s.auth.Issue("22222222-2222-4222-8222-222222222222", "patient")
	for _, tc := range []struct {
		token string
		want  int
	}{{"", 401}, {other, 404}} {
		if out := doAuthed(t, s.Routes(), "GET", url, tc.token, ""); out.Code != tc.want {
			t.Fatalf("read code %d want %d", out.Code, tc.want)
		}
	}
	if out := uploadDiaryTestImage(t, s, professional, "a.png", data); out.Code != 403 {
		t.Fatalf("professional upload %d", out.Code)
	}
	if out := uploadDiaryTestImage(t, s, "", "a.png", data); out.Code != 401 {
		t.Fatalf("anonymous upload %d", out.Code)
	}
	if out := doAuthed(t, s.Routes(), "GET", url+"?access_token="+owner, "", ""); out.Code != 401 {
		t.Fatalf("query token read %d", out.Code)
	}
	if out := doAuthed(t, s.Routes(), "GET", "/uploads/"+diaryMediaPatient+"/"+filepath.Base(url), "", ""); out.Code != 404 {
		t.Fatalf("public read %d", out.Code)
	}
}

func TestDiaryMediaRejectsInvalidImagesAndDecompressionBombs(t *testing.T) {
	s, _, _ := newSafetyTestServer()
	s.cfg.UploadDir = filepath.Join(t.TempDir(), "public")
	token, _ := s.auth.Issue(diaryMediaPatient, "patient")
	oversized := bytes.Repeat([]byte{'x'}, (5<<20)+1)
	bomb := append([]byte(nil), diaryTestPNG(t)...)
	binary.BigEndian.PutUint32(bomb[16:20], 100000)
	binary.BigEndian.PutUint32(bomb[20:24], 100000)
	binary.BigEndian.PutUint32(bomb[29:33], crc32.ChecksumIEEE(bomb[12:29]))
	for _, tc := range []struct {
		name string
		data []byte
		want int
	}{
		{"text.png", []byte("<svg>unsafe</svg>"), 400},
		{"fake.jpg", []byte{0xff, 0xd8, 0xff, 0xe0}, 400},
		{"truncated.png", diaryTestPNG(t)[:33], 400},
		{"bomb.png", bomb, 400},
		{"large.png", oversized, 413},
		{"fake.webp", []byte("RIFFxxxxWEBPVP8 "), 400},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if out := uploadDiaryTestImage(t, s, token, tc.name, tc.data); out.Code != tc.want {
				t.Fatalf("code %d want %d: %s", out.Code, tc.want, out.Body)
			}
		})
	}
	var jpg bytes.Buffer
	_ = jpeg.Encode(&jpg, image.NewNRGBA(image.Rect(0, 0, 2, 2)), nil)
	url := diaryUploadURL(t, uploadDiaryTestImage(t, s, token, "a.jpg", jpg.Bytes()))
	if out := doAuthed(t, s.Routes(), "GET", url, token, ""); out.Code != 200 || out.Header().Get("Content-Type") != "image/jpeg" {
		t.Fatalf("jpeg read %d %v", out.Code, out.Header())
	}
}

func TestDiaryMediaProfessionalRequiresSharedReferenceAndCurrentConsent(t *testing.T) {
	f := newTherapyConsentFixture(t)
	grantContinuousTherapyAccess(t, f)
	f.srv.cfg.UploadDir = filepath.Join(t.TempDir(), "public")
	owner, _ := f.srv.auth.Issue(f.patient.ID, "patient")
	professional, _ := f.srv.auth.Issue(f.prof.ID, "professional")
	url := diaryUploadURL(t, uploadDiaryTestImage(t, f.srv, owner, "a.png", diaryTestPNG(t)))
	ctx := context.Background()
	_, err := f.st.UpdatePatientDataConsent(ctx, store.PatientDataConsent{PatientID: f.patient.ID, ProfessionalID: f.prof.ID, ShareMoodDiary: true})
	if err != nil {
		t.Fatal(err)
	}
	meta, _ := json.Marshal(map[string]any{"media": []map[string]string{{"url": "https://api.example.test" + url, "kind": "drawing"}}})
	note := "Catatan\n\n<!--malva-diary-v1:" + base64.RawURLEncoding.EncodeToString(meta) + "-->"
	entry, err := f.st.UpsertDiaryEntry(ctx, store.DiaryEntry{PatientID: f.patient.ID, Title: "Private", Note: note})
	if err != nil {
		t.Fatal(err)
	}
	read := func(want int) {
		t.Helper()
		out := doAuthed(t, f.srv.Routes(), "GET", url, professional, "")
		if out.Code != want {
			t.Fatalf("professional read %d want %d: %s", out.Code, want, out.Body)
		}
	}
	read(404)
	if _, err = f.db.Exec(`UPDATE diary_entries SET shared_with_professionals=true WHERE id=$1`, entry.ID); err != nil {
		t.Fatal(err)
	}
	read(200)
	if _, err = f.st.UpdatePatientDataConsent(ctx, store.PatientDataConsent{PatientID: f.patient.ID, ProfessionalID: f.prof.ID}); err != nil {
		t.Fatal(err)
	}
	read(404)
	if _, err = f.st.UpdatePatientDataConsent(ctx, store.PatientDataConsent{PatientID: f.patient.ID, ProfessionalID: f.prof.ID, ShareMoodDiary: true}); err != nil {
		t.Fatal(err)
	}
	if _, err = f.db.Exec(`UPDATE diary_entries SET deleted_at=now() WHERE id=$1`, entry.ID); err != nil {
		t.Fatal(err)
	}
	read(404)
}

func TestDiaryMediaReferenceRequiresCanonicalMarkerBoundary(t *testing.T) {
	path := "/v1/diary-media/owner/image.png"
	metadata := base64.URLEncoding.EncodeToString([]byte(`{"media":[{"url":"/v1/diary-media/owner/image.png","kind":"drawing"}]}`))
	marker := "<!--malva-diary-v1:" + metadata + "-->"
	for _, tc := range []struct {
		name, note string
		want       bool
	}{
		{"standalone", marker, true},
		{"paragraph", "Catatan\n\n" + marker, true},
		{"adjacent", "Catatan" + marker, false},
		{"single-newline", "Catatan\n" + marker, false},
		{"space-prefix", " " + marker, false},
		{"trailing-content", marker + "other", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if got := diaryNoteReferencesMedia(tc.note, path); got != tc.want {
				t.Fatalf("media reference=%v want %v", got, tc.want)
			}
		})
	}
}

func TestDiaryMediaOnlySaveRoundTripAndProfessionalRead(t *testing.T) {
	f := newTherapyConsentFixture(t)
	grantContinuousTherapyAccess(t, f)
	f.srv.cfg.UploadDir = filepath.Join(t.TempDir(), "public")
	owner, _ := f.srv.auth.Issue(f.patient.ID, "patient")
	professional, _ := f.srv.auth.Issue(f.prof.ID, "professional")
	imageURL := diaryUploadURL(t, uploadDiaryTestImage(t, f.srv, owner, "drawing.png", diaryTestPNG(t)))
	if _, err := f.st.UpdatePatientDataConsent(context.Background(), store.PatientDataConsent{PatientID: f.patient.ID, ProfessionalID: f.prof.ID, ShareMoodDiary: true}); err != nil {
		t.Fatal(err)
	}
	meta, _ := json.Marshal(map[string]any{"media": []map[string]string{{"url": "https://api.example.test" + imageURL, "kind": "drawing"}}})
	note := "<!--malva-diary-v1:" + base64.URLEncoding.EncodeToString(meta) + "-->"
	path := "/v1/diary-entries"
	for _, method := range []string{"POST", "PUT"} {
		body, _ := json.Marshal(map[string]any{"title": "Gambar", "note": note, "shared_with_professionals": true})
		out := doAuthed(t, f.srv.Routes(), method, path, owner, string(body))
		want := 201
		if method == "PUT" {
			want = 200
		}
		if out.Code != want {
			t.Fatalf("%s media-only save %d: %s", method, out.Code, out.Body)
		}
		var payload struct {
			Diary store.DiaryEntry `json:"diary"`
		}
		if err := json.Unmarshal(out.Body.Bytes(), &payload); err != nil {
			t.Fatal(err)
		}
		if payload.Diary.Note != note {
			t.Fatalf("%s changed media-only marker", method)
		}
		read := doAuthed(t, f.srv.Routes(), "GET", imageURL, professional, "")
		if read.Code != 200 {
			t.Fatalf("%s media-only professional read %d: %s", method, read.Code, read.Body)
		}
		path = "/v1/diary-entries/" + payload.Diary.ID
	}
}
