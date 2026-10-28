import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/theme.dart';
// therapy_library mengekspor ulang `ai/assessment_scoring.dart`, sehingga
// scoreDass21/scoreWho5/penanda versi skala tetap tersedia dari sini.
import 'package:malva_mental_health/src/widgets/therapy_library.dart';

/// Unit test skoring DASS-21 & WHO-5 (murni, tanpa widget/network).
///
/// Sejak skala instrumen dibakukan (DASS-21 0-3, WHO-5 0-5), submission baru
/// WAJIB membawa penanda `scale_version` = 2. Submission lama (UI 1-3 / 1-5)
/// tidak punya penanda dan tetap dihitung dengan rumus lama.

/// Jawaban DASS-21. [standardized] = true → data baru (0-3 + penanda versi).
Map<String, dynamic> _dass({
  Map<int, int> overrides = const {},
  bool standardized = true,
}) {
  final answers = <String, dynamic>{for (var i = 1; i <= 21; i++) 'q$i': 0};
  overrides.forEach((item, value) => answers['q$item'] = value);
  if (standardized) answers[scaleVersionKey] = standardizedScaleVersion;
  return answers;
}

/// Jawaban WHO-5 dari daftar nilai q1..q5.
Map<String, dynamic> _who5(List<int> values, {bool standardized = true}) {
  final answers = <String, dynamic>{
    for (var i = 0; i < values.length; i++) 'q${i + 1}': values[i],
  };
  if (standardized) answers[scaleVersionKey] = standardizedScaleVersion;
  return answers;
}

/// Isi item DASS-21 milik satu subskala dengan nilai tertentu.
Map<int, int> _items(Set<int> items, int value) =>
    {for (final item in items) item: value};

