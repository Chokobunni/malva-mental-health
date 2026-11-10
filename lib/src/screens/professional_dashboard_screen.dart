import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../professional_role.dart';
import '../providers/providers.dart';
import '../services/care_session_time.dart';
import '../services/care_session_refresh.dart';
import '../services/server_clock.dart';
import '../widgets/session_attendance_actions.dart';
import '../services/dashboard_sync_service.dart';
import '../services/malva_api_client.dart';
import '../services/meeting_launcher.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';
import '../widgets/meet_join_button.dart';
import '../widgets/friendly_error.dart';
import '../widgets/professional_avatar.dart';
import '../widgets/professional_availability_summary.dart';
import 'booking/credential_screens.dart';
import 'chat_screen.dart';
import 'google_account_screen.dart';
import 'messages_list_screen.dart';
import 'notifications_screen.dart';
import 'portal/e_prescription_screen.dart';
import 'portal/earnings_screen.dart';
import 'portal/shared_patient_data_screen.dart';
import 'pro_patient_detail_screen.dart';
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
    extends ConsumerState<ProfessionalDashboardScreen>
    with WidgetsBindingObserver {
  late final CareSessionRefresh _sessionRefresh;

  /// Pasien yang menolak/tidak membagikan data screening (403 access_denied
  /// per-pasien). Dipakai untuk menampilkan penanda kecil di kartu pasien,
  /// BUKAN banner global — satu pasien tanpa consent tidak boleh mematikan
  /// seluruh dashboard.
  final Set<String> _screeningNotShared = {};

  List<BackendPatientProfessionalLink> _links = const [];
  Map<String, List<BackendScreeningSession>> _screeningsByPatient = const {};
  List<BackendCareSession> _upcomingSessions = const [];
  List<BackendCareSession> _todaySessions = const [];
  String _searchQuery = '';
  int _tabIndex = 0;
  bool _showAllUpcomingVideos = false;
  bool _showAllUpcomingChats = false;
  bool _isLoadingOnlineData = false;
  String? _onlineError;

  SyncStatus _syncStatus = SyncStatus.idle;
  DateTime? _lastSyncTime;
  late final DashboardSyncService _syncService;
  StreamSubscription<DashboardSyncEvent>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionRefresh = CareSessionRefresh(() {
      if (!mounted) return;
      setState(() {});
      unawaited(_loadOnlineProfessionalData());
    }, poll: false);
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
    _sessionRefresh.dispose();
    WidgetsBinding.instance.removeObserver(this);
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      unawaited(_loadOnlineProfessionalData());
    }
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
    final header = _ProfessionalHeader(
      displayName: widget.session?.displayName ??
          ref.watch(currentSessionProvider)?.displayName ??
          '',
      online: _lastSyncTime != null && _onlineError == null,
      syncing: _syncStatus == SyncStatus.syncing,
      onRefresh: _manualRefresh,
      onProfile: () => setState(() => _tabIndex = 4),
      onNotifications: () => Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => NotificationsScreen(
                  session: widget.session, apiClient: widget.apiClient))),
    );
    return Theme(
        data: Theme.of(context).copyWith(
            cardTheme: Theme.of(context)
                .cardTheme
                .copyWith(elevation: 0, color: Colors.white),
            navigationBarTheme: NavigationBarThemeData(
              height: 64,
              backgroundColor: Colors.white,
              indicatorColor: const Color(0xFFF3E6F7),
              iconTheme: WidgetStateProperty.resolveWith((states) =>
                  IconThemeData(
                      size: 20,
                      color: states.contains(WidgetState.selected)
                          ? _dashboardPurple
                          : const Color(0xFF9AA7B1))),
              labelTextStyle: WidgetStateProperty.resolveWith((states) =>
                  TextStyle(
                      fontSize: 11,
                      fontWeight:
                          states.contains(WidgetState.selected)
                              ? FontWeight.w700
                              : FontWeight.w500,
                      color: states.contains(WidgetState.selected)
                          ? _dashboardPurple
                          : const Color(0xFF9AA7B1))),
            )),
        child: Scaffold(
          backgroundColor: const Color(0xFFF9F5FC),
          body: Column(
            children: [
              if (_tabIndex != 0) header,
              Expanded(
                child: _tabIndex == 3
                    ? MessagesListScreen(
                        key: ObjectKey(widget.session),
                        session: widget.session,
                        apiClient: widget.apiClient,
                      )
                    : _tabIndex == 1
                        ? ProScheduleScreen(
                            session: widget.session,
                            apiClient: widget.apiClient,
                            header: _CreateMeetingButton(
                              session: widget.session,
                              apiClient: widget.apiClient,
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadOnlineProfessionalData,
                            child: ListView(
                              padding: EdgeInsets.zero,
                              children: [
                                if (_tabIndex == 0) header,
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 14, 16, 40),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      // Banner error ringkas (hanya bila pemuatan gagal).
                                      // Bukan "section" konten — sekadar pemberitahuan status
                                      // agar kegagalan server tidak senyap, dengan pesan
                                      // Indonesia yang ramah.
                                      if (_tabIndex == 0 &&
                                          _onlineError != null)
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 14),
                                          child: SoftCard(
                                            bordered: false,
                                            color: MalvaColors.danger
                                                .withValues(alpha: 0.08),
                                            child: Row(
                                              children: [
                                                const Icon(
                                                    Icons.cloud_off_rounded,
                                                    color: MalvaColors.danger),
                                                const SizedBox(width: 10),
                                                Expanded(
                                                    child: Text(_onlineError!)),
                                                TextButton(
                                                  onPressed:
                                                      _loadOnlineProfessionalData,
                                                  child:
                                                      const Text('Coba lagi'),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      // ---- TAB 0 §0: Sesi berjalan (video & chat) ----
                                      if (_tabIndex == 0)
                                        const _DashboardSectionLabel(
                                            'Sesi berjalan',
                                            icon: Icons.play_arrow_rounded),
                                      if (_tabIndex == 0)
                                        _OngoingSessionsSection(
                                          onChanged:
                                              _loadOnlineProfessionalData,
                                          sessions: _ongoingSessions,
                                          isLoading: _isLoadingOnlineData,
                                        ),
                                      if (_tabIndex == 0)
                                        const SizedBox(height: 14),
                                      // ---- TAB 0 §1: Video call mendatang ----
                                      if (_tabIndex ==
                                          0)
                                        _DashboardSectionLabel(
                                            'Video call mendatang',
                                            icon: Icons.videocam_rounded,
                                            action: _upcomingVideoSessions
                                                        .length >
                                                    1
                                                ? IconButton(
                                                    tooltip: _showAllUpcomingVideos
                                                        ? 'Tampilkan lebih sedikit sesi video'
                                                        : 'Tampilkan semua sesi video',
                                                    onPressed: () => setState(() =>
                                                        _showAllUpcomingVideos =
                                                            !_showAllUpcomingVideos),
                                                    icon: Icon(_showAllUpcomingVideos
                                                        ? Icons
                                                            .expand_less_rounded
                                                        : Icons
                                                            .expand_more_rounded))
                                                : const Icon(
                                                    Icons.expand_more_rounded,
                                                    color: Color(0xFF7F8993),
                                                    size: 18)),
                                      if (_tabIndex == 0)
                                        _UpcomingSessionsSection(
                                          sessions: _showAllUpcomingVideos
                                              ? _upcomingVideoSessions
                                              : _upcomingVideoSessions
                                                  .take(1)
                                                  .toList(),
                                          video: true,
                                          accessToken:
                                              widget.session?.accessToken ?? '',
                                          apiClient: widget.apiClient,
                                          onChanged:
                                              _loadOnlineProfessionalData,
                                          isLoading: _isLoadingOnlineData,
                                        ),
                                      if (_tabIndex == 0)
                                        const SizedBox(height: 14),
                                      if (_tabIndex == 0)
                                        _DashboardSectionLabel(
                                            'Sesi chat mendatang',
                                            icon: Icons.chat_bubble_rounded,
                                            action: _upcomingChatSessions
                                                        .length >
                                                    1
                                                ? IconButton(
                                                    tooltip: _showAllUpcomingChats
                                                        ? 'Tampilkan lebih sedikit sesi chat'
                                                        : 'Tampilkan semua sesi chat',
                                                    onPressed: () => setState(() =>
                                                        _showAllUpcomingChats =
                                                            !_showAllUpcomingChats),
                                                    icon: Icon(_showAllUpcomingChats
                                                        ? Icons
                                                            .expand_less_rounded
                                                        : Icons
                                                            .expand_more_rounded))
                                                : const Icon(
                                                    Icons.expand_more_rounded,
                                                    color: Color(0xFF7F8993),
                                                    size: 18)),
                                      if (_tabIndex == 0)
                                        _UpcomingSessionsSection(
                                          sessions: _showAllUpcomingChats
                                              ? _upcomingChatSessions
                                              : _upcomingChatSessions
                                                  .take(1)
                                                  .toList(),
                                          video: false,
                                          accessToken:
                                              widget.session?.accessToken ?? '',
                                          apiClient: widget.apiClient,
                                          onChanged:
                                              _loadOnlineProfessionalData,
                                          isLoading: _isLoadingOnlineData,
                                        ),
                                      if (_tabIndex == 0)
                                        const SizedBox(height: 14),
                                      // ---- TAB 2: PASIEN ----
                                      if (_tabIndex == 2)
                                        const SectionLabel(
                                            'Cari & filter pasien',
                                            icon: Icons.search_rounded),
                                      if (_tabIndex == 2)
                                        _PatientSearch(
                                          query: _searchQuery,
                                          onChanged: (value) => setState(
                                              () => _searchQuery = value),
                                        ),
                                      if (_tabIndex == 2)
                                        const SizedBox(height: 14),
                                      // Shared records are available with the patient list.
                                      if (_tabIndex == 2) ...[
                                        const SizedBox(height: 22),
                                        const SectionLabel(
                                            'Data Pasien Dibagikan',
                                            icon: Icons.folder_shared_rounded),
                                        _PortalDoorCard(
                                          icon: Icons.folder_shared_rounded,
                                          color: MalvaColors.mint,
                                          title: 'Data pasien dibagikan',
                                          subtitle:
                                              'Mood, diary, obat, health record, goals, '
                                              'terapi • $_connectedPatientCount pasien',
                                          onTap: () => Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  SharedPatientDataScreen(
                                                session: widget.session,
                                                apiClient: widget.apiClient,
                                              ),
                                            ),
                                          ).then((_) =>
                                              _loadOnlineProfessionalData()),
                                        ),
                                      ],
                                      if (_tabIndex == 0)
                                        _ProfessionalToolsSection(
                                            key: ValueKey(
                                                widget.session?.backendUserId ??
                                                    widget.session?.identifier),
                                            session: widget.session,
                                            apiClient: widget.apiClient,
                                            refreshToken: _lastSyncTime),
                                      if (_tabIndex == 2)
                                        // Teks label dipertahankan persis "Pasien terhubung"
                                        // (dipakai test widget). Jumlah pasien dipindah ke
                                        // `action` supaya tidak mengubah string label.
                                        SectionLabel(
                                          'Pasien terhubung',
                                          icon: Icons.people_alt_rounded,
                                          action:
                                              Text('${patients.length} pasien'),
                                        ),
                                      if (_tabIndex == 2)
                                        _ConnectedPatientList(
                                          patients: _filterPatients(patients),
                                          onOpen: (patient) {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) =>
                                                    ProPatientDetailScreen(
                                                  patientId: patient.patientId,
                                                  patientName:
                                                      patient.displayName,
                                                  session: widget.session,
                                                  apiClient: widget.apiClient,
                                                ),
                                              ),
                                            ).then((_) =>
                                                _loadOnlineProfessionalData());
                                          },
                                        ),
                                      if (_tabIndex == 2 && patients.isEmpty)
                                        const EmptyState(
                                          icon: Icons.people_outline_rounded,
                                          title: 'Belum ada pasien terhubung',
                                          subtitle:
                                              'Pasien terhubung setelah membeli paket atau booking sesi denganmu.',
                                        ),
                                      // More follows Messages in the navigation bar.
                                      if (_tabIndex == 4) ...[
                                        _ProfessionalPortalSection(
                                          session: widget.session,
                                          apiClient: widget.apiClient,
                                          onRefresh:
                                              _loadOnlineProfessionalData,
                                        ),
                                        const SizedBox(height: 22),
                                        _RelationshipManagementSection(
                                          patients: patients,
                                          professionalCode:
                                              widget.session?.identifier,
                                          onRefresh:
                                              _loadOnlineProfessionalData,
                                        ),
                                        const SizedBox(height: 16),
                                        OutlinedButton.icon(
                                          onPressed: widget.onLogout,
                                          icon:
                                              const Icon(Icons.logout_rounded),
                                          label: const Text('Keluar'),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
              ),
            ],
          ),
          bottomNavigationBar: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.1,
            child: NavigationBar(
              selectedIndex: _tabIndex,
              onDestinationSelected: (value) =>
                  setState(() => _tabIndex = value),
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
                    icon: Icon(Icons.chat_bubble_outline_rounded),
                    selectedIcon: Icon(Icons.chat_bubble_rounded),
                    label: 'Messages'),
                NavigationDestination(
                    icon: Icon(Icons.grid_view_outlined),
                    selectedIcon: Icon(Icons.grid_view_rounded),
                    label: 'Lainnya'),
              ],
            ),
          ),
        ));
  }

  /// Sesi terjadwal mendatang, urut terdekat dulu.
  List<BackendCareSession> get _upcomingVideoSessions =>
      _upcomingSessionsFor('video');
  List<BackendCareSession> get _upcomingChatSessions =>
      _upcomingSessionsFor('chat');

  List<BackendCareSession> _upcomingSessionsFor(String type) {
    final list = _upcomingSessions
        .where((s) =>
            s.sessionType == type &&
            s.status == 'scheduled' &&
            !s.isAfterJoinWindow)
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
    final now = ServerClock.now();
    final list = _todaySessions.where((s) {
      final at = parseWibStored(s.scheduledAt);
      if (at == null) return false;
      return s.isScheduled && isCareSessionOngoing(now, at, s.durationMinutes);
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

        return (link, await loadScreenings());
      }).toList();
      final patientResults = await Future.wait(patientFutures);
      for (final (link, screenings) in patientResults) {
        screeningsByPatient[link.patientId] = screenings;
      }
      // Sesi video mendatang + sesi yang SEDANG BERJALAN (untuk "Sesi
      // berjalan").
      final upcomingSessions = await safely(() => apiClient.listCareSessions(
          accessToken: accessToken, scope: 'upcoming'));
      // `scope=ongoing` hanya mengembalikan sesi scheduled dalam jendela waktu.
      // Klien memeriksa ulang batas waktu sebelum menampilkan aksi.
      final todaySessions = await safely(() => apiClient.listCareSessions(
          accessToken: accessToken, scope: 'ongoing'));
      if (!mounted) return;
      setState(() {
        _links = links;
        _screeningsByPatient = screeningsByPatient;
        _upcomingSessions = upcomingSessions ?? const <BackendCareSession>[];
        _todaySessions = todaySessions ?? const <BackendCareSession>[];
        _screeningNotShared
          ..clear()
          ..addAll(screeningNotShared);
        _isLoadingOnlineData = false;
        _lastSyncTime = wibNow();
      });
      _sessionRefresh.update([..._upcomingSessions, ..._todaySessions]);
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
            bordered: false,
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
                              : '${professionalRoleLabel(specialization)} ($specialization)',
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

const _dashboardPurple = Color(0xFF9950AE);

class _ProfessionalHeader extends StatelessWidget {
  const _ProfessionalHeader({
    required this.displayName,
    required this.online,
    required this.syncing,
    required this.onRefresh,
    required this.onProfile,
    required this.onNotifications,
  });
  final String displayName;
  final bool online;
  final bool syncing;
  final VoidCallback onRefresh;
  final VoidCallback onProfile;
  final VoidCallback onNotifications;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
              colors: [Color(0xFF54206F), Color(0xFF8A3AA2), Color(0xFFC97BCC)],
              stops: [0, .45, 1],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter),
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(32)),
          boxShadow: [
            BoxShadow(
                color: Color(0x24562470), blurRadius: 18, offset: Offset(0, 8))
          ],
        ),
        child: SafeArea(
            bottom: false,
            child: Padding(
                padding: const EdgeInsets.fromLTRB(21, 8, 16, 26),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Image.asset('assets/checkin/flower-white.png',
                            width: 26, height: 30),
                        const SizedBox(width: 16),
                        Flexible(
                            child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                        color:
                                            Colors.white.withValues(alpha: .16),
                                        borderRadius: BorderRadius.circular(24),
                                        border: Border.all(
                                            color: Colors.white
                                                .withValues(alpha: .2))),
                                    child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.circle,
                                              size: 8,
                                              color: online
                                                  ? MalvaColors.mint
                                                  : const Color(0xFFCFBED6)),
                                          const SizedBox(width: 6),
                                          Text(online ? 'Online' : 'Offline',
                                              style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12)),
                                        ])))),
                        const Spacer(),
                        _headerAction(
                            'Refresh manual',
                            onRefresh,
                            syncing
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.refresh_rounded, size: 19)),
                        const SizedBox(width: 8),
                        _headerAction('Notifikasi', onNotifications,
                            const Icon(Icons.notifications_outlined, size: 19)),
                        const SizedBox(width: 10),
                        Tooltip(
                            message: 'Profil Profesional',
                            child: InkWell(
                                onTap: onProfile,
                                borderRadius: BorderRadius.circular(24),
                                child: Container(
                                    width: 42,
                                    height: 42,
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                            color: Colors.white
                                                .withValues(alpha: .6),
                                            width: 2)),
                                    child: Stack(children: [
                                      Center(
                                          child: Text(_initials(displayName),
                                              style: const TextStyle(
                                                  fontSize: 15,
                                                  color: Colors.white,
                                                  fontWeight:
                                                      FontWeight.w600))),
                                      if (online)
                                        const Positioned(
                                            right: 0,
                                            bottom: 0,
                                            child: Icon(Icons.circle,
                                                color: MalvaColors.mint,
                                                size: 8)),
                                    ]))))
                      ]),
                      const SizedBox(height: 24),
                      const Text('Professional',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              height: 1.2,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 6),
                      Text('Prioritas pasien, screening, sesi, dan paket',
                          style: TextStyle(
                              color: Colors.white.withValues(alpha: .72),
                              fontSize: 13)),
                    ]))),
      );

  Widget _headerAction(String tooltip, VoidCallback onTap, Widget icon) =>
      IconButton.filledTonal(
          tooltip: tooltip,
          onPressed: onTap,
          style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: .13),
              foregroundColor: Colors.white,
              minimumSize: const Size(34, 34),
              padding: const EdgeInsets.all(7),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          icon: icon);

  String _initials(String name) {
    final parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return parts.take(2).map((p) => p[0]).join().toUpperCase();
  }
}

