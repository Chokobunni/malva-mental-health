package server

import (
	"testing"

	"malva/backend/internal/store"
)

// TestMeetReadyTruthTable mengunci satu-satunya definisi "Google Meet siap".
//
// Fungsi ini dipakai dua tempat yang tidak boleh berbeda pendapat:
//   - googleStatusHandler (kartu pengaturan profesional: tombol "Aktifkan" vs
//     "Google Meet aktif"), dan
//   - createBooking (menolak pesanan sesi video sebelum pasien membayar).
//
// Bila salah satu syarat dilonggarkan tanpa sengaja, pasien bisa membayar
// sesi video yang ruang pertemuannya tidak mungkin dibuat.
func TestMeetReadyTruthTable(t *testing.T) {
	identity := store.GoogleIdentity{Linked: true, Subject: "sub-1"}
	token := store.GoogleTokenInfo{
		GoogleSubject:   "sub-1",
		HasRefreshToken: true,
		Scope:           "https://www.googleapis.com/auth/calendar.events",
	}
	cases := []struct {
		name       string
		configured bool
		identity   store.GoogleIdentity
		token      store.GoogleTokenInfo
		want       bool
	}{
		{"semua syarat terpenuhi", true, identity, token, true},
		{"server tanpa client secret", false, identity, token, false},
		{"identitas belum tertaut", true, store.GoogleIdentity{}, token, false},
		{"token milik akun Google lain", true, identity,
			store.GoogleTokenInfo{GoogleSubject: "sub-2", HasRefreshToken: true,
				Scope: "https://www.googleapis.com/auth/calendar.events"}, false},
		{"tanpa refresh token", true, identity,
			store.GoogleTokenInfo{GoogleSubject: "sub-1", Scope: "https://www.googleapis.com/auth/calendar.events"}, false},
		{"tanpa izin calendar", true, identity,
			store.GoogleTokenInfo{GoogleSubject: "sub-1", HasRefreshToken: true, Scope: "openid email"}, false},
		{"izin calendar penuh", true, identity,
			store.GoogleTokenInfo{GoogleSubject: "sub-1", HasRefreshToken: true,
				Scope: "https://www.googleapis.com/auth/calendar"}, true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := meetReady(tc.configured, tc.identity, tc.token); got != tc.want {
				t.Fatalf("meetReady = %v, mau %v", got, tc.want)
			}
		})
	}
}
