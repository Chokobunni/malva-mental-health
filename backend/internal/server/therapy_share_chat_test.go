package server

import (
	"strings"
	"testing"
)

// Unit test murni untuk therapyShareChat — menentukan kind & teks pesan chat
// yang dibuat saat pasien membagikan worksheet. Tidak butuh DB/server.
func TestTherapyShareChat(t *testing.T) {
	cases := []struct {
		name         string
		moduleID     string
		title        string
		summary      string
		wantKind     string
		wantContains []string
	}{
		{
			name:         "dass21 memakai kind assessment",
			moduleID:     "dass21",
			title:        "DASS-21",
			summary:      "Depresi 10 (Ringan) • Kecemasan 8 (Ringan) • Stres 12 (Normal)",
			wantKind:     "assessment",
			wantContains: []string{"Hasil", "Depresi 10"},
		},
		{
			name:         "who5 memakai kind assessment",
			moduleID:     "who5",
			title:        "WHO-5",
			summary:      "WHO-5 12/25 (48%) — Kesejahteraan rendah",
			wantKind:     "assessment",
			wantContains: []string{"Hasil", "WHO-5 12/25"},
		},
		{
			name:         "worksheet latihan memakai kind worksheet",
			moduleID:     "abcde",
			title:        "Restrukturisasi Kognitif (ABCDE)",
			summary:      "",
			wantKind:     "worksheet",
			wantContains: []string{"Worksheet", "ABCDE"},
		},
		{
			name:         "judul kosong pada worksheet tetap informatif",
			moduleID:     "abcde",
			title:        "   ",
			summary:      "",
			wantKind:     "worksheet",
			wantContains: []string{"Worksheet"},
		},
		{
			name:         "judul kosong pada asesmen menyebut asesmen",
			moduleID:     "dass21",
			title:        "",
			summary:      "",
			wantKind:     "assessment",
			wantContains: []string{"Hasil", "asesmen"},
		},
		{
			name:         "ringkasan kosong tidak menghasilkan titik dua menggantung",
			moduleID:     "who5",
			title:        "WHO-5",
			summary:      "  ",
			wantKind:     "assessment",
			wantContains: []string{"Hasil WHO-5 dibagikan."},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			kind, text := therapyShareChat(tc.moduleID, tc.title, tc.summary)
			if kind != tc.wantKind {
				t.Fatalf("kind = %q, mau %q", kind, tc.wantKind)
			}
			for _, want := range tc.wantContains {
				if !strings.Contains(text, want) {
					t.Fatalf("teks %q tidak memuat %q", text, want)
				}
			}
			if strings.Contains(text, ": :") || strings.Contains(text, ": .") {
				t.Fatalf("teks tidak rapi: %q", text)
			}
		})
	}
}