class _DashboardSectionLabel extends StatelessWidget {
  const _DashboardSectionLabel(this.text, {required this.icon, this.action});
  final String text;
  final IconData icon;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.only(bottom: 12, top: 8),
      child: Row(children: [
        Container(
            width: 6,
            height: 17,
            decoration: BoxDecoration(
                color: _dashboardPurple,
                borderRadius: BorderRadius.circular(8))),
        const SizedBox(width: 8),
        Icon(icon, color: _dashboardPurple, size: 16),
        const SizedBox(width: 8),
        Expanded(
            child: Text(text,
                style: const TextStyle(
                    color: _dashboardPurple,
                    fontSize: 15,
                    height: 1.2,
                    fontWeight: FontWeight.w700))),
        if (action != null) action!,
      ]));
}

class _DashboardCard extends StatelessWidget {
  const _DashboardCard(
      {required this.child, this.padding = const EdgeInsets.all(17)});
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0D9B52B6), blurRadius: 24, offset: Offset(0, 8))
          ]),
      child: Padding(padding: padding, child: child));
}

class _ProfessionalToolsSection extends ConsumerStatefulWidget {
  const _ProfessionalToolsSection(
      {super.key, this.session, this.apiClient, this.refreshToken});
  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final Object? refreshToken;

  @override
  ConsumerState<_ProfessionalToolsSection> createState() =>
      _ProfessionalToolsSectionState();
}

