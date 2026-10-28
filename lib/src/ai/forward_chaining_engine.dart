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

  /// Keandalan instrumen terstandar (PHQ-9/GAD-7) sebagai sumber bukti.
  /// Total skor berasal dari kuesioner baku & tervalidasi, sehingga CF-nya
  /// mencerminkan keandalan instrumen — bukan rata-rata jawaban pasien
  /// (yang akan mendilusi rule saat semua jawaban 0).
  static const double _instrumentCF = 0.95;

  /// CF bukti minimum untuk item keselamatan (PHQ-9 item 9).
  /// DSM-5: adanya ide menyakiti diri bermakna klinis apa pun
  /// frekuensinya, jadi CF bukti tidak boleh rendah.
  static const double _safetyEvidenceCF = 0.95;

  /// ID item keselamatan yang memakai CF floor di atas.
  static const String _selfHarmFactId = 'phq_self_harm';

  /// Run forward chaining inference on the given answers.
  ///
  /// This is the main entry point for the inference engine. It:
  /// 1. Converts patient answers to facts in working memory
  /// 2. Calculates total scores
  /// 3. Iteratively applies rules until no more fire
  /// 4. Returns the final inference result with audit trail
  ///
  /// Setiap rule hanya boleh menembak SEKALI (fire-once) sesuai kaidah
  /// forward chaining: menembak ulang rule yang sama akan menggabungkan
  /// CF yang sama berulang kali sehingga nilai konvergen ke 1.0.
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

      // Item keselamatan memakai CF floor (ide bermakna klinis).
      var cf = CertaintyFactorCalculator.scoreToCF(rawValue);
      if (questionId == _selfHarmFactId && rawValue > 0) {
        cf = _safetyEvidenceCF;
      }

      workingMemory[questionId] = ClinicalFact(
        factId: questionId,
        value: rawValue,
        certaintyFactor: cf,
        explanation: 'Jawaban langsung dari pasien (skor $rawValue)',
      );
    }

    // Calculate total scores
    _calculateTotalScores(workingMemory, questionIds, 'phq9', 'phq_');
    _calculateTotalScores(workingMemory, questionIds, 'gad7', 'gad_');

    // Run forward chaining
    final trace = <RuleFiredTrace>[];
    final firedRuleIds = <String>{};
    bool rulesFired = true;
    int iterations = 0;

    while (rulesFired && iterations < _maxIterations) {
      rulesFired = false;
      iterations++;

      for (final rule in rules) {
        // Fire-once: rule yang sudah menembak tidak dievaluasi ulang.
        if (firedRuleIds.contains(rule.id)) continue;

        final result = _evaluateRule(rule, workingMemory);

        if (result.fired) {
          rulesFired = true;
          firedRuleIds.add(rule.id);
          trace.add(result);

          // CF kesimpulan = CF(rule) x CF(bukti) — dihitung di _evaluateRule.
          final conclusionCF = result.resultCF;

          // Apply conclusions to working memory
          for (final conclusion in rule.conclusions) {
            final existingFact = workingMemory[conclusion.factId];

            if (existingFact != null) {
              // Combine CFs if fact already exists
              final combinedCF = CertaintyFactorCalculator.combine(
                existingFact.certaintyFactor,
                conclusionCF,
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
                certaintyFactor: conclusionCF,
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
  ///
  /// CF fakta total memakai keandalan instrumen (0.95) karena skor total
  /// adalah keluaran kuesioner baku, bukan keyakinan pasien per item.
  void _calculateTotalScores(
    Map<String, ClinicalFact> workingMemory,
    List<String> questionIds,
    String prefix,
    String questionPrefix,
  ) {
    int total = 0;
    int count = 0;

    for (final questionId in questionIds) {
      if (questionId.startsWith(questionPrefix)) {
        final fact = workingMemory[questionId];
        if (fact != null) {
          total += fact.value as int;
          count++;
        }
      }
    }

    if (count > 0) {
      workingMemory['${prefix}_total_score'] = ClinicalFact(
        factId: '${prefix}_total_score',
        value: total,
        certaintyFactor: _instrumentCF,
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

    // Rule hanya menembak bila SEMUA kondisi terpenuhi DAN ada bukti nyata
    // (CF gabungan > 0). Menembak dengan CF 0 hanya akan menulis fakta tanpa
    // keyakinan ke working memory dan mengotori audit trail.
    final combinedConditionsCF =
        CertaintyFactorCalculator.combineConditions(conditionCFs);
    final allSatisfied = failedConditions.isEmpty && combinedConditionsCF > 0;
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
    // Tentukan level keparahan dari skor total (depression_level / anxiety_level).
    // Ini TIDAK boleh di-override oleh crisis_flag — level keparahan dan flag
    // krisis adalah dua hal terpisah: level = seberapa parah gejala secara
    // keseluruhan, crisisFlag = apakah ada indikator keselamatan diri.
    final depressionLevel = workingMemory['depression_level'];
    final anxietyLevel = workingMemory['anxiety_level'];

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

    // Pilih instrumen yang BENAR-BENAR menghasilkan level.
    // Tanpa penjagaan ini, skor GAD-7 minimal (0-4) jatuh ke cabang depresi
    // yang tidak punya fakta sama sekali: CF menjadi 0 dan ringkasan salah
    // menyebut "gejala depresi" padahal yang diukur adalah kecemasan.
    if (depressionLevel != null &&
        (anxietyLevel == null || depPriority >= anxPriority)) {
      finalLevel = depressionLevel.value as String? ?? 'minimal';
      finalCF = depressionLevel.certaintyFactor;
      summary = depressionLevel.explanation;
    } else if (anxietyLevel != null) {
      finalLevel = anxietyLevel.value as String? ?? 'minimal';
      finalCF = anxietyLevel.certaintyFactor;
      summary = anxietyLevel.explanation;
    } else {
      // Tidak ada rule keparahan yang menembak (mis. data tidak lengkap).
      finalLevel = 'minimal';
      finalCF = 0.0;
      summary = 'Tidak ada level keparahan yang terbentuk dari jawaban.';
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

    // Krisis: crisis_flag dibuat oleh rule PHQ9_CRISIS_SELF_HARM bila item 9 > 0.
    // Ini menandai perlunya intervensi keselamatan, tetapi TIDAK mengubah
    // level keparahan — pasien dengan skor PHQ-9 7/27 + item 9 = 1 tetap
    // "mild" secara keparahan, namun flagged sebagai krisis karena ide
    // menyakiti diri memerlukan perhatian segera.
    bool isCrisis = false;
    final crisisFlag = workingMemory['crisis_flag'];
    // Deteksi memakai CF > 0 (bukan perbandingan nilai) agar sejalan dengan
    // implementasi server di backend/internal/inference dan tahan terhadap
    // perbedaan tipe nilai antar-engine (bool di Dart, string di Go).
    if (crisisFlag != null && crisisFlag.certaintyFactor > 0) {
      isCrisis = true;
      final crisisLevel = workingMemory['crisis_level'];
      final crisisSummary = crisisLevel?.value as String? ??
          'Ada indikator keselamatan diri. Tampilkan crisis flow dan hubungi profesional.';
      summary = '$summary $crisisSummary';
      if (crisisFlag.certaintyFactor > finalCF) {
        finalCF = crisisFlag.certaintyFactor;
      }
    }

    return InferenceResult(
      level: finalLevel,
      certaintyFactor: finalCF,
      summary: summary,
      isCrisis: isCrisis,
      trace: trace,
      workingMemory: Map.unmodifiable(workingMemory),
    );
  }
}
