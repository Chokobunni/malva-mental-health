package store

import (
	"strconv"
	"strings"
	"testing"
)

// ============================================================
// Regresi BUG C2 (unit test MURNI, tanpa database).
//
// Bukti produksi 28–29 Okt 2026:
//   GET /v1/doctors/search?limit=100                          -> 4 profesional
//   GET /v1/doctors/search?limit=100&patient_lat=-6.2&...     -> 3 profesional
// Yang hilang: dr. Hafid Algistian, Sp.KJ — satu-satunya profesional dengan
// foto hasil unggahan dan satu-satunya yang hospital_lat/lng = NULL.
//
// Rantainya: unggah foto -> simpan profil menghapus koordinat (BUG C1) ->
// profesional tanpa koordinat tersaring dari direktori karena query SELALU
// memasang `pc.hospital_lat IS NOT NULL` ketika pasien mengirim koordinat.
// Test ini menjaga agar klausa itu HANYA muncul bila ada filter jarak
// eksplisit (MaxKM).
// ============================================================

const (
	coordClause   = "pc.hospital_lat IS NOT NULL"
	verifiedWhere = "pc.verification_status = 'VERIFIED'"
)

// hasClause melaporkan apakah ada klausa WHERE yang memuat potongan teks
// tertentu.
func hasClause(where []string, fragment string) bool {
	for _, clause := range where {
		if strings.Contains(clause, fragment) {
			return true
		}
	}
	return false
}

func floatPtr(v float64) *float64 { return &v }

// TestBuildDoctorSearchWhereKeepsDoctorsWithoutCoordinates: pasien mengirim
// koordinat TANPA filter jarak -> filter koordinat TIDAK boleh dipasang,
// sehingga profesional tanpa koordinat tetap tampil (distance_km NULL).
func TestBuildDoctorSearchWhereKeepsDoctorsWithoutCoordinates(t *testing.T) {
	filter := buildDoctorSearchWhere(DoctorSearchParams{
		PatientLat: floatPtr(-6.2),
		PatientLng: floatPtr(106.8),
		SortBy:     "distance",
		Limit:      100,
	})

	if hasClause(filter.Where, coordClause) {
		t.Fatalf("filter koordinat tidak boleh aktif tanpa MaxKM, where = %v", filter.Where)
	}
	// Kolom jarak tetap dihitung agar ORDER BY distance_km tetap valid.
	if strings.Contains(filter.DistanceCol, "NULL::numeric AS distance_km") {
		t.Fatalf("distance_km harus dihitung saat koordinat pasien ada, dapat %q", filter.DistanceCol)
	}
	if !strings.Contains(filter.DistanceCol, "AS distance_km") {
		t.Fatalf("kolom distance_km harus selalu ada agar Scan stabil, dapat %q", filter.DistanceCol)
	}
	// Argumen koordinat tetap dikirim (untuk kolom jarak), urut lat lalu lng.
	if len(filter.Args) != 2 {
		t.Fatalf("mau 2 argumen koordinat, dapat %d: %v", len(filter.Args), filter.Args)
	}
	if lat, ok := filter.Args[0].(float64); !ok || lat != -6.2 {
		t.Fatalf("argumen pertama harus patient_lat, dapat %v", filter.Args[0])
	}
	if lng, ok := filter.Args[1].(float64); !ok || lng != 106.8 {
		t.Fatalf("argumen kedua harus patient_lng, dapat %v", filter.Args[1])
	}
}

// TestBuildDoctorSearchWhereFiltersByDistanceWhenMaxKM: bila pasien memakai
// filter jarak eksplisit, perilaku HARUS sama seperti sebelumnya — hanya
// profesional dengan koordinat & dalam radius yang lolos.
func TestBuildDoctorSearchWhereFiltersByDistanceWhenMaxKM(t *testing.T) {
	filter := buildDoctorSearchWhere(DoctorSearchParams{
		PatientLat: floatPtr(-6.2),
		PatientLng: floatPtr(106.8),
		MaxKM:      floatPtr(5),
		SortBy:     "distance",
		Limit:      100,
	})

	if !hasClause(filter.Where, coordClause) {
		t.Fatalf("dengan MaxKM, filter koordinat wajib aktif, where = %v", filter.Where)
	}
	// Harus ada klausa haversine <= $n (filter radius).
	radiusFound := false
	for _, clause := range filter.Where {
		if strings.Contains(clause, "AS distance_km") || strings.Contains(clause, "distance_km") {
			t.Errorf("klausa WHERE tidak boleh memakai alias distance_km: %q", clause)
		}
		if strings.Contains(clause, "<= $") && strings.Contains(clause, "6371") {
			radiusFound = true
		}
	}
	if !radiusFound {
		t.Fatalf("klausa radius (haversine <= $n) tidak ditemukan, where = %v", filter.Where)
	}
	// Argumen: lat, lng, max_km.
	if len(filter.Args) != 3 {
		t.Fatalf("mau 3 argumen (lat, lng, max_km), dapat %d: %v", len(filter.Args), filter.Args)
	}
	if maxKM, ok := filter.Args[2].(float64); !ok || maxKM != 5 {
		t.Fatalf("argumen ketiga harus max_km, dapat %v", filter.Args[2])
	}
}

