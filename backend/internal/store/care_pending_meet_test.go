package store

import (
	"context"
	"strings"
	"testing"
	"time"

	"malva/backend/internal/clock"
)

// ============================================================
// PENGECUALIAN INVARIAN "SESI VIDEO WAJIB PUNYA LINK"
//
// Aturan bisnis (keputusan pemilik produk): kondisi akun Google milik
// PROFESIONAL tidak boleh memblokir PASIEN. Sesi video boleh lahir tanpa link
// bila pemanggil secara eksplisit meminta (AllowPendingMeet), lalu link dibuat
// menyusul. Semua jalur lain tetap tunduk pada invarian keras.
//
// Kedua test di bawah berjalan TANPA Postgres: pemeriksaan invarian berada
// sebelum transaksi database, sehingga bisa dibuktikan lewat error validasi
// berikutnya (durasi / jadwal masa lalu).
// ============================================================

// TestCreateCareSessionVideoWithoutLinkRejectedByDefault memastikan invarian
// lama tidak hilang: tanpa pengecualian eksplisit, sesi video tanpa link tetap
// ditolak.
func TestCreateCareSessionVideoWithoutLinkRejectedByDefault(t *testing.T) {
	st := New(nil)
	_, err := st.CreateCareSession(context.Background(), CareSession{
		PatientID:       "00000000-0000-0000-0000-000000000001",
		ProfessionalID:  "00000000-0000-0000-0000-000000000002",
		SessionType:     "video",
		ScheduledAt:     clock.Now().Add(2 * time.Hour),
		DurationMinutes: 60,
	})
	if err == nil {
		t.Fatal("sesi video tanpa link harus ditolak tanpa AllowPendingMeet")
	}
	if !strings.Contains(err.Error(), "wajib memiliki link") {
		t.Fatalf("pesan error = %q, mau memuat \"wajib memiliki link\"", err.Error())
	}
}

// TestCreateCareSessionAllowPendingMeetSkipsLinkInvariant membuktikan
// pengecualian bekerja: dengan AllowPendingMeet=true, pemeriksaan link
// dilewati sehingga validasi berikutnya (durasi tidak valid) yang gagal.
//
// Bila pengecualian TIDAK bekerja, error yang muncul akan tetap soal link.
func TestCreateCareSessionAllowPendingMeetSkipsLinkInvariant(t *testing.T) {
	st := New(nil)
	_, err := st.CreateCareSession(context.Background(), CareSession{
		PatientID:        "00000000-0000-0000-0000-000000000001",
		ProfessionalID:   "00000000-0000-0000-0000-000000000002",
		SessionType:      "video",
		ScheduledAt:      clock.Now().Add(2 * time.Hour),
		DurationMinutes:  5, // di bawah batas 10 menit
		AllowPendingMeet: true,
	})
	if err == nil {
		t.Fatal("durasi 5 menit harus ditolak")
	}
	if strings.Contains(err.Error(), "wajib memiliki link") {
		t.Fatalf("invarian link seharusnya dilewati saat AllowPendingMeet=true, dapat: %q", err.Error())
	}
	if !strings.Contains(err.Error(), "duration_minutes") {
		t.Fatalf("error = %q, mau soal duration_minutes", err.Error())
	}
}

// TestCreateCareSessionAllowPendingMeetReachesFutureCheck memastikan jalur
// AllowPendingMeet lolos pemeriksaan link lalu berhenti di validasi jadwal
// (bukti kedua bahwa invarian link benar-benar dilewati).
func TestCreateCareSessionAllowPendingMeetReachesFutureCheck(t *testing.T) {
	st := New(nil)
	_, err := st.CreateCareSession(context.Background(), CareSession{
		PatientID:        "00000000-0000-0000-0000-000000000001",
		ProfessionalID:   "00000000-0000-0000-0000-000000000002",
		SessionType:      "video",
		ScheduledAt:      clock.Now().Add(-2 * time.Hour),
		DurationMinutes:  60,
		AllowPendingMeet: true,
	})
	if err == nil {
		t.Fatal("jadwal di masa lalu harus ditolak")
	}
	if strings.Contains(err.Error(), "wajib memiliki link") {
		t.Fatalf("invarian link seharusnya dilewati, dapat: %q", err.Error())
	}
	if !strings.Contains(err.Error(), "masa depan") {
		t.Fatalf("error = %q, mau soal jadwal masa depan", err.Error())
	}
}
