import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';
import '../widgets/therapy_library.dart';

// ============================================================
// ASSESSMENT RECORD — riwayat skrining & assessment pasien.
//
// Halaman ini menampung DUA sumber hasil yang berbeda bentuk:
//   1. Screening PHQ-9 + GAD-7 (tabel screening di server).
//   2. Worksheet assessment DASS-21 / WHO-5 (submission therapy).
// Keduanya dulu tercampur dengan worksheet terapi dalam satu daftar,
// sehingga hasil skrining sulit dibedakan dari catatan latihan. Sekarang
// assessment record punya halaman sendiri dan daftar "Therapy Record"
// hanya berisi worksheet terapi (lihat `TherapySubmissionsScreen`).
//
// Model & pemuat data di file ini sengaja publik karena dipakai ulang oleh
// Health Record (`screens/record_screen.dart`) agar tampilan detail dan
// ringkasan skor tidak diduplikasi di dua tempat.
// ============================================================

/// Satu baris riwayat assessment record (screening atau worksheet assessment).
class AssessmentHistoryEntry {
  const AssessmentHistoryEntry({
    required this.kind,
    required this.title,
    required this.subtitle,
    this.date,
    this.moduleId = '',
    this.answers = const <String, dynamic>{},
    this.screening,
    this.isShared = false,
  });

  /// Hasil screening PHQ-9 + GAD-7 (tabel `screenings`).
  static const String kindScreening = 'screening';

  /// Hasil worksheet asesmen DASS-21 / WHO-5 (submission therapy).
  static const String kindWorksheet = 'worksheet';

  /// [kindScreening] atau [kindWorksheet].
  final String kind;
  final String title;

  /// Ringkasan skor siap tampil (sudah diformat baku dari server).
  final String subtitle;
  final DateTime? date;
  final String moduleId;
  final Map<String, dynamic> answers;
  final BackendScreeningSession? screening;
  final bool isShared;

  bool get isScreening => kind == kindScreening;

  /// Definisi modul asesmen (DASS-21/WHO-5) bila id-nya dikenal.
  TherapyModule? get module => findTherapyModuleById(moduleId);

  /// True bila entri ini assessment record, bukan worksheet terapi.
  bool get isAssessmentResult => isScreening || (module?.isAssessment ?? false);

  /// Ikon kartu: ikon modul bila dikenal, selain itu ikon generik per jenis.
  IconData get icon =>
      module?.icon ??
      (isScreening ? Icons.fact_check_rounded : Icons.self_improvement_rounded);

  /// Warna aksen kartu, konsisten dengan warna modulnya.
  Color get color =>
      module?.color ?? (isScreening ? MalvaColors.seed : MalvaColors.orchid);
}

/// Format tanggal + jam assessment record (`dd/MM/yyyy HH:mm`).
String formatAssessmentDate(DateTime? date) {
  if (date == null) return 'Tanggal tidak tercatat';
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(date.day)}/${two(date.month)}/${date.year} '
      '${two(date.hour)}:${two(date.minute)}';
}

/// Ringkasan skor satu subskala screening, mis. `PHQ-9 12/27 (Sedang)`.
String _screeningScorePart(String label, BackendAssessmentSummary summary) {
  final score = '$label ${summary.score}/${summary.maxScore}';
  // Level bisa kosong pada data lama; jangan tampilkan "( )" yang membingungkan.
  return summary.level.isEmpty ? score : '$score (${summary.level})';
}

/// Ringkasan skor screening PHQ-9 + GAD-7 dalam satu baris.
String screeningScoreSummary(BackendScreeningSession session) =>
    '${_screeningScorePart('PHQ-9', session.phq9)} • '
    '${_screeningScorePart('GAD-7', session.gad7)}';

/// Bungkus submission worksheet menjadi entri riwayat.
AssessmentHistoryEntry assessmentEntryFromSubmission(
  BackendTherapySubmission submission,
) {
  final module = findTherapyModuleById(submission.moduleId);
  return AssessmentHistoryEntry(
    kind: AssessmentHistoryEntry.kindWorksheet,
    title: submission.title.isEmpty
        ? (module?.title ?? 'Assessment record')
        : submission.title,
    subtitle: submission.summary,
    date: submission.createdDateTime,
    moduleId: submission.moduleId,
    // `answers` mentah dipakai apa adanya supaya penanda versi skala
    // (`scale_version`) ikut terbawa ke kartu skor.
    answers: submission.answers,
    isShared: submission.isShared,
  );
}

