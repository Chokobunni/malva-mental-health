import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

void main() {
  test('missing per-instrument CF recovers existing severity-rule support', () {
    final session = BackendScreeningSession.fromJson({
      'bundle': {
        'phq9': {'score': 23, 'max_score': 27},
        'gad7': {'score': 21, 'max_score': 21},
      }
    });
    expect(session.phq9.hasCertaintyFactor, isTrue);
    expect(session.phq9.certaintyFactor, closeTo(.9025, 1e-9));
    expect(session.gad7.hasCertaintyFactor, isTrue);
    expect(session.gad7.certaintyFactor, closeTo(.855, 1e-9));
    expect(session.phq9.answers, isEmpty);
    expect(session.gad7.answers, isEmpty);
  });

  test('stored positive PHQ safety is retained when recovering rule support',
      () {
    final result = BackendAssessmentSummary.fromJson({
      'type': 'phq9',
      'score': 7,
      'max_score': 27,
      'crisis_flag': true,
    });
    expect(result.crisisFlag, isTrue);
    expect(result.certaintyFactor, closeTo(.95, 1e-9));
  });

  test('recorded CF including zero remains authoritative over recovery', () {
    for (final cf in [0.0, .43, .95]) {
      final result = BackendAssessmentSummary.fromJson({
        'type': 'phq9',
        'score': 23,
        'max_score': 27,
        'cf': cf,
      });
      expect(result.hasCertaintyFactor, isTrue);
      expect(result.certaintyFactor, cf);
    }
  });

  test('unknown totals cannot produce model support from safety alone', () {
    for (final total in [null, -1, 28, 1.5, '23']) {
      final result = BackendAssessmentSummary.fromJson({
        'type': 'phq9',
        'score': total,
        'max_score': 27,
        'crisis_flag': true,
      });
      expect(result.hasCertaintyFactor, isFalse);
      expect(result.crisisFlag, isTrue);
    }
  });

  test('saved full answers recover safety CF without changing the total', () {
    final result = BackendAssessmentSummary.fromJson({
      'type': 'phq9',
      'score': 1,
      'max_score': 27,
      'answers': [
        for (final id in [
          'phq_interest',
          'phq_low_mood',
          'phq_sleep',
          'phq_energy',
          'phq_appetite',
          'phq_self_worth',
          'phq_focus',
          'phq_motor',
          'phq_self_harm'
        ])
          {'question_id': id, 'score': id == 'phq_self_harm' ? 1 : 0}
      ]
    });
    expect(result.score, 1);
    expect(result.crisisFlag, isTrue);
    expect(result.certaintyFactor, closeTo(.95, 1e-9));
  });
}
