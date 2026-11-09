package server

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/gorilla/websocket"
	"malva/backend/internal/clock"
	"malva/backend/internal/realtime"
	"malva/backend/internal/store"
)

type clinicalFixture struct {
	therapyConsentFixture
	sessionID string
}

func newClinicalFixture(t *testing.T) clinicalFixture {
	t.Helper()
	f := clinicalFixture{therapyConsentFixture: newTherapyConsentFixture(t)}
	f.srv.cfg.UploadDir = t.TempDir() + "/public"
	if _, err := f.db.Exec(`UPDATE professional_credentials SET verification_status='VERIFIED' WHERE user_id=$1`, f.prof.ID); err != nil {
		t.Fatal(err)
	}
	if err := f.db.QueryRow(`INSERT INTO care_sessions(patient_id,professional_id,session_type,scheduled_at,duration_minutes,status) VALUES($1,$2,'chat',$3,30,'scheduled') RETURNING id`, f.patient.ID, f.prof.ID, clock.Now().Add(-time.Minute)).Scan(&f.sessionID); err != nil {
		t.Fatal(err)
	}
	if _, err := f.st.UpdatePatientDataConsent(context.Background(), store.PatientDataConsent{PatientID: f.patient.ID, ProfessionalID: f.prof.ID, ShareGoals: true, ShareMedications: true, ShareHealthRecord: true}); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		for _, table := range []string{"chat_messages", "care_sessions", "goals", "medications"} {
			if _, err := f.db.Exec(`DELETE FROM `+table+` WHERE patient_id=$1`, f.patient.ID); err != nil {
				t.Errorf("cleanup %s: %v", table, err)
			}
		}
	})
	return f
}

func (f clinicalFixture) call(t *testing.T, method, path, role, subject string, body any) *httptest.ResponseRecorder {
	t.Helper()
	token, _ := f.srv.auth.Issue(subject, role)
	raw, _ := json.Marshal(body)
	return doAuthed(t, f.srv.Routes(), method, path, token, string(raw))
}

func TestClinicalProfessionalCards(t *testing.T) {
	f := newClinicalFixture(t)
	goal, err := f.st.CreateGoal(context.Background(), store.UpsertGoalParams{PatientID: f.patient.ID, Title: "Walk"})
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		name, kind string
		meta       map[string]any
		want       int
	}{
		{"assessment", "assessment_request", map[string]any{"session_id": f.sessionID, "module_id": "dass21"}, 201},
		{"screening", "assessment_request", map[string]any{"session_id": f.sessionID, "module_id": "screening"}, 201},
		{"summary", "session_summary", map[string]any{"session_id": f.sessionID, "goal_ids": []string{goal.ID}, "insight": "Practice daily"}, 201},
		{"goals", "goals", map[string]any{"session_id": f.sessionID, "goal_ids": []string{goal.ID}}, 201},
		{"unknown module", "assessment_request", map[string]any{"session_id": f.sessionID, "module_id": "invented"}, 403},
		{"wrong session", "assessment_request", map[string]any{"session_id": "other", "module_id": "who5"}, 403},
		{"private field", "session_summary", map[string]any{"session_id": f.sessionID, "private_note": "secret"}, 403},
		{"forged attachment", "attachment", map[string]any{"session_id": f.sessionID, "attachment_id": "forged"}, 403},
		{"patient kind", "prescription", map[string]any{"session_id": f.sessionID}, 403},
	} {
		t.Run(tc.name, func(t *testing.T) {
			out := f.call(t, "POST", "/v1/messages", "professional", f.prof.ID, map[string]any{"recipient_id": f.patient.ID, "kind": tc.kind, "metadata": tc.meta})
			if out.Code != tc.want {
				t.Fatalf("status %d want %d: %s", out.Code, tc.want, out.Body)
			}
			if out.Code == 201 {
				var p struct {
					Message store.ChatMessage `json:"message"`
				}
				_ = json.Unmarshal(out.Body.Bytes(), &p)
				if p.Message.Kind != tc.kind {
					t.Fatalf("lost clinical kind: %s", p.Message.Kind)
				}
			}
		})
	}
	otherGoal, err := f.st.CreateGoal(context.Background(), store.UpsertGoalParams{PatientID: f.other.ID, Title: "Private goal"})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _, _ = f.db.Exec(`DELETE FROM goals WHERE id=$1`, otherGoal.ID) })
	out := f.call(t, "POST", "/v1/messages", "professional", f.prof.ID, map[string]any{"recipient_id": f.patient.ID, "kind": "goals", "metadata": map[string]any{"session_id": f.sessionID, "goal_ids": []string{otherGoal.ID}}})
	if out.Code != 403 {
		t.Fatalf("other patient's goal accepted: %d %s", out.Code, out.Body)
	}
	if _, err := f.db.Exec(`UPDATE care_sessions SET scheduled_at=$2 WHERE id=$1`, f.sessionID, clock.Now().Add(-2*time.Hour)); err != nil {
		t.Fatal(err)
	}
	out = f.call(t, "POST", "/v1/messages", "professional", f.prof.ID, map[string]any{"recipient_id": f.patient.ID, "kind": "assessment_request", "metadata": map[string]any{"session_id": f.sessionID, "module_id": "who5"}})
	if out.Code != 403 {
		t.Fatalf("expired session accepted: %d", out.Code)
	}
}

