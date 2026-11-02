import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/services/care_session_time.dart';

// ============================================================
// Uji batas jendela "sesi berjalan" (fungsi murni).
//
// Aturan: scheduledAt - 10 menit <= now <= scheduledAt + durasi + 30 menit.
// Batas inklusif di kedua ujung. Kasus: sebelum jendela, tepat di
// start-10, di dalam, tepat di akhir, setelah jendela.
// ============================================================

void main() {
  // Sesi 09:00, durasi 50 menit -> berakhir 09:50.
  // Jendela: 08:50 .. 10:20 (09:50 + 30 menit).
  final scheduledAt = DateTime(2026, 10, 22, 9, 0);
  const durationMinutes = 50;

  bool ongoing(DateTime now) =>
      isCareSessionOngoing(now, scheduledAt, durationMinutes);

  group('isCareSessionOngoing — batas jendela', () {
    test('sebelum jendela (08:49) -> false', () {
      expect(ongoing(DateTime(2026, 10, 22, 8, 49)), isFalse);
    });

    test('tepat di start-10 (08:50) -> true (batas inklusif)', () {
      expect(ongoing(DateTime(2026, 10, 22, 8, 50)), isTrue);
    });

    test('di dalam jendela (09:25) -> true', () {
      expect(ongoing(DateTime(2026, 10, 22, 9, 25)), isTrue);
    });

    test('tepat di akhir jendela (10:20) -> true (batas inklusif)', () {
      expect(ongoing(DateTime(2026, 10, 22, 10, 20)), isTrue);
    });

    test('setelah jendela (10:21) -> false', () {
      expect(ongoing(DateTime(2026, 10, 22, 10, 21)), isFalse);
    });
  });

  group('isCareSessionOngoing — kasus tepi lain', () {
    test('tepat di jadwal (09:00) -> true', () {
      expect(ongoing(DateTime(2026, 10, 22, 9, 0)), isTrue);
    });

    test('durasi 0: jendela 08:50 .. 09:30', () {
      expect(
        isCareSessionOngoing(
            DateTime(2026, 10, 22, 9, 30), scheduledAt, 0),
        isTrue,
      );
      expect(
        isCareSessionOngoing(
            DateTime(2026, 10, 22, 9, 31), scheduledAt, 0),
        isFalse,
      );
    });

    test('durasi negatif diperlakukan sebagai 0', () {
      expect(
        isCareSessionOngoing(
            DateTime(2026, 10, 22, 9, 30), scheduledAt, -15),
        isTrue,
      );
      expect(
        isCareSessionOngoing(
            DateTime(2026, 10, 22, 9, 31), scheduledAt, -15),
        isFalse,
      );
    });

    test('hari berbeda (kemarin) -> false', () {
      expect(ongoing(DateTime(2026, 10, 21, 9, 0)), isFalse);
    });
  });
}
