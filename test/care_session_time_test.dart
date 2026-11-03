import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/services/care_session_time.dart';

// ============================================================
// Uji batas jendela "sesi berjalan" (fungsi murni).
//
// Aturan: scheduledAt - 10 menit <= now <= scheduledAt + durasi (TEPAT saat
// durasi habis, tanpa kelonggaran +30). Batas inklusif di kedua ujung. Kasus:
// sebelum jendela, tepat di start-10, di dalam, tepat di akhir, setelah jendela.
// ============================================================

void main() {
  // Sesi 09:00, durasi 50 menit -> berakhir 09:50.
  // Jendela: 08:50 .. 09:50 (tepat saat durasi habis).
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

    test('tepat saat durasi habis (09:50) -> true (batas inklusif)', () {
      expect(ongoing(DateTime(2026, 10, 22, 9, 50)), isTrue);
    });

    test('satu menit setelah durasi habis (09:51) -> false', () {
      expect(ongoing(DateTime(2026, 10, 22, 9, 51)), isFalse);
    });

    test('setelah jendela (10:20) -> false (tak ada lagi +30)', () {
      expect(ongoing(DateTime(2026, 10, 22, 10, 20)), isFalse);
    });
  });

  group('isCareSessionOngoing — kasus tepi lain', () {
    test('tepat di jadwal (09:00) -> true', () {
      expect(ongoing(DateTime(2026, 10, 22, 9, 0)), isTrue);
    });

    test('durasi 0: jendela 08:50 .. 09:00 (tutup tepat di jadwal)', () {
      expect(
        isCareSessionOngoing(DateTime(2026, 10, 22, 9, 0), scheduledAt, 0),
        isTrue,
      );
      expect(
        isCareSessionOngoing(DateTime(2026, 10, 22, 9, 1), scheduledAt, 0),
        isFalse,
      );
    });

    test('durasi negatif diperlakukan sebagai 0', () {
      expect(
        isCareSessionOngoing(DateTime(2026, 10, 22, 9, 0), scheduledAt, -15),
        isTrue,
      );
      expect(
        isCareSessionOngoing(DateTime(2026, 10, 22, 9, 1), scheduledAt, -15),
        isFalse,
      );
    });

    test('hari berbeda (kemarin) -> false', () {
      expect(ongoing(DateTime(2026, 10, 21, 9, 0)), isFalse);
    });
  });
}