func TestClinicalGoalAndDiagnosisRequireActiveSession(t *testing.T) {
	f := newClinicalFixture(t)
	body := map[string]any{"patient_id": f.patient.ID, "title": "Daily walk", "target_per_week": 3}
	out := f.call(t, "POST", "/v1/goals", "professional", f.prof.ID, body)
	if out.Code != 201 {
		t.Fatalf("professional goal status %d: %s", out.Code, out.Body)
	}
	if _, err := f.db.Exec(`UPDATE care_sessions SET scheduled_at=$2 WHERE id=$1`, f.sessionID, clock.Now().Add(-2*time.Hour)); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		method, path string
		body         any
	}{
		{"POST", "/v1/goals", body},
		{"PUT", "/v1/health-record", map[string]string{"patient_id": f.patient.ID, "diagnosis_summary": "New diagnosis"}},
		{"POST", "/v1/medications", map[string]any{"patient_id": f.patient.ID, "name": "Medication"}},
	} {
		out := f.call(t, tc.method, tc.path, "professional", f.prof.ID, tc.body)
		if out.Code != 403 {
			t.Fatalf("expired mutation %s status %d: %s", tc.path, out.Code, out.Body)
		}
	}
}

func TestClinicalPsychologistCannotMutateMedication(t *testing.T) {
	f := newClinicalFixture(t)
	med, err := f.st.UpsertMedication(context.Background(), store.Medication{PatientID: f.patient.ID, Name: "Existing"})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := f.db.Exec(`UPDATE professional_credentials SET specialization='M.Psi' WHERE user_id=$1`, f.prof.ID); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		method, path string
		body         any
	}{
		{"POST", "/v1/medications", map[string]string{"patient_id": f.patient.ID, "name": "Forbidden"}},
		{"PUT", "/v1/medications/" + med.ID, map[string]string{"patient_id": f.patient.ID, "name": "Forbidden"}},
		{"DELETE", "/v1/medications/" + med.ID + "?patient_id=" + f.patient.ID, nil},
	} {
		out := f.call(t, tc.method, tc.path, "professional", f.prof.ID, tc.body)
		if out.Code != 403 {
			t.Fatalf("%s status %d: %s", tc.method, out.Code, out.Body)
		}
	}
}

