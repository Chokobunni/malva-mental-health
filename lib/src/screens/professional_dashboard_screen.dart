import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/dashboard_sync_service.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';
import '../widgets/professional_avatar.dart';
import 'booking/credential_screens.dart';
import 'notifications_screen.dart';
import 'portal/crisis_incident_log_screen.dart';
import 'portal/e_prescription_screen.dart';
import 'portal/earnings_screen.dart';
import 'pro_patient_detail_screen.dart';
import 'pro_pricing_screen.dart';
import 'professional_profile_editor_screen.dart';
import 'pro_schedule_screen.dart';

class ProfessionalDashboardScreen extends ConsumerStatefulWidget {
  const ProfessionalDashboardScreen({
    super.key,
    required this.onLogout,
    this.session,
    this.apiClient,
    this.syncService,
  });

  final VoidCallback onLogout;
  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final DashboardSyncService? syncService;

  @override
  ConsumerState<ProfessionalDashboardScreen> createState() =>
      _ProfessionalDashboardScreenState();
}

class _ProfessionalDashboardScreenState
    extends ConsumerState<ProfessionalDashboardScreen> {
  final Set<String> _reviewedScreeningIds = {};
  final Map<String, List<BackendProfessionalNote>> _professionalNotes = {};

  List<BackendPatientProfessionalLink> _links = const [];
  Map<String, List<BackendScreeningSession>> _screeningsByPatient = const {};
  List<_AuditEntry> _serverAuditEntries = const [];
  String? _selectedPatientId;
  String _searchQuery = '';
  int _tabIndex = 0;
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
    final patients = _patientsForDashboard();
    final selected = _selectedPatient(patients);
    // Dihitung SETELAH dedup agar konsisten dengan daftar yang benar-benar
    // dirender. Satu screening krisis yang belum direview muncul di kedua
    // antrean; tanpa dedup tombol "Lihat semua prioritas" bisa muncul
    // padahal tidak ada item tambahan yang bisa dilihat.
    final priorityCount = _dedupByScreening([
      ..._crisisQueue(patients),
      ..._reviewQueue(patients),
    ]).length;
    return Scaffold(
      body: Column(
        children: [
          GradientHeader(
            title: 'Professional',
            subtitle: 'Prioritas pasien, screening, sesi, dan paket',
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
                  tooltip: 'Notifikasi',
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => NotificationsScreen(
                        session: widget.session,
                        apiClient: widget.apiClient,
                      ),
                    ),
                  ),
                  icon: const Icon(Icons.notifications_rounded,
                      color: Colors.white),
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
                      : const Icon(Icons.refresh_rounded, color: Colors.white),
                ),
                IconButton(
                  tooltip: 'Keluar',
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout_rounded, color: Colors.white),
                ),
              ],
            ),
          ),
          Expanded(
            child: _tabIndex == 1
                ? ProScheduleScreen(
                    session: widget.session,
                    apiClient: widget.apiClient,
                  )
                : RefreshIndicator(
                    onRefresh: _loadOnlineProfessionalData,
                    child: ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
                        // ---- TAB 0: DASHBOARD ----
                        if (_tabIndex == 0)
                          _DashboardStatusStrip(
                            isLoading: _isLoadingOnlineData,
                            error: _onlineError,
                            hasBackendSession:
                                widget.session?.accessToken?.isNotEmpty == true,
                            onRetry: _loadOnlineProfessionalData,
                            syncStatus: _syncStatus,
                            lastSyncTime: _lastSyncTime,
                          ),
                        if (_tabIndex == 0)
                          const SectionLabel('Ringkasan',
                              icon: Icons.insights_rounded),
                        // ---- QUICK ACTION: Create Meeting ----
                        if (_tabIndex == 0) ...[
                          _CreateMeetingButton(
                            session: widget.session,
                            apiClient: widget.apiClient,
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (_tabIndex == 0)
                          _PriorityMetrics(
                            patientCount: patients.length,
                            crisisCount: _crisisQueue(patients).length,
                            reviewCount: _reviewQueue(patients).length,
                            onPatientsTap: _showActivePatientsSheet,
                            onCrisisTap: () =>
                                _showPriorityListSheet(crisisOnly: true),
                            onReviewTap: () =>
                                _showPriorityListSheet(crisisOnly: false),
                          ),
                        if (_tabIndex == 0) const SizedBox(height: 22),
                        // ---- TAB 2: PASIEN ----
                        if (_tabIndex == 2)
                          const SectionLabel('Cari & filter pasien',
                              icon: Icons.search_rounded),
                        if (_tabIndex == 2)
                          _PatientSearch(
                            query: _searchQuery,
                            onChanged: (value) =>
                                setState(() => _searchQuery = value),
                          ),
                        if (_tabIndex == 2) const SizedBox(height: 14),
                        if (_tabIndex == 0)
                          SectionLabel(
                            'Prioritas pasien',
                            icon: Icons.priority_high_rounded,
                            action: TextButton.icon(
                              onPressed: _loadOnlineProfessionalData,
                              icon: const Icon(Icons.refresh_rounded),
                              label: const Text('Refresh'),
                            ),
                          ),
                        if (_tabIndex == 0)
                          _PriorityQueue(
                            crisisQueue: _crisisQueue(patients),
                            reviewQueue: _reviewQueue(patients),
                            reviewedIds: _reviewedScreeningIds,
                            onReview: _openScreeningReview,
                            onOpenDetail: _showPriorityDetail,
                          ),
                        if (_tabIndex == 0 && priorityCount > 3)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => _showPriorityListSheet(
                                  crisisOnly: false, showAll: true),
                              child: const Text('Lihat semua prioritas'),
                            ),
                          ),
                        // ---- TAB 0: Daftar pasien ringkas di dashboard ----
                        if (_tabIndex == 0 && patients.isNotEmpty) ...[
                          const SizedBox(height: 22),
                          SectionLabel(
                            'Pasien terhubung',
                            icon: Icons.people_alt_rounded,
                            action: TextButton.icon(
                              onPressed: () => setState(() => _tabIndex = 2),
                              icon: const Icon(Icons.arrow_forward_rounded,
                                  size: 16),
                              label: const Text('Semua'),
                            ),
                          ),
                          for (final patient in patients.take(5)) ...[
                            SoftCard(
                              bordered: true,
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ProPatientDetailScreen(
                                      patientId: patient.patientId,
                                      patientName: patient.displayName,
                                      session: widget.session,
                                      apiClient: widget.apiClient,
                                    ),
                                  ),
                                ).then((_) => _loadOnlineProfessionalData());
                              },
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  InitialAvatar(
                                    name: patient.displayName,
                                    radius: 18,
                                    color: patient.hasCrisis
                                        ? MalvaColors.danger
                                        : MalvaColors.seed,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          patient.displayName,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w900),
                                        ),
                                        Text(
                                          '${patient.sourceLabel} • ${_riskLabel(patient.latestLevel)}'
                                          '${patient.screenings.isNotEmpty ? ' • ${patient.screenings.length} screening' : ''}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (patient.hasCrisis)
                                    const StatusPill(
                                      label: 'Krisis',
                                      color: MalvaColors.danger,
                                    )
                                  else
                                    const Icon(Icons.chevron_right_rounded),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (patients.length > 5)
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                onPressed: () => setState(() => _tabIndex = 2),
                                child: Text(
                                    'Lihat semua ${patients.length} pasien'),
                              ),
                            ),
                        ],
                        if (_tabIndex == 2)
                          // Teks label dipertahankan persis "Pasien terhubung"
                          // (dipakai test widget). Jumlah pasien dipindah ke
                          // `action` supaya tidak mengubah string label.
                          SectionLabel(
                            'Pasien terhubung',
                            icon: Icons.people_alt_rounded,
                            action: Text('${patients.length} pasien'),
                          ),
                        if (_tabIndex == 2)
                          _ConnectedPatientList(
                            patients: _filterPatients(patients),
                            onOpen: (patient) {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ProPatientDetailScreen(
                                    patientId: patient.patientId,
                                    patientName: patient.displayName,
                                    session: widget.session,
                                    apiClient: widget.apiClient,
                                  ),
                                ),
                              ).then((_) => _loadOnlineProfessionalData());
                            },
                          ),
                        if (_tabIndex == 2 && patients.isEmpty)
                          const EmptyState(
                            icon: Icons.people_outline_rounded,
                            title: 'Belum ada pasien terhubung',
                            subtitle:
                                'Pasien terhubung setelah membeli paket atau booking sesi denganmu.',
                          ),
                        // ---- TAB 3: LAINNYA ----
                        if (_tabIndex == 3) ...[
                          _RelationshipManagementSection(
                            patients: patients,
                            professionalCode: widget.session?.identifier,
                            onRefresh: _loadOnlineProfessionalData,
                          ),
                          const SizedBox(height: 22),
                          _AuditAndExportSection(
                            auditEntries: _serverAuditEntries,
                            onExport: selected == null
                                ? () {}
                                : () => _openExportSummary(selected),
                          ),
                          const SizedBox(height: 22),
                          _ProfessionalPortalSection(
                            session: widget.session,
                            apiClient: widget.apiClient,
                            onRefresh: _loadOnlineProfessionalData,
                          ),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tabIndex,
        onDestinationSelected: (value) => setState(() => _tabIndex = value),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.dashboard_outlined),
              selectedIcon: Icon(Icons.dashboard_rounded),
              label: 'Dashboard'),
          NavigationDestination(
              icon: Icon(Icons.calendar_month_outlined),
              selectedIcon: Icon(Icons.calendar_month_rounded),
              label: 'Jadwal'),
          NavigationDestination(
              icon: Icon(Icons.people_outline_rounded),
              selectedIcon: Icon(Icons.people_rounded),
              label: 'Pasien'),
          NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view_rounded),
              label: 'Lainnya'),
        ],
      ),
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
      final reviewedScreeningIds = <String>{};
      final serverAuditEntries = <_AuditEntry>[];
      final notesByPatient = <String, List<BackendProfessionalNote>>{};

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

        screeningsByPatient[patientId] =
            results[0] as List<BackendScreeningSession>;

        final reviews = results[1] as List<BackendScreeningReview>? ??
            const <BackendScreeningReview>[];
        for (final review in reviews) {
          if (review.status.toLowerCase() != 'pending') {
            reviewedScreeningIds.add(review.screeningSessionId);
          }
        }

        final notes = results[2] as List<BackendProfessionalNote>? ??
            const <BackendProfessionalNote>[];
        notesByPatient[patientId] = notes;

        final auditLogs =
            results[3] as List<BackendAuditLog>? ?? const <BackendAuditLog>[];
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
        _serverAuditEntries = serverAuditEntries;
        _professionalNotes
          ..clear()
          ..addAll(notesByPatient);
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

  /// Pasien dashboard SELALU dari server (tanpa pasien demo lokal).
  List<_ProfessionalPatient> _patientsForDashboard() {
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
    final items = <_PriorityItem>[];
    final seen = <String>{};
    for (final patient in patients) {
      for (final screening in patient.screenings) {
        if (!screening.crisisFlag) continue;
        // Lewati screening yang sudah direview agar tidak menumpuk selamanya
        // di dashboard (dulu: baris crisis lama tetap tampil setelah direview).
        if (_reviewedScreeningIds.contains(screening.id)) continue;
        // Satu item per (pasien, screening) — jangan pernah render dua kali.
        if (!seen.add(screening.id)) continue;
        items.add(
          _PriorityItem(
            patient: patient,
            screening: screening,
            title: 'Crisis alert',
            body:
                '${patient.displayName} memiliki crisis flag pada screening ${_formatDate(screening.createdAt)}.',
            color: MalvaColors.danger,
          ),
        );
      }
    }
    // Urutkan terbaru dulu agar alert paling baru tampil paling atas.
    items.sort((a, b) {
      final at = a.screening.createdAt;
      final bt = b.screening.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return items;
  }

  List<_PriorityItem> _reviewQueue(List<_ProfessionalPatient> patients) {
    final items = <_PriorityItem>[];
    final seen = <String>{};
    for (final patient in patients) {
      for (final screening in patient.screenings.take(3)) {
        if (_reviewedScreeningIds.contains(screening.id)) continue;
        // Dedupe: satu item per screening walau data pasien terduplikasi.
        if (!seen.add(screening.id)) continue;
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
    // Urutkan terbaru dulu.
    items.sort((a, b) {
      final at = a.screening.createdAt;
      final bt = b.screening.createdAt;
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });
    return items;
  }

  // ----------------------------------------------------------
  // BOTTOM SHEETS — metrik & detail prioritas
  // ----------------------------------------------------------

  void _showActivePatientsSheet() {
    final list = _patientsForDashboard()
        .where((patient) => patient.status == 'active')
        .toList(growable: false);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Theme.of(sheetContext).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Pasien aktif (${list.length})',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Ketuk pasien untuk membuka detailnya di tab Pasien.',
                style: TextStyle(
                    color: Theme.of(sheetContext).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const EmptyState(
                  icon: Icons.people_outline_rounded,
                  title: 'Belum ada pasien aktif',
                  subtitle: 'Pasien terhubung akan tercatat di sini.',
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final patient = list[index];
                      return SoftCard(
                        bordered: true,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          setState(() {
                            _selectedPatientId = patient.patientId;
                            // Tab Pasien ada di indeks 2 (0=Dashboard,
                            // 1=Jadwal, 2=Pasien, 3=Lainnya). Sebelumnya
                            // bernilai 1 sehingga menekan pasien justru
                            // membuka layar Jadwal.
                            _tabIndex = 2;
                          });
                        },
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: patient.hasCrisis
                                  ? MalvaColors.danger
                                  : MalvaColors.seed.withValues(alpha: 0.12),
                              child: Text(
                                patient.displayName.isEmpty
                                    ? '?'
                                    : patient.displayName.characters.first
                                        .toUpperCase(),
                                style: TextStyle(
                                  color: patient.hasCrisis
                                      ? Colors.white
                                      : MalvaColors.seed,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    patient.displayName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900),
                                  ),
                                  Text(
                                    '${patient.sourceLabel} • ${_riskLabel(patient.latestLevel)}',
                                    style: Theme.of(sheetContext)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            color: Theme.of(sheetContext)
                                                .colorScheme
                                                .onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  /// Buang item ganda berdasarkan id screening, pertahankan kemunculan
  /// pertama. Dipakai jalur [showAll]: screening krisis yang belum direview
  /// muncul di `_crisisQueue` DAN `_reviewQueue` sehingga tanpa ini item yang
  /// sama dirender dua kali.
  List<_PriorityItem> _dedupByScreening(List<_PriorityItem> items) {
    final seen = <String>{};
    final result = <_PriorityItem>[];
    for (final item in items) {
      if (seen.add(item.screening.id)) {
        result.add(item);
      }
    }
    return result;
  }

  /// Bottom-sheet antrean prioritas.
  ///
  /// [crisisOnly] true → hanya antrean crisis; false → hanya antrean review.
  /// [showAll] true → gabungan antrean crisis + review (dipakai tombol
  /// "Lihat semua prioritas"). Tidak mengubah perilaku pemanggil lama.
  void _showPriorityListSheet({
    required bool crisisOnly,
    bool showAll = false,
  }) {
    final patients = _patientsForDashboard();
    final items = showAll
        ? _dedupByScreening([
            ..._crisisQueue(patients),
            ..._reviewQueue(patients),
          ])
        : crisisOnly
            ? _crisisQueue(patients)
            : _reviewQueue(patients);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Theme.of(sheetContext).colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                showAll
                    ? 'Semua prioritas (${items.length})'
                    : crisisOnly
                        ? 'Crisis alert (${items.length})'
                        : 'Perlu review (${items.length})',
                style: Theme.of(sheetContext)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                showAll
                    ? 'Gabungan antrean crisis & review klinis.'
                    : crisisOnly
                        ? 'Pasien dengan crisis flag — prioritaskan penilaian keselamatan.'
                        : 'Screening terbaru yang menunggu review klinis.',
                style: TextStyle(
                    color: Theme.of(sheetContext).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              if (items.isEmpty)
                EmptyState(
                  icon: showAll
                      ? Icons.inbox_rounded
                      : crisisOnly
                          ? Icons.check_circle_outline_rounded
                          : Icons.inbox_rounded,
                  title: showAll
                      ? 'Tidak ada prioritas'
                      : crisisOnly
                          ? 'Tidak ada crisis aktif'
                          : 'Semua sudah direview',
                  subtitle: showAll
                      ? 'Antrean crisis & review sedang kosong.'
                      : crisisOnly
                          ? 'Flag krisis baru akan muncul di sini.'
                          : 'Screening baru akan muncul di sini.',
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, index) {
                      final item = items[index];
                      return SoftCard(
                        bordered: true,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _showPriorityDetail(item);
                        },
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor:
                                  item.color.withValues(alpha: 0.16),
                              child: Icon(
                                (showAll
                                        ? item.screening.crisisFlag
                                        : crisisOnly)
                                    ? Icons.priority_high_rounded
                                    : Icons.fact_check_rounded,
                                color: item.color,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.patient.displayName,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900),
                                  ),
                                  Text(
                                    '${item.title} • ${_formatDate(item.screening.createdAt)}',
                                    style: Theme.of(sheetContext)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            color: Theme.of(sheetContext)
                                                .colorScheme
                                                .onSurfaceVariant),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _showPriorityDetail(_PriorityItem item) {
    final screening = item.screening;
    final isCrisis = screening.crisisFlag;
    final phqMax = screening.phq9MaxScore <= 0 ? 27 : screening.phq9MaxScore;
    final gadMax = screening.gad7MaxScore <= 0 ? 21 : screening.gad7MaxScore;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 12,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: Theme.of(sheetContext).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 26,
                      backgroundColor: item.color.withValues(alpha: 0.16),
                      child: Icon(
                        isCrisis
                            ? Icons.priority_high_rounded
                            : Icons.fact_check_rounded,
                        color: item.color,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 17),
                          ),
                          Text(
                            '${item.patient.displayName} • ${_formatDate(screening.createdAt)}',
                            style: Theme.of(sheetContext)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: Theme.of(sheetContext)
                                        .colorScheme
                                        .onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    StatusPill(
                      label: isCrisis
                          ? 'Krisis'
                          : _riskLabel(screening.overallLevel),
                      color: item.color,
                    ),
                  ],
                ),
                if (isCrisis) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: MalvaColors.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: MalvaColors.danger.withValues(alpha: 0.3),
                      ),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.warning_amber_rounded,
                            color: MalvaColors.danger),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Crisis flag aktif. Prioritaskan penilaian keselamatan dan follow-up sesuai SOP klinis.',
                            style: TextStyle(
                              color: MalvaColors.danger,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SoftCard(
                  bordered: true,
                  color: isCrisis
                      ? MalvaColors.danger.withValues(alpha: 0.06)
                      : MalvaColors.seed.withValues(alpha: 0.04),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'PHQ-9: ${screening.phq9Score}/$phqMax',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          Text(
                            _riskLabel(screening.phq9Level),
                            style: TextStyle(
                              color: _riskColor(screening.phq9Level),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ProgressStrip(
                        value: screening.phq9Score / phqMax,
                        color: _riskColor(screening.phq9Level),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'GAD-7: ${screening.gad7Score}/$gadMax',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w900),
                            ),
                          ),
                          Text(
                            _riskLabel(screening.gad7Level),
                            style: TextStyle(
                              color: _riskColor(screening.gad7Level),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ProgressStrip(
                        value: screening.gad7Score / gadMax,
                        color: _riskColor(screening.gad7Level),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Overall: ${_riskLabel(screening.overallLevel)}',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Catatan: hasil screening adalah alat bantu, bukan diagnosis final.',
                        style: TextStyle(
                            color: Theme.of(sheetContext)
                                .colorScheme
                                .onSurfaceVariant,
                            fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(item.body),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    _openScreeningReview(item.patient, screening);
                  },
                  icon: const Icon(Icons.fact_check_rounded),
                  label: const Text('Review screening'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(sheetContext);
                    unawaited(
                        _reviewScreening(screening.id).catchError((_) {}));
                  },
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Tandai direview'),
                ),
              ],
            ),
          ),
        );
      },
    );
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
              const SizedBox(height: 8),
              // === Certainty Factor (FC + CF) ===
              Text(
                'CF PHQ-9: ${(screening.phq9CF * 100).toStringAsFixed(0)}% — '
                'CF GAD-7: ${(screening.gad7CF * 100).toStringAsFixed(0)}%',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              if (screening.ruleTrace.isNotEmpty)
                Text(
                  'Rule: ${screening.ruleTrace}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
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
            style: compactFilledButtonStyle,
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
      // Tandai lokal agar baris langsung hilang dari antrean & metrik turun,
      // tanpa perlu keluar dari layar. Refresh berikutnya menyelaraskan dgn server.
      setState(() => _reviewedScreeningIds.add(screeningId));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Screening ditandai sebagai direview.'),
          backgroundColor: MalvaColors.mint,
        ),
      );
    } on MalvaApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Gagal: ${e.message}'),
            backgroundColor: MalvaColors.danger),
      );
    }
  }

  void _exportData() async {
    final exportPatients = _patientsForDashboard();
    final selected = _selectedPatient(exportPatients);

    final StringBuffer csv = StringBuffer();
    csv.writeln('Malva Professional Dashboard Export');
    csv.writeln('Date: ${DateTime.now()}');
    csv.writeln();

    csv.writeln('--- Patient Info ---');
    csv.writeln('Name: ${selected?.displayName ?? "N/A"}');
    csv.writeln('ID: ${selected?.patientId ?? "N/A"}');
    csv.writeln();

    csv.writeln('--- Screening History ---');
    csv.writeln(
        'ID,PHQ-9 Score,PHQ-9 Level,GAD-7 Score,GAD-7 Level,Crisis,Created');
    if (selected != null) {
      for (final s in selected.screenings) {
        csv.writeln(
            '${s.id},${s.phq9Score},${s.phq9Level},${s.gad7Score},${s.gad7Level},${s.crisisFlag},${s.createdAt}');
      }
    }
    csv.writeln();

    csv.writeln('--- Audit Logs (server) ---');
    csv.writeln('Title,Body,Created');
    for (final a in _serverAuditEntries) {
      csv.writeln('${a.title},${a.body},${a.createdAt}');
    }

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: csv.toString(),
          subject: 'Malva Dashboard Export',
        ),
      );
    } on Object {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Export gagal'), backgroundColor: MalvaColors.danger),
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
                  color: MalvaColors.seed.withValues(alpha: 0.06),
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
                  color: MalvaColors.seed.withValues(alpha: 0.06),
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

/// Strip status ringkas untuk tab Dashboard: menggabungkan [_StatusBanner]
/// (error / belum login + tombol "Coba lagi") dan [_SyncStatusBar] (status
/// sinkronisasi) menjadi SATU baris agar tidak menumpuk dua blok status.
///
/// Prioritas tampil: error / belum login > status sync. Indikator dot
/// [_SyncStatusIndicator] di header tetap dipertahankan sebagai representasi
/// sync yang ringkas.
class _DashboardStatusStrip extends StatelessWidget {
  const _DashboardStatusStrip({
    required this.isLoading,
    required this.error,
    required this.hasBackendSession,
    required this.onRetry,
    required this.syncStatus,
    required this.lastSyncTime,
  });

  final bool isLoading;
  final String? error;
  final bool hasBackendSession;
  final Future<void> Function() onRetry;
  final SyncStatus syncStatus;
  final DateTime? lastSyncTime;

  @override
  Widget build(BuildContext context) {
    // Error atau belum login → banner (membawa pesan + tombol "Coba lagi").
    if (error != null || !hasBackendSession) {
      return _StatusBanner(
        isLoading: isLoading,
        error: error,
        hasBackendSession: hasBackendSession,
        onRetry: onRetry,
      );
    }
    // Sehat → satu baris status sync ringkas.
    return _SyncStatusBar(
      syncStatus: syncStatus,
      lastSyncTime: lastSyncTime,
      hasBackendSession: hasBackendSession,
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
          bordered: true,
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
          bordered: true,
          color: MalvaColors.danger.withValues(alpha: 0.08),
          child: const Text(
            'Belum login ke server. Login sebagai profesional untuk melihat data real.',
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
        bordered: true,
        accent: color,
        tone: color.withValues(alpha: 0.08),
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
    required this.onPatientsTap,
    required this.onCrisisTap,
    required this.onReviewTap,
  });

  final int patientCount;
  final int crisisCount;
  final int reviewCount;
  final VoidCallback onPatientsTap;
  final VoidCallback onCrisisTap;
  final VoidCallback onReviewTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _MetricCard(
            icon: Icons.people_alt_rounded,
            value: '$patientCount',
            label: 'Pasien aktif',
            color: MalvaColors.seed,
            onTap: onPatientsTap,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricCard(
            icon: Icons.warning_amber_rounded,
            value: '$crisisCount',
            label: 'Crisis alert',
            color: crisisCount == 0 ? MalvaColors.mint : MalvaColors.danger,
            onTap: onCrisisTap,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _MetricCard(
            icon: Icons.rate_review_rounded,
            value: '$reviewCount',
            label: 'Perlu review',
            color: reviewCount == 0 ? MalvaColors.mint : MalvaColors.orchid,
            onTap: onReviewTap,
          ),
        ),
      ],
    );
  }
}

