package store

import (
	"bytes"
	"context"
	"crypto/sha256"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
)

func ClinicalRetryID(namespace, senderID, key string) string {
	hash := sha256.Sum256([]byte(namespace + "\x00" + senderID + "\x00" + key))
	hash[6] = (hash[6] & 0x0f) | 0x40
	hash[8] = (hash[8] & 0x3f) | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", hash[0:4], hash[4:6], hash[6:8], hash[8:10], hash[10:16])
}

func ValidClinicalClientID(id string) bool {
	if len(id) != 36 {
		return false
	}
	for i, c := range id {
		if i == 8 || i == 13 || i == 18 || i == 23 {
			if c != '-' {
				return false
			}
			continue
		}
		if (c < '0' || c > '9') && (c < 'a' || c > 'f') && (c < 'A' || c > 'F') {
			return false
		}
	}
	return true
}

type clinicalGoalSnapshot struct {
	ID            string `json:"id"`
	Title         string `json:"title"`
	TargetPerWeek int    `json:"target_per_week"`
}

// ValidateProfessionalChatCard is shared by REST and WebSocket so neither
// transport can bypass clinical consent, references, or the session boundary.
func (s *Store) ValidateProfessionalChatCard(ctx context.Context, patientID, professionalID, kind string, raw json.RawMessage, access ChatAccess) (json.RawMessage, error) {
	denied := errors.New("kartu klinis tidak valid atau tidak diizinkan untuk sesi ini")
	if !access.InSession || access.SessionID == "" || len(raw) > 8192 {
		return nil, denied
	}
	if kind != "assessment_request" && kind != "session_summary" && kind != "goals" {
		// Attachments are created only by the authenticated upload endpoint.
		return nil, denied
	}
	_, _, linked, err := s.AreUsersLinked(ctx, patientID, professionalID)
	if err != nil || !linked {
		return nil, denied
	}
	cred, err := s.GetProfessionalCredential(ctx, professionalID)
	if err != nil || cred.VerificationStatus != "VERIFIED" {
		return nil, denied
	}
	var meta struct {
		SessionID string   `json:"session_id"`
		ModuleID  string   `json:"module_id,omitempty"`
		GoalIDs   []string `json:"goal_ids,omitempty"`
		Insight   string   `json:"insight,omitempty"`
	}
	decoder := json.NewDecoder(bytes.NewReader(raw))
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(&meta); err != nil || meta.SessionID != access.SessionID {
		return nil, denied
	}
	var snapshots []clinicalGoalSnapshot
	if kind == "assessment_request" {
		if (meta.ModuleID != "screening" && meta.ModuleID != "dass21" && meta.ModuleID != "who5") || len(meta.GoalIDs) != 0 || meta.Insight != "" {
			return nil, denied
		}
	} else {
		meta.Insight = strings.TrimSpace(meta.Insight)
		if meta.ModuleID != "" || len(meta.GoalIDs) > 20 || len(meta.Insight) > 2000 {
			return nil, denied
		}
		if kind == "goals" && (len(meta.GoalIDs) == 0 || meta.Insight != "") {
			return nil, denied
		}
		if kind == "session_summary" && len(meta.GoalIDs) == 0 && meta.Insight == "" {
			return nil, denied
		}
		if len(meta.GoalIDs) > 0 {
			active, err := s.PatientDataAccessActive(ctx, patientID, professionalID)
			if err != nil || !active {
				return nil, denied
			}
			consent, err := s.GetPatientDataConsent(ctx, patientID, professionalID)
			if err != nil || !consent.ShareGoals {
				return nil, denied
			}
			seen := map[string]bool{}
			for _, id := range meta.GoalIDs {
				if id == "" || seen[id] {
					return nil, denied
				}
				var goal clinicalGoalSnapshot
				if err := s.db.QueryRowContext(ctx, `SELECT id,title,target_per_week FROM goals WHERE id::text=$1 AND patient_id=$2 AND is_active`, id, patientID).Scan(&goal.ID, &goal.Title, &goal.TargetPerWeek); err != nil {
					return nil, denied
				}
				snapshots = append(snapshots, goal)
				seen[id] = true
			}
		}
	}
	metadata, _ := json.Marshal(meta)
	if len(snapshots) > 0 {
		var enriched map[string]any
		_ = json.Unmarshal(metadata, &enriched)
		enriched["goals"] = snapshots
		return json.Marshal(enriched)
	}
	return metadata, nil
}

// GetChatAttachment authorizes against the persisted message pair, so an ended
// session or a removed current link does not erase access to chat history.
func (s *Store) GetChatAttachment(ctx context.Context, messageID, userID string) (ChatMessage, error) {
	var msg ChatMessage
	err := s.db.QueryRowContext(ctx, `SELECT id,patient_id,professional_id,sender_id,sender_name,text,kind,attachment_meta,created_at
		FROM chat_messages WHERE id=$1 AND kind='attachment' AND (patient_id=$2 OR professional_id=$2)`, messageID, userID).
		Scan(&msg.ID, &msg.PatientID, &msg.ProfessionalID, &msg.SenderID, &msg.SenderName, &msg.Text, &msg.Kind, &msg.Metadata, &msg.CreatedAt)
	if err != nil {
		return ChatMessage{}, err
	}
	var meta struct {
		AttachmentID string `json:"attachment_id"`
	}
	if json.Unmarshal(msg.Metadata, &meta) != nil || meta.AttachmentID != msg.ID {
		return ChatMessage{}, sql.ErrNoRows
	}
	return msg, nil
}
