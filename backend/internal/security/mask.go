package security

import "strings"

// MaskEmail menyamarkan alamat email dengan mempertahankan karakter pertama
// bagian lokal dan seluruh domain. Contoh: "budi@gmail.com" -> "b***@gmail.com".
// String kosong menghasilkan "". Nilai tanpa '@' yang valid disamarkan penuh.
func MaskEmail(email string) string {
	email = strings.TrimSpace(email)
	if email == "" {
		return ""
	}
	at := strings.IndexByte(email, '@')
	if at <= 0 {
		return "***"
	}
	local := email[:at]
	domain := email[at:]
	runes := []rune(local)
	if len(runes) == 0 {
		return "***" + domain
	}
	return string(runes[0]) + "***" + domain
}

// MaskPhone menyamarkan nomor telepon dengan mempertahankan 3 karakter awal
// dan 4 karakter terakhir. Contoh: "+6281234567890" -> "+62****7890".
// Nomor terlalu pendek (<= 7 karakter) disamarkan penuh menjadi "****".
// String kosong menghasilkan "".
func MaskPhone(phone string) string {
	phone = strings.TrimSpace(phone)
	if phone == "" {
		return ""
	}
	runes := []rune(phone)
	n := len(runes)
	if n <= 7 {
		return "****"
	}
	return string(runes[:3]) + "****" + string(runes[n-4:])
}

// MaskToken menyamarkan token/secret dengan mempertahankan 4 karakter awal
// diikuti "****". Token lebih pendek dari 8 karakter disamarkan penuh menjadi
// "****" agar tidak membocorkan sebagian besar nilai. String kosong -> "".
func MaskToken(token string) string {
	token = strings.TrimSpace(token)
	if token == "" {
		return ""
	}
	if len(token) < 8 {
		return "****"
	}
	return token[:4] + "****"
}
