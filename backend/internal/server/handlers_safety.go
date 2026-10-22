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
	TriggeredBy   string   `json:"triggered_by"`
	PHQ9Q9Score   *int     `json:"phq9_q9_score"`
	Latitude      *float64 `json:"latitude"`
	Longitude     *float64 `json:"longitude"`
	Message       string   `json:"message"`
	ContactPhones []string `json:"contact_phones,omitempty"`
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

	// Ambil nama tampilan pasien sekali di sini — dipakai baik untuk broadcast
	// realtime ke profesional maupun pesan WhatsApp ke kontak darurat.
	// Sebelumnya broadcast memakai claims.Subject (UUID), sehingga profesional
	// melihat ID acak alih-alih nama pasien saat notifikasi krisis masuk.
	patientName := claims.Subject
	if u, err := s.store.GetUserByID(r.Context(), claims.Subject); err == nil && u.DisplayName != "" {
		patientName = u.DisplayName
	}

	// Broadcast crisis alert ke hub (profesionals terpantau real-time)
	event := map[string]interface{}{
		"type": "crisis_alert",
		"data": map[string]interface{}{
			"incident_id":   created.ID,
			"patient_id":    claims.Subject,
			"patient_name":  patientName,
			"triggered_by":  triggeredBy,
			"phq9_q9_score": req.PHQ9Q9Score,
			"latitude":      req.Latitude,
			"longitude":     req.Longitude,
			"message":       req.Message,
			"timestamp":     time.Now().UTC().Format(time.RFC3339),
		},
	}
	s.hub.Broadcast(event)

	// Blast ke kontak: kirim WhatsApp SUNGGUHAN via Fonnte lalu catat status
	// sesuai hasil nyata gateway. Berjalan di background karena request
	// context dibatalkan setelah handler return.
	deliveryConfigured := s.sos != nil
	channel := "whatsapp"
	status := "queued"
	if !deliveryConfigured {
		channel = "none"
		status = "unconfigured"
	}
	go func(patientID, pName, incidentID, channel string, lat, lng *float64, filterPhones []string) {
		ctx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
		defer cancel()
		contacts, listErr := s.store.ListEmergencyContacts(ctx, patientID)
		if listErr != nil {
			s.logger.Error("sos list contacts failed", "error", listErr)
		}
		// Bila pasien memilih kontak tertentu (contact_phones tidak kosong),
		// hanya kirim ke kontak yang nomornya ada di daftar pilihan. Kontak
		// lain dilewati tanpa error — ini bukan kegagalan, melainkan pilihan
		// eksplisit pasien.
		filterSet := make(map[string]bool, len(filterPhones))
		for _, ph := range filterPhones {
			filterSet[strings.TrimSpace(ph)] = true
		}
		hasFilter := len(filterSet) > 0
		sentCount := 0
		for _, contact := range contacts {
			if hasFilter && !filterSet[strings.TrimSpace(contact.ContactPhone)] {
				continue
			}
			blastID, err := s.store.CreateSOSBlastLog(ctx, incidentID, contact.ContactPhone, channel)
			if err != nil {
				s.logger.Error("sos blast create failed", "error", err)
				continue
			}
			msgBody := fmt.Sprintf(
				"HALO %s, %s sedang mengalami krisis kesehatan mental. Mohon segera hubungi. %s",
				contact.ContactName,
				pName,
				mapLink(lat, lng),
			)
			if !deliveryConfigured {
				// Tidak ada transport: jangan pernah menandai 'sent'.
				if uerr := s.store.UpdateSOSBlastStatus(ctx, blastID, "failed", ""); uerr != nil {
					s.logger.Error("sos blast update failed", "error", uerr)
				}
				continue
			}
			msgID, sendErr := s.sos.Send(ctx, contact.ContactPhone, msgBody)
			if sendErr != nil {
				s.logger.Error("sos blast send failed", "contact", contact.ContactName, "error", sendErr)
				if uerr := s.store.UpdateSOSBlastStatus(ctx, blastID, "failed", ""); uerr != nil {
					s.logger.Error("sos blast update failed", "error", uerr)
				}
				if aerr := s.store.AddAuditLog(ctx, patientID, patientID, "sos_blast.failed", "sos_blast_log", blastID,
					map[string]any{"error": sendErr.Error(), "contact": contact.ContactName}); aerr != nil {
					s.logger.Error("sos audit failed", "error", aerr)
				}
				continue
			}
			sentCount++
			if uerr := s.store.UpdateSOSBlastStatus(ctx, blastID, "sent", msgID); uerr != nil {
				s.logger.Error("sos blast update failed", "error", uerr)
			}
			if aerr := s.store.AddAuditLog(ctx, patientID, patientID, "sos_blast.whatsapp", "sos_blast_log", blastID,
				map[string]any{"message": msgBody, "contact": contact.ContactName, "message_id": msgID}); aerr != nil {
				s.logger.Error("sos audit failed", "error", aerr)
			}
		}
		_ = s.store.AddAuditLog(ctx, patientID, patientID, "crisis_alert.sos", "crisis_incidents", incidentID,
			map[string]any{
				"contacts_count": len(contacts),
				"sent_count":     sentCount,
				"channel":        channel,
				"triggered_by":   triggeredBy,
			})
	}(claims.Subject, patientName, created.ID, channel, created.Latitude, created.Longitude, req.ContactPhones)

	// Status jujur: pesan baru masuk antrean kirim, belum tentu terkirim.
	// Status per kontak bisa dipantau lewat GET /v1/sos-blast-status.
	writeJSON(w, http.StatusCreated, map[string]interface{}{
		"incident_id":         created.ID,
		"status":              status,
		"channel":             channel,
		"delivery_configured": deliveryConfigured,
		"incident":            created,
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
	// Siarkan perubahan profil (foto/video intro) ke pasien terhubung agar
	// tampilan di sisi pasien ikut terbarui tanpa refresh manual.
	s.broadcastProfessionalProfileUpdate(r.Context(), claims.Subject)
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
	schedules, _ := s.store.ListActiveSchedulesForProfessional(r.Context(), userID)
	pricing, _ := s.store.GetProfessionalPricing(r.Context(), userID)
	reviews, _ := s.store.ListDoctorReviews(r.Context(), userID, 10)
	if reviews == nil {
		reviews = []store.DoctorReview{}
	}
	rating, _ := s.store.DoctorRating(r.Context(), userID)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"credential": cred,
		"packages":   packages,
		"schedules":  schedules,
		"pricing":    pricing,
		"reviews":    reviews,
		"rating":     rating,
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

	schedules, err := s.store.ListActiveSchedulesForProfessional(r.Context(), userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	dayOfWeek := int(target.Weekday())

	// Beberapa driver mengembalikan TIME sebagai "15:04:05"; terima keduanya.
	parseClock := func(v string) (time.Time, bool) {
		v = strings.TrimSpace(v)
		for _, layout := range []string{"15:04:05", "15:04"} {
			if t, err := time.Parse(layout, v); err == nil {
				return t, true
			}
		}
		return time.Time{}, false
	}

	// Hari libur profesional: tidak ada slot sama sekali.
	if off, err := s.store.ListTimeOff(r.Context(), userID, dateStr, dateStr); err == nil && len(off) > 0 {
		writeJSON(w, http.StatusOK, map[string]interface{}{
			"slots": []interface{}{}, "date": dateStr, "off": true,
		})
		return
	}
	// Tandai slot yang sudah terisi sesi (pending/scheduled) agar tidak double-book.
	dayStart := time.Date(target.Year(), target.Month(), target.Day(), 0, 0, 0, 0, wibLoc)
	booked := map[string]bool{}
	if sessions, err := s.store.ListCareSessions(r.Context(), userID, "professional", "all", "", 200); err == nil {
		for _, cs := range sessions {
			if cs.Status != "scheduled" && cs.Status != "pending_payment" {
				continue
			}
			local := cs.ScheduledAt.In(wibLoc)
			if local.Year() == target.Year() && local.Month() == target.Month() && local.Day() == target.Day() {
				booked[local.Format("15:04")] = true
			}
		}
	}
	_ = dayStart
	nowWIB := time.Now().In(wibLoc)

	slots := make([]interface{}, 0)
	for _, sch := range schedules {
		if sch.DayOfWeek != dayOfWeek {
			continue
		}
		start, okStart := parseClock(sch.StartTime)
		end, okEnd := parseClock(sch.EndTime)
		if !okStart || !okEnd || !start.Before(end) {
			continue
		}
		step := time.Duration(sch.SlotDurationMinutes) * time.Minute
		if step <= 0 {
			step = 30 * time.Minute
		}
		for t := start; t.Add(step).Before(end) || t.Add(step).Equal(end); t = t.Add(step) {
			label := t.Format("15:04")
			available := !booked[label]
			// Lead time 24 jam: sesi butuh persiapan kedua belah pihak
			// (aturan yang sama dipakai createBooking/validateSlot).
			slotTime, _ := time.ParseInLocation("2006-01-02 15:04", dateStr+" "+label, wibLoc)
			if !slotTime.After(nowWIB.Add(24 * time.Hour)) {
				available = false
			}
			slots = append(slots, map[string]interface{}{
				"time":      label,
				"available": available,
			})
		}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"slots": slots, "date": dateStr})
}

// getDoctorAvailability ringkasan 14 hari ke depan: hari praktik, libur,
// dan jumlah slot bebas (tanpa rincian jam).
func (s *Server) getDoctorAvailability(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	_ = claims
	userID := r.PathValue("user_id")
	if userID == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "user_id is required"})
		return
	}
	schedules, err := s.store.ListActiveSchedulesForProfessional(r.Context(), userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	nowWIB := time.Now().In(wibLoc)
	startDate := time.Date(nowWIB.Year(), nowWIB.Month(), nowWIB.Day(), 0, 0, 0, 0, wibLoc)
	endDate := startDate.AddDate(0, 0, 13)

	// Satu query untuk hari libur seluruh 14 hari (sebelumnya satu query per hari).
	offDates := map[string]bool{}
	if offs, err := s.store.ListTimeOff(r.Context(), userID,
		startDate.Format("2006-01-02"), endDate.Format("2006-01-02")); err == nil {
		for _, o := range offs {
			offDates[o.OffDate] = true
		}
	}

	parseClockLocal := func(v string) (int, bool) {
		v = strings.TrimSpace(v)
		for _, layout := range []string{"15:04:05", "15:04"} {
			if t, err := time.Parse(layout, v); err == nil {
				return t.Hour()*60 + t.Minute(), true
			}
		}
		return 0, false
	}

	// Langkah 1 — kumpulkan semua slot kandidat tanpa menyentuh database.
	candidates := make([][]time.Time, 14)
	allTimes := make([]time.Time, 0, 128)
	for i := 0; i < 14; i++ {
		day := startDate.AddDate(0, 0, i)
		dateStr := day.Format("2006-01-02")
		if offDates[dateStr] {
			continue
		}
		dayOfWeek := int(day.Weekday())
		for _, sch := range schedules {
			if sch.DayOfWeek != dayOfWeek {
				continue
			}
			step := sch.SlotDurationMinutes
			if step <= 0 {
				step = 30
			}
			startMin, ok1 := parseClockLocal(sch.StartTime)
			endMin, ok2 := parseClockLocal(sch.EndTime)
			if !ok1 || !ok2 || endMin <= startMin {
				continue
			}
			for m := startMin; m+step <= endMin; m += step {
				h, mm := m/60, m%60
				label := fmt.Sprintf("%02d:%02d", h, mm)
				slotTime, err := time.ParseInLocation("2006-01-02 15:04", dateStr+" "+label, wibLoc)
				if err != nil {
					continue
				}
				// PERBAIKAN BUG #4: filter 24 jam dipindahkan ke validateSlot
				// (saat booking). Endpoint ketersediaan harus menampilkan SEMUA
				// slot agar pasien melihat jadwal yang baru ditambahkan profesional.
				// Sebelumnya slot dalam 24 jam disembunyikan sehingga jadwal hari
				// ini tampak kosong di sisi pasien meskipun aktif di sisi profesional.
				if !slotTime.After(nowWIB) {
					continue
				}
				candidates[i] = append(candidates[i], slotTime)
				allTimes = append(allTimes, slotTime)
			}
		}
	}

	// Langkah 2 — satu query untuk semua slot terisi. Sebelumnya IsSlotBooked
	// dipanggil per slot, sehingga satu permintaan ketersediaan bisa menembak
	// ±224 query ke database dan menjadikan endpoint ini yang paling berat.
	booked := map[string]bool{}
	if b, err := s.store.CountBookedSessions(r.Context(), userID, allTimes); err == nil {
		booked = b
	}

	// Langkah 3 — susun respons dari hasil dua langkah di atas.
	days := make([]interface{}, 0, 14)
	for i := 0; i < 14; i++ {
		day := startDate.AddDate(0, 0, i)
		dateStr := day.Format("2006-01-02")
		freeSlots := 0
		for _, slotTime := range candidates[i] {
			if !booked[slotTime.UTC().Format(time.RFC3339)] {
				freeSlots++
			}
		}
		days = append(days, map[string]interface{}{
			"date":        dateStr,
			"day_of_week": int(day.Weekday()),
			"off":         offDates[dateStr],
			"free_slots":  freeSlots,
		})
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"days": days})
}