/// Bungkus satu sesi screening menjadi entri riwayat.
AssessmentHistoryEntry assessmentEntryFromScreening(
  BackendScreeningSession session,
) {
  return AssessmentHistoryEntry(
    kind: AssessmentHistoryEntry.kindScreening,
    title: 'Screening PHQ-9 + GAD-7',
    subtitle: screeningScoreSummary(session),
    date: session.createdAt,
    screening: session,
  );
}

/// Urutkan entri terbaru dulu; entri tanpa tanggal ditaruh paling akhir.
int _byDateDescending(AssessmentHistoryEntry a, AssessmentHistoryEntry b) {
  final dateA = a.date;
  final dateB = b.date;
  if (dateA == null && dateB == null) return 0;
  if (dateA == null) return 1;
  if (dateB == null) return -1;
  return dateB.compareTo(dateA);
}

/// Muat seluruh riwayat assessment record (worksheet assessment + screening).
///
/// Tiap sumber dimuat dengan try/catch sendiri: kegagalan satu endpoint tidak
/// boleh mengosongkan hasil dari endpoint lain. Bila SEMUA sumber gagal
/// (tidak ada satu entri pun), error pertama dilempar agar layar menampilkan
/// pesan gagal-muat, bukan empty state yang menyesatkan.
///
/// [patientId] kosong = lewati panggilan screening (server menolak
/// `patient_id` kosong dengan error 400).
Future<List<AssessmentHistoryEntry>> loadAssessmentHistory({
  required MalvaApiClient api,
  required String accessToken,
  String? patientId,
}) async {
  final entries = <AssessmentHistoryEntry>[];
  final failures = <Object>[];

  // Sumber 1: worksheet asesmen DASS-21 / WHO-5.
  try {
    final submissions =
        await api.listTherapySubmissions(accessToken: accessToken);
    for (final submission in submissions) {
      if (findTherapyModuleById(submission.moduleId)?.isAssessment == true) {
        entries.add(assessmentEntryFromSubmission(submission));
      }
    }
  } on Object catch (e) {
    failures.add(e);
  }

  // Sumber 2: riwayat screening PHQ-9 + GAD-7.
  final resolvedPatientId = (patientId ?? '').trim();
  if (resolvedPatientId.isNotEmpty) {
    try {
      final screenings = await api.listScreenings(
        accessToken: accessToken,
        patientId: resolvedPatientId,
        limit: 50,
      );
      for (final session in screenings) {
        entries.add(assessmentEntryFromScreening(session));
      }
    } on Object catch (e) {
      failures.add(e);
    }
  }

  if (entries.isEmpty && failures.isNotEmpty) {
    throw failures.first;
  }

  entries.sort(_byDateDescending);
  return entries;
}

/// Tampilkan detail satu assessment record dalam bottom sheet.
///
/// Dipakai bersama oleh [AssessmentHistoryScreen], [AssessmentHistoryPreview],
/// dan Health Record supaya satu entri selalu terbuka dengan tampilan sama.
Future<void> showAssessmentHistoryDetail(
  BuildContext context,
  AssessmentHistoryEntry entry,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.85,
        ),
        // Scrollable: detail DASS-21 (tiga subskala + tabel rentang) bisa
        // lebih tinggi dari layar.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
          child: _AssessmentDetailBody(entry: entry),
        ),
      ),
    ),
  );
}

/// Isi bottom sheet detail: judul, tanggal, lalu kartu sesuai jenis hasil.
class _AssessmentDetailBody extends StatelessWidget {
  const _AssessmentDetailBody({required this.entry});