class _ProfessionalToolsSectionState
    extends ConsumerState<_ProfessionalToolsSection> {
  Future<BackendProfessionalCredential?>? _credential;
  Future<List<Object>>? _availability;
  bool _availabilityExpanded = false;
  AuthSession? get session => widget.session;
  MalvaApiClient? get apiClient => widget.apiClient;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void didUpdateWidget(covariant _ProfessionalToolsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session?.accessToken != session?.accessToken ||
        oldWidget.apiClient != apiClient ||
        oldWidget.refreshToken != widget.refreshToken) {
      _reload();
    }
  }

  void _reload() {
    final MalvaApiClient client =
        widget.apiClient ?? ref.read(apiClientProvider);
    final token = session?.accessToken;
    _credential = token == null || token.isEmpty
        ? null
        : client.getMyCredentials(accessToken: token);
    _availability = token == null || token.isEmpty
        ? null
        : Future.wait<Object>([
            client.listMySchedules(accessToken: token),
            client.getPricing(accessToken: token),
            client.listTimeOff(accessToken: token),
          ]);
  }

  @override
  Widget build(BuildContext context) {
    Future<void> open(Widget page) async =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const _DashboardSectionLabel('Klinis',
          icon: Icons.medical_services_outlined),
      FutureBuilder<BackendProfessionalCredential?>(
        future: _credential,
        builder: (context, snapshot) =>
            isPsychiatristSpecialization(snapshot.data?.specialization ?? '')
                ? _PortalDoorCard(
                    icon: Icons.medication_rounded,
                    title: 'E-Prescription',
                    subtitle: 'Terbitkan resep dengan digital signature + QR',
                    color: MalvaColors.mint,
                    onTap: () => open(EPrescriptionScreen(
                        session: session, apiClient: apiClient)))
                : const SoftCard(
                    color: Colors.white,
                    child: Text('Resep obat hanya untuk Psikiater (Sp.KJ).')),
      ),
      const SizedBox(height: 14),
      const _DashboardSectionLabel('Operasional',
          icon: Icons.work_outline_rounded),
      _PortalDoorCard(
          icon: Icons.account_balance_wallet_rounded,
          title: 'Earnings',
          subtitle: 'Pendapatan, fee platform, dan payout',
          color: MalvaColors.amber,
          onTap: () =>
              open(EarningsScreen(session: session, apiClient: apiClient))),
      const SizedBox(height: 18),
      FutureBuilder<List<Object>>(
          future: _availability,
          builder: (context, snapshot) => _DashboardCard(
              padding: EdgeInsets.zero,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                        button: true,
                        expanded: _availabilityExpanded,
                        child: InkWell(
                            key: const ValueKey('home-availability'),
                            borderRadius: BorderRadius.circular(24),
                            onTap: () => setState(() =>
                                _availabilityExpanded = !_availabilityExpanded),
                            child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Row(children: [
                                  const CircleAvatar(
                                      backgroundColor: Color(0xFFF5EDFA),
                                      radius: 22,
                                      child: Icon(Icons.event_available_rounded,
                                          color: _dashboardPurple)),
                                  const SizedBox(width: 12),
                                  const Expanded(
                                      child: Text('Ketersediaan & harga',
                                          style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF252E38)))),
                                  CircleAvatar(
                                      radius: 14,
                                      backgroundColor: const Color(0xFFF7F8FA),
                                      child: Icon(
                                          _availabilityExpanded
                                              ? Icons.expand_less_rounded
                                              : Icons.expand_more_rounded,
                                          color: const Color(0xFF9AA7B1),
                                          size: 20)),
                                ])))),
                    if (_availabilityExpanded) ...[
                      const Divider(height: 1, color: Color(0xFFF2F2F5)),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(17, 16, 17, 17),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(children: [
                                const Expanded(
                                    child: Text('PENGATURAN',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 11.5,
                                            color: Color(0xFF9AA7B1)))),
                                TextButton.icon(
                                  onPressed: () async {
                                    await open(ProAvailabilityScreen(
                                        session: session,
                                        apiClient: apiClient));
                                    if (mounted) setState(_reload);
                                  },
                                  icon: const Icon(Icons.edit_calendar_rounded,
                                      size: 18),
                                  style: TextButton.styleFrom(
                                      foregroundColor: _dashboardPurple,
                                      minimumSize: Size.zero,
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 4, horizontal: 2),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap),
                                  label: const Text('Atur',
                                      style: TextStyle(
                                          fontFamily: 'Roboto', fontSize: 13)),
                                ),
                              ]),
                              const Divider(
                                  height: 18, color: Color(0xFFEDEFF2)),
                              Builder(
                                builder: (context) {
                                  if (_availability == null) {
                                    return const Text(
                                        'Login dulu untuk melihat ketersediaan.');
                                  }
                                  if (snapshot.connectionState !=
                                      ConnectionState.done) {
                                    return const Center(
                                        child: CircularProgressIndicator());
                                  }
                                  if (snapshot.hasError || !snapshot.hasData) {
                                    return Column(children: [
                                      const Text(
                                          'Ketersediaan & harga belum dapat dimuat.'),
                                      OutlinedButton.icon(
                                        onPressed: () => setState(_reload),
                                        icon: const Icon(Icons.refresh_rounded),
                                        label: const Text('Coba Lagi'),
                                      ),
                                    ]);
                                  }
                                  final data = snapshot.requireData;
                                  return ProfessionalAvailabilitySummary(
                                    schedules: data[0]
                                        as List<BackendProfessionalSchedule>,
                                    pricing:
                                        data[1] as BackendProfessionalPricing,
                                    timeOff: data[2] as List<BackendTimeOff>,
                                  );
                                },
                              ),
                            ]),
                      ),
                    ],
                  ]))),
    ]);
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
  String get latestLevel => latestScreening?.overallLevel ?? 'unavailable';
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
      overallLevel: session.crisisFlag
          ? 'crisis'
          : session.phq9.maxScore > 0 &&
                  session.phq9.score >= 0 &&
                  session.phq9.score <= session.phq9.maxScore &&
                  session.gad7.maxScore > 0 &&
                  session.gad7.score >= 0 &&
                  session.gad7.score <= session.gad7.maxScore
              ? session.overallLevel
              : 'unavailable',
      crisisFlag: session.crisisFlag,
      phq9Score: session.phq9.score,
      phq9MaxScore: session.phq9.maxScore,
      phq9Level: session.phq9.level,
      gad7Score: session.gad7.score,
      gad7MaxScore: session.gad7.maxScore,
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

