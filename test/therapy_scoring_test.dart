import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/widgets/therapy_library.dart';

/// Unit test skoring DASS-21 & WHO-5 (murni, tanpa widget/network).
/// Ditambahkan oleh QA (Edward) untuk menutup AC-1.5 / T03 yang sebelumnya
/// tidak punya cakupan test. Jalankan di CI/lokal: `flutter test`.

Map<String, dynamic> _dass({Map<int, int> overrides = const {}}) {
  final answers = <String, dynamic>{for (var i = 1; i <= 21; i++) 'q$i': 0};
  overrides.forEach((item, value) => answers['q$item'] = value);
  return answers;
}

Map<String, dynamic> _who5(List<int> values) => {
      for (var i = 0; i < values.length; i++) 'q${i + 1}': values[i],
    };

void main() {
  group('scoreDass21', () {
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

    test('dass21Summary memuat angka & level tiap subskala', () {
      final summary = dass21Summary(_dass());
      expect(summary, contains('Depresi 0 (Normal)'));
      expect(summary, contains('Kecemasan 0 (Normal)'));
      expect(summary, contains('Stres 0 (Normal)'));
    });
  });

  group('scoreWho5', () {
    test('semua 5 -> raw 25, 100%, kesejahteraan baik', () {
      final s = scoreWho5(_who5([5, 5, 5, 5, 5]));
      expect(s.raw, 25);
      expect(s.percent, 100);
      expect(s.lowWellbeing, isFalse);
      expect(s.possibleDepression, isFalse);
    });

    test('semua 1 (nilai terendah UI 1-5) -> raw 0, percent 0', () {
      final s = scoreWho5(_who5([1, 1, 1, 1, 1]));
      expect(s.raw, 0);
      expect(s.percent, 0);
      expect(s.possibleDepression, isTrue);
      expect(s.lowWellbeing, isTrue);
    });

    test('raw 12 -> lowWellbeing true tapi bukan possibleDepression', () {
      final s = scoreWho5(_who5([5, 5, 2, 0, 0]));
      expect(s.raw, 12);
      expect(s.percent, 48);
      expect(s.lowWellbeing, isTrue); // raw < 13
      expect(s.possibleDepression, isFalse); // raw > 7
    });

    test('who5Summary memuat skor dan kategori', () {
      expect(who5Summary(_who5([5, 5, 5, 5, 5])), contains('WHO-5 25/25'));
      expect(
          who5Summary(_who5([5, 5, 5, 5, 5])), contains('Kesejahteraan baik'));
      expect(
          who5Summary(_who5([1, 1, 1, 1, 1])), contains('screening lanjutan'));
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