  final AssessmentHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    final screening = entry.screening;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundColor: entry.color.withValues(alpha: 0.14),
              child: Icon(entry.icon, color: entry.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatAssessmentDate(entry.date),
                    style: TextStyle(fontSize: 12, color: onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (entry.isShared)
              const StatusPill(
                label: 'Dibagikan',
                color: MalvaColors.mint,
                icon: Icons.send_rounded,
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (screening != null) ...[
          _ScreeningScoreCard(
            title: 'PHQ-9 — Depresi',
            summary: screening.phq9,
            color: MalvaColors.seed,
          ),
          const SizedBox(height: 10),
          _ScreeningScoreCard(
            title: 'GAD-7 — Kecemasan',
            summary: screening.gad7,
            color: MalvaColors.mint,
          ),
          if (screening.crisisFlag) ...[
            const SizedBox(height: 10),
            SoftCard(
              color: MalvaColors.danger.withValues(alpha: 0.08),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.health_and_safety_rounded,
                      color: MalvaColors.danger),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Screening ini menandai risiko krisis. Segera hubungi '
                      'bantuan darurat atau profesional terdekat.',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 12.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ] else if (entry.module?.isAssessment == true)
          AssessmentResultCard(
            moduleId: entry.moduleId,
            answers: entry.answers,
          )
        else
          _WorksheetAnswerList(
            moduleId: entry.moduleId,
            answers: entry.answers,
            summary: entry.subtitle,
            color: entry.color,
          ),
        // Disclaimer hanya relevan untuk hasil skrining/asesmen. Worksheet
        // terapi (mis. "Latihan Pernapasan Teratur") bukan hasil ukur, jadi
        // tidak perlu catatan ini.
        if (entry.isAssessmentResult) ...[
          const SizedBox(height: 14),
          Text(
            'Skor assessment adalah alat bantu screening, bukan diagnosis.',
            style: TextStyle(fontSize: 11.5, color: onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// Kartu ringkas satu subskala screening (skor/maks + level + ringkasan).
class _ScreeningScoreCard extends StatelessWidget {
  const _ScreeningScoreCard({
    required this.title,
    required this.summary,
    required this.color,
  });

  final String title;
  final BackendAssessmentSummary summary;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final level = summary.level;
    return SoftCard(
      color: color.withValues(alpha: 0.07),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 14),
                ),
              ),
              if (level.isNotEmpty) StatusPill(label: level, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${summary.score}/${summary.maxScore}',
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
          ),
          if (summary.summary.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              summary.summary,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

/// Daftar jawaban worksheet non-assessment (therapy record) di dalam detail.
class _WorksheetAnswerList extends StatelessWidget {
  const _WorksheetAnswerList({
    required this.moduleId,
    required this.answers,
    required this.summary,
    required this.color,
  });

  final String moduleId;
  final Map<String, dynamic> answers;
  final String summary;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final items = therapyAnswerEntries(moduleId: moduleId, answers: answers);
    if (items.isEmpty && summary.isEmpty) {
      return Text(
        'Jawaban worksheet ini tidak tersimpan.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (summary.isNotEmpty) ...[
          Text(summary, style: const TextStyle(fontStyle: FontStyle.italic)),
          const SizedBox(height: 10),
        ],
        for (final item in items) ...[
          Container(
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
                  item.label,
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 12.5),
                ),
                const SizedBox(height: 4),
                Text(item.answer, style: const TextStyle(fontSize: 13)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// Halaman daftar lengkap assessment record (screening + worksheet assessment).
class AssessmentHistoryScreen extends ConsumerStatefulWidget {
  const AssessmentHistoryScreen({super.key});

  @override
  ConsumerState<AssessmentHistoryScreen> createState() =>
      _AssessmentHistoryScreenState();
}

class _AssessmentHistoryScreenState
    extends ConsumerState<AssessmentHistoryScreen> {
  List<AssessmentHistoryEntry> _entries = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    if (token == null || token.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'Login dulu untuk melihat assessment record.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final entries = await loadAssessmentHistory(
        api: ref.read(apiClientProvider),
        accessToken: token,
        patientId: session?.backendUserId,
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            GradientHeader(
              title: 'Assessment Record',
              subtitle: 'Riwayat skrining & asesmen yang tersimpan',
              leading: IconButton(
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
              trailing: IconButton(
                tooltip: 'Muat ulang',
                onPressed: _isLoading ? null : _load,
                icon: const Icon(Icons.refresh_rounded, color: Colors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isLoading)
                    const SoftCard(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    )
                  else if (_error != null)
                    FriendlyErrorCard(error: _error!, onRetry: _load)
                  else if (_entries.isEmpty)
                    const EmptyState(
                      icon: Icons.fact_check_rounded,
                      title: 'Belum ada assessment record',
                      subtitle:
                          'Isi DASS-21 atau WHO-5 dari menu Assessment, atau '
                          'selesaikan screening PHQ-9 + GAD-7. Hasilnya '
                          'tersimpan di sini.',
                    )
                  else
                    for (final entry in _entries) ...[
                      AssessmentHistoryCard(
                        entry: entry,
                        onTap: () => showAssessmentHistoryDetail(
                          context,
                          entry,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kartu satu entri assessment record (dipakai halaman riwayat).
class AssessmentHistoryCard extends StatelessWidget {
  const AssessmentHistoryCard({
    super.key,
    required this.entry,
    required this.onTap,
  });

  final AssessmentHistoryEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    return SoftCard(
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: entry.color.withValues(alpha: 0.14),
            child: Icon(entry.icon, color: entry.color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 14),
                ),
                if (entry.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    entry.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: onSurfaceVariant),
                  ),
                ],
                const SizedBox(height: 3),
                Text(
                  formatAssessmentDate(entry.date),
                  style: TextStyle(fontSize: 11.5, color: onSurfaceVariant),
                ),
              ],
            ),
          ),
          if (entry.isShared) ...[
            const SizedBox(width: 8),
            const StatusPill(
              label: 'Dibagikan',
              color: MalvaColors.mint,
              icon: Icons.send_rounded,
            ),
          ],
        ],
      ),
    );
  }
}

/// Ringkasan assessment record terbaru untuk halaman Assessment.
///
/// Memuat datanya sendiri dan sengaja TIDAK menampilkan spinner besar:
/// halaman induk tidak boleh tertahan menunggu endpoint ini. Bila kosong atau
/// gagal, yang tampil hanya kartu ajakan/keterangan ringkas.
class AssessmentHistoryPreview extends ConsumerStatefulWidget {
  const AssessmentHistoryPreview({super.key});

  @override
  ConsumerState<AssessmentHistoryPreview> createState() =>
      _AssessmentHistoryPreviewState();
}

class _AssessmentHistoryPreviewState
    extends ConsumerState<AssessmentHistoryPreview> {
  List<AssessmentHistoryEntry> _entries = const [];
  bool _isLoading = true;
  String? _error;

  /// Batas entri yang ditampilkan di halaman induk.
  static const int _maxPreview = 3;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = ref.read(currentSessionProvider);
    final token = session?.accessToken;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Login dulu untuk melihat assessment record.';
      });
      return;
    }
    try {
      final entries = await loadAssessmentHistory(
        api: ref.read(apiClientProvider),
        accessToken: token,
        patientId: session?.backendUserId,
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
        _error = null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  void _openAll() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AssessmentHistoryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    // Placeholder ringkas: baris teks + indikator kecil, bukan spinner besar.
    if (_isLoading) {
      return SoftCard(
        child: Row(
          children: [
            const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Memuat assessment record…',
              style: TextStyle(fontSize: 12.5, color: onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    if (_error != null) {
      return SoftCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.cloud_off_rounded, color: MalvaColors.amber),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Assessment record belum bisa dimuat. $_error',
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
            TextButton(onPressed: _load, child: const Text('Coba')),
          ],
        ),
      );
    }
    if (_entries.isEmpty) {
      return const SoftCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.fact_check_outlined, color: MalvaColors.seed),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Belum ada assessment record. Isi DASS-21 atau WHO-5 di bawah — '
                'hasilnya akan tersimpan di sini.',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
              ),
            ),
          ],
        ),
      );
    }

    final preview = _entries.take(_maxPreview).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in preview) ...[
          AssessmentHistoryCard(
            entry: entry,
            onTap: () => showAssessmentHistoryDetail(context, entry),
          ),
          const SizedBox(height: 10),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _openAll,
            child: const Text('Lihat semua'),
          ),
        ),
      ],
    );
  }
}
