package server

import "testing"

// TestIsGoogleMeetURL memastikan pengenalan link Google Meet benar, termasuk
// saat menolak link penyedia lama (Jitsi) agar bisa diganti.
func TestIsGoogleMeetURL(t *testing.T) {
	cases := []struct {
		in   string
		want bool
	}{
		{"https://meet.google.com/abc-defg-hij", true},
		{"https://MEET.GOOGLE.COM/abc-defg-hij", true},
		{"  https://meet.google.com/abc  ", true},
		{"https://meet.jit.si/malva-abc-123", false},
		{"https://zoom.us/j/123456", false},
		{"", false},
	}
	for _, c := range cases {
		if got := isGoogleMeetURL(c.in); got != c.want {
			t.Errorf("isGoogleMeetURL(%q) = %v, mau %v", c.in, got, c.want)
		}
	}
}