func TestClinicalPrivateAttachments(t *testing.T) {
	f := newClinicalFixture(t)
	var b bytes.Buffer
	mw := multipart.NewWriter(&b)
	_ = mw.WriteField("recipient_id", f.patient.ID)
	part, _ := mw.CreateFormFile("file", "signed.pdf")
	_, _ = io.WriteString(part, "%PDF-1.4\nclinical signed document\n%%EOF")
	_ = mw.Close()
	token, _ := f.srv.auth.Issue(f.prof.ID, "professional")
	req := httptest.NewRequest("POST", "/v1/chat-attachments", &b)
	req.Header.Set("Content-Type", mw.FormDataContentType())
	req.Header.Set("Authorization", "Bearer "+token)
	out := httptest.NewRecorder()
	f.srv.Routes().ServeHTTP(out, req)
	if out.Code != 201 {
		t.Fatalf("upload status %d: %s", out.Code, out.Body)
	}
	var p struct {
		Message store.ChatMessage `json:"message"`
	}
	if err := json.Unmarshal(out.Body.Bytes(), &p); err != nil {
		t.Fatal(err)
	}
	if p.Message.Kind != "attachment" || strings.Contains(string(p.Message.Metadata), "/uploads/") {
		t.Fatalf("unsafe attachment metadata %s", p.Message.Metadata)
	}
	if _, err := f.db.Exec(`UPDATE care_sessions SET scheduled_at=$2 WHERE id=$1`, f.sessionID, clock.Now().Add(-2*time.Hour)); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		role, id string
		want     int
	}{{"patient", f.patient.ID, 200}, {"professional", f.prof.ID, 200}, {"patient", f.other.ID, 404}} {
		get := f.call(t, "GET", "/v1/chat-attachments/"+p.Message.ID, tc.role, tc.id, nil)
		if get.Code != tc.want {
			t.Fatalf("attachment read status %d want %d: %s", get.Code, tc.want, get.Body)
		}
		if get.Code == 200 && !strings.HasPrefix(get.Body.String(), "%PDF-") {
			t.Fatal("download did not return document")
		}
	}
	unauth := doAuthed(t, f.srv.Routes(), "GET", "/v1/chat-attachments/"+p.Message.ID, "", "")
	if unauth.Code != 401 {
		t.Fatalf("anonymous download %d", unauth.Code)
	}
}

func TestClinicalCardRetryDoesNotDuplicate(t *testing.T) {
	f := newClinicalFixture(t)
	body := map[string]any{"recipient_id": f.patient.ID, "kind": "assessment_request", "client_message_id": "78fdb267-91fb-4812-b1e4-023ba39e9ee1", "metadata": map[string]string{"session_id": f.sessionID, "module_id": "who5"}}
	var first string
	for i := 0; i < 2; i++ {
		out := f.call(t, "POST", "/v1/messages", "professional", f.prof.ID, body)
		if out.Code != 201 {
			t.Fatalf("retry status %d: %s", out.Code, out.Body)
		}
		var p struct {
			Message store.ChatMessage `json:"message"`
		}
		_ = json.Unmarshal(out.Body.Bytes(), &p)
		if i == 0 {
			first = p.Message.ID
		} else if p.Message.ID != first {
			t.Fatal("retry created duplicate message")
		}
	}
	body["metadata"] = map[string]string{"session_id": f.sessionID, "module_id": "dass21"}
	out := f.call(t, "POST", "/v1/messages", "professional", f.prof.ID, body)
	if out.Code < 400 {
		t.Fatal("reused retry key accepted different payload")
	}
}

func TestClinicalGoalRetryDoesNotDuplicate(t *testing.T) {
	f := newClinicalFixture(t)
	token, _ := f.srv.auth.Issue(f.prof.ID, "professional")
	call := func(title string) *httptest.ResponseRecorder {
		raw, _ := json.Marshal(map[string]string{"patient_id": f.patient.ID, "title": title})
		req := httptest.NewRequest("POST", "/v1/goals", bytes.NewReader(raw))
		req.Header.Set("Authorization", "Bearer "+token)
		req.Header.Set("Idempotency-Key", "homework-123")
		out := httptest.NewRecorder()
		f.srv.Routes().ServeHTTP(out, req)
		return out
	}
	var first string
	for i := 0; i < 2; i++ {
		out := call("Daily walk")
		if out.Code != 201 {
			t.Fatalf("goal retry %d: %s", out.Code, out.Body)
		}
		var p struct {
			Goal store.Goal `json:"goal"`
		}
		_ = json.Unmarshal(out.Body.Bytes(), &p)
		if i == 0 {
			first = p.Goal.ID
		} else if p.Goal.ID != first {
			t.Fatal("goal retry created duplicate")
		}
	}
	if out := call("Different homework"); out.Code < 400 {
		t.Fatal("goal retry key accepted different payload")
	}
}

