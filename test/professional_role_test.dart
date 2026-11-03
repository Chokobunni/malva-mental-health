import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/professional_role.dart';

// ============================================================
// LABEL PERAN PROFESIONAL & ATURAN PSIKIATER
//
// Satu sumber kebenaran untuk label Psikiater/Psikolog dan untuk menentukan
// siapa yang boleh meresepkan obat (hanya Psikiater / Sp.KJ). Aturan harus
// konsisten dengan helper Go `isPsychiatristSpecialization` di backend.
// ============================================================

void main() {
  test('professionalRoleLabel memetakan spesialisasi ke label peran', () {
    expect(professionalRoleLabel('Sp.KJ'), 'Psikiater');
    expect(professionalRoleLabel('sp.kj'), 'Psikiater');
    expect(professionalRoleLabel('Psikiater'), 'Psikiater');
    expect(professionalRoleLabel('Psikiatri'), 'Psikiater');

    expect(professionalRoleLabel('M.Psi'), 'Psikolog');
    expect(professionalRoleLabel('S.Psi., M.Psi'), 'Psikolog');
    expect(professionalRoleLabel('Psikolog Klinis'), 'Psikolog');

    expect(professionalRoleLabel(''), 'Profesional');
    expect(professionalRoleLabel('   '), 'Profesional');
    expect(professionalRoleLabel('Dokter Umum'), 'Profesional');
  });

  test('isPsychiatristSpecialization hanya true untuk Psikiater', () {
    expect(isPsychiatristSpecialization('Sp.KJ'), isTrue);
    expect(isPsychiatristSpecialization('sp.kj'), isTrue);
    expect(isPsychiatristSpecialization('SP.KJ'), isTrue);
    expect(isPsychiatristSpecialization('Psikiater'), isTrue);

    expect(isPsychiatristSpecialization('M.Psi'), isFalse);
    expect(isPsychiatristSpecialization('Psikolog Klinis'), isFalse);
    expect(isPsychiatristSpecialization(''), isFalse);
    expect(isPsychiatristSpecialization('Dokter Umum'), isFalse);
  });
}
