import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/care_session_time.dart';
import '../services/dashboard_sync_service.dart';
import '../services/malva_api_client.dart';
import '../services/meeting_launcher.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';
import '../widgets/friendly_error.dart';
import '../widgets/professional_avatar.dart';
import 'booking/credential_screens.dart';
import 'chat_screen.dart';
import 'google_account_screen.dart';
import 'notifications_screen.dart';
import 'portal/crisis_incident_log_screen.dart';
import 'portal/e_prescription_screen.dart';
import 'portal/earnings_screen.dart';
import 'portal/professional_assessment_history_screen.dart';
import 'portal/shared_patient_data_screen.dart';
import 'pro_patient_detail_screen.dart';
import 'pro_pricing_screen.dart';
import 'professional_profile_editor_screen.dart';
import 'pro_schedule_screen.dart';
import '../time/wib.dart';

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
  final Map<String, List<BackendProfessionalNote>> _professionalNotes = {};

  /// Pasien yang menolak/tidak membagikan data screening (403 access_denied
  /// per-pasien). Dipakai untuk menampilkan penanda kecil di kartu pasien,
  /// BUKAN banner global — satu pasien tanpa consent tidak boleh mematikan
  /// seluruh dashboard.
  final Set<String> _screeningNotShared = {};

  List<BackendPatientProfessionalLink> _links = const [];
  Map<String, List<BackendScreeningSession>> _screeningsByPatient = const {};
  List<_AuditEntry> _serverAuditEntries = const [];
  List<BackendCareSession> _upcomingSessions = const [];
  List<BackendCareSession> _todaySessions = const [];
  int _crisisLogCount = 0;
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
          _onlineError = friendlyServerMessage(event.errorMessage!);
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
                ? Column(
                    children: [
                      // Aksi "buat meeting" dipindah ke tab Jadwal agar tetap
                      // tersedia setelah tombolnya dilepas dari Dashboard.
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
                        child: _CreateMeetingButton(
                          session: widget.session,
                          apiClient: widget.apiClient,
                        ),
                      ),
                      Expanded(
                        child: ProScheduleScreen(
                          session: widget.session,
                          apiClient: widget.apiClient,
                        ),
                      ),
                    ],
                  )
                : RefreshIndicator(
                    onRefresh: _loadOnlineProfessionalData,
                    child: ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
                        // Banner error ringkas (hanya bila pemuatan gagal).
                        // Bukan "section" konten — sekadar pemberitahuan status
                        // agar kegagalan server tidak senyap, dengan pesan
                        // Indonesia yang ramah.
                        if (_tabIndex == 0 && _onlineError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14),
                            child: SoftCard(
                              bordered: true,
                              color: MalvaColors.danger.withValues(alpha: 0.08),
                              child: Row(
                                children: [
                                  const Icon(Icons.cloud_off_rounded,
                                      color: MalvaColors.danger),
                                  const SizedBox(width: 10),
                                  Expanded(child: Text(_onlineError!)),
                                  TextButton(
                                    onPressed: _loadOnlineProfessionalData,
                                    child: const Text('Coba lagi'),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // ---- TAB 0 §0: Sesi berjalan (video & chat) ----
                        if (_tabIndex == 0)
                          const SectionLabel('Sesi berjalan',
                              icon: Icons.play_circle_rounded),
                        if (_tabIndex == 0)
                          _OngoingSessionsSection(
                            sessions: _ongoingSessions,
                            isLoading: _isLoadingOnlineData,
                          ),
                        if (_tabIndex == 0) const SizedBox(height: 22),
                        // ---- TAB 0 §1: Video call mendatang ----
                        if (_tabIndex == 0)
                          const SectionLabel('Video call mendatang',
                              icon: Icons.videocam_rounded),
                        if (_tabIndex == 0)
                          _UpcomingVideoCallSection(
                            sessions: _upcomingVideoSessions,
                            isLoading: _isLoadingOnlineData,
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
                                        if (patient.screeningNotShared)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text(
                                              'Pasien belum membagikan data skrining',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: Colors.grey,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                            ),
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
                        // ---- TAB 0 §3: Crisis Incident Log (satu pintu) ----
                        if (_tabIndex == 0) ...[
                          const SizedBox(height: 22),
                          const SectionLabel('Crisis Incident Log',
                              icon: Icons.shield_rounded),
                          SoftCard(
                            bordered: true,
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => CrisisIncidentLogScreen(
                                  session: widget.session,
                                  apiClient: widget.apiClient,
                                ),
                              ),
                            ).then((_) => _loadOnlineProfessionalData()),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 14),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: (_crisisLogCount > 0
                                          ? MalvaColors.danger
                                          : MalvaColors.mint)
                                      .withValues(alpha: 0.12),
                                  child: Icon(Icons.shield_rounded,
                                      color: _crisisLogCount > 0
                                          ? MalvaColors.danger
                                          : MalvaColors.mint),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Riwayat insiden krisis',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w900)),
                                      Text(
                                        _crisisLogCount > 0
                                            ? '$_crisisLogCount belum ditangani'
                                            : 'Semua sudah ditangani',
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
                                if (_crisisLogCount > 0)
                                  StatusPill(
                                    label: '$_crisisLogCount',
                                    color: MalvaColors.danger,
                                  )
                                else
                                  const Icon(Icons.chevron_right_rounded),
                              ],
                            ),
                          ),
                        ],
                        // ---- TAB 0 §4: Riwayat Asesmen (satu pintu) ----
                        if (_tabIndex == 0) ...[
                          const SizedBox(height: 22),
                          const SectionLabel('Riwayat Asesmen',
                              icon: Icons.fact_check_rounded),
                          _PortalDoorCard(
                            icon: Icons.fact_check_rounded,
                            color: MalvaColors.seed,
                            title: 'Riwayat asesmen pasien',
                            subtitle: '$_totalScreenings asesmen dari '
                                '$_connectedPatientCount pasien terhubung',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ProfessionalAssessmentHistoryScreen(
                                  session: widget.session,
                                  apiClient: widget.apiClient,
                                ),
                              ),
                            ).then((_) => _loadOnlineProfessionalData()),
                          ),
                        ],
                        // ---- TAB 0 §5: Data Pasien Dibagikan (satu pintu) ----
                        if (_tabIndex == 0) ...[
                          const SizedBox(height: 22),
                          const SectionLabel('Data Pasien Dibagikan',
                              icon: Icons.folder_shared_rounded),
                          _PortalDoorCard(
                            icon: Icons.folder_shared_rounded,
                            color: MalvaColors.mint,
                            title: 'Data pasien dibagikan',
                            subtitle: 'Mood, diary, obat, health record, goals, '
                                'terapi • $_connectedPatientCount pasien',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SharedPatientDataScreen(
                                  session: widget.session,
                                  apiClient: widget.apiClient,
                                ),
                              ),
                            ).then((_) => _loadOnlineProfessionalData()),
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

  /// Sesi video terjadwal mendatang (status scheduled), urut terdekat dulu.
  List<BackendCareSession> get _upcomingVideoSessions {
    final list = _upcomingSessions
        .where((s) => s.sessionType == 'video' && s.status == 'scheduled')
        .toList();
    list.sort((a, b) {
      final at = parseWibStored(a.scheduledAt);
      final bt = parseWibStored(b.scheduledAt);
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return at.compareTo(bt);
    });
    return list;
  }

  /// Sesi yang jendela waktunya sedang berjalan sekarang (video maupun chat),
  /// urut berdasarkan waktu mulai. Memakai helper murni [isCareSessionOngoing]
  /// agar aturan jendela identik dengan unit test.
  List<BackendCareSession> get _ongoingSessions {
    final now = wibNow();
    final list = _todaySessions.where((s) {
      final at = parseWibStored(s.scheduledAt);
      if (at == null) return false;
      return isCareSessionOngoing(now, at, s.durationMinutes);
    }).toList();
    list.sort((a, b) {
      final at = parseWibStored(a.scheduledAt);
      final bt = parseWibStored(b.scheduledAt);
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return at.compareTo(bt);
    });
    return list;
  }

  /// Total asesmen (screening) dari seluruh pasien terhubung — untuk subtitle
  /// kartu "Riwayat Asesmen".
  int get _totalScreenings =>
      _screeningsByPatient.values.fold<int>(0, (sum, list) => sum + list.length);

  /// Jumlah pasien terhubung (link aktif).
  int get _connectedPatientCount => _links.length;

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
      final serverAuditEntries = <_AuditEntry>[];
      final notesByPatient = <String, List<BackendProfessionalNote>>{};
      // Pasien yang 403 (tidak membagikan screening). Dikumpulkan di sini
      // agar tidak tercampur dengan error jaringan/500.
      final screeningNotShared = <String>{};

      final patientFutures = links.map((link) async {
        final patientId = link.patientId;

        // `listScreenings` WAJIB dibungkus try/catch: satu pasien tanpa consent
        // membalas 403 dan tidak boleh membatalkan Future.wait sehingga
        // dashboard lain (link, statistik) tetap tampil. Hanya 403 yang
        // dicatat sebagai "screening belum dibagikan"; error lain diabaikan
        // sebagai daftar kosong tanpa menandai pasien.
        Future<List<BackendScreeningSession>> loadScreenings() async {
          try {
            return await apiClient.listScreenings(
              accessToken: accessToken,
              patientId: patientId,
              limit: 20,
            );
          } on MalvaApiException catch (error) {
            if (error.statusCode == 403) {
              screeningNotShared.add(patientId);
            }
            return const <BackendScreeningSession>[];
          } on Object {
            return const <BackendScreeningSession>[];
          }
        }

        final results = await Future.wait<Object?>([
          loadScreenings(),
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

        final notes = results[1] as List<BackendProfessionalNote>? ??
            const <BackendProfessionalNote>[];
        notesByPatient[patientId] = notes;

        final auditLogs =
            results[2] as List<BackendAuditLog>? ?? const <BackendAuditLog>[];
        serverAuditEntries.addAll(
          auditLogs.map(
            (entry) => _AuditEntry(
              title: entry.action,
              body: entry.entityType,
              createdAt: entry.createdAt ?? wibNow(),
            ),
          ),
        );
      }
      // Sesi video mendatang + sesi yang SEDANG BERJALAN (untuk "Sesi
      // berjalan") + ringkasan Crisis Incident Log (satu permintaan
      // masing-masing).
      final upcomingSessions = await safely(() => apiClient.listCareSessions(
          accessToken: accessToken, scope: 'upcoming'));
      // `scope=ongoing` mengembalikan sesi scheduled ATAU completed yang masih
      // di dalam jendela waktu (profesional sudah menekan "Hadir" -> completed,
      // tetapi sesi tetap "berjalan" sampai jendela habis). Tetap disaring lagi
      // di klien lewat jendela waktu murni (isCareSessionOngoing).
      final todaySessions = await safely(() => apiClient.listCareSessions(
          accessToken: accessToken, scope: 'ongoing'));
      final crisisLog = await safely(() =>
          apiClient.getCrisisIncidentLog(accessToken: accessToken, limit: 1));
      if (!mounted) return;
      setState(() {
        _links = links;
        _screeningsByPatient = screeningsByPatient;
        _serverAuditEntries = serverAuditEntries;
        _professionalNotes
          ..clear()
          ..addAll(notesByPatient);
        _upcomingSessions = upcomingSessions ?? const <BackendCareSession>[];
        _todaySessions = todaySessions ?? const <BackendCareSession>[];
        _crisisLogCount = crisisLog?.unresolved ?? 0;
        _screeningNotShared
          ..clear()
          ..addAll(screeningNotShared);
        _selectedPatientId ??= links.isEmpty ? null : links.first.patientId;
        _isLoadingOnlineData = false;
        _lastSyncTime = wibNow();
      });
    } on MalvaApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _onlineError = friendlyServerMessage(error.message);
        _isLoadingOnlineData = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        // friendlyErrorMessage menerjemahkan error mentah ke teks Indonesia
        // yang ramah (tidak pernah menampilkan kalimat Inggris teknis).
        _onlineError = friendlyErrorMessage(error);
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
          screeningNotShared: _screeningNotShared.contains(link.patientId),
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

  void _exportData() async {
    final exportPatients = _patientsForDashboard();
    final selected = _selectedPatient(exportPatients);

    final StringBuffer csv = StringBuffer();
    csv.writeln('Malva Professional Dashboard Export');
    csv.writeln('Date: ${wibNow()}');
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
        'Screening terakhir: ${formatScreeningDate(latest.createdAt)}',
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
        'Screening Date,${formatScreeningDate(latest.createdAt)}',
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
                      if (patient.screeningNotShared)
                        Text(
                          'Pasien belum membagikan data skrining',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey,
                                    fontWeight: FontWeight.w600,
                                  ),
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
                                '${entry.body} - ${formatScreeningDate(entry.createdAt)}'),
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
        if (session != null) ...[
          const SizedBox(height: 10),
          // Akun Google & Meet: hubungkan Gmail, aktifkan Google Meet.
          ActionTile(
            icon: Icons.alternate_email_rounded,
            title: 'Akun Google & Meet',
            subtitle: 'Hubungkan Gmail, aktifkan Google Meet',
            color: MalvaColors.seed,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => GoogleAccountScreen(
                  session: session!,
                  apiClient: apiClient ?? ref.read(apiClientProvider),
                  showMeet: true,
                ),
              ),
            ).then((_) {
              // Segarkan kartu identitas (email) setelah kembali.
              _handleProfileSaved();
            }),
          ),
        ],
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