func TestClinicalPatientCannotForgeNewProfessionalCards(t *testing.T) {
	f := newClinicalFixture(t)
	for _, kind := range []string{"attachment", "assessment_request", "session_summary"} {
		out := f.call(t, "POST", "/v1/messages", "patient", f.patient.ID, map[string]any{"recipient_id": f.prof.ID, "kind": kind, "metadata": map[string]string{"session_id": f.sessionID, "module_id": "who5"}})
		if out.Code != 403 {
			t.Fatalf("patient forged %s: %d %s", kind, out.Code, out.Body)
		}
	}
}

func TestClinicalAttachmentRejectsMalformedWebP(t *testing.T) {
	data := []byte("RIFFxxxxWEBPVP8 ")
	if _, err := validateChatAttachment("fake.webp", data); err == nil {
		t.Fatal("truncated WebP accepted")
	}
}

func clinicalSocket(t *testing.T, f clinicalFixture, userID, role string) *websocket.Conn {
	t.Helper()
	if f.srv.hub == nil {
		f.srv.hub = realtime.NewHub(f.srv.logger, func(string) bool { return true }, f.st)
	}
	hs := httptest.NewServer(f.srv.Routes())
	t.Cleanup(hs.Close)
	token, _ := f.srv.auth.Issue(userID, role)
	conn, _, err := websocket.DefaultDialer.Dial("ws"+strings.TrimPrefix(hs.URL, "http")+"/v1/realtime/ws", http.Header{"Authorization": []string{"Bearer " + token}})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = conn.Close() })
	_ = conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	return conn
}

func TestClinicalWebsocketCardPolicyAndRetry(t *testing.T) {
	f := newClinicalFixture(t)
	conn := clinicalSocket(t, f, f.prof.ID, "professional")
	goodID := "c0851fe0-0b7c-42fa-8f64-c1680665986a"
	badID := "5ad8ce47-e08c-49d0-af6c-487270b7dff3"
	write := func(id, kind, module string) {
		t.Helper()
		if err := conn.WriteJSON(map[string]any{"type": "chat_message", "data": map[string]any{"id": id, "client_message_id": id, "sender_id": f.prof.ID, "recipient_id": f.patient.ID, "kind": kind, "metadata": map[string]string{"session_id": f.sessionID, "module_id": module}}}); err != nil {
			t.Fatal(err)
		}
	}
	write(badID, "assessment_request", "invented")
	for i := 0; i < 2; i++ {
		write(goodID, "assessment_request", "who5")
		for {
			var event struct {
				Type string          `json:"type"`
				Data json.RawMessage `json:"data"`
			}
			if err := conn.ReadJSON(&event); err != nil {
				t.Fatal(err)
			}
			if event.Type != "chat_message" {
				continue
			}
			var message struct{ ID, Kind string }
			_ = json.Unmarshal(event.Data, &message)
			if message.ID != store.ClinicalRetryID("message", f.prof.ID, goodID) || message.Kind != "assessment_request" {
				t.Fatalf("unexpected websocket card %s", event.Data)
			}
			break
		}
	}
	var count int
	if err := f.db.QueryRow(`SELECT count(*) FROM chat_messages WHERE patient_id=$1`, f.patient.ID).Scan(&count); err != nil || count != 1 {
		t.Fatalf("WS rejected/duplicate count %d err %v", count, err)
	}
}

