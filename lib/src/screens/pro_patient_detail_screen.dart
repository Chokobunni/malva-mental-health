import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';
import '../widgets/therapy_library.dart';
import 'chat_screen.dart';

// ============================================================
// PRO PATIENT DETAIL — semua yang dibutuhkan profesional untuk
// satu pasien, dari semua scope sisi pasien:
//   Paket & sesi • Screening & review • Worksheet (DASS/WHO-5 +
//   skor) • Goals & habits • Mood/diary (read-only, tanpa balas)
//   • Kiriman chat pasien • Health record & obat • Catatan sesi.
// ============================================================

class ProPatientDetailScreen extends ConsumerStatefulWidget {
  const ProPatientDetailScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    this.session,
    this.apiClient,
  });

  final String patientId;
  final String patientName;
  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<ProPatientDetailScreen> createState() =>
      _ProPatientDetailScreenState();
}

class _ProPatientDetailScreenState extends ConsumerState<ProPatientDetailScreen> {
  List<BackendCarePackage> _packages = const [];
  List<BackendCareSession> _sessions = const [];
  List<BackendScreeningSession> _screenings = const [];
  List<BackendTherapySubmission> _worksheets = const [];
  List<BackendGoal> _goals = const [];
  List<BackendMoodCheckin> _moods = const [];
  List<BackendDiaryEntry> _diaries = const [];
  List<BackendChatMessage> _shares = const [];
  List<BackendProfessionalNote> _notes = const [];
  List<BackendMedication> _medications = const [];
  List<BackendTimelineEvent> _timeline = const [];
  BackendHealthRecord? _healthRecord;
  String? _restricted;
  bool _isLoading = true;
  String? _error;