class _ProfessionalPatient {
  const _ProfessionalPatient({
    required this.patientId,
    required this.displayName,
    required this.sourceLabel,
    required this.status,
    required this.linkedAt,
    required this.screenings,
    this.screeningNotShared = false,
  });

  final String patientId;
  final String displayName;
  final String sourceLabel;
  final String status;
  final DateTime? linkedAt;
  final List<_ScreeningView> screenings;

  /// True bila pasien ini membalas 403 (screening belum dibagikan). Dipakai
  /// untuk menampilkan penanda kecil per-pasien, bukan banner global.
  final bool screeningNotShared;

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
      createdAt: toWibOrNull(session.createdAt),
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

/// Tanggal screening untuk TAMPILAN **dan** EKSPOR (text/CSV).
///
/// `createdAt` dari server berbentuk UTC; laporan klinis harus mengikuti
/// kalender LOKAL tenaga medis (WIB), jadi selalu `` lebih dulu.
/// Satu implementasi dipakai bersama agar angka di layar dan di berkas ekspor
/// tidak pernah berbeda tanggal.
String formatScreeningDate(DateTime? value) {
  if (value == null) return 'Belum ada tanggal';
  return formatWibDate(value);
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
    final diff = wibNow().difference(lastSyncTime!);
    if (diff.inMinutes < 5) return MalvaColors.mint;
    if (diff.inMinutes < 30) return MalvaColors.amber;
    return MalvaColors.danger;
  }

