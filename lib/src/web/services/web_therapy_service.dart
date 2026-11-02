import '../../time/wib.dart';
import '../../widgets/therapy_library.dart';

// ============================================================
// TERAPI WEB — LAPISAN DATA (read-only terhadap therapy_library)
// ============================================================
//
// Definisi modul TIDAK diduplikasi: seluruh konten (judul, deskripsi, langkah,
// field worksheet, label skala) berasal dari `lib/src/widgets/therapy_library.dart`.
// Berkas ini hanya menambah hal yang khusus web: pengelompokan kategori,
// penampung jawaban form, pembentuk payload server (identik dengan mobile), dan
// teks ringkasan untuk dialog/unduhan.

/// Satu kelompok modul berdasarkan `category` di therapy_library.
class WebTherapyGroup {
  const WebTherapyGroup({required this.category, required this.modules});

  final String category;
  final List<TherapyModule> modules;
}

/// Urutan kategori yang diinginkan di hub. Kategori lain tetap tampil setelah
/// daftar ini (urut alfabetis) agar modul baru tidak pernah "hilang".
const List<String> _webCategoryOrder = <String>[
  'Assessment',
  'CBT',
  'DBT',
  'Relaksasi',
  'Psikoedukasi',
];

/// Semua modul yang tampil di web: dua asesmen (DASS-21, WHO-5) + 8 worksheet.
///
/// `allTherapyModules` di therapy_library sengaja HANYA berisi worksheet, jadi
/// dua modul asesmen ditambahkan di sini agar hub menampilkan 10 modul.
List<TherapyModule> webTherapyModules() => <TherapyModule>[
      dass21Module,
      who5Module,
      ...allTherapyModules,
    ];

/// Modul dikelompokkan per kategori, dengan urutan kategori yang stabil.
List<WebTherapyGroup> webTherapyGroups() {
  final grouped = <String, List<TherapyModule>>{};
  for (final TherapyModule module in webTherapyModules()) {
    final raw = (module.category ?? '').trim();
    final category = raw.isEmpty ? 'Lainnya' : raw;
    grouped.putIfAbsent(category, () => <TherapyModule>[]).add(module);
  }
  int rank(String category) {
    final index = _webCategoryOrder.indexOf(category);
    return index < 0 ? _webCategoryOrder.length : index;
  }

  final categories = grouped.keys.toList()
    ..sort((String a, String b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : a.compareTo(b);
    });
  return categories
      .map((String category) =>
          WebTherapyGroup(category: category, modules: grouped[category]!))
      .toList(growable: false);
}

/// Cari modul berdasarkan id (delegasi ke therapy_library).
TherapyModule? webTherapyModuleById(String id) => findTherapyModuleById(id);

/// True bila modul adalah asesmen berskor (di web diarahkan ke `/asesmen`).
bool webTherapyIsAssessment(TherapyModule module) => module.isAssessment;

/// Penampung jawaban form worksheet.
///
/// Bentuk map-nya sengaja mutable agar widget cukup memanggil satu callback
/// `onChanged` setiap kali satu nilai berubah, tanpa membuat state baru.
class WebWorksheetAnswers {
  /// Jawaban field `text` (id field → teks).
  final Map<String, String> texts = <String, String>{};

  /// Jawaban field `scale` (id field → nilai).
  final Map<String, int> scales = <String, int>{};

  /// Jawaban field `number` (id field → nilai).
  final Map<String, int> numbers = <String, int>{};

  /// Jawaban field `points` (id field → daftar isi per poin, panjang =
  /// `pointCount`). Nilai kosong tetap disimpan agar indeks poin stabil.
  final Map<String, List<String>> points = <String, List<String>>{};

  /// Jawaban field `choice` (id field → satu opsi).
  final Map<String, String> choices = <String, String>{};

  /// Jawaban field `choiceMulti` (id field → himpunan opsi).
  final Map<String, Set<String>> multiChoices = <String, Set<String>>{};

  /// Nilai "sebelum" untuk field `beforeAfter`.
  final Map<String, int> before = <String, int>{};

  /// Nilai "sesudah" untuk field `beforeAfter`.
  final Map<String, int> after = <String, int>{};

  /// Jumlah field yang sudah punya jawaban (dipakai indikator progres).
  int filledCount(TherapyModule module) {
    var count = 0;
    for (final TherapyWorksheetField field in module.worksheetFields) {
      if (_isFilled(field)) count++;
    }
    return count;
  }

  bool _isFilled(TherapyWorksheetField field) {
    switch (field.kind) {
      case TherapyFieldKind.text:
        return (texts[field.id] ?? '').trim().isNotEmpty;
      case TherapyFieldKind.scale:
        return scales[field.id] != null;
      case TherapyFieldKind.number:
        return numbers[field.id] != null;
      case TherapyFieldKind.points:
        final list = points[field.id];
        return list != null && list.any((String p) => p.trim().isNotEmpty);
      case TherapyFieldKind.choice:
        return (choices[field.id] ?? '').isNotEmpty;
      case TherapyFieldKind.choiceMulti:
        return (multiChoices[field.id] ?? const <String>{}).isNotEmpty;
      case TherapyFieldKind.beforeAfter:
        return before[field.id] != null || after[field.id] != null;
    }
  }

  bool hasAnyAnswer(TherapyModule module) => filledCount(module) > 0;

