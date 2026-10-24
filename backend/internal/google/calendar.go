package google

import (
	"context"
	"fmt"
	"strings"
	"time"

	"golang.org/x/oauth2"
	googoauth "golang.org/x/oauth2/google"
	calendar "google.golang.org/api/calendar/v3"
	googleapi "google.golang.org/api/option"

	"malva/backend/internal/config"
	"malva/backend/internal/store"
)

// ErrReauthNeeded dikembalikan saat refresh token sudah tidak valid
// (mis. user mencabut akses dari Google Account settings). Handler harus
// mengarahkan user untuk menautkan ulang akun Google.
var ErrReauthNeeded = fmt.Errorf("google re-authentication needed")

// CalendarService membungkus akses ke Google Calendar API untuk membuat,
// mengubah, dan membatalkan event Meet atas nama profesional.
type CalendarService struct {
	cfg   config.Config
	store *store.Store
}

// MeetEventOptions parameter pembuatan event Meet baru.
type MeetEventOptions struct {
	Summary   string
	StartTime time.Time
	EndTime   time.Time
}

// NewCalendarService membuat instance CalendarService.
func NewCalendarService(cfg config.Config, st *store.Store) *CalendarService {
	return &CalendarService{cfg: cfg, store: st}
}

// oauth2Config mengembalikan konfigurasi OAuth2 untuk pertukaran token
// dan akses Calendar API. RedirectURL kosong karena kita hanya memakai
// authorization code flow dari aplikasi mobile (PKCE-like).
func (c *CalendarService) oauth2Config() *oauth2.Config {
	return &oauth2.Config{
		ClientID:     c.cfg.GoogleClientID,
		ClientSecret: c.cfg.GoogleClientSecret,
		Endpoint:     googoauth.Endpoint,
		Scopes:       []string{calendar.CalendarEventsScope},
	}
}

// getClient mengambil stored token, membuat HTTP client terautentikasi,
// dan memperbarui token bila terjadi auto-refresh oleh library oauth2.
func (c *CalendarService) getClient(ctx context.Context, professionalUserID string) (*oauth2.Token, error) {
	stored, err := c.store.GetGoogleToken(ctx, professionalUserID)
	if err != nil {
		return nil, ErrReauthNeeded
	}
	tok := &oauth2.Token{
		AccessToken:  stored.AccessToken,
		RefreshToken: stored.RefreshToken,
		TokenType:    "Bearer",
		Expiry:       stored.TokenExpiry,
	}
	// TokenSource otomatis melakukan refresh bila token kedaluwarsa.
	ts := c.oauth2Config().TokenSource(ctx, tok)
	newTok, err := ts.Token()
	if err != nil {
		// Refresh gagal (invalid_grant, token revoked, dll.)
		errMsg := strings.ToLower(err.Error())
		if strings.Contains(errMsg, "invalid_grant") ||
			strings.Contains(errMsg, "token has been expired or revoked") ||
			strings.Contains(errMsg, "unauthorized_client") {
			return nil, ErrReauthNeeded
		}
		return nil, fmt.Errorf("gagal mendapatkan token Google: %w", err)
	}
	// Bila token berubah (auto-refresh), simpan yang baru.
	if newTok.AccessToken != tok.AccessToken || newTok.RefreshToken != tok.RefreshToken {
		refresh := newTok.RefreshToken
		if refresh == "" {
			refresh = stored.RefreshToken // refresh token tidak selalu dikembalikan
		}
		if uerr := c.store.UpsertGoogleToken(ctx, professionalUserID, refresh, newTok.AccessToken, newTok.Expiry, stored.Scope); uerr != nil {
			// Log saja, jangan gagalkan operasi kalender.
			_ = uerr
		}
	}
	return newTok, nil
}

// calendarSvc membuat Calendar API service untuk user tertentu.
func (c *CalendarService) calendarSvc(ctx context.Context, professionalUserID string) (*calendar.Service, error) {
	tok, err := c.getClient(ctx, professionalUserID)
	if err != nil {
		return nil, err
	}
	client := c.oauth2Config().Client(ctx, tok)
	svc, err := calendar.NewService(ctx, googleapi.WithHTTPClient(client))
	if err != nil {
		return nil, fmt.Errorf("gagal membuat Calendar service: %w", err)
	}
	return svc, nil
}

// CreateMeetEvent membuat event Google Calendar dengan konferensi Meet.
// Mengembalikan (eventID, meetURL, error).
func (c *CalendarService) CreateMeetEvent(ctx context.Context, professionalUserID string, opts MeetEventOptions) (string, string, error) {
	svc, err := c.calendarSvc(ctx, professionalUserID)
	if err != nil {
		return "", "", err
	}
	requestID := fmt.Sprintf("malva-%d", time.Now().UnixNano())
	event := &calendar.Event{
		Summary: opts.Summary,
		Start: &calendar.EventDateTime{
			DateTime: opts.StartTime.Format(time.RFC3339),
			TimeZone: "Asia/Jakarta",
		},
		End: &calendar.EventDateTime{
			DateTime: opts.EndTime.Format(time.RFC3339),
			TimeZone: "Asia/Jakarta",
		},
		ConferenceData: &calendar.ConferenceData{
			CreateRequest: &calendar.CreateConferenceRequest{
				RequestId: requestID,
				ConferenceSolutionKey: &calendar.ConferenceSolutionKey{
					Type: "hangoutsMeet",
				},
			},
		},
	}
	call := svc.Events.Insert("primary", event).ConferenceDataVersion(1)
	created, err := call.Context(ctx).Do()
	if err != nil {
		return "", "", fmt.Errorf("gagal membuat event Meet: %w", err)
	}
	meetURL := ""
	if created.ConferenceData != nil && len(created.ConferenceData.EntryPoints) > 0 {
		meetURL = created.ConferenceData.EntryPoints[0].Uri
	}
	return created.Id, meetURL, nil
}

// UpdateMeetEvent mengubah waktu mulai/selesai event yang sudah ada.
func (c *CalendarService) UpdateMeetEvent(ctx context.Context, professionalUserID, eventID string, newStart, newEnd time.Time) error {
	svc, err := c.calendarSvc(ctx, professionalUserID)
	if err != nil {
		return err
	}
	// Ambil event yang ada terlebih dahulu.
	existing, err := svc.Events.Get("primary", eventID).Context(ctx).Do()
	if err != nil {
		return fmt.Errorf("gagal mengambil event Meet: %w", err)
	}
	existing.Start = &calendar.EventDateTime{
		DateTime: newStart.Format(time.RFC3339),
		TimeZone: "Asia/Jakarta",
	}
	existing.End = &calendar.EventDateTime{
		DateTime: newEnd.Format(time.RFC3339),
		TimeZone: "Asia/Jakarta",
	}
	_, err = svc.Events.Update("primary", eventID, existing).Context(ctx).Do()
	if err != nil {
		return fmt.Errorf("gagal memperbarui event Meet: %w", err)
	}
	return nil
}

// CancelMeetEvent menghapus event dari kalender profesional.
func (c *CalendarService) CancelMeetEvent(ctx context.Context, professionalUserID, eventID string) error {
	svc, err := c.calendarSvc(ctx, professionalUserID)
	if err != nil {
		return err
	}
	err = svc.Events.Delete("primary", eventID).Context(ctx).Do()
	if err != nil {
		return fmt.Errorf("gagal membatalkan event Meet: %w", err)
	}
	return nil
}
