package server

import (
	"encoding/base64"
	"encoding/json"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestPatientAvatarPrivatePersistenceAndValidation(t *testing.T) {
	s, _, professional := newSafetyTestServer()
	s.cfg.UploadDir = filepath.Join(t.TempDir(), "public")
	owner, _ := s.auth.Issue(diaryMediaPatient, "patient")
	avatar := base64.StdEncoding.EncodeToString(diaryTestPNG(t))
	body, _ := json.Marshal(map[string]string{"avatar": avatar})
	put := doAuthed(t, s.Routes(), "PUT", "/v1/patient-avatar", owner, string(body))
	if put.Code != 200 {
		t.Fatalf("save avatar %d: %s", put.Code, put.Body)
	}
	got := doAuthed(t, s.Routes(), "GET", "/v1/patient-avatar", owner, "")
	if got.Code != 200 || !strings.Contains(got.Body.String(), avatar) || got.Header().Get("Cache-Control") != "private, no-store" {
		t.Fatalf("owner read %d: %s", got.Code, got.Body)
	}
	for _, path := range []string{"/uploads/.patient-avatars/" + diaryMediaPatient + ".json", "/uploads/%2epatient-avatars/" + diaryMediaPatient + ".json", "/uploads/"} {
		for _, method := range []string{"GET", "HEAD"} {
			out := doAuthed(t, s.Routes(), method, path, "", "")
			if out.Code != 404 {
				t.Fatalf("public avatar exposed via %s %s: %d", method, path, out.Code)
			}
		}
	}
	publicDir := filepath.Join(s.cfg.UploadDir, diaryMediaPatient)
	if err := os.MkdirAll(publicDir, 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(publicDir, "photo.png"), diaryTestPNG(t), 0600); err != nil {
		t.Fatal(err)
	}
	if out := doAuthed(t, s.Routes(), "GET", "/uploads/"+diaryMediaPatient+"/photo.png", "", ""); out.Code != 200 {
		t.Fatalf("existing public professional photo blocked: %d", out.Code)
	}
	// A stale device's first sync must not replace a newer selected avatar.
	req := httptest.NewRequest("PUT", "/v1/patient-avatar", strings.NewReader(`{"avatar":"default"}`))
	req.Header.Set("Authorization", "Bearer "+owner)
	req.Header.Set("If-None-Match", "*")
	res := httptest.NewRecorder()
	s.Routes().ServeHTTP(res, req)
	if res.Code != 200 || !strings.Contains(res.Body.String(), avatar) {
		t.Fatalf("migration replaced saved avatar: %d %s", res.Code, res.Body)
	}
	if out := doAuthed(t, s.Routes(), "PUT", "/v1/patient-avatar", owner, `{"avatar":"default"}`); out.Code != 200 {
		t.Fatalf("replace avatar %d: %s", out.Code, out.Body)
	}
	restarted, _, _ := newSafetyTestServer()
	restarted.cfg.UploadDir = s.cfg.UploadDir
	if out := doAuthed(t, restarted.Routes(), "GET", "/v1/patient-avatar", owner, ""); out.Code != 200 || !strings.Contains(out.Body.String(), "default") {
		t.Fatalf("persisted avatar after server recreation %d: %s", out.Code, out.Body)
	}
	for _, invalid := range []string{"https://example.com/photo.png", "assets/reference/avatar-6.png", "Li4vLi4v"} {
		raw, _ := json.Marshal(map[string]string{"avatar": invalid})
		if out := doAuthed(t, s.Routes(), "PUT", "/v1/patient-avatar", owner, string(raw)); out.Code != 400 {
			t.Fatalf("invalid avatar accepted: %d", out.Code)
		}
	}
	if out := doAuthed(t, s.Routes(), "PUT", "/v1/patient-avatar", professional, `{"avatar":"default"}`); out.Code != 403 {
		t.Fatalf("professional avatar write %d", out.Code)
	}
	if out := doAuthed(t, s.Routes(), "GET", "/v1/patient-avatar?patient_id=../secret", owner, ""); out.Code != 400 {
		t.Fatalf("unsafe patient ID %d", out.Code)
	}
}

func TestPatientAvatarReadPermitsHistoricalPairOnly(t *testing.T) {
	f := clinicalFixture{therapyConsentFixture: newTherapyConsentFixture(t)}
	f.srv.cfg.UploadDir = filepath.Join(t.TempDir(), "public")
	patient, _ := f.srv.auth.Issue(f.patient.ID, "patient")
	professional, _ := f.srv.auth.Issue(f.prof.ID, "professional")
	other, _ := f.srv.auth.Issue(f.other.ID, "patient")
	if out := doAuthed(t, f.srv.Routes(), "PUT", "/v1/patient-avatar", patient, `{"avatar":"assets/reference/avatar-2.png"}`); out.Code != 200 {
		t.Fatalf("save %d: %s", out.Code, out.Body)
	}
	if _, err := f.db.Exec(`UPDATE patient_professional_links SET status='inactive' WHERE patient_id=$1 AND professional_id=$2`, f.patient.ID, f.prof.ID); err != nil {
		t.Fatal(err)
	}
	path := "/v1/patient-avatar?patient_id=" + f.patient.ID
	if out := doAuthed(t, f.srv.Routes(), "GET", path, professional, ""); out.Code != 200 || !strings.Contains(out.Body.String(), "avatar-2.png") {
		t.Fatalf("historical peer read %d: %s", out.Code, out.Body)
	}
	if out := doAuthed(t, f.srv.Routes(), "GET", path, other, ""); out.Code != 404 {
		t.Fatalf("unrelated patient read %d", out.Code)
	}
}
