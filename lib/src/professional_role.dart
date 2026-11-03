/// Klasifikasi peran profesional dari string spesialisasi kredensial.
///
/// Satu sumber kebenaran untuk label Psikiater/Psikolog dan untuk menentukan
/// siapa yang boleh meresepkan obat (hanya Psikiater). Cermin dari helper Go
/// `isPsychiatristSpecialization` di backend agar aturan server & klien sama.
///
/// Aturan (dinormalisasi ke huruf besar):
///   - mengandung "KJ" / "PSIKIATER" / "PSIKIATRI"  -> Psikiater
///   - mengandung "PSI" / "PSIKOLOG"               -> Psikolog
///   - kosong / tak dikenal                         -> Profesional
///
/// Contoh: "Sp.KJ" -> Psikiater, "M.Psi" -> Psikolog, "S.Psi., M.Psi" -> Psikolog.
library;

/// Label peran yang ramah dibaca dari sebuah spesialisasi.
String professionalRoleLabel(String specialization) {
  final s = specialization.toUpperCase().trim();
  if (s.isEmpty) return 'Profesional';
  if (_isPsychiatrist(s)) return 'Psikiater';
  if (_isPsychologist(s)) return 'Psikolog';
  return 'Profesional';
}

/// True bila spesialisasi menandakan Psikiater (Sp.KJ) — satu-satunya peran
/// yang boleh meresepkan obat.
bool isPsychiatristSpecialization(String specialization) {
  final s = specialization.toUpperCase().trim();
  if (s.isEmpty) return false;
  return _isPsychiatrist(s);
}

bool _isPsychiatrist(String upper) =>
    upper.contains('KJ') ||
    upper.contains('PSIKIATER') ||
    upper.contains('PSIKIATRI');

bool _isPsychologist(String upper) =>
    upper.contains('PSI') || upper.contains('PSIKOLOG');
