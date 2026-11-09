package server

import (
	"encoding/json"
	"errors"
	"malva/backend/internal/auth"
	"malva/backend/internal/clock"
	"malva/backend/internal/store"
	"net/http"
	"strconv"
	"strings"
	"time"
)

func (item *eRxItemRequest) UnmarshalJSON(raw []byte) error {
	type plain eRxItemRequest
	var value plain
	if err := json.Unmarshal(raw, &value); err != nil {
		return err
	}
	var fields map[string]json.RawMessage
	if err := json.Unmarshal(raw, &fields); err != nil {
		return err
	}
	*item = eRxItemRequest(value)
	_, item.StockProvided = fields["current_stock"]
	return nil
}
func validatePrescriptionRequest(req createEPrescriptionRequest) error {
	if req.Status != "" && req.Status != "issued" && req.Status != "draft" {
		return errors.New("status resep harus issued atau draft")
	}
	if len(req.Diagnosis) > 2000 || len(req.Notes) > 10000 || len(req.Instructions) > 10000 || len(req.Items) > 50 {
		return errors.New("isi resep terlalu panjang")
	}
	if len(req.Items) == 0 && req.Status != "draft" {
		return errors.New("setidaknya satu obat wajib diisi")
	}
	seen := map[string]bool{}
	for _, item := range req.Items {
		if item.ID != "" {
			if !store.ValidClinicalClientID(item.ID) || seen[item.ID] {
				return errors.New("id item resep tidak valid atau berulang")
			}
			seen[item.ID] = true
		}
		if strings.TrimSpace(item.Name) == "" || len(item.Name) > 255 || len(item.Dosage) > 100 || len(item.Frequency) > 50 || item.CurrentStock < 0 || item.CurrentStock > 1000000000 || item.AlertBelow < 0 || item.AlertBelow > 1000000000 || item.Days < 0 || item.UnitsPerDay < 0 {
			return errors.New("nama, dosis, jadwal, dan stok obat tidak valid")
		}
		if len(item.Schedule) > 0 && string(item.Schedule) != "{}" {
			parts := strings.Fields(item.Dosage)
			dose := 0.0
			if len(parts) > 0 {
				dose, _ = strconv.ParseFloat(strings.ReplaceAll(parts[0], ",", "."), 64)
			}
			if !(dose > 0) || dose > 1e9 || (item.CurrentStock <= 0 && item.ID == "" && req.Status != "draft") || !oneOf(item.Form, "Tablet", "Kapsul", "Sirup", "Injeksi") || !oneOf(item.Unit, "mg", "mcg", "g", "ml", "IU") {
				return errors.New("dosis, stok, bentuk dan satuan obat wajib valid")
			}
		}
		if err := store.ValidateMedicationSchedule(item.Schedule); err != nil {
			return err
		}
	}
	return nil
}
func (s *Server) prescribingAuthor(w http.ResponseWriter, r *http.Request, claims auth.Claims) bool {
	if !s.requireVerifiedProfessional(w, r, claims) {
		return false
	}
	cred, err := s.store.GetProfessionalCredential(r.Context(), claims.Subject)
	if err != nil || !isPsychiatristSpecialization(cred.Specialization) {
		writeError(w, http.StatusForbidden, errors.New("resep hanya dapat diubah oleh Psikiater terverifikasi"))
		return false
	}
	return true
}
func (s *Server) updateEPrescription(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if !s.prescribingAuthor(w, r, claims) {
		return
	}
	old, err := s.store.GetEPrescription(r.Context(), r.PathValue("id"))
	if err != nil || old.ProfessionalID != claims.Subject {
		writeError(w, http.StatusNotFound, errors.New("resep tidak ditemukan"))
		return
	}
	var req createEPrescriptionRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if req.PatientID == "" {
		req.PatientID = old.PatientID
	}
	if req.PatientID != old.PatientID {
		writeError(w, http.StatusConflict, errors.New("pasien resep tidak dapat diubah"))
		return
	}
	if req.Status == "" {
		req.Status = old.Status
	}
	if err := validatePrescriptionRequest(req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	cred, _ := s.store.GetProfessionalCredential(r.Context(), claims.Subject)
	sig := map[string]any{"str_number": cred.STRNumber, "sip_number": cred.SIPNumber, "sipp_number": cred.SIPPNumber, "timestamp": clock.Now().Format(time.RFC3339)}
	_, err = s.store.UpdateEPrescription(r.Context(), store.EPrescription{ID: old.ID, ProfessionalID: claims.Subject, PatientID: old.PatientID, Status: req.Status, Diagnosis: req.Diagnosis, Notes: req.Notes, Instructions: req.Instructions, SignatureData: sig, QRToken: generateChatMessageID()}, rxItemsFromRequest(req.Items))
	if err != nil {
		code := http.StatusInternalServerError
		if errors.Is(err, store.ErrPrescriptionNotFound) {
			code = http.StatusNotFound
		}
		if errors.Is(err, store.ErrPrescriptionConflict) {
			code = http.StatusConflict
		}
		writeError(w, code, err)
		return
	}
	full, err := s.store.GetEPrescription(r.Context(), old.ID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	s.publishClinicalChange(old.PatientID, "medications")
	writeJSON(w, http.StatusOK, map[string]any{"prescription": full})
}
func (s *Server) deleteEPrescription(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if !s.prescribingAuthor(w, r, claims) {
		return
	}
	old, err := s.store.GetEPrescription(r.Context(), r.PathValue("id"))
	if err != nil || old.ProfessionalID != claims.Subject {
		writeError(w, http.StatusNotFound, errors.New("resep tidak ditemukan"))
		return
	}
	if err := s.store.DeleteEPrescription(r.Context(), old.ID, claims.Subject, generateChatMessageID()); err != nil {
		code := http.StatusInternalServerError
		if errors.Is(err, store.ErrPrescriptionNotFound) {
			code = http.StatusNotFound
		}
		writeError(w, code, err)
		return
	}
	s.publishClinicalChange(old.PatientID, "medications")
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}
