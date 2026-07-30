/// Data models for Forward Chaining + Certainty Factor screening engine.
///
/// These models are isolated in `lib/src/ai/` to avoid affecting existing code.
/// The existing `AssessmentResult` interface is preserved for backward compatibility.
library;

/// Represents a patient's answer to a screening question.
///
/// Each answer maps to a symptom with a raw score (0-3) that will be
/// converted to a Certainty Factor for inference.
class PatientAnswer {
  /// The question identifier (e.g., 'phq_interest', 'gad_nervous').
  final String questionId;

  /// Raw answer value: 0 = Tidak sama sekali, 1 = Beberapa hari,
  /// 2 = Lebih dari separuh hari, 3 = Hampir setiap hari.
  final int rawValue;

  const PatientAnswer({
    required this.questionId,
    required this.rawValue,
  });

  /// Validate the answer is within acceptable range.
  bool get isValid => rawValue >= 0 && rawValue <= 3;
}

/// Represents a single clinical fact in working memory.
///
/// Facts are the building blocks of forward chaining - they represent
/// what the system knows about the patient's condition.
class ClinicalFact {
  /// Unique identifier for this fact (e.g., 'depression_level', 'anxiety_level').
  final String factId;

  /// The value of this fact (e.g., 'mild', 'severe', true, false).
  final dynamic value;

  /// Certainty Factor for this fact, ranging from -1.0 to 1.0.
  /// Positive values indicate the fact is supported, negative values
  /// indicate the fact is contradicted.
  final double certaintyFactor;

  /// Human-readable explanation of how this fact was derived.
  final String explanation;

  const ClinicalFact({
    required this.factId,
    required this.value,
    required this.certaintyFactor,
    this.explanation = '',
  });

  @override
  String toString() =>
      'ClinicalFact($factId: $value, CF=${certaintyFactor.toStringAsFixed(3)})';
}

/// Represents an IF-THEN rule in the knowledge base.
///
/// Rules connect symptoms/facts to conclusions using Certainty Factors.
/// When all conditions are met, the rule fires and produces conclusions.
class ScreeningRule {
  /// Unique identifier for this rule (e.g., 'PHQ9_DEPRESSION_MILD').
  final String id;

  /// Human-readable description of what this rule checks.
  final String description;

  /// All conditions that must be true for this rule to fire.
  /// ALL conditions must be satisfied (AND logic).
  final List<RuleCondition> conditions;

  /// Conclusions produced when this rule fires.
  /// Each conclusion adds a new fact to working memory.
  final List<RuleConclusion> conclusions;

  /// Base Certainty Factor for this rule (0.0 to 1.0).
  /// Represents the rule's overall reliability from clinical literature.
  final double ruleCF;

  const ScreeningRule({
    required this.id,
    required this.description,
    required this.conditions,
    required this.conclusions,
    required this.ruleCF,
  });
}

/// A single condition in a screening rule.
///
/// Conditions check whether a fact or answer meets certain criteria.
/// Conditions can reference either patient answers or derived facts.
class RuleCondition {
  /// The fact or answer ID to check.
  final String factId;

  /// Comparison operator.
  final ConditionOperator operator;

  /// Value to compare against.
  final dynamic value;

  /// Minimum CF required for this condition to be satisfied.
  /// If the fact's CF is below this threshold, the condition fails.
  final double minCF;

  const RuleCondition({
    required this.factId,
    required this.operator,
    required this.value,
    this.minCF = 0.0,
  });
}

/// Comparison operators for rule conditions.
enum ConditionOperator {
  equals('=='),
  notEquals('!='),
  greaterThan('>'),
  greaterOrEqual('>='),
  lessThan('<'),
  lessOrEqual('<='),
  contains('contains');

  final String symbol;
  const ConditionOperator(this.symbol);
}

/// A conclusion produced by a firing rule.
///
/// Conclusions add new facts to working memory with an associated CF.
/// These derived facts can trigger further rules in the chain.
class RuleConclusion {
  /// The fact ID to set or update.
  final String factId;

  /// Value to assign to this fact.
  final dynamic value;

  /// Certainty Factor for this conclusion.
  /// Will be combined with the rule's CF and condition CFs.
  final double cf;

  /// Human-readable explanation for audit trail.
  final String explanation;

  const RuleConclusion({
    required this.factId,
    required this.value,
    required this.cf,
    this.explanation = '',
  });
}

/// Result of running forward chaining inference.
///
/// Contains the final diagnosis, combined CF, and complete audit trail
/// of which rules fired during inference.
class InferenceResult {
  /// The primary diagnosis level (e.g., 'minimal', 'mild', 'moderate', 'severe', 'crisis').
  final String level;

  /// Combined Certainty Factor for this diagnosis (0.0 to 1.0).
  final double certaintyFactor;

  /// Human-readable summary of the diagnosis.
  final String summary;

  /// Whether this result indicates a crisis situation.
  final bool isCrisis;

  /// Complete audit trail of rules that fired during inference.
  final List<RuleFiredTrace> trace;

  /// All facts in working memory after inference.
  final Map<String, ClinicalFact> workingMemory;

  const InferenceResult({
    required this.level,
    required this.certaintyFactor,
    required this.summary,
    required this.isCrisis,
    required this.trace,
    required this.workingMemory,
  });
}

/// Audit trail entry for a rule that fired during inference.
///
/// This provides transparency into how the system reached its conclusion,
/// which is critical for clinical decision support systems.
class RuleFiredTrace {
  /// The rule that was evaluated.
  final ScreeningRule rule;

  /// Whether the rule actually fired (all conditions met).
  final bool fired;

  /// The combined CF of all conditions when evaluated.
  final double conditionCF;

  /// The resulting CF after combining with rule CF.
  final double resultCF;

  /// Which conditions were satisfied.
  final List<String> satisfiedConditions;

  /// Which conditions were NOT satisfied (if rule didn't fire).
  final List<String> failedConditions;

  const RuleFiredTrace({
    required this.rule,
    required this.fired,
    required this.conditionCF,
    required this.resultCF,
    this.satisfiedConditions = const [],
    this.failedConditions = const [],
  });
}
