package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"strconv"
	"strings"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/security"
	"malva/backend/internal/store"
)

// ============================================================
// SAFETY: Emergency Contacts + Crisis Incidents + SOS Blast
// ============================================================

type emergencyContactRequest struct {
	ContactName  string `json:"contact_name"`
	ContactPhone string `json:"contact_phone"`
	Relationship string `json:"relationship"`
	IsDefault    bool   `json:"is_default"`
}

type crisisAlertRequestV2 struct {
	TriggeredBy string   `json:"triggered_by"`
	PHQ9Q9Score *int     `json:"phq9_q9_score"`
	Latitude    *float64 `json:"latitude"`
	Longitude   *float64 `json:"longitude"`
	Message     string   `json:"message"`
}

type resolveCrisisRequest struct {
	ResolutionNotes string `json:"resolution_notes"`
}

func validateIndonesianPhone(phone string) bool {
	ph := strings.TrimSpace(strings.ReplaceAll(phone, " ", ""))
	ph = strings.ReplaceAll(ph, "-", "")
	ph = strings.ReplaceAll(ph, "(", "")
	ph = strings.ReplaceAll(ph, ")", "")
	ph = strings.TrimPrefix(ph, "+")
	if len(ph) < 9 || len(ph) > 15 {
		return false
	}
	if !strings.HasPrefix(ph, "0") && !strings.HasPrefix(ph, "62") {
		return false
	}
	for _, c := range ph {
		if c < '0' || c > '9' {
			return false
		}
	}
	return true
}

func (s *Server) listEmergencyContacts(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	contacts, err := s.store.ListEmergencyContacts(r.Context(), claims.Subject)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"contacts": contacts})
}

func (s *Server) createEmergencyContact(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	var req emergencyContactRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	// Validasi input dulu (fail-fast) sebelum menyentuh store.
	name := strings.TrimSpace(req.ContactName)
	phone := strings.TrimSpace(req.ContactPhone)
	if name == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "contact_name is required"})
		return
	}
	name = security.SanitizeText(name)
	if name == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "contact_name is required"})
		return
	}
	if len(name) > 100 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "contact_name maksimal 100 karakter"})
		return
	}
	if !validateIndonesianPhone(phone) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "format nomor telepon tidak valid (gunakan 08xxxxxxxxxx atau 62xxxxxxxxxx)"})
		return
	}
	if len(strings.TrimSpace(req.Relationship)) > 50 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "relationship maksimal 50 karakter"})
		return
	}

	count, err := s.store.CountEmergencyContacts(r.Context(), claims.Subject)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if count >= 5 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Maksimal 5 kontak darurat per pasien"})
		return
	}

	c := store.EmergencyContact{
		PatientID:    claims.Subject,
		ContactName:  name,
		ContactPhone: phone,
		Relationship: security.SanitizeText(strings.TrimSpace(req.Relationship)),
		IsDefault:    req.IsDefault,
	}

	created, err := s.store.CreateEmergencyContact(r.Context(), c)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]interface{}{"contact": created})
}

func (s *Server) deleteEmergencyContact(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	contactID := r.PathValue("id")
	if err := s.store.DeleteEmergencyContact(r.Context(), claims.Subject, contactID); err != nil {
		writeError(w, http.StatusNotFound, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"deleted": true})
}

// updateEmergencyContact mengubah nama/nomor/hubungan kontak milik pasien.
func (s *Server) updateEmergencyContact(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	contactID := r.PathValue("id")
	var req emergencyContactRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	name := strings.TrimSpace(req.ContactName)
	phone := strings.TrimSpace(req.ContactPhone)
	if name == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "contact_name is required"})
		return
	}
	name = security.SanitizeText(name)
	if name == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "contact_name is required"})
		return
	}
	if len(name) > 100 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "contact_name maksimal 100 karakter"})
		return
	}
	if !validateIndonesianPhone(phone) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "format nomor telepon tidak valid (gunakan 08xxxxxxxxxx atau 62xxxxxxxxxx)"})
		return
	}
	if len(strings.TrimSpace(req.Relationship)) > 50 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "relationship maksimal 50 karakter"})
		return
	}

	// Beralih ke default: reset default lama lalu set.
	if req.IsDefault {
		if err := s.store.ClearDefaultEmergencyContact(r.Context(), claims.Subject); err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
	}

	c := store.EmergencyContact{
		ID:           contactID,
		PatientID:    claims.Subject,
		ContactName:  name,
		ContactPhone: phone,
		Relationship: security.SanitizeText(strings.TrimSpace(req.Relationship)),
		IsDefault:    req.IsDefault,
	}
	if err := s.store.UpdateEmergencyContact(r.Context(), c); err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "contact not found"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"contact": c})
}

