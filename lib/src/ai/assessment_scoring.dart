/// Skoring baku DASS-21 & WHO-5 — deterministik, tanpa Certainty Factor.
///
/// Sebelumnya seluruh fungsi di berkas ini tinggal di
/// `widgets/therapy_library.dart`. Dipindahkan ke lapisan `ai/` agar
/// `ai/assessment_interpretation.dart` bisa memakai RUMUS YANG SAMA tanpa
/// mengimpor widget (menghindari impor melingkar). `therapy_library.dart`
/// mengekspor ulang berkas ini sehingga pemanggil lama tetap bekerja.
///
/// ATURAN KUNCI:
/// 1. Skor instrumen murni hasil penjumlahan jawaban pasien (baku):
///    - DASS-21: 21 item, jawaban 0-3, jumlah per subskala x 2 → 0-42.
///    - WHO-5  : 5 item, jawaban 0-5, jumlah → 0-25, persen = raw x 4.
/// 2. Certainty Factor TIDAK BOLEH mengubah skor maupun level. CF hanya
///    dipakai di lapisan interpretasi triage (assessment_interpretation.dart).
/// 3. Submission lama tersimpan dengan skala 1-3 (DASS-21) / 1-5 (WHO-5) dan
///    TIDAK punya penanda versi. Deteksi "adanya nilai 0" tidak boleh dipakai
///    untuk data baru (data baru justru sering 0), karena itu klien baru
///    WAJIB menyisipkan [scaleVersionKey] = [standardizedScaleVersion] saat
///    submit. Bila penanda tidak ada, dipakai rumus lama agar riwayat pasien
///    tetap terbaca benar.
library;

// ============================================================
// PENANDA VERSI SKALA (kompatibilitas data lama)
// ============================================================

/// Kunci penanda versi skala di dalam map `answers` submission.
const String scaleVersionKey = 'scale_version';

/// Kunci nilai minimum skala (informatif, untuk audit data).
const String scaleMinKey = 'scale_min';

/// Kunci nilai maksimum skala (informatif, untuk audit data).
const String scaleMaxKey = 'scale_max';

/// Versi skala baku: DASS-21 0-3, WHO-5 0-5.
const int standardizedScaleVersion = 2;

/// Kelompok item DASS-21 per subskala (nomor item 1-based, sesuai instrumen).
const Set<int> dassDepressionItems = {3, 5, 10, 13, 16, 17, 21};
const Set<int> dassAnxietyItems = {2, 4, 7, 9, 15, 19, 20};
const Set<int> dassStressItems = {1, 6, 8, 11, 12, 14, 18};

/// Baca satu jawaban sebagai int (toleran terhadap `num` dari JSON).
int answerInt(Map<String, dynamic> answers, String key) {
  final value = answers[key];
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}

/// True bila submission ditandai memakai skala baku (versi 2).
bool isStandardizedScale(Map<String, dynamic> answers) =>
    answerInt(answers, scaleVersionKey) == standardizedScaleVersion;

/// Heuristik HANYA untuk data lama (tanpa penanda versi).
///
/// UI generasi pertama memakai skala 0-based sehingga menghasilkan nilai 0,
/// sedangkan UI generasi kedua memakai 1-based (tidak pernah 0). Karena itu
/// adanya nilai 0 pada data TANPA penanda menandakan data generasi pertama.
/// JANGAN memakai heuristik ini untuk data baru — data baru sah bernilai 0.
bool _looksLikeLegacyZeroBased(Map<String, dynamic> answers, int itemCount) {
  for (var i = 1; i <= itemCount; i++) {
    if (answerInt(answers, 'q$i') <= 0) return true;
  }
  return false;
}

// ============================================================
// TABEL RENTANG SKOR (dipakai UI & interpretasi)
// ============================================================

/// Satu baris tabel rentang skor: rentang, label, dan saran singkat.
class ScoreRangeRow {
  const ScoreRangeRow({
    required this.min,
    required this.max,
    required this.label,
    required this.advice,
  });

  /// Batas bawah (inklusif).
  final int min;

  /// Batas atas (inklusif).
  final int max;

  /// Label tingkat keparahan, mis. 'Sedang'.
  final String label;

  /// Saran singkat berbahasa Indonesia untuk pasien.
  final String advice;

  /// True bila [score] berada di rentang ini.
  bool contains(int score) => score >= min && score <= max;

  /// Teks rentang untuk tabel, mis. '14–20'.
  String get rangeLabel => '$min–$max';
}