func TestClinicalMutationsPublishInAppRefreshWithoutPush(t *testing.T) {
	f := newClinicalFixture(t)
	conn := clinicalSocket(t, f, f.patient.ID, "patient")
	checkEvent := func(resource string) {
		t.Helper()
		for {
			var e struct {
				Type string         `json:"type"`
				Data map[string]any `json:"data"`
			}
			if err := conn.ReadJSON(&e); err != nil {
				t.Fatal(err)
			}
			if e.Type != "clinical_data_changed" {
				continue
			}
			if e.Data["patient_id"] != f.patient.ID || e.Data["resource"] != resource {
				t.Fatalf("invalid refresh event %+v", e)
			}
			break
		}
	}
	goal := f.call(t, "POST", "/v1/goals", "professional", f.prof.ID, map[string]string{"patient_id": f.patient.ID, "title": "Walk"})
	if goal.Code != 201 {
		t.Fatalf("goal %d %s", goal.Code, goal.Body)
	}
	checkEvent("goals")
	var createdGoal struct {
		Goal store.Goal `json:"goal"`
	}
	_ = json.Unmarshal(goal.Body.Bytes(), &createdGoal)
	goalUpdate := f.call(t, "PATCH", "/v1/goals/"+createdGoal.Goal.ID, "patient", f.patient.ID, map[string]string{"title": "Walk daily"})
	if goalUpdate.Code != 200 {
		t.Fatalf("goal update %d %s", goalUpdate.Code, goalUpdate.Body)
	}
	checkEvent("goals")
	goalDelete := f.call(t, "DELETE", "/v1/goals/"+createdGoal.Goal.ID, "patient", f.patient.ID, nil)
	if goalDelete.Code != 200 {
		t.Fatalf("goal delete %d %s", goalDelete.Code, goalDelete.Body)
	}
	checkEvent("goals")
	med := f.call(t, "POST", "/v1/medications", "professional", f.prof.ID, map[string]string{"patient_id": f.patient.ID, "name": "Existing"})
	if med.Code != 201 {
		t.Fatalf("med %d %s", med.Code, med.Body)
	}
	checkEvent("medications")
	var p struct {
		Medication store.Medication `json:"medication"`
	}
	_ = json.Unmarshal(med.Body.Bytes(), &p)
	update := f.call(t, "PUT", "/v1/medications/"+p.Medication.ID, "professional", f.prof.ID, map[string]string{"patient_id": f.patient.ID, "name": "Edited"})
	if update.Code != 200 {
		t.Fatalf("update %d %s", update.Code, update.Body)
	}
	checkEvent("medications")
	del := f.call(t, "DELETE", "/v1/medications/"+p.Medication.ID+"?patient_id="+f.patient.ID, "professional", f.prof.ID, nil)
	if del.Code != 200 {
		t.Fatalf("delete %d %s", del.Code, del.Body)
	}
	checkEvent("medications")
	diagnosis := f.call(t, "PUT", "/v1/health-record", "professional", f.prof.ID, map[string]string{"patient_id": f.patient.ID, "diagnosis_summary": "Diagnosis"})
	if diagnosis.Code != 200 {
		t.Fatalf("diagnosis %d %s", diagnosis.Code, diagnosis.Body)
	}
	checkEvent("health_record")
	var count int
	if err := f.db.QueryRow(`SELECT count(*) FROM notification_outbox o JOIN notifications n ON n.id=o.notification_id WHERE n.user_id=$1`, f.patient.ID).Scan(&count); err != nil || count != 0 {
		t.Fatalf("clinical changes created push outbox %d err %v", count, err)
	}
}