// handleCrisisAlertV2 menerima SOS + persist + notifikasi high-priority + blast ke kontak.
func (s *Server) handleCrisisAlertV2(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	// Rate-limit: 1x per 10 menit per pasien (anti-spam)
	if !s.limits.allow(claims.Subject + ":sos") {
		writeJSON(w, http.StatusTooManyRequests,
			map[string]string{"error": "Terlalu sering mengirim SOS. Tunggu 10 menit."})
		return
	}

	var req crisisAlertRequestV2
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	if req.Latitude != nil && req.Longitude != nil {
		if !s.validateLatLng(*req.Latitude, *req.Longitude) {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid coordinates"})
			return
		}
	}

	triggeredBy := req.TriggeredBy
	if triggeredBy == "" {
		triggeredBy = "sos_button"
	}
	if !s.validTriggeredBy(triggeredBy) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid triggered_by"})
		return
	}

	inc := store.CrisisIncident{
		PatientID:   claims.Subject,
		TriggeredBy: triggeredBy,
		PHQ9Q9Score: req.PHQ9Q9Score,
		Latitude:    req.Latitude,
		Longitude:   req.Longitude,
	}

	created, err := s.store.CreateCrisisIncident(r.Context(), inc)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	// Broadcast crisis alert ke hub (profesionals terpantau real-time)
	event := map[string]interface{}{
		"type": "crisis_alert",
		"data": map[string]interface{}{
			"incident_id":   created.ID,
			"patient_id":    claims.Subject,
			"patient_name":  claims.Subject,
			"triggered_by":  triggeredBy,
			"phq9_q9_score": req.PHQ9Q9Score,
			"latitude":      req.Latitude,
			"longitude":     req.Longitude,
			"message":       req.Message,
			"timestamp":     time.Now().UTC().Format(time.RFC3339),
		},
	}
	s.hub.Broadcast(event)

	// Blast ke kontak: persist log + broadcast. Gunakan background context
	// karena request context dibatalkan setelah handler return.
	patientName := claims.Subject
	if u, err := s.store.GetUserByID(r.Context(), claims.Subject); err == nil && u.DisplayName != "" {
		patientName = u.DisplayName
	}
	go func(patientID, pName, incidentID string, lat, lng *float64) {
		ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
		defer cancel()
		contacts, listErr := s.store.ListEmergencyContacts(ctx, patientID)
		if listErr != nil {
			s.logger.Error("sos list contacts failed", "error", listErr)
		}
		for _, contact := range contacts {
			blastID, err := s.store.CreateSOSBlastLog(ctx, incidentID, contact.ContactPhone, "sms")
			if err == nil {
				msgBody := fmt.Sprintf(
					"HALO %s, %s sedang mengalami krisis kesehatan mental. Mohon segera hubungi. %s",
					contact.ContactName,
					pName,
					mapLink(lat, lng),
				)
				if aerr := s.store.AddAuditLog(ctx, patientID, patientID, "sos_blast.sms", "sos_blast_log", blastID,
					map[string]any{"message": msgBody, "contact": contact.ContactName}); aerr != nil {
					s.logger.Error("sos audit failed", "error", aerr)
				}
				if uerr := s.store.UpdateSOSBlastStatus(ctx, blastID, "sent", blastID); uerr != nil {
					s.logger.Error("sos blast update failed", "error", uerr)
				}
			} else {
				s.logger.Error("sos blast create failed", "error", err)
			}
		}
		_ = s.store.AddAuditLog(ctx, patientID, patientID, "crisis_alert.sos", "crisis_incidents", incidentID,
			map[string]any{"contacts_count": len(contacts), "triggered_by": triggeredBy})
	}(claims.Subject, patientName, created.ID, created.Latitude, created.Longitude)

	writeJSON(w, http.StatusCreated, map[string]interface{}{
		"incident_id": created.ID,
		"status":      "sent",
		"incident":    created,
	})
}

func mapLink(lat, lng *float64) string {
	if lat == nil || lng == nil {
		return ""
	}
	return fmt.Sprintf("https://maps.google.com/?q=%.5f,%.5f", *lat, *lng)
}

