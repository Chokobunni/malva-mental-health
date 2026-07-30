import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:malva_mental_health/src/assessment_engine.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';

void main() {
  group('AssessmentEngine PHQ-9', () {
    test('maps PHQ-9 severity boundaries', () {
      expect(_phqNoCrisis(4).level, RiskLevel.minimal);
      expect(_phqNoCrisis(5).level, RiskLevel.mild);
      expect(_phqNoCrisis(9).level, RiskLevel.mild);
      expect(_phqNoCrisis(10).level, RiskLevel.moderate);
      expect(_phqNoCrisis(14).level, RiskLevel.moderate);
      expect(_phqNoCrisis(15).level, RiskLevel.severe);
      expect(_phqNoCrisis(19).level, RiskLevel.severe);
      expect(_phqNoCrisis(20).level, RiskLevel.severe);
    });

    test('sets crisis flag when item 9 is positive', () {
      final result = AssessmentEngine.score(
        type: AssessmentType.phq9,
        answers: [0, 0, 0, 0, 0, 0, 0, 0, 1],
      );

      expect(result.crisisFlag, isTrue);
      expect(result.level, RiskLevel.crisis);
    });
  });

  group('AssessmentEngine GAD-7', () {
    test('maps GAD-7 severity boundaries', () {
      expect(_gad(4).level, RiskLevel.minimal);
      expect(_gad(5).level, RiskLevel.mild);
      expect(_gad(9).level, RiskLevel.mild);
      expect(_gad(10).level, RiskLevel.moderate);
      expect(_gad(14).level, RiskLevel.moderate);
      expect(_gad(15).level, RiskLevel.severe);
      expect(_gad(21).level, RiskLevel.severe);
    });
  });

  test('stores combined initial screening bundle', () {
    final container = ProviderContainer();
    final store = container.read(malvaStoreProvider.notifier);
    final phq9 = _phqNoCrisis(10);
    final gad7 = _gad(5);

    store.saveScreeningBundle(
      ScreeningBundle(
        id: 'bundle_test',
        phq9: phq9,
        gad7: gad7,
        createdAt: DateTime(2026, 7, 9),
        isInitial: true,
        source: 'test',
      ),
    );

    expect(
        store.state.initialScreeningStatus, InitialScreeningStatus.completed);
    expect(store.state.screeningBundles, hasLength(1));
    expect(store.state.assessments, hasLength(2));
  });
}

AssessmentResult _phqNoCrisis(int score) {
  final answers = [..._answers(score, 8), 0];
  return AssessmentEngine.score(type: AssessmentType.phq9, answers: answers);
}

AssessmentResult _gad(int score) {
  return AssessmentEngine.score(
      type: AssessmentType.gad7, answers: _answers(score, 7));
}

List<int> _answers(int total, int length) {
  final answers = List<int>.filled(length, 0);
  var remaining = total;
  for (var i = 0; i < answers.length; i++) {
    final value = remaining.clamp(0, 3).toInt();
    answers[i] = value;
    remaining -= value;
  }
  return answers;
}
