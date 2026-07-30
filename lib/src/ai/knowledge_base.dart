import 'models.dart';

/// Knowledge base containing clinical screening rules for PHQ-9 and GAD-7.
///
/// Rules are based on:
/// - WHO PHQ-9 (Patient Health Questionnaire-9)
/// - WHO GAD-7 (Generalized Anxiety Disorder-7)
/// - Clinical practice guidelines for mental health screening
///
/// Each rule has:
/// - Conditions that must be met (patient answers or derived facts)
/// - Conclusions with Certainty Factors
/// - A base CF representing the rule's clinical reliability
class KnowledgeBase {
  /// Prevent instantiation of static class.
  const KnowledgeBase._();

  /// All PHQ-9 screening rules for depression assessment.
  static List<ScreeningRule> get phq9Rules => [
        // ============================================================
        // SEVERITY LEVEL RULES (based on total score ranges)
        // These rules determine the overall depression severity level
        // ============================================================

        ScreeningRule(
          id: 'PHQ9_MINIMAL',
          description: 'Gejala depresi minimal (skor 0-4)',
          conditions: [
            RuleCondition(
              factId: 'phq9_total_score',
              operator: ConditionOperator.lessOrEqual,
              value: 4,
              minCF: 0.0,
            ),
          ],
          conclusions: [
            RuleConclusion(
              factId: 'depression_level',
              value: 'minimal',
              cf: 0.9,
              explanation: 'Skor PHQ-9 ≤ 4 menunjukkan gejala depresi minimal',
            ),
            RuleConclusion(
              factId: 'depression_summary',
              value: 'Gejala depresi minimal. Pantau pola mood dan rutinitas.',
              cf: 0.9,
            ),
          ],
          ruleCF: 0.95,
        ),

        ScreeningRule(
          id: 'PHQ9_MILD',
          description: 'Gejala depresi ringan (skor 5-9)',
          conditions: [
            RuleCondition(
              factId: 'phq9_total_score',
              operator: ConditionOperator.greaterOrEqual,
              value: 5,
              minCF: 0.0,
            ),
            RuleCondition(
              factId: 'phq9_total_score',
              operator: ConditionOperator.lessOrEqual,
              value: 9,
              minCF: 0.0,
            ),
          ],
          conclusions: [
            RuleConclusion(
              factId: 'depression_level',
              value: 'mild',
              cf: 0.85,
              explanation: 'Skor PHQ-9 5-9 menunjukkan gejala depresi ringan',
            ),
            RuleConclusion(
              factId: 'depression_summary',
              value:
                  'Gejala ringan. Ulangi asesmen dan diskusikan bila menetap.',
              cf: 0.85,
            ),
          ],
          ruleCF: 0.93,
        ),

        ScreeningRule(
          id: 'PHQ9_MODERATE',
          description: 'Gejala depresi sedang (skor 10-14)',
          conditions: [
            RuleCondition(
              factId: 'phq9_total_score',
              operator: ConditionOperator.greaterOrEqual,
              value: 10,
              minCF: 0.0,
            ),
            RuleCondition(
              factId: 'phq9_total_score',
              operator: ConditionOperator.lessOrEqual,
              value: 14,
              minCF: 0.0,
            ),
          ],
          conclusions: [
            RuleConclusion(
              factId: 'depression_level',
              value: 'moderate',
              cf: 0.9,
              explanation: 'Skor PHQ-9 10-14 menunjukkan gejala depresi sedang',
            ),
            RuleConclusion(
              factId: 'depression_summary',
              value:
                  'Gejala sedang. Perlu review profesional dan rencana tindak lanjut.',
              cf: 0.9,
            ),
          ],
          ruleCF: 0.95,
        ),

        ScreeningRule(
          id: 'PHQ9_SEVERE_MODERATE',
          description: 'Gejala depresi cukup berat (skor 15-19)',
          conditions: [
            RuleCondition(
              factId: 'phq9_total_score',
              operator: ConditionOperator.greaterOrEqual,
              value: 15,
              minCF: 0.0,
            ),
            RuleCondition(
              factId: 'phq9_total_score',
              operator: ConditionOperator.lessOrEqual,
              value: 19,
              minCF: 0.0,
            ),
          ],
          conclusions: [
            RuleConclusion(
              factId: 'depression_level',
              value: 'severe',
              cf: 0.92,
              explanation:
                  'Skor PHQ-9 15-19 menunjukkan gejala depresi cukup berat',
            ),
            RuleConclusion(
              factId: 'depression_summary',
              value: 'Gejala cukup berat. Prioritaskan evaluasi profesional.',
              cf: 0.92,
            ),
          ],
          ruleCF: 0.96,
        ),

        ScreeningRule(
          id: 'PHQ9_SEVERE_HIGH',
          description: 'Gejala depresi berat (skor 20-27)',
          conditions: [
            RuleCondition(
              factId: 'phq9_total_score',
              operator: ConditionOperator.greaterOrEqual,
              value: 20,
              minCF: 0.0,
            ),
          ],
          conclusions: [
            RuleConclusion(
              factId: 'depression_level',
              value: 'severe',
              cf: 0.95,
              explanation: 'Skor PHQ-9 ≥ 20 menunjukkan gejala depresi berat',
            ),
            RuleConclusion(
              factId: 'depression_summary',
              value: 'Gejala berat. Butuh review klinis segera.',
              cf: 0.95,
            ),
          ],
          ruleCF: 0.98,
        ),

        // ============================================================
        // CRISIS RULE (Self-harm indicator)
        // This rule fires immediately if any self-harm item is positive
        // ============================================================

        ScreeningRule(
          id: 'PHQ9_CRISIS_SELF_HARM',
          description: 'Indikator krisis: pikiran menyakiti diri',
          conditions: [
            RuleCondition(
              factId: 'phq_self_harm',
              operator: ConditionOperator.greaterThan,
              value: 0,
              minCF: 0.0,
            ),
          ],
          conclusions: [
            RuleConclusion(
              factId: 'crisis_flag',
              value: true,
              cf: 0.95,
              explanation: 'Item 9 PHQ-9 positif (pikiran menyakiti diri)',
            ),
            RuleConclusion(
              factId: 'crisis_level',
              value: 'crisis',
              cf: 0.95,
              explanation:
                  'Ada indikator keselamatan diri. Tampilkan crisis flow dan hubungi profesional.',
            ),
          ],
          ruleCF: 1.0, // Maximum reliability - this is a critical safety rule
        ),

        // ============================================================
        // SYMPTOM PATTERN RULES
        // These rules detect specific symptom combinations
        // ============================================================

        ScreeningRule(
          id: 'PHQ9_MOTOR_RETARDATION',
          description: 'Pola gejala: perlambatan motorik/bicara',
          conditions: [
            RuleCondition(
              factId: 'phq_motor',
              operator: ConditionOperator.greaterOrEqual,
              value: 2,
              minCF: 0.0,
            ),
          ],
          conclusions: [
            RuleConclusion(
              factId: 'motor_retardation_present',
              value: true,
              cf: 0.7,
              explanation:
                  'Gejala perlambatan motorik/bicara terdeteksi (skor ≥ 2)',
            ),
          ],
          ruleCF: 0.8,
        ),

        ScreeningRule(
          id: 'PHQ9_SLEEP_DISRUPTION',
          description: 'Pola gejala: gangguan tidur signifikan',
          conditions: [
            RuleCondition(
              factId: 'phq_sleep',
              operator: ConditionOperator.greaterOrEqual,
              value: 2,
              minCF: 0.0,
            ),
          ],
          conclusions: [
            RuleConclusion(
              factId: 'sleep_disruption_present',
              value: true,
              cf: 0.7,
              explanation:
                  'Gejala gangguan tidur signifikan terdeteksi (skor ≥ 2)',
            ),
          ],
          ruleCF: 0.85,
        ),

        ScreeningRule(
          id: 'PHQ9_APPETITE_CHANGE',
          description: 'Pola gejala: perubahan nafsu makan',
          conditions: [
            RuleCondition(
              factId: 'phq_appetite',
              operator: ConditionOperator.greaterOrEqual,
              value: 2,
              minCF: 0.0,
            ),
          ],
          conclusions: [
            RuleConclusion(
              factId: 'appetite_change_present',
              value: true,
              cf: 0.7,
              explanation: 'Gejala perubahan nafsu makan terdeteksi (skor ≥ 2)',
            ),
          ],
          ruleCF: 0.8,
        ),

        ScreeningRule(
          id: 'PHQ9_CONCENTRATION_ISSUE',
          description: 'Pola gejala: kesulitan konsentrasi',
          conditions: [
            RuleCondition(
              factId: 'phq_focus',
              operator: ConditionOperator.greaterOrEqual,
              value: 2,
              minCF: 0.0,
            ),
          ],
          conclusions: [
            RuleConclusion(
              factId: 'concentration_issue_present',
              value: true,
              cf: 0.7,
              explanation: 'Gejala kesulitan konsentrasi terdeteksi (skor ≥ 2)',
            ),
          ],
          ruleCF: 0.8,
        ),

        ScreeningRule(
          id: 'PHQ9_SELF_WORTH_ISSUE',
          description: 'Pola gejala: perasaan gagal/menyalahkan diri',
          conditions: [
            RuleCondition(
              factId: 'phq_self_worth',
              operator: ConditionOperator.greaterOrEqual,
              value: 2,
              minCF: 0.0,
            ),
          ],
          conclusions: [
            RuleConclusion(
              factId: 'self_worth_issue_present',
              value: true,
              cf: 0.7,
              explanation:
                  'Gejala perasaan gagal/menyalahkan diri terdeteksi (skor ≥ 2)',
            ),
          ],
          ruleCF: 0.85,
        ),
      ];

