import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../assessment_engine.dart';
import '../models.dart';
import '../services/dashboard_sync_service.dart';
import '../services/malva_api_client.dart';
import '../store/malva_store.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';

class ProfessionalDashboardScreen extends StatefulWidget {
  const ProfessionalDashboardScreen({
    super.key,
    required this.store,
    required this.onLogout,
    this.session,
    this.apiClient,
    this.syncService,
  });

  final MalvaStore store;
  final VoidCallback onLogout;
  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final DashboardSyncService? syncService;

  @override
  State<ProfessionalDashboardScreen> createState() =>
      _ProfessionalDashboardScreenState();
}

class _ProfessionalDashboardScreenState
    extends State<ProfessionalDashboardScreen> {
  final Set<String> _reviewedScreeningIds = {};
  final List<_AuditEntry> _auditEntries = [];
  final Map<String, List<BackendProfessionalNote>> _professionalNotes = {};
  final Map<String, List<BackendFollowUpMessage>> _followUpMessages = {};

  List<BackendPatientProfessionalLink> _links = const [];
  Map<String, List<BackendScreeningSession>> _screeningsByPatient = const {};
  Map<String, List<BackendTimelineEvent>> _timelineEventsByPatient = const {};
  Map<String, List<BackendMoodCheckin>> _moodsByPatient = const {};
  Map<String, List<BackendDiaryEntry>> _diariesByPatient = const {};
  Map<String, List<BackendMedication>> _medicationsByPatient = const {};
  Map<String, List<BackendMedicationLog>> _medicationLogsByPatient = const {};
  Set<String> _moodDiaryRestrictedPatients = const {};
  Set<String> _medicationRestrictedPatients = const {};
  List<_AuditEntry> _serverAuditEntries = const [];
  String? _selectedPatientId;
  String _searchQuery = '';
  bool _isLoadingOnlineData = false;
  String? _onlineError;

  SyncStatus _syncStatus = SyncStatus.idle;
  DateTime? _lastSyncTime;
  late final DashboardSyncService _syncService;
  StreamSubscription<DashboardSyncEvent>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _syncService = widget.syncService ?? DashboardSyncService();
    _syncService.setOnRefresh(_loadOnlineProfessionalData);
    _syncSubscription = _syncService.stream.listen((event) {
      if (!mounted) return;
      setState(() {
        _syncStatus = event.status;
        _lastSyncTime = event.lastSyncTime;
        if (event.status == SyncStatus.error && event.errorMessage != null) {
          _onlineError = event.errorMessage;
        }
      });
    });
    _syncService.startSync();
    unawaited(_loadOnlineProfessionalData());
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    if (widget.syncService == null) {
      _syncService.dispose();
    }
    super.dispose();
  }

  Future<void> _manualRefresh() async {
    await _syncService.refreshNow();
  }

  @override
  void didUpdateWidget(covariant ProfessionalDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session?.accessToken != widget.session?.accessToken) {
      unawaited(_loadOnlineProfessionalData());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final patients = _patientsForDashboard();
        final filteredPatients = _filterPatients(patients);
        final selectedPatient = _selectedPatient(patients);
        final selectedScreenings = selectedPatient == null
            ? <_ScreeningView>[]
            : selectedPatient.screenings;
        final crisisQueue = _crisisQueue(patients);
        final reviewQueue = _reviewQueue(patients);
        final isBackendPatient = selectedPatient?.sourceLabel == 'Backend';

        return Scaffold(
          body: RefreshIndicator(
            onRefresh: _loadOnlineProfessionalData,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                GradientHeader(
                  title: 'Professional',
                  subtitle:
                      'Prioritas pasien, screening, alert, dan follow-up klinis',
                  leading: const Icon(
                    Icons.medical_information_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _SyncStatusIndicator(
                        status: _syncStatus,
                        lastSyncTime: _lastSyncTime,
                      ),
                      IconButton(
                        tooltip: 'Refresh manual',
                        onPressed: _manualRefresh,
                        icon: _syncStatus == SyncStatus.syncing
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded,
                                color: Colors.white),
                      ),
                      IconButton(
                        tooltip: 'Keluar',
                        onPressed: widget.onLogout,
                        icon:
                            const Icon(Icons.logout_rounded, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _StatusBanner(
                        isLoading: _isLoadingOnlineData,
                        error: _onlineError,
                        hasBackendSession:
                            widget.session?.accessToken?.isNotEmpty == true,
                        onRetry: _loadOnlineProfessionalData,
                      ),
                      _SyncStatusBar(
                        syncStatus: _syncStatus,
                        lastSyncTime: _lastSyncTime,
                        hasBackendSession:
                            widget.session?.accessToken?.isNotEmpty == true,
                      ),
                      _PriorityMetrics(
                        patientCount: patients.length,
                        crisisCount: crisisQueue.length,
                        reviewCount: reviewQueue.length,
                      ),
                      const SizedBox(height: 18),
                      _PatientSearch(
                        query: _searchQuery,
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                      ),
                      const SizedBox(height: 18),
                      SectionLabel(
                        '1. Dashboard prioritas pasien',
                        action: TextButton.icon(
                          onPressed: _loadOnlineProfessionalData,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Refresh'),
                        ),
                      ),
                      _PriorityQueue(
                        crisisQueue: crisisQueue,
                        reviewQueue: reviewQueue,
                        reviewedIds: _reviewedScreeningIds,
                        onReview: _openScreeningReview,
                      ),
                      const SizedBox(height: 22),
                      const SectionLabel('2. Daftar pasien terhubung'),
                      _ConnectedPatientList(
                        patients: filteredPatients,
                        selectedPatientId: selectedPatient?.patientId,
                        onSelect: (patient) => setState(
                          () => _selectedPatientId = patient.patientId,
                        ),
                      ),
                      const SizedBox(height: 22),
                      if (selectedPatient == null)
                        const EmptyState(
                          icon: Icons.people_outline_rounded,
                          title: 'Belum ada pasien terhubung',
                          subtitle:
                              'Pasien perlu menghubungkan akun dengan ID profesional sebelum data real muncul.',
                        )
                      else ...[
                        _PatientDetailSection(
                          patient: selectedPatient,
                          professionalCode: widget.session?.identifier,
                        ),
                        const SizedBox(height: 22),
                        _ScreeningHistorySection(
                          patient: selectedPatient,
                          screenings: selectedScreenings,
                          reviewedIds: _reviewedScreeningIds,
                          onReview: _openScreeningReview,
                        ),
                        const SizedBox(height: 22),
                        _TimelineSection(
                          patient: selectedPatient,
                          backendEvents: _timelineEventsByPatient[
                                  selectedPatient.patientId] ??
                              const <BackendTimelineEvent>[],
                          diaryEntries: widget.store.diaryEntries.take(2),
                          medicationLogs: widget.store.medicationLogs.take(2),
                          allowLocalFallback: !isBackendPatient,
                        ),
                        const SizedBox(height: 22),
                        _MoodDiaryReviewSection(
                          online: isBackendPatient,
                          restricted: _moodDiaryRestrictedPatients
                              .contains(selectedPatient.patientId),
                          moods: _moodsByPatient[selectedPatient.patientId] ??
                              const <BackendMoodCheckin>[],
                          backendEntries:
                              _diariesByPatient[selectedPatient.patientId] ??
                                  const <BackendDiaryEntry>[],
                          localEntries:
                              widget.store.diaryEntries.take(4).toList(),
                          onBackendFeedback: (entry) =>
                              _openBackendDiaryFeedback(
                            selectedPatient,
                            entry,
                          ),
                          onLocalFeedback: _openDiaryFeedback,
                        ),
                        const SizedBox(height: 22),
                        _MedicationMonitoringSection(
                          store: widget.store,
                          online: isBackendPatient,
                          restricted: _medicationRestrictedPatients
                              .contains(selectedPatient.patientId),
                          medications: _medicationsByPatient[
                                  selectedPatient.patientId] ??
                              const <BackendMedication>[],
                          logs: _medicationLogsByPatient[
                                  selectedPatient.patientId] ??
                              const <BackendMedicationLog>[],
                        ),
                        const SizedBox(height: 22),
                        _ProfessionalNotesSection(
                          notes: _professionalNotes[selectedPatient.patientId] ?? const [],
                          followUps:
                              _followUpMessages[selectedPatient.patientId] ?? const [],
                          onEditNote: () => _openProfessionalNote(
                            selectedPatient,
                          ),
                          onFollowUp: () =>
                              _openFollowUpMessage(selectedPatient),
                        ),
                        const SizedBox(height: 22),
                        _RelationshipManagementSection(
                          patients: patients,
                          professionalCode: widget.session?.identifier,
                          onRefresh: _loadOnlineProfessionalData,
                        ),
                        const SizedBox(height: 22),
                        _AuditAndExportSection(
                          auditEntries: [
                            ..._auditEntries,
                            ..._serverAuditEntries,
                          ],
                          onExport: () => _openExportSummary(selectedPatient),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _loadOnlineProfessionalData() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      return;
    }

    setState(() {
      _isLoadingOnlineData = true;
      _onlineError = null;
    });

    try {
      Future<T?> safely<T>(Future<T> Function() load) async {
        try {
          return await load();
        } on Object {
          return null;
        }
      }

      final links = await apiClient.listPatientProfessionalLinks(
          accessToken: accessToken);
      final screeningsByPatient = <String, List<BackendScreeningSession>>{};
      final timelineEventsByPatient = <String, List<BackendTimelineEvent>>{};
      final moodsByPatient = <String, List<BackendMoodCheckin>>{};
      final diariesByPatient = <String, List<BackendDiaryEntry>>{};
      final medicationsByPatient = <String, List<BackendMedication>>{};
      final medicationLogsByPatient = <String, List<BackendMedicationLog>>{};
      final moodDiaryRestrictedPatients = <String>{};
      final medicationRestrictedPatients = <String>{};
      final notesByPatient = <String, List<BackendProfessionalNote>>{};
      final followUpsByPatient = <String, List<BackendFollowUpMessage>>{};
      final reviewedScreeningIds = <String>{};
      final serverAuditEntries = <_AuditEntry>[];

      final patientFutures = links.map((link) async {
        final patientId = link.patientId;
        
        final results = await Future.wait([
          apiClient.listScreenings(
            accessToken: accessToken,
            patientId: patientId,
            limit: 20,
          ),
          safely(() => apiClient.listScreeningReviews(
            accessToken: accessToken,
            patientId: patientId,
            limit: 50,
          )),
          safely(() => apiClient.listProfessionalNotes(
            accessToken: accessToken,
            patientId: patientId,
            limit: 5,
          )),
          safely(() => apiClient.listFollowUps(
            accessToken: accessToken,
            patientId: patientId,
            limit: 5,
          )),
          safely(() => apiClient.listTimeline(
            accessToken: accessToken,
            patientId: patientId,
            limit: 20,
          )),
          _loadMoodDiaryData(apiClient, accessToken, patientId),
          _loadMedicationData(apiClient, accessToken, patientId),
          safely(() => apiClient.listAuditLogs(
            accessToken: accessToken,
            patientId: patientId,
            limit: 20,
          )),
        ]);

        return (link, results);
      }).toList();

      final patientResults = await Future.wait(patientFutures);

      for (final (link, results) in patientResults) {
        final patientId = link.patientId;
        
        screeningsByPatient[patientId] = results[0] as List<BackendScreeningSession>;
        
        final reviews = results[1] as List<BackendScreeningReview>? ?? const <BackendScreeningReview>[];
        for (final review in reviews) {
          if (review.status.toLowerCase() != 'pending') {
            reviewedScreeningIds.add(review.screeningSessionId);
          }
        }

        final notes = results[2] as List<BackendProfessionalNote>? ?? const <BackendProfessionalNote>[];
        notesByPatient[patientId] = notes;

        final followUps = results[3] as List<BackendFollowUpMessage>? ?? const <BackendFollowUpMessage>[];
        followUpsByPatient[patientId] = followUps;

        timelineEventsByPatient[patientId] = results[4] as List<BackendTimelineEvent>? ?? const <BackendTimelineEvent>[];

        final moodDiaryResult = results[5] as _MoodDiaryResult;
        moodsByPatient[patientId] = moodDiaryResult.moods;
        diariesByPatient[patientId] = moodDiaryResult.diaries;
        if (moodDiaryResult.restricted) {
          moodDiaryRestrictedPatients.add(patientId);
        }

        final medicationResult = results[6] as _MedicationResult;
        medicationsByPatient[patientId] = medicationResult.medications;
        medicationLogsByPatient[patientId] = medicationResult.logs;
        if (medicationResult.restricted) {
          medicationRestrictedPatients.add(patientId);
        }

        final auditLogs = results[7] as List<BackendAuditLog>? ?? const <BackendAuditLog>[];
        serverAuditEntries.addAll(
          auditLogs.map(
            (entry) => _AuditEntry(
              title: entry.action,
              body: entry.entityType,
              createdAt: entry.createdAt ?? DateTime.now(),
            ),
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _links = links;
        _screeningsByPatient = screeningsByPatient;
        _timelineEventsByPatient = timelineEventsByPatient;
        _moodsByPatient = moodsByPatient;
        _diariesByPatient = diariesByPatient;
        _medicationsByPatient = medicationsByPatient;
        _medicationLogsByPatient = medicationLogsByPatient;
        _moodDiaryRestrictedPatients = moodDiaryRestrictedPatients;
        _medicationRestrictedPatients = medicationRestrictedPatients;
        _serverAuditEntries = serverAuditEntries;
        _professionalNotes
          ..clear()
          ..addAll(notesByPatient);
        _followUpMessages
          ..clear()
          ..addAll(followUpsByPatient);
        _reviewedScreeningIds.addAll(reviewedScreeningIds);
        _selectedPatientId ??= links.isEmpty ? null : links.first.patientId;
        _isLoadingOnlineData = false;
        _lastSyncTime = DateTime.now();
      });
    } on MalvaApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _onlineError = error.message;
        _isLoadingOnlineData = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _onlineError = 'Data profesional belum dapat dimuat: $error';
        _isLoadingOnlineData = false;
      });
    }
  }

  Future<_MoodDiaryResult> _loadMoodDiaryData(
    MalvaApiClient apiClient,
    String accessToken,
    String patientId,
  ) async {
    try {
      final moods = await apiClient.listMoodCheckins(
        accessToken: accessToken,
        patientId: patientId,
        limit: 30,
      );
      final diaries = await apiClient.listDiaryEntries(
        accessToken: accessToken,
        patientId: patientId,
        limit: 30,
      );
      return _MoodDiaryResult(moods: moods, diaries: diaries);
    } on MalvaApiException catch (error) {
      if (error.statusCode == 403) {
        return _MoodDiaryResult(
          moods: const [],
          diaries: const [],
          restricted: true,
        );
      }
      return _MoodDiaryResult(moods: const [], diaries: const []);
    } on Object {
      return _MoodDiaryResult(moods: const [], diaries: const []);
    }
  }

  Future<_MedicationResult> _loadMedicationData(
    MalvaApiClient apiClient,
    String accessToken,
    String patientId,
  ) async {
    try {
      final medications = await apiClient.listMedications(
        accessToken: accessToken,
        patientId: patientId,
        limit: 50,
      );
      final logs = await apiClient.listMedicationLogs(
        accessToken: accessToken,
        patientId: patientId,
        limit: 50,
      );
      return _MedicationResult(medications: medications, logs: logs);
    } on MalvaApiException catch (error) {
      if (error.statusCode == 403) {
        return _MedicationResult(
          medications: const [],
          logs: const [],
          restricted: true,
        );
      }
      return _MedicationResult(medications: const [], logs: const []);
    } on Object {
      return _MedicationResult(medications: const [], logs: const []);
    }
  }

  List<_ProfessionalPatient> _patientsForDashboard() {
    if (_links.isNotEmpty) {
      return [
        for (final link in _links)
          _ProfessionalPatient(
            patientId: link.patientId,
            displayName: link.patientDisplayName.isEmpty
                ? 'Pasien Malva'
                : link.patientDisplayName,
            sourceLabel: 'Backend',
            status: link.status,
            linkedAt: null,
            screenings: (_screeningsByPatient[link.patientId] ??
                    const <BackendScreeningSession>[])
                .map(_ScreeningView.fromBackend)
                .toList(growable: false),
          ),
      ];
    }

    final localScreenings = widget.store.screeningBundles
        .map(_ScreeningView.fromLocal)
        .toList(growable: false)
        .reversed
        .toList(growable: false);
    return [
      _ProfessionalPatient(
        patientId: widget.store.patient.id,
        displayName: widget.store.patient.name,
        sourceLabel: 'Demo lokal',
        status: 'active',
        linkedAt: null,
        screenings: localScreenings,
      ),
    ];
  }

  List<_ProfessionalPatient> _filterPatients(
    List<_ProfessionalPatient> patients,
  ) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return patients;
    return patients
        .where((patient) =>
            patient.displayName.toLowerCase().contains(query) ||
            patient.patientId.toLowerCase().contains(query) ||
            patient.latestLevel.toLowerCase().contains(query))
        .toList(growable: false);
  }

  _ProfessionalPatient? _selectedPatient(List<_ProfessionalPatient> patients) {
    if (patients.isEmpty) return null;
    final selectedId = _selectedPatientId;
    if (selectedId != null) {
      for (final patient in patients) {
        if (patient.patientId == selectedId) return patient;
      }
    }
    return patients.first;
  }

  List<_PriorityItem> _crisisQueue(List<_ProfessionalPatient> patients) {
    return [
      for (final patient in patients)
        for (final screening in patient.screenings)
          if (screening.crisisFlag)
            _PriorityItem(
              patient: patient,
              screening: screening,
              title: 'Crisis alert',
              body:
                  '${patient.displayName} memiliki crisis flag pada screening ${_formatDate(screening.createdAt)}.',
              color: MalvaColors.danger,
            ),
    ];
  }

  List<_PriorityItem> _reviewQueue(List<_ProfessionalPatient> patients) {
    final items = <_PriorityItem>[];
    for (final patient in patients) {
      for (final screening in patient.screenings.take(3)) {
        if (_reviewedScreeningIds.contains(screening.id)) continue;
        items.add(
          _PriorityItem(
            patient: patient,
            screening: screening,
            title: 'Screening belum direview',
            body:
                '${patient.displayName}: PHQ-9 ${screening.phq9Score}, GAD-7 ${screening.gad7Score}, level ${screening.overallLevelLabel}.',
            color: screening.overallColor,
          ),
        );
      }
    }
    return items;
  }

  void _openScreeningReview(
    _ProfessionalPatient patient,
    _ScreeningView screening,
  ) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(
          screening.crisisFlag
              ? Icons.warning_amber_rounded
              : Icons.fact_check_rounded,
          color: screening.crisisFlag ? MalvaColors.danger : MalvaColors.seed,
        ),
        title: Text('Review screening ${patient.displayName}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Tanggal: ${_formatDate(screening.createdAt)}'),
              const SizedBox(height: 8),
              Text(
                'PHQ-9: ${screening.phq9Score}/${screening.phq9MaxScore} (${screening.phq9LevelLabel})',
              ),
              Text(
                'GAD-7: ${screening.gad7Score}/${screening.gad7MaxScore} (${screening.gad7LevelLabel})',
              ),
              const SizedBox(height: 8),
              Text('Overall: ${screening.overallLevelLabel}'),
              if (screening.crisisFlag) ...[
                const SizedBox(height: 8),
                const Text(
                  'Crisis flag aktif. Prioritaskan penilaian keselamatan dan follow-up sesuai SOP klinis.',
                  style: TextStyle(
                    color: MalvaColors.danger,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Catatan: hasil screening adalah alat bantu, bukan diagnosis final.',
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              unawaited(_reviewScreening(screening.id).catchError((_) {}));
            },
            icon: const Icon(Icons.check_rounded),
            label: const Text('Tandai direview'),
          ),
        ],
      ),
    );
  }

  Future<void> _reviewScreening(String screeningId) async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) return;

    final noteController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.verified_rounded, color: MalvaColors.mint),
        title: const Text('Tandai sebagai direview?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Tambahkan catatan profesional (opsional):'),
            const SizedBox(height: 12),
            TextField(
              controller: noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Catatan review...',
              ),
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
            child: const Text('Ya, Tandai'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await apiClient.reviewScreening(
        accessToken: accessToken,
        screeningId: screeningId,
        status: 'reviewed',
        note: noteController.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Screening ditandai sebagai direview.'),
          backgroundColor: MalvaColors.mint,
        ),
      );
    } on MalvaApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal: ${e.message}'), backgroundColor: MalvaColors.danger),
      );
    }
  }

  void _openDiaryFeedback(BuildContext context, DiaryEntry entry) {
    final controller =
        TextEditingController(text: entry.professionalFeedback ?? '');
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 0, 18, bottomInset + 18),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Mood/diary review',
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                Text(entry.title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  minLines: 4,
                  maxLines: 8,
                  decoration: const InputDecoration(
                    labelText: 'Feedback untuk pasien',
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () {
                    final feedback = controller.text.trim();
                    widget.store.upsertDiary(
                      DiaryEntry(
                        id: entry.id,
                        createdAt: entry.createdAt,
                        mood: entry.mood,
                        title: entry.title,
                        note: entry.note,
                        professionalFeedback:
                            feedback.isEmpty ? null : feedback,
                      ),
                    );
                    setState(() {
                      _auditEntries.insert(
                        0,
                        _AuditEntry(
                          title: 'Feedback diary disimpan',
                          body: entry.title,
                          createdAt: DateTime.now(),
                        ),
                      );
                    });
                    Navigator.pop(sheetContext);
                  },
                  child: const Text('Simpan feedback'),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(controller.dispose);
  }

  void _openBackendDiaryFeedback(
    _ProfessionalPatient patient,
    BackendDiaryEntry entry,
  ) {
    final controller =
        TextEditingController(text: entry.professionalFeedback ?? '');
    _openTextSheet(
      title: 'Mood/diary review',
      subtitle: 'Feedback untuk diary "${entry.title}".',
      controller: controller,
      label: 'Feedback untuk pasien',
      actionLabel: 'Simpan feedback',
      onSave: (value) async {
        final apiClient = widget.apiClient;
        final accessToken = widget.session?.accessToken;
        if (value.isEmpty || apiClient == null || accessToken == null) return;
        try {
          await apiClient.updateDiaryFeedback(
            accessToken: accessToken,
            patientId: patient.patientId,
            diaryId: entry.id,
            feedback: value,
          );
          await _loadOnlineProfessionalData();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Feedback diary tersimpan.')),
          );
        } on Object catch (error) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Feedback gagal disimpan: $error')),
          );
        }
      },
    );
  }

  void _openProfessionalNote(_ProfessionalPatient patient) {
    final existing = _professionalNotes[patient.patientId];
    final controller = TextEditingController(
        text: existing?.isNotEmpty == true ? existing!.first.body : '');
    _openTextSheet(
      title: 'Catatan profesional',
      subtitle:
          'Catatan internal untuk ${patient.displayName}. Jika backend aktif, catatan ini tersimpan di server klinis.',
      controller: controller,
      label: 'Catatan internal',
      actionLabel: 'Simpan catatan',
      onSave: (value) async {
        setState(() {
          if (value.isEmpty) {
            _professionalNotes.remove(patient.patientId);
          } else {
            _professionalNotes[patient.patientId] = [
              if (existing != null) ...existing,
              BackendProfessionalNote(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                patientId: patient.patientId,
                professionalId: widget.session?.identifier ?? '',
                body: value,
                visibility: 'private',
                updatedAt: DateTime.now(),
              ),
            ];
          }
          _auditEntries.insert(
            0,
            _AuditEntry(
              title: 'Catatan profesional diperbarui',
              body: patient.displayName,
              createdAt: DateTime.now(),
            ),
          );
        });
        await _saveProfessionalNoteToBackend(patient, value);
      },
    );
  }

  void _openFollowUpMessage(_ProfessionalPatient patient) {
    final existing = _followUpMessages[patient.patientId];
    final controller =
        TextEditingController(text: existing?.isNotEmpty == true ? existing!.first.body : '');
    _openTextSheet(
      title: 'Follow-up message',
      subtitle:
          'Arahan untuk ${patient.displayName}. Jika backend aktif, pesan ini masuk ke Home pasien dan notifikasi realtime.',
      controller: controller,
      label: 'Pesan follow-up',
      actionLabel: 'Kirim follow-up',
      onSave: (value) async {
        setState(() {
          if (value.isEmpty) {
            _followUpMessages.remove(patient.patientId);
          } else {
            _followUpMessages[patient.patientId] = [
              if (existing != null) ...existing,
              BackendFollowUpMessage(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                patientId: patient.patientId,
                professionalId: widget.session?.identifier ?? '',
                body: value,
                status: 'sent',
                createdAt: DateTime.now(),
                readAt: null,
              ),
            ];
          }
          _auditEntries.insert(
            0,
            _AuditEntry(
              title: 'Draft follow-up diperbarui',
              body: patient.displayName,
              createdAt: DateTime.now(),
            ),
          );
        });
        await _saveFollowUpToBackend(patient, value);
      },
    );
  }

  Future<void> _saveProfessionalNoteToBackend(
    _ProfessionalPatient patient,
    String value,
  ) async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (value.isEmpty ||
        apiClient == null ||
        accessToken == null ||
        accessToken.isEmpty) {
      return;
    }

    try {
      await apiClient.createProfessionalNote(
        accessToken: accessToken,
        patientId: patient.patientId,
        body: value,
        visibility: 'private',
      );
      await _loadOnlineProfessionalData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Catatan tersimpan ke backend.')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Catatan tersimpan lokal, sync backend gagal: $error'),
        ),
      );
    }
  }

  Future<void> _saveFollowUpToBackend(
    _ProfessionalPatient patient,
    String value,
  ) async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (value.isEmpty ||
        apiClient == null ||
        accessToken == null ||
        accessToken.isEmpty) {
      return;
    }

    try {
      await apiClient.createFollowUp(
        accessToken: accessToken,
        patientId: patient.patientId,
        body: value,
        status: 'sent',
      );
      await _loadOnlineProfessionalData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Follow-up terkirim ke pasien.')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Follow-up tersimpan lokal, sync backend gagal: $error'),
        ),
      );
    }
  }

  void _openTextSheet({
    required String title,
    required String subtitle,
    required TextEditingController controller,
    required String label,
    required String actionLabel,
    required FutureOr<void> Function(String value) onSave,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(18, 0, 18, bottomInset + 18),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: Theme.of(sheetContext)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 6),
                Text(subtitle),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  minLines: 4,
                  maxLines: 8,
                  decoration: InputDecoration(labelText: label),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () async {
                    await onSave(controller.text.trim());
                    if (!sheetContext.mounted) return;
                    Navigator.pop(sheetContext);
                  },
                  child: Text(actionLabel),
                ),
              ],
            ),
          ),
        );
      },
    ).whenComplete(controller.dispose);
  }

  void _exportData() async {
    final patients = _patientsForDashboard();
    final selected = _selectedPatient(patients);

    final StringBuffer csv = StringBuffer();
    csv.writeln('Malva Professional Dashboard Export');
    csv.writeln('Date: ${DateTime.now()}');
    csv.writeln();

    csv.writeln('--- Patient Info ---');
    csv.writeln('Name: ${selected?.displayName ?? "N/A"}');
    csv.writeln('ID: ${selected?.patientId ?? "N/A"}');
    csv.writeln();

    csv.writeln('--- Screening History ---');
    csv.writeln('ID,PHQ-9 Score,PHQ-9 Level,GAD-7 Score,GAD-7 Level,Crisis,Created');
    if (selected != null) {
      for (final s in selected.screenings) {
        csv.writeln('${s.id},${s.phq9Score},${s.phq9Level},${s.gad7Score},${s.gad7Level},${s.crisisFlag},${s.createdAt}');
      }
    }
    csv.writeln();

    csv.writeln('--- Timeline Events ---');
    csv.writeln('ID,Type,Title,Body,Created');
    if (selected != null) {
      final events = _timelineEventsByPatient[selected.patientId] ?? const <BackendTimelineEvent>[];
      for (final e in events) {
        csv.writeln('${e.id},${e.type},${e.title},${e.body},${e.createdAt}');
      }
    }
    csv.writeln();

    csv.writeln('--- Audit Logs ---');
    csv.writeln('Title,Body,Created');
    for (final a in _auditEntries) {
      csv.writeln('${a.title},${a.body},${a.createdAt}');
    }

    try {
      await Share.share(csv.toString(), subject: 'Malva Dashboard Export');
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Export gagal'), backgroundColor: MalvaColors.danger),
      );
    }
  }

  void _openExportSummary(_ProfessionalPatient patient) {
    final latest = patient.latestScreening;
    final summary = [
      'Ringkasan Malva - ${patient.displayName}',
      'Patient ID: ${patient.patientId}',
      'Status relasi: ${patient.status}',
      if (latest != null) ...[
        'Screening terakhir: ${_formatDate(latest.createdAt)}',
        'Overall: ${latest.overallLevelLabel}',
        'PHQ-9: ${latest.phq9Score}/${latest.phq9MaxScore}',
        'GAD-7: ${latest.gad7Score}/${latest.gad7MaxScore}',
        'Crisis flag: ${latest.crisisFlag ? 'Ya' : 'Tidak'}',
      ],
      if (_professionalNotes[patient.patientId]?.isNotEmpty == true)
        'Catatan profesional: ${_professionalNotes[patient.patientId]!.map((n) => n.body).join("; ")}',
      if (_followUpMessages[patient.patientId]?.isNotEmpty == true)
        'Follow-up: ${_followUpMessages[patient.patientId]!.map((f) => f.body).join("; ")}',
    ].join('\n');

    final csvData = [
      'Field,Value',
      'Patient Name,${patient.displayName}',
      'Patient ID,${patient.patientId}',
      'Status,${patient.status}',
      if (latest != null) ...[
        'Screening Date,${_formatDate(latest.createdAt)}',
        'Overall Level,${latest.overallLevelLabel}',
        'PHQ-9 Score,${latest.phq9Score}/${latest.phq9MaxScore}',
        'GAD-7 Score,${latest.gad7Score}/${latest.gad7MaxScore}',
        'Crisis Flag,${latest.crisisFlag ? 'Yes' : 'No'}',
      ],
    ].join('\n');

    setState(() {
      _auditEntries.insert(
        0,
        _AuditEntry(
          title: 'Ringkasan diekspor',
          body: patient.displayName,
          createdAt: DateTime.now(),
        ),
      );
    });

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export ringkasan'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Format Text:',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(summary,
                    style: const TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 16),
              const Text('Format CSV:',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(csvData,
                    style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _exportData();
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy Data'),
          ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.isLoading,
    required this.error,
    required this.hasBackendSession,
    required this.onRetry,
  });

  final bool isLoading;
  final String? error;
  final bool hasBackendSession;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.only(bottom: 14),
        child: LinearProgressIndicator(),
      );
    }
    if (error != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: SoftCard(
          color: MalvaColors.danger.withValues(alpha: 0.08),
          child: Row(
            children: [
              const Icon(Icons.cloud_off_rounded, color: MalvaColors.danger),
              const SizedBox(width: 10),
              Expanded(child: Text(error!)),
              TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
            ],
          ),
        ),
      );
    }
    if (!hasBackendSession) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: SoftCard(
          color: MalvaColors.seed.withValues(alpha: 0.08),
          child: const Text(
            'Mode demo lokal aktif. Login profesional backend akan menampilkan pasien terhubung secara real.',
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

class _SyncStatusBar extends StatelessWidget {
  const _SyncStatusBar({
    required this.syncStatus,
    required this.lastSyncTime,
    required this.hasBackendSession,
  });

  final SyncStatus syncStatus;
  final DateTime? lastSyncTime;
  final bool hasBackendSession;

  @override
  Widget build(BuildContext context) {
    if (!hasBackendSession) return const SizedBox.shrink();

    final color = switch (syncStatus) {
      SyncStatus.syncing => MalvaColors.mint,
      SyncStatus.error => MalvaColors.danger,
      SyncStatus.idle => _stalenessColor,
    };

    final icon = switch (syncStatus) {
      SyncStatus.syncing => Icons.sync_rounded,
      SyncStatus.error => Icons.error_outline_rounded,
      SyncStatus.idle => Icons.check_circle_outline_rounded,
    };

    final text = switch (syncStatus) {
      SyncStatus.syncing => 'Menyinkronkan...',
      SyncStatus.error => 'Sync gagal',
      SyncStatus.idle => lastSyncTime != null
          ? 'Terakhir sync: ${_formatTimeAgo(lastSyncTime!)}'
          : 'Belum pernah sync',
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SoftCard(
        color: color.withValues(alpha: 0.08),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (syncStatus == SyncStatus.syncing)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
      ),
    );
  }

  Color get _stalenessColor {
    if (lastSyncTime == null) return Colors.grey;
    final diff = DateTime.now().difference(lastSyncTime!);
    if (diff.inMinutes < 5) return MalvaColors.mint;
    if (diff.inMinutes < 30) return MalvaColors.amber;
    return MalvaColors.danger;
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s lalu';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m lalu';
    if (diff.inHours < 24) return '${diff.inHours}j lalu';
    return '${diff.inDays}h lalu';
  }
}

class _PriorityMetrics extends StatelessWidget {
  const _PriorityMetrics({
    required this.patientCount,
    required this.crisisCount,
    required this.reviewCount,
  });

  final int patientCount;
  final int crisisCount;
  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: MetricTile(
            icon: Icons.people_alt_rounded,
            value: '$patientCount',
            label: 'Pasien aktif',
            color: MalvaColors.seed,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: MetricTile(
            icon: Icons.warning_amber_rounded,
            value: '$crisisCount',
            label: 'Crisis alert',
            color: crisisCount == 0 ? MalvaColors.mint : MalvaColors.danger,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: MetricTile(
            icon: Icons.rate_review_rounded,
            value: '$reviewCount',
            label: 'Perlu review',
            color: reviewCount == 0 ? MalvaColors.mint : MalvaColors.orchid,
          ),
        ),
      ],
    );
  }
}

