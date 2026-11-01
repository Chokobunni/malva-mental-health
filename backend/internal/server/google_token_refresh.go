package server

import (
	"context"
	"errors"
	"time"

	"golang.org/x/oauth2"
	googoauth "golang.org/x/oauth2/google"

	"malva/backend/internal/clock"
	"malva/backend/internal/store"
)

const (
	// Pemeliharaan tujuh hari bukan pengganti refresh access token per jam.
	googleTokenMaintenanceInterval = 7 * 24 * time.Hour
	// Sweeper sepuluh menit memperbarui sebelum access token habis.
	googleAccessTokenRefreshLead = 15 * time.Minute
)

// RunGoogleTokenRefresh memperbarui access token sebelum habis, atau setidaknya
// setiap tujuh hari bila Google menerbitkan access token berumur lebih panjang.
// Hasil dan last_refreshed_at disimpan atomik; refresh token rotasi ikut disimpan.
// Semua kegagalan hanya dicatat untuk operator, tanpa notifikasi pengguna.
//
// Google menerapkan batas refresh token tujuh hari untuk aplikasi OAuth External
// berstatus Testing yang meminta Calendar. Tidak ada cara programatik untuk
// memperpanjang batas tersebut: refresh hanya menjaga access token tetap segar
// dan menangkap rotasi. Status Production menghapus batas Testing, bukan
// menjamin token abadi (token masih dapat dicabut atau kedaluwarsa karena alasan
// lain). Publikasikan lewat OAuth consent screen → Publish app, lalu consent
// ulang bila perlu; lihat docs/GOOGLE_CALENDAR_SETUP.md.
func (s *Server) RunGoogleTokenRefresh(ctx context.Context) (int, error) {
	if s.store == nil || s.cfg.GoogleClientID == "" || s.cfg.GoogleClientSecret == "" {
		return 0, nil
	}
	// Satu proses tidak boleh menjalankan dua refresh terjadwal bersamaan.
	s.googleRefreshMu.Lock()
	defer s.googleRefreshMu.Unlock()
	now := clock.Now()
	candidates, err := s.store.ListGoogleTokensDueForRefresh(ctx,
		now.Add(-googleTokenMaintenanceInterval), now.Add(googleAccessTokenRefreshLead))
	if err != nil {
		return 0, err
	}
	oauthCfg := &oauth2.Config{
		ClientID:     s.cfg.GoogleClientID,
		ClientSecret: s.cfg.GoogleClientSecret,
		Endpoint:     googoauth.Endpoint,
	}
	refreshed := 0
	for _, candidate := range candidates {
		if err := ctx.Err(); err != nil {
			return refreshed, err
		}
		if !store.HasCalendarScope(candidate.Scope) {
			continue
		}
		refreshCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
		// Access token kosong memaksa TokenSource menukar refresh token.
		token, refreshErr := oauthCfg.TokenSource(refreshCtx,
			&oauth2.Token{RefreshToken: candidate.RefreshToken}).Token()
		cancel()
		if refreshErr != nil {
			// Jangan log RetrieveError mentah: body Google dapat memuat token.
			code := "jaringan_atau_respons_tidak_valid"
			var oauthErr *oauth2.RetrieveError
			if errors.As(refreshErr, &oauthErr) {
				switch oauthErr.ErrorCode {
				case "invalid_grant", "invalid_client", "unauthorized_client", "temporarily_unavailable":
					code = oauthErr.ErrorCode
				default:
					code = "oauth_ditolak"
				}
			}
			if s.logger != nil {
				s.logger.Warn("auto-refresh token Google gagal", "user", candidate.UserID, "code", code)
			}
			if code == "invalid_grant" {
				// Token dicabut/kedaluwarsa tidak boleh dicoba tanpa akhir.
				if err := s.store.DeleteGoogleTokenIfUnchanged(ctx, candidate.UserID, candidate.RefreshToken); err != nil {
					return refreshed, err
				}
			}
			continue
		}
		refresh := token.RefreshToken
		if refresh == "" {
			refresh = candidate.RefreshToken
		}
		saved, err := s.store.SaveGoogleTokenRefresh(ctx, candidate.UserID,
			candidate.RefreshToken, refresh, token.AccessToken, token.Expiry)
		if err != nil {
			return refreshed, err
		}
		if saved {
			refreshed++
		}
	}
	return refreshed, nil
}
