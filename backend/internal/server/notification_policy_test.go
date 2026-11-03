package server

import (
	"testing"
)

// ============================================================
// QA — unit test MURNI untuk kebijakan notifikasi (notification_policy.go).
// Tidak butuh database: menguji langsung fungsi policy yang dipakai
// notifyUser untuk memutuskan push FCM.
//
// Kebijakan final: pasien & profesional HANYA push untuk CHAT (`chat_message`).
// Pengingat obat & goals = notifikasi lokal perangkat (Flutter) → TIDAK pernah
// lewat FCM. Jenis sesi/pembayaran/krisis = in-app saja.
// ============================================================

// TestPushAllowedPatientChatOnly — pasien HANYA di-push untuk chat. Jenis sesi,
// pembayaran, obat, dan krisis TIDAK boleh memicu push lagi.
func TestPushAllowedPatientChatOnly(t *testing.T) {
	if !pushAllowed("patient", "chat_message") {
		t.Fatal("pasien kind chat_message seharusnya push")
	}
	notPush := []string{
		"session_scheduled",
		"session_reminder",
		"session_meet_ready",
		"session_meet_missing",
		"session_meet_update_failed",
		"session_cancelled_professional",
		"package_activated",
		"payment_needs_reconciliation",
		"medication_prescribed",
		"prescription_created",
		// Pengingat obat = notifikasi LOKAL perangkat, bukan FCM.
		"medication_reminder",
		"crisis_alert",
		"screening_reviewed",
	}
	for _, kind := range notPush {
		if pushAllowed("patient", kind) {
			t.Errorf("pasien kind %q TIDAK boleh push (in-app saja / lokal perangkat)", kind)
		}
	}
}

// TestPushAllowedProfessionalChatOnly — profesional HANYA di-push untuk chat;
// peristiwa sesi pun tidak lagi memicu push.
func TestPushAllowedProfessionalChatOnly(t *testing.T) {
	if !pushAllowed("professional", "chat_message") {
		t.Fatal("profesional kind chat_message seharusnya push")
	}
	notPush := []string{
		"session_scheduled",
		"session_rescheduled",
		"session_cancelled_patient",
		"session_cancelled_professional",
		"session_reminder",
		"session_meet_ready",
		"session_meet_missing",
		"session_meet_update_failed",
		"session_needs_reschedule",
		"crisis_alert",
		"screening_reviewed",
		"payment_needs_reconciliation",
		"package_activated",
		"credential_pending",
		"medication_prescribed",
	}
	for _, kind := range notPush {
		if pushAllowed("professional", kind) {
			t.Errorf("profesional kind %q TIDAK boleh push (hanya chat)", kind)
		}
	}
}

// TestPushKindsHanyaChat memeriksa isi map secara langsung: masing-masing hanya
// berisi satu entri `chat_message`.
func TestPushKindsHanyaChat(t *testing.T) {
	for name, m := range map[string]map[string]bool{
		"patientPushKinds":      patientPushKinds,
		"professionalPushKinds": professionalPushKinds,
	} {
		if len(m) != 1 || !m["chat_message"] {
			t.Errorf("%s harus hanya berisi chat_message, dapat %v", name, m)
		}
	}
}

// TestPushAllowedPatientLowPriorityTidakPush menegaskan jenis low-priority
// (review screening, health record, catatan, terapi, kredensial) TIDAK push dan
// digabung menjadi digest harian.
func TestPushAllowedPatientLowPriorityTidakPush(t *testing.T) {
	lowPriority := []string{
		"screening_reviewed",
		"health_record_updated",
		"professional_note_shared",
		"therapy_shared",
		"credential_pending",
	}
	for _, kind := range lowPriority {
		if pushAllowed("patient", kind) {
			t.Errorf("pasien kind %q seharusnya TIDAK push (harus digest in-app)", kind)
		}
		if !isDigestKind(kind) {
			t.Errorf("kind %q seharusnya terdaftar sebagai digest", kind)
		}
	}
}

// TestPushAllowedRoleTakDikenalTidakPush: role kosong/asing -> aman (tidak push).
func TestPushAllowedRoleTakDikenalTidakPush(t *testing.T) {
	for _, role := range []string{"", "admin", "unknown"} {
		if pushAllowed(role, "chat_message") {
			t.Errorf("role %q seharusnya tidak push", role)
		}
		if pushAllowed(role, "session_scheduled") {
			t.Errorf("role %q seharusnya tidak push", role)
		}
	}
}

// TestDigestBodyFormat memastikan teks digest terbaca natural & memuat jumlah.
func TestDigestBodyFormat(t *testing.T) {
	cases := []struct {
		kind  string
		count int
		name  string
		want  string
	}{
		{"screening_reviewed", 2, "Rina Prasetyo, M.Psi", "2 pembaruan screening dari Rina Prasetyo, M.Psi."},
		{"health_record_updated", 3, "Prof X", "3 pembaruan Health Record dari Prof X."},
		{"professional_note_shared", 1, "Prof Y", "1 catatan baru dari Prof Y."},
		{"therapy_shared", 4, "Prof Z", "4 pembaruan terapi dari Prof Z."},
		// Kind tak dikenal -> fallback generik yang tetap memuat jumlah & nama.
		{"lain_lain", 5, "Prof W", "5 pembaruan dari Prof W."},
	}
	for _, c := range cases {
		if got := digestBody(c.kind, c.count, c.name); got != c.want {
			t.Errorf("digestBody(%q,%d,%q) = %q, mau %q", c.kind, c.count, c.name, got, c.want)
		}
	}
}

// TestSessionNotificationDeduped — jadwal/pengingat/link-siap/link-hilang/
// link-gagal hanya dibuat sekali per sesi. Pembatalan/reschedule & jenis lain
// TIDAK deduped.
func TestSessionNotificationDeduped(t *testing.T) {
	deduped := []string{
		"session_scheduled",
		"session_reminder",
		"session_meet_ready",
		"session_meet_missing",
		"session_meet_update_failed",
	}
	for _, kind := range deduped {
		if !sessionNotificationDeduped(kind) {
			t.Errorf("kind %q seharusnya deduped (sekali per sesi)", kind)
		}
	}
	notDeduped := []string{
		"session_rescheduled",
		"session_cancelled_patient",
		"session_cancelled_professional",
		"session_needs_reschedule",
		"crisis_alert",
		"screening_reviewed",
		"chat_message",
		"",
	}
	for _, kind := range notDeduped {
		if sessionNotificationDeduped(kind) {
			t.Errorf("kind %q TIDAK boleh deduped", kind)
		}
	}
}
