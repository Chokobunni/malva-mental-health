import '../../ai/assessment_interpretation.dart';
import '../../assessment_engine.dart';
import '../../models.dart';
import '../../services/malva_api_client.dart';
import '../../time/wib.dart';
import '../../widgets/therapy_library.dart';

// ============================================================
// ASESMEN WEB — LAPISAN DATA & SKOR
// ============================================================
//
// Seluruh perhitungan MEMAKAI ULANG mesin yang sudah ada (read-only):
//   - PHQ-9 / GAD-7 : AssessmentEngine.score() → Forward Chaining + Certainty
//                     Factor (lib/src/assessment_engine.dart).
//   - DASS-21       : scoreDass21() + dassRangesFor() + interpretDassWho5()
//   - WHO-5         : scoreWho5() + who5Ranges + interpretDassWho5()
//
// Tidak ada rumus baru di sini dan tidak ada perubahan pada mesin tersebut,
// sehingga hasil web identik dengan mobile untuk jawaban yang sama.

/// Instrumen asesmen yang tersedia di web.
enum WebAssessmentInstrument {
  /// PHQ-9 + GAD-7 (backend hanya menerima keduanya sekaligus).
  screening,

  /// DASS-21 (21 item, tiga subskala).
  dass21,

  /// WHO-5 (5 item kesejahteraan).
  who5,
}

/// Metadata instrumen untuk hub, runner, dan riwayat.
extension WebAssessmentInstrumentInfo on WebAssessmentInstrument {
  String get title => switch (this) {
        WebAssessmentInstrument.screening => 'PHQ-9 + GAD-7',
        WebAssessmentInstrument.dass21 => 'DASS-21',
        WebAssessmentInstrument.who5 => 'WHO-5',
      };

  String get shortTitle => switch (this) {
        WebAssessmentInstrument.screening => 'PHQ-9 / GAD-7',
        WebAssessmentInstrument.dass21 => 'DASS-21',
        WebAssessmentInstrument.who5 => 'WHO-5',
      };

  String get description => switch (this) {
        WebAssessmentInstrument.screening =>
          'Skrining gejala depresi (9 soal) dan kecemasan (7 soal) dalam dua '
              'minggu terakhir. Hasil dikirim ke server agar bisa ditinjau '
              'profesional.',
        WebAssessmentInstrument.dass21 =>
          'Mengukur tiga area sekaligus — depresi, kecemasan, dan stres — '
              'masing-masing 0–42 berdasarkan pengalaman seminggu terakhir.',
        WebAssessmentInstrument.who5 =>
          'Lima pertanyaan singkat tentang kesejahteraan dalam dua minggu '
              'terakhir. Skor 0–25, persentase = skor × 4.',
      };

  int get itemCount => switch (this) {
        WebAssessmentInstrument.screening => 16,
        WebAssessmentInstrument.dass21 => 21,
        WebAssessmentInstrument.who5 => 5,
      };

  int get estimatedMinutes => switch (this) {
        WebAssessmentInstrument.screening => 5,
        WebAssessmentInstrument.dass21 => 8,
        WebAssessmentInstrument.who5 => 2,
      };

  /// `module_id` untuk `POST /v1/therapy-submissions` (kosong untuk screening
  /// yang memakai `POST /v1/screenings`).
  String get moduleId => switch (this) {
        WebAssessmentInstrument.screening => '',
        WebAssessmentInstrument.dass21 => 'dass21',
        WebAssessmentInstrument.who5 => 'who5',
      };

  /// True bila instrumen disimpan sebagai therapy submission (bisa dibagikan).
  bool get canShare => this != WebAssessmentInstrument.screening;
}

/// Satu baris skor pada layar hasil.
class WebAssessmentScoreCard {
  const WebAssessmentScoreCard({
    required this.title,
    required this.scoreText,
    required this.level,
    this.certaintyPercent,
    this.note,
    this.reasons = const <String>[],
  });

  final String title;

  /// Teks skor siap tampil, mis. `12/27` atau `10/25 (40%)`.
  final String scoreText;

  /// Label tingkat keparahan dari instrumen (mis. `Sedang`).
  final String level;

  /// Keyakinan mesin inferensi untuk baris ini (0–100), bila ada.
  final int? certaintyPercent;