String _riskLabel(String value) {
  return switch (value.toLowerCase()) {
    'unavailable' => 'Belum tersedia',
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
    'unavailable' => Colors.grey,
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
/// `createdAt` dari server memakai WIB; laporan klinis harus mengikuti
/// kalender LOKAL tenaga medis (WIB), jadi selalu `` lebih dulu.
/// Satu implementasi dipakai bersama agar angka di layar dan di berkas ekspor
/// tidak pernah berbeda tanggal.
String formatScreeningDate(DateTime? value) {
  if (value == null) return 'Belum ada tanggal';
  return formatWibDate(value);
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
      bordered: false,
      color: Colors.white,
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

/// Sesi mendatang dengan identitas, jadwal WIB, dan aksi sesuai jendela sesi.
class _UpcomingSessionsSection extends ConsumerStatefulWidget {
  const _UpcomingSessionsSection(
      {required this.sessions,
      required this.isLoading,
      required this.video,
      required this.accessToken,
      required this.onChanged,
      this.apiClient});
  final List<BackendCareSession> sessions;
  final bool isLoading;
  final bool video;
  final String accessToken;
  final Future<void> Function() onChanged;
  final MalvaApiClient? apiClient;
  @override
  ConsumerState<_UpcomingSessionsSection> createState() =>
      _UpcomingSessionsSectionState();
}

class _UpcomingSessionsSectionState
    extends ConsumerState<_UpcomingSessionsSection> {
  final _cancelling = <String>{};

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading) {
      return const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Center(child: CircularProgressIndicator()));
    }
    if (widget.sessions.isEmpty) {
      return _DashboardCard(
          child: Row(children: [
        Icon(
            widget.video
                ? Icons.videocam_off_rounded
                : Icons.chat_bubble_outline_rounded,
            color: const Color(0xFF98A4AD)),
        const SizedBox(width: 10),
        Expanded(
            child: Text(
                widget.video
                    ? 'Belum ada video call terjadwal.'
                    : 'Belum ada sesi chat mendatang.',
                style:
                    const TextStyle(color: Color(0xFF7D8993), fontSize: 13))),
      ]));
    }
    return Column(children: [
      for (final s in widget.sessions) ...[
        _DashboardCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Stack(children: [
              CircleAvatar(
                  radius: 25,
                  backgroundColor: const Color(0xFFF3E6F8),
                  child: Text(_initials(s.patientName),
                      style: const TextStyle(
                          color: _dashboardPurple,
                          fontSize: 18,
                          fontWeight: FontWeight.w700))),
              const Positioned(
                  right: 0,
                  bottom: 0,
                  child: Tooltip(
                      message: 'Status online belum diketahui',
                      child: DecoratedBox(
                          decoration: BoxDecoration(
                              color: Color(0xFFB7BEC5),
                              shape: BoxShape.circle,
                              border: Border.fromBorderSide(
                                  BorderSide(color: Colors.white, width: 2))),
                          child: SizedBox.square(dimension: 13)))),
            ]),
            const SizedBox(width: 14),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(s.patientName.isEmpty ? 'Pasien' : s.patientName,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF252E38))),
                  const SizedBox(height: 3),
                  Row(children: [
                    Icon(
                        s.isVideo
                            ? Icons.videocam_rounded
                            : Icons.forum_rounded,
                        size: 16,
                        color: _dashboardPurple),
                    const SizedBox(width: 5),
                    Expanded(
                        child: Text(
                            s.isVideo
                                ? 'Video Session, ${s.durationMinutes} menit'
                                : 'Chat • ${s.durationMinutes} menit',
                            style: const TextStyle(
                                fontSize: 13, color: Color(0xFF7D8993)))),
                  ]),
                ])),
          ]),
          const SizedBox(height: 14),
          Text(_whenLabel(s),
              style: const TextStyle(
                  fontSize: 13,
                  height: 1.2,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF303A45))),
          const SizedBox(height: 12),
          if (s.isVideo && (s.canJoinNow || s.meetingUrl.trim().isEmpty))
            MeetJoinButton(
                session: s,
                accessToken: widget.accessToken,
                expanded: true,
                onSessionChanged: (_) => unawaited(widget.onChanged()))
          else
            Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
                decoration: BoxDecoration(
                    color: const Color(0xFFF6EFFA),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0xFFF0E7F5))),
                child:
                    Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.schedule_rounded,
                      size: 16, color: _dashboardPurple),
                  const SizedBox(width: 7),
                  Flexible(
                      child: Text(_countdown(s),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 13,
                              height: 1.2,
                              color: _dashboardPurple,
                              fontWeight: FontWeight.w500))),
                ])),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: FilledButton.icon(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => ChatScreen(
                                otherUserId: s.patientId,
                                otherUserName: s.patientName))),
                    style: FilledButton.styleFrom(
                        backgroundColor: _dashboardPurple,
                        minimumSize: const Size.fromHeight(40),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        textStyle: const TextStyle(
                            fontSize: 14,
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w500),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13))),
                    icon: const Icon(Icons.chat_bubble_rounded, size: 15),
                    label: const Text('Chat'))),
            const SizedBox(width: 12),
            Expanded(
                child: OutlinedButton(
                    onPressed: _canCancel(s) && !_cancelling.contains(s.id)
                        ? () => _cancel(s)
                        : null,
                    style: OutlinedButton.styleFrom(
                        foregroundColor: _dashboardPurple,
                        minimumSize: const Size.fromHeight(40),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        side: const BorderSide(color: Color(0xFFE5E7EB)),
                        textStyle: const TextStyle(
                            fontSize: 14,
                            fontFamily: 'Roboto',
                            fontWeight: FontWeight.w500),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13))),
                    child: Text(_cancelling.contains(s.id)
                        ? 'Membatalkan...'
                        : 'Cancel'))),
          ]),
        ])),
        if (s != widget.sessions.last) const SizedBox(height: 12),
      ],
    ]);
  }

  bool _canCancel(BackendCareSession s) =>
      s.isScheduled &&
      s.scheduledDateTime != null &&
      ServerClock.now().isBefore(s.scheduledDateTime!);

  Future<void> _cancel(BackendCareSession s) async {
    if (!_canCancel(s) || _cancelling.contains(s.id)) return;
    final token = widget.accessToken;
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Batalkan sesi?'),
                content: const Text(
                    'Kredit sesi pasien otomatis kembali dan bisa dijadwalkan ulang.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Kembali')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: compactFilledButtonStyle,
                      child: const Text('Batalkan')),
                ]));
    if (!mounted ||
        confirmed != true ||
        widget.accessToken != token ||
        token.isEmpty ||
        !_canCancel(s)) return;
    setState(() => _cancelling.add(s.id));
    try {
      final MalvaApiClient api =
          widget.apiClient ?? ref.read(apiClientProvider);
      await api.updateCareSession(
          accessToken: token,
          sessionId: s.id,
          status: 'cancelled_by_professional');
      if (!mounted || widget.accessToken != token) return;
      await widget.onChanged();
    } on Object catch (error) {
      if (!mounted || widget.accessToken != token) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _cancelling.remove(s.id));
    }
  }

  String _initials(String name) => name
      .trim()
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .take(2)
      .map((s) => s[0])
      .join()
      .toUpperCase();

  String _countdown(BackendCareSession s) {
    final at = s.scheduledDateTime;
    if (at == null) return 'Jadwal belum tersedia';
    final diff = at.difference(ServerClock.now());
    if (diff <= Duration.zero) return 'Sesi berlangsung';
    final minutes = (diff.inSeconds / 60).ceil();
    final hours = minutes ~/ 60;
    return 'Mulai dalam ${hours > 0 ? '$hours jam ' : ''}${minutes % 60} mnt';
  }

  String _whenLabel(BackendCareSession s) {
    final at = s.scheduledDateTime;
    if (at == null) return 'Jadwal belum tersedia';
    if (!s.isVideo) return '${formatWibDateTime(at)} WIB';
    const days = [
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu',
      'Minggu'
    ];
    const months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember'
    ];
    return '${days[at.weekday - 1]}, ${at.day} ${months[at.month - 1]} ${at.year} • ${formatWibBubbleTime(at)}';
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
  Widget build(BuildContext context) => Material(
      type: MaterialType.transparency,
      child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: _DashboardCard(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
              child: Row(children: [
                Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: .09),
                        borderRadius: BorderRadius.circular(17)),
                    child: Icon(icon, color: color, size: 21)),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: Color(0xFF252E38))),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style: const TextStyle(
                              fontSize: 11, color: Color(0xFF9AA7B1))),
                    ])),
                const SizedBox(width: 4),
                const CircleAvatar(
                    radius: 14,
                    backgroundColor: Color(0xFFF7F8FA),
                    child: Icon(Icons.chevron_right_rounded,
                        size: 19, color: Color(0xFF9AA7B1))),
              ]))));
}

