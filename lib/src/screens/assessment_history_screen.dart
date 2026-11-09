import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../models.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';
import '../widgets/therapy_library.dart';
import '../widgets/shared_record_detail.dart';
import '../time/wib.dart';

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
    this.sourceId = '',
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
  final String sourceId;

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

/// Format tanggal + jam assessment record (`dd/MM/yyyy HH:mm`) dalam waktu
/// LOKAL.
///
/// `createdAt` screening berasal dari server (UTC), jadi WAJIB ``
/// lebih dulu; tanpa itu screening dini hari WIB tampil mundur 7 jam dan
/// tanggalnya bisa jadi kemarin. Entri lokal (dibuat `wibNow()`) tidak
/// terpengaruh karena `` bersifat idempoten.
String formatAssessmentDate(DateTime? date) {
  if (date == null) return 'Tanggal tidak tercatat';
  return formatWibDateTime(date);
}

/// Ringkasan skor satu subskala screening, mis. `PHQ-9 12/27 (Sedang)`.
String _screeningScorePart(String label, BackendAssessmentSummary summary) {
  if (summary.score < 0 ||
      summary.maxScore <= 0 ||
      summary.score > summary.maxScore) {
    return '$label Belum tersedia';
  }
  final score = '$label ${summary.score}/${summary.maxScore}';
  // Level bisa kosong pada data lama; jangan tampilkan "( )" yang membingungkan.
  return summary.level.isEmpty
      ? score
      : '$score (${_screeningLevelLabel(summary.level)})';
}

String _screeningLevelLabel(String level) => switch (level.toLowerCase()) {
      'minimal' => 'Minimal',
      'mild' => 'Ringan',
      'moderate' => 'Sedang',
      'moderately_severe' => 'Cukup berat',
      'severe' => 'Berat',
      'crisis' => 'Krisis',
      _ => level,
    };

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
    sourceId: submission.id,
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
    sourceId: session.id,
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

List<AssessmentHistoryEntry> filterAssessmentHistory(
  Iterable<AssessmentHistoryEntry> entries, {
  required Set<String> instruments,
  bool oldestFirst = false,
}) {
  final filtered = entries
      .where((entry) => entry.isScreening
          ? instruments.contains('phq9') || instruments.contains('gad7')
          : instruments.contains(entry.moduleId))
      .toList();
  filtered.sort((a, b) {
    if (a.date == null || b.date == null) return _byDateDescending(a, b);
    return oldestFirst ? a.date!.compareTo(b.date!) : _byDateDescending(a, b);
  });
  return filtered;
}

