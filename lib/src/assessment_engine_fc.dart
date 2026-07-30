/// Bridge between the new AI engine and existing assessment interface.
///
/// This module provides backward-compatible scoring that uses
/// Forward Chaining + Certainty Factor internally while returning
/// the same `AssessmentResult` type used by existing screens.
///
/// This ensures no existing features are broken while adding
/// AI-powered reasoning.
import 'models.dart';
import 'ai/ai.dart' as ai;

/// Enhanced assessment engine that uses Forward Chaining + CF.
///
/// This engine maintains the same interface as the original
/// `AssessmentEngine` but uses AI-based reasoning internally.
class AssessmentEngine {
  const AssessmentEngine._();

  static const ruleVersion = '2026.1.FC'; // FC = Forward Chaining

  static const responseLabels = [
    'Tidak sama sekali',
    'Beberapa hari',
    'Lebih dari separuh hari',
    'Hampir setiap hari',
  ];

  static const phq9Questions = [
    AssessmentQuestion(id: 'phq_interest', label: 'Minat atau rasa senang menurun', domain: 'mood'),
    AssessmentQuestion(id: 'phq_low_mood', label: 'Mood sedih, murung, atau putus asa', domain: 'mood'),
    AssessmentQuestion(id: 'phq_sleep', label: 'Pola tidur terganggu', domain: 'sleep'),
    AssessmentQuestion(id: 'phq_energy', label: 'Energi rendah atau mudah lelah', domain: 'energy'),
    AssessmentQuestion(id: 'phq_appetite', label: 'Perubahan nafsu makan', domain: 'appetite'),
    AssessmentQuestion(id: 'phq_self_worth', label: 'Merasa gagal atau menyalahkan diri', domain: 'self_worth'),
    AssessmentQuestion(id: 'phq_focus', label: 'Sulit berkonsentrasi', domain: 'focus'),
    AssessmentQuestion(id: 'phq_motor', label: 'Gerak atau bicara melambat, atau gelisah', domain: 'motor'),
    AssessmentQuestion(id: 'phq_self_harm', label: 'Pikiran menyakiti diri', domain: 'safety'),
  ];

  static const gad7Questions = [
    AssessmentQuestion(id: 'gad_nervous', label: 'Merasa gugup, cemas, atau tegang', domain: 'anxiety'),
    AssessmentQuestion(id: 'gad_control', label: 'Sulit menghentikan kekhawatiran', domain: 'worry'),
    AssessmentQuestion(id: 'gad_worry', label: 'Terlalu banyak khawatir', domain: 'worry'),
    AssessmentQuestion(id: 'gad_relax', label: 'Sulit rileks', domain: 'relaxation'),
    AssessmentQuestion(id: 'gad_restless', label: 'Sulit diam karena gelisah', domain: 'restlessness'),
    AssessmentQuestion(id: 'gad_irritable', label: 'Mudah kesal', domain: 'irritability'),
    AssessmentQuestion(id: 'gad_fear', label: 'Takut sesuatu buruk terjadi', domain: 'fear'),
  ];

  static List<AssessmentQuestion> questionsFor(AssessmentType type) {
    return switch (type) {
      AssessmentType.phq9 => phq9Questions,
      AssessmentType.gad7 => gad7Questions,
    };
  }

  /// Score using Forward Chaining + Certainty Factor.
  ///
  /// This method uses the AI engine internally but returns
  /// the same `AssessmentResult` type for backward compatibility.
  static AssessmentResult score({
    required AssessmentType type,
    required List<int> answers,
  }) {
    final expected = questionsFor(type).length;
    if (answers.length != expected) {
      throw ArgumentError('Expected $expected answers for ${type.title}.');
    }
    if (answers.any((value) => value < 0 || value > 3)) {
      throw ArgumentError('Assessment answers must be between 0 and 3.');
    }

    // Get question IDs for the AI engine
    final questionIds = questionsFor(type).map((q) => q.id).toList();

    // Get rules for this assessment type
    final rules = type == AssessmentType.phq9
        ? ai.KnowledgeBase.phq9Rules
        : ai.KnowledgeBase.gad7Rules;

    // Run Forward Chaining inference
    final aiEngine = ai.ForwardChainingEngine();
    final inferenceResult = aiEngine.infer(
      questionIds: questionIds,
      answers: answers,
      rules: rules,
    );

    // Calculate simple total score for backward compatibility
    final totalScore = answers.fold<int>(0, (sum, value) => sum + value);

    // Map AI result level to RiskLevel
    final riskLevel = _mapToRiskLevel(inferenceResult.level);

    // Convert AI trace to RuleTrace for backward compatibility
    final rulesFired = inferenceResult.trace
        .where((t) => t.fired)
        .map((t) => RuleTrace(
              id: t.rule.id,
              label: t.rule.description,
              level: _mapToRiskLevel(t.rule.id.contains('CRISIS')
                  ? 'crisis'
                  : _levelFromRuleId(t.rule.id)),
            ))
        .toList();

    // Build summary with CF information
    final summary = '${inferenceResult.summary}\n'
        'Confidence: ${(inferenceResult.certaintyFactor * 100).toStringAsFixed(1)}%';

    return AssessmentResult(
      type: type,
      score: totalScore,
      maxScore: type == AssessmentType.phq9 ? 27 : 21,
      level: riskLevel,
      summary: summary,
      crisisFlag: inferenceResult.isCrisis,
      rulesFired: rulesFired,
      createdAt: DateTime.now(),
      ruleVersion: ruleVersion,
    );
  }

  /// Map AI inference level to RiskLevel enum.
  static RiskLevel _mapToRiskLevel(String level) {
    switch (level) {
      case 'minimal':
        return RiskLevel.minimal;
      case 'mild':
        return RiskLevel.mild;
      case 'moderate':
        return RiskLevel.moderate;
      case 'severe':
        return RiskLevel.severe;
      case 'crisis':
        return RiskLevel.crisis;
      default:
        return RiskLevel.minimal;
    }
  }

  /// Extract level from rule ID.
  static String _levelFromRuleId(String ruleId) {
    if (ruleId.contains('MINIMAL')) return 'minimal';
    if (ruleId.contains('MILD')) return 'mild';
    if (ruleId.contains('MODERATE')) return 'moderate';
    if (ruleId.contains('SEVERE')) return 'severe';
    return 'minimal';
  }
}