void main() {
  group('scoreDass21 — skala baku 0-3', () {
    test('semua 0 -> subskala 0 & level Normal', () {
      final s = scoreDass21(_dass());
      expect(s.depression, 0);
      expect(s.anxiety, 0);
      expect(s.stress, 0);
      expect(s.depressionLevel, 'Normal');
      expect(s.anxietyLevel, 'Normal');
      expect(s.stressLevel, 'Normal');
    });

    test('semua 3 -> tiap subskala 42 (7 item x 3 x 2), Sangat berat', () {
      final s = scoreDass21(_dass(
        overrides: {for (var i = 1; i <= 21; i++) i: 3},
      ));
      expect(s.depression, 42);
      expect(s.anxiety, 42);
      expect(s.stress, 42);
      expect(s.depressionLevel, 'Sangat berat');
      expect(s.anxietyLevel, 'Sangat berat');
      expect(s.stressLevel, 'Sangat berat');
    });

    test('item dikelompokkan per subskala (depresi = item 3,5,10,13,16,17,21)',
        () {
      // q3 + q5 = 3 + 2 = 5 -> depresi 10; subskala lain 0.
      final s = scoreDass21(_dass(overrides: {3: 3, 5: 2}));
      expect(s.depression, 10);
      expect(s.anxiety, 0);
      expect(s.stress, 0);
      expect(s.depressionLevel, 'Ringan'); // 10 <= 13
    });

    test('cutoff level berbeda per subskala (anx<=7 Normal, 8 Ringan)', () {
      // Anxiety item 2,4,7,9,15,19,20. q2+q4 = 3+1 = 4 -> anx 8 -> Ringan.
      final s = scoreDass21(_dass(overrides: {2: 3, 4: 1}));
      expect(s.anxiety, 8);
      expect(s.anxietyLevel, 'Ringan');
      // Stress item 1,6,8,... q1+q6 = 3+3 = 6 -> str 12 -> Normal (<=14).
      final s2 = scoreDass21(_dass(overrides: {1: 3, 6: 3}));
      expect(s2.stress, 12);
      expect(s2.stressLevel, 'Normal');
    });

    test('ambang tiap subskala di batas atas & bawah', () {
      // Depresi: 10 Ringan, 14 Sedang, 21 Berat, 28 Sangat berat.
      expect(scoreDass21(_dass(overrides: {3: 3, 5: 2})).depression, 10);
      expect(scoreDass21(_dass(overrides: {3: 3, 5: 3, 10: 1})).depressionLevel,
          'Sedang'); // 14
      expect(
          scoreDass21(_dass(
            overrides: {3: 3, 5: 3, 10: 3, 13: 1, 16: 1},
          )).depressionLevel,
          'Berat'); // 22
      expect(
          scoreDass21(_dass(overrides: _items(dassDepressionItems, 2)))
              .depressionLevel,
          'Sangat berat'); // 28
      // Kecemasan: 8 Ringan, 10 Sedang, 16 Berat, 20 Sangat berat.
      expect(scoreDass21(_dass(overrides: {2: 3, 4: 1})).anxiety, 8);
      expect(scoreDass21(_dass(overrides: {2: 3, 4: 2})).anxiety, 10);
      expect(scoreDass21(_dass(overrides: {2: 3, 4: 3, 7: 2})).anxiety, 16);
      expect(
          scoreDass21(_dass(overrides: {2: 3, 4: 3, 7: 2, 9: 2})).anxiety, 20);
      // Stres: 16 Ringan, 20 Sedang, 28 Berat, 34 Sangat berat.
      expect(scoreDass21(_dass(overrides: {1: 3, 6: 3, 8: 2})).stress, 16);
      expect(
          scoreDass21(_dass(overrides: {1: 3, 6: 3, 8: 3, 11: 1})).stress, 20);
      expect(
          scoreDass21(_dass(overrides: _items(dassStressItems, 2))).stress, 28);
      expect(
          scoreDass21(_dass(overrides: {
            1: 3,
            6: 3,
            8: 3,
            11: 3,
            12: 3,
            14: 2,
          })).stressLevel,
          'Sangat berat'); // 34 -> >=34
    });

    test('dass21Summary memuat angka & level tiap subskala', () {
      final summary = dass21Summary(_dass());
      expect(summary, contains('Depresi 0 (Normal)'));
      expect(summary, contains('Kecemasan 0 (Normal)'));
      expect(summary, contains('Stres 0 (Normal)'));
    });
  });

  group('scoreDass21 — kompatibilitas data lama (tanpa penanda versi)', () {
    test('nilai 1-3 memakai rumus lama (raw-1) x3', () {
      // Semua 2 pada data lama -> tiap item bernilai 1 -> 7 x 1 x 3 = 21.
      final legacy = scoreDass21(_dass(
        standardized: false,
        overrides: {for (var i = 1; i <= 21; i++) i: 2},
      ));
      expect(legacy.depression, 21);
      expect(legacy.depressionLevel, 'Berat');
    });

    test('nilai yang sama pada data BARU menghasilkan skor berbeda', () {
      // Skala baku: semua 2 -> 7 x 2 x 2 = 28 (Sangat berat), bukan 21.
      final standardized = scoreDass21(_dass(
        overrides: {for (var i = 1; i <= 21; i++) i: 2},
      ));
      expect(standardized.depression, 28);
      expect(standardized.depressionLevel, 'Sangat berat');
    });

    test('semua 3 pada data lama tetap 42 (rumus lama x3)', () {
      final legacy = scoreDass21(_dass(
        standardized: false,
        overrides: {for (var i = 1; i <= 21; i++) i: 3},
      ));
      expect(legacy.depression, 42);
      expect(legacy.anxiety, 42);
      expect(legacy.stress, 42);
    });

    test('data lama yang mengandung 0 tetap dibaca sebagai skala 0-3', () {
      final legacy = scoreDass21(_dass(standardized: false, overrides: {3: 3}));
      expect(legacy.depression, 6); // 3 x 2
      expect(legacy.depressionLevel, 'Normal');
    });
  });

  group('scoreWho5 — skala baku 0-5', () {
    test('semua 5 -> raw 25, 100%, kesejahteraan baik', () {
      final s = scoreWho5(_who5([5, 5, 5, 5, 5]));
      expect(s.raw, 25);
      expect(s.percent, 100);
      expect(s.lowWellbeing, isFalse);
      expect(s.possibleDepression, isFalse);
      expect(s.level, 'Baik');
    });

    test('semua 0 -> raw 0, percent 0, kemungkinan depresi', () {
      final s = scoreWho5(_who5([0, 0, 0, 0, 0]));
      expect(s.raw, 0);
      expect(s.percent, 0);
      expect(s.possibleDepression, isTrue);
      expect(s.lowWellbeing, isTrue);
      expect(s.level, 'Sangat rendah');
    });

    test('raw 12 -> lowWellbeing true tapi bukan possibleDepression', () {
      final s = scoreWho5(_who5([5, 5, 2, 0, 0]));
      expect(s.raw, 12);
      expect(s.percent, 48);
      expect(s.lowWellbeing, isTrue); // raw <= 12 (<= 50%)
      expect(s.possibleDepression, isFalse); // raw > 7
      expect(s.level, 'Rendah');
    });

    test('batas possibleDepression: raw 7 ya, raw 8 tidak', () {
      expect(scoreWho5(_who5([2, 2, 1, 1, 1])).raw, 7);
      expect(scoreWho5(_who5([2, 2, 1, 1, 1])).possibleDepression, isTrue);
      expect(scoreWho5(_who5([2, 2, 2, 1, 1])).raw, 8);
      expect(scoreWho5(_who5([2, 2, 2, 1, 1])).possibleDepression, isFalse);
    });

    test('who5Summary memuat skor dan kategori', () {
      expect(who5Summary(_who5([5, 5, 5, 5, 5])), contains('WHO-5 25/25'));
      expect(
          who5Summary(_who5([5, 5, 5, 5, 5])), contains('Kesejahteraan baik'));
      expect(
          who5Summary(_who5([0, 0, 0, 0, 0])), contains('screening lanjutan'));
    });
  });

  group('scoreWho5 — kompatibilitas data lama (tanpa penanda versi)', () {
    test('nilai 1-5 dikonversi ke 0-4 lalu diskalakan 0-25', () {
      // Semua 1 -> total 0 -> raw 0, 0%.
      final lowest = scoreWho5(_who5([1, 1, 1, 1, 1], standardized: false));
      expect(lowest.raw, 0);
      expect(lowest.percent, 0);
      // Semua 5 -> total 20 -> raw 25, 100%.
      final highest = scoreWho5(_who5([5, 5, 5, 5, 5], standardized: false));
      expect(highest.raw, 25);
      expect(highest.percent, 100);
    });

    test('data lama yang mengandung 0 tetap dibaca sebagai skala 0-5', () {
      final s = scoreWho5(_who5([5, 5, 2, 0, 0], standardized: false));
      expect(s.raw, 12);
      expect(s.percent, 48);
    });
  });

  group('assessmentSummary', () {
    test('memilih ringkasan sesuai modul', () {
      expect(assessmentSummary('dass21', _dass()), contains('Depresi 0'));
      expect(assessmentSummary('who5', _who5([5, 5, 5, 5, 5])),
          contains('WHO-5 25/25'));
      expect(assessmentSummary('abcde', const {}), isEmpty);
    });
  });

  group('severityColor', () {
    test('memetakan level ke warna palet Malva', () {
      expect(severityColor('normal'), MalvaColors.mint);
      expect(severityColor('ringan'), MalvaColors.mint);
      expect(severityColor('sedang'), MalvaColors.amber);
      expect(severityColor('berat'), MalvaColors.danger);
      expect(severityColor('sangat berat'), MalvaColors.danger);
    });

    test('case-insensitive & fallback seed untuk level tak dikenal', () {
      expect(severityColor('BERAT'), MalvaColors.danger);
      expect(severityColor('Sangat Berat'), MalvaColors.danger);
      expect(severityColor('tidak-dikenal'), MalvaColors.seed);
    });
  });
}
