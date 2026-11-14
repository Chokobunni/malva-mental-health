package server

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"strings"
	"testing"

	"malva/backend/internal/store"
)

func TestDiarySaveRejectsByteOverflowWithoutMutation(t *testing.T) {
	for _, method := range []string{"POST", "PUT"} {
		for _, tc := range []struct {
			name, title, note, message string
		}{
			{"ascii-title", strings.Repeat("a", 161), "Replacement", "judul diary maksimal 160 byte"},
			{"multibyte-title", strings.Repeat("a", 159) + "é", "Replacement", "judul diary maksimal 160 byte"},
			{"ascii-note", "Replacement", strings.Repeat("a", 6001), "isi diary maksimal 6000 byte"},
			{"multibyte-note", "Replacement", strings.Repeat("a", 5999) + "é", "isi diary maksimal 6000 byte"},
		} {
			t.Run(method+"/"+tc.name, func(t *testing.T) {
				db, st := openOnboardingTestStore(t)
				patient := createIdentityTestUser(t, db, st, "patient", nil)
				s := newOnboardingTestServer(db)
				token, _ := s.auth.Issue(patient.ID, "patient")
				originalNote := "Original\n\n<!--malva-diary-v1:eyJtZWRpYSI6W119-->"
				original, err := st.UpsertDiaryEntry(context.Background(), store.DiaryEntry{PatientID: patient.ID, Title: "Original", Note: originalNote})
				if err != nil {
					t.Fatal(err)
				}
				body, _ := json.Marshal(map[string]any{"title": tc.title, "note": tc.note})
				path := "/v1/diary-entries"
				if method == "PUT" {
					path += "/" + original.ID
				}
				out := doAuthed(t, s.Routes(), method, path, token, string(body))
				if out.Code != 400 || !strings.Contains(out.Body.String(), tc.message) {
					t.Fatalf("expected explicit byte-limit rejection; got %d: %s", out.Code, out.Body)
				}
				entries, err := st.ListDiaryEntries(context.Background(), patient.ID, false, 0)
				if err != nil || len(entries) != 1 || entries[0].Title != "Original" || entries[0].Note != originalNote {
					t.Fatalf("invalid save mutated diary: %+v %v", entries, err)
				}
			})
		}
	}
}

func TestDiarySavePreservesMultibyteAndMetadataAtExactByteLimits(t *testing.T) {
	db, _ := openOnboardingTestStore(t)
	st := store.New(db)
	patient := createIdentityTestUser(t, db, st, "patient", nil)
	s := newOnboardingTestServer(db)
	token, _ := s.auth.Issue(patient.ID, "patient")
	metadata := base64.URLEncoding.EncodeToString([]byte(`{"media":[{"url":"/v1/diary-media/owner/image.png","kind":"drawing"}]}`))
	suffix := "\n\n<!--malva-diary-v1:" + metadata + "-->"
	note := strings.Repeat("é", (6000-len(suffix))/2)
	if len(note)+len(suffix) < 6000 {
		note += "a"
	}
	note += suffix
	title := strings.Repeat("é", 80)
	path := "/v1/diary-entries"
	for _, method := range []string{"POST", "PUT"} {
		if method == "PUT" {
			title = strings.Repeat("🌿", 40)
			note = "ø" + note[len("é"):]
		}
		body, _ := json.Marshal(map[string]any{"title": title, "note": note})
		out := doAuthed(t, s.Routes(), method, path, token, string(body))
		want := 201
		if method == "PUT" {
			want = 200
		}
		if out.Code != want {
			t.Fatalf("%s exact byte limits: %d %s", method, out.Code, out.Body)
		}
		var payload struct {
			Diary store.DiaryEntry `json:"diary"`
		}
		if err := json.Unmarshal(out.Body.Bytes(), &payload); err != nil {
			t.Fatal(err)
		}
		if payload.Diary.Title != title || payload.Diary.Note != note {
			t.Fatal("save altered valid UTF-8 or attachment metadata")
		}
		path = "/v1/diary-entries/" + payload.Diary.ID
	}
	entries, err := st.ListDiaryEntries(context.Background(), patient.ID, false, 0)
	if err != nil || len(entries) != 1 || entries[0].Title != title || entries[0].Note != note {
		t.Fatalf("saved byte boundaries changed: %+v %v", entries, err)
	}
}
