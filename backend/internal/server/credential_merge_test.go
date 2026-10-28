package server

import (
	"testing"

	"malva/backend/internal/store"
)

// ============================================================
// Regresi BUG C1 (unit test MURNI, tanpa database).
//
// Bukti produksi 28–29 Okt 2026: dr. Hafid Algistian, Sp.KJ adalah
// satu-satunya profesional dengan foto hasil unggahan DAN satu-satunya yang
// hospital_lat/lng = NULL. Artinya: unggah foto -> _save() -> form editor
// tidak mengirim koordinat -> handler menulis NULL -> profesional hilang dari
// direktori. mergeCredentialPreserving menjaga rantai itu tidak terulang.
// ============================================================

func f64(v float64) *float64 { return &v }

// existingCredential adalah kondisi "sudah punya data lengkap" di database.
func existingCredential() store.ProfessionalCredential {
	return store.ProfessionalCredential{
		UserID:          "user-1",
		STRNumber:       "STR-LAMA",
		SIPNumber:       "SIP-LAMA",
		SIPPNumber:      "SIPP-LAMA",
		Specialization:  "Sp.KJ",
		HospitalLat:     f64(-6.2),
		HospitalLng:     f64(106.8),
		HospitalName:    "RS Malva",
		AddressDetails:  "Jl. Lama 1",
		IsBPJSSupported: true,
		PhotoIntroURL:   "https://api.malva.web.id/uploads/user-1/foto-lama.jpg",
		VideoIntroURL:   "https://api.malva.web.id/uploads/user-1/video-lama.mp4",
		Bio:             "Bio lama",
		DocumentURL:     "/uploads/user-1/dokumen-lama.pdf",
		YearsExperience: 9,
		PriceFrom:       150000,
	}
}

// TestMergeCredentialPreservingKeepsCoordinates: request TANPA hospital_lat/lng
// (persis seperti form editor) tidak boleh menghapus koordinat lama.
func TestMergeCredentialPreservingKeepsCoordinates(t *testing.T) {
	existing := existingCredential()
	merged := mergeCredentialPreserving(existing, uploadCredentialsRequest{
		STRNumber:      "STR-LAMA",
		SIPNumber:      "SIP-LAMA",
		SIPPNumber:     "SIPP-LAMA",
		Specialization: "Sp.KJ",
		Bio:            "Bio baru",
	})

	if merged.HospitalLat == nil || merged.HospitalLng == nil {
		t.Fatalf("koordinat lama terhapus: lat=%v lng=%v", merged.HospitalLat, merged.HospitalLng)
	}
	if *merged.HospitalLat != -6.2 || *merged.HospitalLng != 106.8 {
		t.Fatalf("koordinat berubah: lat=%v lng=%v", *merged.HospitalLat, *merged.HospitalLng)
	}
	// Perubahan dari klien tetap dipakai.
	if merged.Bio != "Bio baru" {
		t.Errorf("bio dari klien harus tersimpan, dapat %q", merged.Bio)
	}
	// Field yang diisi admin tidak boleh ter-nol-kan.
	if merged.YearsExperience != 9 || merged.PriceFrom != 150000 {
		t.Errorf("years_experience/price_from harus dipertahankan, dapat %d/%d",
			merged.YearsExperience, merged.PriceFrom)
	}
}

// TestMergeCredentialPreservingHonoursNewCoordinates: bila klien BENAR-BENAR
// mengirim koordinat (mis. admin memindahkan faskes), nilai baru yang dipakai.
func TestMergeCredentialPreservingHonoursNewCoordinates(t *testing.T) {
	existing := existingCredential()
	merged := mergeCredentialPreserving(existing, uploadCredentialsRequest{
		Specialization: "Sp.KJ",
		HospitalLat:    f64(-7.25),
		HospitalLng:    f64(112.75),
	})

	if merged.HospitalLat == nil || merged.HospitalLng == nil {
		t.Fatalf("koordinat baru hilang: lat=%v lng=%v", merged.HospitalLat, merged.HospitalLng)
	}
	if *merged.HospitalLat != -7.25 || *merged.HospitalLng != 112.75 {
		t.Fatalf("koordinat baru harus dipakai, dapat lat=%v lng=%v",
			*merged.HospitalLat, *merged.HospitalLng)
	}
}