  /// Catatan/anjuran singkat dari tabel rentang.
  final String? note;

  /// Rule/alasan yang menembak (maksimal beberapa baris).
  final List<String> reasons;
}

/// Hasil lengkap satu sesi asesmen di web.
class WebAssessmentOutcome {
  const WebAssessmentOutcome({
    required this.instrument,
    required this.createdAt,
    required this.crisisFlag,
    required this.triageLabel,
    required this.certaintyPercent,
    required this.reasons,
    required this.cards,
    required this.summaryText,
    this.screeningBundle,
    this.therapyAnswers,
  });

  final WebAssessmentInstrument instrument;

  /// Waktu skor dibuat (WIB).
  final DateTime createdAt;

  /// True bila ada indikator keselamatan diri (PHQ-9 item 9 / rule krisis).
  final bool crisisFlag;

  /// Label triage gabungan (`Minimal`..`Krisis` untuk screening; hasil
  /// interpretasi DASS/WHO-5 untuk instrumen lain).
  final String triageLabel;

  /// Keyakinan triage gabungan (0–100).
  final int certaintyPercent;

  /// Alasan/rule yang menembak, siap dibaca pengguna.
  final List<String> reasons;

  /// Rincian per instrumen/subskala.
  final List<WebAssessmentScoreCard> cards;

  /// Ringkasan teks yang disimpan ke server (format sama dengan mobile).
  final String summaryText;

  /// Terisi hanya untuk [WebAssessmentInstrument.screening].
  final ScreeningBundle? screeningBundle;

  /// Terisi hanya untuk DASS-21 / WHO-5 (termasuk penanda `scale_version`).
  final Map<String, dynamic>? therapyAnswers;
}

/// Satu pertanyaan pada runner.
class WebAssessmentItem {
  const WebAssessmentItem({
    required this.number,
    required this.label,
    required this.shortLabels,
    required this.fullLabels,
    this.minValue = 0,
    this.maxValue = 3,
    this.sectionTitle,
  });

  /// Nomor urut yang tampil (1-based, lintas seksi).
  final String number;
  final String label;

  /// Label pendek pada tombol pilihan (mis. `0`..`3` atau `Sering`).
  final List<String> shortLabels;

  /// Makna lengkap tiap nilai — dipakai sebagai tooltip.
  final List<String> fullLabels;
  final int minValue;
  final int maxValue;

  /// Judul seksi; hanya terisi pada item pertama tiap seksi.
  final String? sectionTitle;

  /// Semua nilai skala yang mungkin, urut.
  List<int> get values =>
      List<int>.generate(maxValue - minValue + 1, (int i) => minValue + i);

  /// Tooltip untuk nilai [value].
  String tooltipFor(int value) {
    final index = value - minValue;
    if (index < 0 || index >= fullLabels.length) return '$value';
    return fullLabels[index];
  }

  /// Label pendek untuk nilai [value].
  String shortLabelFor(int value) {
    final index = value - minValue;
    if (index < 0 || index >= shortLabels.length) return '$value';
    return shortLabels[index];
  }
}

/// Daftar pertanyaan untuk [instrument].
///
/// PHQ-9 dan GAD-7 digabung menjadi 16 soal dengan dua seksi jelas karena
/// `POST /v1/screenings` mewajibkan keduanya terkirim bersamaan.
List<WebAssessmentItem> webAssessmentItems(WebAssessmentInstrument instrument) {
  switch (instrument) {
    case WebAssessmentInstrument.screening:
      final items = <WebAssessmentItem>[];
      var number = 0;
      for (final AssessmentQuestion question
          in AssessmentEngine.phq9Questions) {
        number++;
        items.add(
          WebAssessmentItem(
            number: '$number',
            label: question.label,
            shortLabels: AssessmentEngine.responseLabels,
            fullLabels: AssessmentEngine.responseDescriptions,
            sectionTitle:
                number == 1 ? 'PHQ-9 · 9 pertanyaan · 2 minggu terakhir' : null,
          ),
        );
      }
      for (final AssessmentQuestion question
          in AssessmentEngine.gad7Questions) {
        number++;
        items.add(
          WebAssessmentItem(
            number: '$number',
            label: question.label,
            shortLabels: AssessmentEngine.responseLabels,
            fullLabels: AssessmentEngine.responseDescriptions,
            sectionTitle: number == 10
                ? 'GAD-7 · 7 pertanyaan · 2 minggu terakhir'
                : null,
          ),
        );
      }
      return items;
    case WebAssessmentInstrument.dass21:
      return _itemsFromWorksheet(
        dass21WorksheetFields,
        sectionTitle: 'DASS-21 · 21 pernyataan · seminggu terakhir',
      );
    case WebAssessmentInstrument.who5:
      return _itemsFromWorksheet(
        who5WorksheetFields,
        sectionTitle: 'WHO-5 · 5 pertanyaan · 2 minggu terakhir',
      );
  }
}