/// Section "Sesi berjalan" untuk tab Dashboard: sesi (video/chat) yang jendela
/// waktunya sedang aktif sekarang. Bila tidak ada, tampil empty state ringkas.
class _OngoingSessionsSection extends StatelessWidget {
  const _OngoingSessionsSection({
    required this.sessions,
    required this.isLoading,
    required this.onChanged,
  });

  final List<BackendCareSession> sessions;
  final bool isLoading;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (sessions.isEmpty) {
      return const _DashboardCard(
        padding: EdgeInsets.symmetric(horizontal: 17, vertical: 16),
        child: Row(
          children: [
            Icon(Icons.play_circle_outline_rounded,
                color: Color(0xFF9AA7B1), size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Tidak ada sesi berjalan saat ini.',
                style: TextStyle(
                    color: Color(0xFF7D8993),
                    fontWeight: FontWeight.w400,
                    fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    return Column(
      children: [
        for (final s in sessions) ...[
          _OngoingSessionCard(session: s, onChanged: onChanged),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _OngoingSessionCard extends StatelessWidget {
  const _OngoingSessionCard({required this.session, required this.onChanged});

  final BackendCareSession session;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final isVideo = session.sessionType == 'video';
    final patientName =
        session.patientName.isEmpty ? 'Pasien' : session.patientName;
    final timeRange = _timeRangeLabel(session);
    final badgeColor = isVideo ? MalvaColors.seed : MalvaColors.mint;
    return _DashboardCard(
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
          const SizedBox(height: 8),
          SessionAttendanceActions(
              session: session,
              role: UserRole.professional,
              onChanged: onChanged),
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
    if (!session.canJoinNow) return;
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
    if (!session.canJoinNow) return;
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
