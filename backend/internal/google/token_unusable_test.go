package google

import (
	"errors"
	"testing"

	"golang.org/x/oauth2"
)

// ============================================================
// DETEKSI REFRESH TOKEN YANG SUDAH TIDAK BERLAKU
//
// Penting untuk BUG 3: selama OAuth consent screen berstatus "Testing",
// Google hanya memberi refresh token berlaku 7 hari. Setelah itu setiap
// refresh dibalas `invalid_grant`. Tanpa klasifikasi ini, status profesional
// tetap terlihat "aktif" (bohong) dan setiap percobaan memanggil Google lagi.
//
// Klasifikasi dipakai getClient untuk menghapus token lalu mengembalikan
// ErrReauthNeeded, sehingga UI berubah menjadi "perlu tautkan ulang".
// ============================================================

func TestTokenUnusableDetectsInvalidGrant(t *testing.T) {
	cases := []struct {
		name string
		err  error
		want bool
	}{
		{
			name: "oauth2 RetrieveError invalid_grant",
			err:  &oauth2.RetrieveError{ErrorCode: "invalid_grant", ErrorDescription: "Token has been expired or revoked."},
			want: true,
		},
		{
			name: "pesan invalid_grant tanpa tipe RetrieveError",
			err:  errors.New(`oauth2: "invalid_grant" "Token has been expired or revoked."`),
			want: true,
		},
		{
			name: "unauthorized_client",
			err:  errors.New("oauth2: cannot fetch token: 401 Unauthorized unauthorized_client"),
			want: true,
		},
		{
			name: "kegagalan jaringan sementara bukan alasan tautkan ulang",
			err:  errors.New("dial tcp: i/o timeout"),
			want: false,
		},
		{
			name: "5xx Google bukan alasan tautkan ulang",
			err:  errors.New("googleapi: Error 503: Backend Error"),
			want: false,
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := tokenUnusable(tc.err); got != tc.want {
				t.Fatalf("tokenUnusable(%v) = %v, mau %v", tc.err, got, tc.want)
			}
		})
	}
}
