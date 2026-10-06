package server

import (
	"database/sql"
	"encoding/json"
	"errors"
	"net/http"
	"strings"

	"malva/backend/internal/auth"
	"malva/backend/internal/security"
	"malva/backend/internal/store"
)

// ============================================================
// GOALS & HABITS — pasien menulis, profesional membaca (bila terkait)
// ============================================================

type goalRequest struct {
	Title         string `json:"title"`
	Category      string `json:"category"`
	TargetPerWeek *int   `json:"target_per_week"`
	IsActive      *bool  `json:"is_active"`
	PatientID     string `json:"patient_id"`
}

type habitLogRequest struct {
	GoalID   string `json:"goal_id"`
	LoggedOn string `json:"logged_on"`
	Date     string `json:"date"` // alias kompatibilitas
	Done     *bool  `json:"done"`
}

// resolvePatientScope menentukan patient_id yang boleh diakses:
// pasien = dirinya sendiri; profesional = pasien yang terhubung.
func (s *Server) resolvePatientScope(r *http.Request, claims auth.Claims, requested string) (string, bool, error) {
	requested = strings.TrimSpace(requested)
	if claims.Role == "patient" || claims.Role == "admin" {
		if requested != "" && requested != claims.Subject && claims.Role == "patient" {
			return "", false, errors.New("pasien hanya boleh mengakses datanya sendiri")
		}
		if requested == "" {
			requested = claims.Subject
		}
		return requested, requested == claims.Subject, nil
	}
	// Profesional: harus ada relasi aktif dengan pasien tsb.
	if requested == "" {
		return "", false, errors.New("patient_id wajib diisi untuk profesional")
	}
	_, _, linked, err := s.store.AreUsersLinked(r.Context(), requested, claims.Subject)
	if err != nil {
		return "", false, err
	}
	if !linked {
		return "", false, errors.New("pasien tidak terhubung dengan anda")
	}
	return requested, false, nil
}

func (s *Server) listGoals(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	patientID, _, err := s.resolvePatientScope(r, claims, r.URL.Query().Get("patient_id"))
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	includeInactive := r.URL.Query().Get("include_inactive") == "true"
	goals, err := s.store.ListGoals(r.Context(), patientID, includeInactive)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"goals": goals})
}

func (s *Server) createGoal(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	var req goalRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	patientID, isSelf, err := s.resolvePatientScope(r, claims, req.PatientID)
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	if !isSelf && claims.Role != "admin" {
		writeError(w, http.StatusForbidden, errors.New("hanya pasien yang bisa menambah goals."))
		return
	}
	title := security.SanitizeText(strings.TrimSpace(req.Title))
	if title == "" {
		writeError(w, http.StatusBadRequest, errors.New("title wajib diisi."))
		return
	}
	if len(title) > 200 {
		writeError(w, http.StatusBadRequest, errors.New("title maksimal 200 karakter."))
		return
	}
	category := strings.ToLower(security.SanitizeText(strings.TrimSpace(req.Category)))
	target := 0
	if req.TargetPerWeek != nil {
		target = *req.TargetPerWeek
	}
	goal, err := s.store.CreateGoal(r.Context(), store.UpsertGoalParams{
		PatientID:     patientID,
		Title:         title,
		Category:      category,
		TargetPerWeek: target,
	})
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"goal": goal})
}

func (s *Server) updateGoal(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	goalID := r.PathValue("goal_id")
	var req goalRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	patientID, isSelf, err := s.resolvePatientScope(r, claims, req.PatientID)
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	if !isSelf && claims.Role != "admin" {
		writeError(w, http.StatusForbidden, errors.New("hanya pasien yang bisa mengubah goals."))
		return
	}
	goal, err := s.store.UpdateGoal(r.Context(), patientID, goalID,
		security.SanitizeText(req.Title), security.SanitizeText(strings.ToLower(req.Category)),
		req.TargetPerWeek, req.IsActive)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, errors.New("Goal tidak ditemukan."))
			return
		}
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"goal": goal})
}

func (s *Server) deleteGoal(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	goalID := r.PathValue("goal_id")
	patientID := r.URL.Query().Get("patient_id")
	scopeID, isSelf, err := s.resolvePatientScope(r, claims, patientID)
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	if !isSelf && claims.Role != "admin" {
		writeError(w, http.StatusForbidden, errors.New("hanya pasien yang bisa menghapus goals."))
		return
	}
	if err := s.store.DeleteGoal(r.Context(), scopeID, goalID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, errors.New("Goal tidak ditemukan."))
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

func (s *Server) listHabitLogs(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	patientID, _, err := s.resolvePatientScope(r, claims, r.URL.Query().Get("patient_id"))
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	logs, err := s.store.ListHabitLogs(r.Context(), patientID,
		r.URL.Query().Get("from"), r.URL.Query().Get("to"))
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"logs": logs})
}

