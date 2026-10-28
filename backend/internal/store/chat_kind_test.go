package store

import "testing"

// Unit test murni (tanpa DB) untuk normalisasi kind pesan chat.
//
// Regresi yang dijaga: sebelum "worksheet" masuk `validChatKinds`,
// normalizeChatKind diam-diam mengubah kartu worksheet menjadi "text"
// sehingga kartu ringkasan worksheet tidak pernah muncul di chat.
func TestNormalizeChatKind(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{"text", "text"},
		{"summary", "summary"},
		{"assessment", "assessment"},
		{"worksheet", "worksheet"},
		{"prescription", "prescription"},
		{"goals", "goals"},
		{"diary", "diary"},
		{"file", "file"},
		{"voice", "voice"},
		// Kosong / tak dikenal dinormalisasi menjadi teks biasa.
		{"", "text"},
		{"kind-yang-tidak-ada", "text"},
	}

	for _, tc := range cases {
		t.Run(tc.in, func(t *testing.T) {
			if got := normalizeChatKind(tc.in); got != tc.want {
				t.Fatalf("normalizeChatKind(%q) = %q, mau %q", tc.in, got, tc.want)
			}
		})
	}
}

// validChatKinds harus memuat kind yang dipakai backend saat share worksheet.
func TestValidChatKindsContainsShareKinds(t *testing.T) {
	for _, kind := range []string{"assessment", "worksheet"} {
		if !validChatKinds[kind] {
			t.Fatalf("validChatKinds tidak memuat %q", kind)
		}
	}
}