/// Kartu metrik vertikal: ikon di atas, angka, lalu label 2 baris max.
/// Tidak pernah memaksa teks satu kolom huruf-per-huruf.
class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      bordered: true,
      onTap: onTap,
      accent: color,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
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
    required this.onOpenDetail,
  });

  final List<_PriorityItem> crisisQueue;
  final List<_PriorityItem> reviewQueue;
  final Set<String> reviewedIds;
  final void Function(_ProfessionalPatient patient, _ScreeningView screening)
      onReview;
  final void Function(_PriorityItem item) onOpenDetail;

  @override
  Widget build(BuildContext context) {
    // Buang duplikat: satu screening krisis yang belum direview muncul di
    // `crisisQueue` DAN `reviewQueue`, sehingga tanpa ini baris yang sama
    // tampil dua kali. Samakan dengan perilaku sheet "Semua prioritas".
    final seen = <String>{};
    final queue = [
      for (final item in [...crisisQueue, ...reviewQueue])
        if (seen.add(item.screening.id)) item,
    ].take(3).toList();
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
          _PriorityCard(
            item: item,
            reviewed: reviewedIds.contains(item.screening.id),
            onReview: () => onReview(item.patient, item.screening),
            onTap: () => onOpenDetail(item),
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
    required this.onOpen,
  });

  final List<_ProfessionalPatient> patients;
  final ValueChanged<_ProfessionalPatient> onOpen;

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
            bordered: true,
            onTap: () => onOpen(patient),
            child: Row(
              children: [
                InitialAvatar(
                  name: patient.displayName,
                  radius: 18,
                  color:
                      patient.hasCrisis ? MalvaColors.danger : MalvaColors.pink,
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
                      // Info kuota paket sengaja TIDAK ditampilkan di sini agar
                      // tidak dobel dengan halaman detail pasien (Paket & sesi).
                      Text(
                        '${patient.sourceLabel} - ${patient.status}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
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
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(
          'Relasi pasien–profesional',
          icon: Icons.link_rounded,
          action: TextButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.sync_rounded),
            label: const Text('Sync'),
          ),
        ),
        // Header (kode + penjelasan) selalu terlihat; daftar pasien dilipat.
        CollapsibleCard(
          initiallyExpanded: false,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Kode profesional: ${professionalCode ?? 'belum login backend'}',
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'Pasien memasukkan kode ini untuk memberi akses data screening kepada profesional.',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: onSurfaceVariant),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Divider(height: 22),
              if (patients.isEmpty)
                Text(
                  'Belum ada pasien terhubung.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: onSurfaceVariant),
                )
              else
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
          'Audit & export ringkasan',
          icon: Icons.history_rounded,
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
          // Daftar audit dilipat; tombol "Export" tetap di luar (header).
          CollapsibleCard(
            initiallyExpanded: false,
            header: Row(
              children: [
                const Icon(Icons.history_rounded, color: MalvaColors.seed),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Riwayat audit (${auditEntries.length})',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ],
            ),
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

class _ProfessionalPortalSection extends ConsumerStatefulWidget {
  const _ProfessionalPortalSection({
    this.session,
    this.apiClient,
    this.onRefresh,
  });

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  /// Memuat ulang data profesional di parent state setelah profil disimpan.
  final Future<void> Function()? onRefresh;

  @override
  ConsumerState<_ProfessionalPortalSection> createState() =>
      _ProfessionalPortalSectionState();
}

class _ProfessionalPortalSectionState
    extends ConsumerState<_ProfessionalPortalSection> {
  BackendProfessionalCredential? _credential;
  bool _isLoadingCredential = false;

  /// Alias agar referensi di bawah tetap ringkas.
  AuthSession? get session => widget.session;
  MalvaApiClient? get apiClient => widget.apiClient;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCredential());
  }

  /// Memuat kredensial sendiri (`GET /v1/credentials/me`) untuk menampilkan
  /// avatar + nama profesional di sisi profesional — permintaan produk:
  /// foto profil baru harus langsung tampil di KEDUA sisi.
  Future<void> _loadCredential() async {
    final token = widget.session?.accessToken;
    if (token == null || token.isEmpty) return;
    if (mounted) setState(() => _isLoadingCredential = true);
    try {
      // apiClientProvider bertipe non-null, jadi tidak perlu null-check.
      final MalvaApiClient client =
          widget.apiClient ?? ref.read(apiClientProvider);
      final credential = await client.getMyCredentials(accessToken: token);
      if (!mounted) return;
      setState(() {
        _credential = credential;
        _isLoadingCredential = false;
      });
    } on Object {
      // Best-effort: avatar jatuh ke fallback inisial, kartu tetap tampil.
      if (!mounted) return;
      setState(() => _isLoadingCredential = false);
    }
  }

  /// Dipanggil setelah editor profil berhasil menyimpan.
  void _handleProfileSaved() {
    unawaited(_loadCredential());
    final refresh = widget.onRefresh;
    if (refresh != null) unawaited(refresh());
  }

  @override
  Widget build(BuildContext context) {
    // Setiap revisi profil berubah (disimpan dari layar mana pun), muat ulang
    // kredensial agar foto & nama di kartu ini ikut terbarui.
    ref.listen<int>(professionalProfileRevisionProvider, (previous, next) {
      unawaited(_loadCredential());
    });
    final displayName = (widget.session?.displayName ?? '').trim();
    final specialization = (_credential?.specialization ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Profil Profesional', icon: Icons.badge_rounded),
        // Kartu identitas profesional: avatar + nama + status verifikasi.
        // Foto diambil dari photo_intro_url yang sama dengan yang dilihat
        // pasien, sehingga perubahan foto langsung terlihat di kedua sisi.
        SoftCard(
          child: Row(
            children: [
              ProfessionalAvatar(
                displayName: displayName.isEmpty ? 'Profesional' : displayName,
                radius: 28,
                photoUrl: _credential?.photoIntroUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName.isEmpty ? 'Profesional Malva' : displayName,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _isLoadingCredential
                          ? 'Memuat profil...'
                          : specialization.isEmpty
                              ? 'Belum ada spesialisasi'
                              : specialization,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              if (_credential != null)
                StatusPill(
                  label: _credential!.verificationStatus == 'VERIFIED'
                      ? 'Terverifikasi'
                      : 'Menunggu review',
                  color: _credential!.verificationStatus == 'VERIFIED'
                      ? MalvaColors.mint
                      : MalvaColors.amber,
                ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        const SectionLabel('Portal Profesional',
            icon: Icons.open_in_new_rounded),
        // Edit Profil — profesional mengatur foto, bio, spesialisasi,
        // pendidikan, faskes, dan alamat. Perubahan langsung terlihat di
        // halaman "Profesional Info" yang dilihat pasien.
        ActionTile(
          icon: Icons.edit_rounded,
          title: 'Edit Profil',
          subtitle: 'Foto, bio, keahlian, pendidikan, faskes & alamat',
          color: MalvaColors.seed,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfessionalProfileEditorScreen(
                session: session,
                apiClient: apiClient,
                // Muat ulang kartu identitas + data dashboard setelah simpan.
                onSaved: _handleProfileSaved,
              ),
            ),
          ).then((_) {
            // Setelah editor ditutup, segarkan juga data dashboard di parent
            // (daftar pasien, audit) agar tidak ada tampilan basi.
            _handleProfileSaved();
          }),
        ),
        const SizedBox(height: 10),
        const SectionLabel('Operasional'),
        ActionTile(
          icon: Icons.sell_rounded,
          title: 'Katalog Harga',
          subtitle: 'Atur harga quick chat, video, dan paket 4 sesi',
          color: MalvaColors.orchid,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProPricingScreen(
                session: session,
                apiClient: apiClient,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        ActionTile(
          icon: Icons.account_balance_wallet_rounded,
          title: 'Earnings',
          subtitle: 'Pendapatan, fee platform, dan payout',
          color: MalvaColors.amber,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EarningsScreen(
                session: session,
                apiClient: apiClient,
              ),
            ),
          ),
        ),
        const SizedBox(height: 22),
        const SectionLabel('Klinis & kepatuhan'),
        ActionTile(
          icon: Icons.medication_liquid_rounded,
          title: 'E-Prescription',
          subtitle: 'Terbitkan resep dengan digital signature + QR',
          color: MalvaColors.mint,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EPrescriptionScreen(
                session: session,
                apiClient: apiClient,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        ActionTile(
          icon: Icons.shield_rounded,
          title: 'Crisis Incident Log',
          subtitle: 'Incident aktif, resolusi, dan jejak liability',
          color: MalvaColors.danger,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CrisisIncidentLogScreen(
                session: session,
                apiClient: apiClient,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        ActionTile(
          icon: Icons.verified_outlined,
          title: 'Verifikasi STR/SIP',
          subtitle: 'Upload dokumen lisensi untuk verifikasi admin',
          color: MalvaColors.orchid,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => CredentialUploadScreen(
                session: session,
                apiClient: apiClient,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Kartu prioritas vertikal: header (avatar + judul + pill),
/// ringkasan, lalu skor + aksi. Ketuk untuk detail lengkap.
class _PriorityCard extends StatelessWidget {
  const _PriorityCard({
    required this.item,
    required this.reviewed,
    required this.onReview,
    required this.onTap,
  });

  final _PriorityItem item;
  final bool reviewed;
  final VoidCallback onReview;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final screening = item.screening;
    final isCrisis = screening.crisisFlag;
    return SoftCard(
      bordered: true,
      onTap: onTap,
      accent: item.color,
      tone: item.color.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: item.color.withValues(alpha: 0.16),
                child: Icon(
                  reviewed
                      ? Icons.check_rounded
                      : isCrisis
                          ? Icons.priority_high_rounded
                          : Icons.fact_check_rounded,
                  color: item.color,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(
                      '${item.patient.displayName} • ${_formatDate(screening.createdAt)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(
                label: isCrisis ? 'Krisis' : _riskLabel(screening.overallLevel),
                color: item.color,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            item.body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _ScoreChip(
                      label: 'PHQ-9',
                      value: '${screening.phq9Score}/${screening.phq9MaxScore}',
                    ),
                    _ScoreChip(
                      label: 'GAD-7',
                      value: '${screening.gad7Score}/${screening.gad7MaxScore}',
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: onReview,
                style: compactFilledButtonStyle,
                child: Text(reviewed ? 'Lihat' : 'Review'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScoreChip extends StatelessWidget {
  const _ScoreChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: MalvaColors.seed.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $value',
        style: const TextStyle(
          color: MalvaColors.seed,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
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
    this.phq9CF = 0.0,
    this.gad7CF = 0.0,
    this.ruleTrace = '',
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
      phq9CF: session.phq9.certaintyFactor,
      gad7CF: session.gad7.certaintyFactor,
      ruleTrace: session.phq9.ruleTrace,
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

  /// CF Forward Chaining (0-1) dari server / engine lokal.
  final double phq9CF;
  final double gad7CF;
  final String ruleTrace;

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
    'minimal' => 'Minimal',
    'mild' => 'Ringan',
    'moderate' => 'Sedang',
    'moderately_severe' => 'Cukup Berat',
    'severe' => 'Berat',
    'crisis' => 'Krisis',
    // Fail-safe: level yang tidak dikenal TIDAK boleh tampil sebagai
    // "Minimal". Menurunkan derajat pasien secara diam-diam berbahaya
    // secara klinis; lebih aman menampilkan yang lebih berat.
    _ => 'Berat',
  };
}

Color _riskColor(String value) {
  return switch (value.toLowerCase()) {
    'minimal' => MalvaColors.seed,
    'mild' => MalvaColors.mint,
    'moderate' => const Color(0xFFFFBE55),
    'moderately_severe' => const Color(0xFFE8873C),
    'severe' => MalvaColors.danger,
    'crisis' => MalvaColors.danger,
    // Fail-safe, lihat catatan pada _riskLabel.
    _ => MalvaColors.danger,
  };
}

String _formatDate(DateTime? value) {
  if (value == null) return 'Belum ada tanggal';
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day/$month/${value.year}';
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

/// Tombol "Create Meeting" di dashboard profesional. Membuat Google Meet instan
/// via backend API dan menampilkan link yang bisa dibagikan ke pasien untuk
/// video call real-time.
class _CreateMeetingButton extends StatefulWidget {
  const _CreateMeetingButton({this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  State<_CreateMeetingButton> createState() => _CreateMeetingButtonState();
}

class _CreateMeetingButtonState extends State<_CreateMeetingButton> {
  String? _meetingUrl;
  bool _isLoading = false;

  /// Buat Google Meet via backend API (POST /v1/meet/quick).
  Future<void> _createMeeting() async {
    if (_isLoading) return;
    final api = widget.apiClient;
    final token = widget.session?.accessToken;
    if (api == null || token == null || token.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesi tidak valid. Silakan login ulang.')),
      );
      return;
    }
    setState(() => _isLoading = true);
    try {
      final result = await api.createQuickMeet(accessToken: token);
      if (!mounted) return;
      setState(() => _meetingUrl = result.meetUrl);
    } on MalvaApiException catch (e) {
      if (!mounted) return;
      // Pesan error dari backend (mis. Google belum dihubungkan).
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuat meeting: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _shareMeeting() async {
    if (_meetingUrl == null) return;
    await SharePlus.instance.share(
      ShareParams(
        text: 'Gabung video call Malva: $_meetingUrl',
        subject: 'Video Call — Malva Mental Health',
      ),
    );
  }

  Future<void> _openMeeting() async {
    if (_meetingUrl == null) return;
    final uri = Uri.parse(_meetingUrl!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      bordered: true,
      color: MalvaColors.mint.withValues(alpha: 0.10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 20,
                backgroundColor: MalvaColors.mint,
                child:
                    Icon(Icons.videocam_rounded, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Quick Video Call',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                    ),
                    Text(
                      _meetingUrl == null
                          ? 'Buat room meeting instan untuk testing'
                          : 'Room aktif — bagikan link ke pasien',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_meetingUrl == null)
            FilledButton.icon(
              onPressed: _isLoading ? null : _createMeeting,
              icon: _isLoading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add_circle_outline_rounded, size: 18),
              label: Text(_isLoading ? 'Membuat...' : 'Create Meeting'),
              style: FilledButton.styleFrom(
                backgroundColor: MalvaColors.mint,
                foregroundColor: Colors.white,
              ),
            )
          else ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openMeeting,
                    icon: const Icon(Icons.open_in_new_rounded, size: 16),
                    label: const Text('Buka'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _shareMeeting,
                    icon: const Icon(Icons.share_rounded, size: 16),
                    label: const Text('Bagikan'),
                    style: FilledButton.styleFrom(
                      backgroundColor: MalvaColors.seed,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: _meetingUrl!));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Link disalin ke clipboard')),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  _meetingUrl!,
                  style: const TextStyle(
                    fontSize: 11,
                    color: MalvaColors.seed,
                    decoration: TextDecoration.underline,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _meetingUrl = null),
                child: const Text('Buat room baru',
                    style: TextStyle(fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
