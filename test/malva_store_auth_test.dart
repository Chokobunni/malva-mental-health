import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';

void main() {
  group('MalvaStore auth', () {
    test('auth selalu melalui server (online), bukan sesi lokal dummy', () {
      final container = ProviderContainer();
      final store = container.read(malvaStoreProvider.notifier);

      // Tanpa server: login pasien ditolak (tidak ada sesi palsu).
      expect(
        () => store.loginPatientOnline(
            email: 'pasien@malva.app', password: 'Malva1234'),
        throwsA(isA<AuthFailure>()),
      );
      // Registrasi pasien pun butuh server.
      expect(
        () => store.registerPatientOnline(
            email: 'baru@malva.app',
            password: 'Malva1234!',
            displayName: 'Pasien Baru'),
        throwsA(isA<AuthFailure>()),
      );
      // Login profesional via STR/SIP juga butuh server.
      expect(
        () => store.loginProfessionalOnline(
            professionalId: 'STR-123', password: 'Dokter12345'),
        throwsA(isA<AuthFailure>()),
      );
    });
  });
}
