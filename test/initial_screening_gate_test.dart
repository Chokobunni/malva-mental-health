import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/ai/initial_screening.dart';
import 'package:malva_mental_health/src/ai/assessment_scoring.dart';

void main() {
  test(
      'high standardized WHO summary retains score and identifies low item follow-up',
      () {
    final answers = <String, dynamic>{
      'q1': 1,
      'q2': 5,
      'q3': 5,
      'q4': 5,
      'q5': 5,
      'scale_version': 2,
    };
    expect(who5Summary(answers), contains('WHO-5 21/25 (84%)'));
    expect(who5Summary(answers),
        contains('Perlu screening lanjutan karena ada jawaban 0–1'));
    expect(scoreWho5(answers).level, 'Baik');
    answers.remove('scale_version');
    expect(who5Summary(answers), isNot(contains('jawaban 0–1')));
  });
  test('WHO facts fire R1 only for complete stable answers', () {
    final result = inferInitialScreening([5, 5, 5, 5, 5]);
    expect(result.rawScore, 25);
    expect(result.percent, 100);
    expect(result.needsFurtherScreening, isFalse);
    expect(result.ruleTrace, ['R1']);
  });
  test('achievable scores either side of 50 select correct gate', () {
    expect(inferInitialScreening([2, 2, 2, 3, 3]).percent, 48);
    expect(
        inferInitialScreening([2, 2, 2, 3, 3]).needsFurtherScreening, isTrue);
    expect(inferInitialScreening([2, 2, 3, 3, 3]).percent, 52);
    expect(
        inferInitialScreening([2, 2, 3, 3, 3]).needsFurtherScreening, isFalse);
  });
  test('R2 overrides high total when one item is 0 or 1', () {
    for (final low in [0, 1]) {
      final result = inferInitialScreening([low, 5, 5, 5, 5]);
      expect(result.needsFurtherScreening, isTrue);
      expect(result.ruleTrace, ['R2', 'R3']);
      expect(result.facts['who5_any_item_le_1'], isTrue);
      expect(result.facts['status'], 'Butuh Skrining Lanjutan');
      expect(result.facts['phq9_enabled'], isTrue);
      expect(result.facts['gad7_enabled'], isTrue);
      expect(result.ruleTrace.toSet().length, result.ruleTrace.length);
    }
  });
  test('incomplete and invalid answers never become zero-filled scores', () {
    for (final values in <List<int?>>[
      [],
      [5, 5, 5, 5],
      [5, 5, null, 5, 5],
      [6, 5, 5, 5, 5],
      [-1, 5, 5, 5, 5],
      [5, 5, 5, 5, 5, 5],
    ]) {
      expect(() => inferInitialScreening(values), throwsArgumentError);
    }
  });
}