func (s *Server) validTriggeredBy(t string) bool {
	switch t {
	case "screening", "sos_button", "manual", "phq9_q9", "silent_sos":
		return true
	}
	return false
}

func (s *Server) validateLatLng(lat, lng float64) bool {
	return lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180
}

func (s *Server) listCrisisIncidents(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	patientID, err := s.authorizePatientAccess(r, claims, r.URL.Query().Get("patient_id"))
	if err != nil {
		writeError(w, http.StatusForbidden, err)
		return
	}
	limit := parseQueryInt(r, "limit", 20, 100)
	incidents, err := s.store.ListCrisisIncidents(r.Context(), patientID, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"incidents": incidents})
}

func (s *Server) resolveCrisisIncident(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	var req resolveCrisisRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	if strings.TrimSpace(req.ResolutionNotes) == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "resolution_notes is required"})
		return
	}

	incidentID := r.PathValue("id")
	if claims.Role == "professional" {
		incident, err := s.store.GetCrisisIncident(r.Context(), incidentID)
		if err != nil {
			writeError(w, http.StatusNotFound, err)
			return
		}
		linked, err := s.store.ProfessionalLinkedToPatient(r.Context(), claims.Subject, incident.PatientID)
		if err != nil || !linked {
			writeError(w, http.StatusForbidden, errors.New("professional is not linked to this patient"))
			return
		}
	}
	resolved, err := s.store.ResolveCrisisIncident(r.Context(), incidentID, claims.Subject, req.ResolutionNotes)
	if err != nil {
		writeError(w, http.StatusNotFound, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"incident": resolved})
}

func (s *Server) listBlastStatus(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	incidentID := r.URL.Query().Get("incident_id")
	if incidentID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "incident_id is required"})
		return
	}
	status, err := s.store.SOSBlastStatusForIncident(r.Context(), incidentID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"blast": status})
}

// ============================================================
// PROFESSIONAL: Credentials + Doctor Discovery
// ============================================================

type uploadCredentialsRequest struct {
	STRNumber       string        `json:"str_number"`
	SIPNumber       string        `json:"sip_number"`
	SIPPNumber      string        `json:"sipp_number"`
	Specialization  string        `json:"specialization"`
	SubSpecialties  []string      `json:"sub_specialties"`
	HospitalLat     *float64      `json:"hospital_lat"`
	HospitalLng     *float64      `json:"hospital_lng"`
	HospitalName    string        `json:"hospital_name"`
	AddressDetails  string        `json:"address_details"`
	IsBPJSSupported bool          `json:"is_bpjs_supported"`
	PhotoIntroURL   string        `json:"photo_intro_url"`
	VideoIntroURL   string        `json:"video_intro_url"`
	Bio             string        `json:"bio"`
	Education       []interface{} `json:"education"`
	DocumentURL     string        `json:"document_url"`
}

func (s *Server) uploadCredentials(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "professional" {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "Only professionals can upload credentials"})
		return
	}
	var req uploadCredentialsRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	if req.Specialization == "" {
		req.Specialization = "M.Psi"
	}
	if !validSpecialization(req.Specialization) {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "specialization tidak dikenal (contoh: Sp.KJ, M.Psi)"})
		return
	}
	if req.HospitalLat != nil && req.HospitalLng != nil {
		if !s.validateLatLng(*req.HospitalLat, *req.HospitalLng) {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "Invalid hospital coordinates"})
			return
		}
	}

	// Pertahankan harga & pengalaman yang diset admin agar tidak ter-nol-kan
	// saat profesional memperbarui kredensialnya sendiri.
	yearsExperience, priceFrom := 0, int64(0)
	if existing, err := s.store.GetProfessionalCredential(r.Context(), claims.Subject); err == nil {
		yearsExperience, priceFrom = existing.YearsExperience, existing.PriceFrom
	}
	cred, err := s.store.UpsertProfessionalCredential(r.Context(), store.ProfessionalCredential{
		UserID:          claims.Subject,
		STRNumber:       req.STRNumber,
		SIPNumber:       req.SIPNumber,
		SIPPNumber:      req.SIPPNumber,
		Specialization:  req.Specialization,
		SubSpecialties:  req.SubSpecialties,
		HospitalLat:     req.HospitalLat,
		HospitalLng:     req.HospitalLng,
		HospitalName:    req.HospitalName,
		AddressDetails:  req.AddressDetails,
		IsBPJSSupported: req.IsBPJSSupported,
		PhotoIntroURL:   req.PhotoIntroURL,
		VideoIntroURL:   req.VideoIntroURL,
		Bio:             req.Bio,
		Education:       req.Education,
		DocumentURL:     req.DocumentURL,
		YearsExperience: yearsExperience,
		PriceFrom:       priceFrom,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]interface{}{
		"credential":          cred,
		"verification_status": cred.VerificationStatus,
	})
}

