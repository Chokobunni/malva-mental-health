import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/ai/assessment_interpretation.dart';
import 'package:malva_mental_health/src/ai/assessment_scoring.dart';

/// Unit test lapisan interpretasi pakar (forward chaining + Certainty Factor).
///
/// Yang diuji HANYA keyakinan triage. Skor instrumen sendiri tetap
/// deterministik dan diuji di `therapy_scoring_test.dart`.

Map<String, dynamic> _dass({
  Map<int, int> overrides = const {},
}) {
  final answers = <String, dynamic>{
    for (var i = 1; i <= 21; i++) 'q$i': 0,
    scaleVersionKey: standardizedScaleVersion,
  };
  overrides.forEach((item, value) => answers['q$item'] = value);
  return answers;
}

Map<String, dynamic> _who5(List<int> values) => {
      for (var i = 0; i < values.length; i++) 'q${i + 1}': values[i],
      scaleVersionKey: standardizedScaleVersion,
    };

Map<int, int> _items(Set<int> items, int value) =>
    {for (final item in items) item: value};

void main() {
  group('interpretDassWho5 — DASS-21', () {
    test('depresi sangat berat -> triage tinggi', () {
      final result = interpretDassWho5(
        answers: _dass(overrides: _items(dassDepressionItems, 3)),
        moduleId: 'dass21',
      );
      expect(result.triageLevel, 'tinggi');
      expect(result.certaintyFactor, greaterThan(0.8));
      expect(result.reasons, isNotEmpty);
      expect(result.ruleVersion, assessmentRuleVersion);
    });

    test('semua subskala sangat berat -> triage krisis', () {
      final result = interpretDassWho5(
        answers: _dass(overrides: {
          for (var i = 1; i <= 21; i++) i: 3,
        }),
        moduleId: 'dass21',
      );
      expect(result.triageLevel, 'krisis');
      expect(result.certaintyFactor, greaterThanOrEqualTo(0.9));
    });

    test('semua jawaban 0 -> triage rendah', () {
      final result = interpretDassWho5(answers: _dass(), moduleId: 'dass21');
      expect(result.triageLevel, 'rendah');
      expect(result.certaintyFactor, closeTo(0.40, 0.0001));
      expect(result.reasons, isNotEmpty);
    });

    test('depresi sedang -> triage sedang', () {
      // Depresi 14 (Sedang): q3 + q5 + q10 = 3 + 3 + 1 = 7 -> 14.
      final result = interpretDassWho5(
        answers: _dass(overrides: {3: 3, 5: 3, 10: 1}),
        moduleId: 'dass21',
      );
      expect(scoreDass21(_dass(overrides: {3: 3, 5: 3, 10: 1})).depressionLevel,
          'Sedang');
      expect(result.triageLevel, 'sedang');
    });

    test('CF naik saat bukti bertambah (depresi + kecemasan berat)', () {
      final depresiSaja = interpretDassWho5(
        answers: _dass(overrides: _items(dassDepressionItems, 3)),
        moduleId: 'dass21',
      );
      // Depresi Sangat berat (42) + kecemasan Berat (16).
      final duaBukti = interpretDassWho5(
        answers: _dass(overrides: {
          ..._items(dassDepressionItems, 3),
          2: 3,
          4: 3,
          7: 2,
        }),
        moduleId: 'dass21',
      );
      expect(
          scoreDass21(_dass(overrides: {
            ..._items(dassDepressionItems, 3),
            2: 3,
            4: 3,
            7: 2,
          })).anxietyLevel,
          'Berat');
      expect(duaBukti.triageLevel, 'tinggi');
      expect(
        duaBukti.certaintyFactor,
        greaterThan(depresiSaja.certaintyFactor),
      );
      expect(duaBukti.reasons.length, greaterThanOrEqualTo(2));
    });
  });

  group('interpretDassWho5 — WHO-5', () {
    test('kesejahteraan rendah saja -> triage sedang', () {
      // 12/25 = 48% -> di bawah 50% tetapi di atas 28%.
      final result =
          interpretDassWho5(answers: _who5([5, 5, 2, 0, 0]), moduleId: 'who5');
      expect(scoreWho5(_who5([5, 5, 2, 0, 0])).percent, 48);
      expect(result.triageLevel, 'sedang');
    });

    test('kesejahteraan sangat rendah (<= 28%) -> triage tinggi', () {
      final result =
          interpretDassWho5(answers: _who5([1, 1, 1, 0, 0]), moduleId: 'who5');
      expect(scoreWho5(_who5([1, 1, 1, 0, 0])).percent, 12);
      expect(result.triageLevel, 'tinggi');
    });

    test('kesejahteraan baik -> triage rendah', () {
      final result =
          interpretDassWho5(answers: _who5([5, 5, 5, 5, 5]), moduleId: 'who5');
      expect(result.triageLevel, 'rendah');
    });
  });

  group('AssessmentInterpretation', () {
    test('label & persen keyakinan siap tampil', () {
      final result = interpretDassWho5(
        answers: _dass(overrides: _items(dassDepressionItems, 3)),
        moduleId: 'dass21',
      );
      expect(result.triageLabel, 'Tinggi');
      expect(result.certaintyPercent, inInclusiveRange(80, 100));
      expect(result.summaryLine, contains('Interpretasi triage: Tinggi'));
      expect(result.summaryLine, contains('CF '));
    });

    test('modul non-asesmen tidak menghasilkan triage tinggi', () {
      final result = interpretDassWho5(
        answers: const {'activating': 'presentasi ditolak'},
        moduleId: 'abcde',
      );
      expect(result.triageLevel, 'rendah');
      expect(result.certaintyFactor, lessThanOrEqualTo(1.0));
    });
  });
}