func TestClinicalAttachmentValidationAndRetry(t *testing.T) {
	f := newClinicalFixture(t)
	// Professional attachments belong to the session, independent of patient-data consent.
	if _, err := f.st.UpdatePatientDataConsent(context.Background(), store.PatientDataConsent{PatientID: f.patient.ID, ProfessionalID: f.prof.ID}); err != nil {
		t.Fatal(err)
	}
	token, _ := f.srv.auth.Issue(f.prof.ID, "professional")
	upload := func(name string, data []byte, clientID string) *httptest.ResponseRecorder {
		t.Helper()
		var body bytes.Buffer
		mw := multipart.NewWriter(&body)
		_ = mw.WriteField("recipient_id", f.patient.ID)
		_ = mw.WriteField("client_message_id", clientID)
		p, _ := mw.CreateFormFile("file", name)
		_, _ = p.Write(data)
		_ = mw.Close()
		r := httptest.NewRequest("POST", "/v1/chat-attachments", &body)
		r.Header.Set("Content-Type", mw.FormDataContentType())
		r.Header.Set("Authorization", "Bearer "+token)
		out := httptest.NewRecorder()
		f.srv.Routes().ServeHTTP(out, r)
		return out
	}
	png, _ := base64.StdEncoding.DecodeString("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAusB9Wl2nKwAAAAASUVORK5CYII=")
	id := "344d5a92-831d-4771-8cfb-c53fa0c7b445"
	// Simulate a process exit after immutable file publication but before
	// creating its message: a retry must recover without overwriting bytes.
	if err := os.MkdirAll(f.srv.privateChatDir(), 0700); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(f.srv.privateChatDir(), store.ClinicalRetryID("message", f.prof.ID, id)), png, 0600); err != nil {
		t.Fatal(err)
	}
	var first string
	for i := 0; i < 2; i++ {
		out := upload("photo.png", png, id)
		if out.Code != 201 {
			t.Fatalf("upload %d %s", out.Code, out.Body)
		}
		var p struct {
			Message store.ChatMessage `json:"message"`
		}
		_ = json.Unmarshal(out.Body.Bytes(), &p)
		if i == 0 {
			first = p.Message.ID
		} else if first != p.Message.ID {
			t.Fatal("attachment retry duplicated message")
		}
	}
	for _, tc := range []struct {
		name string
		data []byte
		id   string
	}{{"different.png", png, id}, {"fake.jpg", []byte("text disguised as image"), ""}, {"fake.pdf", png, ""}, {"huge.pdf", bytes.Repeat([]byte("a"), maxChatAttachmentSize+1), ""}} {
		if out := upload(tc.name, tc.data, tc.id); out.Code < 400 {
			t.Fatalf("invalid file accepted %s", tc.name)
		}
	}
	if _, err := f.db.Exec(`UPDATE care_sessions SET scheduled_at=$2 WHERE id=$1`, f.sessionID, clock.Now().Add(-2*time.Hour)); err != nil {
		t.Fatal(err)
	}
	if out := upload("photo.png", png, ""); out.Code != 403 {
		t.Fatalf("outside-session attachment %d %s", out.Code, out.Body)
	}
}

func TestClinicalMutationsHonorVerificationLinkAndConsent(t *testing.T) {
	for _, permission := range []string{"verification", "link", "consent"} {
		t.Run(permission, func(t *testing.T) {
			f := newClinicalFixture(t)
			var err error
			switch permission {
			case "verification":
				_, err = f.db.Exec(`UPDATE professional_credentials SET verification_status='PENDING' WHERE user_id=$1`, f.prof.ID)
			case "link":
				_, err = f.db.Exec(`UPDATE patient_professional_links SET status='inactive' WHERE patient_id=$1 AND professional_id=$2`, f.patient.ID, f.prof.ID)
			case "consent":
				_, err = f.st.UpdatePatientDataConsent(context.Background(), store.PatientDataConsent{PatientID: f.patient.ID, ProfessionalID: f.prof.ID})
			}
			if err != nil {
				t.Fatal(err)
			}
			for _, tc := range []struct {
				method, path string
				body         any
			}{
				{"POST", "/v1/goals", map[string]string{"patient_id": f.patient.ID, "title": "Forbidden"}},
				{"PUT", "/v1/health-record", map[string]string{"patient_id": f.patient.ID, "diagnosis_summary": "Forbidden"}},
				{"POST", "/v1/medications", map[string]string{"patient_id": f.patient.ID, "name": "Forbidden"}},
			} {
				out := f.call(t, tc.method, tc.path, "professional", f.prof.ID, tc.body)
				if out.Code != 403 {
					t.Fatalf("%s permitted %s: %d %s", permission, tc.path, out.Code, out.Body)
				}
			}
		})
	}
}

