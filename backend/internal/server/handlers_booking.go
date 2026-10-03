package server

import (
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"malva/backend/internal/auth"
	"malva/backend/internal/store"
)

// ============================================================
// BOOKING, PAYMENT, EARNINGS, E-PRESCRIPTION
// ============================================================

type createBookingRequest struct {
	PatientID       string `json:"patient_id"`
	ProfessionalID  string `json:"professional_id"`
	PackageID       *string `json:"package_id,omitempty"`
	ServiceType     string `json:"service_type"`
	SessionType     string `json:"session_type"`
	BookingDate     string `json:"booking_date"`
	SlotTime        string `json:"slot_time"`
	DurationMinutes int    `json:"duration_minutes"`
	Price           int64  `json:"price"`
}

type createPaymentRequest struct {
	BookingID     string `json:"booking_id"`
	PaymentMethod string `json:"payment_method"`
}

type markPaidRequest struct {
	Reference  string `json:"reference"`
	ExternalID string `json:"external_id"`
}

func (s *Server) createBooking(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	// Profesional terverifikasi bisa buat booking untuk pasiennya, atau pasien buat sendiri
	var req createBookingRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	isProfessional := claims.Role == "professional"
	patientID := req.PatientID
	var professionalID string

	if !isProfessional {
		patientID = claims.Subject
		if req.ProfessionalID == "" {
			writeJSON(w, http.StatusBadRequest, map[string]string{"error": "professional_id is required"})
			return
		}
		professionalID = req.ProfessionalID
	} else {
		if patientID == "" {
			patientID = claims.Subject
		}
		isVerified := s.requireVerifiedProfessional(w, r, claims)
		if !isVerified {
			return
		}
		professionalID = claims.Subject
	}

	cred, err := s.store.GetProfessionalCredential(r.Context(), professionalID)
	if err != nil || cred.VerificationStatus != "VERIFIED" {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "Professional not found or not verified"})
		return
	}

	duration := req.DurationMinutes
	if duration <= 0 { duration = 30 }
	if duration > 120 { duration = 120 }

	b, err := s.store.CreateBooking(r.Context(), store.Booking{
		PatientID:       patientID,
		ProfessionalID:  professionalID,
		PackageID:       req.PackageID,
		ServiceType:     req.ServiceType,
		SessionType:     req.SessionType,
		BookingDate:     req.BookingDate,
		SlotTime:        req.SlotTime,
		DurationMinutes: duration,
		Price:           req.Price,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	writeJSON(w, http.StatusCreated, map[string]interface{}{"booking": b})
}

func (s *Server) createPayment(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	var req createPaymentRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
// Generate reference: TXN-YYYYMMDDHHMMSS-RANDOM6
	reference := fmt.Sprintf("TXN-%s-%06d",
		time.Now().Format("20060102150405"),
		(int64)(time.Now().UnixNano()%1000000),
	)

	// Dummy harga dari booking
	bookings, _ := s.store.ListBookingsForUser(r.Context(), claims.Subject, claims.Role, 5)
	var bookingPrice int64 = 150000
	for _, b := range bookings {
		if b.ID == req.BookingID {
			bookingPrice = b.Price
			break
		}
	}
	platformFee := int64(float64(bookingPrice) * 0.10 / 100.0)
	serviceFee := int64(2000)
	gross := bookingPrice
	net := gross - platformFee + serviceFee

	p, err := s.store.CreatePayment(r.Context(), store.Payment{
		BookingID:         req.BookingID,
		PaymentMethod:     req.PaymentMethod,
		GrossAmount:       gross,
		ServiceFeeAmount:  serviceFee,
		PlatformFeeAmount: platformFee,
		NetAmount:         net,
		Reference:         reference,
	})
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}

	writeJSON(w, http.StatusCreated, map[string]interface{}{
		"payment": p,
		"breakdown": map[string]interface{}{
			"consultation": bookingPrice,
			"service_fee":  serviceFee,
			"total":        gross + serviceFee,
			"platform_fee": platformFee,
			"net_to_doctor": net,
		},
	})
}

func (s *Server) markPaymentPaid(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	// Profesional verifikasi pembayaran booking miliknya, atau webhook internal
	var req markPaidRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}

	p, err := s.store.MarkPaymentPaid(r.Context(), req.Reference, req.ExternalID)
	if err != nil {
		writeError(w, http.StatusNotFound, err)
		return
	}

	// Create earning untuk profesional
	// (Dalam production, ini dipakar lewat webhook gateway — di sini hanya simulasi)
	writeJSON(w, http.StatusOK, map[string]interface{}{"payment": p, "status": "paid"})
}