func (s *Server) getMyCredentials(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	cred, err := s.store.GetProfessionalCredential(r.Context(), claims.Subject)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "No credentials submitted yet"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"credential": cred})
}

func (s *Server) searchDoctors(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	_ = claims
	params := store.DoctorSearchParams{Limit: parseQueryInt(r, "limit", 50, 100)}
	if v := r.URL.Query().Get("patient_lat"); v != "" {
		if f, err := strconv.ParseFloat(v, 64); err == nil {
			params.PatientLat = &f
		}
	}
	if v := r.URL.Query().Get("patient_lng"); v != "" {
		if f, err := strconv.ParseFloat(v, 64); err == nil {
			params.PatientLng = &f
		}
	}
	params.Specialization = r.URL.Query().Get("specialization")
	params.SortBy = r.URL.Query().Get("sort_by")
	if v := r.URL.Query().Get("max_price"); v != "" {
		if p, err := strconv.ParseInt(v, 10, 64); err == nil {
			params.MaxPrice = &p
		}
	}
	if v := r.URL.Query().Get("max_km"); v != "" {
		if f, err := strconv.ParseFloat(v, 64); err == nil {
			params.MaxKM = &f
		}
	}
	// Klien mengirim is_bpjs_supported (is_bpjs dipertahankan sebagai alias).
	if v := r.URL.Query().Get("is_bpjs_supported"); v != "" {
		b := v == "true" || v == "1"
		params.IsBPJSSupported = &b
	} else if v := r.URL.Query().Get("is_bpjs"); v != "" {
		b := v == "true" || v == "1"
		params.IsBPJSSupported = &b
	}

	results, err := s.store.SearchDoctors(r.Context(), params)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"doctors": results})
}

func (s *Server) getDoctorProfile(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	_ = claims
	userID := r.PathValue("user_id")
	if userID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "user_id is required"})
		return
	}
	cred, err := s.store.GetProfessionalCredential(r.Context(), userID)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "Doctor not found or not verified"})
		return
	}
	if cred.VerificationStatus != "VERIFIED" {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "Doctor profile not publicly available until verified"})
		return
	}
	packages, _ := s.store.ListServicePackages(r.Context(), userID)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"credential": cred,
		"packages":   packages,
	})
}

func (s *Server) getDoctorAvailableSlots(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	_ = claims
	userID := r.PathValue("user_id")
	dateStr := r.URL.Query().Get("date")
	if dateStr == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "date is required (YYYY-MM-DD)"})
		return
	}
	target, err := time.Parse("2006-01-02", dateStr)
	if err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid date format"})
		return
	}

	schedules, err := s.store.ListSchedulesForProfessional(r.Context(), userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	dayOfWeek := int(target.Weekday())

	var slots []interface{}
	for _, sch := range schedules {
		if sch.DayOfWeek != dayOfWeek {
			continue
		}
		start, _ := time.Parse("15:04", sch.StartTime)
		end, _ := time.Parse("15:04", sch.EndTime)
		for t := start; t.Before(end); t = t.Add(time.Duration(sch.SlotDurationMinutes) * time.Minute) {
			slot := t.Format("15:04")
			slots = append(slots, map[string]interface{}{
				"time":      slot,
				"available": true,
			})
		}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"slots": slots, "date": dateStr})
}

func (s *Server) requireVerifiedProfessional(w http.ResponseWriter, r *http.Request, claims auth.Claims) bool {
	if claims.Role != "professional" {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "Only professionals can access this resource"})
		return false
	}
	cred, err := s.store.GetProfessionalCredential(r.Context(), claims.Subject)
	if err != nil || cred.VerificationStatus != "VERIFIED" {
		writeJSON(w, http.StatusForbidden, map[string]string{
			"error":               "Your STR/SIP are still PENDING. Please wait for admin verification.",
			"verification_status": cred.VerificationStatus,
		})
		return false
	}
	return true
}

func parseQueryInt(r *http.Request, name string, defaultVal, max int) int {
	if v := r.URL.Query().Get(name); v != "" {
		if n, err := strconv.Atoi(v); err == nil && n > 0 && n <= max {
			return n
		}
	}
	return defaultVal
}