/// Ambang baku DASS-21 subskala depresi (0-42).
const List<ScoreRangeRow> dassDepressionRanges = [
  ScoreRangeRow(
      min: 0,
      max: 9,
      label: 'Normal',
      advice: 'Tidak ada tanda depresi berarti.'),
  ScoreRangeRow(
      min: 10,
      max: 13,
      label: 'Ringan',
      advice: 'Pantau suasana hati, lanjutkan aktivitas yang bermakna.'),
  ScoreRangeRow(
      min: 14,
      max: 20,
      label: 'Sedang',
      advice: 'Pertimbangkan konsultasi dengan profesional.'),
  ScoreRangeRow(
      min: 21,
      max: 27,
      label: 'Berat',
      advice: 'Disarankan segera bicara dengan profesional.'),
  ScoreRangeRow(
      min: 28,
      max: 42,
      label: 'Sangat berat',
      advice: 'Butuh pendampingan profesional secepatnya.'),
];

/// Ambang baku DASS-21 subskala kecemasan (0-42).
const List<ScoreRangeRow> dassAnxietyRanges = [
  ScoreRangeRow(
      min: 0, max: 7, label: 'Normal', advice: 'Kecemasan dalam batas wajar.'),
  ScoreRangeRow(
      min: 8,
      max: 9,
      label: 'Ringan',
      advice: 'Coba teknik pernapasan dan relaksasi rutin.'),
  ScoreRangeRow(
      min: 10,
      max: 14,
      label: 'Sedang',
      advice: 'Pertimbangkan konsultasi dengan profesional.'),
  ScoreRangeRow(
      min: 15,
      max: 19,
      label: 'Berat',
      advice: 'Disarankan segera bicara dengan profesional.'),
  ScoreRangeRow(
      min: 20,
      max: 42,
      label: 'Sangat berat',
      advice: 'Butuh pendampingan profesional secepatnya.'),
];

/// Ambang baku DASS-21 subskala stres (0-42).
const List<ScoreRangeRow> dassStressRanges = [
  ScoreRangeRow(
      min: 0,
      max: 14,
      label: 'Normal',
      advice: 'Tingkat stres dalam batas wajar.'),
  ScoreRangeRow(
      min: 15,
      max: 18,
      label: 'Ringan',
      advice: 'Jaga istirahat dan batas waktu kerja.'),
  ScoreRangeRow(
      min: 19,
      max: 25,
      label: 'Sedang',
      advice: 'Latih regulasi diri, pertimbangkan konsultasi.'),
  ScoreRangeRow(
      min: 26,
      max: 33,
      label: 'Berat',
      advice: 'Disarankan bicara dengan profesional.'),
  ScoreRangeRow(
      min: 34,
      max: 42,
      label: 'Sangat berat',
      advice: 'Butuh pendampingan profesional secepatnya.'),
];

/// Rentang skor WHO-5 (0-25) beserta artinya.
const List<ScoreRangeRow> who5Ranges = [
  ScoreRangeRow(
      min: 0,
      max: 7,
      label: 'Sangat rendah',
      advice: 'Kemungkinan depresi — disarankan screening lanjutan.'),
  ScoreRangeRow(
      min: 8,
      max: 12,
      label: 'Rendah',
      advice: 'Kesejahteraan rendah — pertimbangkan konsultasi.'),
  ScoreRangeRow(
      min: 13,
      max: 19,
      label: 'Cukup',
      advice: 'Kesejahteraan cukup, jaga kebiasaan baik.'),
  ScoreRangeRow(
      min: 20,
      max: 25,
      label: 'Baik',
      advice: 'Kesejahteraan dalam rentang baik.'),
];

/// Tabel rentang untuk satu subskala DASS-21 ('depression'/'anxiety'/'stress').
List<ScoreRangeRow> dassRangesFor(String subscale) => switch (subscale) {
      'depression' => dassDepressionRanges,
      'anxiety' => dassAnxietyRanges,
      _ => dassStressRanges,
    };

/// Label tingkat keparahan DASS-21 untuk [score] pada [subscale].
String dassLevel(String subscale, int score) {
  final rows = dassRangesFor(subscale);
  for (final row in rows) {
    if (row.contains(score)) return row.label;
  }
  return rows.last.label;
}

/// Peringkat tingkat keparahan DASS-21 (0 = Normal .. 4 = Sangat berat).
int dassLevelRank(String level) => switch (level) {
      'Ringan' => 1,
      'Sedang' => 2,
      'Berat' => 3,
      'Sangat berat' => 4,
      _ => 0,
    };

// ============================================================
// SKOR DASS-21
// ============================================================

/// Hasil skoring DASS-21 (tiap subskala 0-42).
class Dass21Score {
  const Dass21Score({
    required this.depression,
    required this.anxiety,
    required this.stress,
    required this.depressionLevel,
    required this.anxietyLevel,
    required this.stressLevel,
  });

  final int depression;
  final int anxiety;
  final int stress;
  final String depressionLevel;
  final String anxietyLevel;
  final String stressLevel;
}