func (s *Server) logHabit(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	var req habitLogRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	goalID := strings.TrimSpace(req.GoalID)
	if goalID == "" {
		writeError(w, http.StatusBadRequest, errors.New("goal_id wajib diisi."))
		return
	}
	// Pasien hanya bisa menandai goal miliknya sendiri.
	if claims.Role != "patient" {
		writeError(w, http.StatusForbidden, errors.New("hanya pasien yang bisa mencatat habit."))
		return
	}
	logged := strings.TrimSpace(req.LoggedOn)
	if logged == "" {
		logged = strings.TrimSpace(req.Date)
	}
	done := true
	if req.Done != nil {
		done = *req.Done
	}
	log, err := s.store.LogHabit(r.Context(), claims.Subject, goalID, logged, done)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, errors.New("Goal tidak ditemukan."))
			return
		}
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"log": log})
}

// ============================================================
// THERAPY SUBMISSIONS — simpan worksheet, unduh, bagikan ke profesional
// ============================================================

type therapySubmissionRequest struct {
	ModuleID  string          `json:"module_id"`
	Title     string          `json:"title"`
	Answers   json.RawMessage `json:"answers"`
	Summary   string          `json:"summary"`
	PatientID string          `json:"patient_id"`
}

type therapyShareRequest struct {
	ProfessionalID string `json:"professional_id"`
}

const maxTherapyModuleID = 64
const maxTherapyAnswersBytes = 64 * 1024

func (s *Server) listTherapySubmissions(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	// Profesional melihat yang dibagikan ke dirinya; pasien melihat miliknya.
	professionalView := claims.Role == "professional"
	if professionalView && r.URL.Query().Get("patient_id") != "" {
		// Profesional menelusuri submission satu pasien yang terhubung.
		patientID, _, err := s.resolvePatientScope(r, claims, r.URL.Query().Get("patient_id"))
		if err != nil {
			writeError(w, http.StatusForbidden, err)
			return
		}
		all, err := s.store.ListTherapySubmissions(r.Context(), patientID, false)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		shared := make([]store.TherapySubmission, 0, len(all))
		for _, sub := range all {
			if sub.SharedWithProfessionalID != nil && *sub.SharedWithProfessionalID == claims.Subject {
				shared = append(shared, sub)
			}
		}
		writeJSON(w, http.StatusOK, map[string]any{"submissions": shared})
		return
	}
	owner := claims.Subject
	submissions, err := s.store.ListTherapySubmissions(r.Context(), owner, professionalView)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"submissions": submissions})
}

func (s *Server) createTherapySubmission(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "patient" {
		writeError(w, http.StatusForbidden, errors.New("hanya pasien yang bisa menyimpan worksheet."))
		return
	}
	var req therapySubmissionRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	moduleID := strings.TrimSpace(req.ModuleID)
	if moduleID == "" || len(moduleID) > maxTherapyModuleID {
		writeError(w, http.StatusBadRequest, errors.New("module_id tidak valid."))
		return
	}
	if len(req.Answers) > maxTherapyAnswersBytes {
		writeError(w, http.StatusBadRequest, errors.New("jawaban terlalu besar (maks 64 KB)."))
		return
	}
	title := security.SanitizeText(strings.TrimSpace(req.Title))
	summary := security.SanitizeText(strings.TrimSpace(req.Summary))
	sub, err := s.store.CreateTherapySubmission(r.Context(), claims.Subject, moduleID,
		title, req.Answers, summary, nil)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"submission": sub})
}

func (s *Server) getTherapySubmission(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	submissionID := r.PathValue("submission_id")
	professionalView := claims.Role == "professional"
	sub, err := s.store.GetTherapySubmission(r.Context(), claims.Subject, submissionID, professionalView)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, errors.New("Worksheet tidak ditemukan."))
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"submission": sub})
}

func (s *Server) shareTherapySubmission(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "patient" {
		writeError(w, http.StatusForbidden, errors.New("hanya pasien yang bisa membagikan worksheet."))
		return
	}
	submissionID := r.PathValue("submission_id")
	var req therapyShareRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	professionalID := strings.TrimSpace(req.ProfessionalID)
	if professionalID != "" {
		_, _, linked, err := s.store.AreUsersLinked(r.Context(), claims.Subject, professionalID)
		if err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
		if !linked {
			writeError(w, http.StatusForbidden, errors.New("Kamu belum terhubung dengan profesional tersebut."))
			return
		}
	}
	sub, err := s.store.ShareTherapySubmission(r.Context(), claims.Subject, submissionID, professionalID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, errors.New("Worksheet tidak ditemukan."))
			return
		}
		writeError(w, http.StatusBadRequest, err)
		return
	}
	// Notifikasi ke profesional (in-app) bila dibagikan.
	if professionalID != "" {
		s.notifyPatient(r, professionalID, "therapy_shared",
			"Worksheet terapi baru dibagikan oleh pasien.",
			"Pasien membagikan worksheet terapi untuk kamu tinjau.",
			map[string]string{"submission_id": sub.ID, "module_id": sub.ModuleID})
	}
	writeJSON(w, http.StatusOK, map[string]any{"submission": sub})
}

func (s *Server) deleteTherapySubmission(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "patient" {
		writeError(w, http.StatusForbidden, errors.New("hanya pasien yang bisa menghapus worksheet."))
		return
	}
	submissionID := r.PathValue("submission_id")
	if err := s.store.DeleteTherapySubmission(r.Context(), claims.Subject, submissionID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, errors.New("Worksheet tidak ditemukan."))
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}