  String _formatTimeAgo(DateTime time) {
    final diff = wibNow().difference(time);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

/// Tombol "Create Meeting" di dashboard profesional. Membuat Google Meet instan
/// via backend API dan menampilkan link yang bisa dibagikan ke pasien untuk
/// video call real-time.
class _CreateMeetingButton extends ConsumerStatefulWidget {
  const _CreateMeetingButton({this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<_CreateMeetingButton> createState() =>
      _CreateMeetingButtonState();
}

class _CreateMeetingButtonState extends ConsumerState<_CreateMeetingButton> {
  String? _meetingUrl;
  bool _isLoading = false;

  /// Buat Google Meet via backend API (POST /v1/meet/quick).
  Future<void> _createMeeting() async {
    if (_isLoading) return;
    final MalvaApiClient api = widget.apiClient ?? ref.read(apiClientProvider);
    final token = widget.session?.accessToken;
    if (token == null || token.isEmpty) {
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
      // `meet_belum_aktif` = Google Calendar profesional belum aktif. Beri
      // jalan keluar langsung: tombol "Hubungkan" ke layar Akun Google.
      if (e.code == 'meet_belum_aktif') {
        _showMeetNotActiveSnack(e.message);
        return;
      }
      // Pesan error lain dari backend (mis. Google belum dihubungkan).
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

  /// SnackBar dengan aksi "Hubungkan" menuju layar Akun Google (bagian Meet).
  /// Layar itu SUDAH ada (`GoogleAccountScreen(showMeet: true)`) — tidak perlu
  /// layar baru.
  void _showMeetNotActiveSnack(String message) {
    final session = widget.session;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 8),
        action: session == null
            ? null
            : SnackBarAction(
                label: 'Hubungkan',
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GoogleAccountScreen(
                        session: session,
                        apiClient:
                            widget.apiClient ?? ref.read(apiClientProvider),
                        showMeet: true,
                      ),
                    ),
                  );
                },
              ),
      ),
    );
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

/// Section "Video call mendatang" untuk tab Dashboard: daftar sesi video
/// terjadwal (nama pasien, waktu, aksi gabung/salin tautan) atau empty state
/// ringkas bila tidak ada.
class _UpcomingVideoCallSection extends StatelessWidget {
  const _UpcomingVideoCallSection({
    required this.sessions,
    required this.isLoading,
  });

  final List<BackendCareSession> sessions;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (sessions.isEmpty) {
      return const SoftCard(
        bordered: true,
        child: Row(
          children: [
            Icon(Icons.videocam_off_rounded, color: Colors.black38),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Belum ada video call terjadwal.',
                style: TextStyle(
                    color: Colors.black54, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final s in sessions.take(5)) ...[
          SoftCard(
            bordered: true,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                InitialAvatar(
                  name: s.patientName.isEmpty ? 'Pasien' : s.patientName,
                  radius: 18,
                  color: MalvaColors.seed,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.patientName.isEmpty ? 'Pasien' : s.patientName,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        _whenLabel(s.scheduledAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (s.meetingUrl.isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => _join(context, s.meetingUrl),
                    icon: const Icon(Icons.videocam_rounded, size: 18),
                    label: const Text('Gabung'),
                    style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                  )
                else
                  const Text('Link menyusul',
                      style: TextStyle(fontSize: 11, color: Colors.black45)),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  String _whenLabel(String? raw) {
    final dt = parseWibStored(raw);
    if (dt == null) return '';
    return formatWibDateTimeShort(dt);
  }

  Future<void> _join(BuildContext context, String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

/// Tombol Outlined ringkas untuk dipakai di dalam `Row` (theme global memakai
/// minimumSize tak-hingga sehingga tanpa style ini tombol melahap seluruh lebar).
final ButtonStyle _compactOutlinedButtonStyle = OutlinedButton.styleFrom(
  minimumSize: Size.zero,
  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
);

/// Kartu "satu pintu" generik untuk dashboard profesional: satu tombol besar
/// yang membuka layar lain. Meniru pola visual kartu Crisis Incident Log
/// (ikon berwarna + judul + subjudul + chevron).
class _PortalDoorCard extends StatelessWidget {
  const _PortalDoorCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      bordered: true,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

/// Section "Sesi berjalan" untuk tab Dashboard: sesi (video/chat) yang jendela
/// waktunya sedang aktif sekarang. Bila tidak ada, tampil empty state ringkas.
class _OngoingSessionsSection extends StatelessWidget {
  const _OngoingSessionsSection({
    required this.sessions,
    required this.isLoading,
  });

  final List<BackendCareSession> sessions;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (sessions.isEmpty) {
      return const SoftCard(
        bordered: true,
        child: Row(
          children: [
            Icon(Icons.play_circle_outline_rounded, color: Colors.black38),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tidak ada sesi berjalan saat ini.',
                style: TextStyle(
                    color: Colors.black54, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final s in sessions) ...[
          _OngoingSessionCard(session: s),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _OngoingSessionCard extends StatelessWidget {
  const _OngoingSessionCard({required this.session});

  final BackendCareSession session;

  @override
  Widget build(BuildContext context) {
    final isVideo = session.sessionType == 'video';
    final patientName =
        session.patientName.isEmpty ? 'Pasien' : session.patientName;
    final timeRange = _timeRangeLabel(session);
    final badgeColor = isVideo ? MalvaColors.seed : MalvaColors.mint;
    return SoftCard(
      bordered: true,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              InitialAvatar(
                name: patientName,
                radius: 18,
                color: MalvaColors.seed,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(patientName,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text(
                      timeRange,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: isVideo ? 'Video' : 'Chat',
                color: badgeColor,
                icon: isVideo
                    ? Icons.videocam_rounded
                    : Icons.chat_bubble_rounded,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const StatusPill(
                label: 'Berlangsung',
                color: MalvaColors.mint,
                icon: Icons.sensors_rounded,
              ),
              const Spacer(),
              if (isVideo) ...[
                if (session.meetingUrl.trim().isNotEmpty)
                  FilledButton.icon(
                    onPressed: () => _joinVideo(context),
                    icon: const Icon(Icons.videocam_rounded, size: 18),
                    label: const Text('Gabung'),
                    style: compactFilledButtonStyle,
                  ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _openChat(context, patientName),
                  icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                  label: const Text('Chat'),
                  style: _compactOutlinedButtonStyle,
                ),
              ] else
                FilledButton.icon(
                  onPressed: () => _openChat(context, patientName),
                  icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                  label: const Text('Buka chat'),
                  style: compactFilledButtonStyle,
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Label rentang waktu `HH:mm–HH:mm WIB` dari jadwal + durasi sesi.
  String _timeRangeLabel(BackendCareSession s) {
    final start = parseWibStored(s.scheduledAt);
    if (start == null) return '';
    final end = start.add(Duration(minutes: s.durationMinutes));
    return '${formatWibBubbleTime(start)}–${formatWibBubbleTime(end)} WIB';
  }

  Future<void> _joinVideo(BuildContext context) async {
    final result = await openMeetLink(session.meetingUrl);
    if (result == MeetLaunchResult.failed) {
      await copyMeetLink(session.meetingUrl);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Tautan Meet disalin. Tempel di aplikasi Meet untuk '
              'bergabung.'),
        ),
      );
    }
  }

  void _openChat(BuildContext context, String patientName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUserName: patientName,
          otherUserId: session.patientId,
        ),
      ),
    );
  }
}
