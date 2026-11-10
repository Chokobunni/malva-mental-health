import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../assessment_engine.dart';
import '../professional_role.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../services/mood_insights.dart';
import '../widgets/mood_insights.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';
import '../widgets/therapy_library.dart';
import '../widgets/shared_record_detail.dart';
import 'chat_screen.dart';
import 'portal/prescription_wizard_screen.dart';
import 'assessment_history_screen.dart';

// ============================================================
// PRO PATIENT DETAIL — semua yang dibutuhkan profesional untuk
// satu pasien, dari semua scope sisi pasien:
//   Paket & sesi • Screening & review • Worksheet (DASS/WHO-5 +
//   skor) • Goals & habits • Mood (read-only, tanpa balas)
//   Health record & obat.
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

class _ProPatientDetailScreenState
    extends ConsumerState<ProPatientDetailScreen> {
  Set<String> _assessmentInstruments = {'who5', 'gad7', 'phq9', 'dass21'};
  bool _oldestAssessmentFirst = false;
  int _visibleAssessments = 5;

  List<Widget> _clinicalAssessmentRecords() {
    final entries = filterAssessmentHistory([
      for (final screening in _screenings)
        assessmentEntryFromScreening(screening),
      for (final worksheet in _worksheets)
        if (isCompleteAssessmentAnswers(worksheet.moduleId, worksheet.answers))
          assessmentEntryFromSubmission(worksheet),
    ],
        instruments: _assessmentInstruments,
        oldestFirst: _oldestAssessmentFirst);
    return [
      if (entries.isEmpty &&
          !_isUnavailable('Screening PHQ-9 / GAD-7') &&
          !_isUnavailable('Assessment & worksheet'))
        const EmptyState(
            icon: Icons.fact_check_outlined,
            title: 'Belum ada screening',
            subtitle: 'Tidak ada hasil untuk filter ini.'),
      for (final entry in entries.take(_visibleAssessments)) ...[
        if (entry.screening != null)
          _clinicalScreening(entry.screening!)
        else
          Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(formatAssessmentDate(entry.date),
                style: const TextStyle(fontSize: 12)),
            TherapySubmissionView(
                key: ValueKey('worksheet-' + entry.sourceId),
                moduleId: entry.moduleId,
                title: entry.title,
                answers: entry.answers,
                summary: entry.subtitle),
          ]),
        const SizedBox(height: 8),
      ],
      if (entries.length > _visibleAssessments)
        TextButton(
            onPressed: () => setState(() => _visibleAssessments += 5),
            child: const Text('Tampilkan lebih banyak')),
    ];
  }

  Widget _clinicalScreening(BackendScreeningSession sc) => CollapsibleCard(
        key: ValueKey('screening-${sc.id}'),
        color: Colors.white,
        semanticLabel: 'Detail screening ${_screeningDate(sc.createdAt)}',
        header: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_instrumentHeader('PHQ-9', sc.phq9)} • ${_instrumentHeader('GAD-7', sc.gad7)}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
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
                  color: sc.crisisFlag ? MalvaColors.danger : null,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SharedRecordDetail.screening(screening: sc),
            const SizedBox(height: 12),
            _ScreeningInstrumentDetail(
              name: 'PHQ-9',
              score: sc.phq9.score,
              maxScore: sc.phq9.maxScore,
              level: sc.phq9.level,
              summary: sc.phq9.summary,
              answers: sc.phq9.answers,
              crisisFlag: sc.phq9.crisisFlag,
            ),
            const SizedBox(height: 12),
            _ScreeningInstrumentDetail(
              name: 'GAD-7',
              score: sc.gad7.score,
              maxScore: sc.gad7.maxScore,
              level: sc.gad7.level,
              summary: sc.gad7.summary,
              answers: sc.gad7.answers,
              crisisFlag: sc.gad7.crisisFlag,
            ),
          ],
        ),
      );

  List<BackendCarePackage> _packages = const [];
  List<BackendCareSession> _sessions = const [];
  List<BackendScreeningSession> _screenings = const [];
  List<BackendTherapySubmission> _worksheets = const [];
  List<BackendGoal> _goals = const [];
  List<BackendMoodCheckin> _moods = const [];
  List<BackendMedication> _medications = const [];
  BackendHealthRecord? _healthRecord;
  String? _restricted;
  bool _isLoading = true;
  String? _error;

  /// True bila profesional yang login adalah Psikiater (Sp.KJ) — satu-satunya
  /// peran yang boleh meresepkan obat. Default false (tombol disembunyikan)
  /// sampai kredensial termuat.
  bool _isPsychiatrist = false;

  /// Bagian opsional yang gagal dimuat. Data klinis yang gagal dimuat tidak
  /// boleh tampil sama seperti "pasien memang tidak punya data", jadi bagian
  /// yang gagal disebutkan namanya di layar.
  List<String> _failedSections = const [];
  List<String> _unsharedSections = const [];

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
      final failed = <String>[];
      final unshared = <String>[];
      Future<T?> safely<T>(
          Future<T> Function() load, String sectionLabel) async {
        try {
          return await load();
        } on MalvaApiException catch (e) {
          if (e.statusCode == 403) {
            unshared.add(sectionLabel);
            // 403 = pasien tidak membagikan data ini; sudah dijelaskan lewat
            // _restricted, bukan kegagalan muat.
            if (mounted) {
              setState(() => _restricted = (_restricted == null)
                  ? e.message
                  : '$_restricted • ${e.message}');
            }
          } else {
            failed.add(sectionLabel);
          }
          return null;
        } on Object {
          failed.add(sectionLabel);
          return null;
        }
      }

      final results = await Future.wait([
        _api.listCarePackages(accessToken: token, patientId: widget.patientId),
        _api.listCareSessions(
            accessToken: token, scope: 'all', patientId: widget.patientId),
        safely(
            () => _api.listScreenings(
                accessToken: token, patientId: widget.patientId, limit: 10),
            'Screening PHQ-9 / GAD-7'),
        safely(
            () => _api.listTherapySubmissions(
                accessToken: token, patientId: widget.patientId),
            'Assessment & worksheet'),
        safely(
            () =>
                _api.listGoals(accessToken: token, patientId: widget.patientId),
            'Goals'),
        safely(
            () => _api.listMoodCheckins(
                accessToken: token, patientId: widget.patientId, limit: 0),
            'Mood'),
        safely(
            () => _api.listMedications(
                accessToken: token, patientId: widget.patientId, limit: 30),
            'Obat'),
      ]);
      final record = await safely(
          () => _api.getHealthRecord(
                accessToken: token,
                patientId: widget.patientId,
              ),
          'Health Record');
      if (!mounted) return;
      // Muat kredensial sendiri untuk menentukan apakah Psikiater (hanya
      // Psikiater yang boleh meresepkan). Kegagalan memuat tidak menjatuhkan
      // layar — perlakukan sebagai bukan psikiater (aman).
      BackendProfessionalCredential? cred;
      try {
        cred = await _api.getMyCredentials(accessToken: token);
      } on Object {
        cred = null;
      }
      if (!mounted) return;
      setState(() {
        _packages = results[0] as List<BackendCarePackage>;
        _sessions = results[1] as List<BackendCareSession>;
        _screenings =
            (results[2] as List<BackendScreeningSession>?) ?? const [];
        final seenWorksheets = <String>{};
        _worksheets = ((results[3] as List<BackendTherapySubmission>?) ??
                const [])
            .where((item) =>
                (item.moduleId != 'who5' && item.moduleId != 'dass21') ||
                isCompleteAssessmentAnswers(item.moduleId, item.answers))
            .where((item) =>
                item.id.trim().isEmpty || seenWorksheets.add(item.id.trim()))
            .toList(growable: false);
        _goals = (results[4] as List<BackendGoal>?) ?? const [];
        _moods = (results[5] as List<BackendMoodCheckin>?) ?? const [];
        _medications = (results[6] as List<BackendMedication>?) ?? const [];
        _healthRecord = record;
        _isPsychiatrist =
            cred != null && isPsychiatristSpecialization(cred.specialization);
        _failedSections = List.unmodifiable(failed);
        _unsharedSections = List.unmodifiable(unshared);
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

  bool _isUnavailable(String section) =>
      _failedSections.contains(section) || _unsharedSections.contains(section);

  Widget _sectionStatus(String section) {
    final unshared = _unsharedSections.contains(section);
    return SoftCard(
      bordered: true,
      child: Row(
        children: [
          Icon(unshared ? Icons.lock_outline_rounded : Icons.cloud_off_rounded),
          const SizedBox(width: 10),
          Expanded(
            child: Text(unshared
                ? '$section tidak dibagikan pasien.'
                : '$section belum dapat dimuat.'),
          ),
          if (!unshared)
            TextButton(onPressed: _load, child: const Text('Coba lagi')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
        data: Theme.of(context).copyWith(
            cardTheme: Theme.of(context).cardTheme.copyWith(elevation: .35)),
        child: Scaffold(
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
                  // ============================================================
                  // GRUP 1 — Ringkasan klinis
                  // ============================================================
                  const SectionLabel('Ringkasan klinis',
                      icon: Icons.assessment_rounded),
                  if (_packages.isEmpty && _sessions.isEmpty)
                    const EmptyState(
                      icon: Icons.card_membership_outlined,
                      title: 'Belum ada paket',
                      subtitle: 'Pasien belum membeli paket denganmu.',
                    )
                  else
                    CollapsibleCard(
                      key: const ValueKey('packages-section'),
                      color: Colors.white,
                      semanticLabel: 'Paket & sesi',
                      header: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Paket & sesi',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          if (_packages.isNotEmpty)
                            StatusPill(
                              label: '${_packages.length} paket',
                              color: MalvaColors.seed,
                            ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_packages.isNotEmpty)
                            for (final p in _packages) ...[
                              SoftCard(
                                padding: const EdgeInsets.all(12),
                                color: const Color(0xFFF7F8FA),
                                accent: MalvaColors.orchid,
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
                                          label: p.status.toUpperCase(),
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
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 12),
                              for (final s in _sessions
                                  .where((s) => s.packageId == p.id)) ...[
                                _ClinicalSessionCard(session: s),
                                const SizedBox(height: 12),
                              ],
                            ],
                          if (_sessions.any((s) =>
                              !_packages.any((p) => p.id == s.packageId)))
                            for (final s in _sessions.where((s) => !_packages
                                .any((p) => p.id == s.packageId))) ...[
                              _ClinicalSessionCard(session: s),
                              const SizedBox(height: 8),
                            ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  const SectionLabel('Health Record & Obat'),
                  SoftCard(
                    color: Colors.white,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_isUnavailable('Health Record'))
                          _sectionStatus('Health Record')
                        else
                          Text(
                            _healthRecord?.diagnosisSummary.isNotEmpty == true
                                ? _healthRecord!.diagnosisSummary
                                : 'Belum ada diagnosis / tidak dibagikan.',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        const SizedBox(height: 8),
                        if (_isUnavailable('Obat')) _sectionStatus('Obat'),
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
                                onPressed: _isUnavailable('Health Record')
                                    ? null
                                    : () => _openHealthRecordEdit(context),
                                style: compactFilledButtonStyle,
                                icon: const Icon(Icons.edit_note_rounded,
                                    size: 16),
                                label: const Text('Isi diagnosis'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              // Resep hanya untuk Psikiater (Sp.KJ). Psikolog
                              // melihat keterangan, bukan tombol yang pasti 403.
                              child: _isPsychiatrist
                                  ? OutlinedButton.icon(
                                      onPressed: () =>
                                          _openPrescribeMedication(context),
                                      icon: const Icon(Icons.medication_rounded,
                                          size: 16),
                                      label: const Text('Resepkan obat'),
                                    )
                                  : const Text(
                                      'Hanya Psikiater (Sp.KJ) yang dapat '
                                      'meresepkan obat.',
                                      style: TextStyle(fontSize: 11.5),
                                    ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  // ============================================================
                  // GRUP 2 — Pemantauan harian (semua read-only → dilipat)
                  // ============================================================
                  const SizedBox(height: 22),
                  const SectionLabel('Pemantauan harian',
                      icon: Icons.monitor_heart_rounded),
                  if (_isUnavailable('Goals'))
                    _sectionStatus('Goals')
                  else if (_goals.isEmpty)
                    const EmptyState(
                      icon: Icons.flag_outlined,
                      title: 'Belum ada goals / tidak dibagikan',
                      subtitle: 'Goals pasien muncul bila dibagikan.',
                    )
                  else
                    CollapsibleCard(
                      key: const ValueKey('goals-section'),
                      color: Colors.white,
                      semanticLabel: 'Goals & habits',
                      header: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Goals & habits',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          StatusPill(
                            label: '${_goals.length}',
                            color: MalvaColors.amber,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          for (final g in _goals.take(5)) ...[
                            Row(
                              children: [
                                const Icon(Icons.flag_rounded,
                                    color: MalvaColors.amber),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    '${g.title} (${g.doneThisWeek}/${g.targetPerWeek}/mgg)',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (_isUnavailable('Mood')) _sectionStatus('Mood'),
                  if (_moods.isEmpty && !_isUnavailable('Mood'))
                    const EmptyState(
                      icon: Icons.menu_book_outlined,
                      title: 'Belum ada data / tidak dibagikan',
                      subtitle:
                          'Mood hanya dibaca — bahas saat sesi, tanpa balasan di luar sesi.',
                    )
                  else if (_moods.isNotEmpty)
                    CollapsibleCard(
                      key: const ValueKey('mood-section'),
                      color: Colors.white,
                      semanticLabel: 'Mood Entries',
                      header: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Mood Entries',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          StatusPill(
                            label: '${_moods.length}',
                            color: MalvaColors.orchid,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (_moods.isNotEmpty)
                            MoodInsights(
                                entries: _moods
                                    .where((m) => m.occurredAt != null)
                                    .map(moodEntryFromBackend)
                                    .toList()),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  const SizedBox(height: 22),
                  const SectionLabel('Screening', center: true),
                  AssessmentHistoryFilters(
                    selected: _assessmentInstruments,
                    oldestFirst: _oldestAssessmentFirst,
                    onChanged: (selected, oldest) => setState(() {
                      _assessmentInstruments = selected;
                      _oldestAssessmentFirst = oldest;
                      _visibleAssessments = 5;
                    }),
                  ),
                  if (_isUnavailable('Assessment & worksheet'))
                    _sectionStatus('Assessment & worksheet'),
                  if (_isUnavailable('Screening PHQ-9 / GAD-7'))
                    _sectionStatus('Screening PHQ-9 / GAD-7'),
                  ..._clinicalAssessmentRecords(),
                  const SectionLabel('Worksheet terapi dibagikan'),
                  if (_isUnavailable('Assessment & worksheet'))
                    _sectionStatus('Assessment & worksheet')
                  else if (!_worksheets.any(
                      (w) => w.moduleId != 'who5' && w.moduleId != 'dass21'))
                    const EmptyState(
                      icon: Icons.assignment_outlined,
                      title: 'Belum ada worksheet terapi dibagikan',
                      subtitle:
                          'Latihan terapi yang dibagikan pasien muncul di sini.',
                    )
                  else
                    for (final w in _worksheets.where((w) =>
                        w.moduleId != 'who5' && w.moduleId != 'dass21')) ...[
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
                  // ============================================================
                  // GRUP 4 — Akses data
                  // ============================================================
                  const SizedBox(height: 22),
                  const SectionLabel('Akses data',
                      icon: Icons.lock_open_rounded),
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
                    )
                  else
                    SoftCard(
                      color: MalvaColors.mint.withValues(alpha: 0.08),
                      child: const Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.verified_user_rounded,
                              color: MalvaColors.mint),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                                'Semua data yang dibagikan pasien dapat diakses.'),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
        ));
  }

  Future<void> _openPrescribeMedication(BuildContext context) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => EPrescriptionFormScreen(
        session: widget.session,
        apiClient: _api,
        preselectedPatientId: widget.patientId,
        preselectedPatientName: widget.patientName,
      ),
    ));
    if (mounted) await _load();
  }

  Future<void> _openHealthRecordEdit(BuildContext context) async {
    final controller =
        TextEditingController(text: _healthRecord?.diagnosisSummary ?? '');
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

/// Tanggal screening ringkas (dd/mm/yyyy) untuk header kartu yang dilipat.
String _screeningDate(DateTime? dt) {
  if (dt == null) return 'Tanggal tidak diketahui';
  final local = dt;
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
    required this.answers,
    required this.crisisFlag,
  });

  final String name;
  final int score;
  final int maxScore;
  final String level;
  final String summary;
  final Map<String, int> answers;
  final bool crisisFlag;

  @override
  Widget build(BuildContext context) {
    if (maxScore <= 0 || score < 0 || score > maxScore) {
      return Text('$name: hasil belum tersedia.');
    }
    final questions = name == 'PHQ-9'
        ? AssessmentEngine.phq9Questions
        : AssessmentEngine.gad7Questions;
    final complete = questions.every((q) => answers.containsKey(q.id));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: const TextStyle(fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        const Text('Indikator klinis',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: [
          StatusPill(
              label: '${name == 'PHQ-9' ? 'Depresi' : 'Kecemasan'} • $level',
              color: MalvaColors.seed),
          if (crisisFlag || (answers['phq_self_harm'] ?? 0) > 0)
            const StatusPill(
                label: 'Risiko menyakiti diri',
                color: MalvaColors.danger,
                icon: Icons.warning_rounded),
        ]),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 12),
          SoftCard(
              color: const Color(0xFFFBF7FD),
              accent: MalvaColors.orchid,
              child: Text(summary)),
        ],
        const SizedBox(height: 12),
        CollapsibleCard(
            color: Colors.white,
            semanticLabel: 'Detail jawaban $name',
            header: const Row(children: [
              Icon(Icons.checklist_rounded, color: MalvaColors.seed),
              SizedBox(width: 8),
              Expanded(child: Text('Lihat detail jawaban'))
            ]),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!complete)
                    const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Text('Sebagian jawaban belum tersedia.')),
                  for (final q in questions)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: SoftCard(
                            color: const Color(0xFFF7F8FA),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(q.label,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800)),
                                  const SizedBox(height: 4),
                                  Text(answers[q.id] == null
                                      ? 'Jawaban belum tersedia'
                                      : '${answers[q.id]} • ${AssessmentEngine.responseDescriptions[answers[q.id]!]}'),
                                ]))),
                ])),
      ],
    );
  }
}