List<WebAssessmentItem> _itemsFromWorksheet(
  List<TherapyWorksheetField> fields, {
  required String sectionTitle,
}) {
  var number = 0;
  return fields.map((TherapyWorksheetField field) {
    number++;
    final min = field.minValue ?? 0;
    final max = field.maxValue ?? 0;
    return WebAssessmentItem(
      number: number.toString(),
      label: field.label,
      minValue: min,
      maxValue: max,
      shortLabels: field.scaleShortLabels.isNotEmpty
          ? field.scaleShortLabels
          : field.scaleLabels,
      fullLabels: field.scaleLabels.isNotEmpty
          ? field.scaleLabels
          : field.scaleShortLabels,
      sectionTitle: number == 1 ? sectionTitle : null,
    );
  }).toList(growable: false);
}

/// Peta jawaban DASS-21/WHO-5 ke format `answers` server.
///
/// `scale_version = 2` WAJIB ikut: tanpa penanda itu, `scoreDass21`/`scoreWho5`
/// menganggap data lama (1-based) dan menggeser skor klinis.
Map<String, dynamic> webTherapyAnswers(
  WebAssessmentInstrument instrument,
  List<int> answers,
) {
  final map = <String, dynamic>{};
  for (var i = 0; i < answers.length; i++) {
    map['q${i + 1}'] = answers[i];
  }
  map[scaleVersionKey] = standardizedScaleVersion;
  map[scaleMinKey] = 0;
  map[scaleMaxKey] = instrument == WebAssessmentInstrument.who5 ? 5 : 3;
  return map;
}

/// Skor PHQ-9 + GAD-7 memakai `AssessmentEngine` (Forward Chaining + CF).
WebAssessmentOutcome buildScreeningOutcome({
  required List<int> phq9Answers,
  required List<int> gad7Answers,
  required DateTime createdAt,
}) {
  final phq9 = AssessmentEngine.score(
    type: AssessmentType.phq9,
    answers: phq9Answers,
  );
  final gad7 = AssessmentEngine.score(
    type: AssessmentType.gad7,
    answers: gad7Answers,
  );
  final bundle = ScreeningBundle(
    id: '',
    phq9: phq9,
    gad7: gad7,
    createdAt: createdAt,
    isInitial: false,
    source: 'web',
  );
  final certainty = phq9.certaintyFactor >= gad7.certaintyFactor
      ? phq9.certaintyFactor
      : gad7.certaintyFactor;
  final reasons = <String>[
    ...phq9.rulesFired.map((RuleTrace rule) => 'PHQ-9: ${rule.label}'),
    ...gad7.rulesFired.map((RuleTrace rule) => 'GAD-7: ${rule.label}'),
  ];
  return WebAssessmentOutcome(
    instrument: WebAssessmentInstrument.screening,
    createdAt: createdAt,
    crisisFlag: bundle.crisisFlag,
    triageLabel: bundle.overallLevel.label,
    certaintyPercent: (certainty.clamp(0.0, 1.0) * 100).round(),
    reasons: reasons,
    summaryText: bundle.summary,
    screeningBundle: bundle,
    cards: <WebAssessmentScoreCard>[
      WebAssessmentScoreCard(
        title: 'PHQ-9 · depresi',
        scoreText: '${phq9.score}/${phq9.maxScore}',
        level: phq9.level.label,
        certaintyPercent: (phq9.certaintyFactor.clamp(0.0, 1.0) * 100).round(),
        note: '9 pertanyaan · 2 minggu terakhir',
        reasons: phq9.rulesFired
            .map((RuleTrace rule) => rule.label)
            .toList(growable: false),
      ),
      WebAssessmentScoreCard(
        title: 'GAD-7 · kecemasan',
        scoreText: '${gad7.score}/${gad7.maxScore}',
        level: gad7.level.label,
        certaintyPercent: (gad7.certaintyFactor.clamp(0.0, 1.0) * 100).round(),
        note: '7 pertanyaan · 2 minggu terakhir',
        reasons: gad7.rulesFired
            .map((RuleTrace rule) => rule.label)
            .toList(growable: false),
      ),
    ],
  );
}