class AssessmentHistoryFilters extends StatelessWidget {
  const AssessmentHistoryFilters(
      {super.key,
      required this.selected,
      required this.oldestFirst,
      required this.onChanged});
  final Set<String> selected;
  final bool oldestFirst;
  final void Function(Set<String>, bool) onChanged;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButton<bool>(
            value: oldestFirst,
            items: const [
              DropdownMenuItem(value: false, child: Text('Terbaru')),
              DropdownMenuItem(value: true, child: Text('Terlama')),
            ],
            onChanged: (value) {
              if (value != null) onChanged(selected, value);
            },
          ),
          Wrap(spacing: 8, runSpacing: 4, children: [
            for (final instrument in const {
              'who5': 'WHO-5',
              'phq9_gad7': 'PHQ-9 + GAD-7',
              'dass21': 'DASS-21'
            }.entries)
              FilterChip(
                label: Text(instrument.value),
                selected: instrument.key == 'phq9_gad7'
                    ? selected.contains('phq9') || selected.contains('gad7')
                    : selected.contains(instrument.key),
                onSelected: (enabled) {
                  final next = {...selected};
                  final keys = instrument.key == 'phq9_gad7'
                      ? {'phq9', 'gad7'}
                      : {instrument.key};
                  enabled ? next.addAll(keys) : next.removeAll(keys);
                  onChanged(next, oldestFirst);
                },
              ),
          ]),
          const SizedBox(height: 12),
        ],
      );
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
  bool requireAllSources = false,
}) async {
  final entries = <AssessmentHistoryEntry>[];
  final failures = <Object>[];

  // Sumber 1: worksheet asesmen DASS-21 / WHO-5.
  try {
    final submissions =
        await api.listTherapySubmissions(accessToken: accessToken, limit: 0);
    final seenIds = <String>{};
    for (final submission in submissions) {
      if (!isCompleteAssessmentAnswers(
          submission.moduleId, submission.answers)) {
        continue;
      }
      final id = submission.id.trim();
      if (id.isNotEmpty && !seenIds.add(id)) continue;
      entries.add(assessmentEntryFromSubmission(submission));
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
        limit: 0,
      );
      for (final session in screenings) {
        entries.add(assessmentEntryFromScreening(session));
      }
    } on Object catch (e) {
      failures.add(e);
    }
  }

  if (failures.isNotEmpty && (requireAllSources || entries.isEmpty)) {
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
  final owner = ProviderScope.containerOf(context, listen: false)
      .read(currentSessionProvider);
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
          child: Consumer(builder: (context, ref, _) {
            if (ref.watch(currentSessionProvider) != owner) {
              return const Text(
                  'Akun telah berubah. Buka kembali record milik akun ini.');
            }
            return _AssessmentDetailBody(entry: entry);
          }),
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
    if (screening != null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SharedRecordDetail.screening(screening: screening),
        const SizedBox(height: 14),
        Text('Skor assessment adalah alat bantu screening, bukan diagnosis.',
            style: TextStyle(fontSize: 11.5, color: onSurfaceVariant)),
        const SizedBox(height: 12),
        AssessmentRecordShareActions(entry: entry),
      ]);
    }
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
        if (entry.module?.isAssessment == true)
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
          const SizedBox(height: 12),
          AssessmentRecordShareActions(entry: entry),
        ],
      ],
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
  Set<String> _instruments = {'who5', 'gad7', 'phq9', 'dass21'};
  bool _oldestFirst = false;
  int _visibleCount = 5;

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
      if (!mounted || ref.read(currentSessionProvider) != session) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    } on Object catch (e) {
      if (!mounted || ref.read(currentSessionProvider) != session) return;
      setState(() {
        _isLoading = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentSessionProvider, (previous, next) {
      if (previous == next) return;
      _entries = const [];
      _visibleCount = 5;
      _load();
    });
    final visible = filterAssessmentHistory(_entries,
        instruments: _instruments, oldestFirst: _oldestFirst);
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
                  AssessmentHistoryFilters(
                    selected: _instruments,
                    oldestFirst: _oldestFirst,
                    onChanged: (instruments, oldest) => setState(() {
                      _instruments = instruments;
                      _oldestFirst = oldest;
                      _visibleCount = 5;
                    }),
                  ),
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
                  else if (visible.isEmpty)
                    const Text('Tidak ada hasil untuk filter ini.')
                  else ...[
                    for (final entry in visible.take(_visibleCount)) ...[
                      AssessmentHistoryCard(
                        entry: entry,
                        onTap: () => showAssessmentHistoryDetail(
                          context,
                          entry,
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (visible.length > _visibleCount)
                      TextButton(
                        onPressed: () => setState(() => _visibleCount += 5),
                        child: Text(
                            'Tampilkan lebih banyak (${visible.length - _visibleCount})'),
                      ),
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
/// Sharing uses the same server authorization as chat and worksheet records.
class AssessmentRecordShareActions extends ConsumerStatefulWidget {
  const AssessmentRecordShareActions({super.key, required this.entry});
  final AssessmentHistoryEntry entry;
  @override
  ConsumerState<AssessmentRecordShareActions> createState() =>
      _AssessmentRecordShareActionsState();
}

class _AssessmentRecordShareActionsState
    extends ConsumerState<AssessmentRecordShareActions> {
  late final AuthSession? _owner;
  bool _busy = false;
  @override
  void initState() {
    super.initState();
    _owner = ref.read(currentSessionProvider);
  }

  bool get _ownerMatches =>
      mounted && ref.read(currentSessionProvider) == _owner;
  void _toast(String message) {
    if (_ownerMatches)
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _share({required bool pdf}) async {
    if (_busy || !_ownerMatches || _owner?.role != UserRole.patient) return;
    final token = _owner?.accessToken;
    if (token == null || token.isEmpty) {
      _toast('Login dulu untuk membagikan hasil.');
      return;
    }
    setState(() => _busy = true);
    final entry = widget.entry;
    try {
      if (pdf) {
        final lines = <String>[formatAssessmentDate(entry.date)];
        final screening = entry.screening;
        if (screening != null) {
          lines.add(screeningScoreSummary(screening));
          if (screening.phq9.summary.isNotEmpty)
            lines.add(screening.phq9.summary);
          if (screening.gad7.summary.isNotEmpty)
            lines.add(screening.gad7.summary);
          if (screening.crisisFlag)
            lines.add(
                'Risiko krisis: segera hubungi bantuan darurat atau profesional terdekat.');
        } else if (entry.moduleId == 'who5') {
          lines.add(who5Summary(entry.answers));
        } else if (entry.moduleId == 'dass21') {
          final score = scoreDass21(entry.answers);
          lines.addAll([
            'Depresi: ${score.depression}/42 — ${score.depressionLevel}',
            'Kecemasan: ${score.anxiety}/42 — ${score.anxietyLevel}',
            'Stres: ${score.stress}/42 — ${score.stressLevel}'
          ]);
        }
        lines.add('Hasil screening adalah alat bantu, bukan diagnosis.');
        await ref.read(exportServiceProvider).sharePdf(
            title: entry.title,
            lines: lines,
            filename: 'malva_assessment_record.pdf',
            canShare: () => _ownerMatches);
        return;
      }
      if (entry.sourceId.isEmpty) {
        _toast('Record tersimpan belum tersedia untuk dibagikan.');
        return;
      }
      final api = ref.read(apiClientProvider);
      final packages = await api.listCarePackages(accessToken: token);
      if (!_ownerMatches) return;
      final links = await api.listPatientProfessionalLinks(accessToken: token);
      if (!_ownerMatches) return;
      final professionalIds = packages
          .where((p) => p.isActive)
          .map((p) => p.professionalId)
          .toSet();
      final eligible = links
          .where((link) =>
              link.status == 'active' &&
              professionalIds.contains(link.professionalUserId))
          .toList();
      if (eligible.isEmpty) {
        _toast(
            'Berbagi data membutuhkan paket aktif dengan profesional terhubung.');
        return;
      }
      final selected = await showDialog<BackendPatientProfessionalLink>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
                title: const Text('Bagikan ke profesional'),
                children: [
                  for (final link in eligible)
                    SimpleDialogOption(
                      onPressed: () => Navigator.pop(dialogContext, link),
                      child: Text(link.professionalDisplayName.isEmpty
                          ? 'Profesional terhubung'
                          : link.professionalDisplayName),
                    )
                ],
              ));
      if (selected == null || !_ownerMatches) return;
      final permission = await api.chatPermission(
          accessToken: token, professionalId: selected.professionalUserId);
      if (!_ownerMatches) return;
      if (!permission.canShare) {
        _toast('Berbagi data belum tersedia untuk profesional ini.');
        return;
      }
      if (entry.isScreening) {
        final screening = entry.screening!;
        final text = 'Hasil screening: ${screeningScoreSummary(screening)}.';
        await api.sendChatMessage(
            accessToken: token,
            recipientId: selected.professionalUserId,
            text: text,
            kind: 'assessment',
            metadata: {
              'source': 'screening',
              'screening_id': entry.sourceId,
              'overall_level': screening.overallLevel,
              'phq9_score': screening.phq9.score,
              'gad7_score': screening.gad7.score,
              'crisis_flag': screening.crisisFlag,
              'summary': text,
              if (entry.date != null) 'shared_at': wibIso(entry.date!),
            });
      } else {
        await api.shareTherapySubmission(
            accessToken: token,
            submissionId: entry.sourceId,
            professionalId: selected.professionalUserId);
      }
      _toast('Assessment record dibagikan ke profesional.');
    } on Object catch (error) {
      _toast('Gagal membagikan hasil: ${friendlyErrorMessage(error)}');
    } finally {
      if (_ownerMatches) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentSessionProvider, (previous, next) {
      if (next != _owner && mounted) Navigator.maybePop(context);
    });
    if (_owner?.role != UserRole.patient) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 8, children: [
      OutlinedButton.icon(
          onPressed: _busy ? null : () => _share(pdf: false),
          icon: const Icon(Icons.send_rounded),
          label: const Text('Bagikan ke profesional')),
      OutlinedButton.icon(
          onPressed: _busy ? null : () => _share(pdf: true),
          icon: const Icon(Icons.picture_as_pdf_rounded),
          label: const Text('Bagikan PDF')),
    ]);
  }
}

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
      if (!mounted || ref.read(currentSessionProvider) != session) return;
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
      if (!mounted || ref.read(currentSessionProvider) != session) return;
      setState(() {
        _entries = entries;
        _isLoading = false;
        _error = null;
      });
    } on Object catch (e) {
      if (!mounted || ref.read(currentSessionProvider) != session) return;
      setState(() {
        _isLoading = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentSessionProvider, (previous, next) {
      if (previous == next) return;
      setState(() {
        _entries = const [];
        _isLoading = true;
        _error = null;
      });
      _load();
    });
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
    // Tombol "Lihat semua" sengaja TIDAK dirender di sini: pintu masuk ke
    // halaman lengkap cukup satu, yaitu aksi pada `SectionLabel('Assessment
    // Record')` di halaman induk (`AssessmentListScreen`). Menampilkannya di
    // sini membuat dua tombol "Lihat semua" bertumpuk.
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
      ],
    );
  }
}