// TestMergeCredentialPreservingKeepsDocumentAndMedia: request yang
// mengosongkan document_url / photo / video tidak boleh menghapus data lama.
func TestMergeCredentialPreservingKeepsDocumentAndMedia(t *testing.T) {
	existing := existingCredential()
	merged := mergeCredentialPreserving(existing, uploadCredentialsRequest{
		Specialization: "Sp.KJ",
		DocumentURL:    "",
		PhotoIntroURL:  "",
		VideoIntroURL:  "",
	})

	if merged.DocumentURL != existing.DocumentURL {
		t.Errorf("document_url harus dipertahankan, dapat %q", merged.DocumentURL)
	}
	if merged.PhotoIntroURL != existing.PhotoIntroURL {
		t.Errorf("photo_intro_url lama tidak boleh hilang (jadi avatar DiceBear), dapat %q",
			merged.PhotoIntroURL)
	}
	if merged.VideoIntroURL != existing.VideoIntroURL {
		t.Errorf("video_intro_url lama tidak boleh hilang, dapat %q", merged.VideoIntroURL)
	}
}

// TestMergeCredentialPreservingAcceptsNewMedia: foto baru hasil unggahan harus
// menang atas foto lama (jalur "ganti foto profil").
func TestMergeCredentialPreservingAcceptsNewMedia(t *testing.T) {
	existing := existingCredential()
	const newPhoto = "https://api.malva.web.id/uploads/user-1/foto-baru.jpg"
	merged := mergeCredentialPreserving(existing, uploadCredentialsRequest{
		Specialization: "Sp.KJ",
		PhotoIntroURL:  newPhoto,
	})

	if merged.PhotoIntroURL != newPhoto {
		t.Fatalf("foto baru harus dipakai, dapat %q", merged.PhotoIntroURL)
	}
	// Video tidak dikirim -> tetap video lama.
	if merged.VideoIntroURL != existing.VideoIntroURL {
		t.Errorf("video lama harus dipertahankan, dapat %q", merged.VideoIntroURL)
	}
}

// TestMergeCredentialPreservingFirstTimeSave: profesional yang BELUM punya
// kredensial (zero value) tidak boleh panic dan tidak mengarang data.
func TestMergeCredentialPreservingFirstTimeSave(t *testing.T) {
	merged := mergeCredentialPreserving(store.ProfessionalCredential{}, uploadCredentialsRequest{
		STRNumber:      "STR-BARU",
		SIPNumber:      "SIP-BARU",
		Specialization: "M.Psi",
		HospitalName:   "Klinik Baru",
	})

	if merged.HospitalLat != nil || merged.HospitalLng != nil {
		t.Errorf("tanpa data lama, koordinat harus tetap nil, dapat lat=%v lng=%v",
			merged.HospitalLat, merged.HospitalLng)
	}
	if merged.DocumentURL != "" || merged.PhotoIntroURL != "" {
		t.Errorf("tanpa data lama, dokumen/foto harus kosong, dapat %q/%q",
			merged.DocumentURL, merged.PhotoIntroURL)
	}
	if merged.STRNumber != "STR-BARU" || merged.Specialization != "M.Psi" {
		t.Errorf("data dari klien harus tersimpan: str=%q spec=%q",
			merged.STRNumber, merged.Specialization)
	}
}

// TestMergeCredentialPreservingDoesNotSetUserID: UserID harus datang dari klaim
// autentikasi, bukan dari body request (anti pemalsuan).
func TestMergeCredentialPreservingDoesNotSetUserID(t *testing.T) {
	merged := mergeCredentialPreserving(existingCredential(), uploadCredentialsRequest{
		Specialization: "Sp.KJ",
	})
	if merged.UserID != "" {
		t.Fatalf("UserID tidak boleh diisi fungsi merge, dapat %q", merged.UserID)
	}
}