class _ClinicalSessionCard extends StatelessWidget {
  const _ClinicalSessionCard({required this.session});
  final BackendCareSession session;

  @override
  Widget build(BuildContext context) {
    final missed = session.status == 'no_show';
    final at = session.scheduledDateTime;
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des'
    ];
    final statusColor = session.isScheduled
        ? const Color(0xFF2B67C6)
        : session.status == 'completed'
            ? MalvaColors.mint
            : MalvaColors.danger;
    return Opacity(
        opacity: missed ? .55 : 1,
        child: Container(
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFF0F0F3))),
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              CircleAvatar(
                  backgroundColor: MalvaColors.seed.withValues(alpha: .08),
                  child: Icon(
                      missed
                          ? Icons.videocam_off_rounded
                          : session.isVideo
                              ? Icons.videocam_rounded
                              : Icons.chat_bubble_rounded,
                      color: missed ? Colors.grey : MalvaColors.seed)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                        at == null
                            ? 'Tanggal tidak tercatat'
                            : '${at.day} ${months[at.month - 1]} ${at.year}',
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            decoration:
                                missed ? TextDecoration.lineThrough : null)),
                    if (at != null)
                      Text(
                          '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')} WIB'),
                  ])),
              const SizedBox(width: 8),
              Flexible(
                  child: StatusPill(
                      label: session.status.toUpperCase().replaceAll('_', ' '),
                      color: statusColor)),
            ])));
  }
}

String _instrumentHeader(String name, BackendAssessmentSummary result) {
  if (result.maxScore <= 0 ||
      result.score < 0 ||
      result.score > result.maxScore) {
    return '$name belum tersedia';
  }
  return '$name ${result.score}';
}
