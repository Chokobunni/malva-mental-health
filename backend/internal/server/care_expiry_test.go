package server

import (
	"encoding/base64"
	"encoding/json"
	"path/filepath"
	"strings"
	"testing"

	"malva/backend/internal/store"
)

func TestExpiredCarePreservesDiaryChatHistory(t *testing.T) {
	f := newTherapyConsentFixture(t)
	grantContinuousTherapyAccess(t, f)
	f.srv.cfg.UploadDir = filepath.Join(t.TempDir(), "public")
	owner, _ := f.srv.auth.Issue(f.patient.ID, "patient")
	professional, _ := f.srv.auth.Issue(f.prof.ID, "professional")
	stranger, _ := f.srv.auth.Issue(f.other.ID, "patient")
	media := diaryUploadURL(t, uploadDiaryTestImage(t, f.srv, owner, "sketch.png", diaryTestPNG(t)))
	otherMedia := diaryUploadURL(t, uploadDiaryTestImage(t, f.srv, owner, "private.png", diaryTestPNG(t)))
	metadata, _ := json.Marshal(map[string]any{"media": []map[string]string{{"url": media, "kind": "drawing"}}})
	note := "<!--malva-diary-v1:" + base64.RawURLEncoding.EncodeToString(metadata) + "-->"
	entry, err := f.st.UpsertDiaryEntry(t.Context(), store.DiaryEntry{PatientID: f.patient.ID, Title: "Diary", Note: note})
	if err != nil {
		t.Fatal(err)
	}
	if _, _, err := f.st.SetDiaryRecipient(t.Context(), f.patient.ID, entry.ID, f.prof.ID, true); err != nil {
		t.Fatal(err)
	}
	var marker string
	if err := f.db.QueryRow(`INSERT INTO chat_messages (patient_id, professional_id, sender_id, sender_name, text, kind, attachment_meta, id)
        VALUES ($1,$2,$1,'Patient','Diary dibagikan','diary',jsonb_build_object('diary', jsonb_build_object('note', $3::text)),gen_random_uuid()::text)
        RETURNING id`, f.patient.ID, f.prof.ID, note).Scan(&marker); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = f.db.Exec("DELETE FROM chat_messages WHERE id=$1", marker) })
	if _, err := f.db.Exec(`UPDATE care_packages SET expires_at=now() - interval '1 minute'
        WHERE patient_id=$1 AND professional_id=$2`, f.patient.ID, f.prof.ID); err != nil {
		t.Fatal(err)
	}
	newer, err := f.st.CreateChatMessage(t.Context(), store.ChatMessage{ID: generateChatMessageID(), PatientID: f.patient.ID, ProfessionalID: f.prof.ID, SenderID: f.patient.ID, Kind: "text", Text: "More recent"})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = f.db.Exec("DELETE FROM chat_messages WHERE id=$1", newer.ID) })
	routes := f.srv.Routes()
	call := func(method, path, token, body string, want int) string {
		t.Helper()
		out := doAuthed(t, routes, method, path, token, body)
		if out.Code != want {
			t.Fatalf("%s %s: got %d want %d: %s", method, path, out.Code, want, out.Body)
		}
		return out.Body.String()
	}
	access := "/v1/diary-entries/" + entry.ID + "/access"
	result := call("GET", access, owner, "", 200)
	var permissions diaryAccessTestResponse
	if err := json.Unmarshal([]byte(result), &permissions); err != nil || len(permissions.Eligible) != 0 || len(permissions.Recipients) != 1 {
		t.Fatal("expired professional must stay in past grants only")
	}
	call("PUT", access+"/"+f.prof.ID, owner, "", 403)
	shareBody, _ := json.Marshal(map[string]any{
		"recipient_id": f.prof.ID, "kind": "diary",
		"metadata": map[string]string{"diary_id": entry.ID},
	})
	call("POST", "/v1/messages", owner, string(shareBody), 403)
	for _, token := range []string{owner, professional} {
		links := call("GET", "/v1/patient-professional-links", token, "", 200)
		if !strings.Contains(links, `"status":"expired"`) {
			t.Fatal("ended pair was not returned as expired")
		}
		path := "/v1/messages?patient_id=" + f.patient.ID + "&professional_id=" + f.prof.ID + "&limit=1"
		newestPage := call("GET", path, token, "", 200)
		if !strings.Contains(newestPage, newer.ID) || strings.Contains(newestPage, marker) {
			t.Fatal("unexpected newest history page")
		}
		olderPage := call("GET", path+"&before="+newer.ID, token, "", 200)
		if !strings.Contains(olderPage, marker) || strings.Contains(olderPage, newer.ID) {
			t.Fatal("unable to load previous history page")
		}
	}
	call("GET", media, owner, "", 200)
	call("GET", media, professional, "", 200)
	call("DELETE", access+"/"+f.prof.ID, owner, "", 200)
	call("GET", "/v1/diary-entries/"+entry.ID, professional, "", 404)
	call("GET", media, professional, "", 200)
	call("GET", otherMedia, professional, "", 404)
	call("GET", media, stranger, "", 404)
	if _, err := f.db.Exec(`UPDATE users SET disabled_at=now() WHERE id=$1`, f.prof.ID); err != nil {
		t.Fatal(err)
	}
	call("GET", media, professional, "", 404)
}
