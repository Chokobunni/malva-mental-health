import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/ai/ai.dart';

void main() {
  group('CertaintyFactorCalculator', () {
    group('scoreToCF', () {
      test('score 0 returns CF 0.0', () {
        expect(CertaintyFactorCalculator.scoreToCF(0), 0.0);
      });

      test('score 1 returns CF 0.3', () {
        expect(CertaintyFactorCalculator.scoreToCF(1), 0.3);
      });

      test('score 2 returns CF 0.6', () {
        expect(CertaintyFactorCalculator.scoreToCF(2), 0.6);
      });

      test('score 3 returns CF 0.9', () {
        expect(CertaintyFactorCalculator.scoreToCF(3), 0.9);
      });
    });

    group('combine', () {
      test('combines two positive CFs correctly', () {
        // CF(A) = 0.6, CF(B) = 0.4
        // Combined = 0.6 + 0.4 * (1 - 0.6) = 0.76
        final result = CertaintyFactorCalculator.combine(0.6, 0.4);
        expect(result, closeTo(0.76, 0.001));
      });

      test('combines CF with 1.0 correctly', () {
        // CF(A) = 0.8, CF(B) = 1.0
        // Combined = 0.8 + 1.0 * (1 - 0.8) = 1.0
        final result = CertaintyFactorCalculator.combine(0.8, 1.0);
        expect(result, closeTo(1.0, 0.001));
      });

      test('combines two negative CFs correctly', () {
        // CF(A) = -0.6, CF(B) = -0.4
        // Combined = -0.6 + (-0.4) * (1 + (-0.6)) = -0.76
        final result = CertaintyFactorCalculator.combine(-0.6, -0.4);
        expect(result, closeTo(-0.76, 0.001));
      });

      test('combines opposite sign CFs correctly', () {
        // CF(A) = 0.7, CF(B) = -0.3
        // Should partially cancel out
        final result = CertaintyFactorCalculator.combine(0.7, -0.3);
        expect(result, lessThan(0.7));
        expect(result, greaterThan(-0.3));
      });

      test('combines 0.0 with positive CF', () {
        final result = CertaintyFactorCalculator.combine(0.0, 0.5);
        expect(result, closeTo(0.5, 0.001));
      });

      test('combines 0.0 with 0.0', () {
        final result = CertaintyFactorCalculator.combine(0.0, 0.0);
        expect(result, 0.0);
      });
    });

    group('combineConditions', () {
      test('combines multiple positive conditions', () {
        final result =
            CertaintyFactorCalculator.combineConditions([0.6, 0.4, 0.5]);
        expect(result, greaterThan(0.0));
        expect(result, lessThan(1.0));
      });

      test('returns 0.0 for empty list', () {
        expect(CertaintyFactorCalculator.combineConditions([]), 0.0);
      });

      test('returns 0.0 when all conditions are 0', () {
        expect(
            CertaintyFactorCalculator.combineConditions([0.0, 0.0, 0.0]), 0.0);
      });
    });

    group('normalize', () {
      test('normalizes -1.0 to 0.0', () {
        expect(CertaintyFactorCalculator.normalize(-1.0), 0.0);
      });

      test('normalizes 0.0 to 0.5', () {
        expect(CertaintyFactorCalculator.normalize(0.0), 0.5);
      });

      test('normalizes 1.0 to 1.0', () {
        expect(CertaintyFactorCalculator.normalize(1.0), 1.0);
      });
    });

    group('labelFor', () {
      test('returns correct labels for different CF ranges', () {
        // CF = 0.0 → normalized = 0.5 → 'Cukup Pasti'
        expect(CertaintyFactorCalculator.labelFor(-1.0), 'Sangat Tidak Pasti');
        expect(CertaintyFactorCalculator.labelFor(0.0), 'Cukup Pasti');
        // CF = 0.5 → normalized = 0.75 → 'Pasti'
        expect(CertaintyFactorCalculator.labelFor(0.5), 'Pasti');
        expect(CertaintyFactorCalculator.labelFor(1.0), 'Sangat Pasti');
      });
    });
  });

  group('KnowledgeBase', () {
    test('PHQ-9 rules are defined', () {
      expect(KnowledgeBase.phq9Rules.length, greaterThan(0));
    });

    test('GAD-7 rules are defined', () {
      expect(KnowledgeBase.gad7Rules.length, greaterThan(0));
    });

    test('PHQ-9 has 9 question IDs', () {
      expect(KnowledgeBase.phq9QuestionIds.length, 9);
    });

    test('GAD-7 has 7 question IDs', () {
      expect(KnowledgeBase.gad7QuestionIds.length, 7);
    });

    test('all rules have valid IDs', () {
      for (final rule in KnowledgeBase.allRules) {
        expect(rule.id.isNotEmpty, true, reason: 'Rule ID should not be empty');
        expect(rule.ruleCF, greaterThan(0.0));
        expect(rule.ruleCF, lessThanOrEqualTo(1.0));
      }
    });
  });

  group('ForwardChainingEngine', () {
    late ForwardChainingEngine engine;

    setUp(() {
      engine = ForwardChainingEngine();
    });

    group('PHQ-9 Screening', () {
      test('minimal depression (score 0-4)', () {
        // All answers 0 = score 0
        final result = engine.infer(
          questionIds: KnowledgeBase.phq9QuestionIds,
          answers: [0, 0, 0, 0, 0, 0, 0, 0, 0],
          rules: KnowledgeBase.phq9Rules,
        );

        expect(result.level, 'minimal');
        expect(result.isCrisis, false);
        expect(result.certaintyFactor, greaterThan(0.0));
      });

      test('mild depression (score 5-9)', () {
        // Answers: 1,1,1,1,1,0,0,0,0 = score 5
        final result = engine.infer(
          questionIds: KnowledgeBase.phq9QuestionIds,
          answers: [1, 1, 1, 1, 1, 0, 0, 0, 0],
          rules: KnowledgeBase.phq9Rules,
        );

        expect(result.level, 'mild');
        expect(result.isCrisis, false);
      });

      test('moderate depression (score 10-14)', () {
        // Answers: 2,2,2,2,2,0,0,0,0 = score 10
        final result = engine.infer(
          questionIds: KnowledgeBase.phq9QuestionIds,
          answers: [2, 2, 2, 2, 2, 0, 0, 0, 0],
          rules: KnowledgeBase.phq9Rules,
        );

        expect(result.level, 'moderate');
        expect(result.isCrisis, false);
      });

      test('severe depression (score 15-19)', () {
        // Answers: 2,2,2,2,2,2,2,1,0 = score 15
        final result = engine.infer(
          questionIds: KnowledgeBase.phq9QuestionIds,
          answers: [2, 2, 2, 2, 2, 2, 2, 1, 0],
          rules: KnowledgeBase.phq9Rules,
        );

        expect(result.level, 'severe');
        expect(result.isCrisis, false);
      });

      test('severe depression (score 20-27)', () {
        // Answers: 3,3,3,3,3,3,2,0,0 = score 20
        final result = engine.infer(
          questionIds: KnowledgeBase.phq9QuestionIds,
          answers: [3, 3, 3, 3, 3, 3, 2, 0, 0],
          rules: KnowledgeBase.phq9Rules,
        );

        expect(result.level, 'severe');
        expect(result.isCrisis, false);
      });

      test('crisis flag when self-harm item positive', () {
        // Item 9 (phq_self_harm) = 1, all others 0
        final result = engine.infer(
          questionIds: KnowledgeBase.phq9QuestionIds,
          answers: [0, 0, 0, 0, 0, 0, 0, 0, 1],
          rules: KnowledgeBase.phq9Rules,
        );

        expect(result.level, 'crisis');
        expect(result.isCrisis, true);
        expect(result.certaintyFactor, greaterThan(0.9));
      });

      test('crisis flag even with low total score', () {
        // Low total but self-harm positive
        final result = engine.infer(
          questionIds: KnowledgeBase.phq9QuestionIds,
          answers: [0, 0, 0, 0, 0, 0, 0, 0, 3],
          rules: KnowledgeBase.phq9Rules,
        );

        expect(result.isCrisis, true);
      });

      test('audit trail contains fired rules', () {
        final result = engine.infer(
          questionIds: KnowledgeBase.phq9QuestionIds,
          answers: [1, 1, 1, 1, 1, 0, 0, 0, 0],
          rules: KnowledgeBase.phq9Rules,
        );

        expect(result.trace.length, greaterThan(0));
        expect(result.trace.any((t) => t.fired), true);
      });
    });

    group('GAD-7 Screening', () {
      test('minimal anxiety (score 0-4)', () {
        final result = engine.infer(
          questionIds: KnowledgeBase.gad7QuestionIds,
          answers: [0, 0, 0, 0, 0, 0, 0],
          rules: KnowledgeBase.gad7Rules,
        );

        expect(result.level, 'minimal');
        expect(result.isCrisis, false);
      });

      test('mild anxiety (score 5-9)', () {
        final result = engine.infer(
          questionIds: KnowledgeBase.gad7QuestionIds,
          answers: [1, 1, 1, 1, 1, 0, 0],
          rules: KnowledgeBase.gad7Rules,
        );

        expect(result.level, 'mild');
        expect(result.isCrisis, false);
      });

      test('moderate anxiety (score 10-14)', () {
        final result = engine.infer(
          questionIds: KnowledgeBase.gad7QuestionIds,
          answers: [2, 2, 2, 2, 2, 0, 0],
          rules: KnowledgeBase.gad7Rules,
        );

        expect(result.level, 'moderate');
        expect(result.isCrisis, false);
      });

      test('severe anxiety (score 15-21)', () {
        final result = engine.infer(
          questionIds: KnowledgeBase.gad7QuestionIds,
          answers: [3, 3, 3, 2, 2, 1, 1],
          rules: KnowledgeBase.gad7Rules,
        );

        expect(result.level, 'severe');
        expect(result.isCrisis, false);
      });
    });

    group('Clinical Scenarios', () {
      test('scenario: patient with mixed depression and anxiety', () {
        // PHQ-9: moderate depression (score 10)
        final phq9Result = engine.infer(
          questionIds: KnowledgeBase.phq9QuestionIds,
          answers: [2, 2, 2, 2, 2, 0, 0, 0, 0],
          rules: KnowledgeBase.phq9Rules,
        );

        // GAD-7: moderate anxiety (score 10)
        final gad7Result = engine.infer(
          questionIds: KnowledgeBase.gad7QuestionIds,
          answers: [2, 2, 2, 2, 2, 0, 0],
          rules: KnowledgeBase.gad7Rules,
        );

        expect(phq9Result.level, 'moderate');
        expect(gad7Result.level, 'moderate');
      });

      test('scenario: crisis patient with comorbid conditions', () {
        // High PHQ-9 with self-harm
        final result = engine.infer(
          questionIds: KnowledgeBase.phq9QuestionIds,
          answers: [3, 3, 3, 3, 3, 3, 3, 3, 3],
          rules: KnowledgeBase.phq9Rules,
        );

        expect(result.isCrisis, true);
        expect(result.level, 'crisis');
        expect(result.certaintyFactor, greaterThan(0.9));
      });

      test('scenario: minimal symptoms', () {
        final result = engine.infer(
          questionIds: KnowledgeBase.phq9QuestionIds,
          answers: [0, 0, 0, 0, 0, 0, 0, 0, 0],
          rules: KnowledgeBase.phq9Rules,
        );

        expect(result.level, 'minimal');
        expect(result.certaintyFactor, greaterThan(0.8));
      });
    });

    group('Error Handling', () {
      test('throws when answer count mismatch', () {
        expect(
          () => engine.infer(
            questionIds: KnowledgeBase.phq9QuestionIds,
            answers: [0, 0, 0], // Wrong count
            rules: KnowledgeBase.phq9Rules,
          ),
          throwsArgumentError,
        );
      });

      test('throws when answer out of range', () {
        expect(
          () => engine.infer(
            questionIds: KnowledgeBase.phq9QuestionIds,
            answers: [0, 0, 0, 0, 0, 0, 0, 0, 5], // Invalid
            rules: KnowledgeBase.phq9Rules,
          ),
          throwsArgumentError,
        );
      });

      test('throws when negative answer', () {
        expect(
          () => engine.infer(
            questionIds: KnowledgeBase.phq9QuestionIds,
            answers: [0, 0, 0, 0, 0, 0, 0, 0, -1], // Invalid
            rules: KnowledgeBase.phq9Rules,
          ),
          throwsArgumentError,
        );
      });
    });

    group('Working Memory', () {
      test('working memory contains all facts', () {
        final result = engine.infer(
          questionIds: KnowledgeBase.phq9QuestionIds,
          answers: [1, 1, 1, 1, 1, 0, 0, 0, 0],
          rules: KnowledgeBase.phq9Rules,
        );

        // Should contain original answers
        expect(result.workingMemory.containsKey('phq_interest'), true);
        expect(result.workingMemory.containsKey('phq_self_harm'), true);

        // Should contain derived facts
        expect(result.workingMemory.containsKey('phq9_total_score'), true);
        expect(result.workingMemory.containsKey('depression_level'), true);
      });

      test('total score is calculated correctly', () {
        final result = engine.infer(
          questionIds: KnowledgeBase.phq9QuestionIds,
          answers: [1, 2, 1, 0, 1, 0, 0, 0, 0],
          rules: KnowledgeBase.phq9Rules,
        );

        final totalScore = result.workingMemory['phq9_total_score'];
        expect(totalScore?.value, 5);
      });
    });
  });
}