/// Skor DASS-21: tiga subskala (0–42) + interpretasi triage (CF + alasan).
WebAssessmentOutcome buildDass21Outcome({
  required List<int> answers,
  required DateTime createdAt,
}) {
  final map = webTherapyAnswers(WebAssessmentInstrument.dass21, answers);
  final score = scoreDass21(map);
  final interpretation = interpretDassWho5(answers: map, moduleId: 'dass21');
  return WebAssessmentOutcome(
    instrument: WebAssessmentInstrument.dass21,
    createdAt: createdAt,
    crisisFlag: interpretation.triageLevel == 'krisis',
    triageLabel: interpretation.triageLabel,
    certaintyPercent: interpretation.certaintyPercent,
    reasons: interpretation.reasons,
    summaryText: dass21Summary(map),
    therapyAnswers: map,
    cards: <WebAssessmentScoreCard>[
      _dassCard(
          'Depresi', score.depression, score.depressionLevel, 'depression'),
      _dassCard('Kecemasan', score.anxiety, score.anxietyLevel, 'anxiety'),
      _dassCard('Stres', score.stress, score.stressLevel, 'stress'),
    ],
  );
}

WebAssessmentScoreCard _dassCard(
  String title,
  int score,
  String level,
  String subscale,
) {
  final rows = dassRangesFor(subscale);
  final row = rows.firstWhere(
    (ScoreRangeRow candidate) => candidate.contains(score),
    orElse: () => rows.last,
  );
  return WebAssessmentScoreCard(
    title: title,
    scoreText: '$score/42',
    level: level,
    note: '${row.rangeLabel} · ${row.advice}',
  );
}

/// Skor WHO-5: raw 0–25, persen = raw × 4, plus interpretasi triage.
WebAssessmentOutcome buildWho5Outcome({
  required List<int> answers,
  required DateTime createdAt,
}) {
  final map = webTherapyAnswers(WebAssessmentInstrument.who5, answers);
  final score = scoreWho5(map);
  final interpretation = interpretDassWho5(answers: map, moduleId: 'who5');
  final row = who5Ranges.firstWhere(
    (ScoreRangeRow candidate) => candidate.contains(score.raw),
    orElse: () => who5Ranges.last,
  );
  return WebAssessmentOutcome(
    instrument: WebAssessmentInstrument.who5,
    createdAt: createdAt,
    crisisFlag: interpretation.triageLevel == 'krisis',
    triageLabel: interpretation.triageLabel,
    certaintyPercent: interpretation.certaintyPercent,
    reasons: interpretation.reasons,
    summaryText: who5Summary(map),
    therapyAnswers: map,
    cards: <WebAssessmentScoreCard>[
      WebAssessmentScoreCard(
        title: 'Kesejahteraan (WHO-5)',
        scoreText: '${score.raw}/25 (${score.percent}%)',
        level: score.level,
        certaintyPercent: interpretation.certaintyPercent,
        note: '${row.rangeLabel} · ${row.advice}',
      ),
    ],
  );
}

/// Instrumen dari `module_id` therapy submission (untuk riwayat).
WebAssessmentInstrument? webInstrumentForModuleId(String moduleId) {
  return switch (moduleId) {
    'dass21' => WebAssessmentInstrument.dass21,
    'who5' => WebAssessmentInstrument.who5,
    _ => null,
  };
}

/// Satu baris riwayat asesmen (gabungan screening + therapy submission).
class WebAssessmentHistoryEntry {
  const WebAssessmentHistoryEntry({
    required this.id,
    required this.instrument,
    required this.createdAt,
    required this.scoreText,
    required this.level,
    required this.certaintyPercent,
    this.sharedWithProfessionalId,
    this.reasons = const <String>[],
    this.isScreening = false,
  });

  final String id;
  final WebAssessmentInstrument instrument;
  final DateTime? createdAt;
  final String scoreText;
  final String level;
  final int certaintyPercent;

