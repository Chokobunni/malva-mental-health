package google

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"

	"golang.org/x/oauth2"
	googoauth "golang.org/x/oauth2/google"
	calendar "google.golang.org/api/calendar/v3"
	googleapi "google.golang.org/api/option"

	"malva/backend/internal/clock"
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
	Summary string
	// Description tampil di undangan kalender (opsional).
	Description string
	StartTime   time.Time
	EndTime     time.Time
	// AttendeeEmails diundang ke event sehingga menerima email undangan dan
	// pengingat dari Google Calendar. Kosong = event hanya milik profesional.
	AttendeeEmails []string
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
	identity, err := c.store.GetGoogleIdentity(ctx, professionalUserID)
	if err != nil || !identity.Linked {
		return nil, ErrReauthNeeded
	}
	stored, err := c.store.GetGoogleToken(ctx, professionalUserID)
	if err != nil || stored.GoogleSubject != identity.Subject || strings.TrimSpace(stored.RefreshToken) == "" || !store.HasCalendarScope(stored.Scope) {
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
		if tokenUnusable(err) {
			// Refresh token ditolak Google (dicabut, kedaluwarsa — termasuk
			// kasus consent screen masih "Testing" yang membuat refresh token
			// hanya berlaku 7 hari — atau unauthorized_client). Hapus baris
			// token agar status berubah dari "aktif" (bohong) menjadi "perlu
			// tautkan ulang", dan percobaan berikutnya gagal cepat tanpa
			// memanggil Google lagi.
			if derr := c.store.DeleteGoogleToken(ctx, professionalUserID); derr != nil {
				// Kegagalan menghapus tidak mengubah hasil akhir: pemanggil
				// tetap harus menautkan ulang.
				_ = derr
			}
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
		// Auto-refresh access token BUKAN grant baru: pertahankan tanggal grant
		// lama agar umur refresh token tidak ter-reset (newGrant=false).
		if uerr := c.store.UpsertGoogleToken(ctx, professionalUserID, refresh, newTok.AccessToken, newTok.Expiry, stored.Scope, stored.GoogleSubject, false); uerr != nil {
			// Log saja, jangan gagalkan operasi kalender.
			_ = uerr
		}
	}
	return newTok, nil
}

// tokenUnusable melaporkan apakah kegagalan refresh token berarti token itu
// tidak akan pernah berhasil lagi (harus ditautkan ulang), bukan kegagalan
// sementara (jaringan/5xx Google).
//
// Google membalas `invalid_grant` untuk refresh token yang dicabut, kedaluwarsa,
// atau — kasus paling sering di Malva — diterbitkan saat OAuth consent screen
// masih berstatus "Testing" sehingga hanya berlaku 7 hari.
func tokenUnusable(err error) bool {
	var retrieveErr *oauth2.RetrieveError
	if errors.As(err, &retrieveErr) && strings.Contains(strings.ToLower(retrieveErr.ErrorCode), "invalid_grant") {
		return true
	}
	errMsg := strings.ToLower(err.Error())
	return strings.Contains(errMsg, "invalid_grant") ||
		strings.Contains(errMsg, "token has been expired or revoked") ||
		strings.Contains(errMsg, "unauthorized_client")
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

// buildMeetEvent menyusun payload event Google Calendar untuk satu sesi.
// Fungsi murni (tanpa jaringan/DB) agar format waktu WIB dan konferensi Meet
// bisa diuji langsung. Semua waktu dinormalkan ke zona WIB sehingga Google
// menerima offset +07:00, bukan Z.
func buildMeetEvent(opts MeetEventOptions, requestID string) *calendar.Event {
	start := opts.StartTime.In(clock.Location())
	end := opts.EndTime.In(clock.Location())
	event := &calendar.Event{
		Summary:     opts.Summary,
		Description: opts.Description,
		Start: &calendar.EventDateTime{
			DateTime: start.Format(time.RFC3339),
			TimeZone: "Asia/Jakarta",
		},
		End: &calendar.EventDateTime{
			DateTime: end.Format(time.RFC3339),
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
	// Undang peserta (pasien) agar menerima email undangan + pengingat.
	for _, email := range opts.AttendeeEmails {
		email = strings.TrimSpace(email)
		if email == "" {
			continue
		}
		event.Attendees = append(event.Attendees, &calendar.EventAttendee{Email: email})
	}
	return event
}

// CreateMeetEvent membuat event Google Calendar dengan konferensi Meet.
// Mengembalikan (eventID, meetURL, error).
func (c *CalendarService) CreateMeetEvent(ctx context.Context, professionalUserID string, opts MeetEventOptions) (string, string, error) {
	svc, err := c.calendarSvc(ctx, professionalUserID)
	if err != nil {
		return "", "", err
	}
	requestID := fmt.Sprintf("malva-%d", time.Now().UnixNano())
	event := buildMeetEvent(opts, requestID)
	call := svc.Events.Insert("primary", event).ConferenceDataVersion(1)
	if len(event.Attendees) > 0 {
		// sendUpdates=all: Google mengirim email undangan ke peserta.
		call = call.SendUpdates("all")
	}
	created, err := call.Context(ctx).Do()
	if err != nil {
		return "", "", fmt.Errorf("gagal membuat event Meet: %w", err)
	}
	var entryPoints []*calendar.EntryPoint
	if created.ConferenceData != nil {
		entryPoints = created.ConferenceData.EntryPoints
	}
	meetURL := pickMeetURL(entryPoints)
	return created.Id, meetURL, nil
}

// pickMeetURL memilih URI entry point konferensi bertipe video.
//
// Google Calendar mengembalikan beberapa entry point untuk satu conferenceData:
// selain "video" (tautan Meet sesungguhnya) ada juga "phone" (nomor dial-in)
// dan "more" (tautan informasi). Memakai indeks 0 secara membabi buta bisa
// menyimpan nomor telepon atau tautan informasi sebagai tautan Meet, sehingga
// pasien menerima tautan yang salah. Karena itu tipe "video" dicari lebih dulu;
// indeks 0 hanya dipakai sebagai fallback bila Google tidak menandai tipe
// apa pun (perilaku lama dipertahankan agar event tetap punya tautan).
func pickMeetURL(entryPoints []*calendar.EntryPoint) string {
	for _, ep := range entryPoints {
		if ep == nil || ep.Uri == "" {
			continue
		}
		if ep.EntryPointType == "video" {
			return ep.Uri
		}
	}
	for _, ep := range entryPoints {
		if ep != nil && ep.Uri != "" {
			return ep.Uri
		}
	}
	return ""
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
