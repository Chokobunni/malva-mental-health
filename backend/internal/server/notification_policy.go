package server

import "fmt"

// notification_policy.go adalah SATU-SATUNYA tempat kebijakan "notifikasi mana
// yang boleh memicu push FCM". Semua handler memakai notifyPatient/notifyUser,
// yang menerapkan kebijakan di sini — jangan menyebar `if kind == ...` ke
// handler.
//
// Latar belakang: pasien menerima ledakan push duplikat dan profesional
// menerima push untuk hal-hal yang tidak butuh intervensi mendesak. Kebijakan:
//   * Pasien  — hanya peristiwa SESI, PEMBAYARAN, OBAT, KRISIS yang push.
//     Jenis low-priority (review screening, health record, catatan, terapi,
//     kredensial) digabung menjadi digest harian (in-app saja).
//   * Profesional — hanya SESI & CHAT yang push. Sisanya in-app saja.
//
// Default (kind tak dikenal) = TIDAK push (in-app saja). Ini konsisten dengan
// prinsip "kurangi kebisingan": jenis baru harus didaftarkan eksplisit bila
// memang layak push.

// patientPushKinds adalah jenis notifikasi yang boleh memicu push untuk pasien.
var patientPushKinds = map[string]bool{
	// Sesi & video call.
	"session_meet_ready":             true,
	"session_scheduled":              true,
	"session_rescheduled":            true,
	"session_cancelled_patient":      true,
	"session_cancelled_professional": true,
	"session_reminder":               true,
	"session_meet_missing":           true,
	"session_meet_update_failed":     true,
	"session_needs_reschedule":       true,
	// Paket & pembayaran.
	"package_activated":            true,
	"payment_needs_reconciliation": true,
	// Obat.
	"medication_prescribed": true,
	"prescription_created":  true,
	"medication_reminder":   true,
	// Krisis / SOS.
	"crisis_alert": true,
}

// professionalPushKinds adalah jenis notifikasi yang boleh memicu push untuk
// profesional: HANYA sesi & chat.
var professionalPushKinds = map[string]bool{
	"session_scheduled":              true,
	"session_rescheduled":            true,
	"session_cancelled_patient":      true,
	"session_cancelled_professional": true,
	"session_reminder":               true,
	"session_meet_missing":           true,
	"session_meet_update_failed":     true,
	"session_meet_ready":             true,
	"session_needs_reschedule":       true,
	// Pesan chat (bila/ketika notifikasi chat dibuat; WS chat_message tetap
	// realtime terpisah).
	"chat_message": true,
}

// patientDigestKinds adalah jenis yang DIGABUNG menjadi digest harian per
// (user, profesional, hari WIB) alih-alih membuat baris baru tiap kejadian.
// Jenis ini selalu in-app (tidak pernah push).
var patientDigestKinds = map[string]bool{
	"screening_reviewed":       true,
	"health_record_updated":    true,
	"professional_note_shared": true,
	// Berikut umumnya ditujukan ke profesional, tetapi didaftarkan agar perilaku
	// konsisten bila suatu saat dikirim ke pasien.
	"therapy_shared":     true,
	"credential_pending": true,
}

// pushAllowed menentukan apakah notifikasi `kind` untuk penerima ber-`role`
// boleh memicu push FCM. Role tak dikenal → tidak push (aman).
func pushAllowed(role, kind string) bool {
	switch role {
	case "patient":
		return patientPushKinds[kind]
	case "professional":
		return professionalPushKinds[kind]
	default:
		return false
	}
}

// isDigestKind menandai jenis notifikasi yang digabung menjadi digest harian.
func isDigestKind(kind string) bool {
	return patientDigestKinds[kind]
}

// sessionNotificationDeduped menandai jenis notifikasi sesi yang harus dibuat
// HANYA SEKALI per sesi per pengguna. Jenis ini (jadwal, pengingat, link siap)
// sering dipicu ulang oleh retry/duplikasi jalur (mis. sweeper + handler),
// sehingga tanpa penjaga entity-level baris notifikasi menumpuk dan pengguna
// melihat pesan yang sama berkali-kali. Pembatalan/reschedule TIDAK termasuk:
// peristiwa itu memang perlu memberi tahu perubahan status.
func sessionNotificationDeduped(kind string) bool {
	switch kind {
	case "session_scheduled", "session_reminder", "session_meet_ready":
		return true
	default:
		return false
	}
}

// digestBody menyusun teks body digest yang terbaca natural dalam Bahasa
// Indonesia untuk `count` pembaruan dari profesional bernama `professionalName`.
// Bila nama tidak diketahui, pemanggil mengoper "Profesional Anda".
func digestBody(kind string, count int, professionalName string) string {
	switch kind {
	case "screening_reviewed":
		return fmt.Sprintf("%d pembaruan screening dari %s.", count, professionalName)
	case "health_record_updated":
		return fmt.Sprintf("%d pembaruan Health Record dari %s.", count, professionalName)
	case "professional_note_shared":
		return fmt.Sprintf("%d catatan baru dari %s.", count, professionalName)
	case "therapy_shared":
		return fmt.Sprintf("%d pembaruan terapi dari %s.", count, professionalName)
	default:
		return fmt.Sprintf("%d pembaruan dari %s.", count, professionalName)
	}
}
