import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import 'friendly_error.dart';
import 'malva_components.dart';

// ============================================================
// TERAPI LIBRARY — konten edukasi dengan penjelasan singkat
// dan langkah-langkah (tutorial) untuk setiap modul:
//   - Assessment tambahan: DASS-21, WHO-5 (dengan skor otomatis)
//   - Terapi Kognitif Perilaku (CBT): ABCDE, Thinking Traps,
//     Behavioral Activation
//   - Terapi Kognitif (DBT): Grounding 5-4-3-2-1, TIPP & Pernapasan
//   - Terapi Relaksasi & Regulasi Somatik: Pernapasan Teratur,
//     Relaksasi Otot Progresif
//   - Terapi Psikoedukasi Terstruktur
//
// Aturan kolom isian:
//   - Penomoran (1, 2, 3 / A, B, C / 5-4-3-2-1) adalah label TETAP
//     yang dirender sebagai badge — pasien tidak bisa mengeditnya,
//     hanya mengisi jawabannya.
//   - Skala (DASS-21 0-3, WHO-5 0-5, intensitas 0-10) berupa pilihan
//     tombol berlabel, bukan ketikan angka.
//   - Poin jamak ("3 poin penting", "5 hal yang dilihat") berupa
//     kolom terpisah per poin dengan nomor tetap.
// ============================================================

/// Jenis kolom isian worksheet.
enum TherapyFieldKind {
  /// Teks bebas (satu baris / paragraf).
  text,

  /// Skala pilihan tetap [minValue..maxValue] dengan label tiap nilai.
  /// Pasien memilih tombol — tidak mengetik angka.
  scale,

  /// Angka cacah (stepper +/-), mis. jumlah siklus napas.
  number,

  /// Daftar N poin tetap (mis. 3 poin penting, 5 hal yang dilihat).
  /// Nomor poin dirender tetap; pasien mengisi isi tiap poin.
  points,

  /// Pilihan tunggal (chips).
  choice,

  /// Pilihan jamak (chips, boleh lebih dari satu).
  choiceMulti,

  /// Perbandingan sebelum & sesudah (dua skala 0-10).
  beforeAfter,
}

class TherapyModule {
  const TherapyModule({
    required this.title,
    required this.description,
    required this.steps,
    this.id = '',
    this.icon,
    this.color,
    this.category,
    this.worksheetFields = const [],
  });

  final String title;
  final String description;
  final List<String> steps;

  /// Identifier modul untuk submission server (mis. 'abcde').
  final String id;
  final IconData? icon;
  final Color? color;
  final String? category;

  /// Field worksheet yang bisa diisi pasien lalu disimpan/dibagikan.
  final List<TherapyWorksheetField> worksheetFields;

  /// True bila modul ini assessment yang wajib dijawab lengkap.
  bool get isAssessment => id == 'dass21' || id == 'who5';
}

/// Satu pertanyaan/isian pada worksheet modul terapi.
class TherapyWorksheetField {
  const TherapyWorksheetField({
    required this.id,
    required this.label,
    this.badge = '',
    this.hint = '',
    this.kind = TherapyFieldKind.text,
    this.multiline = true,
    this.minValue,
    this.maxValue,
    this.scaleLabels = const [],
    this.choices = const [],
    this.pointCount = 0,
    this.pointLabels = const [],
  });

  final String id;

  /// Teks pertanyaan TANPA nomor (nomor dirender dari [badge]).
  final String label;

  /// Nomor/huruf tetap yang tampil sebagai badge (mis. '1', 'A', '5').
  /// Pasien tidak bisa mengedit badge ini.
  final String badge;
  final String hint;
  final TherapyFieldKind kind;
  final bool multiline;

  /// Rentang untuk [TherapyFieldKind.scale], [number], [beforeAfter].
  final int? minValue;
  final int? maxValue;

  /// Label tiap nilai skala, urut dari minValue ke maxValue.
  /// Bila kosong, dipakai label angka saja.
  final List<String> scaleLabels;

  /// Opsi untuk [TherapyFieldKind.choice] / [choiceMulti].
  final List<String> choices;

  /// Jumlah poin tetap untuk [TherapyFieldKind.points].
  final int pointCount;

  /// Label tiap poin (opsional). Bila kosong, dipakai "Poin 1..N".
  final List<String> pointLabels;

  bool get isScale =>
      kind == TherapyFieldKind.scale && minValue != null && maxValue != null;

  List<int> get scaleValues =>
      isScale ? [for (var v = minValue!; v <= maxValue!; v++) v] : const [];

  String scaleLabel(int value) {
    if (scaleLabels.isEmpty || !isScale) return '$value';
    final idx = value - minValue!;
    if (idx < 0 || idx >= scaleLabels.length) return '$value';
    return scaleLabels[idx];
  }

  List<String> effectivePointLabels() {
    if (pointLabels.isNotEmpty) return pointLabels;
    return [for (var i = 1; i <= pointCount; i++) 'Poin $i'];
  }
}

// ============================================================
// SKORING DASS-21 & WHO-5 (dipakai pasien & profesional)
// ============================================================

/// Kelompok item DASS-21 per subskala (nomor item 1-based).
const Set<int> _dassDepressionItems = {3, 5, 10, 13, 16, 17, 21};
const Set<int> _dassAnxietyItems = {2, 4, 7, 9, 15, 19, 20};
const Set<int> _dassStressItems = {1, 6, 8, 11, 12, 14, 18};

int _answerInt(Map<String, dynamic> answers, String key) {
  final v = answers[key];
  if (v is int) return v;
  if (v is num) return v.toInt();
  return 0;
}

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

String _dassLevel(String subscale, int score) {
  switch (subscale) {
    case 'depression':
      if (score <= 9) return 'Normal';
      if (score <= 13) return 'Ringan';
      if (score <= 20) return 'Sedang';
      if (score <= 27) return 'Berat';
      return 'Sangat berat';
    case 'anxiety':
      if (score <= 7) return 'Normal';
      if (score <= 9) return 'Ringan';
      if (score <= 14) return 'Sedang';
      if (score <= 19) return 'Berat';
      return 'Sangat berat';
    default: // stress
      if (score <= 14) return 'Normal';
      if (score <= 18) return 'Ringan';
      if (score <= 25) return 'Sedang';
      if (score <= 33) return 'Berat';
      return 'Sangat berat';
  }
}

/// Skor DASS-21: jumlah per subskala x2 (setara DASS-42).
Dass21Score scoreDass21(Map<String, dynamic> answers) {
  var dep = 0, anx = 0, str = 0;
  for (var i = 1; i <= 21; i++) {
    final v = _answerInt(answers, 'q$i').clamp(0, 3);
    if (_dassDepressionItems.contains(i)) {
      dep += v;
    } else if (_dassAnxietyItems.contains(i)) {
      anx += v;
    } else if (_dassStressItems.contains(i)) {
      str += v;
    }
  }
  dep *= 2;
  anx *= 2;
  str *= 2;
  return Dass21Score(
    depression: dep,
    anxiety: anx,
    stress: str,
    depressionLevel: _dassLevel('depression', dep),
    anxietyLevel: _dassLevel('anxiety', anx),
    stressLevel: _dassLevel('stress', str),
  );
}

String dass21Summary(Map<String, dynamic> answers) {
  final s = scoreDass21(answers);
  return 'Depresi ${s.depression} (${s.depressionLevel}) • '
      'Kecemasan ${s.anxiety} (${s.anxietyLevel}) • '
      'Stres ${s.stress} (${s.stressLevel})';
}

class Who5Score {
  const Who5Score({required this.raw, required this.percent});

  final int raw;
  final int percent;

  bool get lowWellbeing => raw < 13;
  bool get possibleDepression => raw <= 7;
}

Who5Score scoreWho5(Map<String, dynamic> answers) {
  var total = 0;
  for (var i = 1; i <= 5; i++) {
    total += _answerInt(answers, 'q$i').clamp(0, 5);
  }
  return Who5Score(raw: total, percent: total * 4);
}

String who5Summary(Map<String, dynamic> answers) {
  final s = scoreWho5(answers);
  var suffix = 'Kesejahteraan baik';
  if (s.possibleDepression) {
    suffix = 'Perlu screening lanjutan (kemungkinan depresi)';
  } else if (s.lowWellbeing) {
    suffix = 'Kesejahteraan rendah, pertimbangkan konsultasi';
  }
  return 'WHO-5 ${s.raw}/25 (${s.percent}%) — $suffix';
}

/// Ringkasan skor untuk modul assessment; '' untuk modul lain.
String assessmentSummary(String moduleId, Map<String, dynamic> answers) {
  if (moduleId == 'dass21') return dass21Summary(answers);
  if (moduleId == 'who5') return who5Summary(answers);
  return '';
}

/// Jumlah item skala yang belum dijawab (untuk validasi assessment).
int countUnansweredScale(TherapyModule module, Map<String, int?> scaleValues) {
  var n = 0;
  for (final f in module.worksheetFields) {
    if (f.isScale && scaleValues[f.id] == null) n++;
  }
  return n;
}

// ============================================================
// MODUL: DASS-21
// ============================================================

const List<String> _dassScaleLabels = [
  'Tidak pernah',
  'Kadang-kadang',
  'Sering',
  'Hampir selalu',
];

