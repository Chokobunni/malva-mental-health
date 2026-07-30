import 'models.dart';
import 'certainty_factor.dart';

/// Forward Chaining inference engine for mental health screening.
///
/// This engine implements data-driven reasoning:
/// 1. Start with patient answers (facts)
/// 2. Apply rules to derive new facts (conclusions)
/// 3. New facts can trigger more rules (chaining)
/// 4. Continue until no more rules can fire
///
/// The engine uses Certainty Factors to handle uncertainty in
/// clinical reasoning, providing confidence levels rather than
/// binary yes/no conclusions.
class ForwardChainingEngine {
  /// Maximum number of inference cycles to prevent infinite loops.
  static const int _maxIterations = 100;

  /// Run forward chaining inference on the given answers.
  ///
  /// This is the main entry point for the inference engine. It:
  /// 1. Converts patient answers to facts in working memory
  /// 2. Calculates total scores
  /// 3. Iteratively applies rules until no more fire
  /// 4. Returns the final inference result with audit trail
  ///
  /// Parameters:
  ///   [questionIds] - List of question identifiers in order
  ///   [answers] - Patient's raw answers (0-3) for each question
  ///   [rules] - Knowledge base rules to apply
  ///
  /// Returns:
  ///   [InferenceResult] with diagnosis, CF, and audit trail
  InferenceResult infer({
    required List<String> questionIds,
    required List<int> answers,
    required List<ScreeningRule> rules,
  }) {
    if (questionIds.length != answers.length) {
      throw ArgumentError('Question IDs and answers must have the same length');
    }

    // Initialize working memory with patient answers
    final workingMemory = <String, ClinicalFact>{};

    // Convert raw answers to clinical facts with CF
    for (int i = 0; i < questionIds.length; i++) {
      final questionId = questionIds[i];
      final rawValue = answers[i];

      if (rawValue < 0 || rawValue > 3) {
        throw ArgumentError('Answer for $questionId must be between 0 and 3');
      }

      workingMemory[questionId] = ClinicalFact(
        factId: questionId,
        value: rawValue,
        certaintyFactor: CertaintyFactorCalculator.scoreToCF(rawValue),
        explanation: 'Jawaban langsung dari pasien (skor $rawValue)',
      );
    }

    // Calculate total scores
    _calculateTotalScores(workingMemory, questionIds, 'phq9', 'phq_');
    _calculateTotalScores(workingMemory, questionIds, 'gad7', 'gad_');

    // Run forward chaining
    final trace = <RuleFiredTrace>[];
    bool rulesFired = true;
    int iterations = 0;

    while (rulesFired && iterations < _maxIterations) {
      rulesFired = false;
      iterations++;

      for (final rule in rules) {
        final result = _evaluateRule(rule, workingMemory);

        if (result.fired) {
          rulesFired = true;
          trace.add(result);

          // Apply conclusions to working memory
          for (final conclusion in rule.conclusions) {
            final existingFact = workingMemory[conclusion.factId];

            if (existingFact != null) {
              // Combine CFs if fact already exists
              final combinedCF = CertaintyFactorCalculator.combine(
                existingFact.certaintyFactor,
                conclusion.cf,
              );
              workingMemory[conclusion.factId] = ClinicalFact(
                factId: conclusion.factId,
                value: conclusion.value,
                certaintyFactor: combinedCF,
                explanation:
                    '${existingFact.explanation} + ${conclusion.explanation}',
              );
            } else {
              // Create new fact
              workingMemory[conclusion.factId] = ClinicalFact(
                factId: conclusion.factId,
                value: conclusion.value,
                certaintyFactor: conclusion.cf,
                explanation: conclusion.explanation,
              );
            }
          }
        }
      }
    }

    // Determine final diagnosis from working memory
    return _buildResult(workingMemory, trace);
  }

