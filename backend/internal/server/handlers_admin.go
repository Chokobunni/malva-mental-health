package server

import (
	"database/sql"
	"errors"
	"net/http"
	"strings"

	"malva/backend/internal/auth"
	"malva/backend/internal/security"
	"malva/backend/internal/store"
)

// requireAdmin hanya mengizinkan token dengan role admin.
func (s *Server) requireAdmin(next authedHandler) http.HandlerFunc {
	return s.requireAuth(func(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
		if claims.Role != "admin" {
			writeError(w, http.StatusForbidden, errors.New("Akses khusus admin."))
			return
		}
		next(w, r, claims)
	})
}

func (s *Server) listAdminUsers(w http.ResponseWriter, r *http.Request, _ auth.Claims) {
	users, err := s.store.ListUsers(r.Context(), 200)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"users": users})
}

type adminUpdateUserRequest struct {
	DisplayName *string `json:"display_name"`
	Role        *string `json:"role"`
	Phone       *string `json:"phone"`
	DateOfBirth *string `json:"date_of_birth"`
	Gender      *string `json:"gender"`
	Disabled    *bool   `json:"disabled"`
}

func (s *Server) updateAdminUser(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	userID := r.PathValue("user_id")
	if strings.TrimSpace(userID) == "" {
		writeError(w, http.StatusBadRequest, errors.New("user_id wajib diisi."))
		return
	}
	if userID == claims.Subject {
		writeError(w, http.StatusBadRequest, errors.New("Tidak bisa mengubah akun admin sendiri dari sini."))
		return
	}
	var req adminUpdateUserRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	displayName, role, phone, dateOfBirth, gender := "", "", "", "", ""
	if req.DisplayName != nil {
		displayName = *req.DisplayName
	}
	if req.Role != nil {
		role = *req.Role
	}
	if req.Phone != nil {
		phone = *req.Phone
	}
	if req.DateOfBirth != nil {
		dateOfBirth = *req.DateOfBirth
	}
	if req.Gender != nil {
		gender = *req.Gender
	}
	updated, err := s.store.UpdateUserAdmin(r.Context(), userID, displayName, role, phone, dateOfBirth, gender, req.Disabled)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, errors.New("Pengguna tidak ditemukan."))
			return
		}
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"user": updated})
}

func (s *Server) deleteAdminUser(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	userID := r.PathValue("user_id")
	if strings.TrimSpace(userID) == "" {
		writeError(w, http.StatusBadRequest, errors.New("user_id wajib diisi."))
		return
	}
	if userID == claims.Subject {
		writeError(w, http.StatusBadRequest, errors.New("Tidak bisa menghapus akun admin sendiri."))
		return
	}
	if err := s.store.DeleteUser(r.Context(), userID); err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, errors.New("Pengguna tidak ditemukan."))
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "deleted"})
}

// listAdminDoctors mengembalikan SEMUA dokter (termasuk PENDING/REJECTED dan
// yang dinonaktifkan) untuk tab Dokter di panel admin.
func (s *Server) listAdminDoctors(w http.ResponseWriter, r *http.Request, _ auth.Claims) {
	params := store.DoctorSearchParams{
		Limit:             200,
		IncludeUnverified: true,
		Specialization:    strings.TrimSpace(r.URL.Query().Get("specialization")),
	}
	results, err := s.store.SearchDoctors(r.Context(), params)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"doctors": results})
}

// getAdminDoctor mengembalikan profil lengkap satu dokter untuk form edit:
// akun + kredensial + jadwal + paket (khusus admin).
func (s *Server) getAdminDoctor(w http.ResponseWriter, r *http.Request, _ auth.Claims) {
	userID := r.PathValue("user_id")
	if strings.TrimSpace(userID) == "" {
		writeError(w, http.StatusBadRequest, errors.New("user_id wajib diisi."))
		return
	}
	user, err := s.store.GetUserByID(r.Context(), userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, errors.New("Dokter tidak ditemukan."))
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if user.Role != "professional" {
		writeError(w, http.StatusBadRequest, errors.New("Akun ini bukan profesional."))
		return
	}
	cred, err := s.store.GetProfessionalCredential(r.Context(), userID)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	schedules, err := s.store.ListSchedulesForProfessional(r.Context(), userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	packages, err := s.store.ListServicePackages(r.Context(), userID)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"user":       user,
		"credential": cred,
		"schedules":  schedules,
		"packages":   packages,
	})
}

