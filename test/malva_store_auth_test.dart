import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/store/malva_store.dart';

void main() {
  group('MalvaStore auth', () {
    test('logs in seeded patient with email and password', () {
      final store = MalvaStore.seeded();

      final session =
          store.loginPatient(email: 'pasien@malva.app', password: 'Malva1234');

      expect(session.role, UserRole.patient);
      expect(session.identifier, 'pasien@malva.app');
    });

    test('rejects unknown patient email and wrong password', () {
      final store = MalvaStore.seeded();

      expect(
        () =>
            store.loginPatient(email: 'wrong@malva.app', password: 'Malva1234'),
        throwsA(isA<AuthFailure>()),
      );
      expect(
        () => store.loginPatient(
            email: 'pasien@malva.app', password: 'wrongpass'),
        throwsA(isA<AuthFailure>()),
      );
    });

    test('requires professional id to contain exactly 16 digits', () {
      final store = MalvaStore.seeded();

      expect(
        () => store.loginProfessional(
            professionalId: '12345', password: 'Dokter1234'),
        throwsA(isA<AuthFailure>()),
      );
      expect(
        () => store.loginProfessional(
            professionalId: '1234567890123456', password: 'Dokter1234'),
        returnsNormally,
      );
    });
  });
}