  /// Calculate total scores and add to working memory.
  void _calculateTotalScores(
    Map<String, ClinicalFact> workingMemory,
    List<String> questionIds,
    String prefix,
    String questionPrefix,
  ) {
    int total = 0;
    double totalCF = 0.0;
    int count = 0;

    for (final questionId in questionIds) {
      if (questionId.startsWith(questionPrefix)) {
        final fact = workingMemory[questionId];
        if (fact != null) {
          total += fact.value as int;
          totalCF += fact.certaintyFactor;
          count++;
        }
      }
    }

    if (count > 0) {
      final avgCF = totalCF / count;

      workingMemory['${prefix}_total_score'] = ClinicalFact(
        factId: '${prefix}_total_score',
        value: total,
        certaintyFactor: avgCF,
        explanation: 'Total skor $prefix: $total dari $count item',
      );
    }
  }

  /// Evaluate a single rule against working memory.
  RuleFiredTrace _evaluateRule(
    ScreeningRule rule,
    Map<String, ClinicalFact> workingMemory,
  ) {
    final satisfiedConditions = <String>[];
    final failedConditions = <String>[];
    final conditionCFs = <double>[];

    for (final condition in rule.conditions) {
      final fact = workingMemory[condition.factId];

      if (fact == null) {
        failedConditions.add(
          '${condition.factId}: fact not found in working memory',
        );
        conditionCFs.add(0.0);
        continue;
      }

      final conditionMet = _evaluateCondition(condition, fact);
      final conditionCF = conditionMet ? fact.certaintyFactor : 0.0;

      conditionCFs.add(conditionCF);

      if (conditionMet && conditionCF >= condition.minCF) {
        satisfiedConditions.add(
          '${condition.factId} ${condition.operator.symbol} ${condition.value} '
          '(CF=${conditionCF.toStringAsFixed(3)})',
        );
      } else {
        failedConditions.add(
          '${condition.factId} ${condition.operator.symbol} ${condition.value} '
          '(CF=${conditionCF.toStringAsFixed(3)}, min=${condition.minCF})',
        );
      }
    }

    // Rule fires only if ALL conditions are satisfied
    final allSatisfied = failedConditions.isEmpty;
    final combinedConditionsCF =
        CertaintyFactorCalculator.combineConditions(conditionCFs);
    final resultCF = allSatisfied
        ? CertaintyFactorCalculator.applyRuleCF(
            rule.ruleCF, combinedConditionsCF)
        : 0.0;

    return RuleFiredTrace(
      rule: rule,
      fired: allSatisfied,
      conditionCF: combinedConditionsCF,
      resultCF: resultCF,
      satisfiedConditions: satisfiedConditions,
      failedConditions: failedConditions,
    );
  }

  /// Evaluate a single condition against a fact.
  bool _evaluateCondition(RuleCondition condition, ClinicalFact fact) {
    final factValue = fact.value;
    final conditionValue = condition.value;

    // Handle different types of comparisons
    if (factValue is int && conditionValue is int) {
      return _compareInt(factValue, condition.operator, conditionValue);
    } else if (factValue is double && conditionValue is double) {
      return _compareDouble(factValue, condition.operator, conditionValue);
    } else if (factValue is String && conditionValue is String) {
      return _compareString(factValue, condition.operator, conditionValue);
    } else if (factValue is bool && conditionValue is bool) {
      return factValue == conditionValue;
    }

    // Default: try to compare as strings
    return factValue.toString() == conditionValue.toString();
  }

  bool _compareInt(int value, ConditionOperator op, int target) {
    switch (op) {
      case ConditionOperator.equals:
        return value == target;
      case ConditionOperator.notEquals:
        return value != target;
      case ConditionOperator.greaterThan:
        return value > target;
      case ConditionOperator.greaterOrEqual:
        return value >= target;
      case ConditionOperator.lessThan:
        return value < target;
      case ConditionOperator.lessOrEqual:
        return value <= target;
      case ConditionOperator.contains:
        return value.toString().contains(target.toString());
    }
  }