type scheduleInput struct {
	DayOfWeek           int    `json:"day_of_week"`
	StartTime           string `json:"start_time"`
	EndTime             string `json:"end_time"`
	SlotDurationMinutes int    `json:"slot_duration_minutes"`
	// IsActive opsional. Bila tidak dikirim (nil) dianggap aktif, agar
	// klien lama yang tidak mengenal field ini tidak menonaktifkan jadwal.
	IsActive *bool `json:"is_active"`
}

type updateSchedulesRequest struct {
	Schedules []scheduleInput `json:"schedules"`
}

// listMySchedules jadwal mingguan milik profesional yang login.
func (s *Server) listMySchedules(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "professional" {
		writeError(w, http.StatusForbidden, errors.New("only professionals can view own schedules"))
		return
	}
	schedules, err := s.store.ListSchedulesForProfessional(r.Context(), claims.Subject)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if schedules == nil {
		schedules = []store.ProfessionalSchedule{}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"schedules": schedules})
}

// updateMySchedules profesional menentukan hari apa saja available.
func (s *Server) updateMySchedules(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "professional" {
		writeError(w, http.StatusForbidden, errors.New("only professionals can update own schedules"))
		return
	}
	var req updateSchedulesRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	var schedules []store.ProfessionalSchedule
	for _, sch := range req.Schedules {
		if sch.DayOfWeek < 0 || sch.DayOfWeek > 6 {
			writeError(w, http.StatusBadRequest, errors.New("day_of_week harus 0 (Min) sampai 6 (Sab)"))
			return
		}
		start := strings.TrimSpace(sch.StartTime)
		end := strings.TrimSpace(sch.EndTime)
		if len(start) > 5 {
			start = start[:5]
		}
		if len(end) > 5 {
			end = end[:5]
		}
		if _, err := time.Parse("15:04", start); err != nil {
			writeError(w, http.StatusBadRequest, errors.New("start_time harus HH:MM"))
			return
		}
		if _, err := time.Parse("15:04", end); err != nil {
			writeError(w, http.StatusBadRequest, errors.New("end_time harus HH:MM"))
			return
		}
		if start >= end {
			writeError(w, http.StatusBadRequest, errors.New("start_time harus sebelum end_time"))
			return
		}
		duration := sch.SlotDurationMinutes
		if duration <= 0 {
			duration = 30
		}
		if duration < 10 || duration > 180 {
			writeError(w, http.StatusBadRequest, errors.New("slot_duration_minutes harus 10-180"))
			return
		}
		// Default aktif bila klien tidak mengirim is_active.
		isActive := true
		if sch.IsActive != nil {
			isActive = *sch.IsActive
		}
		schedules = append(schedules, store.ProfessionalSchedule{
			DayOfWeek:           sch.DayOfWeek,
			StartTime:           start,
			EndTime:             end,
			SlotDurationMinutes: duration,
			IsActive:            isActive,
		})
	}
	if err := s.store.UpsertSchedules(r.Context(), claims.Subject, schedules); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	updated, err := s.store.ListSchedulesForProfessional(r.Context(), claims.Subject)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"schedules": updated})
}

