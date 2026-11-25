import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/diagnosis/diagnosis_search_field.dart';
import '../../features/diagnosis/diagnosis_summary.dart';
import '../../features/diagnosis/icd10_service.dart';
import '../models.dart';
import '../assessment_engine.dart';
import '../professional_role.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../services/mood_insights.dart';
import '../services/server_clock.dart';
import '../time/wib.dart';
import '../widgets/mood_insights.dart';
import '../widgets/clinical_allergy_section.dart';
import '../widgets/clinical_profile_cards.dart';
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

class _ProPatientDetailScreenState extends ConsumerState<ProPatientDetailScreen>
    with WidgetsBindingObserver {
  String _archiveQuery = '';
  String _archiveFilter = 'Semua';
  int _visibleAssessments = 4;
  List<BackendHealthRecordAllergy> _allergies = const [];
  int? _adherence;

  List<Widget> _clinicalAssessmentRecords() {
    final entries = [
      for (final screening in _screenings)
        assessmentEntryFromScreening(screening),
      for (final worksheet in _worksheets)
        assessmentEntryFromSubmission(worksheet),
    ]..sort((a, b) => (b.date?.millisecondsSinceEpoch ?? 0)
        .compareTo(a.date?.millisecondsSinceEpoch ?? 0));
    final query = _archiveQuery.trim().toLowerCase();
    final filtered = entries
        .where((entry) =>
            (_archiveFilter == 'Semua' ||
                entry.isAssessmentResult == (_archiveFilter == 'Asesmen')) &&
            '${entry.title} ${entry.subtitle}'.toLowerCase().contains(query))
        .toList();
    return [
      const SectionLabel('Arsip Klinis & Skrining'),
      const Text('Hasil asesmen psikometri & lembar kerja terapi pasien'),
      const SizedBox(height: 12),
      TextField(
        decoration: const InputDecoration(
          hintText: 'Cari hasil asesmen atau terapi…',
          prefixIcon: Icon(Icons.search),
        ),
        onChanged: (query) => setState(() {
          _archiveQuery = query;
          _visibleAssessments = 4;
        }),
      ),
      const SizedBox(height: 6),
      Wrap(
        spacing: 8,
        children: [
          for (final option in const ['Semua', 'Asesmen', 'Terapi'])
            ChoiceChip(
              label: Text(option),
              selected: _archiveFilter == option,
              showCheckmark: false,
              onSelected: (_) => setState(() {
                _archiveFilter = option;
                _visibleAssessments = 4;
              }),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (_isUnavailable('Asesmen & lembar kerja'))
        _sectionStatus('Asesmen & lembar kerja'),
      if (_isUnavailable('Skrining PHQ-9 / GAD-7'))
        _sectionStatus('Skrining PHQ-9 / GAD-7'),
      if (filtered.isEmpty && entries.isNotEmpty)
        const SoftCard(child: Text('Tidak ada hasil yang cocok.')),
      if (entries.isEmpty &&
          !_isUnavailable('Skrining PHQ-9 / GAD-7') &&
          !_isUnavailable('Asesmen & lembar kerja'))
        const SoftCard(child: Text('Belum ada arsip klinis.')),
      for (final entry in filtered.take(_visibleAssessments)) ...[
        _archiveCard(entry),
        const SizedBox(height: 8),
      ],
      if (filtered.length > _visibleAssessments)
        OutlinedButton(
          onPressed: () => setState(() => _visibleAssessments += 5),
          child: Text(
              'Tunjukkan Lebih (${filtered.length - _visibleAssessments} lagi)'),
        ),
    ];
  }

  Widget _archiveCard(AssessmentHistoryEntry entry) {
    final screening = entry.screening;
    final crisis = screening?.crisisFlag == true;
    final color = crisis ? MalvaColors.danger : entry.color;
    return SoftCard(
      color: Colors.white,
      outline: crisis ? BorderSide(color: color.withValues(alpha: 0.25)) : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClinicalIconTile(icon: entry.icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                if (screening != null)
                  Wrap(
                    spacing: 6,
                    runSpacing: 5,
                    children: [
                      if (crisis)
                        const StatusPill(
                            label: 'CRISIS',
                            color: MalvaColors.danger,
                            icon: Icons.warning_amber_rounded),
                      for (final score in entry.subtitle.split(' • '))
                        StatusPill(label: score, color: color),
                    ],
                  )
                else if (entry.subtitle.isNotEmpty)
                  Text(entry.subtitle,
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                Text(
                  '${entry.isAssessmentResult ? 'Asesmen' : 'Terapi'} • ${formatAssessmentDate(entry.date)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Wrap(
                  spacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (screening != null || entry.isShared)
                      const StatusPill(
                          label: 'Dibagikan',
                          color: MalvaColors.mint,
                          icon: Icons.send_outlined),
                    TextButton(
                      onPressed: () => _showArchiveResult(entry),
                      child: const Text('Lihat hasil'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showArchiveResult(AssessmentHistoryEntry entry) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (_) => Consumer(builder: (context, ref, _) {
        ref.watch(authStateProvider);
        if (_accountChanged)
          return const Padding(
            padding: EdgeInsets.all(18),
            child: Text('Sesi akun telah berubah.'),
          );
        return FractionallySizedBox(
          heightFactor: 0.85,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              Text(entry.title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 10),
              if (entry.screening case final screening?)
                _clinicalScreening(screening)
              else
                TherapySubmissionView(
                  moduleId: entry.moduleId,
                  title: entry.title,
                  answers: entry.answers,
                  summary: entry.subtitle,
                ),
            ],
          ),
        );
      }),
    );
  }

  Widget _clinicalScreening(BackendScreeningSession sc) => CollapsibleCard(
        key: ValueKey('screening-${sc.id}'),
        initiallyExpanded: true,
        color: Colors.white,
        semanticLabel: 'Detail skrining ${_screeningDate(sc.createdAt)}',
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
  bool _verified = false;
  bool _diagnosisOpening = false;
  bool _accountChanged = false;
  Timer? _diagnosisBoundary;
  Timer? _consentPoll;
  int _loadRevision = 0;
  int _clinicalRevision = 0;
  bool _refreshingClinical = false;
  final _clinicalAccess = ValueNotifier(true);
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
    if (_accountChanged) return null;
    final current = ref.read(currentSessionProvider);
    final original = widget.session;
    if (current != null &&
        original != null &&
        (current.role != original.role ||
            (current.backendUserId ?? current.identifier) !=
                (original.backendUserId ?? original.identifier))) return null;
    final t = (current ?? original)?.accessToken;
    return (t == null || t.isEmpty) ? null : t;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _consentPoll = Timer.periodic(const Duration(seconds: 30), (_) {
      final state = WidgetsBinding.instance.lifecycleState;
      if (state == null || state == AppLifecycleState.resumed) {
        unawaited(_refreshClinical());
      }
    });
    ref.listenManual(authStateProvider, (previous, next) {
      final owner = widget.session ?? previous?.session;
      if (owner == null) return;
      final session = next.session;
      if (session?.role != owner.role ||
          (session?.backendUserId ?? session?.identifier) !=
              (owner.backendUserId ?? owner.identifier)) {
        setState(() => _accountChanged = true);
        _diagnosisBoundary?.cancel();
        _consentPoll?.cancel();
        _clinicalAccess.value = false;
      }
    });
    _load();
  }

  Iterable<({DateTime start, DateTime end})> get _diagnosisWindows sync* {
    final professional = widget.session ?? ref.read(currentSessionProvider);
    final id = professional?.backendUserId ?? professional?.identifier;
    if (id == null || !_verified || _accountChanged) return;
    for (final package in _packages) {
      if (!package.isActive ||
          package.totalSessions <= 1 ||
          package.patientId != widget.patientId ||
          package.professionalId != id) continue;
      final start = parseWibStored(package.startsAt);
      final end = package.expiresDateTime;
      if (start != null && end != null) yield (start: start, end: end);
    }
    for (final session in _sessions) {
      if (session.packageId?.isNotEmpty == true ||
          session.status != 'scheduled' ||
          session.patientId != widget.patientId ||
          session.professionalId != id) continue;
      final start = session.scheduledDateTime;
      if (start != null)
        yield (
          start: start,
          end: start.add(Duration(minutes: session.durationMinutes))
        );
    }
  }

  bool get _canEditDiagnosis {
    final now = ServerClock.now();
    return _healthRecord != null &&
        _diagnosisWindows.any((window) =>
            !now.isBefore(window.start) && now.isBefore(window.end));
  }

  Iterable<({DateTime? start, DateTime end})> get _readWindows sync* {
    final professional = widget.session ?? ref.read(currentSessionProvider);
    final id = professional?.backendUserId ?? professional?.identifier;
    if (id == null) return;
    for (final package in _packages) {
      final end = package.expiresDateTime;
      if (end != null &&
          package.isActive &&
          package.patientId == widget.patientId &&
          package.professionalId == id) {
        yield (start: null, end: end);
      }
    }
    for (final session in _sessions) {
      // A package session cannot extend access beyond its package.
      if (session.packageId?.isNotEmpty == true ||
          session.status != 'scheduled' ||
          session.patientId != widget.patientId ||
          session.professionalId != id) continue;
      final start = session.scheduledDateTime;
      if (start != null) {
        yield (
          start: start,
          end: start.add(Duration(minutes: session.durationMinutes))
        );
      }
    }
  }

  void _watchDiagnosisBoundary({DateTime? after}) {
    _diagnosisBoundary?.cancel();
    final now = ServerClock.now();
    final cutoff = after != null && after.isAfter(now) ? after : now;
    final future = [
      for (final window in _readWindows) ...[
        if (window.start != null) window.start!,
        window.end
      ],
      for (final window in _diagnosisWindows) ...[window.start, window.end],
    ].where((time) => time.isAfter(cutoff)).toList()
      ..sort();
    if (future.isEmpty) return;
    final boundary = future.first;
    _diagnosisBoundary = Timer(boundary.difference(now), () {
      if (!mounted || _accountChanged) return;
      if (!_readWindows.any((window) =>
          window.end.isAfter(boundary) &&
          (window.start == null || !boundary.isBefore(window.start!)))) {
        _clearClinical();
      } else {
        setState(() {});
      }
      unawaited(_refreshClinical(force: true));
      _watchDiagnosisBoundary(after: boundary);
    });
  }

  void _clearClinical() {
    ++_clinicalRevision;
    _refreshingClinical = false;
    setState(() {
      _healthRecord = null;
      _allergies = const [];
    });
    _clinicalAccess.value = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _accountChanged || _isLoading)
      return;
    final now = ServerClock.now();
    if (!_readWindows.any((window) =>
        window.end.isAfter(now) &&
        (window.start == null || !now.isBefore(window.start!)))) {
      _clearClinical();
    }
    _watchDiagnosisBoundary();
    unawaited(_refreshClinical(force: true));
  }

  Future<void> _refreshClinical({bool force = false}) async {
    final token = _token;
    if (token == null || _isLoading || (_refreshingClinical && !force)) return;
    final revision = ++_clinicalRevision;
    final patientId = widget.patientId;
    _refreshingClinical = true;
    final failed = <String>{};
    final unshared = <String>{};
    Future<T?> fetch<T>(String label, Future<T> Function() request) async {
      try {
        return await request();
      } on MalvaApiException catch (error) {
        if (error.statusCode == 401 || error.statusCode == 403) {
          unshared.add(label);
        } else {
          failed.add(label);
        }
      } on Object {
        failed.add(label);
      }
      return null;
    }

    const diagnosis = 'Rekam Medis';
    const allergies = 'Alergi & Reaksi Obat';
    final results = await Future.wait([
      fetch(diagnosis,
          () => _api.getHealthRecord(accessToken: token, patientId: patientId)),
      fetch(
          allergies,
          () => _api.listHealthRecordAllergies(
              accessToken: token, patientId: patientId)),
    ]);
    if (!mounted ||
        _accountChanged ||
        widget.patientId != patientId ||
        revision != _clinicalRevision) return;
    _refreshingClinical = false;
    setState(() {
      _healthRecord = results[0] as BackendHealthRecord?;
      _allergies =
          (results[1] as List<BackendHealthRecordAllergy>?) ?? const [];
      _failedSections = [
        ..._failedSections
            .where((label) => label != diagnosis && label != allergies),
        ...failed,
      ];
      _unsharedSections = [
        ..._unsharedSections
            .where((label) => label != diagnosis && label != allergies),
        ...unshared,
      ];
    });
    _clinicalAccess.value = _healthRecord != null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _diagnosisBoundary?.cancel();
    _consentPoll?.cancel();
    _clinicalAccess.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final revision = ++_loadRevision;
    final patientId = widget.patientId;
    ++_clinicalRevision;
    _refreshingClinical = false;
    bool current() =>
        mounted &&
        !_accountChanged &&
        revision == _loadRevision &&
        widget.patientId == patientId;
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
            if (current()) {
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
                accessToken: token, patientId: widget.patientId, limit: 0),
            'Skrining PHQ-9 / GAD-7'),
        safely(
            () => _api.listTherapySubmissions(
                accessToken: token, patientId: widget.patientId),
            'Asesmen & lembar kerja'),
        safely(
            () =>
                _api.listGoals(accessToken: token, patientId: widget.patientId),
            'Target'),
        safely(
            () => _api.listMoodCheckins(
                accessToken: token, patientId: widget.patientId, limit: 0),
            'Mood'),
        safely(
            () => _api.listMedications(
                accessToken: token, patientId: widget.patientId, limit: 100),
            'Obat'),
        safely(
          () => _api.listHealthRecordAllergies(
              accessToken: token, patientId: widget.patientId),
          'Alergi & Reaksi Obat',
        ),
        safely(
          () => _api.listMedicationLogs(
              accessToken: token, patientId: widget.patientId, limit: 0),
          'Kepatuhan Obat',
        ),
      ]);
      final record = await safely(
          () => _api.getHealthRecord(
                accessToken: token,
                patientId: widget.patientId,
              ),
          'Rekam Medis');
      if (!current()) return;
      // Muat kredensial sendiri untuk menentukan apakah Psikiater (hanya
      // Psikiater yang boleh meresepkan). Kegagalan memuat tidak menjatuhkan
      // layar — perlakukan sebagai bukan psikiater (aman).
      BackendProfessionalCredential? cred;
      try {
        cred = await _api.getMyCredentials(accessToken: token);
      } on Object {
        cred = null;
      }
      if (!current()) return;
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
        _allergies =
            (results[7] as List<BackendHealthRecordAllergy>?) ?? const [];
        final logs = results[8] as List<BackendMedicationLog>?;
        _adherence = logs == null || _medications.isEmpty
            ? null
            : clinicalMedicationAdherence(_medications, logs);
        _verified = cred?.verificationStatus.toUpperCase() == 'VERIFIED';
        _isPsychiatrist =
            cred != null && isPsychiatristSpecialization(cred.specialization);
        _failedSections = List.unmodifiable(failed);
        _unsharedSections = List.unmodifiable(unshared);
        _isLoading = false;
      });
      _clinicalAccess.value = record != null;
      _watchDiagnosisBoundary();
    } on Object catch (e) {
      if (!current()) return;
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
    if (_accountChanged) {
      return Scaffold(
        appBar: AppBar(title: const Text('Info Pasien')),
        body: const Center(
            child: Text('Sesi akun telah berubah. Buka kembali info pasien.')),
      );
    }
    return Theme(
        data: Theme.of(context).copyWith(
            cardTheme: Theme.of(context).cardTheme.copyWith(elevation: .35)),
        child: Scaffold(
          appBar: AppBar(
            centerTitle: false,
            titleTextStyle: const TextStyle(
              fontFamily: 'Roboto',
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: Colors.white,
            ),
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.patientName,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                const Text('PROFIL KLINIS',
                    style:
                        TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
              ],
            ),
            flexibleSpace: const DecoratedBox(
              decoration: BoxDecoration(
                  gradient: LinearGradient(
                colors: [MalvaColors.seed, MalvaColors.orchid],
              )),
            ),
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
                  SectionLabel(
                    'Paket & Sesi Konsultasi',
                    action: StatusPill(
                        label: '${_packages.length} paket',
                        color: MalvaColors.seed),
                  ),
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
                      semanticLabel: 'Jadwal sesi',
                      initiallyExpanded: true,
                      header: const Text(
                        'Paket & sesi',
                        style: TextStyle(fontWeight: FontWeight.w900),
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
                                        const ClinicalIconTile(
                                          icon: Icons.calendar_today_outlined,
                                          color: MalvaColors.seed,
                                        ),
                                        const SizedBox(width: 8),
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
                                      '${p.remainingSessions}/${p.totalSessions} sesi tersisa'
                                      '${p.totalSessions > 0 ? ' • ${(p.usedSessions * 100 / p.totalSessions).round()}% terpakai' : ''}',
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
                  SectionLabel(
                    'Diagnosis Klinis (ICD-10)',
                    action: TextButton.icon(
                      onPressed: !_canEditDiagnosis || _diagnosisOpening
                          ? null
                          : () => _openHealthRecordEdit(context),
                      icon: const Icon(Icons.edit_note_rounded),
                      label: const Text('Isi diagnosis'),
                    ),
                  ),
                  if (_isUnavailable('Rekam Medis'))
                    _sectionStatus('Rekam Medis')
                  else if (_healthRecord?.diagnosisSummary.trim().isNotEmpty ==
                      true)
                    ClinicalDiagnosisCard(
                      record: _healthRecord!,
                      onEdit: !_canEditDiagnosis || _diagnosisOpening
                          ? null
                          : () => _openHealthRecordEdit(context),
                    )
                  else
                    const SoftCard(child: Text('Belum ada diagnosis.')),
                  const SizedBox(height: 22),
                  ClinicalAllergySection(
                    records: _allergies,
                    prescribing: true,
                    status: _isUnavailable('Alergi & Reaksi Obat')
                        ? _sectionStatus('Alergi & Reaksi Obat')
                        : null,
                  ),
                  const SizedBox(height: 22),
                  SectionLabel(
                    'Obat Aktif (${_medications.length})',
                    action: _isPsychiatrist
                        ? TextButton.icon(
                            onPressed: () => _openPrescribeMedication(context),
                            icon: const Icon(Icons.add),
                            label: const Text('Resepkan obat'),
                          )
                        : null,
                  ),
                  if (_isUnavailable('Obat'))
                    _sectionStatus('Obat')
                  else if (_medications.isEmpty)
                    const SoftCard(child: Text('Belum ada obat aktif.'))
                  else ...[
                    if (_adherence != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: StatusPill(
                          label: 'Kepatuhan $_adherence% (7 hr)',
                          color: MalvaColors.seed,
                        ),
                      ),
                    for (final medication in _medications) ...[
                      ClinicalMedicationCard(med: medication),
                      const SizedBox(height: 8),
                    ],
                  ],
                  const SizedBox(height: 22),
                  ..._clinicalAssessmentRecords(),
                  // ============================================================
                  // GRUP 2 — Pemantauan harian (semua read-only → dilipat)
                  // ============================================================
                  const SizedBox(height: 22),
                  const SectionLabel('Pemantauan harian',
                      icon: Icons.monitor_heart_rounded),
                  if (_isUnavailable('Target'))
                    _sectionStatus('Target')
                  else if (_goals.isEmpty)
                    const EmptyState(
                      icon: Icons.flag_outlined,
                      title: 'Belum ada target / tidak dibagikan',
                      subtitle: 'Target pasien muncul bila dibagikan.',
                    )
                  else
                    CollapsibleCard(
                      key: const ValueKey('goals-section'),
                      color: Colors.white,
                      semanticLabel: 'Target & Kebiasaan',
                      header: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Target & Kebiasaan',
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
    if (!_canEditDiagnosis || _diagnosisOpening) return;
    setState(() => _diagnosisOpening = true);
    try {
      final service = Icd10Service();
      final catalog = await service.load();
      if (!context.mounted || !_canEditDiagnosis) return;
      final original = _healthRecord!.diagnosisSummary;
      final patientId = widget.patientId;
      var selected = selectedDiagnosesFrom(original, catalog);
      final legacy = selected.isEmpty && original.trim().isNotEmpty;
      var saving = false;
      String? error;
      final updated = await showDialog<BackendHealthRecord>(
        context: context,
        builder: (_) => ValueListenableBuilder<bool>(
            valueListenable: _clinicalAccess,
            builder: (_, active, __) =>
                Consumer(builder: (dialog, dialogRef, _) {
                  dialogRef.watch(authStateProvider);
                  if (!active ||
                      _accountChanged ||
                      !mounted ||
                      widget.patientId != patientId) {
                    return AlertDialog(
                      content: const Text('Akses diagnosis sudah berakhir.'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: const Text('Tutup'),
                        ),
                      ],
                    );
                  }
                  return StatefulBuilder(builder: (ctx, update) {
                    final summary = diagnosisSummaryFor(selected);
                    return PopScope(
                      canPop: !saving,
                      child: AlertDialog(
                        backgroundColor: Colors.white,
                        actionsPadding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        title: Row(
                          children: [
                            const Expanded(child: Text('Diagnosis Pasien')),
                            IconButton(
                              tooltip: 'Tutup',
                              onPressed:
                                  saving ? null : () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        scrollable: true,
                        content: SizedBox(
                          width: 440,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text(
                                  'Pilih diagnosis utama & sekunder berdasarkan kode ICD-10'),
                              const SizedBox(height: 14),
                              if (legacy) ...[
                                const Text('Diagnosis sebelumnya',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
                                Text(original),
                                const SizedBox(height: 12),
                              ],
                              DiagnosisSearchField(
                                service: service,
                                showSelectionCards: true,
                                selected: selected,
                                enabled: !saving,
                                onChanged: (value) => update(() {
                                  selected = value;
                                  error = null;
                                }),
                              ),
                              if (error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 8),
                                  child: Text(error!,
                                      style: TextStyle(
                                          color:
                                              Theme.of(ctx).colorScheme.error)),
                                ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: saving ? null : () => Navigator.pop(ctx),
                            child: const Text('Batal'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 42),
                              textStyle: const TextStyle(
                                  fontFamily: 'Roboto',
                                  fontWeight: FontWeight.w700),
                            ),
                            onPressed: saving ||
                                    summary == original ||
                                    (legacy && selected.isEmpty)
                                ? null
                                : () async {
                                    final token = _token;
                                    if (token == null || !_canEditDiagnosis) {
                                      update(() => error =
                                          'Izin mengubah diagnosis sudah berakhir.');
                                      return;
                                    }
                                    if (utf8.encode(summary).length > 2000) {
                                      update(() => error =
                                          'Diagnosis melebihi batas 2.000 byte.');
                                      return;
                                    }
                                    update(() {
                                      saving = true;
                                      error = null;
                                    });
                                    try {
                                      final record = await _api
                                          .updateHealthRecordDiagnosis(
                                        accessToken: token,
                                        patientId: patientId,
                                        diagnosisSummary: summary,
                                      );
                                      if (ctx.mounted && !_accountChanged) {
                                        Navigator.pop(ctx, record);
                                      }
                                    } on Object catch (e) {
                                      if (!ctx.mounted || _accountChanged)
                                        return;
                                      update(() {
                                        saving = false;
                                        error = friendlyErrorMessage(e);
                                      });
                                    }
                                  },
                            child: Text(
                                saving ? 'Menyimpan...' : 'Simpan Diagnosis'),
                          ),
                        ],
                      ),
                    );
                  });
                })),
      );
      if (!context.mounted ||
          _accountChanged ||
          !_clinicalAccess.value ||
          updated == null) return;
      ++_clinicalRevision;
      _refreshingClinical = false;
      setState(() => _healthRecord = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Diagnosis tersimpan.'),
          backgroundColor: MalvaColors.mint,
        ),
      );
    } on Object catch (e) {
      if (!context.mounted || _accountChanged) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    } finally {
      if (mounted) setState(() => _diagnosisOpening = false);
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