class _PatientSearch extends StatelessWidget {
  const _PatientSearch({
    required this.query,
    required this.onChanged,
  });

  final String query;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      decoration: const InputDecoration(
        labelText: 'Filter/search pasien',
        hintText: 'Cari nama, patient id, atau level risiko',
        prefixIcon: Icon(Icons.search_rounded),
      ),
    );
  }
}

class _PriorityQueue extends StatelessWidget {
  const _PriorityQueue({
    required this.crisisQueue,
    required this.reviewQueue,
    required this.reviewedIds,
    required this.onReview,
  });

  final List<_PriorityItem> crisisQueue;
  final List<_PriorityItem> reviewQueue;
  final Set<String> reviewedIds;
  final void Function(_ProfessionalPatient patient, _ScreeningView screening)
      onReview;

  @override
  Widget build(BuildContext context) {
    final queue = [...crisisQueue, ...reviewQueue].take(5).toList();
    if (queue.isEmpty) {
      return const EmptyState(
        icon: Icons.inbox_rounded,
        title: 'Tidak ada prioritas urgent',
        subtitle:
            'Crisis flag dan screening yang belum direview akan muncul di sini.',
      );
    }

    return Column(
      children: [
        for (final item in queue) ...[
          _ReviewItem(
            title: item.title,
            body: item.body,
            color: item.color,
            reviewed: reviewedIds.contains(item.screening.id),
            onReview: () => onReview(item.patient, item.screening),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ConnectedPatientList extends StatelessWidget {
  const _ConnectedPatientList({
    required this.patients,
    required this.selectedPatientId,
    required this.onSelect,
  });

  final List<_ProfessionalPatient> patients;
  final String? selectedPatientId;
  final ValueChanged<_ProfessionalPatient> onSelect;

  @override
  Widget build(BuildContext context) {
    if (patients.isEmpty) {
      return const EmptyState(
        icon: Icons.person_search_rounded,
        title: 'Tidak ada pasien sesuai filter',
        subtitle: 'Coba ubah kata kunci pencarian.',
      );
    }

    return Column(
      children: [
        for (final patient in patients) ...[
          SoftCard(
            color: patient.patientId == selectedPatientId
                ? MalvaColors.seed.withValues(alpha: 0.08)
                : null,
            onTap: () => onSelect(patient),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      patient.hasCrisis ? MalvaColors.danger : MalvaColors.pink,
                  child: const Icon(Icons.person_rounded, color: Colors.white),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        patient.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '${patient.sourceLabel} - ${patient.status}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  label: patient.latestLevelLabel,
                  color: patient.latestColor,
                  icon: Icons.fact_check_rounded,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _PatientDetailSection extends StatelessWidget {
  const _PatientDetailSection({
    required this.patient,
    required this.professionalCode,
  });

  final _ProfessionalPatient patient;
  final String? professionalCode;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('3. Detail pasien'),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: patient.hasCrisis
                        ? MalvaColors.danger
                        : MalvaColors.pink,
                    child:
                        const Icon(Icons.person_rounded, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          patient.displayName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                        Text('Patient ID: ${patient.patientId}'),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  StatusPill(
                    label: 'Relasi ${patient.status}',
                    color: MalvaColors.seed,
                    icon: Icons.link_rounded,
                  ),
                  StatusPill(
                    label: patient.sourceLabel,
                    color: MalvaColors.mint,
                    icon: Icons.storage_rounded,
                  ),
                  StatusPill(
                    label: 'Latest ${patient.latestLevelLabel}',
                    color: patient.latestColor,
                    icon: Icons.monitor_heart_rounded,
                  ),
                  if (professionalCode != null)
                    StatusPill(
                      label: 'Kode pro: $professionalCode',
                      color: MalvaColors.orchid,
                      icon: Icons.verified_user_rounded,
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScreeningHistorySection extends StatelessWidget {
  const _ScreeningHistorySection({
    required this.patient,
    required this.screenings,
    required this.reviewedIds,
    required this.onReview,
  });

  final _ProfessionalPatient patient;
  final List<_ScreeningView> screenings;
  final Set<String> reviewedIds;
  final void Function(_ProfessionalPatient patient, _ScreeningView screening)
      onReview;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('4. Histori PHQ-9/GAD-7 & 6. Review screening'),
        if (screenings.isEmpty)
          const EmptyState(
            icon: Icons.fact_check_outlined,
            title: 'Belum ada histori screening',
            subtitle:
                'PHQ-9 dan GAD-7 pasien akan muncul setelah pasien submit screening.',
          )
        else
          for (final screening in screenings.take(6)) ...[
            SoftCard(
              color: screening.crisisFlag
                  ? MalvaColors.danger.withValues(alpha: 0.08)
                  : null,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _formatDate(screening.createdAt),
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      StatusPill(
                        label: reviewedIds.contains(screening.id)
                            ? 'Reviewed'
                            : 'Belum review',
                        color: reviewedIds.contains(screening.id)
                            ? MalvaColors.mint
                            : MalvaColors.orchid,
                        icon: reviewedIds.contains(screening.id)
                            ? Icons.check_rounded
                            : Icons.rate_review_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _ScoreLine(
                    label: 'PHQ-9',
                    score: screening.phq9Score,
                    maxScore: screening.phq9MaxScore,
                    level: screening.phq9LevelLabel,
                    color: screening.phq9Color,
                  ),
                  const SizedBox(height: 8),
                  _ScoreLine(
                    label: 'GAD-7',
                    score: screening.gad7Score,
                    maxScore: screening.gad7MaxScore,
                    level: screening.gad7LevelLabel,
                    color: screening.gad7Color,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      StatusPill(
                        label: 'Overall ${screening.overallLevelLabel}',
                        color: screening.overallColor,
                        icon: Icons.monitor_heart_rounded,
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: () => onReview(patient, screening),
                        child: const Text('Review'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _ScoreLine extends StatelessWidget {
  const _ScoreLine({
    required this.label,
    required this.score,
    required this.maxScore,
    required this.level,
    required this.color,
  });

  final String label;
  final int score;
  final int maxScore;
  final String level;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final value = maxScore == 0 ? 0.0 : score / maxScore;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '$label $score/$maxScore',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ),
            Text(level),
          ],
        ),
        const SizedBox(height: 6),
        ProgressStrip(value: value, color: color),
      ],
    );
  }
}

class _TimelineSection extends StatelessWidget {
  const _TimelineSection({
    required this.patient,
    required this.backendEvents,
    required this.diaryEntries,
    required this.medicationLogs,
    required this.allowLocalFallback,
  });

  final _ProfessionalPatient patient;
  final List<BackendTimelineEvent> backendEvents;
  final Iterable<DiaryEntry> diaryEntries;
  final Iterable<MedicationLog> medicationLogs;
  final bool allowLocalFallback;

  @override
  Widget build(BuildContext context) {
    final events = backendEvents.isNotEmpty
        ? backendEvents.map(_TimelineEvent.fromBackend).toList(growable: false)
        : allowLocalFallback
            ? <_TimelineEvent>[
                for (final screening in patient.screenings.take(4))
                  _TimelineEvent(
                    icon: Icons.fact_check_rounded,
                    title: 'Screening ${screening.overallLevelLabel}',
                    body:
                        'PHQ-9 ${screening.phq9Score}, GAD-7 ${screening.gad7Score}',
                    color: screening.overallColor,
                  ),
                for (final entry in diaryEntries)
                  _TimelineEvent(
                    icon: entry.mood.icon,
                    title: 'Diary: ${entry.title}',
                    body: entry.note,
                    color: MalvaColors.seed,
                  ),
                for (final log in medicationLogs)
                  _TimelineEvent(
                    icon: Icons.medication_rounded,
                    title: 'Medication ${log.status}',
                    body: log.medicationName,
                    color: MalvaColors.mint,
                  ),
              ]
            : <_TimelineEvent>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('7. Timeline pasien'),
        if (events.isEmpty)
          const EmptyState(
            icon: Icons.timeline_rounded,
            title: 'Timeline belum tersedia',
            subtitle: 'Screening, mood, diary, dan obat akan tersusun di sini.',
          )
        else
          SoftCard(
            child: Column(
              children: [
                for (final event in events.take(6)) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: event.color.withValues(alpha: 0.12),
                        child: Icon(event.icon, color: event.color, size: 19),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            Text(
                              event.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (event != events.take(6).last) const Divider(height: 18),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _MoodDiaryReviewSection extends StatelessWidget {
  const _MoodDiaryReviewSection({
    required this.online,
    required this.restricted,
    required this.moods,
    required this.backendEntries,
    required this.localEntries,
    required this.onBackendFeedback,
    required this.onLocalFeedback,
  });

  final bool online;
  final bool restricted;
  final List<BackendMoodCheckin> moods;
  final List<BackendDiaryEntry> backendEntries;
  final List<DiaryEntry> localEntries;
  final ValueChanged<BackendDiaryEntry> onBackendFeedback;
  final void Function(BuildContext context, DiaryEntry entry) onLocalFeedback;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('8. Mood/diary review'),
        if (restricted)
          const EmptyState(
            icon: Icons.lock_outline_rounded,
            title: 'Akses mood/diary dibatasi pasien',
            subtitle:
                'Pasien dapat mengubah consent dari menu Akses profesional.',
          )
        else if (online && moods.isEmpty && backendEntries.isEmpty)
          const EmptyState(
            icon: Icons.menu_book_outlined,
            title: 'Belum ada mood atau diary',
            subtitle:
                'Data baru pasien akan tampil otomatis setelah disinkronkan.',
          )
        else if (online) ...[
          if (moods.isNotEmpty)
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Check-in mood terbaru',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 10),
                  for (final mood in moods.take(4)) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(_moodIcon(mood.mood), color: MalvaColors.orchid),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${_moodLabel(mood.mood)} • tidur ${mood.sleepHours.toStringAsFixed(1)}j • energi ${mood.energy}/10 • cemas ${mood.anxiety}/10${mood.note.isEmpty ? '' : '\n${mood.note}'}',
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          if (moods.isNotEmpty && backendEntries.isNotEmpty)
            const SizedBox(height: 10),
          for (final entry in backendEntries.take(6)) ...[
            SoftCard(
              child: Row(
                children: [
                  CircleAvatar(child: Icon(_moodIcon(entry.mood))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(entry.title,
                            style:
                                const TextStyle(fontWeight: FontWeight.w900)),
                        Text(entry.note,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        if (entry.professionalFeedback?.isNotEmpty == true)
                          Text(
                            'Feedback: ${entry.professionalFeedback}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: MalvaColors.seed,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Beri feedback',
                    onPressed: () => onBackendFeedback(entry),
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ] else
          for (final entry in localEntries) ...[
            SoftCard(
              child: Row(
                children: [
                  CircleAvatar(child: Icon(entry.mood.icon)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          entry.title,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        Text(
                          entry.note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (entry.professionalFeedback != null)
                          Text(
                            'Feedback: ${entry.professionalFeedback}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: MalvaColors.seed,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Beri feedback',
                    onPressed: () => onLocalFeedback(context, entry),
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _MedicationMonitoringSection extends StatelessWidget {
  const _MedicationMonitoringSection({
    required this.store,
    required this.online,
    required this.restricted,
    required this.medications,
    required this.logs,
  });

  final MalvaStore store;
  final bool online;
  final bool restricted;
  final List<BackendMedication> medications;
  final List<BackendMedicationLog> logs;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('9. Monitoring obat'),
        if (restricted)
          const EmptyState(
            icon: Icons.lock_outline_rounded,
            title: 'Akses obat dibatasi pasien',
            subtitle:
                'Pasien dapat mengubah consent dari menu Akses profesional.',
          )
        else if (online && medications.isEmpty)
          const EmptyState(
            icon: Icons.medication_outlined,
            title: 'Belum ada obat aktif',
            subtitle: 'Obat yang dicatat pasien akan tampil di sini.',
          )
        else
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ScoreLine(
                  label: 'Adherence hari ini',
                  score: online
                      ? _backendAdherencePercent
                      : store.adherencePercent,
                  maxScore: 100,
                  level:
                      '${online ? _backendAdherencePercent : store.adherencePercent}%',
                  color: (online
                              ? _backendAdherencePercent
                              : store.adherencePercent) >=
                          80
                      ? MalvaColors.mint
                      : MalvaColors.orchid,
                ),
                const SizedBox(height: 14),
                if (online)
                  for (final med in medications) ...[
                    _MedicationRow(
                      name: med.name,
                      dosage: med.dosage,
                      stock: med.currentStock,
                      needsRefill: med.needsRefill,
                    ),
                    const SizedBox(height: 8),
                  ]
                else
                  for (final med in store.medications) ...[
                    Row(
                      children: [
                        Icon(
                          med.needsRefill
                              ? Icons.warning_amber_rounded
                              : Icons.medication_rounded,
                          color: med.needsRefill
                              ? MalvaColors.danger
                              : MalvaColors.seed,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '${med.name} ${med.dosage} - stok ${med.currentStock}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (med.needsRefill)
                          const StatusPill(
                            label: 'Refill',
                            color: MalvaColors.danger,
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                if (online && logs.isNotEmpty) ...[
                  const Divider(height: 22),
                  const Text('Log terbaru',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 8),
                  for (final log in logs.take(5))
                    Text(
                      '${log.medicationName}: ${log.status} • ${_formatDate(log.takenAt)}',
                    ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  int get _backendAdherencePercent {
    if (medications.isEmpty) return 0;
    final now = DateTime.now();
    final taken = logs.where((log) {
      final date = log.takenAt;
      return log.status == 'taken' &&
          date != null &&
          date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;
    }).length;
    return ((taken / medications.length) * 100).clamp(0, 100).round();
  }
}

class _MedicationRow extends StatelessWidget {
  const _MedicationRow({
    required this.name,
    required this.dosage,
    required this.stock,
    required this.needsRefill,
  });

  final String name;
  final String dosage;
  final int stock;
  final bool needsRefill;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          needsRefill ? Icons.warning_amber_rounded : Icons.medication_rounded,
          color: needsRefill ? MalvaColors.danger : MalvaColors.seed,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$name $dosage - stok $stock',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        if (needsRefill)
          const StatusPill(label: 'Refill', color: MalvaColors.danger),
      ],
    );
  }
}

class _ProfessionalNotesSection extends StatelessWidget {
  const _ProfessionalNotesSection({
    required this.notes,
    required this.followUps,
    required this.onEditNote,
    required this.onFollowUp,
  });

  final List<BackendProfessionalNote> notes;
  final List<BackendFollowUpMessage> followUps;
  final VoidCallback onEditNote;
  final VoidCallback onFollowUp;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('10. Catatan profesional & 12. Follow-up message'),
        Row(
          children: [
            Expanded(
              child: ActionTile(
                icon: Icons.edit_note_rounded,
                title: 'Catatan profesional',
                subtitle: notes.isNotEmpty
                    ? notes.first.body
                    : 'Tambah catatan internal lokal',
                onTap: onEditNote,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ActionTile(
                icon: Icons.send_rounded,
                title: 'Follow-up',
                subtitle: followUps.isNotEmpty
                    ? followUps.first.body
                    : 'Buat draft arahan pasien',
                color: MalvaColors.orchid,
                onTap: onFollowUp,
              ),
            ),
          ],
        ),
        if (notes.length > 1) ...[
          const SizedBox(height: 12),
          const Text('Riwayat catatan profesional:',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final note in notes)
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note.body, maxLines: 3, overflow: TextOverflow.ellipsis),
                  if (note.updatedAt != null)
                    Text(
                      _formatDate(note.updatedAt),
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                ],
              ),
            ),
        ],
        if (followUps.length > 1) ...[
          const SizedBox(height: 12),
          const Text('Riwayat follow-up:',
              style: TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          for (final fu in followUps)
            SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(fu.body, maxLines: 3, overflow: TextOverflow.ellipsis),
                  if (fu.createdAt != null)
                    Text(
                      _formatDate(fu.createdAt),
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _RelationshipManagementSection extends StatelessWidget {
  const _RelationshipManagementSection({
    required this.patients,
    required this.professionalCode,
    required this.onRefresh,
  });

  final List<_ProfessionalPatient> patients;
  final String? professionalCode;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          '11. Manajemen relasi pasien-profesional',
          action: TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.sync_rounded),
            label: const Text('Sync'),
          ),
        ),
        SoftCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Kode profesional: ${professionalCode ?? 'belum login backend'}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Text(
                'Pasien memasukkan kode ini untuk memberi akses data screening kepada profesional.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.black54),
              ),
              const Divider(height: 22),
              for (final patient in patients) ...[
                Row(
                  children: [
                    const Icon(Icons.link_rounded, color: MalvaColors.seed),
                    const SizedBox(width: 10),
                    Expanded(child: Text(patient.displayName)),
                    Text(patient.status),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _AuditAndExportSection extends StatelessWidget {
  const _AuditAndExportSection({
    required this.auditEntries,
    required this.onExport,
  });

  final List<_AuditEntry> auditEntries;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          '13. Audit log UI & 15. Export ringkasan',
          action: TextButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.ios_share_rounded),
            label: const Text('Export'),
          ),
        ),
        if (auditEntries.isEmpty)
          const EmptyState(
            icon: Icons.history_rounded,
            title: 'Belum ada audit UI lokal',
            subtitle:
                'Review, catatan, follow-up, dan export akan tercatat di sini.',
          )
        else
          SoftCard(
            child: Column(
              children: [
                for (final entry in auditEntries.take(6)) ...[
                  Row(
                    children: [
                      const Icon(Icons.history_rounded,
                          color: MalvaColors.seed),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              entry.title,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                            Text(
                                '${entry.body} - ${_formatDate(entry.createdAt)}'),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (entry != auditEntries.take(6).last)
                    const Divider(height: 18),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ReviewItem extends StatelessWidget {
  const _ReviewItem({
    required this.title,
    required this.body,
    required this.color,
    required this.reviewed,
    required this.onReview,
  });

  final String title;
  final String body;
  final Color color;
  final bool reviewed;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: color.withValues(alpha: 0.08),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.16),
            child: Icon(
              reviewed ? Icons.check_rounded : Icons.priority_high_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                Text(body),
              ],
            ),
          ),
          FilledButton(
            onPressed: onReview,
            child: Text(reviewed ? 'Lihat' : 'Review'),
          ),
        ],
      ),
    );
  }
}

class _ProfessionalPatient {
  const _ProfessionalPatient({
    required this.patientId,
    required this.displayName,
    required this.sourceLabel,
    required this.status,
    required this.linkedAt,
    required this.screenings,
  });

  final String patientId;
  final String displayName;
  final String sourceLabel;
  final String status;
  final DateTime? linkedAt;
  final List<_ScreeningView> screenings;

  _ScreeningView? get latestScreening =>
      screenings.isEmpty ? null : screenings.first;
  bool get hasCrisis => screenings.any((screening) => screening.crisisFlag);
  String get latestLevel => latestScreening?.overallLevel ?? 'minimal';
  String get latestLevelLabel => _riskLabel(latestLevel);
  Color get latestColor => _riskColor(latestLevel);
}

class _ScreeningView {
  const _ScreeningView({
    required this.id,
    required this.createdAt,
    required this.overallLevel,
    required this.crisisFlag,
    required this.phq9Score,
    required this.phq9MaxScore,
    required this.phq9Level,
    required this.gad7Score,
    required this.gad7MaxScore,
    required this.gad7Level,
  });

  factory _ScreeningView.fromBackend(BackendScreeningSession session) {
    return _ScreeningView(
      id: session.id,
      createdAt: session.createdAt,
      overallLevel: session.overallLevel,
      crisisFlag: session.crisisFlag,
      phq9Score: session.phq9.score,
      phq9MaxScore: session.phq9.maxScore == 0 ? 27 : session.phq9.maxScore,
      phq9Level: session.phq9.level,
      gad7Score: session.gad7.score,
      gad7MaxScore: session.gad7.maxScore == 0 ? 21 : session.gad7.maxScore,
      gad7Level: session.gad7.level,
    );
  }

  factory _ScreeningView.fromLocal(ScreeningBundle bundle) {
    return _ScreeningView(
      id: bundle.id,
      createdAt: bundle.createdAt,
      overallLevel: bundle.overallLevel.name,
      crisisFlag: bundle.crisisFlag,
      phq9Score: bundle.phq9.score,
      phq9MaxScore: bundle.phq9.maxScore,
      phq9Level: bundle.phq9.level.name,
      gad7Score: bundle.gad7.score,
      gad7MaxScore: bundle.gad7.maxScore,
      gad7Level: bundle.gad7.level.name,
    );
  }

  final String id;
  final DateTime? createdAt;
  final String overallLevel;
  final bool crisisFlag;
  final int phq9Score;
  final int phq9MaxScore;
  final String phq9Level;
  final int gad7Score;
  final int gad7MaxScore;
  final String gad7Level;

  String get overallLevelLabel => _riskLabel(overallLevel);
  String get phq9LevelLabel => _riskLabel(phq9Level);
  String get gad7LevelLabel => _riskLabel(gad7Level);
  Color get overallColor => _riskColor(overallLevel);
  Color get phq9Color => _riskColor(phq9Level);
  Color get gad7Color => _riskColor(gad7Level);
}

class _PriorityItem {
  const _PriorityItem({
    required this.patient,
    required this.screening,
    required this.title,
    required this.body,
    required this.color,
  });

  final _ProfessionalPatient patient;
  final _ScreeningView screening;
  final String title;
  final String body;
  final Color color;
}

class _TimelineEvent {
  const _TimelineEvent({
    required this.icon,
    required this.title,
    required this.body,
    required this.color,
  });

  factory _TimelineEvent.fromBackend(BackendTimelineEvent event) {
    return _TimelineEvent(
      icon: switch (event.type.toLowerCase()) {
        'screening' => Icons.fact_check_rounded,
        'mood' => Icons.mood_rounded,
        'diary' => Icons.edit_note_rounded,
        'follow_up' => Icons.mark_email_read_rounded,
        'medication' => Icons.medication_rounded,
        _ => Icons.timeline_rounded,
      },
      title: event.title,
      body: event.body,
      color: switch (event.type.toLowerCase()) {
        'screening' => MalvaColors.orchid,
        'mood' => MalvaColors.pink,
        'diary' => MalvaColors.seed,
        'follow_up' => MalvaColors.amber,
        'medication' => MalvaColors.mint,
        _ => MalvaColors.seed,
      },
    );
  }

  final IconData icon;
  final String title;
  final String body;
  final Color color;
}

class _AuditEntry {
  const _AuditEntry({
    required this.title,
    required this.body,
    required this.createdAt,
  });

  final String title;
  final String body;
  final DateTime createdAt;
}

String _riskLabel(String value) {
  return switch (value.toLowerCase()) {
    'mild' => 'Ringan',
    'moderate' => 'Sedang',
    'severe' => 'Berat',
    'crisis' => 'Krisis',
    _ => 'Minimal',
  };
}

Color _riskColor(String value) {
  return switch (value.toLowerCase()) {
    'mild' => MalvaColors.mint,
    'moderate' => const Color(0xFFFFBE55),
    'severe' => MalvaColors.danger,
    'crisis' => MalvaColors.danger,
    _ => MalvaColors.seed,
  };
}

String _formatDate(DateTime? value) {
  if (value == null) return 'Belum ada tanggal';
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day/$month/${value.year}';
}

IconData _moodIcon(String value) {
  return switch (value.toLowerCase()) {
    'great' => Icons.sentiment_very_satisfied_rounded,
    'good' => Icons.sentiment_satisfied_alt_rounded,
    'sad' => Icons.sentiment_dissatisfied_rounded,
    'awful' => Icons.sentiment_very_dissatisfied_rounded,
    _ => Icons.sentiment_neutral_rounded,
  };
}

String _moodLabel(String value) {
  return switch (value.toLowerCase()) {
    'great' => 'Sangat baik',
    'good' => 'Baik',
    'sad' => 'Sedih',
    'awful' => 'Buruk',
    _ => 'Cukup',
  };
}

class _MoodDiaryResult {
  const _MoodDiaryResult({
    required this.moods,
    required this.diaries,
    this.restricted = false,
  });

  final List<BackendMoodCheckin> moods;
  final List<BackendDiaryEntry> diaries;
  final bool restricted;
}

class _MedicationResult {
  const _MedicationResult({
    required this.medications,
    required this.logs,
    this.restricted = false,
  });

  final List<BackendMedication> medications;
  final List<BackendMedicationLog> logs;
  final bool restricted;
}

class _SyncStatusIndicator extends StatelessWidget {
  const _SyncStatusIndicator({
    required this.status,
    this.lastSyncTime,
  });

  final SyncStatus status;
  final DateTime? lastSyncTime;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      SyncStatus.syncing => MalvaColors.mint,
      SyncStatus.error => MalvaColors.danger,
      SyncStatus.idle => _stalenessColor,
    };

    final tooltip = switch (status) {
      SyncStatus.syncing => 'Syncing...',
      SyncStatus.error => 'Sync error',
      SyncStatus.idle => lastSyncTime != null
          ? 'Last synced: ${_formatTimeAgo(lastSyncTime!)}'
          : 'Not synced yet',
    };

    return Tooltip(
      message: tooltip,
      child: Container(
        width: 10,
        height: 10,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Color get _stalenessColor {
    if (lastSyncTime == null) return Colors.grey;
    final diff = DateTime.now().difference(lastSyncTime!);
    if (diff.inMinutes < 5) return MalvaColors.mint;
    if (diff.inMinutes < 30) return MalvaColors.amber;
    return MalvaColors.danger;
  }

  String _formatTimeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