func (s *Server) listBookings(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	limit := parseQueryInt(r, "limit", 20, 100)
	bookings, err := s.store.ListBookingsForUser(r.Context(), claims.Subject, claims.Role, limit)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"bookings": bookings})
}

func (s *Server) earningsSummary(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if !s.requireVerifiedProfessional(w, r, claims) {
		return
	}
	summary, err := s.store.EarningsSummary(r.Context(), claims.Subject)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	transactions, _ := s.store.ListEarningsTransactions(r.Context(), claims.Subject, 20)
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"summary": summary,
		"transactions": transactions,
	})
}

func (s *Server) requestPayout(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if !s.requireVerifiedProfessional(w, r, claims) {
		return
	}
	earningID := r.PathValue("earning_id")
	if err := s.store.RequestPayout(r.Context(), earningID, "bca", "2643985203"); err != nil {
		writeError(w, http.StatusNotFound, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"status": "payout_requested"})
}

// ============================================================
// BOOKING, PAYMENT, EARNINGS, E-PRESCRIPTION
// ============================================================

type createEPrescriptionRequest struct {
	PatientID    string `json:"patient_id"`
	Instructions string `json:"instructions"`
	Notes       string `json:"notes"`
	Items        []eRxItemRequest `json:"items"`
}

type eRxItemRequest struct {
	Name        string  `json:"name"`
	Dosage      string  `json:"dosage"`
	Frequency   string  `json:"frequency"`
	Days        int     `json:"days"`
	UnitsPerDay int     `json:"units_per_day"`
	MedicationID *string `json:"medication_id,omitempty"`
}

func (s *Server) createEPrescription(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	if !s.requireVerifiedProfessional(w, r, claims) {
		return
	}
	cred, err := s.store.GetProfessionalCredential(r.Context(), claims.Subject)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if cred.Specialization != "Sp.KJ" {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "E-Prescription hanya untuk Psikiater (Sp.KJ). Psikolog M.Psi tidak dapat membuat resep."})
		return
	}

	var req createEPrescriptionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	if len(req.Items) == 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "at least one medication item is required"})
		return
	}

	sig := map[string]interface{}{
		"str_number": cred.STRNumber,
		"sip_number": cred.SIPNumber,
		"sipp_number": cred.SIPPNumber,
		"timestamp": time.Now().UTC().Format(time.RFC3339),
	}

	qrToken := fmt.Sprintf("RX-%s-%d", claims.Subject[:8], time.Now().UnixNano()/1e6)
	rx, err := s.store.CreateEPrescription(r.Context(), store.EPrescription{
		ProfessionalID: claims.Subject,
		PatientID:      req.PatientID,
		Notes:          req.Notes,
		Instructions:   req.Instructions,
		SignatureData:  sig,
		QRToken:        qrToken,
	}, rxItemsFromRequest(req.Items))
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]interface{}{"prescription": rx})
}

func rxItemsFromRequest(items []eRxItemRequest) []store.EPrescriptionItem {
	out := make([]store.EPrescriptionItem, len(items))
	for i, item := range items {
		out[i] = store.EPrescriptionItem{
			MedicationID: item.MedicationID,
			Name:         item.Name,
			Frequency:    item.Frequency,
			Days:         item.Days,
			UnitsPerDay:  item.UnitsPerDay,
		}
		if item.UnitsPerDay <= 0 { out[i].UnitsPerDay = 1 }
		if item.Days <= 0 { out[i].Days = 30 }
	}
	return out
}

func (s *Server) getEPrescription(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	rxID := r.PathValue("id")
	rx, err := s.store.GetEPrescription(r.Context(), rxID)
	if err != nil {
		writeError(w, http.StatusNotFound, err)
		return
	}
	isDoctor := claims.Role == "professional" && claims.Subject == rx.ProfessionalID
	isPatient := claims.Role == "patient" && claims.Subject == rx.PatientID
	if !isDoctor && !isPatient {
		if s.consentAllows(r, rx.PatientID, claims.Subject, "health_record") {
			// allowed
		} else {
			writeJSON(w, http.StatusForbidden, map[string]string{"error": "No consent to view this prescription"})
			return
		}
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"prescription": rx})
}

func (s *Server) listEPrescriptions(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	rx, err := s.store.ListEPrescriptionsForUser(r.Context(), claims.Subject, claims.Role)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{"prescriptions": rx})
}

func (s *Server) verifyEPrescriptionQR(w http.ResponseWriter, r *http.Request) {
	token := r.URL.Query().Get("token")
	if token == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "token is required"})
		return
	}
	rx, err := s.store.GetEPrescriptionByQR(r.Context(), token)
	if err != nil {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "Invalid prescription QR"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]interface{}{
		"valid":          true,
		"prescription":   rx,
		"verified_by":    "Malva QR Verification",
	})
}
