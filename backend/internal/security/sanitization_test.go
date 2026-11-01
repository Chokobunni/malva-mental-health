package security

import "testing"

// TestSanitizeTextTidakMengEscapeHTML mengunci perbaikan Bug C: SanitizeText
// TIDAK boleh meng-HTML-escape karakter & < > " '. Klien Flutter tidak
// merender HTML, sehingga escaping saat menyimpan mengorupsi data (mis.
// diagnosis berisi "&amp;" tampil mentah). Escaping adalah tanggung jawab
// lapisan render, bukan penyimpanan.
func TestSanitizeTextTidakMengEscapeHTML(t *testing.T) {
	cases := []struct {
		name, in, want string
	}{
		{"ampersand", "F41.1 & F60.3", "F41.1 & F60.3"},
		{"kurung sudut", "tekan <enter> lalu > lanjut", "tekan <enter> lalu > lanjut"},
		{"kutip ganda", `dia bilang "halo"`, `dia bilang "halo"`},
		{"kutip tunggal", "ibu's cat", "ibu's cat"},
		{"campur semua", `a & b < c > d " e ' f`, `a & b < c > d " e ' f`},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := SanitizeText(c.in); got != c.want {
				t.Errorf("SanitizeText(%q) = %q, mau %q", c.in, got, c.want)
			}
		})
	}
}

// TestSanitizeTextMembuangKarakterKontrol: karakter kontrol \x00-\x1F dibuang,
// tetapi \n dan \t dipertahankan karena sah untuk teks multiline.
func TestSanitizeTextMembuangKarakterKontrol(t *testing.T) {
	cases := []struct {
		name, in, want string
	}{
		{"null", "sebelum\x00sesudah", "sebelumsesudah"},
		{"bell", "a\x07b", "ab"},
		{"vertical tab", "a\x0bb", "ab"},
		{"newline dipertahankan", "baris1\nbaris2", "baris1\nbaris2"},
		{"tab tunggal dipertahankan", "kolom1\tkolom2", "kolom1\tkolom2"},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := SanitizeText(c.in); got != c.want {
				t.Errorf("SanitizeText(%q) = %q, mau %q", c.in, got, c.want)
			}
		})
	}
}

// TestSanitizeTextMerapikanSpasi: deretan spasi berlebih dirapikan menjadi satu,
// spasi tunggal dipertahankan, dan leading/trailing di-TrimSpace.
func TestSanitizeTextMerapikanSpasi(t *testing.T) {
	cases := []struct {
		name, in, want string
	}{
		{"spasi berlebih", "halo    dunia", "halo dunia"},
		{"leading trailing", "   halo dunia   ", "halo dunia"},
		{"tab berlebih", "a\t\t\tb", "a b"},
		{"spasi tunggal tetap", "halo dunia", "halo dunia"},
		{"kosong", "   ", ""},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			if got := SanitizeText(c.in); got != c.want {
				t.Errorf("SanitizeText(%q) = %q, mau %q", c.in, got, c.want)
			}
		})
	}
}
