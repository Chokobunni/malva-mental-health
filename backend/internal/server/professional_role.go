package server

import "strings"

// professionalRole.go menyediakan klasifikasi peran profesional dari string
// spesialisasi kredensial. Cermin dari helper Dart
// lib/src/professional_role.dart agar aturan konsisten di server & klien.
//
// Aturan (uppercase):
//   - mengandung "KJ" / "PSIKIATER" / "PSIKIATRI"  -> Psikiater
//   - mengandung "PSI" / "PSIKOLOG"               -> Psikolog
//   - kosong / tak dikenal                         -> Profesional
//
// Contoh: "Sp.KJ" -> Psikiater, "M.Psi" -> Psikolog.

// isPsychiatristSpecialization true bila spesialisasi menandakan psikiater
// (satu-satunya peran yang boleh meresepkan obat).
func isPsychiatristSpecialization(specialization string) bool {
	s := strings.ToUpper(strings.TrimSpace(specialization))
	if s == "" {
		return false
	}
	return strings.Contains(s, "KJ") ||
		strings.Contains(s, "PSIKIATER") ||
		strings.Contains(s, "PSIKIATRI")
}