  /// Terisi bila hasil sudah dibagikan ke profesional.
  final String? sharedWithProfessionalId;
  final List<String> reasons;

  /// True bila baris berasal dari `POST /v1/screenings` (PHQ-9 + GAD-7).
  final bool isScreening;

  bool get shared => (sharedWithProfessionalId ?? '').isNotEmpty;
}

/// Label Indonesia dari kode level server (`minimal`, `mild`, ...).
String webRiskLevelLabel(String code) => switch (code.toLowerCase()) {
      'minimal' => 'Minimal',
      'mild' => 'Ringan',
      'moderate' => 'Sedang',
      'moderately_severe' => 'Cukup Berat',
      'severe' => 'Berat',
      'crisis' => 'Krisis',
      _ => code.isEmpty ? '—' : code,
    };

/// Riwayat dari satu sesi screening server (PHQ-9 + GAD-7).
WebAssessmentHistoryEntry webHistoryFromScreening(
  BackendScreeningSession session,
) {
  final cf = session.phq9.certaintyFactor >= session.gad7.certaintyFactor
      ? session.phq9.certaintyFactor
      : session.gad7.certaintyFactor;
  return WebAssessmentHistoryEntry(
    id: session.id,
    instrument: WebAssessmentInstrument.screening,
    createdAt: session.createdAt,
    scoreText: 'PHQ-9 ${session.phq9.score}/${session.phq9.maxScore} · '
        'GAD-7 ${session.gad7.score}/${session.gad7.maxScore}',
    level: webRiskLevelLabel(session.overallLevel),
    certaintyPercent: (cf.clamp(0.0, 1.0) * 100).round(),
    reasons: <String>[
      if (session.phq9.ruleTrace.isNotEmpty) 'PHQ-9: ${session.phq9.ruleTrace}',
      if (session.gad7.ruleTrace.isNotEmpty) 'GAD-7: ${session.gad7.ruleTrace}',
    ],
    isScreening: true,
  );
}

/// Riwayat dari satu therapy submission (DASS-21 / WHO-5).
///
/// Mengembalikan `null` untuk modul lain (mis. worksheet terapi biasa) karena
/// bukan asesmen. Skor dihitung ulang dari `answers` memakai mesin yang sama,
/// sehingga data lama (tanpa `scale_version`) tetap terbaca benar.
WebAssessmentHistoryEntry? webHistoryFromTherapy(
  BackendTherapySubmission submission,
) {
  final instrument = webInstrumentForModuleId(submission.moduleId);
  if (instrument == null) return null;
  final answers = submission.answers;
  final DateTime? createdAt = parseWibStored(submission.createdAt);
  if (instrument == WebAssessmentInstrument.dass21) {
    final score = scoreDass21(answers);
    final interpretation =
        interpretDassWho5(answers: answers, moduleId: 'dass21');
    return WebAssessmentHistoryEntry(
      id: submission.id,
      instrument: instrument,
      createdAt: createdAt,
      scoreText: 'Depresi ${score.depression} · Kecemasan ${score.anxiety} · '
          'Stres ${score.stress} (dari 42)',
      level: _highestDassLevel(score),
      certaintyPercent: interpretation.certaintyPercent,
      sharedWithProfessionalId: submission.sharedWithProfessionalId,
      reasons: interpretation.reasons,
    );
  }
  final score = scoreWho5(answers);
  final interpretation = interpretDassWho5(answers: answers, moduleId: 'who5');
  return WebAssessmentHistoryEntry(
    id: submission.id,
    instrument: instrument,
    createdAt: createdAt,
    scoreText: '${score.raw}/25 (${score.percent}%)',
    level: score.level,
    certaintyPercent: interpretation.certaintyPercent,
    sharedWithProfessionalId: submission.sharedWithProfessionalId,
    reasons: interpretation.reasons,
  );
}

/// Tingkat keparahan tertinggi di antara tiga subskala DASS-21.
String _highestDassLevel(Dass21Score score) {
  final levels = <String>[
    score.depressionLevel,
    score.anxietyLevel,
    score.stressLevel,
  ];
  levels.sort(
    (String a, String b) => dassLevelRank(b).compareTo(dassLevelRank(a)),
  );
  return levels.first;
}