func TestClinicalSummaryKeepsAuthoritativeHomeworkSnapshotOnRetry(t *testing.T) {
	f := newClinicalFixture(t)
	goal, err := f.st.CreateGoal(context.Background(), store.UpsertGoalParams{PatientID: f.patient.ID, Title: "Original homework", TargetPerWeek: 4})
	if err != nil {
		t.Fatal(err)
	}
	meta := map[string]any{"session_id": f.sessionID, "goal_ids": []string{goal.ID}, "insight": "Practice"}
	body := map[string]any{"recipient_id": f.patient.ID, "kind": "session_summary", "client_message_id": "9db91620-e60f-4ffd-b95a-a3aaf604536b", "metadata": meta}
	for i := 0; i < 2; i++ {
		out := f.call(t, "POST", "/v1/messages", "professional", f.prof.ID, body)
		if out.Code != 201 {
			t.Fatalf("summary %d %s", out.Code, out.Body)
		}
		var p struct {
			Message struct {
				Metadata struct {
					Goals []struct {
						ID, Title     string
						TargetPerWeek int `json:"target_per_week"`
					} `json:"goals"`
				} `json:"metadata"`
			} `json:"message"`
		}
		_ = json.Unmarshal(out.Body.Bytes(), &p)
		if len(p.Message.Metadata.Goals) != 1 || p.Message.Metadata.Goals[0].Title != "Original homework" || p.Message.Metadata.Goals[0].TargetPerWeek != 4 {
			t.Fatalf("lost authoritative snapshot: %s", out.Body)
		}
		if i == 0 {
			if _, err := f.db.Exec(`UPDATE goals SET title='Edited later' WHERE id=$1`, goal.ID); err != nil {
				t.Fatal(err)
			}
		}
	}
	meta["goals"] = []map[string]string{{"id": goal.ID, "title": "Forged homework"}}
	if out := f.call(t, "POST", "/v1/messages", "professional", f.prof.ID, body); out.Code != 403 {
		t.Fatalf("client forged homework snapshot: %d %s", out.Code, out.Body)
	}
}

func TestClinicalMedicationCreateRetryUsesOneRecordAndRejectsChangedPayload(t *testing.T) {
	f := newClinicalFixture(t)
	token, _ := f.srv.auth.Issue(f.prof.ID, "professional")
	body := map[string]any{"patient_id": f.patient.ID, "name": "  Sertraline  ", "dosage": "50 mg", "form": "Tablet", "reminder_time": "08:00", "relation_to_meal": "Setelah makan", "current_stock": 30, "alert_below": 5, "source": "Profesional"}
	call := func(payload map[string]any) *httptest.ResponseRecorder {
		t.Helper()
		raw, _ := json.Marshal(payload)
		r := httptest.NewRequest("POST", "/v1/medications", bytes.NewReader(raw))
		r.Header.Set("Authorization", "Bearer "+token)
		r.Header.Set("Idempotency-Key", "medication-intent-1")
		out := httptest.NewRecorder()
		f.srv.Routes().ServeHTTP(out, r)
		return out
	}
	var first string
	// The caller treats the first response as lost and retries the same intent.
	for i := 0; i < 2; i++ {
		out := call(body)
		if out.Code != 201 {
			t.Fatalf("medication retry %d %s", out.Code, out.Body)
		}
		var p struct {
			Medication store.Medication `json:"medication"`
		}
		_ = json.Unmarshal(out.Body.Bytes(), &p)
		if i == 0 {
			first = p.Medication.ID
		} else if first != p.Medication.ID {
			t.Fatal("lost-response retry duplicated medication")
		}
	}
	for field, value := range map[string]any{"name": "Changed", "dosage": "100 mg", "form": "Capsule", "reminder_time": "09:00", "relation_to_meal": "Sebelum makan", "current_stock": 31, "alert_below": 6, "source": "Changed source"} {
		changed := map[string]any{}
		for k, v := range body {
			changed[k] = v
		}
		changed[field] = value
		if out := call(changed); out.Code < 400 {
			t.Fatalf("idempotency key accepted changed %s", field)
		}
	}
	// Equivalent normalized input is the same intent, not a new medication.
	body["name"] = "Sertraline"
	body["dosage"] = " 50 mg "
	if out := call(body); out.Code != 201 {
		t.Fatalf("normalized replay failed %d %s", out.Code, out.Body)
	}
	var count int
	if err := f.db.QueryRow(`SELECT count(*) FROM medications WHERE patient_id=$1`, f.patient.ID).Scan(&count); err != nil || count != 1 {
		t.Fatalf("medication count %d err %v", count, err)
	}
}
