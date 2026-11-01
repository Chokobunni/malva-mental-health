package server

import (
	"strings"
	"testing"
)

// ============================================================
// QA — unit test MURNI untuk kebijakan notifikasi (notification_policy.go).
// Tidak butuh database: menguji langsung fungsi policy yang dipakai
// notifyUser untuk memutuskan push FCM vs digest in-app.
//
//   W1 — jenis low-priority digabung menjadi digest (in-app saja, tanpa push).
//   W7 — push profesional HANYA untuk sesi & chat.
// ============================================================

// TestPushAllowedPatientLowPriorityTidakPush menegaskan bahwa jenis
// low-priority (review screening, health record, catatan, terapi, kredensial)
// TIDAK boleh memicu push untuk pasien — inilah prasyarat W1: bila tidak push,
// notifyUser menggabungkannya ke digest harian.
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
		// Setiap jenis low-priority wajib ditandai sebagai digest.
		if !isDigestKind(kind) {
			t.Errorf("kind %q seharusnya terdaftar sebagai digest", kind)
		}
	}
}

// TestPushAllowedPatientPentingPush memastikan peristiwa penting pasien
// (sesi, pembayaran, obat, krisis) tetap memicu push — dan BUKAN digest.
func TestPushAllowedPatientPentingPush(t *testing.T) {
	penting := []string{
		"session_meet_ready",
		"session_scheduled",
		"session_reminder",
		"package_activated",
		"payment_needs_reconciliation",
		"medication_prescribed",
		"crisis_alert",
	}
	for _, kind := range penting {
		if !pushAllowed("patient", kind) {
			t.Errorf("pasien kind %q seharusnya push", kind)
		}
		if isDigestKind(kind) {
			t.Errorf("kind %q TIDAK boleh jadi digest (harus push)", kind)
		}
	}
}

// TestPushAllowedProfessionalHanyaSesiDanChat — inti W7: profesional hanya
// di-push untuk peristiwa sesi & chat. Krisis, screening, pembayaran, dan
// kredensial TIDAK boleh memicu push ke profesional.
func TestPushAllowedProfessionalHanyaSesiDanChat(t *testing.T) {
	bolehPush := []string{
		"session_scheduled",
		"session_rescheduled",
		"session_cancelled_patient",
		"session_cancelled_professional",
		"session_reminder",
		"session_meet_ready",
		"session_meet_missing",
		"session_meet_update_failed",
		"session_needs_reschedule",
		"chat_message",
	}
	for _, kind := range bolehPush {
		if !pushAllowed("professional", kind) {
			t.Errorf("profesional kind %q seharusnya push (sesi/chat)", kind)
		}
	}

	// Jenis NON-sesi/chat yang dulu mengganggu profesional — wajib TIDAK push.
	tidakBolehPush := []string{
		"crisis_alert",
		"screening_reviewed",
		"screening_crisis",
		"payment_needs_reconciliation",
		"package_activated",
		"credential_pending",
		"medication_prescribed",
		"professional_note_shared",
		"health_record_updated",
		"therapy_shared",
	}
	for _, kind := range tidakBolehPush {
		if pushAllowed("professional", kind) {
			t.Errorf("profesional kind %q TIDAK boleh push (bukan sesi/chat)", kind)
		}
	}
}

// TestProfessionalPushKindsHanyaSesiChat memeriksa isi map secara langsung:
// setiap entri harus berawalan "session_" atau bernilai "chat_message".
func TestProfessionalPushKindsHanyaSesiChat(t *testing.T) {
	if len(professionalPushKinds) == 0 {
		t.Fatal("professionalPushKinds kosong")
	}
	for kind, allowed := range professionalPushKinds {
		if !allowed {
			continue
		}
		if kind != "chat_message" && !strings.HasPrefix(kind, "session_") {
			t.Errorf("professionalPushKinds memuat %q yang bukan sesi/chat", kind)
		}
	}
}

// TestPushAllowedRoleTakDikenalTidakPush: role kosong/asing -> aman (tidak push).
func TestPushAllowedRoleTakDikenalTidakPush(t *testing.T) {
	for _, role := range []string{"", "admin", "unknown"} {
		if pushAllowed(role, "session_scheduled") {
			t.Errorf("role %q seharusnya tidak push", role)
		}
		if pushAllowed(role, "crisis_alert") {
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