  bool _compareDouble(double value, ConditionOperator op, double target) {
    switch (op) {
      case ConditionOperator.equals:
        return (value - target).abs() < 0.001;
      case ConditionOperator.notEquals:
        return (value - target).abs() >= 0.001;
      case ConditionOperator.greaterThan:
        return value > target;
      case ConditionOperator.greaterOrEqual:
        return value >= target;
      case ConditionOperator.lessThan:
        return value < target;
      case ConditionOperator.lessOrEqual:
        return value <= target;
      case ConditionOperator.contains:
        return value.toString().contains(target.toString());
    }
  }

  bool _compareString(String value, ConditionOperator op, String target) {
    switch (op) {
      case ConditionOperator.equals:
        return value.toLowerCase() == target.toLowerCase();
      case ConditionOperator.notEquals:
        return value.toLowerCase() != target.toLowerCase();
      case ConditionOperator.greaterThan:
        return value.compareTo(target) > 0;
      case ConditionOperator.greaterOrEqual:
        return value.compareTo(target) >= 0;
      case ConditionOperator.lessThan:
        return value.compareTo(target) < 0;
      case ConditionOperator.lessOrEqual:
        return value.compareTo(target) <= 0;
      case ConditionOperator.contains:
        return value.toLowerCase().contains(target.toLowerCase());
    }
  }

  /// Build the final inference result from working memory.
  InferenceResult _buildResult(
    Map<String, ClinicalFact> workingMemory,
    List<RuleFiredTrace> trace,
  ) {
    // Check for crisis first (highest priority)
    final crisisFlag = workingMemory['crisis_flag'];
    if (crisisFlag != null && crisisFlag.value == true) {
      final crisisLevel = workingMemory['crisis_level'];
      return InferenceResult(
        level: 'crisis',
        certaintyFactor: crisisFlag.certaintyFactor,
        summary: crisisLevel?.value as String? ??
            'Ada indikator keselamatan diri. Tampilkan crisis flow dan hubungi profesional.',
        isCrisis: true,
        trace: trace,
        workingMemory: Map.unmodifiable(workingMemory),
      );
    }

    // Get depression and anxiety levels
    final depressionLevel = workingMemory['depression_level'];
    final anxietyLevel = workingMemory['anxiety_level'];

    // Determine overall level (highest severity)
    String finalLevel;
    double finalCF;
    String summary;

    final levelPriority = {
      'minimal': 0,
      'mild': 1,
      'moderate': 2,
      'severe': 3,
      'crisis': 4,
    };

    final depPriority = levelPriority[depressionLevel?.value] ?? 0;
    final anxPriority = levelPriority[anxietyLevel?.value] ?? 0;

    if (depPriority >= anxPriority) {
      finalLevel = depressionLevel?.value as String? ?? 'minimal';
      finalCF = depressionLevel?.certaintyFactor ?? 0.0;
      summary = depressionLevel?.explanation ?? 'Gejala depresi minimal.';
    } else {
      finalLevel = anxietyLevel?.value as String? ?? 'minimal';
      finalCF = anxietyLevel?.certaintyFactor ?? 0.0;
      summary = anxietyLevel?.explanation ?? 'Gejala kecemasan minimal.';
    }

    // Build combined summary
    final depSummary = workingMemory['depression_summary']?.value;
    final anxSummary = workingMemory['anxiety_summary']?.value;
    if (depSummary != null && anxSummary != null) {
      summary = '$depSummary $anxSummary';
    } else if (depSummary != null) {
      summary = depSummary as String;
    } else if (anxSummary != null) {
      summary = anxSummary as String;
    }

    return InferenceResult(
      level: finalLevel,
      certaintyFactor: finalCF,
      summary: summary,
      isCrisis: false,
      trace: trace,
      workingMemory: Map.unmodifiable(workingMemory),
    );
  }
}
