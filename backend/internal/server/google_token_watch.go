package server

import (
	"context"
	"fmt"
	"time"

	"malva/backend/internal/clock"
)

// notifGoogleTokenExpiring adalah tipe notifikasi peringatan bahwa izin Google
// Calendar profesional akan kedaluwarsa. Muncul karena OAuth consent screen
// masih "Testing" sehingga Google hanya memberi refresh token berlaku 7 hari.
const notifGoogleTokenExpiring = "google_calendar_expiring"

// RunGoogleTokenExpiryCheck memindai SEMUA refresh token Google yang tersimpan
// dan mengirim notifikasi proaktif ke profesional yang grant-nya mendekati
// kedaluwarsa (umur >= TTL-1 hari). Maksimal satu notifikasi per hari per grant
// agar tidak membanjiri pengguna; begitu profesional memperbarui izin, tanggal
// grant berubah sehingga hitungan umur kembali dari awal.
//
// Mengembalikan jumlah notifikasi yang benar-benar terkirim. TTL 0 (mis. setelah
// aplikasi dipublikasikan) mematikan peringatan sepenuhnya. store nil (Server
// parsial pada test) juga no-op.
func (s *Server) RunGoogleTokenExpiryCheck(ctx context.Context) (int, error) {
	ttl := s.googleRefreshTokenTTL()
	if ttl <= 0 || s.store == nil {
		return 0, nil
	}
	grants, err := s.store.ListGoogleTokenGrantAges(ctx)
	if err != nil {
		return 0, err
	}
	warnFrom := ttl - 24*time.Hour
	now := clock.Now()
	sent := 0
	for _, g := range grants {
		age := now.Sub(g.IssuedAt)
		if age < warnFrom {
			continue
		}
		ageDays := int(age.Hours() / 24)
		if ageDays < 0 {
			ageDays = 0
		}
		// Dedupe harian: reference memuat tanggal grant + umur hari. Karena
		// umur bertambah tiap hari, satu grant menghasilkan reference berbeda
		// tiap hari (maksimal satu notifikasi/hari) tanpa perlu skema baru.
		reference := fmt.Sprintf("%s#d%d", g.IssuedAt.In(clock.Location()).Format("2006-01-02"), ageDays)
		if s.alreadyNotifiedForReference(ctx, g.UserID, notifGoogleTokenExpiring, reference) {
			continue
		}
		daysLeft := ttl - age
		if daysLeft < 0 {
			daysLeft = 0
		}
		// Bulatkan ke atas: sisa 0,5 hari tetap "1 hari".
		daysLeftInt := int((daysLeft + 24*time.Hour - 1) / (24 * time.Hour))
		when := "besok"
		if daysLeftInt <= 0 {
			when = "hari ini"
		}
		body := "Izin Google Calendar Anda berakhir " + when +
			" karena aplikasi masih dalam mode Testing. " +
			"Buka Pengaturan → Akun Google lalu tekan \"Perbarui izin\" agar link Meet sesi video tetap dibuat otomatis."
		s.notifyUser(ctx, g.UserID, notifGoogleTokenExpiring,
			"Izin Google Calendar perlu diperbarui",
			body,
			map[string]string{
				"reference": reference,
				"days_left": fmt.Sprintf("%d", daysLeftInt),
			})
		sent++
	}
	return sent, nil
}
