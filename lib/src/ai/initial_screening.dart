import 'assessment_scoring.dart';

/// Deterministic WHO-5 entry rules; these do not assign diagnostic certainty.
const initialScreeningRuleVersion = 'who5-entry-v1';

class InitialScreeningDecision {
  const InitialScreeningDecision({
    required this.rawScore,
    required this.percent,
    required this.needsFurtherScreening,
    required this.facts,
    required this.ruleTrace,
  });

  final int rawScore;
  final int percent;
  final bool needsFurtherScreening;
  final Map<String, Object> facts;
  final List<String> ruleTrace;
}

/// Every item must exist before deriving facts, so partial input cannot stop
/// screening through a fabricated zero or an inflated partial total.
InitialScreeningDecision inferInitialScreening(List<int?> answers) {
  if (answers.length != 5 ||
      answers.any((value) => value == null || value < 0 || value > 5)) {
    throw ArgumentError(
        'WHO-5 membutuhkan 5 jawaban lengkap dalam rentang 0–5.');
  }
  final score = scoreWho5({
    for (var i = 0; i < 5; i++) 'q${i + 1}': answers[i],
    scaleVersionKey: standardizedScaleVersion,
  });
  final facts = <String, Object>{
    'who5_raw': score.raw,
    'who5_percent': score.percent,
    'who5_percent_ge_50': score.percent >= 50,
    'who5_any_item_le_1': answers.any((value) => value! <= 1),
    'phq9_enabled': false,
    'gad7_enabled': false,
  };
  final trace = <String>[];
  final fired = <String>{};
  // Derived status is a new fact: R3 consumes it in the next inference pass.
  final rules = <({String id, bool Function() matches, void Function() apply})>[
    (
      id: 'R3',
      matches: () => facts['status'] == 'Butuh Skrining Lanjutan',
      apply: () {
        facts['phq9_enabled'] = true;
        facts['gad7_enabled'] = true;
      },
    ),
    (
      id: 'R2',
      matches: () =>
          facts['who5_percent_ge_50'] == false ||
          facts['who5_any_item_le_1'] == true,
      apply: () => facts['status'] = 'Butuh Skrining Lanjutan',
    ),
    (
      id: 'R1',
      matches: () =>
          facts['who5_percent_ge_50'] == true &&
          facts['who5_any_item_le_1'] == false,
      apply: () => facts['status'] = 'Kondisi Mental Sangat Baik',
    ),
  ];
  var changed = true;
  while (changed) {
    changed = false;
    for (final rule in rules) {
      if (fired.contains(rule.id) || !rule.matches()) continue;
      rule.apply();
      fired.add(rule.id);
      trace.add(rule.id);
      changed = true;
    }
  }
  return InitialScreeningDecision(
    rawScore: score.raw,
    percent: score.percent,
    needsFurtherScreening:
        facts['phq9_enabled'] == true && facts['gad7_enabled'] == true,
    facts: Map.unmodifiable(facts),
    ruleTrace: List.unmodifiable(trace),
  );
}