// TestBuildDoctorSearchWhereWithoutPatientCoordinates: tanpa koordinat pasien,
// tidak ada perhitungan jarak dan tidak ada filter koordinat — daftar penuh.
func TestBuildDoctorSearchWhereWithoutPatientCoordinates(t *testing.T) {
	filter := buildDoctorSearchWhere(DoctorSearchParams{SortBy: "name_asc", Limit: 100})

	if filter.DistanceCol != "NULL::numeric AS distance_km" {
		t.Fatalf("tanpa koordinat pasien, distance_km harus NULL, dapat %q", filter.DistanceCol)
	}
	if hasClause(filter.Where, coordClause) {
		t.Fatalf("tanpa koordinat pasien tidak boleh ada filter koordinat, where = %v", filter.Where)
	}
	if len(filter.Args) != 0 {
		t.Fatalf("tanpa filter apa pun, argumen harus kosong, dapat %v", filter.Args)
	}
}

// TestBuildDoctorSearchWhereVerificationGuard: direktori publik hanya boleh
// menampilkan profesional VERIFIED & tidak dinonaktifkan; panel admin
// (IncludeUnverified) melihat semuanya.
func TestBuildDoctorSearchWhereVerificationGuard(t *testing.T) {
	publicFilter := buildDoctorSearchWhere(DoctorSearchParams{Limit: 100})
	if !hasClause(publicFilter.Where, verifiedWhere) {
		t.Fatalf("direktori publik wajib memfilter verification_status = 'VERIFIED', where = %v", publicFilter.Where)
	}
	if !hasClause(publicFilter.Where, "u.disabled_at IS NULL") {
		t.Fatalf("direktori publik wajib mengecualikan akun nonaktif, where = %v", publicFilter.Where)
	}

	adminFilter := buildDoctorSearchWhere(DoctorSearchParams{Limit: 100, IncludeUnverified: true})
	if hasClause(adminFilter.Where, verifiedWhere) {
		t.Fatalf("panel admin harus melihat semua status, where = %v", adminFilter.Where)
	}
}

// TestBuildDoctorSearchWherePlaceholdersMatchArgs: jumlah placeholder $n harus
// sama dengan jumlah argumen, dan nomornya berurutan 1..n. Ini mencegah
// regresi "pq: got N parameters but the statement requires M" yang hanya
// muncul saat runtime.
func TestBuildDoctorSearchWherePlaceholdersMatchArgs(t *testing.T) {
	bpjs := true
	filter := buildDoctorSearchWhere(DoctorSearchParams{
		PatientLat:      floatPtr(-6.2),
		PatientLng:      floatPtr(106.8),
		MaxKM:           floatPtr(10),
		Specialization:  "Sp.KJ",
		MaxPrice:        int64Ptr(500000),
		IsBPJSSupported: &bpjs,
		Limit:           100,
	})
	joined := strings.Join(filter.Where, " AND ")
	for i := 1; i <= len(filter.Args); i++ {
		placeholder := "$" + strconv.Itoa(i)
		if !strings.Contains(joined, placeholder) {
			t.Fatalf("placeholder %s tidak ditemukan di WHERE: %s", placeholder, joined)
		}
	}
	// Tidak boleh ada placeholder melebihi jumlah argumen.
	overflow := "$" + strconv.Itoa(len(filter.Args)+1)
	if strings.Contains(joined, overflow) {
		t.Fatalf("placeholder %s melebihi jumlah argumen (%d): %s", overflow, len(filter.Args), joined)
	}
}

func int64Ptr(v int64) *int64 { return &v }
