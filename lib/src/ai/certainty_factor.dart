/// Certainty Factor (CF) calculation functions.
///
/// Implements the certainty factor model from expert systems theory.
/// CF ranges from -1.0 (definitely false) to 1.0 (definitely true).
///
/// References:
/// - Shortliffe, E.H. & Buchanan, B.G. (1975). "A Model of Inexact
///   Reasoning in Medicine." Mathematical Biosciences.
/// - Kerkhoffs, J. (2020). "Certainty Factors in Expert Systems."
///
/// The key formula for combining two CFs is:
///   If CF(A) >= 0 and CF(B) >= 0:
///     CF_combined = CF(A) + CF(B) * (1 - CF(A))
///   If CF(A) < 0 and CF(B) < 0:
///     CF_combined = CF(A) + CF(B) * (1 + CF(A))
///   If signs differ:
///     CF_combined = (CF(A) + CF(B)) / (1 - min(|CF(A)|, |CF(B)|))
class CertaintyFactorCalculator {
  /// Prevent instantiation of utility class.
  const CertaintyFactorCalculator._();

  /// Combine two Certainty Factors using the standard CF formula.
  ///
  /// This is the core operation in CF-based reasoning. When two pieces
  /// of evidence support the same hypothesis, their CFs are combined
  /// to produce a stronger (or weaker) overall confidence.
  ///
  /// Mathematical basis:
  /// - When both CFs are positive (both support the hypothesis):
  ///   The combined CF is higher than either individual CF, but never
  ///   reaches 1.0 unless one CF is already 1.0.
  ///
  /// - When both CFs are negative (both contradict the hypothesis):
  ///   The combined CF is more negative, but never reaches -1.0.
  ///
  /// - When CFs have opposite signs:
  ///   They partially cancel each other out.
  ///
  /// Parameters:
  ///   [cf1] - First certainty factor (-1.0 to 1.0)
  ///   [cf2] - Second certainty factor (-1.0 to 1.0)
  ///
  /// Returns:
  ///   Combined certainty factor (-1.0 to 1.0)
  ///
  /// Example:
  ///   CF(depression) = 0.6, CF(insomnia) = 0.4
  ///   Combined = 0.6 + 0.4 * (1 - 0.6) = 0.76
  static double combine(double cf1, double cf2) {
    // Clamp inputs to valid range
    cf1 = cf1.clamp(-1.0, 1.0);
    cf2 = cf2.clamp(-1.0, 1.0);

    // Case 1: Both CFs are positive (both support the hypothesis)
    if (cf1 >= 0 && cf2 >= 0) {
      return cf1 + cf2 * (1.0 - cf1);
    }

    // Case 2: Both CFs are negative (both contradict the hypothesis)
    if (cf1 < 0 && cf2 < 0) {
      return cf1 + cf2 * (1.0 + cf1);
    }

    // Case 3: CFs have opposite signs (partial cancellation)
    final double pos;
    final double neg;
    if (cf1 >= 0) {
      pos = cf1;
      neg = cf2;
    } else {
      pos = cf2;
      neg = cf1;
    }

    return (pos + neg) / (1.0 - pos.abs().clamp(0.0, 1.0).toDouble() *
        (pos.abs() < neg.abs() ? pos.abs() : neg.abs()));
  }

  /// Convert a raw symptom score (0-3) to a Certainty Factor.
  ///
  /// This mapping is based on clinical interpretation of PHQ-9/GAD-7:
  /// - 0 (Tidak sama sekali): No evidence → CF = 0.0
  /// - 1 (Beberapa hari): Weak evidence → CF = 0.3
  /// - 2 (Lebih dari separuh hari): Moderate evidence → CF = 0.6
  /// - 3 (Hampir setiap hari): Strong evidence → CF = 0.9
  ///
  /// Parameters:
  ///   [rawScore] - Raw answer value (0-3)
  ///
  /// Returns:
  ///   Certainty Factor (0.0 to 0.9)
  static double scoreToCF(int rawScore) {
    switch (rawScore) {
      case 0:
        return 0.0;
      case 1:
        return 0.3;
      case 2:
        return 0.6;
      case 3:
        return 0.9;
      default:
        return 0.0;
    }
  }

  /// Combine the rule's reliability CF with the condition CFs.
  ///
  /// When a rule fires, its conclusion CF is the product of:
  /// - The rule's base reliability (from clinical literature)
  /// - The combined CF of all conditions being satisfied
  ///
  /// Parameters:
  ///   [ruleCF] - The rule's base reliability (0.0 to 1.0)
  ///   [conditionsCF] - Combined CF of all conditions
  ///
  /// Returns:
  ///   Final CF for the conclusion
  static double applyRuleCF(double ruleCF, double conditionsCF) {
    // Both must be positive for the rule to produce a positive conclusion
    // If conditions CF is negative, the rule doesn't support the conclusion
    if (conditionsCF <= 0) return 0.0;

    return ruleCF * conditionsCF;
  }

  /// Calculate the combined CF of multiple conditions (AND logic).
  ///
  /// For AND conditions, we combine CFs sequentially. All conditions
  /// must have positive CF (be satisfied) for the rule to fire.
  ///
  /// Parameters:
  ///   [conditionCFs] - List of CFs from individual conditions
  ///
  /// Returns:
  ///   Combined CF representing all conditions together
  static double combineConditions(List<double> conditionCFs) {
    if (conditionCFs.isEmpty) return 0.0;

    // Filter out negative CFs (failed conditions)
    final positiveCFs = conditionCFs.where((cf) => cf > 0).toList();
    if (positiveCFs.isEmpty) return 0.0;

    // Combine sequentially
    double result = positiveCFs.first;
    for (int i = 1; i < positiveCFs.length; i++) {
      result = combine(result, positiveCFs[i]);
    }
    return result;
  }

  /// Normalize a CF to a 0-1 scale for display purposes.
  ///
  /// This maps the -1.0 to 1.0 range to 0.0 to 1.0 for UI display.
  ///
  /// Parameters:
  ///   [cf] - Raw CF value (-1.0 to 1.0)
  ///
  /// Returns:
  ///   Normalized value (0.0 to 1.0)
  static double normalize(double cf) {
    return (cf + 1.0) / 2.0;
  }

  /// Get a human-readable label for a CF value.
  ///
  /// Parameters:
  ///   [cf] - Certainty Factor (-1.0 to 1.0)
  ///
  /// Returns:
  ///   Descriptive label in Indonesian
  static String labelFor(double cf) {
    final normalized = normalize(cf);
    if (normalized < 0.2) return 'Sangat Tidak Pasti';
    if (normalized < 0.4) return 'Tidak Pasti';
    if (normalized < 0.6) return 'Cukup Pasti';
    if (normalized < 0.8) return 'Pasti';
    return 'Sangat Pasti';
  }
}
