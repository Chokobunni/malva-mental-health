/// Lapisan interpretasi pakar untuk hasil DASS-21 & WHO-5.
///
/// Memakai **Forward Chaining** sederhana + **Certainty Factor** (CF) untuk
/// menilai KEYAKINAN TRIAGE/RUJUKAN, bukan untuk mengubah skor.
///
/// ATURAN KERAS (jangan dilanggar):
/// 1. Skor instrumen tetap DETERMINISTIK — dihitung oleh
///    `ai/assessment_scoring.dart` (jumlah item x faktor, tanpa CF).
/// 2. Certainty Factor HANYA menyatakan seberapa yakin sistem menempatkan
///    pasien pada satu tingkat triage. CF tidak boleh menaikkan/menurunkan
///    skor maupun level subskala.
/// 3. Nada keluaran harus suportif, tanpa istilah menakutkan.
///
/// Alur penalaran:
///   fakta (level depresi/kecemasan/stres DASS + persen WHO-5)
///     → daftar rule yang terpenuhi (masing-masing punya CF dasar)
///     → pilih tingkat triage TERTINGGI yang tercapai
///     → gabungkan CF rule-rule pada tingkat itu dengan
///       `CertaintyFactorCalculator.combine` (bukti yang saling menguatkan
///       menaikkan keyakinan, tetapi tidak pernah melewati 1.0).
library;

import 'assessment_scoring.dart';
import 'certainty_factor.dart';

/// Versi kumpulan aturan; disimpan pada hasil agar dapat diaudit.
const String assessmentRuleVersion = 'dass21-who5-v1';

/// Tingkat triage yang mungkin keluar dari mesin inferensi.
enum TriageLevel {
  /// Tidak ada indikasi yang menonjol.
  rendah,

  /// Perlu pemantauan / konsultasi terjadwal.
  sedang,

  /// Perlu rujukan profesional segera.
  tinggi,

  /// Perlu bantuan segera (kombinasi gejala sangat berat).
  krisis,
}

/// Hasil interpretasi: tingkat triage + keyakinan + alasan yang bisa dibaca.
class AssessmentInterpretation {
  const AssessmentInterpretation({
    required this.triageLevel,
    required this.certaintyFactor,
    required this.reasons,
    required this.ruleVersion,
  });

  /// Salah satu dari 'rendah' | 'sedang' | 'tinggi' | 'krisis'.
  final String triageLevel;

  /// Keyakinan triage (0..1). BUKAN skor instrumen.
  final double certaintyFactor;

  /// Alasan singkat berbahasa Indonesia (maksimal 3).
  final List<String> reasons;

  /// Versi aturan yang dipakai.
  final String ruleVersion;

  /// Label tingkat triage untuk ditampilkan.
  String get triageLabel => switch (triageLevel) {
        'krisis' => 'Krisis',
        'tinggi' => 'Tinggi',
        'sedang' => 'Sedang',
        _ => 'Rendah',
      };

  /// Keyakinan dalam persen (0-100) untuk ditampilkan.
  int get certaintyPercent => (certaintyFactor.clamp(0.0, 1.0) * 100).round();

  /// Baris ringkas siap tampil, mis. "Interpretasi triage: Tinggi (CF 78%)".
  String get summaryLine =>
      'Interpretasi triage: $triageLabel (CF $certaintyPercent%)';

  /// Peringkat numerik tingkat triage (0 rendah .. 3 krisis).
  int get triageRank => _rankOf(triageLevel);

  static int _rankOf(String level) => switch (level) {
        'krisis' => 3,
        'tinggi' => 2,
        'sedang' => 1,
        _ => 0,
      };
}

/// Fakta yang dipakai mesin inferensi.
///
/// Hanya satu instrumen yang biasanya tersedia per submission (modul
/// `dass21` atau `who5`), sehingga rule yang membutuhkan dua instrumen
/// sekaligus hanya menembak bila datanya ada.
class _Facts {
  const _Facts({this.dass, this.who5});

  final Dass21Score? dass;
  final Who5Score? who5;

  String? get depressionLevel => dass?.depressionLevel;
  String? get anxietyLevel => dass?.anxietyLevel;
  String? get stressLevel => dass?.stressLevel;

  int get depressionRank =>
      dass == null ? 0 : dassLevelRank(dass!.depressionLevel);
  int get anxietyRank => dass == null ? 0 : dassLevelRank(dass!.anxietyLevel);
  int get stressRank => dass == null ? 0 : dassLevelRank(dass!.stressLevel);

  int? get who5Percent => who5?.percent;

  static _Facts from(Map<String, dynamic> answers, String moduleId) {
    if (moduleId == 'dass21') {
      return _Facts(dass: scoreDass21(answers));
    }
    if (moduleId == 'who5') {
      return _Facts(who5: scoreWho5(answers));
    }
    return const _Facts();
  }
}

/// Satu rule yang terpenuhi beserta CF dasar dan alasannya.
class _FiredRule {
  const _FiredRule({
    required this.level,
    required this.certainty,
    required this.reason,
  });

  final TriageLevel level;
  final double certainty;
  final String reason;
}