const dass21Module = TherapyModule(
  id: 'dass21',
  title: 'DASS-21 (Depression Anxiety Stress Scales)',
  description:
      'Kuesioner 21 pertanyaan untuk mengukur tiga aspek: depresi, kecemasan, '
      'dan stres selama minggu terakhir. Pilih jawaban yang paling sesuai '
      'untuk setiap pernyataan (skala 0-3). Skor dihitung otomatis per '
      'kategori dan langsung tampil setelah semua pertanyaan terjawab.',
  icon: Icons.assignment_rounded,
  color: MalvaColors.seed,
  category: 'Assessment',
  worksheetFields: dass21WorksheetFields,
  steps: [
    'Cari tempat tenang dan luangkan waktu ± 10 menit.',
    'Jawab 21 pernyataan sesuai kondisi minggu terakhir.',
    'Jawab berdasarkan pengalaman nyata, bukan yang "seharusnya".',
    'Semua pertanyaan wajib dijawab — skor Depresi, Kecemasan, dan Stres dihitung otomatis.',
    'Simpan hasilnya untuk dibagikan ke profesional saat konsultasi.',
    'Ulangi setiap 2-4 minggu untuk memantau tren, bukan hari per hari.',
  ],
);

/// Field worksheet DASS-21 (21 item, skala 0-3 berlabel).
const dass21WorksheetFields = <TherapyWorksheetField>[
  TherapyWorksheetField(
      id: 'q1',
      badge: '1',
      label: 'Saya merasa sulit untuk menenangkan diri',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
  TherapyWorksheetField(
      id: 'q2',
      badge: '2',
      label: 'Saya menyadari mulut saya terasa kering',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
  TherapyWorksheetField(
      id: 'q3',
      badge: '3',
      label: 'Saya tidak dapat merasakan perasaan positif sama sekali',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
  TherapyWorksheetField(
      id: 'q4',
      badge: '4',
      label: 'Saya mengalami kesulitan bernapas',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
  TherapyWorksheetField(
      id: 'q5',
      badge: '5',
      label: 'Saya merasa sulit berinisiatif mengerjakan sesuatu',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
  TherapyWorksheetField(
      id: 'q6',
      badge: '6',
      label: 'Saya cenderung bereaksi berlebihan terhadap situasi',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
  TherapyWorksheetField(
      id: 'q7',
      badge: '7',
      label: 'Saya mengalami gemetar (mis. di tangan)',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
  TherapyWorksheetField(
      id: 'q8',
      badge: '8',
      label: 'Saya merasa banyak menggunakan energi untuk cemas',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
  TherapyWorksheetField(
      id: 'q9',
      badge: '9',
      label: 'Saya khawatir akan situasi di mana saya panik',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
  TherapyWorksheetField(
      id: 'q10',
      badge: '10',
      label: 'Saya merasa tidak ada hal yang dapat saya nantikan',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
  TherapyWorksheetField(
      id: 'q11',
      badge: '11',
      label: 'Saya merasa gelisah',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
  TherapyWorksheetField(
      id: 'q12',
      badge: '12',
      label: 'Saya sulit untuk rileks',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
  TherapyWorksheetField(
      id: 'q13',
      badge: '13',
      label: 'Saya merasa sedih dan tertekan',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
  TherapyWorksheetField(
      id: 'q14',
      badge: '14',
      label: 'Saya tidak sabar terhadap hal yang menghalangi pekerjaan',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
  TherapyWorksheetField(
      id: 'q15',
      badge: '15',
      label: 'Saya merasa hampir panik',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
  TherapyWorksheetField(
      id: 'q16',
      badge: '16',
      label: 'Saya tidak bisa menjadi antusias terhadap apa pun',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
  TherapyWorksheetField(
      id: 'q17',
      badge: '17',
      label: 'Saya merasa tidak berharga',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
  TherapyWorksheetField(
      id: 'q18',
      badge: '18',
      label: 'Saya merasa mudah tersinggung',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
  TherapyWorksheetField(
      id: 'q19',
      badge: '19',
      label: 'Saya menyadari perubahan detak jantung saat cemas',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
  TherapyWorksheetField(
      id: 'q20',
      badge: '20',
      label: 'Saya merasa takut tanpa alasan yang jelas',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
  TherapyWorksheetField(
      id: 'q21',
      badge: '21',
      label: 'Saya merasa hidup tidak berarti',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 3,
      scaleLabels: _dassScaleLabels),
];

// ============================================================
// MODUL: WHO-5
// ============================================================

const List<String> _who5ScaleLabels = [
  'Tidak pernah',
  'Kadang-kadang',
  'Kurang dari separuh waktu',
  'Lebih dari separuh waktu',
  'Sebagian besar waktu',
  'Setiap saat',
];

const who5Module = TherapyModule(
  id: 'who5',
  title: 'WHO-5 (Well-Being Index)',
  description:
      'Kuesioner singkat 5 pertanyaan untuk mengukur kesejahteraan psikologis '
      'dua minggu terakhir. Pilih jawaban yang paling sesuai untuk setiap '
      'pernyataan (skala 0-5). Skor total dihitung otomatis (0-25).',
  icon: Icons.favorite_rounded,
  color: MalvaColors.mint,
  category: 'Assessment',
  worksheetFields: who5WorksheetFields,
  steps: [
    'Siapkan diri di kondisi tenang (± 3 menit).',
    'Ingat dua minggu terakhir, bukan hanya hari ini.',
    'Jawab kelima pernyataan — semuanya wajib dijawab.',
    'Skor dihitung otomatis: di bawah 13 berarti kesejahteraan rendah dan disarankan screening lanjutan.',
    'Ulangi rutin untuk melihat arah perubahan.',
  ],
);

/// Field worksheet WHO-5 (5 item, skala 0-5 berlabel).
const who5WorksheetFields = <TherapyWorksheetField>[
  TherapyWorksheetField(
      id: 'q1',
      badge: '1',
      label: 'Saya merasa cerah dan bersemangat',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 5,
      scaleLabels: _who5ScaleLabels),
  TherapyWorksheetField(
      id: 'q2',
      badge: '2',
      label: 'Saya merasa tenang dan rileks',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 5,
      scaleLabels: _who5ScaleLabels),
  TherapyWorksheetField(
      id: 'q3',
      badge: '3',
      label: 'Saya merasa aktif dan penuh energi',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 5,
      scaleLabels: _who5ScaleLabels),
  TherapyWorksheetField(
      id: 'q4',
      badge: '4',
      label: 'Saya bangun dengan perasaan segar',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 5,
      scaleLabels: _who5ScaleLabels),
  TherapyWorksheetField(
      id: 'q5',
      badge: '5',
      label: 'Hidup saya dipenuhi hal-hal yang menarik',
      kind: TherapyFieldKind.scale,
      minValue: 0,
      maxValue: 5,
      scaleLabels: _who5ScaleLabels)
];

// ============================================================
// MODUL TERAPI (CBT / DBT / Relaksasi / Psikoedukasi)
// ============================================================

const List<String> _weekdayChoices = [
  'Senin',
  'Selasa',
  'Rabu',
  'Kamis',
  'Jumat',
  'Sabtu',
  'Minggu',
];

const abcdeModule = TherapyModule(
  id: 'abcde',
  title: 'Restrukturisasi Kognitif (ABCDE)',
  description:
      'Teknik inti CBT untuk mengidentifikasi dan mengubah pola pikir negatif. '
      'ABCDE = Activating event (kejadian pemicu), Belief (pikiran/interpretasi), '
      'Consequence (perasaan & perilaku), Dispute (mempertanyakan pikiran), '
      'Effective new belief (pikiran baru yang seimbang).',
  icon: Icons.psychology_alt_rounded,
  color: MalvaColors.orchid,
  category: 'CBT',
  worksheetFields: abcdeWorksheetFields,
  steps: [
    'A — Tulis kejadian pemicu secara faktual ("Presentasi ditolak bos").',
    'B — Catat pikiran otomatis yang muncul ("Saya gagal total").',
    'C — Kenali perasaan & perilaku yang muncul (malu, menarik diri).',
    'D — Bantah: bukti apa yang mendukung/menentang pikiran itu?',
    'E — Rumuskan pikiran baru yang seimbang ("Ini satu proyek, '
        'bukan definisi kemampuan saya").',
    'Latih dengan satu kejadian per hari melalui menu ABCDE CBT.',
  ],
);

/// Field worksheet ABCDE (badge huruf tetap, isi bebas).
const abcdeWorksheetFields = <TherapyWorksheetField>[
  TherapyWorksheetField(
    id: 'activating',
    badge: 'A',
    label: 'Activating event (kejadian pemicu)',
    hint: 'Tulis fakta kejadiannya, bukan tafsirannya…',
  ),
  TherapyWorksheetField(
    id: 'belief',
    badge: 'B',
    label: 'Belief (pikiran otomatis)',
    hint: 'Pikiran yang muncul saat kejadian itu…',
  ),
  TherapyWorksheetField(
    id: 'consequence_physical',
    badge: 'C1',
    label: 'Consequence: reaksi fisik',
    hint: 'Jantung berdebar, tegang, dll…',
  ),
  TherapyWorksheetField(
    id: 'consequence_emotional',
    badge: 'C2',
    label: 'Consequence: emosi & perilaku',
    hint: 'Malu, cemas, menghindar, dll…',
  ),
  TherapyWorksheetField(
    id: 'dispute',
    badge: 'D',
    label: 'Dispute (bantah pikiran)',
    hint: 'Bukti yang mendukung/menentang pikiran itu…',
  ),
  TherapyWorksheetField(
    id: 'effective',
    badge: 'E',
    label: 'Effective new belief (pikiran baru)',
    hint: 'Versi pikiran yang lebih seimbang & realistis…',
  ),
];

const thinkingTrapsModule = TherapyModule(
  id: 'thinking_traps',
  title: 'Identifikasi Distorsi Kognitif (Thinking Traps)',
  description:
      'Distorsi kognitif adalah "jebakan pikiran" — cara berpikir otomatis '
      'yang menyimpang dari fakta, seperti kata-kata harus (should), '
      'membaca pikiran orang lain, membesar-besarkan (catastrophizing), '
      'dan pemikiran hitam-putih. Mengenali jebakan adalah langkah pertama '
      'untuk keluar darinya.',
  icon: Icons.psychology_rounded,
  color: MalvaColors.amber,
  category: 'CBT',
  worksheetFields: thinkingTrapsWorksheetFields,
  steps: [
    'Tuliskan pikiran negatif yang muncul hari ini.',
    'Pilih jenis jebakan yang cocok (boleh lebih dari satu).',
    'Tulis bukti yang mendukung dan yang menentang pikiran itu.',
    'Tanyakan: "Apa yang akan saya katakan ke teman yang berpikir begini?"',
    'Tulis versi pikiran yang lebih seimbang dan realistis.',
  ],
);

const List<String> _thinkingTrapChoices = [
  'Catastrophizing',
  'Mind reading',
  'All-or-nothing',
  'Overgeneralization',
  'Should statements',
  'Fortune telling',
  'Emotional reasoning',
];

/// Field worksheet Thinking Traps.
const thinkingTrapsWorksheetFields = <TherapyWorksheetField>[
  TherapyWorksheetField(
    id: 'thought',
    badge: '1',
    label: 'Pikiran negatif yang muncul',
    hint: 'Tulis persis seperti yang ada di kepalamu…',
  ),
  TherapyWorksheetField(
    id: 'trap_type',
    badge: '2',
    label: 'Jenis jebakan pikiran',
    hint: 'Pilih yang cocok (boleh lebih dari satu)',
    kind: TherapyFieldKind.choiceMulti,
    choices: _thinkingTrapChoices,
  ),
  TherapyWorksheetField(
    id: 'evidence',
    badge: '3',
    label: 'Bukti nyata',
    hint: 'Isi kedua poin di bawah ini',
    kind: TherapyFieldKind.points,
    pointCount: 2,
    pointLabels: ['Mendukung pikiran itu', 'Menentang pikiran itu'],
  ),
  TherapyWorksheetField(
    id: 'balanced_thought',
    badge: '4',
    label: 'Pikiran seimbang versi baru',
    hint: 'Kalimat yang lebih adil untuk dirimu sendiri…',
  ),
];

const behavioralActivationModule = TherapyModule(
  id: 'behavioral_activation',
  title: 'Behavioral Activation / Goals',
  description:
      'Teknik CBT untuk mengatasi malaise: jangan menunggu "punya semangat dulu '
      'baru bergerak", tetapi bergerak dulu (aktivitas kecil bernilai) agar '
      'semangat mengikuti. Dikombinasikan dengan penetapan goals kecil yang '
      'terukur untuk membangun momentum.',
  icon: Icons.directions_run_rounded,
  color: MalvaColors.seed,
  category: 'CBT',
  worksheetFields: behavioralActivationWorksheetFields,
  steps: [
    'Pilih SATU aktivitas kecil bernilai (mis. jalan 10 menit, '
        'menyapu satu ruangan).',
    'Pilih hari dan tulis jam spesifik di bawah ini.',
    'Lakukan tanpa menunggu mood membaik — mulai sekecil apa pun.',
    'Catat hasil dan bagaimana perasaanmu setelahnya.',
    'Naikkan tingkat kesulitan bertahap setiap beberapa hari.',
    'Rayakan streak kecil untuk memperkuat kebiasaan.',
  ],
);

/// Field worksheet Behavioral Activation.
const behavioralActivationWorksheetFields = <TherapyWorksheetField>[
  TherapyWorksheetField(
    id: 'activity',
    badge: '1',
    label: 'Aktivitas kecil yang dipilih',
    hint: 'Mulai dari yang paling ringan dan spesifik…',
  ),
  TherapyWorksheetField(
    id: 'schedule_day',
    badge: '2',
    label: 'Hari pelaksanaan',
    kind: TherapyFieldKind.choice,
    choices: _weekdayChoices,
  ),
  TherapyWorksheetField(
    id: 'schedule_time',
    badge: '3',
    label: 'Jam & pemicu',
    hint: 'Mis. 07.00 setelah bangun tidur',
    multiline: false,
  ),
  TherapyWorksheetField(
    id: 'result',
    badge: '4',
    label: 'Hasil & perasaan setelah dilakukan',
    hint: 'Apa yang berubah pada mood atau energimu?',
  ),
  TherapyWorksheetField(
    id: 'next_step',
    badge: '5',
    label: 'Langkah berikutnya',
    kind: TherapyFieldKind.choice,
    choices: ['Ulangi dulu', 'Naikkan sedikit', 'Ganti aktivitas'],
  ),
];

const groundingModule = TherapyModule(
  id: 'grounding',
  title: 'Grounding 5-4-3-2-1 (DBT)',
  description:
      'Teknik grounding berbasis panca indera untuk menghentikan spiral '
      'kecemasan dan membawa pikiran kembali ke saat ini: 5 hal yang '
      'dilihat, 4 yang didengar, 3 yang diraba, 2 yang diendus, '
      'dan 1 yang dirasakan.',
  icon: Icons.self_improvement_rounded,
  color: MalvaColors.mint,
  category: 'DBT',
  worksheetFields: groundingWorksheetFields,
  steps: [
    'Tarik napas dalam sekali dan perlahan keluarkan.',
    '5 — Sebutkan 5 benda yang bisa kamu LIHAT sekarang.',
    '4 — Identifikasi 4 SUARA yang bisa kamu dengar.',
    '3 — Raba 3 benda dan perhatikan teksturnya.',
    '2 — Cium 2 AROMA di sekitarmu (atau aroma favoritmu).',
    '1 — Sadari 1 hal yang bisa kamu RASA (napas, rasa minuman).',
    'Ulangi bila perlu. Tersedia panduan audio di menu Safety.',
  ],
);

/// Field worksheet Grounding 5-4-3-2-1 (poin tetap per indera).
const groundingWorksheetFields = <TherapyWorksheetField>[
  TherapyWorksheetField(
    id: 'see',
    badge: '5',
    label: 'Yang saya LIHAT',
    hint: 'Sebutkan 5 benda di sekitarmu…',
    kind: TherapyFieldKind.points,
    pointCount: 5,
  ),
  TherapyWorksheetField(
    id: 'hear',
    badge: '4',
    label: 'Yang saya DENGAR',
    hint: 'Suara apa saja yang terdengar sekarang?',
    kind: TherapyFieldKind.points,
    pointCount: 4,
  ),
  TherapyWorksheetField(
    id: 'touch',
    badge: '3',
    label: 'Yang saya RABA',
    hint: 'Tekstur benda yang kamu sentuh…',
    kind: TherapyFieldKind.points,
    pointCount: 3,
  ),
  TherapyWorksheetField(
    id: 'smell',
    badge: '2',
    label: 'Yang saya CIUM',
    hint: 'Aroma di sekitar atau aroma favoritmu…',
    kind: TherapyFieldKind.points,
    pointCount: 2,
  ),
  TherapyWorksheetField(
    id: 'taste_feel',
    badge: '1',
    label: 'Yang saya RASA',
    hint: 'Napas, rasa minuman, atau sensasi tubuh…',
    kind: TherapyFieldKind.points,
    pointCount: 1,
  ),
];

const tippModule = TherapyModule(
  id: 'tipp',
  title: 'TIPP & Pernapasan Teratur (DBT & Somatik)',
  description:
      'TIPP = Temperature (air dingin di wajah), Intense exercise (olahraga '
      'singkat), Paced breathing (napas teratur), Paired muscle relaxation '
      '(relaksasi otot berpasangan). Teknik regulasi emosi cepat yang '
      'bekerja lewat respons fisiologis tubuh untuk menurunkan intensitas '
      'emosi dalam hitungan menit.',
  icon: Icons.ac_unit_rounded,
  color: MalvaColors.orchid,
  category: 'DBT',
  worksheetFields: tippWorksheetFields,
  steps: [
    'Temperature — Tempelkan kompres/wadah air dingin ke wajah 15-30 detik '
        '(menstimulasi refleks dive yang menenangkan).',
    'Intense exercise — Lakukan gerakan intens 1-2 menit (jumping jack, '
        'jalan cepat) untuk "membakar" hormon stres.',
    'Paced breathing — Napas perlahan: tarik 4 detik, tahan 2, hembus 6.',
    'Paired muscle relaxation — Ketegangkan otot saat menarik napas, '
        'lepaskan saat menghembuskan.',
    'Nilai intensitas emosi sebelum & sesudah latihan (0-10).',
    'Praktikkan saat tenang agar mudah dipanggil saat krisis.',
  ],
);

/// Field worksheet TIPP.
const tippWorksheetFields = <TherapyWorksheetField>[
  TherapyWorksheetField(
    id: 'temperature',
    badge: '1',
    label: 'Temperature — pengalaman air dingin',
    hint: 'Berapa lama dan bagaimana rasanya setelahnya?',
  ),
  TherapyWorksheetField(
    id: 'exercise',
    badge: '2',
    label: 'Intense exercise — gerakan yang dilakukan',
    hint: 'Mis. jumping jack 60 detik',
  ),
  TherapyWorksheetField(
    id: 'paced_breathing',
    badge: '3',
    label: 'Paced breathing — siklus napas',
    hint: 'Berapa siklus 4-2-6 yang kamu lakukan?',
  ),
  TherapyWorksheetField(
    id: 'muscle_relaxation',
    badge: '4',
    label: 'Paired muscle relaxation — otot yang ditegangkan',
    hint: 'Otot mana dan apa bedanya sebelum/sesudah?',
  ),
  TherapyWorksheetField(
    id: 'intensity',
    badge: '5',
    label: 'Intensitas emosi sebelum & sesudah (0-10)',
    kind: TherapyFieldKind.beforeAfter,
    minValue: 0,
    maxValue: 10,
  ),
];

const breathingModule = TherapyModule(
  id: 'breathing',
  title: 'Latihan Pernapasan Teratur',
  description:
      'Pernapasan lambat dan teratur mengaktifkan sistem saraf parasimpatis '
      '(respons istirahat) sehingga detak jantung menurun dan pikiran lebih '
      'jernih. Latihan paling portabel: bisa dilakukan di mana saja tanpa '
      'alat, efektif untuk stres harian dan gangguan tidur ringan.',
  icon: Icons.air_rounded,
  color: MalvaColors.mint,
  category: 'Relaksasi',
  worksheetFields: breathingWorksheetFields,
  steps: [
    'Duduk nyaman, punggung tegak, bahu rileks.',
    'Tarik napas melalui hidung 4 detik (perut mengembang).',
    'Tahan napas 2 detik.',
    'Hembuskan perlahan lewat mulut 6 detik.',
    'Ulangi 5-10 siklus, atau 5 menit sebelum tidur.',
    'Catat jumlah siklus dan ketegangan sebelum/sesudah di bawah.',
    'Gunakan panduan animasi di Safety Protocol untuk ritme.',
  ],
);

/// Field worksheet Pernapasan Teratur.
const breathingWorksheetFields = <TherapyWorksheetField>[
  TherapyWorksheetField(
    id: 'cycles',
    badge: '1',
    label: 'Jumlah siklus 4-2-6 yang dilakukan',
    kind: TherapyFieldKind.number,
    minValue: 0,
    maxValue: 60,
  ),
  TherapyWorksheetField(
    id: 'tension',
    badge: '2',
    label: 'Ketegangan sebelum & sesudah (0-10)',
    kind: TherapyFieldKind.beforeAfter,
    minValue: 0,
    maxValue: 10,
  ),
  TherapyWorksheetField(
    id: 'note',
    badge: '3',
    label: 'Catatan tambahan',
    hint: 'Kapan paling membantu? Sebelum tidur? Saat cemas?',
  ),
];

const pmrModule = TherapyModule(
  id: 'pmr',
  title: 'Relaksasi Otot Progresif',
  description:
      'Progressive Muscle Relaxation (PMR): menegangkan lalu melepaskan '
      'kelompok otot secara berurutan dari kaki ke kepala. Perbedaan '
      'ketegangan-rileks melatih tubuh mengenali dan melepaskan stres '
      'terkumpul, membantu insomnia dan ketegangan fisik.',
  icon: Icons.spa_rounded,
  color: MalvaColors.seed,
  category: 'Relaksasi',
  worksheetFields: pmrWorksheetFields,
  steps: [
    'Berbaring atau duduk nyaman; tarik napas tenang.',
    'Pilih kelompok otot yang dilalui di bawah ini.',
    'Mulai dari kaki: tegangkan otot 5 detik (jangan sampai kram).',
    'Lepaskan tiba-tiba; rasakan perbedaannya 10 detik.',
    'Naik bertahap: betis, paha, perut, tangan, bahu, wajah.',
    'Akhiri dengan 3 napas dalam dan rasakan seluruh tubuh rileks.',
    'Praktikkan 10-15 menit, idealnya sebelum tidur.',
  ],
);

const List<String> _pmrMuscleChoices = [
  'Kaki',
  'Betis',
  'Paha',
  'Perut',
  'Tangan',
  'Bahu',
  'Wajah',
];

/// Field worksheet PMR.
const pmrWorksheetFields = <TherapyWorksheetField>[
  TherapyWorksheetField(
    id: 'muscle_groups',
    badge: '1',
    label: 'Kelompok otot yang dilalui',
    hint: 'Pilih yang sudah dilatih',
    kind: TherapyFieldKind.choiceMulti,
    choices: _pmrMuscleChoices,
  ),
  TherapyWorksheetField(
    id: 'difference',
    badge: '2',
    label: 'Perbedaan tegang vs rileks yang dirasakan',
    hint: 'Bagian mana yang paling terasa lepas?',
  ),
  TherapyWorksheetField(
    id: 'note',
    badge: '3',
    label: 'Catatan & kondisi setelah latihan',
    hint: 'Lebih mudah tidur? Tubuh lebih ringan?',
  ),
];

const psychoeducationModule = TherapyModule(
  id: 'psychoeducation',
  title: 'Terapi Psikoedukasi Terstruktur',
  description:
      'Psikoedukasi memberi pemahaman terstruktur tentang kondisi kesehatan '
      'jiwa: apa itu depresi/kecemasan, bagaimana siklus gejala bekerja, '
      'peran obat dan terapi, serta tanda bahaya. Pemahaman yang baik '
      'terbukti meningkatkan kepatuhan pengobatan dan kemampuan '
      'mengelola diri (self-management).',
  icon: Icons.menu_book_rounded,
  color: MalvaColors.amber,
  category: 'Psikoedukasi',
  worksheetFields: psychoeducationWorksheetFields,
  steps: [
    'Pelajari satu topik per minggu (mis. minggu 1: siklus depresi).',
    'Catat 3 poin penting dan 1 hal yang masih membingungkan.',
    'Hubungkan dengan pengalamanmu: kapan siklus itu terjadi padamu?',
    'Bawa pertanyaan ke sesi konsultasi berikutnya.',
    'Bagikan pemahaman baru ke orang terdekat sebagai sistem dukungan.',
    'Gunakan hasil screening sebagai titik awal diskusi dengan profesional.',
  ],
);

/// Field worksheet Psikoedukasi.
const psychoeducationWorksheetFields = <TherapyWorksheetField>[
  TherapyWorksheetField(
    id: 'topic',
    badge: '1',
    label: 'Topik pekan ini',
    hint: 'Mis. siklus depresi, peran obat, tanda bahaya',
  ),
  TherapyWorksheetField(
    id: 'key_points',
    badge: '2',
    label: '3 poin penting yang dipelajari',
    hint: 'Isi ketiga poin di bawah ini',
    kind: TherapyFieldKind.points,
    pointCount: 3,
  ),
  TherapyWorksheetField(
    id: 'question',
    badge: '3',
    label: 'Hal yang masih membingungkan',
    hint: 'Pertanyaan untuk dibawa ke sesi konsultasi…',
  ),
  TherapyWorksheetField(
    id: 'reflection',
    badge: '4',
    label: 'Refleksi: kapan ini terjadi padaku?',
    hint: 'Hubungkan dengan pengalaman pribadimu…',
  ),
];

/// Semua modul terapi (dipakai Psychological Therapy di Home).
// ignore: prefer_const_constructors
final List<TherapyModule> allTherapyModules = [
  abcdeModule,
  thinkingTrapsModule,
  behavioralActivationModule,
  groundingModule,
  tippModule,
  breathingModule,
  pmrModule,
  psychoeducationModule,
];

/// Cari definisi modul dari id (untuk viewer jawaban tersimpan).
TherapyModule? findTherapyModuleById(String id) {
  if (id == 'dass21') return dass21Module;
  if (id == 'who5') return who5Module;
  for (final m in allTherapyModules) {
    if (m.id == id) return m;
  }
  return null;
}

/// Warna level keparahan (tetap dalam palet Malva).
Color severityColor(String level) {
  switch (level.toLowerCase()) {
    case 'normal':
      return MalvaColors.mint;
    case 'ringan':
      return MalvaColors.mint;
    case 'sedang':
      return MalvaColors.amber;
    case 'berat':
    case 'sangat berat':
      return MalvaColors.danger;
    default:
      return MalvaColors.seed;
  }
}

/// Warna fill kolom isian: paper Malva di terang, surface container di gelap.
/// Memakai token tema (bukan literal off-palette) agar tetap dalam palet Malva.
Color worksheetFieldFill(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  return Theme.of(context).brightness == Brightness.dark
      ? scheme.surfaceContainerHighest
      : MalvaColors.paper;
}

// ============================================================
// DETAIL MODUL — deskripsi + langkah + worksheet + skor
// ============================================================

/// Halaman detail modul terapi: deskripsi + langkah + worksheet.
/// Worksheet bisa diisi, disimpan ke server (folder therapy), diunduh
/// (share/export), dan dibagikan ke profesional (butuh paket aktif).
class TherapyDetailScreen extends ConsumerStatefulWidget {
  const TherapyDetailScreen({super.key, required this.module});

  final TherapyModule module;

  @override
  ConsumerState<TherapyDetailScreen> createState() =>
      _TherapyDetailScreenState();
}

class _TherapyDetailScreenState extends ConsumerState<TherapyDetailScreen> {
  final _textControllers = <String, TextEditingController>{};
  final _scaleValues = <String, int>{};
  final _numberValues = <String, int>{};
  final _choiceValues = <String, String>{};
  final _choiceMultiValues = <String, Set<String>>{};
  final _beforeValues = <String, int>{};
  final _afterValues = <String, int>{};
  bool _isSaving = false;
  bool _saved = false;
  String? _error;

  TherapyModule get module => widget.module;

  @override
  void initState() {
    super.initState();
    for (final field in module.worksheetFields) {
      switch (field.kind) {
        case TherapyFieldKind.text:
          _textControllers[field.id] = TextEditingController();
        case TherapyFieldKind.points:
          for (var i = 0; i < field.pointCount; i++) {
            _textControllers['${field.id}#$i'] = TextEditingController();
          }
        case TherapyFieldKind.choiceMulti:
          _choiceMultiValues[field.id] = <String>{};
        case TherapyFieldKind.scale:
        case TherapyFieldKind.number:
        case TherapyFieldKind.choice:
        case TherapyFieldKind.beforeAfter:
          break;
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _textControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic> _answers() {
    final out = <String, dynamic>{};
    for (final field in module.worksheetFields) {
      switch (field.kind) {
        case TherapyFieldKind.text:
          out[field.id] = _textControllers[field.id]?.text.trim() ?? '';
        case TherapyFieldKind.scale:
          final v = _scaleValues[field.id];
          if (v != null) out[field.id] = v;
        case TherapyFieldKind.number:
          final v = _numberValues[field.id];
          if (v != null) out[field.id] = v;
        case TherapyFieldKind.points:
          final pts = [
            for (var i = 0; i < field.pointCount; i++)
              _textControllers['${field.id}#$i']?.text.trim() ?? '',
          ];
          if (pts.any((p) => p.isNotEmpty)) out[field.id] = pts;
        case TherapyFieldKind.choice:
          final v = _choiceValues[field.id];
          if (v != null && v.isNotEmpty) out[field.id] = v;
        case TherapyFieldKind.choiceMulti:
          final vs = _choiceMultiValues[field.id];
          if (vs != null && vs.isNotEmpty) out[field.id] = vs.toList();
        case TherapyFieldKind.beforeAfter:
          final b = _beforeValues[field.id];
          final a = _afterValues[field.id];
          if (b != null || a != null) {
            out[field.id] = {
              if (b != null) 'before': b,
              if (a != null) 'after': a,
            };
          }
      }
    }
    return out;
  }

  bool get _hasAnyAnswer {
    if (_textControllers.values.any((c) => c.text.trim().isNotEmpty)) {
      return true;
    }
    return _scaleValues.isNotEmpty ||
        _numberValues.isNotEmpty ||
        _choiceValues.isNotEmpty ||
        _choiceMultiValues.values.any((s) => s.isNotEmpty) ||
        _beforeValues.isNotEmpty ||
        _afterValues.isNotEmpty;
  }

  int get _answeredScaleCount {
    var n = 0;
    for (final field in module.worksheetFields) {
      if (field.isScale && _scaleValues[field.id] != null) n++;
    }
    return n;
  }

  int get _totalScaleCount =>
      module.worksheetFields.where((f) => f.isScale).length;

  String? _liveSummary() {
    if (!module.isAssessment) return null;
    if (_answeredScaleCount < _totalScaleCount) return null;
    return assessmentSummary(module.id, {
      for (final e in _scaleValues.entries) e.key: e.value,
    });
  }

  void _markDirty() {
    if (_saved) setState(() => _saved = false);
  }

  Future<void> _submit({bool share = false}) async {
    // Assessment wajib dijawab lengkap agar skor valid.
    if (module.isAssessment) {
      final missing = countUnansweredScale(module, _scaleValues);
      if (missing > 0) {
        setState(() => _error =
            'Masih ada $missing pertanyaan belum dijawab. Lengkapi dulu agar skor valid.');
        return;
      }
    } else if (!_hasAnyAnswer) {
      setState(() => _error = 'Isi minimal satu kolom worksheet dulu.');
      return;
    }
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Login dulu untuk menyimpan worksheet.');
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final answers = _answers();
      final submission = await api.createTherapySubmission(
        accessToken: token,
        moduleId: module.id.isEmpty ? module.title : module.id,
        title: module.title,
        answers: answers,
        summary: assessmentSummary(module.id, answers),
      );
      String? sharedTo;
      if (share) {
        sharedTo = await _pickProfessional();
        if (sharedTo == null) {
          if (mounted) {
            setState(() => _isSaving = false);
            _toast('Worksheet tersimpan di folder therapy. '
                'Belum dibagikan ke profesional.');
          }
          return;
        }
        await api.shareTherapySubmission(
          accessToken: token,
          submissionId: submission.id,
          professionalId: sharedTo,
        );
      }
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saved = true;
      });
      _toast(share
          ? 'Worksheet tersimpan & dibagikan ke profesional.'
          : 'Worksheet tersimpan di folder therapy.');
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  /// Pilih profesional dengan paket aktif untuk berbagi worksheet.
  Future<String?> _pickProfessional() async {
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    if (token == null || token.isEmpty) return null;
    List<BackendPatientProfessionalLink> links;
    try {
      links = await ref
          .read(apiClientProvider)
          .listPatientProfessionalLinks(accessToken: token);
    } on Object {
      return null;
    }
    final active = links
        .where((link) =>
            link.status == 'active' &&
            (link.professionalDisplayName.trim().isNotEmpty))
        .toList(growable: false);
    if (!mounted || active.isEmpty) {
      _toast('Berbagi worksheet butuh paket sesi aktif dengan profesional.');
      return null;
    }
    // Hanya yang paketnya aktif (server menolak sisanya).
    final eligible = <BackendPatientProfessionalLink>[];
    final api = ref.read(apiClientProvider);
    final pkgs = await api.listCarePackages(accessToken: token);
    final activeProIds = {
      for (final p in pkgs)
        if (p.isActive) p.professionalId,
    };
    for (final link in active) {
      if (activeProIds.contains(link.professionalUserId)) eligible.add(link);
    }
    if (!mounted) return null;
    if (eligible.isEmpty) {
      _toast('Berbagi worksheet butuh paket sesi aktif dengan profesional.');
      return null;
    }
    return showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Bagikan ke profesional',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 4),
              Text(
                'Hanya profesional dengan paket sesi aktif.',
                style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              for (final link in eligible)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SoftCard(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const CircleAvatar(
                        backgroundColor: Color(0x228E44AD),
                        child: Icon(Icons.medical_services_rounded,
                            color: MalvaColors.seed),
                      ),
                      title: Text(link.professionalDisplayName,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      trailing: const Icon(Icons.send_rounded, size: 18),
                      onTap: () => Navigator.pop(ctx, link.professionalUserId),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Unduh worksheet sebagai teks (share via share sheet).
  Future<void> _download() async {
    if (module.isAssessment) {
      final missing = countUnansweredScale(module, _scaleValues);
      if (missing > 0) {
        setState(() => _error = 'Masih ada $missing pertanyaan belum dijawab.');
        return;
      }
    } else if (!_hasAnyAnswer) {
      setState(() => _error = 'Isi minimal satu kolom worksheet dulu.');
      return;
    }
    final answers = _answers();
    final buffer = StringBuffer()
      ..writeln('MALVA — Worksheet Terapi')
      ..writeln(module.title)
      ..writeln('Kategori: ${module.category ?? 'Terapi'}')
      ..writeln('Tanggal: ${DateTime.now().toIso8601String()}');
    final summary = assessmentSummary(module.id, answers);
    if (summary.isNotEmpty) {
      buffer.writeln('Hasil: $summary');
    }
    buffer.writeln('----------------------------------------');
    for (final field in module.worksheetFields) {
      buffer.writeln(_fieldHeadline(field));
      buffer.writeln(_answerText(field, answers[field.id]) ?? '(belum diisi)');
      buffer.writeln();
    }
    buffer
      ..writeln('----------------------------------------')
      ..writeln('Catatan: dokumen ini alat bantu latihan, '
          'bukan pengganti diagnosis profesional.');
    final text = buffer.toString();
    final tmp = await getTemporaryDirectory();
    final file = File(
        '${tmp.path}/malva-worksheet-${module.id.isEmpty ? 'terapi' : module.id}-'
        '${DateTime.now().millisecondsSinceEpoch}.txt');
    await file.writeAsString(text);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: 'Worksheet ${module.title} — Malva',
        text: 'Worksheet terapi saya (${module.title}).',
      ),
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
          content: Text(message),
          backgroundColor:
              message.contains('tersimpan') ? MalvaColors.mint : null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = module.color ?? MalvaColors.seed;
    final summary = _liveSummary();
    return Scaffold(
      appBar: AppBar(
        title: Text(module.category ?? 'Terapi'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withValues(alpha: 0.14),
                child: Icon(module.icon ?? Icons.self_improvement_rounded,
                    color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  module.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 17),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Apa itu?',
                    style:
                        TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 6),
                Text(module.description,
                    style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Langkah-langkah',
                    style:
                        TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 10),
                for (var i = 0; i < module.steps.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 11,
                          backgroundColor: color.withValues(alpha: 0.14),
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w900,
                                fontSize: 11),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(module.steps[i],
                              style: Theme.of(context).textTheme.bodyMedium),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (module.worksheetFields.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                const SectionLabel('Worksheet'),
                const Spacer(),
                if (module.isAssessment)
                  StatusPill(
                    label:
                        '${_answeredScaleCount}/${_totalScaleCount} terjawab',
                    color: _answeredScaleCount == _totalScaleCount
                        ? MalvaColors.mint
                        : MalvaColors.amber,
                    icon: Icons.fact_check_rounded,
                  ),
              ],
            ),
            if (module.isAssessment) ...[
              const SizedBox(height: 2),
              ProgressStrip(
                value: _totalScaleCount == 0
                    ? 0
                    : _answeredScaleCount / _totalScaleCount,
                color: MalvaColors.seed,
              ),
              const SizedBox(height: 10),
            ],
            if (summary != null) ...[
              _AssessmentResultCard(moduleId: module.id, answers: _scaleValues),
              const SizedBox(height: 10),
            ],
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    module.isAssessment
                        ? 'Pilih jawaban yang paling sesuai untuk setiap '
                            'pernyataan. Semua wajib dijawab agar skor valid.'
                        : 'Isi worksheet ini sesuai kondisimu. Hasilnya bisa '
                            'disimpan ke folder therapy, diunduh, atau dikirim '
                            'langsung ke profesional (butuh paket sesi aktif).',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  for (final field in module.worksheetFields) ...[
                    _WorksheetFieldBlock(
                      field: field,
                      moduleColor: color,
                      // Layar ini sisi pasien: baris poin read-only (Q-6).
                      readOnly: true,
                      textController: _textControllers[field.id],
                      pointControllers: [
                        for (var i = 0; i < field.pointCount; i++)
                          _textControllers['${field.id}#$i'],
                      ],
                      scaleValue: _scaleValues[field.id],
                      numberValue: _numberValues[field.id],
                      choiceValue: _choiceValues[field.id],
                      choiceMultiValues:
                          _choiceMultiValues[field.id] ?? const <String>{},
                      beforeValue: _beforeValues[field.id],
                      afterValue: _afterValues[field.id],
                      onTextChanged: (_) => _markDirty(),
                      onScaleSelect: (v) => setState(() {
                        _scaleValues[field.id] = v;
                        _saved = false;
                      }),
                      onNumberChanged: (v) => setState(() {
                        _numberValues[field.id] = v;
                        _saved = false;
                      }),
                      onChoiceSelect: (v) => setState(() {
                        _choiceValues[field.id] = v;
                        _saved = false;
                      }),
                      onChoiceMultiToggle: (v) => setState(() {
                        final set = _choiceMultiValues[field.id] ?? <String>{};
                        if (set.contains(v)) {
                          set.remove(v);
                        } else {
                          set.add(v);
                        }
                        _choiceMultiValues[field.id] = set;
                        _saved = false;
                      }),
                      onBeforeSelect: (v) => setState(() {
                        _beforeValues[field.id] = v;
                        _saved = false;
                      }),
                      onAfterSelect: (v) => setState(() {
                        _afterValues[field.id] = v;
                        _saved = false;
                      }),
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(
                    color: MalvaColors.danger, fontWeight: FontWeight.w700)),
          ],
          if (_saved) ...[
            const SizedBox(height: 10),
            const Row(
              children: [
                Icon(Icons.check_circle_rounded, color: MalvaColors.mint),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Worksheet tersimpan di folder therapy (menu More → '
                    'Export / daftar worksheet).',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                  ),
                ),
              ],
            ),
          ],
          if (module.worksheetFields.isNotEmpty) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _isSaving ? null : () => _submit(),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
              ),
              icon: _isSaving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
              label: const Text('Simpan ke Folder Therapy'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _isSaving ? null : () => _submit(share: true),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.send_rounded),
              label: const Text('Simpan & Kirim ke Profesional'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _isSaving ? null : _download,
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              icon: const Icon(Icons.download_rounded),
              label: const Text('Download Worksheet'),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Catatan: konten ini bersifat edukasi dan alat bantu latihan, '
            'bukan pengganti diagnosis atau terapi profesional.',
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontSize: 12),
          ),
        ],
      ),
    );
  }
}

/// Headline jawaban untuk export teks.
String _fieldHeadline(TherapyWorksheetField field) {
  final badge = field.badge.isEmpty ? '' : '[${field.badge}] ';
  return '$badge${field.label}';
}

/// Format jawaban tersimpan menjadi teks satu baris (export & viewer).
String? _answerText(TherapyWorksheetField field, Object? answer) {
  if (answer == null) return null;
  if (answer is int) {
    if (field.isScale) {
      // F-4: field skala berlabel tampilkan label (mis. "Kadang-kadang"),
      // bukan angka mentah 0..3; skala numerik tanpa label tetap angka.
      return field.scaleLabels.isNotEmpty
          ? field.scaleLabel(answer)
          : '$answer';
    }
    return '$answer';
  }
  if (answer is num) return _answerText(field, answer.toInt());
  if (answer is String) return answer.isEmpty ? null : answer;
  if (answer is List) {
    final parts = answer.map((e) => e.toString()).toList();
    if (field.kind == TherapyFieldKind.points) {
      final labels = field.effectivePointLabels();
      final lines = <String>[];
      for (var i = 0; i < parts.length; i++) {
        final head = i < labels.length ? labels[i] : 'Poin ${i + 1}';
        final body = parts[i].trim();
        if (body.isEmpty) continue;
        lines.add('${i + 1}. $head: $body');
      }
      return lines.isEmpty ? null : lines.join('\n');
    }
    final nonEmpty = parts.where((p) => p.trim().isNotEmpty).toList();
    return nonEmpty.isEmpty ? null : nonEmpty.join(', ');
  }
  if (answer is Map) {
    final b = answer['before'];
    final a = answer['after'];
    if (b == null && a == null) return null;
    return 'Sebelum: ${b ?? '-'} • Sesudah: ${a ?? '-'}';
  }
  final s = answer.toString();
  return s.isEmpty ? null : s;
}

/// Kartu hasil skor DASS-21 / WHO-5 (live saat mengisi & untuk viewer).
class _AssessmentResultCard extends StatelessWidget {
  const _AssessmentResultCard({
    required this.moduleId,
    required this.answers,
  });

  final String moduleId;
  final Map<String, int> answers;

  @override
  Widget build(BuildContext context) {
    if (moduleId == 'dass21') {
      final s = scoreDass21(answers);
      return SoftCard(
        color: MalvaColors.seed.withValues(alpha: 0.06),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.auto_graph_rounded, color: MalvaColors.seed),
                SizedBox(width: 8),
                Text('Hasil DASS-21',
                    style:
                        TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 10),
            _ScoreRow(
                label: 'Depresi',
                score: s.depression,
                level: s.depressionLevel),
            const SizedBox(height: 8),
            _ScoreRow(
                label: 'Kecemasan', score: s.anxiety, level: s.anxietyLevel),
            const SizedBox(height: 8),
            _ScoreRow(label: 'Stres', score: s.stress, level: s.stressLevel),
          ],
        ),
      );
    }
    final s = scoreWho5(answers);
    final level = s.possibleDepression
        ? 'Perlu screening lanjutan'
        : s.lowWellbeing
            ? 'Rendah'
            : 'Baik';
    final color = s.possibleDepression
        ? MalvaColors.danger
        : s.lowWellbeing
            ? MalvaColors.amber
            : MalvaColors.mint;
    return SoftCard(
      color: MalvaColors.mint.withValues(alpha: 0.10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.favorite_rounded, color: MalvaColors.mint),
              SizedBox(width: 8),
              Text('Hasil WHO-5',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text('${s.raw}/25 (${s.percent}%)',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 18)),
              ),
              StatusPill(label: level, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            s.possibleDepression
                ? 'Skor ≤ 7 menandakan kemungkinan depresi — disarankan screening lanjutan dan konsultasi profesional.'
                : s.lowWellbeing
                    ? 'Skor di bawah 13 menandakan kesejahteraan rendah — pertimbangkan konsultasi.'
                    : 'Kesejahteraan dalam rentang baik. Ulangi rutin untuk memantau tren.',
            style: const TextStyle(fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _ScoreRow extends StatelessWidget {
  const _ScoreRow({
    required this.label,
    required this.score,
    required this.level,
  });

  final String label;
  final int score;
  final String level;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text('$label: $score',
              style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
        StatusPill(label: level, color: severityColor(level)),
      ],
    );
  }
}

/// Satu blok kolom isian: badge nomor tetap + kontrol jawaban.
/// Penomoran (badge) dirender sebagai label — pasien tidak bisa
/// mengedit nomornya, hanya mengisi jawabannya.
class _WorksheetFieldBlock extends StatelessWidget {
  const _WorksheetFieldBlock({
    required this.field,
    required this.moduleColor,
    this.textController,
    this.pointControllers = const [],
    this.scaleValue,
    this.numberValue,
    this.choiceValue,
    this.choiceMultiValues = const {},
    this.beforeValue,
    this.afterValue,
    this.onTextChanged,
    this.onScaleSelect,
    this.onNumberChanged,
    this.onChoiceSelect,
    this.onChoiceMultiToggle,
    this.onBeforeSelect,
    this.onAfterSelect,
    this.readOnly = false,
  });

  final TherapyWorksheetField field;
  final Color moduleColor;
  final TextEditingController? textController;
  final List<TextEditingController?> pointControllers;
  final int? scaleValue;
  final int? numberValue;
  final String? choiceValue;
  final Set<String> choiceMultiValues;
  final int? beforeValue;
  final int? afterValue;
  final ValueChanged<String>? onTextChanged;
  final ValueChanged<int>? onScaleSelect;
  final ValueChanged<int>? onNumberChanged;
  final ValueChanged<String>? onChoiceSelect;
  final ValueChanged<String>? onChoiceMultiToggle;
  final ValueChanged<int>? onBeforeSelect;
  final ValueChanged<int>? onAfterSelect;

  /// Mode view-only (pasien): baris poin `1..N` dirender statis
  /// tanpa `TextField` — nilai tidak dapat diketik (Q-6).
  final bool readOnly;

  @override
  Widget build(BuildContext context) {
    final fill = worksheetFieldFill(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: moduleColor.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (field.badge.isNotEmpty) ...[
                CircleAvatar(
                  radius: 12,
                  backgroundColor: moduleColor.withValues(alpha: 0.14),
                  child: Text(
                    field.badge,
                    style: TextStyle(
                        color: moduleColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 11.5),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(field.label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 13.5)),
              ),
            ],
          ),
          if (field.hint.isNotEmpty &&
              field.kind != TherapyFieldKind.scale) ...[
            const SizedBox(height: 4),
            Text(
              field.hint,
              style: TextStyle(
                  fontSize: 11.5,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 8),
          switch (field.kind) {
            TherapyFieldKind.scale => _ScaleOptions(
                field: field,
                moduleColor: moduleColor,
                value: scaleValue,
                onSelect: onScaleSelect,
              ),
            TherapyFieldKind.number => _NumberStepper(
                value: numberValue ?? field.minValue ?? 0,
                min: field.minValue ?? 0,
                max: field.maxValue ?? 60,
                color: moduleColor,
                onChanged: onNumberChanged,
              ),
            TherapyFieldKind.points => readOnly
                ? _ReadOnlyPoints(
                    field: field,
                    moduleColor: moduleColor,
                    controllers: pointControllers,
                  )
                : Column(
                    children: [
                      for (var i = 0;
                          i <
                              (field.pointCount == 0
                                  ? pointControllers.length
                                  : field.pointCount);
                          i++)
                        Padding(
                          padding: EdgeInsets.only(
                              bottom: i ==
                                      (field.pointCount == 0
                                              ? pointControllers.length
                                              : field.pointCount) -
                                          1
                                  ? 0
                                  : 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: moduleColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${i + 1}',
                                  style: TextStyle(
                                      color: moduleColor,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: i < pointControllers.length
                                      ? pointControllers[i]
                                      : null,
                                  minLines: 1,
                                  maxLines: 3,
                                  onChanged: onTextChanged,
                                  decoration: InputDecoration(
                                    hintText:
                                        i < field.effectivePointLabels().length
                                            ? field.effectivePointLabels()[i]
                                            : 'Poin ${i + 1}…',
                                    filled: true,
                                    fillColor: fill,
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                          color: moduleColor.withValues(
                                              alpha: 0.25)),
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                          color: moduleColor.withValues(
                                              alpha: 0.25)),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(
                                          color: moduleColor, width: 1.6),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
            TherapyFieldKind.choice => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in field.choices)
                    ChoiceChip(
                      label: Text(option,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      selected: choiceValue == option,
                      onSelected: (_) => onChoiceSelect?.call(option),
                      selectedColor: moduleColor.withValues(alpha: 0.22),
                      side: BorderSide(
                          color: moduleColor.withValues(alpha: 0.35)),
                    ),
                ],
              ),
            TherapyFieldKind.choiceMulti => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in field.choices)
                    FilterChip(
                      label: Text(option,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      selected: choiceMultiValues.contains(option),
                      onSelected: (_) => onChoiceMultiToggle?.call(option),
                      selectedColor: moduleColor.withValues(alpha: 0.22),
                      checkmarkColor: moduleColor,
                      side: BorderSide(
                          color: moduleColor.withValues(alpha: 0.35)),
                    ),
                ],
              ),
            TherapyFieldKind.beforeAfter => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Sebelum latihan',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  const SizedBox(height: 6),
                  _MiniScale(
                    min: field.minValue ?? 0,
                    max: field.maxValue ?? 10,
                    color: moduleColor,
                    value: beforeValue,
                    onSelect: onBeforeSelect,
                  ),
                  const SizedBox(height: 10),
                  const Text('Sesudah latihan',
                      style:
                          TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
                  const SizedBox(height: 6),
                  _MiniScale(
                    min: field.minValue ?? 0,
                    max: field.maxValue ?? 10,
                    color: moduleColor,
                    value: afterValue,
                    onSelect: onAfterSelect,
                  ),
                ],
              ),
            TherapyFieldKind.text => TextField(
                controller: textController,
                minLines: field.multiline ? 2 : 1,
                maxLines: field.multiline ? 5 : 1,
                onChanged: onTextChanged,
                decoration: InputDecoration(
                  hintText: field.hint.isEmpty ? null : field.hint,
                  filled: true,
                  fillColor: fill,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: moduleColor.withValues(alpha: 0.25)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        BorderSide(color: moduleColor.withValues(alpha: 0.25)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: moduleColor, width: 1.6),
                  ),
                ),
              ),
          },
        ],
      ),
    );
  }
}

/// Pilihan skala berlabel (DASS-21 / WHO-5): tombol + label makna.
class _ScaleOptions extends StatelessWidget {
  const _ScaleOptions({
    required this.field,
    required this.moduleColor,
    required this.value,
    required this.onSelect,
  });

  final TherapyWorksheetField field;
  final Color moduleColor;
  final int? value;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final fill = worksheetFieldFill(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in field.scaleValues)
              InkWell(
                onTap: () => onSelect?.call(v),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  constraints: const BoxConstraints(minWidth: 44),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == v ? moduleColor : fill,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: value == v
                          ? moduleColor
                          : moduleColor.withValues(alpha: 0.35),
                      width: value == v ? 2 : 1,
                    ),
                  ),
                  child: Text(
                    // Chip menampilkan label makna (bukan angka mentah).
                    field.scaleLabel(v),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: value == v ? Colors.white : moduleColor,
                    ),
                  ),
                ),
              ),
          ],
        ),
        if (value != null) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: moduleColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              // Hanya label makna — tanpa angka skor.
              field.scaleLabel(value!),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: moduleColor,
              ),
            ),
          ),
        ] else ...[
          const SizedBox(height: 6),
          Text(
            'Ketuk salah satu pilihan untuk menjawab.',
            style: TextStyle(
                fontSize: 11.5,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// Stepper angka (mis. jumlah siklus napas): tombol - / +.
class _NumberStepper extends StatelessWidget {
  const _NumberStepper({
    required this.value,
    required this.min,
    required this.max,
    required this.color,
    required this.onChanged,
  });

  final int value;
  final int min;
  final int max;
  final Color color;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _StepButton(
          icon: Icons.remove_rounded,
          color: color,
          onTap: value > min ? () => onChanged?.call(value - 1) : null,
        ),
        Container(
          width: 64,
          height: 42,
          alignment: Alignment.center,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Text(
            '$value',
            style: TextStyle(
                fontWeight: FontWeight.w900, fontSize: 17, color: color),
          ),
        ),
        _StepButton(
          icon: Icons.add_rounded,
          color: color,
          onTap: value < max ? () => onChanged?.call(value + 1) : null,
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.color, this.onTap});

  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: onTap == null ? Colors.black12 : color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: onTap == null
                  ? Colors.black12
                  : color.withValues(alpha: 0.35)),
        ),
        child: Icon(icon, color: onTap == null ? Colors.black38 : color),
      ),
    );
  }
}

/// Baris poin `1..N` dalam mode view-only (pasien): badge nomor tetap
/// + teks jawaban tersimpan, TANPA `TextField` (Q-6).
class _ReadOnlyPoints extends StatelessWidget {
  const _ReadOnlyPoints({
    required this.field,
    required this.moduleColor,
    required this.controllers,
  });

  final TherapyWorksheetField field;
  final Color moduleColor;
  final List<TextEditingController?> controllers;

  @override
  Widget build(BuildContext context) {
    final labels = field.effectivePointLabels();
    final count = field.pointCount == 0 ? controllers.length : field.pointCount;
    return Column(
      children: [
        for (var i = 0; i < count; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == count - 1 ? 0 : 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: moduleColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                        color: moduleColor,
                        fontWeight: FontWeight.w900,
                        fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Builder(builder: (context) {
                    final value = (i < controllers.length
                            ? controllers[i]?.text.trim()
                            : null) ??
                        '';
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (i < labels.length)
                          Text(
                            labels[i],
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant),
                          ),
                        const SizedBox(height: 2),
                        Text(
                          value.isEmpty ? '—' : value,
                          style: const TextStyle(fontSize: 13),
                        ),
                      ],
                    );
                  }),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Skala mini 0..max (untuk before/after).
class _MiniScale extends StatelessWidget {
  const _MiniScale({
    required this.min,
    required this.max,
    required this.color,
    required this.value,
    required this.onSelect,
  });

  final int min;
  final int max;
  final Color color;
  final int? value;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final fill = worksheetFieldFill(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var v = min; v <= max; v++)
          InkWell(
            onTap: () => onSelect?.call(v),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: value == v ? color : fill,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: value == v ? color : color.withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                '$v',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: value == v ? Colors.white : color,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Halaman daftar worksheet yang sudah disimpan (folder therapy).
class TherapySubmissionsScreen extends ConsumerStatefulWidget {
  const TherapySubmissionsScreen({super.key});

  @override
  ConsumerState<TherapySubmissionsScreen> createState() =>
      _TherapySubmissionsScreenState();
}

class _TherapySubmissionsScreenState
    extends ConsumerState<TherapySubmissionsScreen> {
  List<BackendTherapySubmission> _items = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'Login dulu untuk melihat worksheet.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final items = await ref
          .read(apiClientProvider)
          .listTherapySubmissions(accessToken: token);
      if (!mounted) return;
      setState(() {
        _items = items;
        _isLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  Future<void> _share(BackendTherapySubmission submission) async {
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    if (token == null || token.isEmpty) return;
    List<BackendPatientProfessionalLink> links;
    try {
      links = await ref
          .read(apiClientProvider)
          .listPatientProfessionalLinks(accessToken: token);
    } on Object {
      return;
    }
    final active = links.where((l) => l.status == 'active').toList();
    if (!mounted || active.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Belum ada profesional aktif yang terhubung.')),
      );
      return;
    }
    final api = ref.read(apiClientProvider);
    final pkgs = await api.listCarePackages(accessToken: token);
    final activeProIds = {
      for (final p in pkgs)
        if (p.isActive) p.professionalId,
    };
    final eligible = active
        .where((l) => activeProIds.contains(l.professionalUserId))
        .toList();
    if (!mounted) return;
    if (eligible.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Berbagi worksheet butuh paket sesi aktif dengan profesional.')),
      );
      return;
    }
    final chosen = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('Bagikan worksheet ke',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
              const SizedBox(height: 4),
              Text('Hanya profesional dengan paket sesi aktif.',
                  style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 12),
              for (final link in eligible)
                ListTile(
                  leading: const Icon(Icons.medical_services_rounded,
                      color: MalvaColors.seed),
                  title: Text(link.professionalDisplayName,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  onTap: () => Navigator.pop(ctx, link.professionalUserId),
                ),
            ],
          ),
        ),
      ),
    );
    if (chosen == null) return;
    try {
      await ref.read(apiClientProvider).shareTherapySubmission(
            accessToken: token,
            submissionId: submission.id,
            professionalId: chosen,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Worksheet dibagikan ke profesional.'),
          backgroundColor: MalvaColors.mint,
        ),
      );
      await _load();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }

  Future<void> _delete(BackendTherapySubmission submission) async {
    final token = ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus worksheet?'),
        content: Text('"${submission.title}" akan dihapus permanen.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(apiClientProvider).deleteTherapySubmission(
          accessToken: token, submissionId: submission.id);
      await _load();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Folder Therapy'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(_error!, textAlign: TextAlign.center),
                  ),
                )
              : _items.isEmpty
                  ? const EmptyState(
                      icon: Icons.folder_open_rounded,
                      title: 'Belum ada worksheet',
                      subtitle:
                          'Buka menu Psychological Therapy, pilih modul, isi '
                          'worksheet, lalu simpan. Hasilnya muncul di sini.',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(18),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final created = item.createdDateTime;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: SoftCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(item.title,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w900)),
                                      ),
                                      StatusPill(
                                        label: item.isShared
                                            ? 'Dibagikan'
                                            : 'Tersimpan',
                                        color: item.isShared
                                            ? MalvaColors.mint
                                            : MalvaColors.amber,
                                        icon: item.isShared
                                            ? Icons.send_rounded
                                            : Icons.folder_rounded,
                                      ),
                                    ],
                                  ),
                                  if (item.summary.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(item.summary,
                                        style: const TextStyle(
                                            fontSize: 12.5,
                                            fontStyle: FontStyle.italic)),
                                  ],
                                  if (created != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      '${created.day}/${created.month}/${created.year} '
                                      '${created.hour.toString().padLeft(2, '0')}:'
                                      '${created.minute.toString().padLeft(2, '0')}',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant),
                                    ),
                                  ],
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      OutlinedButton.icon(
                                        onPressed: () => _share(item),
                                        icon: const Icon(Icons.send_rounded,
                                            size: 16),
                                        label: const Text('Bagikan'),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () => _delete(item),
                                        icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            size: 16),
                                        label: const Text('Hapus'),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
    );
  }
}

