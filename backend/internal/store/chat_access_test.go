package store

import (
	"strings"
	"testing"
	"time"
)

// Unit test MURNI (tanpa DB) untuk logika akses chat.
//
// Regresi yang dijaga:
//   * `inSessionWindow` menentukan jendela chat; batasnya harus tepat.
//   * `chatAccessReason` menghasilkan copy yang benar per role — profesional
//     tidak boleh melihat istilah sisi pasien ("Di luar sesi" / "kamu bisa
//     mengirim data").

// fixedNext adalah waktu sesi berikutnya yang dipakai agar string hasil
// deterministik. Dibangun di zona WIB agar format cocok.
func fixedNext() *time.Time {
	t := time.Date(2026, 7, 10, 14, 30, 0, 0, locationWIB)
	return &t
}

func TestChatAccessReason(t *testing.T) {
	next := fixedNext()
	const wantNextPatient = "Chat teks aktif saat sesi berjalan. Sesi berikutnya: 10 Jul 2026 14:30."
	const wantNextProfessional = "Chat teks aktif saat sesi berjalan. Sesi berikutnya dengan pasien ini: 10 Jul 2026 14:30."
	const wantNoNextPatient = "Belum ada sesi terjadwal dengan profesional ini."
	const wantNoNextProfessional = "Belum ada sesi terjadwal dengan pasien ini."

	cases := []struct {
		name string
		role string
		next *time.Time
		want string
	}{
		// 1. Pasien tanpa paket, ada sesi berikutnya.
		{"pasien ada sesi berikutnya", "patient", next, wantNextPatient},
		// 2. Pasien tanpa paket, tidak ada sesi berikutnya.
		{"pasien tanpa sesi", "patient", nil, wantNoNextPatient},
		// 4. Profesional, ada sesi berikutnya.
		{"profesional ada sesi berikutnya", "professional", next, wantNextProfessional},
		// 5. Profesional, tidak ada sesi berikutnya.
		{"profesional tanpa sesi", "professional", nil, wantNoNextProfessional},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			got := chatAccessReason(c.role, c.next)
			if got != c.want {
				t.Fatalf("chatAccessReason(%q, %v) = %q, mau %q", c.role, c.next, got, c.want)
			}
			// Kasus 3 (pasien dengan paket aktif) ditangani cabang inline di
			// ChatAccessFor dengan copy berbagi-data — bukan lewat helper ini.
			// Profesional tidak boleh pernah melihat copy sisi pasien.
			if c.role == "professional" {
				if strings.Contains(got, "Di luar sesi") || strings.Contains(got, "kamu bisa mengirim data") {
					t.Errorf("copy profesional memuat frasa sisi pasien: %q", got)
				}
			}
		})
	}
}

func TestInSessionWindow(t *testing.T) {
	start := time.Date(2026, 7, 10, 14, 0, 0, 0, locationWIB)
	const duration = 30 // menit -> jendela: start-10m s/d start+60m

	cases := []struct {
		name string
		now  time.Time
		want bool
	}{
		{"tepat 10 menit sebelum mulai (batas bawah inklusif)", start.Add(-10 * time.Minute), true},
		{"1 detik sebelum batas bawah", start.Add(-10*time.Minute - time.Second), false},
		{"tepat saat mulai", start, true},
		{"di tengah sesi", start.Add(15 * time.Minute), true},
		{"tepat batas atas (durasi+30 menit)", start.Add(time.Duration(duration+30) * time.Minute), true},
		{"1 detik setelah batas atas", start.Add(time.Duration(duration+30)*time.Minute + time.Second), false},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := inSessionWindow(c.now, start, duration); got != c.want {
				t.Fatalf("inSessionWindow(%v, %v, %d) = %v, mau %v", c.now, start, duration, got, c.want)
			}
		})
	}

	// duration <= 0 diperlakukan sebagai 30 menit: jendela tetap terbuka di
	// tengah sesi standar.
	if !inSessionWindow(start.Add(15*time.Minute), start, 0) {
		t.Fatal("duration 0 seharusnya diperlakukan 30 menit; chat harus aktif di tengah sesi")
	}
}