  MalvaApiClient get _api => widget.apiClient ?? ref.read(apiClientProvider);
  String? get _token {
    final t = widget.session?.accessToken;
    return (t == null || t.isEmpty) ? null : t;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = _token;
    if (token == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Login dulu.';
        });
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
      _restricted = null;
    });
    try {
      Future<T?> safely<T>(Future<T> Function() load) async {
        try {
          return await load();
        } on MalvaApiException catch (e) {
          if (e.statusCode == 403) {
            if (mounted) {
              setState(() => _restricted = (_restricted == null)
                  ? e.message
                  : '$_restricted • ${e.message}');
            }
          }
          return null;
        } on Object {
          return null;
        }
      }

      final results = await Future.wait([
        _api.listCarePackages(accessToken: token, patientId: widget.patientId),
        _api.listCareSessions(
            accessToken: token, scope: 'all', patientId: widget.patientId),
        _api.listScreenings(
            accessToken: token, patientId: widget.patientId, limit: 10),
        _api.listTherapySubmissions(
            accessToken: token, patientId: widget.patientId),
        safely(() => _api.listGoals(
            accessToken: token, patientId: widget.patientId)),
        safely(() => _api.listMoodCheckins(
            accessToken: token, patientId: widget.patientId, limit: 10)),
        safely(() => _api.listDiaryEntries(
            accessToken: token, patientId: widget.patientId, limit: 10)),
        safely(() => _api.listProfessionalNotes(
            accessToken: token, patientId: widget.patientId, limit: 10)),
        safely(() => _api.listMedications(
            accessToken: token, patientId: widget.patientId, limit: 30)),
        safely(() => _api.listTimeline(
            accessToken: token, patientId: widget.patientId, limit: 20)),
      ]);
      List<BackendChatMessage> shares = const [];
      try {
        final myId = widget.session?.backendUserId ??
            widget.session?.identifier ??
            '';
        if (myId.isNotEmpty) {
          final msgs = await _api.listMessages(
            accessToken: token,
            patientId: widget.patientId,
            professionalId: myId,
          );
          shares = msgs
              .where((m) => m.kind != 'text')
              .toList(growable: false);
        }
      } on Object {
        // Riwayat kiriman opsional.
      }
      BackendHealthRecord? record;
      try {
        record = await _api.getHealthRecord(
          accessToken: token,
          patientId: widget.patientId,
        );
      } on MalvaApiException catch (e) {
        if (e.statusCode == 403 && mounted) {
          setState(() => _restricted = 'Health Record tidak dibagikan pasien.');
        }
      } on Object {
        // opsional
      }
      if (!mounted) return;
      setState(() {
        _packages = results[0] as List<BackendCarePackage>;
        _sessions = results[1] as List<BackendCareSession>;
        _screenings = results[2] as List<BackendScreeningSession>;
        _worksheets = results[3] as List<BackendTherapySubmission>;
        _goals = (results[4] as List<BackendGoal>?) ?? const [];
        _moods = (results[5] as List<BackendMoodCheckin>?) ?? const [];
        _diaries = (results[6] as List<BackendDiaryEntry>?) ?? const [];
        _notes =
            (results[7] as List<BackendProfessionalNote>?) ?? const [];
        _medications =
            (results[8] as List<BackendMedication>?) ?? const [];
        _timeline =
            (results[9] as List<BackendTimelineEvent>?) ?? const [];
        _shares = shares;
        _healthRecord = record;
        _isLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorMessage(e);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.patientName),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Chat sesi',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(
                  otherUserName: widget.patientName,
                  otherUserId: widget.patientId,
                ),
              ),
            ),
            icon: const Icon(Icons.chat_bubble_rounded),
          ),
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Center(child: Text(_error!))
            else ...[
              if (_restricted != null)
                SoftCard(
                  color: MalvaColors.amber.withValues(alpha: 0.12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.lock_outline_rounded,
                          color: MalvaColors.amber),
                      const SizedBox(width: 10),
                      Expanded(child: Text(_restricted!)),
                    ],
                  ),
                ),
              if (_restricted != null) const SizedBox(height: 12),
              const SectionLabel('Paket & sesi'),
              if (_packages.isEmpty)
                const EmptyState(
                  icon: Icons.card_membership_outlined,
                  title: 'Belum ada paket',
                  subtitle: 'Pasien belum membeli paket denganmu.',
                )
              else
                for (final p in _packages) ...[
                  SoftCard(
                    color: p.isActive
                        ? MalvaColors.mint.withValues(alpha: 0.08)
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Paket ${p.totalSessions} sesi / ${p.validityDays} hari',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900),
                              ),
                            ),
                            StatusPill(
                              label: p.status,
                              color: p.isActive
                                  ? MalvaColors.mint
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        ProgressStrip(
                          value: p.totalSessions == 0
                              ? 0
                              : p.usedSessions / p.totalSessions,
                          color: MalvaColors.seed,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${p.remainingSessions}/${p.totalSessions} sesi tersisa',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              if (_sessions.isNotEmpty) ...[
                for (final s in _sessions.take(5)) ...[
                  SoftCard(
                    child: Row(
                      children: [
                        Icon(
                            s.isVideo
                                ? Icons.videocam_rounded
                                : Icons.chat_bubble_rounded,
                            color: MalvaColors.seed),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${s.scheduledAt ?? '-'} • ${s.status}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
              const SizedBox(height: 6),
              const SectionLabel('Screening (PHQ-9 / GAD-7)'),
              if (_screenings.isEmpty)
                const EmptyState(
                  icon: Icons.fact_check_outlined,
                  title: 'Belum ada screening',
                  subtitle: 'Hasil screening pasien muncul di sini.',
                )
              else
                for (final sc in _screenings.take(3)) ...[
                  CollapsibleCard(
                    key: ValueKey('screening-${sc.id}'),
                    semanticLabel: 'Detail screening ${_screeningDate(sc.createdAt)}',
                    header: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'PHQ-9 ${sc.phq9.score} • GAD-7 ${sc.gad7.score}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900),
                              ),
                            ),
                            if (sc.crisisFlag)
                              const StatusPill(
                                label: 'CRISIS',
                                color: MalvaColors.danger,
                                icon: Icons.warning_amber_rounded,
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_screeningDate(sc.createdAt)} • Overall: ${sc.overallLevel}',
                          style: TextStyle(
                              color: sc.crisisFlag
                                  ? MalvaColors.danger
                                  : null,
                              fontWeight: FontWeight.w700,
                              fontSize: 12.5),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ScreeningInstrumentDetail(
                          name: 'PHQ-9',
                          score: sc.phq9.score,
                          maxScore: sc.phq9.maxScore,
                          level: sc.phq9.level,
                          summary: sc.phq9.summary,
                        ),
                        const SizedBox(height: 12),
                        _ScreeningInstrumentDetail(
                          name: 'GAD-7',
                          score: sc.gad7.score,
                          maxScore: sc.gad7.maxScore,
                          level: sc.gad7.level,
                          summary: sc.gad7.summary,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 6),
              const SectionLabel('Worksheet dibagikan (dengan skor)'),
              if (_worksheets.isEmpty)
                const EmptyState(
                  icon: Icons.assignment_outlined,
                  title: 'Belum ada worksheet dibagikan',
                  subtitle:
                      'DASS-21, WHO-5, dan worksheet terapi yang dibagikan pasien muncul di sini.',
                )
              else
                for (final w in _worksheets.take(5)) ...[
                  // TherapySubmissionView sudah membungkus dirinya dengan
                  // CollapsibleCard (SoftCard), jadi jangan dibungkus SoftCard
                  // lagi agar kartunya tidak dobel.
                  TherapySubmissionView(
                    key: ValueKey('worksheet-${w.id}'),
                    moduleId: w.moduleId,
                    title: w.title,
                    answers: w.answers,
                    summary: w.summary,
                    sharedAt: w.sharedAt,
                  ),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 6),
              // F-16: hasil DASS-21 / WHO-5 & tren (bila tersedia).
              const SectionLabel('Hasil DASS-21 / WHO-5 & tren'),
              Builder(builder: (context) {
                final dass = _worksheets
                    .where((w) => w.moduleId == 'dass21')
                    .toList(growable: false);
                final who5 = _worksheets
                    .where((w) => w.moduleId == 'who5')
                    .toList(growable: false);
                if (dass.isEmpty && who5.isEmpty) {
                  return const EmptyState(
                    icon: Icons.trending_up_rounded,
                    title: 'Belum ada hasil DASS-21 / WHO-5',
                    subtitle:
                        'Skor dan tren muncul setelah pasien membagikan assessment.',
                  );
                }
                return Column(
                  children: [
                    if (dass.isNotEmpty)
                      _AssessmentTrendCard(
                        title: 'DASS-21',
                        moduleId: 'dass21',
                        submissions: dass,
                      ),
                    if (dass.isNotEmpty) const SizedBox(height: 8),
                    if (who5.isNotEmpty)
                      _AssessmentTrendCard(
                        title: 'WHO-5',
                        moduleId: 'who5',
                        submissions: who5,
                      ),
                  ],
                );
              }),
              const SizedBox(height: 6),
              const SectionLabel('Goals & habits'),
              if (_goals.isEmpty)
                const EmptyState(
                  icon: Icons.flag_outlined,
                  title: 'Belum ada goals / tidak dibagikan',
                  subtitle: 'Goals pasien muncul bila dibagikan.',
                )
              else
                for (final g in _goals.take(5)) ...[
                  SoftCard(
                    child: Row(
                      children: [
                        const Icon(Icons.flag_rounded,
                            color: MalvaColors.amber),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${g.title} (${g.doneThisWeek}/${g.targetPerWeek}/mgg)',
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 12.5),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 6),
              const SectionLabel('Mood & diary (read-only)'),
              if (_moods.isEmpty && _diaries.isEmpty)
                const EmptyState(
                  icon: Icons.menu_book_outlined,
                  title: 'Belum ada data / tidak dibagikan',
                  subtitle:
                      'Mood & diary hanya dibaca — bahas saat sesi, tanpa balasan di luar sesi.',
                )
              else ...[
                for (final m in _moods.take(3)) ...[
                  SoftCard(
                    child: Text(
                      '${m.mood} • tidur ${m.sleepHours.toStringAsFixed(1)}j • energi ${m.energy}/10${m.note.isEmpty ? '' : '\n${m.note}'}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                for (final d in _diaries.take(3)) ...[
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(d.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 12.5)),
                        Text(d.note,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
              const SizedBox(height: 6),
              const SectionLabel('Kiriman pasien (dibahas saat sesi)'),
              if (_shares.isEmpty)
                const EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'Belum ada kiriman',
                  subtitle:
                      'Ringkasan, assessment, goals & diary yang dikirim pasien muncul di sini.',
                )
              else
                for (final m in _shares.take(8)) ...[
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StatusPill(
                            label: m.kind, color: MalvaColors.orchid),
                        const SizedBox(height: 6),
                        Text(m.text,
                            style: const TextStyle(fontSize: 12.5)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 6),
              const SectionLabel('Timeline pasien'),
              if (_timeline.isEmpty)
                const EmptyState(
                  icon: Icons.timeline_outlined,
                  title: 'Belum ada timeline / tidak dibagikan',
                  subtitle:
                      'Screening, mood, diary, dan obat tersusun di sini bila dibagikan.',
                )
              else
                for (final e in _timeline.take(8)) ...[
                  SoftCard(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.timeline_rounded,
                            color: MalvaColors.seed, size: 18),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(e.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5)),
                              if (e.body.isNotEmpty)
                                Text(e.body,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              const SizedBox(height: 6),
              const SectionLabel('Health record & obat'),
              SoftCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _healthRecord?.diagnosisSummary.isNotEmpty == true
                          ? _healthRecord!.diagnosisSummary
                          : 'Belum ada diagnosis / tidak dibagikan.',
                      style:
                          const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    if (_medications.isNotEmpty) ...[
                      const Text('Obat pasien:',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 12.5)),
                      const SizedBox(height: 4),
                      for (final m in _medications.take(5))
                        Text(
                            '• ${m.name} ${m.dosage} (stok ${m.currentStock})',
                            style: const TextStyle(fontSize: 12.5)),
                      const SizedBox(height: 8),
                    ],
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () =>
                                _openHealthRecordEdit(context),
                            style: compactFilledButtonStyle,
                            icon: const Icon(Icons.edit_note_rounded,
                                size: 16),
                            label: const Text('Isi diagnosis'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () =>
                                _openPrescribeMedication(context),
                            icon: const Icon(Icons.medication_rounded,
                                size: 16),
                            label: const Text('Resepkan obat'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              const SectionLabel('Catatan sesi'),
              if (_notes.isEmpty)
                const EmptyState(
                  icon: Icons.edit_note_outlined,
                  title: 'Belum ada catatan',
                  subtitle:
                      'Catatan privat & ringkasan untuk pasien ditulis per sesi.',
                )
              else
                for (final n in _notes.take(5)) ...[
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StatusPill(
                          label: n.visibility == 'shared_with_patient'
                              ? 'Dibagikan ke pasien'
                              : 'Privat',
                          color: n.visibility == 'shared_with_patient'
                              ? MalvaColors.mint
                              : Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                        ),
                        const SizedBox(height: 6),
                        Text(n.body,
                            style: const TextStyle(fontSize: 12.5)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              FilledButton.icon(
                onPressed: () => _openNote(context),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Tulis catatan sesi'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openNote(BuildContext context) async {
    final bodyController = TextEditingController();
    var shared = false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Catatan sesi'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: bodyController,
                maxLines: 4,
                decoration: const InputDecoration(
                    labelText: 'Catatan',
                    hintText: 'Hasil observasi sesi, rencana berikutnya…'),
              ),
              CheckboxListTile(
                value: shared,
                onChanged: (v) => setState(() => shared = v == true),
                title: const Text('Bagikan ke pasien',
                    style: TextStyle(fontSize: 13)),
                contentPadding: EdgeInsets.zero,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: compactFilledButtonStyle,
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
    final body = bodyController.text.trim();
    bodyController.dispose();
    if (saved != true || body.isEmpty) return;
    final token = _token;
    if (token == null) return;
    try {
      await _api.createProfessionalNote(
        accessToken: token,
        patientId: widget.patientId,
        body: body,
        visibility: shared ? 'shared_with_patient' : 'private',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catatan tersimpan.')),
      );
      await _load();
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }

  Future<void> _openPrescribeMedication(BuildContext context) async {
    final nameController = TextEditingController();
    final dosageController = TextEditingController();
    final formController = TextEditingController(text: 'Tablet');
    final timeController = TextEditingController();
    final mealController = TextEditingController();
    final stockController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Resepkan obat'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                  controller: nameController,
                  decoration:
                      const InputDecoration(labelText: 'Nama obat *')),
              TextField(
                  controller: dosageController,
                  decoration:
                      const InputDecoration(labelText: 'Dosis (mis. 50 mg)')),
              TextField(
                  controller: formController,
                  decoration:
                      const InputDecoration(labelText: 'Bentuk')),
              TextField(
                  controller: timeController,
                  decoration: const InputDecoration(
                      labelText: 'Jam minum (mis. 08:00)')),
              TextField(
                  controller: mealController,
                  decoration: const InputDecoration(
                      labelText: 'Kaitan makan')),
              TextField(
                  controller: stockController,
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Stok awal')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: compactFilledButtonStyle,
            child: const Text('Resepkan'),
          ),
        ],
      ),
    );
    final name = nameController.text.trim();
    final dosage = dosageController.text.trim();
    final form = formController.text.trim();
    final reminder = timeController.text.trim();
    final meal = mealController.text.trim();
    final stock = int.tryParse(stockController.text.trim()) ?? 0;
    nameController.dispose();
    dosageController.dispose();
    formController.dispose();
    timeController.dispose();
    mealController.dispose();
    stockController.dispose();
    if (saved != true || name.isEmpty) return;
    final token = _token;
    if (token == null) return;
    try {
      await _api.createMedication(
        accessToken: token,
        patientId: widget.patientId,
        name: name,
        dosage: dosage,
        form: form,
        reminderTime: reminder,
        relationToMeal: meal,
        currentStock: stock,
        alertBelow: 5,
        source: 'Profesional',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Obat diresepkan ke pasien.'),
          backgroundColor: MalvaColors.mint,
        ),
      );
      await _load();
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }

  Future<void> _openHealthRecordEdit(BuildContext context) async {
    final controller = TextEditingController(
        text: _healthRecord?.diagnosisSummary ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Diagnosis pasien'),
        content: TextField(
          controller: controller,
          maxLines: 5,
          decoration: const InputDecoration(
              labelText: 'Diagnosis summary',
              hintText: 'contoh: F41.1 Generalized anxiety disorder'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: compactFilledButtonStyle,
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    final diagnosis = controller.text.trim();
    controller.dispose();
    if (saved != true) return;
    final token = _token;
    if (token == null) return;
    try {
      final updated = await _api.updateHealthRecordDiagnosis(
        accessToken: token,
        patientId: widget.patientId,
        diagnosisSummary: diagnosis,
      );
      if (!context.mounted) return;
      setState(() => _healthRecord = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Diagnosis tersimpan.'),
          backgroundColor: MalvaColors.mint,
        ),
      );
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }
}

// ============================================================
// F-16 — kartu hasil & tren assessment (DASS-21 / WHO-5).
// ============================================================

class _AssessmentTrendCard extends StatelessWidget {
  const _AssessmentTrendCard({
    required this.title,
    required this.moduleId,
    required this.submissions,
  });

  final String title;
  final String moduleId;
  final List<BackendTherapySubmission> submissions;

  /// Total skor pembanding tren: DASS-21 (turunan lebih rendah = membaik),
  /// WHO-5 (raw lebih tinggi = membaik).
  static int _trendValue(String moduleId, Map<String, dynamic> answers) {
    if (moduleId == 'who5') return scoreWho5(answers).raw;
    final d = scoreDass21(answers);
    return d.depression + d.anxiety + d.stress;
  }

  static String _shortDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return iso;
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final ordered = [...submissions]
      ..sort((a, b) => (b.sharedAt ?? b.createdAt ?? '')
          .compareTo(a.sharedAt ?? a.createdAt ?? ''));
    final latest = ordered.first;
    final previous = ordered.length > 1 ? ordered[1] : null;

    final latestSummary = assessmentSummary(moduleId, latest.answers);
    final dateLabel = _shortDate(latest.sharedAt ?? latest.createdAt);
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
              ),
              if (dateLabel.isNotEmpty)
                StatusPill(label: dateLabel, color: MalvaColors.seed),
            ],
          ),
          const SizedBox(height: 6),
          Text(latestSummary, style: const TextStyle(fontSize: 12.5)),
          if (previous != null) ...[
            const SizedBox(height: 8),
            _TrendLine(
              moduleId: moduleId,
              latestValue: _trendValue(moduleId, latest.answers),
              previousValue: _trendValue(moduleId, previous.answers),
            ),
          ] else ...[
            const SizedBox(height: 6),
            Text(
              'Belum ada data sebelumnya untuk menghitung tren.',
              style: TextStyle(fontSize: 11.5, color: onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _TrendLine extends StatelessWidget {
  const _TrendLine({
    required this.moduleId,
    required this.latestValue,
    required this.previousValue,
  });

  final String moduleId;
  final int latestValue;
  final int previousValue;

  @override
  Widget build(BuildContext context) {
    final delta = latestValue - previousValue;
    // DASS-21: skor turun = membaik. WHO-5: skor naik = membaik.
    final bool improved = moduleId == 'who5' ? delta > 0 : delta < 0;

    final Color color;
    final String label;
    if (delta == 0) {
      color = Theme.of(context).colorScheme.onSurfaceVariant;
      label = 'Stabil dibanding assessment sebelumnya';
    } else if (improved) {
      color = MalvaColors.mint;
      label = 'Membaik dibanding assessment sebelumnya';
    } else {
      color = MalvaColors.danger;
      label = 'Perlu perhatian dibanding assessment sebelumnya';
    }

    final IconData icon = delta > 0
        ? Icons.trending_up_rounded
        : delta < 0
            ? Icons.trending_down_rounded
            : Icons.trending_flat_rounded;
    final String deltaLabel = delta > 0 ? '+$delta' : '$delta';

    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '$label ($deltaLabel)',
            style: TextStyle(
                fontSize: 12, color: color, fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}

/// Tanggal screening ringkas (dd/mm/yyyy) untuk header kartu yang dilipat.
String _screeningDate(DateTime? dt) {
  if (dt == null) return 'Tanggal tidak diketahui';
  final local = dt.toLocal();
  return '${local.day}/${local.month}/${local.year}';
}

/// Baris detail skor satu instrumen (PHQ-9 / GAD-7) di dalam kartu
/// screening yang dibuka.
class _ScreeningInstrumentDetail extends StatelessWidget {
  const _ScreeningInstrumentDetail({
    required this.name,
    required this.score,
    required this.maxScore,
    required this.level,
    required this.summary,
  });

  final String name;
  final int score;
  final int maxScore;
  final String level;
  final String summary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$name: $score/$maxScore',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            if (level.isNotEmpty)
              StatusPill(label: level, color: MalvaColors.seed),
          ],
        ),
        const SizedBox(height: 6),
        ProgressStrip(
          value: maxScore <= 0 ? 0 : score / maxScore,
          color: MalvaColors.seed,
        ),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(summary, style: const TextStyle(fontSize: 12.5)),
        ],
      ],
    );
  }
}