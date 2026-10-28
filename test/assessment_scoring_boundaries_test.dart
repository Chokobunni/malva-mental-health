import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/ai/assessment_scoring.dart';

/// Uji ambang batas (cutoff) DASS-21 & WHO-5 secara parameterized.
///
/// Melengkapi `therapy_scoring_test.dart`: berkas ini mengunci SELURUH batas
/// rentang dari kontrak klinis (bukan hanya beberapa titik), sehingga
/// pergeseran ambang satu poin akan langsung merah.
void main() {
  group('dassLevel — ambang baku per subskala', () {
    // (subskala, skor, level yang diharapkan) — batas atas & bawah tiap rentang.
    const cases = <(String, int, String)>[
      // Depresi 0-9 / 10-13 / 14-20 / 21-27 / >=28
      ('depression', 0, 'Normal'),
      ('depression', 9, 'Normal'),
      ('depression', 10, 'Ringan'),
      ('depression', 13, 'Ringan'),
      ('depression', 14, 'Sedang'),
      ('depression', 20, 'Sedang'),
      ('depression', 21, 'Berat'),
      ('depression', 27, 'Berat'),
      ('depression', 28, 'Sangat berat'),
      ('depression', 42, 'Sangat berat'),
      // Kecemasan 0-7 / 8-9 / 10-14 / 15-19 / >=20
      ('anxiety', 0, 'Normal'),
      ('anxiety', 7, 'Normal'),
      ('anxiety', 8, 'Ringan'),
      ('anxiety', 9, 'Ringan'),
      ('anxiety', 10, 'Sedang'),
      ('anxiety', 14, 'Sedang'),
      ('anxiety', 15, 'Berat'),
      ('anxiety', 19, 'Berat'),
      ('anxiety', 20, 'Sangat berat'),
      ('anxiety', 42, 'Sangat berat'),
      // Stres 0-14 / 15-18 / 19-25 / 26-33 / >=34
      ('stress', 0, 'Normal'),
      ('stress', 14, 'Normal'),
      ('stress', 15, 'Ringan'),
      ('stress', 18, 'Ringan'),
      ('stress', 19, 'Sedang'),
      ('stress', 25, 'Sedang'),
      ('stress', 26, 'Berat'),
      ('stress', 33, 'Berat'),
      ('stress', 34, 'Sangat berat'),
      ('stress', 42, 'Sangat berat'),
    ];

    for (final (subscale, score, expected) in cases) {
      test('$subscale $score -> $expected', () {
        expect(dassLevel(subscale, score), expected);
      });
    }
  });

  group('pengelompokan item DASS-21', () {
    // Setiap item hanya boleh masuk SATU subskala, dan gabungannya = 21 item.
    test('gabungan tiga subskala menutup item 1..21 tanpa tumpang tindih', () {
      final all = <int>{
        ...dassDepressionItems,
        ...dassAnxietyItems,
        ...dassStressItems,
      };
      expect(all.length, 21);
      expect(
        dassDepressionItems.length +
            dassAnxietyItems.length +
            dassStressItems.length,
        21,
        reason: 'tidak boleh ada item yang masuk dua subskala',
      );
      expect(all, {for (var i = 1; i <= 21; i++) i});
    });

    test('satu jawaban hanya menambah subskala pemiliknya', () {
      Map<String, dynamic> only(int item, int value) => {
            for (var i = 1; i <= 21; i++) 'q$i': 0,
            'q$item': value,
            scaleVersionKey: standardizedScaleVersion,
          };

      for (final item in dassDepressionItems) {
        final s = scoreDass21(only(item, 3));
        expect(s.depression, 6, reason: 'q$item harus milik depresi');
        expect(s.anxiety, 0);
        expect(s.stress, 0);
      }
      for (final item in dassAnxietyItems) {
        final s = scoreDass21(only(item, 3));
        expect(s.anxiety, 6, reason: 'q$item harus milik kecemasan');
        expect(s.depression, 0);
        expect(s.stress, 0);
      }
      for (final item in dassStressItems) {
        final s = scoreDass21(only(item, 3));
        expect(s.stress, 6, reason: 'q$item harus milik stres');
        expect(s.depression, 0);
        expect(s.anxiety, 0);
      }
    });
  });

  group('skala baku vs data lama', () {
    test('penanda versi 2 membedakan arti nilai yang sama', () {
      final baru = scoreDass21({
        for (var i = 1; i <= 21; i++) 'q$i': 1,
        scaleVersionKey: standardizedScaleVersion,
      });
      // Skala baku: 7 x 1 x 2 = 14.
      expect(baru.depression, 14);

      final lama = scoreDass21({for (var i = 1; i <= 21; i++) 'q$i': 1});
      // Data lama tanpa penanda & tanpa 0: UI 1-3 -> (1-1) x 7 x 3 = 0.
      expect(lama.depression, 0);
    });

    test('nilai di luar rentang dijepit, bukan menghasilkan skor negatif', () {
      final s = scoreDass21({
        for (var i = 1; i <= 21; i++) 'q$i': 9,
        scaleVersionKey: standardizedScaleVersion,
      });
      expect(s.depression, 42); // dijepit ke 3
      final negatif = scoreDass21({
        for (var i = 1; i <= 21; i++) 'q$i': -5,
        scaleVersionKey: standardizedScaleVersion,
      });
      expect(negatif.depression, 0);
    });
  });

  group('Who5Score', () {
    test('level mengikuti ambang raw', () {
      expect(scoreWho5(_who5([0, 0, 0, 0, 0])).level, 'Sangat rendah');
      expect(scoreWho5(_who5([2, 2, 1, 1, 1])).level, 'Sangat rendah'); // 7
      expect(scoreWho5(_who5([2, 2, 2, 1, 1])).level, 'Rendah'); // 8
      expect(scoreWho5(_who5([5, 5, 2, 0, 0])).level, 'Rendah'); // 12
      expect(scoreWho5(_who5([3, 3, 3, 2, 2])).level, 'Cukup'); // 13
      expect(scoreWho5(_who5([4, 4, 4, 4, 3])).level, 'Cukup'); // 19
      expect(scoreWho5(_who5([4, 4, 4, 4, 4])).level, 'Baik'); // 20
      expect(scoreWho5(_who5([5, 5, 5, 5, 5])).level, 'Baik'); // 25
    });

    test('persen selalu raw x 4', () {
      for (final values in [
        [0, 0, 0, 0, 0],
        [1, 1, 1, 1, 1],
        [2, 3, 1, 4, 0],
        [5, 5, 5, 5, 5],
      ]) {
        final s = scoreWho5(_who5(values));
        expect(s.percent, s.raw * 4, reason: 'values=$values');
      }
    });
  });

  group('tabel rentang konsisten dengan fungsi level', () {
    test('setiap skor 0..42 jatuh di tepat satu baris DASS', () {
      for (final subscale in ['depression', 'anxiety', 'stress']) {
        final rows = dassRangesFor(subscale);
        for (var score = 0; score <= 42; score++) {
          final hits = rows.where((r) => r.contains(score)).length;
          expect(hits, 1, reason: '$subscale skor $score harus di 1 baris');
          expect(dassLevel(subscale, score),
              rows.firstWhere((r) => r.contains(score)).label);
        }
      }
    });

    test('setiap skor 0..25 jatuh di tepat satu baris WHO-5', () {
      for (var score = 0; score <= 25; score++) {
        final hits = who5Ranges.where((r) => r.contains(score)).length;
        expect(hits, 1, reason: 'WHO-5 skor $score harus di 1 baris');
      }
    });
  });
}

Map<String, dynamic> _who5(List<int> values) => {
      for (var i = 0; i < values.length; i++) 'q${i + 1}': values[i],
      scaleVersionKey: standardizedScaleVersion,
    };