  /// Pesan validasi (Indonesia) atau `null` bila boleh disimpan.
  ///
  /// Aturannya sama dengan mobile: asesmen wajib lengkap; worksheet cukup
  /// minimal satu kolom terisi (tidak ada paksaan mengisi semua kolom karena
  /// pasien boleh mengerjakan sebagian latihan).
  String? validationError(TherapyModule module) {
    if (module.isAssessment) {
      final missing = module.worksheetFields
          .where((TherapyWorksheetField f) => f.isScale && scales[f.id] == null)
          .length;
      if (missing > 0) {
        return 'Masih ada $missing pertanyaan belum dijawab. Lengkapi dulu '
            'agar skor valid.';
      }
      return null;
    }
    if (!hasAnyAnswer(module)) {
      return 'Isi minimal satu kolom worksheet dulu.';
    }
    return null;
  }

  /// Payload `answers` untuk `POST /v1/therapy-submissions`.
  ///
  /// Bentuknya IDENTIK dengan mobile (`_answers()` di therapy_library):
  /// `points` = List<String>, `choiceMulti` = List<String>, `beforeAfter` =
  /// `{before, after}`. Modul asesmen menambahkan penanda `scale_version`.
  Map<String, dynamic> toPayload(TherapyModule module) {
    final out = <String, dynamic>{};
    for (final TherapyWorksheetField field in module.worksheetFields) {
      switch (field.kind) {
        case TherapyFieldKind.text:
          out[field.id] = (texts[field.id] ?? '').trim();
        case TherapyFieldKind.scale:
          final value = scales[field.id];
          if (value != null) out[field.id] = value;
        case TherapyFieldKind.number:
          final value = numbers[field.id];
          if (value != null) out[field.id] = value;
        case TherapyFieldKind.points:
          final raw = points[field.id];
          final list = <String>[
            for (var i = 0; i < field.pointCount; i++)
              (raw != null && i < raw.length ? raw[i] : '').trim(),
          ];
          if (list.any((String p) => p.isNotEmpty)) out[field.id] = list;
        case TherapyFieldKind.choice:
          final value = choices[field.id] ?? '';
          if (value.isNotEmpty) out[field.id] = value;
        case TherapyFieldKind.choiceMulti:
          final values = multiChoices[field.id];
          if (values != null && values.isNotEmpty) {
            out[field.id] = values.toList(growable: false);
          }
        case TherapyFieldKind.beforeAfter:
          final b = before[field.id];
          final a = after[field.id];
          if (b != null || a != null) {
            out[field.id] = <String, dynamic>{
              if (b != null) 'before': b,
              if (a != null) 'after': a,
            };
          }
      }
    }
    if (module.isAssessment) {
      out[scaleVersionKey] = standardizedScaleVersion;
      out[scaleMinKey] = 0;
      out[scaleMaxKey] = module.id == 'who5' ? 5 : 3;
    }
    return out;
  }

  /// Isi jawaban yang sudah ada (untuk membuka ulang submission tersimpan).
  void loadFrom(TherapyModule module, Map<String, dynamic> answers) {
    for (final TherapyWorksheetField field in module.worksheetFields) {
      final raw = answers[field.id];
      switch (field.kind) {
        case TherapyFieldKind.text:
          if (raw is String) texts[field.id] = raw;
        case TherapyFieldKind.scale:
          if (raw is num) scales[field.id] = raw.toInt();
        case TherapyFieldKind.number:
          if (raw is num) numbers[field.id] = raw.toInt();
        case TherapyFieldKind.points:
          if (raw is List) {
            points[field.id] = raw
                .map((Object? e) => e?.toString() ?? '')
                .toList(growable: false);
          }
        case TherapyFieldKind.choice:
          if (raw is String) choices[field.id] = raw;
        case TherapyFieldKind.choiceMulti:
          if (raw is List) {
            multiChoices[field.id] =
                raw.map((Object? e) => e?.toString() ?? '').toSet();
          }
        case TherapyFieldKind.beforeAfter:
          if (raw is Map) {
            final b = raw['before'];
            final a = raw['after'];
            if (b is num) before[field.id] = b.toInt();
            if (a is num) after[field.id] = a.toInt();
          }
      }
    }
  }
}

/// Teks ringkasan satu worksheet (dialog sukses & unduhan `.txt`).
///
/// Memakai `therapyAnswerEntries` dari therapy_library sehingga format label
/// dan jawaban sama dengan viewer profesional di mobile.
String webWorksheetSummaryText({
  required TherapyModule module,
  required Map<String, dynamic> answers,
  DateTime? createdAt,
}) {
  final entries = therapyAnswerEntries(moduleId: module.id, answers: answers);
  final buffer = StringBuffer()
    ..writeln('Malva — ${module.title}')
    ..writeln('Kategori: ${module.category ?? 'Lainnya'}');
  if (createdAt != null) {
    buffer.writeln('Waktu (WIB): ${formatWibDateTime(createdAt)}');
  }
  buffer.writeln();
  if (entries.isEmpty) {
    buffer.writeln('(belum ada jawaban tersimpan)');
  } else {
    for (final TherapyAnswerEntry entry in entries) {
      buffer
        ..writeln(entry.label)
        ..writeln('  ${entry.answer}')
        ..writeln();
    }
  }
  buffer.writeln(
    'Catatan: worksheet ini adalah latihan mandiri, bukan diagnosis. '
    'Diskusikan dengan profesional bila diperlukan.',
  );
  return buffer.toString();
}

/// Nama berkas unduhan yang aman (tanpa spasi/simbol aneh).
String webWorksheetFileName(TherapyModule module, DateTime createdAt) {
  final slug = module.title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final date = formatWibDate(createdAt).replaceAll('/', '-');
  return 'malva-${slug.isEmpty ? 'worksheet' : slug}-$date.txt';
}
