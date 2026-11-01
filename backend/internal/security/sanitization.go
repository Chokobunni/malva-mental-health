package security

import (
	"regexp"
	"strings"
)

var (
	scriptTagRe   = regexp.MustCompile(`(?i)<script[^>]*>.*?</script>`)
	onEventRe     = regexp.MustCompile(`(?i)\bon\w+\s*=`)
	javascriptRe  = regexp.MustCompile(`(?i)javascript:`)
	dataRe        = regexp.MustCompile(`(?i)data:[^,]*;base64`)
	sqlInjectRe   = regexp.MustCompile(`(?i)(\b(union|select|insert|update|delete|drop|alter|create|exec|execute)\b\s)|(\b(or|and)\b\s+\d+\s*=\s*\d+)|(-{2})|(/\*)|(\*/)|(\bwaitfor\b\s+delay)`)
	pathTraversRe = regexp.MustCompile(`(\.\./|\.\.\\)`)

	// controlCharsRe mencocokkan karakter kontrol ASCII (\x00–\x1F) beserta
	// \x7F (DEL), KECUALI tab (\t) dan newline (\n) yang sah untuk teks
	// multiline (mis. diagnosis, summary worksheet).
	controlCharsRe = regexp.MustCompile(`[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]`)
	// multiSpaceRe merapikan deretan spasi/tab BERLEBIH (2+) menjadi satu spasi.
	// Spasi tunggal dipertahankan agar teks normal tidak berubah.
	multiSpaceRe = regexp.MustCompile(`[ \t]{2,}`)
)

func SanitizeHTML(input string) string {
	input = scriptTagRe.ReplaceAllString(input, "")
	input = onEventRe.ReplaceAllString(input, "")
	input = javascriptRe.ReplaceAllString(input, "")
	input = dataRe.ReplaceAllString(input, "")
	return input
}

// SanitizeText membersihkan teks yang akan DISIMPAN: membuang karakter
// kontrol (kecuali \n dan \t), merapikan spasi berlebih, lalu TrimSpace.
//
// PENTING: fungsi ini TIDAK melakukan HTML-escaping. Escaping (mis. `&` -> `&amp;`)
// adalah tanggung jawab lapisan RENDER, bukan penyimpanan. Klien Flutter tidak
// merender HTML, sehingga escaping saat menyimpan hanya mengorupsi data
// (mis. diagnosis berisi `&amp;` tampil mentah di UI). Lihat migrasi
// 025_unescape_sanitized_text.sql untuk pembersihan data lama.
func SanitizeText(input string) string {
	input = controlCharsRe.ReplaceAllString(input, "")
	input = multiSpaceRe.ReplaceAllString(input, " ")
	input = strings.TrimSpace(input)
	return input
}

func DetectSQLInjection(input string) bool {
	return sqlInjectRe.MatchString(input)
}

func DetectPathTraversal(input string) bool {
	return pathTraversRe.MatchString(input)
}

func SanitizeFilename(name string) string {
	name = strings.ReplaceAll(name, "/", "")
	name = strings.ReplaceAll(name, "\\", "")
	name = strings.ReplaceAll(name, "..", "")
	name = strings.ReplaceAll(name, "%", "")
	name = strings.TrimSpace(name)
	if len(name) > 255 {
		name = name[:255]
	}
	return name
}

func ValidateEmail(email string) bool {
	email = strings.TrimSpace(strings.ToLower(email))
	if len(email) < 3 || len(email) > 254 {
		return false
	}
	atIndex := strings.Index(email, "@")
	if atIndex < 1 || atIndex >= len(email)-1 {
		return false
	}
	domain := email[atIndex+1:]
	if !strings.Contains(domain, ".") {
		return false
	}
	parts := strings.Split(domain, ".")
	for _, part := range parts {
		if len(part) == 0 {
			return false
		}
	}
	return true
}

func SanitizeInput(input string, maxLen int) string {
	input = strings.TrimSpace(input)
	input = SanitizeHTML(input)
	if maxLen > 0 && len(input) > maxLen {
		input = input[:maxLen]
	}
	return input
}

func DetectSuspiciousInput(input string) (bool, string) {
	if DetectSQLInjection(input) {
		return true, "possible SQL injection"
	}
	if DetectPathTraversal(input) {
		return true, "possible path traversal"
	}
	if scriptTagRe.MatchString(input) {
		return true, "possible XSS"
	}
	if onEventRe.MatchString(input) {
		return true, "possible event handler injection"
	}
	return false, ""
}
