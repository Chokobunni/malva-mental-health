import 'models.dart';

enum AssessmentType { phq9, gad7 }

extension AssessmentTypeText on AssessmentType {
  String get title => switch (this) {
        AssessmentType.phq9 => 'PHQ-9',
        AssessmentType.gad7 => 'GAD-7',
      };

  String get subtitle => switch (this) {
        AssessmentType.phq9 =>
          'Screening gejala depresi dalam 2 minggu terakhir',
        AssessmentType.gad7 =>
          'Screening gejala kecemasan dalam 2 minggu terakhir',
      };
}

class AssessmentQuestion {
  const AssessmentQuestion({
    required this.id,
    required this.label,
    required this.domain,
  });

  final String id;
  final String label;
  final String domain;
}

class RuleTrace {
  const RuleTrace({
    required this.id,
    required this.label,
    required this.level,
  });

  final String id;
  final String label;
  final RiskLevel level;
}

class AssessmentResult {
  const AssessmentResult({
    required this.type,
    required this.score,
    required this.maxScore,
    required this.level,
    required this.summary,
    required this.crisisFlag,
    required this.rulesFired,
    required this.createdAt,
    required this.ruleVersion,
  });

  final AssessmentType type;
  final int score;
  final int maxScore;
  final RiskLevel level;
  final String summary;
  final bool crisisFlag;
  final List<RuleTrace> rulesFired;
  final DateTime createdAt;
  final String ruleVersion;
}

class ScreeningBundle {
  const ScreeningBundle({
    required this.id,
    required this.phq9,
    required this.gad7,
    required this.createdAt,
    required this.isInitial,
    required this.source,
  });

  final String id;
  final AssessmentResult phq9;
  final AssessmentResult gad7;
  final DateTime createdAt;
  final bool isInitial;
  final String source;

  bool get crisisFlag => phq9.crisisFlag || gad7.crisisFlag;

  RiskLevel get overallLevel {
    if (crisisFlag) return RiskLevel.crisis;
    final levels = [phq9.level, gad7.level];
    if (levels.contains(RiskLevel.severe)) return RiskLevel.severe;
    if (levels.contains(RiskLevel.moderate)) return RiskLevel.moderate;
    if (levels.contains(RiskLevel.mild)) return RiskLevel.mild;
    return RiskLevel.minimal;
  }

  String get summary {
    if (crisisFlag) {
      return 'Terdapat indikator keselamatan diri. Profesional perlu meninjau hasil ini sebagai prioritas.';
    }
    return 'PHQ-9 ${phq9.score}/${phq9.maxScore} (${phq9.level.label}) dan GAD-7 ${gad7.score}/${gad7.maxScore} (${gad7.level.label}).';
  }
}

class AssessmentEngine {
  const AssessmentEngine._();

  static const ruleVersion = '2026.1';

  static const responseLabels = [
    'Tidak sama sekali',
    'Beberapa hari',
    'Lebih dari separuh hari',
    'Hampir setiap hari',
  ];

  static const phq9Questions = [
    AssessmentQuestion(
      id: 'phq_interest',
      label: 'Minat atau rasa senang menurun',
      domain: 'mood',
    ),
    AssessmentQuestion(
      id: 'phq_low_mood',
      label: 'Mood sedih, murung, atau putus asa',
      domain: 'mood',
    ),
    AssessmentQuestion(
      id: 'phq_sleep',
      label: 'Pola tidur terganggu',
      domain: 'sleep',
    ),
    AssessmentQuestion(
      id: 'phq_energy',
      label: 'Energi rendah atau mudah lelah',
      domain: 'energy',
    ),
    AssessmentQuestion(
      id: 'phq_appetite',
      label: 'Perubahan nafsu makan',
      domain: 'appetite',
    ),
    AssessmentQuestion(
      id: 'phq_self_worth',
      label: 'Merasa gagal atau menyalahkan diri',
      domain: 'self_worth',
    ),
    AssessmentQuestion(
      id: 'phq_focus',
      label: 'Sulit berkonsentrasi',
      domain: 'focus',
    ),
    AssessmentQuestion(
      id: 'phq_motor',
      label: 'Gerak atau bicara melambat, atau gelisah',
      domain: 'motor',
    ),
    AssessmentQuestion(
      id: 'phq_self_harm',
      label: 'Pikiran menyakiti diri',
      domain: 'safety',
    ),
  ];

  static const gad7Questions = [
    AssessmentQuestion(
      id: 'gad_nervous',
      label: 'Merasa gugup, cemas, atau tegang',
      domain: 'anxiety',
    ),
    AssessmentQuestion(
      id: 'gad_control',
      label: 'Sulit menghentikan kekhawatiran',
      domain: 'worry',
    ),
    AssessmentQuestion(
      id: 'gad_worry',
      label: 'Terlalu banyak khawatir',
      domain: 'worry',
    ),
    AssessmentQuestion(
      id: 'gad_relax',
      label: 'Sulit rileks',
      domain: 'relaxation',
    ),
    AssessmentQuestion(
      id: 'gad_restless',
      label: 'Sulit diam karena gelisah',
      domain: 'restlessness',
    ),
    AssessmentQuestion(
      id: 'gad_irritable',
      label: 'Mudah kesal',
      domain: 'irritability',
    ),
    AssessmentQuestion(
      id: 'gad_fear',
      label: 'Takut sesuatu buruk terjadi',
      domain: 'fear',
    ),
  ];

