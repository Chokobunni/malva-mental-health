package server

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"

	"github.com/gorilla/websocket"
	"malva/backend/internal/realtime"
	"malva/backend/internal/store"
)

type diaryAccessTestResponse struct {
	Recipients []struct {
		ProfessionalID string `json:"professional_id"`
		DisplayName    string `json:"display_name"`
	} `json:"recipients"`
	Eligible []struct {
		ProfessionalID string `json:"professional_id"`
		DisplayName    string `json:"display_name"`
	} `json:"eligible"`
}

func TestDiaryChatRequiresAuthorizedReferenceAndKeepsNotePrivate(t *testing.T) {
	f := newTherapyConsentFixture(t)
	t.Cleanup(func() {
		if _, err := f.db.Exec("DELETE FROM chat_messages WHERE patient_id=$1", f.patient.ID); err != nil {
			t.Errorf("cleanup diary chat: %v", err)
		}
	})
	grantContinuousTherapyAccess(t, f)
	ctx := context.Background()
	patientToken, _ := f.srv.auth.Issue(f.patient.ID, "patient")
	const note = "Isi diary hanya tersedia melalui akses diary"
	out := doAuthed(t, f.srv.Routes(), "POST", "/v1/diary-entries", patientToken,
		`{"title":"Catatan","note":"`+note+`","shared_with_professionals":true}`)
	var created struct {
		Diary store.DiaryEntry `json:"diary"`
	}
	if out.Code != 201 || json.Unmarshal(out.Body.Bytes(), &created) != nil ||
		created.Diary.ID == "" || created.Diary.SharedWithProfessionals {
		t.Fatal("new diary must start private even for a legacy client")
	}
	send := func(fields map[string]string, want int) *httptest.ResponseRecorder {
		t.Helper()
		body, _ := json.Marshal(map[string]any{
			"recipient_id": f.prof.ID, "text": note, "kind": "diary", "metadata": fields,
		})
		response := doAuthed(t, f.srv.Routes(), "POST", "/v1/messages", patientToken, string(body))
		if response.Code != want {
			t.Fatalf("chat status %d, want %d: %s", response.Code, want, response.Body)
		}
		return response
	}
	send(map[string]string{"note": note}, 400)
	ref := map[string]string{"diary_id": created.Diary.ID, "note": note}
	send(ref, 400)
	if _, _, err := f.st.SetDiaryRecipient(ctx, f.patient.ID, created.Diary.ID, f.prof.ID, true); err != nil {
		t.Fatal(err)
	}
	out = send(ref, 201)
	if strings.Contains(out.Body.String(), note) || !strings.Contains(out.Body.String(), created.Diary.ID) {
		t.Fatal("new diary chat must contain only an authorized reference")
	}
	if _, _, err := f.st.SetDiaryRecipient(ctx, f.patient.ID, created.Diary.ID, f.prof.ID, false); err != nil {
		t.Fatal(err)
	}
	send(ref, 400)
}

