package security

import "testing"

func TestMaskEmail(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"budi@gmail.com", "b***@gmail.com"},
		{"a@b.co", "a***@b.co"},
		{"", ""},
		{"   ", ""},
		{"not-an-email", "***"},
	}
	for _, c := range cases {
		if got := MaskEmail(c.in); got != c.want {
			t.Errorf("MaskEmail(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestMaskPhone(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"+6281234567890", "+62****7890"},
		{"081234567890", "081****7890"},
		{"", ""},
		{"1234567", "****"},         // 7 karakter -> penuh
		{"12345678", "123****5678"}, // 8 karakter -> awal3 + akhir4
	}
	for _, c := range cases {
		if got := MaskPhone(c.in); got != c.want {
			t.Errorf("MaskPhone(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestMaskToken(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"supersecrettoken", "supe****"},
		{"abcdefgh", "abcd****"},
		{"short", "****"},
		{"1234567", "****"},
		{"", ""},
	}
	for _, c := range cases {
		if got := MaskToken(c.in); got != c.want {
			t.Errorf("MaskToken(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}