  /// All GAD-7 screening rules for anxiety assessment.
  static List<ScreeningRule> get gad7Rules => [
        // ============================================================
        // SEVERITY LEVEL RULES (based on total score ranges)
        // ============================================================

        ScreeningRule(
          id: 'GAD7_MINIMAL',
          description: 'Gejala kecemasan minimal (skor 0-4)',
          conditions: [
            RuleCondition(
              factId: 'gad7_total_score',
              operator: ConditionOperator.lessOrEqual,
              value: 4,
              minCF: 0.0,
            ),
          ],
          conclusions: [
            RuleConclusion(
              factId: 'anxiety_level',
              value: 'minimal',
              cf: 0.9,
              explanation:
                  'Skor GAD-7 ≤ 4 menunjukkan gejala kecemasan minimal',
            ),
            RuleConclusion(
              factId: 'anxiety_summary',
              value: 'Gejala kecemasan minimal. Lanjutkan pemantauan rutin.',
              cf: 0.9,
            ),
          ],
          ruleCF: 0.95,
        ),

        ScreeningRule(
          id: 'GAD7_MILD',
          description: 'Gejala kecemasan ringan (skor 5-9)',
          conditions: [
            RuleCondition(
              factId: 'gad7_total_score',
              operator: ConditionOperator.greaterOrEqual,
              value: 5,
              minCF: 0.0,
            ),
            RuleCondition(
              factId: 'gad7_total_score',
              operator: ConditionOperator.lessOrEqual,
              value: 9,
              minCF: 0.0,
            ),
          ],
          conclusions: [
            RuleConclusion(
              factId: 'anxiety_level',
              value: 'mild',
              cf: 0.85,
              explanation: 'Skor GAD-7 5-9 menunjukkan gejala kecemasan ringan',
            ),
            RuleConclusion(
              factId: 'anxiety_summary',
              value: 'Gejala ringan. Ulangi asesmen pada follow-up.',
              cf: 0.85,
            ),
          ],
          ruleCF: 0.93,
        ),

        ScreeningRule(
          id: 'GAD7_MODERATE',
          description: 'Gejala kecemasan sedang (skor 10-14)',
          conditions: [
            RuleCondition(
              factId: 'gad7_total_score',
              operator: ConditionOperator.greaterOrEqual,
              value: 10,
              minCF: 0.0,
            ),
            RuleCondition(
              factId: 'gad7_total_score',
              operator: ConditionOperator.lessOrEqual,
              value: 14,
              minCF: 0.0,
            ),
          ],
          conclusions: [
            RuleConclusion(
              factId: 'anxiety_level',
              value: 'moderate',
              cf: 0.9,
              explanation:
                  'Skor GAD-7 10-14 menunjukkan gejala kecemasan sedang',
            ),
            RuleConclusion(
              factId: 'anxiety_summary',
              value: 'Gejala sedang. Perlu evaluasi profesional.',
              cf: 0.9,
            ),
          ],
          ruleCF: 0.95,
        ),

        ScreeningRule(
          id: 'GAD7_SEVERE',
          description: 'Gejala kecemasan berat (skor 15-21)',
          conditions: [
            RuleCondition(
              factId: 'gad7_total_score',
              operator: ConditionOperator.greaterOrEqual,
              value: 15,
              minCF: 0.0,
            ),
          ],
          conclusions: [
            RuleConclusion(
              factId: 'anxiety_level',
              value: 'severe',
              cf: 0.92,
              explanation: 'Skor GAD-7 ≥ 15 menunjukkan gejala kecemasan berat',
            ),
            RuleConclusion(
              factId: 'anxiety_summary',
              value:
                  'Gejala berat. Prioritaskan review klinis dan rencana dukungan.',
              cf: 0.92,
            ),
          ],
          ruleCF: 0.97,
        ),

        // ============================================================
        // SYMPTOM PATTERN RULES for GAD-7
        // ============================================================

        ScreeningRule(
          id: 'GAD7_WORRY_RUMINATION',
          description: 'Pola gejala: kekhawatiran berlebihan',
          conditions: [
            RuleCondition(
              factId: 'gad_worry',
              operator: ConditionOperator.greaterOrEqual,
              value: 2,
              minCF: 0.0,
            ),
            RuleCondition(
              factId: 'gad_control',
              operator: ConditionOperator.greaterOrEqual,
              value: 2,
              minCF: 0.0,
            ),
          ],
          conclusions: [
            RuleConclusion(
              factId: 'worry_rumination_present',
              value: true,
              cf: 0.75,
              explanation:
                  'Pola kekhawatiran berulang terdeteksi (kedua item ≥ 2)',
            ),
          ],
          ruleCF: 0.85,
        ),

        ScreeningRule(
          id: 'GAD7_RESTLESSNESS',
          description: 'Pola gejala: gelisah dan sulit rileks',
          conditions: [
            RuleCondition(
              factId: 'gad_restless',
              operator: ConditionOperator.greaterOrEqual,
              value: 2,
              minCF: 0.0,
            ),
            RuleCondition(
              factId: 'gad_relax',
              operator: ConditionOperator.greaterOrEqual,
              value: 2,
              minCF: 0.0,
            ),
          ],
          conclusions: [
            RuleConclusion(
              factId: 'restlessness_present',
              value: true,
              cf: 0.75,
              explanation:
                  'Pola gelisah dan sulit rileks terdeteksi (kedua item ≥ 2)',
            ),
          ],
          ruleCF: 0.85,
        ),

        ScreeningRule(
          id: 'GAD7_FEAR_ANSWER',
          description: 'Pola gejala: ketakutan akan sesuatu buruk',
          conditions: [
            RuleCondition(
              factId: 'gad_fear',
              operator: ConditionOperator.greaterOrEqual,
              value: 2,
              minCF: 0.0,
            ),
          ],
          conclusions: [
            RuleConclusion(
              factId: 'fear_present',
              value: true,
              cf: 0.7,
              explanation:
                  'Gejala ketakutan akan sesuatu buruk terdeteksi (skor ≥ 2)',
            ),
          ],
          ruleCF: 0.8,
        ),
      ];

  /// All screening rules combined.
  static List<ScreeningRule> get allRules => [...phq9Rules, ...gad7Rules];

  /// Question IDs for PHQ-9.
  static const List<String> phq9QuestionIds = [
    'phq_interest',
    'phq_low_mood',
    'phq_sleep',
    'phq_energy',
    'phq_appetite',
    'phq_self_worth',
    'phq_focus',
    'phq_motor',
    'phq_self_harm',
  ];

  /// Question IDs for GAD-7.
  static const List<String> gad7QuestionIds = [
    'gad_nervous',
    'gad_control',
    'gad_worry',
    'gad_relax',
    'gad_restless',
    'gad_irritable',
    'gad_fear',
  ];
}
