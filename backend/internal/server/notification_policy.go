package server

import "fmt"

// notification_policy.go menentukan kelayakan enqueue FCM untuk handler.
// Semua handler memakai notifyPatient/notifyUser. Dispatcher memeriksa ulang
// role, pasangan, dan sesi tersimpan melalui store.OutboxPushAllowed agar
// outbox dari versi lama tetap mengikuti kebijakan saat dikirim.
//
// Kebijakan push yang ditetapkan pemilik produk (final):
//   * PASIEN  — HANYA push untuk CHAT saat sesi aktif (`chat_message`).
//     Pengingat minum obat dan pengingat goals harian adalah notifikasi LOKAL
//     di perangkat (dijadwalkan Flutter), jadi backend TIDAK BOLEH mengirimnya
//     lewat FCM. Jenis sesi/pembayaran/krisis kini in-app saja (tanpa push).
//   * PROFESIONAL — HANYA push untuk CHAT (`chat_message`). Sisanya in-app.
//
// Default (kind tak dikenal) = TIDAK push (in-app saja). Ini konsisten dengan
// prinsip "kurangi kebisingan": jenis baru harus didaftarkan eksplisit bila
// memang layak push.

// patientPushKinds adalah jenis notifikasi yang boleh memicu push untuk pasien.
//
// HANYA chat. Pengingat obat & goals = notifikasi lokal perangkat (Flutter),
// TIDAK BOLEH pernah dikirim lewat FCM dari backend. Jenis sesi/pembayaran/
// krisis sengaja tidak didaftarkan (in-app saja).
var patientPushKinds = map[string]bool{
	"chat_message": true,
}

// professionalPushKinds adalah jenis notifikasi yang boleh memicu push untuk
// profesional: HANYA chat.
var professionalPushKinds = map[string]bool{
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
	case "session_scheduled", "session_reminder", "session_meet_ready",
		// `session_meet_missing` & `session_meet_update_failed` dipancarkan
		// ULANG setiap tick sweeper 10 menit; tanpa dedupe baris notifikasi
		// menumpuk. Cukup sekali per sesi.
		"session_meet_missing", "session_meet_update_failed":
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