func TestDiaryRecipientAccessAndRevocation(t *testing.T) {
	f := newTherapyConsentFixture(t)
	grantContinuousTherapyAccess(t, f)
	ctx := context.Background()
	second := createIdentityTestUser(t, f.db, f.st, "professional", nil)
	unconnected := createIdentityTestUser(t, f.db, f.st, "professional", nil)
	secondCare := f
	secondCare.prof = second
	grantContinuousTherapyAccess(t, secondCare)
	if _, err := f.st.LinkPatientToProfessional(ctx, f.patient.ID, second.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := f.st.UpdatePatientDataConsent(ctx, store.PatientDataConsent{
		PatientID: f.patient.ID, ProfessionalID: f.prof.ID, ShareTimeline: true,
	}); err != nil {
		t.Fatal(err)
	}
	f.srv.cfg.UploadDir = filepath.Join(t.TempDir(), "public")
	patientToken, _ := f.srv.auth.Issue(f.patient.ID, "patient")
	otherPatientToken, _ := f.srv.auth.Issue(f.other.ID, "patient")
	firstToken, _ := f.srv.auth.Issue(f.prof.ID, "professional")
	secondToken, _ := f.srv.auth.Issue(second.ID, "professional")
	unconnectedToken, _ := f.srv.auth.Issue(unconnected.ID, "professional")

	imageURL := diaryUploadURL(t, uploadDiaryTestImage(t, f.srv, patientToken, "drawing.png", diaryTestPNG(t)))
	meta, err := json.Marshal(map[string]any{"media": []map[string]string{{"url": imageURL, "kind": "drawing"}}})
	if err != nil {
		t.Fatal(err)
	}
	const secret = "Catatan pasien yang dipilih"
	entry, err := f.st.UpsertDiaryEntry(ctx, store.DiaryEntry{
		PatientID: f.patient.ID, Title: "Catatan harian",
		Note: secret + "\n\n<!--malva-diary-v1:" + base64.RawURLEncoding.EncodeToString(meta) + "-->",
	})
	if err != nil {
		t.Fatal(err)
	}
	path := "/v1/diary-entries/" + entry.ID
	accessPath := path + "/access"
	listPath := "/v1/diary-entries?patient_id=" + f.patient.ID
	timelinePath := "/v1/timeline?patient_id=" + f.patient.ID
	routes := f.srv.Routes()
	call := func(method, path, token string, want int) *httptest.ResponseRecorder {
		t.Helper()
		out := doAuthed(t, routes, method, path, token, "")
		if out.Code != want {
			t.Fatalf("%s %s got status %d, want %d", method, path, out.Code, want)
		}
		return out
	}
	assertAccess := func(out *httptest.ResponseRecorder, recipients int) {
		t.Helper()
		var body diaryAccessTestResponse
		if err := json.Unmarshal(out.Body.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		if body.Recipients == nil || len(body.Recipients) != recipients || len(body.Eligible) != 2 {
			t.Fatalf("access payload has %d recipients and %d eligible", len(body.Recipients), len(body.Eligible))
		}
		for _, person := range body.Recipients {
			if person.DisplayName == "" || (person.ProfessionalID != f.prof.ID && person.ProfessionalID != second.ID) {
				t.Fatal("access payload includes an unexpected recipient")
			}
		}
	}
	assertList := func(token string, want int) {
		t.Helper()
		var body struct {
			Diaries     []store.DiaryEntry         `json:"diaries"`
			DiaryAccess map[string]json.RawMessage `json:"diary_access"`
		}
		out := call("GET", listPath, token, 200)
		if err := json.Unmarshal(out.Body.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		if body.Diaries == nil || len(body.Diaries) != want || body.DiaryAccess != nil {
			t.Fatal("unexpected professional diary list")
		}
		if want == 1 && body.Diaries[0].ID != entry.ID {
			t.Fatal("unexpected diary returned")
		}
	}
	assertTimeline := func(want bool) {
		t.Helper()
		var body struct {
			Events []store.TimelineEvent `json:"events"`
		}
		out := call("GET", timelinePath, firstToken, 200)
		if err := json.Unmarshal(out.Body.Bytes(), &body); err != nil {
			t.Fatal(err)
		}
		for _, event := range body.Events {
			if event.Type == "diary" && event.ID == entry.ID {
				if !want {
					t.Fatal("timeline exposed unshared diary")
				}
				return
			}
		}
		if want {
			t.Fatal("timeline did not include shared diary")
		}
	}
	call("GET", path, patientToken, 200)
	call("GET", path, otherPatientToken, 404)
	call("GET", path, firstToken, 404)
	call("GET", imageURL, firstToken, 404)
	call("GET", accessPath, firstToken, 403)
	call("GET", accessPath, otherPatientToken, 404)
	call("PUT", accessPath+"/"+f.prof.ID, otherPatientToken, 404)
	call("PUT", accessPath+"/"+unconnected.ID, patientToken, 403)
	assertAccess(call("GET", accessPath, patientToken, 200), 0)
	assertList(firstToken, 0)
	assertTimeline(false)

	assertAccess(call("PUT", accessPath+"/"+f.prof.ID, patientToken, 200), 1)
	assertAccess(call("PUT", accessPath+"/"+f.prof.ID, patientToken, 200), 1)
	assertAccess(call("PUT", "/v1/diary-entries/"+strings.ToUpper(entry.ID)+"/access/"+strings.ToUpper(second.ID), patientToken, 200), 2)
	assertList(firstToken, 1)
	assertList(secondToken, 1)
	assertTimeline(true)
	call("GET", path, firstToken, 200)
	call("GET", imageURL, firstToken, 200)
	call("GET", path, unconnectedToken, 404)
	call("GET", imageURL, unconnectedToken, 404)

	var ownerBody struct {
		DiaryAccess map[string][]struct {
			ProfessionalID string `json:"professional_id"`
		} `json:"diary_access"`
	}
	if err := json.Unmarshal(call("GET", listPath, patientToken, 200).Body.Bytes(), &ownerBody); err != nil {
		t.Fatal(err)
	}
	if len(ownerBody.DiaryAccess[entry.ID]) != 2 {
		t.Fatal("owner diary list did not include both recipients")
	}

	assertAccess(call("DELETE", accessPath+"/"+f.prof.ID, patientToken, 200), 1)
	assertAccess(call("DELETE", accessPath+"/"+f.prof.ID, patientToken, 200), 1)
	assertList(firstToken, 0)
	assertTimeline(false)
	call("GET", path, firstToken, 404)
	call("GET", imageURL, firstToken, 404)
	call("GET", path, secondToken, 200)
	call("GET", imageURL, secondToken, 200)

	if _, err := f.db.Exec(`UPDATE patient_professional_links SET status='inactive' WHERE patient_id=$1 AND professional_id=$2`, f.patient.ID, second.ID); err != nil {
		t.Fatal(err)
	}
	call("GET", path, secondToken, 404)
	call("GET", imageURL, secondToken, 404)
	call("DELETE", accessPath+"/"+second.ID, patientToken, 200)
	if _, err := f.st.LinkPatientToProfessional(ctx, f.patient.ID, second.ID); err != nil {
		t.Fatal(err)
	}
	call("GET", path, secondToken, 404)
	call("GET", imageURL, secondToken, 404)
	call("GET", imageURL, patientToken, 200)
}

func TestDiaryLegacyAccessConvertsOnRecipientChange(t *testing.T) {
	f := newTherapyConsentFixture(t)
	grantContinuousTherapyAccess(t, f)
	ctx := context.Background()
	second := createIdentityTestUser(t, f.db, f.st, "professional", nil)
	if _, err := f.st.LinkPatientToProfessional(ctx, f.patient.ID, second.ID); err != nil {
		t.Fatal(err)
	}
	if _, err := f.db.Exec(`INSERT INTO care_packages(patient_id,professional_id,total_sessions,validity_days,price,status,expires_at)
		VALUES ($1,$2,4,42,100000,'active',now()+interval '30 days')`, f.patient.ID, second.ID); err != nil {
		t.Fatal(err)
	}
	for _, professional := range []string{f.prof.ID, second.ID} {
		if _, err := f.st.UpdatePatientDataConsent(ctx, store.PatientDataConsent{
			PatientID: f.patient.ID, ProfessionalID: professional, ShareMoodDiary: true,
		}); err != nil {
			t.Fatal(err)
		}
	}
	entry, err := f.st.UpsertDiaryEntry(ctx, store.DiaryEntry{
		PatientID: f.patient.ID, Title: "Legacy diary", Note: "Legacy note", SharedWithProfessionals: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	patientToken, _ := f.srv.auth.Issue(f.patient.ID, "patient")
	firstToken, _ := f.srv.auth.Issue(f.prof.ID, "professional")
	secondToken, _ := f.srv.auth.Issue(second.ID, "professional")
	path := "/v1/diary-entries/" + entry.ID
	routes := f.srv.Routes()
	call := func(method, path, token string, want int) *httptest.ResponseRecorder {
		t.Helper()
		out := doAuthed(t, routes, method, path, token, "")
		if out.Code != want {
			t.Fatalf("%s %s got status %d, want %d", method, path, out.Code, want)
		}
		return out
	}
	call("GET", path, firstToken, 200)
	call("GET", path, secondToken, 200)
	out := call("DELETE", path+"/access/"+f.prof.ID, patientToken, 200)
	var body diaryAccessTestResponse
	if err := json.Unmarshal(out.Body.Bytes(), &body); err != nil {
		t.Fatal(err)
	}
	if len(body.Recipients) != 1 || body.Recipients[0].ProfessionalID != second.ID {
		t.Fatal("legacy conversion did not preserve the other recipient")
	}
	call("GET", path, firstToken, 404)
	call("GET", path, secondToken, 200)
	var legacy bool
	if err := f.db.QueryRow(`SELECT shared_with_professionals FROM diary_entries WHERE id=$1`, entry.ID).Scan(&legacy); err != nil || legacy {
		t.Fatalf("legacy flag after conversion = %t, err = %v", legacy, err)
	}
	if _, err := f.st.UpdatePatientDataConsent(ctx, store.PatientDataConsent{
		PatientID: f.patient.ID, ProfessionalID: second.ID,
	}); err != nil {
		t.Fatal(err)
	}
	call("GET", path, secondToken, 404)
	call("PUT", path+"/access/"+second.ID, patientToken, 200)
	call("GET", path, secondToken, 200)
}

func TestDiaryAccessChangeRealtimeIsRecipientOnly(t *testing.T) {
	f := newTherapyConsentFixture(t)
	grantContinuousTherapyAccess(t, f)
	connected := clinicalFixture{therapyConsentFixture: f}
	recipientConn := clinicalSocket(t, connected, f.prof.ID, "professional")
	patientConn := clinicalSocket(t, connected, f.patient.ID, "patient")
	if !readPeerPresence(t, patientConn, f.prof.ID) {
		t.Fatal("professional socket did not connect")
	}
	entry, err := f.st.UpsertDiaryEntry(context.Background(), store.DiaryEntry{
		PatientID: f.patient.ID, Title: "Catatan", Note: "Isi catatan",
	})
	if err != nil {
		t.Fatal(err)
	}
	token, _ := f.srv.auth.Issue(f.patient.ID, "patient")
	path := "/v1/diary-entries/" + entry.ID + "/access/" + f.prof.ID
	readEvent := func(conn *websocket.Conn, eventType string) map[string]string {
		t.Helper()
		for {
			var event struct {
				Type string          `json:"type"`
				Data json.RawMessage `json:"data"`
			}
			if err := conn.ReadJSON(&event); err != nil {
				t.Fatal(err)
			}
			if event.Type == "diary_access_changed" && eventType != event.Type {
				t.Fatal("recipient event was delivered to a different account")
			}
			if event.Type == eventType {
				var data map[string]string
				if len(event.Data) > 0 {
					if err := json.Unmarshal(event.Data, &data); err != nil {
						t.Fatal(err)
					}
				}
				return data
			}
		}
	}
	for _, method := range []string{"PUT", "DELETE"} {
		if result := doAuthed(t, f.srv.Routes(), method, path, token, ""); result.Code != 200 {
			t.Fatalf("%s diary recipient got %d", method, result.Code)
		}
		data := readEvent(recipientConn, "diary_access_changed")
		if len(data) != 3 || data["diary_id"] != entry.ID || data["patient_id"] != f.patient.ID || data["professional_id"] != f.prof.ID {
			t.Fatal("wrong Diary access event payload")
		}
		f.srv.hub.Publish(f.patient.ID, realtime.Event{Type: "test.barrier"})
		readEvent(patientConn, "test.barrier")
	}
}