/// Halaman katalog terapi (dipakai dari Home > Psychological Therapy).
class TherapyCatalogScreen extends StatelessWidget {
  const TherapyCatalogScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final categories =
        allTherapyModules.map((m) => m.category ?? 'Lainnya').toSet().toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Psychological Therapy'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Folder Therapy (worksheet tersimpan)',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const TherapySubmissionsScreen(),
              ),
            ),
            icon: const Icon(Icons.folder_copy_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SoftCard(
            color: MalvaColors.mint.withValues(alpha: 0.10),
            child: Row(
              children: [
                const Icon(Icons.folder_copy_rounded, color: MalvaColors.mint),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Isi worksheet pada tiap modul, lalu simpan ke folder '
                    'therapy — bisa diunduh & dikirim ke profesional (butuh paket sesi aktif).',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TherapySubmissionsScreen(),
                    ),
                  ),
                  child: const Text('Buka'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          for (final category in categories) ...[
            SectionLabel(category),
            for (final module
                in allTherapyModules.where((m) => m.category == category))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: ActionTile(
                  icon: module.icon ?? Icons.self_improvement_rounded,
                  title: module.title,
                  subtitle: module.description,
                  color: module.color ?? MalvaColors.seed,
                  maxSubtitleLines: 2,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => TherapyDetailScreen(module: module),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }
}

/// Viewer jawaban tersimpan untuk profesional: label + skor + jawaban.
/// Dipakai di dashboard profesional untuk worksheet yang dibagikan pasien.
/// Header (judul + status + tanggal) selalu terlihat; daftar jawaban
/// per pertanyaan disembunyikan sampai kartu dibuka agar tidak menumpuk.
class TherapySubmissionView extends StatelessWidget {
  const TherapySubmissionView({
    super.key,
    required this.moduleId,
    required this.title,
    required this.answers,
    this.summary = '',
    this.sharedAt,
  });

  final String moduleId;
  final String title;
  final Map<String, dynamic> answers;
  final String summary;
  final String? sharedAt;

  @override
  Widget build(BuildContext context) {
    final module = findTherapyModuleById(moduleId);
    final fields = module?.worksheetFields ?? const <TherapyWorksheetField>[];
    final color = module?.color ?? MalvaColors.seed;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;

    // Header ringkas: selalu terlihat & bisa di-tap untuk membuka detail.
    final header = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
            const StatusPill(
              label: 'Dibagikan',
              color: MalvaColors.mint,
              icon: Icons.send_rounded,
            ),
          ],
        ),
        if (sharedAt != null && sharedAt!.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(sharedAt!,
              style: TextStyle(fontSize: 11.5, color: onSurfaceVariant)),
        ],
      ],
    );

    // Untuk modul assessment, kartu hasil skor tetap tampil di bagian atas.
    final Widget? resultCard = (module != null && module.isAssessment)
        ? _AssessmentResultCard(
            moduleId: module.id,
            answers: {
              for (final f in fields)
                if (answers[f.id] is int) f.id: (answers[f.id] as int),
            },
          )
        : null;

    // Detail yang dilipat: ringkasan + daftar jawaban per pertanyaan.
    final detail = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (resultCard == null && summary.isNotEmpty) ...[
          Text(summary, style: const TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 10),
        ],
        if (fields.isEmpty)
          Text(answers.toString(), style: const TextStyle(fontSize: 12.5))
        else
          for (final field in fields) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: color.withValues(alpha: 0.18)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _fieldHeadline(field),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 12.5),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _answerText(field, answers[field.id]) ?? '(tidak dijawab)',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
      ],
    );

    return CollapsibleCard(
      header: header,
      body: resultCard,
      semanticLabel: 'Jawaban $title',
      child: detail,
    );
  }
}