/// Interpretasi triage hasil DASS-21 / WHO-5 dengan forward chaining + CF.
///
/// [answers] memakai map jawaban submission (kunci `q1..q21` untuk DASS-21,
/// `q1..q5` untuk WHO-5, plus penanda `scale_version` bila tersedia).
/// [moduleId] menentukan instrumen yang dibaca ('dass21' atau 'who5').
AssessmentInterpretation interpretDassWho5({
  required Map<String, dynamic> answers,
  required String moduleId,
}) {
  final facts = _Facts.from(answers, moduleId);
  final fired = <_FiredRule>[];

  // ---------- Rule tingkat krisis ----------
  if (facts.depressionRank >= 4 &&
      facts.anxietyRank >= 4 &&
      facts.stressRank >= 4) {
    fired.add(const _FiredRule(
      level: TriageLevel.krisis,
      certainty: 0.90,
      reason: 'Ketiga area (depresi, kecemasan, stres) berada di rentang '
          'sangat berat — sebaiknya hubungi profesional atau layanan '
          'bantuan sekarang.',
    ));
  }

  // ---------- Rule tingkat tinggi ----------
  if (facts.depressionRank >= 4 || facts.anxietyRank >= 4) {
    fired.add(const _FiredRule(
      level: TriageLevel.tinggi,
      certainty: 0.86,
      reason: 'Skor depresi atau kecemasan berada di rentang sangat berat — '
          'sebaiknya segera bicara dengan profesional.',
    ));
  }
  if (facts.depressionLevel == 'Berat') {
    fired.add(const _FiredRule(
      level: TriageLevel.tinggi,
      certainty: 0.78,
      reason: 'Skor depresi berada di rentang berat — disarankan '
          'menjadwalkan konsultasi dengan profesional.',
    ));
  }
  if (facts.anxietyLevel == 'Berat') {
    fired.add(const _FiredRule(
      level: TriageLevel.tinggi,
      certainty: 0.70,
      reason: 'Skor kecemasan berada di rentang berat — disarankan '
          'menjadwalkan konsultasi dengan profesional.',
    ));
  }
  final who5Percent = facts.who5Percent;
  if (who5Percent != null && who5Percent <= 28) {
    fired.add(_FiredRule(
      level: TriageLevel.tinggi,
      certainty: 0.74,
      reason: 'Kesejahteraan (WHO-5) hanya $who5Percent% (≤ 28%) — tanda '
          'kemungkinan depresi, disarankan screening lanjutan.',
    ));
  }
  if (who5Percent != null && who5Percent <= 50 && facts.depressionRank >= 2) {
    fired.add(_FiredRule(
      level: TriageLevel.tinggi,
      certainty: 0.72,
      reason: 'Kesejahteraan rendah (WHO-5 $who5Percent%) disertai skor '
          'depresi sedang ke atas.',
    ));
  }

  // ---------- Rule tingkat sedang ----------
  if (facts.depressionLevel == 'Sedang' || facts.anxietyLevel == 'Sedang') {
    fired.add(const _FiredRule(
      level: TriageLevel.sedang,
      certainty: 0.60,
      reason: 'Skor depresi atau kecemasan berada di rentang sedang — pantau '
          'kondisi dan pertimbangkan konsultasi.',
    ));
  }
  if (facts.stressRank >= 3) {
    fired.add(const _FiredRule(
      level: TriageLevel.sedang,
      certainty: 0.58,
      reason: 'Skor stres berada di rentang berat — latihan regulasi diri dan '
          'pertimbangkan konsultasi bila berlanjut.',
    ));
  }
  if (who5Percent != null && who5Percent <= 50) {
    fired.add(_FiredRule(
      level: TriageLevel.sedang,
      certainty: 0.55,
      reason: 'Kesejahteraan (WHO-5) $who5Percent% — di bawah ambang '
          'kesejahteraan baik (50%).',
    ));
  }

  // ---------- Rule default ----------
  if (fired.isEmpty) {
    fired.add(const _FiredRule(
      level: TriageLevel.rendah,
      certainty: 0.40,
      reason: 'Skor asesmen berada di rentang normal — lanjutkan kebiasaan '
          'baik dan ulangi asesmen 2-4 minggu lagi.',
    ));
  }

  // Pilih tingkat triage tertinggi yang tercapai, lalu gabungkan CF seluruh
  // rule pada tingkat tersebut (bukti yang saling menguatkan).
  var chosen = fired.first.level;
  for (final rule in fired) {
    if (rule.level.index > chosen.index) chosen = rule.level;
  }
  var certainty = 0.0;
  final reasons = <String>[];
  for (final rule in fired) {
    if (rule.level != chosen) continue;
    certainty = certainty == 0.0
        ? rule.certainty
        : CertaintyFactorCalculator.combine(certainty, rule.certainty);
    if (reasons.length < 3 && !reasons.contains(rule.reason)) {
      reasons.add(rule.reason);
    }
  }

  return AssessmentInterpretation(
    triageLevel: chosen.name,
    certaintyFactor: certainty.clamp(0.0, 1.0),
    reasons: reasons,
    ruleVersion: assessmentRuleVersion,
  );
}