  static List<AssessmentQuestion> questionsFor(AssessmentType type) {
    return switch (type) {
      AssessmentType.phq9 => phq9Questions,
      AssessmentType.gad7 => gad7Questions,
    };
  }

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

    final memory = _WorkingMemory(type: type, answers: answers);
    for (final rule in _rulesFor(type)) {
      if (rule.when(memory)) {
        rule.then(memory);
      }
    }

    return AssessmentResult(
      type: type,
      score: memory.total,
      maxScore: type == AssessmentType.phq9 ? 27 : 21,
      level: memory.level,
      summary: memory.summary,
      crisisFlag: memory.crisisFlag,
      rulesFired: List.unmodifiable(memory.traces),
      createdAt: DateTime.now(),
      ruleVersion: ruleVersion,
    );
  }

  static List<_ScreeningRule> _rulesFor(AssessmentType type) {
    return switch (type) {
      AssessmentType.phq9 => [
          _ScreeningRule(
            id: 'PHQ9_0_4',
            when: (m) => m.total <= 4,
            then: (m) => m.setLevel(
              RiskLevel.minimal,
              'Gejala depresi minimal. Pantau pola mood dan rutinitas.',
            ),
          ),
          _ScreeningRule(
            id: 'PHQ9_5_9',
            when: (m) => m.total >= 5 && m.total <= 9,
            then: (m) => m.setLevel(
              RiskLevel.mild,
              'Gejala ringan. Ulangi asesmen dan diskusikan bila menetap.',
            ),
          ),
          _ScreeningRule(
            id: 'PHQ9_10_14',
            when: (m) => m.total >= 10 && m.total <= 14,
            then: (m) => m.setLevel(
              RiskLevel.moderate,
              'Gejala sedang. Perlu review profesional dan rencana tindak lanjut.',
            ),
          ),
          _ScreeningRule(
            id: 'PHQ9_15_19',
            when: (m) => m.total >= 15 && m.total <= 19,
            then: (m) => m.setLevel(
              RiskLevel.severe,
              'Gejala cukup berat. Prioritaskan evaluasi profesional.',
            ),
          ),
          _ScreeningRule(
            id: 'PHQ9_20_27',
            when: (m) => m.total >= 20,
            then: (m) => m.setLevel(
              RiskLevel.severe,
              'Gejala berat. Butuh review klinis segera.',
            ),
          ),
          _ScreeningRule(
            id: 'PHQ9_ITEM_9_POSITIVE',
            when: (m) => m.answers[8] > 0,
            then: (m) => m.markCrisis(
              'Ada indikator keselamatan diri. Tampilkan crisis flow dan hubungi profesional.',
            ),
          ),
        ],
      AssessmentType.gad7 => [
          _ScreeningRule(
            id: 'GAD7_0_4',
            when: (m) => m.total <= 4,
            then: (m) => m.setLevel(
              RiskLevel.minimal,
              'Gejala kecemasan minimal. Lanjutkan pemantauan rutin.',
            ),
          ),
          _ScreeningRule(
            id: 'GAD7_5_9',
            when: (m) => m.total >= 5 && m.total <= 9,
            then: (m) => m.setLevel(
              RiskLevel.mild,
              'Gejala ringan. Ulangi asesmen pada follow-up.',
            ),
          ),
          _ScreeningRule(
            id: 'GAD7_10_14',
            when: (m) => m.total >= 10 && m.total <= 14,
            then: (m) => m.setLevel(
              RiskLevel.moderate,
              'Gejala sedang. Perlu evaluasi profesional.',
            ),
          ),
          _ScreeningRule(
            id: 'GAD7_15_21',
            when: (m) => m.total >= 15,
            then: (m) => m.setLevel(
              RiskLevel.severe,
              'Gejala berat. Prioritaskan review klinis dan rencana dukungan.',
            ),
          ),
        ],
    };
  }
}

class _WorkingMemory {
  _WorkingMemory({required this.type, required this.answers})
      : total = answers.fold<int>(0, (sum, value) => sum + value);

  final AssessmentType type;
  final List<int> answers;
  final int total;
  final List<RuleTrace> traces = [];
  RiskLevel level = RiskLevel.minimal;
  String summary = 'Belum ada rule yang terpenuhi.';
  bool crisisFlag = false;

  void setLevel(RiskLevel value, String message) {
    level = value;
    summary = message;
    traces.add(RuleTrace(
        id: '${type.title}_${value.name}', label: message, level: value));
  }

  void markCrisis(String message) {
    crisisFlag = true;
    level = RiskLevel.crisis;
    summary = message;
    traces.add(RuleTrace(
        id: '${type.title}_CRISIS', label: message, level: RiskLevel.crisis));
  }
}

class _ScreeningRule {
  const _ScreeningRule({
    required this.id,
    required this.when,
    required this.then,
  });

  final String id;
  final bool Function(_WorkingMemory memory) when;
  final void Function(_WorkingMemory memory) then;
}