type doctorReviewRequest struct {
	Stars      int    `json:"stars"`
	ReviewText string `json:"review_text"`
	Helpful    *bool  `json:"helpful"`
}

func (s *Server) listDoctorReviews(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	_ = claims
	userID := r.PathValue("user_id")
	reviews, err := s.store.ListDoctorReviews(r.Context(), userID, 20)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	rating, _ := s.store.DoctorRating(r.Context(), userID)
	if reviews == nil {
		reviews = []store.DoctorReview{}
	}
	writeJSON(w, http.StatusOK, map[string]any{"reviews": reviews, "rating": rating})
}

func (s *Server) createDoctorReview(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if claims.Role != "patient" {
		writeError(w, http.StatusForbidden, errors.New("only patients can review"))
		return
	}
	userID := r.PathValue("user_id")
	var req doctorReviewRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	// Ulasan hanya setelah pernah ada sesi completed dengan profesional tsb.
	sessions, err := s.store.ListCareSessions(r.Context(), claims.Subject, "patient", "past", "", 50)
	eligible := false
	if err == nil {
		for _, cs := range sessions {
			if cs.ProfessionalID == userID && cs.Status == "completed" {
				eligible = true
				break
			}
		}
	}
	if !eligible {
		writeError(w, http.StatusForbidden, errors.New("ulasan hanya bisa diberikan setelah sesi selesai"))
		return
	}
	helpful := true
	if req.Helpful != nil {
		helpful = *req.Helpful
	}
	rv, err := s.store.CreateDoctorReview(r.Context(), userID, claims.Subject, req.Stars, req.ReviewText, helpful)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"review": rv})
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