/// Skor DASS-21 baku: jumlah item per subskala x 2 → 0-42.
///
/// - Data baru (`scale_version` = 2): jawaban 0-3 dipakai apa adanya.
/// - Data lama tanpa penanda:
///   * bila ada nilai 0 → skala 0-3 (rumus lama x2) — identik dengan baku;
///   * bila semua nilai 1-3 → UI lama 1-3, dikonversi (raw-1) 0-2 lalu x3
///     agar total tetap 0-42 dan ambang klinis tidak berubah.
Dass21Score scoreDass21(Map<String, dynamic> answers) {
  final standardized = isStandardizedScale(answers);
  final legacyZeroBased =
      !standardized && _looksLikeLegacyZeroBased(answers, 21);
  final zeroBased = standardized || legacyZeroBased;

  var depression = 0;
  var anxiety = 0;
  var stress = 0;
  for (var item = 1; item <= 21; item++) {
    final raw = answerInt(answers, 'q$item');
    final value = zeroBased ? raw.clamp(0, 3) : (raw - 1).clamp(0, 2);
    if (dassDepressionItems.contains(item)) {
      depression += value;
    } else if (dassAnxietyItems.contains(item)) {
      anxiety += value;
    } else if (dassStressItems.contains(item)) {
      stress += value;
    }
  }
  // Skala 0-3 → x2. Skala lama 0-2 (dari UI 1-3) → x3. Keduanya 0-42.
  final factor = zeroBased ? 2 : 3;
  depression *= factor;
  anxiety *= factor;
  stress *= factor;
  return Dass21Score(
    depression: depression,
    anxiety: anxiety,
    stress: stress,
    depressionLevel: dassLevel('depression', depression),
    anxietyLevel: dassLevel('anxiety', anxiety),
    stressLevel: dassLevel('stress', stress),
  );
}

/// Ringkasan DASS-21. FORMAT DIPERTAHANKAN (dipakai backend & fitur bagikan).
String dass21Summary(Map<String, dynamic> answers) {
  final score = scoreDass21(answers);
  return 'Depresi ${score.depression} (${score.depressionLevel}) • '
      'Kecemasan ${score.anxiety} (${score.anxietyLevel}) • '
      'Stres ${score.stress} (${score.stressLevel})';
}

// ============================================================
// SKOR WHO-5
// ============================================================

/// Hasil skoring WHO-5 (raw 0-25, persen 0-100).
class Who5Score {
  const Who5Score({required this.raw, required this.percent});

  final int raw;
  final int percent;

  /// Kesejahteraan rendah bila skor ≤ 12 (≤ 50%).
  bool get lowWellbeing => raw <= 12;

  /// Kemungkinan depresi bila skor ≤ 7 (≤ 28%).
  bool get possibleDepression => raw <= 7;

  /// Label ringkas tingkat kesejahteraan.
  String get level {
    if (possibleDepression) return 'Sangat rendah';
    if (lowWellbeing) return 'Rendah';
    return raw >= 20 ? 'Baik' : 'Cukup';
  }
}

/// Skor WHO-5 baku: jumlah 5 item (0-5) → raw 0-25, persen = raw x 4.
///
/// - Data baru (`scale_version` = 2) dan data lama 0-5: dipakai apa adanya.
/// - Data lama dari UI 1-5 (semua nilai ≥ 1, tanpa 0): dikonversi ke 0-4 per
///   item, total 0-20, lalu dipetakan ke 0-25 — rumus lama dipertahankan.
Who5Score scoreWho5(Map<String, dynamic> answers) {
  final standardized = isStandardizedScale(answers);
  final legacyZeroBased =
      !standardized && _looksLikeLegacyZeroBased(answers, 5);

  var total = 0;
  for (var item = 1; item <= 5; item++) {
    final raw = answerInt(answers, 'q$item');
    total += (standardized || legacyZeroBased)
        ? raw.clamp(0, 5)
        : (raw - 1).clamp(0, 4);
  }
  if (standardized || legacyZeroBased) {
    return Who5Score(raw: total, percent: (total * 4).clamp(0, 100));
  }
  final raw = (total * 5 / 4).round();
  return Who5Score(raw: raw, percent: (raw * 4).clamp(0, 100));
}

/// Ringkasan WHO-5. FORMAT DIPERTAHANKAN (dipakai backend & fitur bagikan).
String who5Summary(Map<String, dynamic> answers) {
  final score = scoreWho5(answers);
  var suffix = 'Kesejahteraan baik';
  if (score.possibleDepression) {
    suffix = 'Perlu screening lanjutan (kemungkinan depresi)';
  } else if (score.lowWellbeing) {
    suffix = 'Kesejahteraan rendah, pertimbangkan konsultasi';
  }
  return 'WHO-5 ${score.raw}/25 (${score.percent}%) — $suffix';
}

/// Ringkasan skor untuk modul assessment; '' untuk modul lain.
String assessmentSummary(String moduleId, Map<String, dynamic> answers) {
  if (moduleId == 'dass21') return dass21Summary(answers);
  if (moduleId == 'who5') return who5Summary(answers);
  return '';
}