func (s *Server) listPendingCredentials(w http.ResponseWriter, r *http.Request, _ auth.Claims) {
	pending, err := s.store.ListPendingCredentials(r.Context())
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"pending": pending})
}

type adminVerifyRequest struct {
	Action          string `json:"action"`
	RejectionReason string `json:"rejection_reason"`
}

func (s *Server) verifyCredential(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	credentialID := r.PathValue("id")
	if strings.TrimSpace(credentialID) == "" {
		writeError(w, http.StatusBadRequest, errors.New("credential id wajib diisi."))
		return
	}
	var req adminVerifyRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	action := strings.ToLower(strings.TrimSpace(req.Action))
	if action != "approve" && action != "reject" {
		writeError(w, http.StatusBadRequest, errors.New("action harus approve atau reject."))
		return
	}
	if err := s.store.VerifyProfessionalCredential(r.Context(), credentialID, claims.Subject, action, strings.TrimSpace(req.RejectionReason)); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

type adminDoctorCredential struct {
	STRNumber       string        `json:"str_number"`
	SIPNumber       string        `json:"sip_number"`
	SIPPNumber      string        `json:"sipp_number"`
	Specialization  string        `json:"specialization"`
	SubSpecialties  []string      `json:"sub_specialties"`
	HospitalLat     *float64      `json:"hospital_lat"`
	HospitalLng     *float64      `json:"hospital_lng"`
	HospitalName    string        `json:"hospital_name"`
	AddressDetails  string        `json:"address_details"`
	IsBPJSSupported *bool         `json:"is_bpjs_supported"`
	PhotoIntroURL   string        `json:"photo_intro_url"`
	VideoIntroURL   string        `json:"video_intro_url"`
	Bio             string        `json:"bio"`
	Education       []interface{} `json:"education"`
	DocumentURL     string        `json:"document_url"`
	YearsExperience int           `json:"years_experience"`
	PriceFrom       int64         `json:"price_from"`
}

type adminDoctorRequest struct {
	Email          string                       `json:"email"`
	Password       string                       `json:"password"`
	DisplayName    string                       `json:"display_name"`
	ProfessionalID string                       `json:"professional_id"`
	Credentials    adminDoctorCredential        `json:"credentials"`
	Schedules      []store.ProfessionalSchedule `json:"schedules"`
	Packages       []store.ServicePackage       `json:"packages"`
}

// validSpecialization menerima spesialisasi psikiatri/psikologi yang lazim
// di Indonesia, plus sub-spesialisasi psikiatri (Sp.*) agar admin fleksibel.
func validSpecialization(spec string) bool {
	s := strings.ToUpper(strings.TrimSpace(spec))
	switch s {
	case "SP.KJ", "M.PSI", "SP.PSI", "SP.AN", "SP.K", "SP.KK" /* psikologi klinis */ :
		return true
	}
	// Sub-spesialisasi psikiatri lain (mis. "Sp.KJ(K)" atau "Sp.KP").
	if strings.HasPrefix(s, "SP.") && len(s) <= 12 {
		return true
	}
	// Psikolog dengan gelar lain (mis. "M.Psi," atau "Psikolog Klinis").
	psikolog := []string{"M.PSI", "M PSI", "PSIKOLOG", "M.A", "M.PSI."}
	for _, p := range psikolog {
		if s == p || strings.HasPrefix(s, p) {
			return true
		}
	}
	return false
}

// createAdminDoctor membuat akun profesional + profil kredensial yang
// langsung VERIFIED, beserta jadwal dan paket harga (khusus admin).
func (s *Server) createAdminDoctor(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	var req adminDoctorRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if !security.ValidateEmail(req.Email) {
		writeError(w, http.StatusBadRequest, errors.New("Format email tidak valid."))
		return
	}
	if err := security.ValidatePassword(req.Password, req.Email); err != nil {
		writeError(w, http.StatusBadRequest, errors.New(security.IndonesianMessage(err)))
		return
	}
	if strings.TrimSpace(req.DisplayName) == "" {
		writeError(w, http.StatusBadRequest, errors.New("Nama dokter wajib diisi."))
		return
	}
	if strings.TrimSpace(req.ProfessionalID) == "" {
		writeError(w, http.StatusBadRequest, errors.New("ID profesional (16 digit) wajib diisi."))
		return
	}
	if !validSpecialization(strings.TrimSpace(req.Credentials.Specialization)) {
		writeError(w, http.StatusBadRequest, errors.New("Spesialisasi harus Sp.KJ (psikiater) atau M.Psi (psikolog)."))
		return
	}
	if req.Credentials.HospitalLat != nil && req.Credentials.HospitalLng != nil {
		if !s.validateLatLng(*req.Credentials.HospitalLat, *req.Credentials.HospitalLng) {
			writeError(w, http.StatusBadRequest, errors.New("Koordinat rumah sakit tidak valid."))
			return
		}
	}
	for _, sch := range req.Schedules {
		if sch.DayOfWeek < 0 || sch.DayOfWeek > 6 {
			writeError(w, http.StatusBadRequest, errors.New("day_of_week harus 0 (Min) sampai 6 (Sab)."))
			return
		}
	}
	hash, err := auth.HashPassword(req.Password)
	if err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	user, err := s.store.CreateUser(r.Context(), store.CreateUserParams{
		Email:          req.Email,
		PasswordHash:   hash,
		Role:           "professional",
		DisplayName:    strings.TrimSpace(req.DisplayName),
		ProfessionalID: strings.TrimSpace(req.ProfessionalID),
	})
	if err != nil {
		if isDuplicateKeyError(err) {
			writeError(w, http.StatusConflict, errors.New("Email atau ID profesional sudah terdaftar."))
			return
		}
		writeError(w, http.StatusBadRequest, err)
		return
	}
	cred, err := s.store.UpsertProfessionalCredential(r.Context(), store.ProfessionalCredential{
		UserID:          user.ID,
		STRNumber:       strings.TrimSpace(req.Credentials.STRNumber),
		SIPNumber:       strings.TrimSpace(req.Credentials.SIPNumber),
		SIPPNumber:      strings.TrimSpace(req.Credentials.SIPPNumber),
		Specialization:  strings.TrimSpace(req.Credentials.Specialization),
		SubSpecialties:  req.Credentials.SubSpecialties,
		HospitalLat:     req.Credentials.HospitalLat,
		HospitalLng:     req.Credentials.HospitalLng,
		HospitalName:    strings.TrimSpace(req.Credentials.HospitalName),
		AddressDetails:  strings.TrimSpace(req.Credentials.AddressDetails),
		IsBPJSSupported: req.Credentials.IsBPJSSupported != nil && *req.Credentials.IsBPJSSupported,
		PhotoIntroURL:   strings.TrimSpace(req.Credentials.PhotoIntroURL),
		VideoIntroURL:   strings.TrimSpace(req.Credentials.VideoIntroURL),
		Bio:             strings.TrimSpace(req.Credentials.Bio),
		Education:       req.Credentials.Education,
		DocumentURL:     strings.TrimSpace(req.Credentials.DocumentURL),
		YearsExperience: req.Credentials.YearsExperience,
		PriceFrom:       req.Credentials.PriceFrom,
	})
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	// Dokter buatan admin langsung terverifikasi agar tampil di direktori.
	if err := s.store.VerifyProfessionalCredential(r.Context(), cred.ID, claims.Subject, "approve", ""); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if len(req.Schedules) > 0 {
		if err := s.store.UpsertSchedules(r.Context(), user.ID, req.Schedules); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
	}
	if len(req.Packages) > 0 {
		if err := s.store.UpsertServicePackages(r.Context(), user.ID, req.Packages); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
	}
	writeJSON(w, http.StatusCreated, map[string]any{"user": user, "credential_id": cred.ID})
}

// updateAdminDoctor mengubah kredensial + jadwal + paket dokter (khusus admin).
func (s *Server) updateAdminDoctor(w http.ResponseWriter, r *http.Request, claims auth.Claims) {
	userID := r.PathValue("user_id")
	if strings.TrimSpace(userID) == "" {
		writeError(w, http.StatusBadRequest, errors.New("user_id wajib diisi."))
		return
	}
	var req adminDoctorRequest
	if err := readJSON(r, &req); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if strings.TrimSpace(req.Credentials.Specialization) != "" && !validSpecialization(strings.TrimSpace(req.Credentials.Specialization)) {
		writeError(w, http.StatusBadRequest, errors.New("Spesialisasi harus Sp.KJ (psikiater) atau M.Psi (psikolog)."))
		return
	}
	// Nama dokter bisa diubah dari form edit (dulu terbuang diam-diam).
	if name := strings.TrimSpace(req.DisplayName); name != "" {
		if err := s.store.UpdateDisplayName(r.Context(), userID, name); err != nil {
			writeError(w, http.StatusInternalServerError, err)
			return
		}
	}
	existing, err := s.store.GetProfessionalCredential(r.Context(), userID)
	if err != nil {
		if errors.Is(err, sql.ErrNoRows) {
			writeError(w, http.StatusNotFound, errors.New("Data kredensial dokter tidak ditemukan."))
			return
		}
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	merged := existing
	if strings.TrimSpace(req.Credentials.Specialization) != "" {
		merged.Specialization = strings.TrimSpace(req.Credentials.Specialization)
	}
	if req.Credentials.SubSpecialties != nil {
		merged.SubSpecialties = req.Credentials.SubSpecialties
	}
	if strings.TrimSpace(req.Credentials.HospitalName) != "" {
		merged.HospitalName = strings.TrimSpace(req.Credentials.HospitalName)
	}
	if strings.TrimSpace(req.Credentials.AddressDetails) != "" {
		merged.AddressDetails = strings.TrimSpace(req.Credentials.AddressDetails)
	}
	if req.Credentials.HospitalLat != nil {
		merged.HospitalLat = req.Credentials.HospitalLat
	}
	if req.Credentials.HospitalLng != nil {
		merged.HospitalLng = req.Credentials.HospitalLng
	}
	// BPJS hanya berubah bila field dikirim (penting agar PUT parsial
	// dari form edit tidak menghapus status BPJS yang ada).
	if req.Credentials.IsBPJSSupported != nil {
		merged.IsBPJSSupported = *req.Credentials.IsBPJSSupported
	}
	if strings.TrimSpace(req.Credentials.Bio) != "" {
		merged.Bio = strings.TrimSpace(req.Credentials.Bio)
	}
	if req.Credentials.Education != nil {
		merged.Education = req.Credentials.Education
	}
	if strings.TrimSpace(req.Credentials.PhotoIntroURL) != "" {
		merged.PhotoIntroURL = strings.TrimSpace(req.Credentials.PhotoIntroURL)
	}
	if strings.TrimSpace(req.Credentials.VideoIntroURL) != "" {
		merged.VideoIntroURL = strings.TrimSpace(req.Credentials.VideoIntroURL)
	}
	if strings.TrimSpace(req.Credentials.STRNumber) != "" {
		merged.STRNumber = strings.TrimSpace(req.Credentials.STRNumber)
	}
	if strings.TrimSpace(req.Credentials.SIPNumber) != "" {
		merged.SIPNumber = strings.TrimSpace(req.Credentials.SIPNumber)
	}
	if strings.TrimSpace(req.Credentials.SIPPNumber) != "" {
		merged.SIPPNumber = strings.TrimSpace(req.Credentials.SIPPNumber)
	}
	if strings.TrimSpace(req.Credentials.DocumentURL) != "" {
		merged.DocumentURL = strings.TrimSpace(req.Credentials.DocumentURL)
	}
	if req.Credentials.YearsExperience > 0 {
		merged.YearsExperience = req.Credentials.YearsExperience
	}
	if req.Credentials.PriceFrom > 0 {
		merged.PriceFrom = req.Credentials.PriceFrom
	}
	// Upsert selalu mengembalikan ke PENDING -> verifikasi ulang otomatis.
	cred, err := s.store.UpsertProfessionalCredential(r.Context(), merged)
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}
	if err := s.store.VerifyProfessionalCredential(r.Context(), cred.ID, claims.Subject, "approve", ""); err != nil {
		writeError(w, http.StatusInternalServerError, err)
		return
	}
	if req.Schedules != nil {
		if err := s.store.UpsertSchedules(r.Context(), userID, req.Schedules); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
	}
	if req.Packages != nil {
		if err := s.store.UpsertServicePackages(r.Context(), userID, req.Packages); err != nil {
			writeError(w, http.StatusBadRequest, err)
			return
		}
	}
	writeJSON(w, http.StatusOK, map[string]any{"credential": cred})
}
