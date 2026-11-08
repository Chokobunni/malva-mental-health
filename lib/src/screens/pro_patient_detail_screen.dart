import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../professional_role.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';
import '../widgets/therapy_library.dart';
import 'chat_screen.dart';
import 'assessment_history_screen.dart';

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
        bordered: true,
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
            _ScreeningInstrumentDetail(
              name: 'PHQ-9',
              score: sc.phq9.score,
              maxScore: sc.phq9.maxScore,
              level: sc.phq9.level,
              summary: sc.phq9.summary,
              certaintyFactor: sc.phq9.certaintyFactor,
              ruleTrace: sc.phq9.ruleTrace,
            ),
            const SizedBox(height: 12),
            _ScreeningInstrumentDetail(
              name: 'GAD-7',
              score: sc.gad7.score,
              maxScore: sc.gad7.maxScore,
              level: sc.gad7.level,
              summary: sc.gad7.summary,
              certaintyFactor: sc.gad7.certaintyFactor,
              ruleTrace: sc.gad7.ruleTrace,
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
  List<BackendDiaryEntry> _diaries = const [];
  List<BackendChatMessage> _shares = const [];
  List<BackendProfessionalNote> _notes = const [];
  List<BackendMedication> _medications = const [];
  List<BackendTimelineEvent> _timeline = const [];
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
                accessToken: token, patientId: widget.patientId, limit: 10),
            'Mood'),
        safely(
            () => _api.listDiaryEntries(
                accessToken: token, patientId: widget.patientId, limit: 10),
            'Diary'),
        safely(
            () => _api.listProfessionalNotes(
                accessToken: token, patientId: widget.patientId, limit: 10),
            'Catatan sesi'),
        safely(
            () => _api.listMedications(
                accessToken: token, patientId: widget.patientId, limit: 30),
            'Obat'),
        safely(
            () => _api.listTimeline(
                accessToken: token, patientId: widget.patientId, limit: 20),
            'Timeline'),
      ]);
      final myId =
          widget.session?.backendUserId ?? widget.session?.identifier ?? '';
      final messages = myId.isEmpty
          ? null
          : await safely(
              () => _api.listMessages(
                    accessToken: token,
                    patientId: widget.patientId,
                    professionalId: myId,
                  ),
              'Kiriman pasien');
      final shares =
          messages?.where((m) => m.kind != 'text').toList(growable: false) ??
              const <BackendChatMessage>[];
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
        _diaries = (results[6] as List<BackendDiaryEntry>?) ?? const [];
        _notes = (results[7] as List<BackendProfessionalNote>?) ?? const [];
        _medications = (results[8] as List<BackendMedication>?) ?? const [];
        _timeline = (results[9] as List<BackendTimelineEvent>?) ?? const [];
        _shares = shares;
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
                  bordered: true,
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
                            bordered: true,
                            padding: const EdgeInsets.all(12),
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
                      if (_sessions.isNotEmpty)
                        for (final s in _sessions.take(5)) ...[
                          SoftCard(
                            bordered: true,
                            padding: const EdgeInsets.all(12),
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
                                        fontWeight: FontWeight.w700,
                                        fontSize: 12.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                    ],
                  ),
                ),
              const SizedBox(height: 14),
              const SectionLabel('Health Record & Obat'),
              SoftCard(
                bordered: true,
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
                        Text('• ${m.name} ${m.dosage} (stok ${m.currentStock})',
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
                            icon: const Icon(Icons.edit_note_rounded, size: 16),
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
                  bordered: true,
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
              if (_isUnavailable('Diary')) _sectionStatus('Diary'),
              if (_moods.isEmpty &&
                  _diaries.isEmpty &&
                  !_isUnavailable('Mood') &&
                  !_isUnavailable('Diary'))
                const EmptyState(
                  icon: Icons.menu_book_outlined,
                  title: 'Belum ada data / tidak dibagikan',
                  subtitle:
                      'Mood & diary hanya dibaca — bahas saat sesi, tanpa balasan di luar sesi.',
                )
              else if (_moods.isNotEmpty || _diaries.isNotEmpty)
                CollapsibleCard(
                  key: const ValueKey('mood-diary-section'),
                  bordered: true,
                  semanticLabel: 'Mood & diary (read-only)',
                  header: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Mood & diary (read-only)',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      StatusPill(
                        label: '${_moods.length + _diaries.length}',
                        color: MalvaColors.orchid,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final m in _moods.take(3)) ...[
                        Text(
                          '${m.mood} • tidur ${m.sleepHours.toStringAsFixed(1)}j • energi ${m.energy}/10${m.note.isEmpty ? '' : '\n${m.note}'}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                        const SizedBox(height: 8),
                      ],
                      for (final d in _diaries.take(3)) ...[
                        Column(
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
                        const SizedBox(height: 8),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              if (_isUnavailable('Kiriman pasien'))
                _sectionStatus('Kiriman pasien')
              else if (_shares.isEmpty)
                const EmptyState(
                  icon: Icons.inbox_outlined,
                  title: 'Belum ada kiriman',
                  subtitle:
                      'Ringkasan, assessment, goals & diary yang dikirim pasien muncul di sini.',
                )
              else
                CollapsibleCard(
                  key: const ValueKey('shares-section'),
                  bordered: true,
                  semanticLabel: 'Kiriman pasien',
                  header: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Kiriman pasien (dibahas saat sesi)',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      StatusPill(
                        label: '${_shares.length}',
                        color: MalvaColors.orchid,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final m in _shares.take(8)) ...[
                        StatusPill(label: m.kind, color: MalvaColors.orchid),
                        const SizedBox(height: 6),
                        Text(m.text, style: const TextStyle(fontSize: 12.5)),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
              const SizedBox(height: 10),
              if (_isUnavailable('Timeline'))
                _sectionStatus('Timeline')
              else if (_timeline.isEmpty)
                const EmptyState(
                  icon: Icons.timeline_outlined,
                  title: 'Belum ada timeline / tidak dibagikan',
                  subtitle:
                      'Screening, mood, diary, dan obat tersusun di sini bila dibagikan.',
                )
              else
                CollapsibleCard(
                  key: const ValueKey('timeline-section'),
                  bordered: true,
                  semanticLabel: 'Timeline pasien',
                  header: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Timeline pasien',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      StatusPill(
                        label: '${_timeline.length}',
                        color: MalvaColors.seed,
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final e in _timeline.take(8)) ...[
                        Row(
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
                                        style: const TextStyle(fontSize: 12)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
                ),
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
              const SectionLabel('Catatan sesi'),
              if (_isUnavailable('Catatan sesi'))
                _sectionStatus('Catatan sesi')
              else if (_notes.isEmpty)
                const EmptyState(
                  icon: Icons.edit_note_outlined,
                  title: 'Belum ada catatan',
                  subtitle:
                      'Catatan privat & ringkasan untuk pasien ditulis per sesi.',
                )
              else
                for (final n in _notes.take(5)) ...[
                  SoftCard(
                    bordered: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        StatusPill(
                          label: n.visibility == 'shared_with_patient'
                              ? 'Dibagikan ke pasien'
                              : 'Privat',
                          color: n.visibility == 'shared_with_patient'
                              ? MalvaColors.mint
                              : Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 6),
                        Text(n.body, style: const TextStyle(fontSize: 12.5)),
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
              const SizedBox(height: 14),
              const SectionLabel('Worksheet terapi dibagikan'),
              if (_isUnavailable('Assessment & worksheet'))
                _sectionStatus('Assessment & worksheet')
              else if (!_worksheets
                  .any((w) => w.moduleId != 'who5' && w.moduleId != 'dass21'))
                const EmptyState(
                  icon: Icons.assignment_outlined,
                  title: 'Belum ada worksheet terapi dibagikan',
                  subtitle:
                      'Latihan terapi yang dibagikan pasien muncul di sini.',
                )
              else
                for (final w in _worksheets.where(
                    (w) => w.moduleId != 'who5' && w.moduleId != 'dass21')) ...[
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
              const SectionLabel('Akses data', icon: Icons.lock_open_rounded),
              if (_restricted != null)
                SoftCard(
                  bordered: true,
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
                  bordered: true,
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
                  decoration: const InputDecoration(labelText: 'Nama obat *')),
              TextField(
                  controller: dosageController,
                  decoration:
                      const InputDecoration(labelText: 'Dosis (mis. 50 mg)')),
              TextField(
                  controller: formController,
                  decoration: const InputDecoration(labelText: 'Bentuk')),
              TextField(
                  controller: timeController,
                  decoration: const InputDecoration(
                      labelText: 'Jam minum (mis. 08:00)')),
              TextField(
                  controller: mealController,
                  decoration: const InputDecoration(labelText: 'Kaitan makan')),
              TextField(
                  controller: stockController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Stok awal')),
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
    required this.certaintyFactor,
    required this.ruleTrace,
  });

  final String name;
  final int score;
  final int maxScore;
  final String level;
  final String summary;
  final double certaintyFactor;
  final String ruleTrace;

  @override
  Widget build(BuildContext context) {
    if (maxScore <= 0 || score < 0 || score > maxScore) {
      return Text('$name: hasil belum tersedia.');
    }
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
        const SizedBox(height: 8),
        if (ruleTrace.isNotEmpty &&
            certaintyFactor.isFinite &&
            certaintyFactor >= 0 &&
            certaintyFactor <= 1) ...[
          Text('Dukungan aturan (CF): ${(certaintyFactor * 100).round()}%',
              style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          const Text(
            'CF adalah dukungan aturan internal, bukan probabilitas diagnosis '
            'atau tingkat keparahan. Skor dan kategori instrumen tetap terpisah.',
            style: TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(ruleTrace, style: const TextStyle(fontSize: 12)),
        ] else
          const Text('CF dan jejak aturan belum tersedia.',
              style: TextStyle(fontSize: 12)),
        if (summary.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(summary, style: const TextStyle(fontSize: 12.5)),
        ],
      ],
    );
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
