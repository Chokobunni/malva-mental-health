import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../services/care_session_refresh.dart';
import '../widgets/session_attendance_actions.dart';
import '../services/medication_reminder_service.dart';
import '../theme.dart';
import '../widgets/crisis_hotline.dart';
import '../widgets/daily_checkin_flow.dart';
import '../widgets/malva_components.dart';
import '../widgets/meet_join_button.dart';
import '../widgets/friendly_error.dart';
import '../widgets/professional_avatar.dart';
import '../widgets/sync_status.dart';
import '../widgets/therapy_library.dart';
import 'booking/doctor_discovery_screen.dart';
import 'chat_screen.dart';
import 'diary_history_screen.dart';
import 'goals_screen.dart';
import 'history_log_screen.dart';
import 'mood_medication_checkin_screen.dart';
import 'notifications_screen.dart';
import 'record_screen.dart';

// ============================================================
// HOME — layout final:
//   [Sesi booking aktif]      (bila ada, Join/Cancel)
//   Daily Check-in interaktif (emoji -> obat -> tidur -> energi -> streak)
//   Self Care:                Goals & Habits / Diary History /
//                             Psychological Therapy / Health Record
//   Professional Care:        tombol Find Professionals
//                             Assessment / History Log
//   Mood Medication Check-in  (banner -> screen Mood+Medication)
// ============================================================

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.onOpenMood,
    required this.onOpenMedication,
    required this.onOpenDiary,
    required this.onOpenChat,
    required this.onOpenMore,
    required this.onOpenAssessment,
    this.medicationReminderService,
    this.session,
    this.apiClient,
  });

  final VoidCallback onOpenMood;
  final VoidCallback onOpenMedication;
  final VoidCallback onOpenDiary;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenMore;
  final VoidCallback onOpenAssessment;
  final MedicationReminderService? medicationReminderService;
  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  late final CareSessionRefresh _sessionRefresh;
  bool _isInitialLoading = true;
  List<BackendCareSession> _upcomingSessions = const [];
  bool _ongoingLoadFailed = false;
  bool _upcomingLoadFailed = false;
  int _sessionsRequest = 0;

  AuthSession? get _session =>
      widget.session ?? ref.read(currentSessionProvider);
  MalvaApiClient get _api => widget.apiClient ?? ref.read(apiClientProvider);

  /// Sesi scheduled dalam jendela waktu; konfirmasi hadir tidak menutup akses.
  List<BackendCareSession> _ongoingSessions = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionRefresh = CareSessionRefresh(() {
      if (!mounted) return;
      setState(() {});
      unawaited(_loadUpcomingSession());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadUpcomingSession());
      Future<void>.delayed(const Duration(milliseconds: 400)).then((_) {
        if (mounted) setState(() => _isInitialLoading = false);
      });
    });
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session?.accessToken != widget.session?.accessToken ||
        oldWidget.apiClient != widget.apiClient) {
      unawaited(_loadUpcomingSession());
    }
  }

  @override
  void dispose() {
    _sessionRefresh.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      unawaited(_loadUpcomingSession());
    }
  }

  Future<void> _refreshAll() async {
    await _loadUpcomingSession();
    // Segarkan riwayat check-in dan obat dari server saat pull-to-refresh.
    final notifier = ref.read(malvaStoreProvider.notifier);
    await Future.wait([
      notifier.loadCheckinHistory().catchError((_) {}),
      notifier.loadMedications().catchError((_) {}),
    ]);
  }

  Future<void> _loadUpcomingSession() async {
    final request = ++_sessionsRequest;
    final apiClient = _api;
    final rawToken = _session?.accessToken;
    final accessToken =
        (rawToken == null || rawToken.isEmpty) ? null : rawToken;
    if (accessToken == null) {
      if (mounted) {
        setState(() {
          _upcomingSessions = const [];
          _ongoingSessions = const [];
          _ongoingLoadFailed = false;
          _upcomingLoadFailed = false;
        });
      }
      return;
    }
    bool upcomingFailed = false;
    bool ongoingFailed = false;
    Future<List<BackendCareSession>> load(String scope) async {
      try {
        return await apiClient.listCareSessions(
            accessToken: accessToken, scope: scope);
      } on Object {
        if (scope == 'ongoing') {
          ongoingFailed = true;
        } else {
          upcomingFailed = true;
        }
        return [];
      }
    }

    final results = await Future.wait([load('upcoming'), load('ongoing')]);
    if (!mounted ||
        request != _sessionsRequest ||
        _session?.accessToken != accessToken) return;
    final upcoming = results[0]
      ..sort((a, b) => (a.scheduledAt ?? '').compareTo(b.scheduledAt ?? ''));
    final ongoing = results[1]
      ..sort((a, b) => (a.scheduledAt ?? '').compareTo(b.scheduledAt ?? ''));
    setState(() {
      _upcomingSessions = upcoming;
      _ongoingSessions = ongoing;
      _upcomingLoadFailed = upcomingFailed;
      _ongoingLoadFailed = ongoingFailed;
    });
    _sessionRefresh.update([...upcoming, ...ongoing]);
  }

  @override
  Widget build(BuildContext context) {
    // Foto/nama profesional bisa berubah kapan saja (event realtime
    // `professional.profile.updated`). Muat ulang data sesi yang menampilkan
    // identitas profesional tanpa perlu refresh manual (bug 28 Okt 2026:
    // foto profil baru tidak muncul di sisi pasien).
    ref.listen<int>(professionalProfileRevisionProvider, (previous, next) {
      unawaited(_loadUpcomingSession());
    });
    ref.listen<AuthSession?>(currentSessionProvider, (before, after) {
      if (widget.session == null && before?.accessToken != after?.accessToken) {
        unawaited(_loadUpcomingSession());
      }
    });
    final storeState = ref.watch(malvaStoreProvider);
    final auth = _session;
    final ongoingSessions =
        _ongoingSessions.where((s) => s.canJoinNow).toList();
    final ongoingIds = ongoingSessions.map((s) => s.id).toSet();
    final upcomingVideos = _upcomingSessions.where((s) =>
        s.isScheduled &&
        !s.isAfterJoinWindow &&
        s.isVideo &&
        !ongoingIds.contains(s.id));
    final upcomingChats = _upcomingSessions.where((s) =>
        s.isScheduled &&
        !s.isAfterJoinWindow &&
        !s.isVideo &&
        !ongoingIds.contains(s.id));
    // Nama sapaan diambil dari sesi login asli, fallback ke store.
    final displayName = (auth?.displayName.trim().isNotEmpty ?? false)
        ? auth!.displayName
        : storeState.patient.name;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            if (_isInitialLoading) const LinearProgressIndicator(),
            GradientHeader(
              title: 'Home',
              subtitle: 'Halo, $displayName',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _NotificationBell(
                    session: auth,
                    apiClient: _api,
                  ),
                  IconButton(
                    tooltip: 'Profil',
                    onPressed: widget.onOpenMore,
                    icon: const CircleAvatar(
                      backgroundColor: Colors.white,
                      child:
                          Icon(Icons.person_rounded, color: MalvaColors.seed),
                    ),
                  ),
                ],
              ),
            ),
            const CrisisHotlineBanner(),
            const OfflineBanner(),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Sesi berjalan',
                      icon: Icons.play_circle_rounded),
                  if (_ongoingLoadFailed)
                    const Text('Sesi berjalan belum dapat dimuat.')
                  else if (ongoingSessions.isEmpty)
                    const SoftCard(
                        child: Text('Tidak ada sesi berjalan saat ini.'))
                  else
                    for (final s in ongoingSessions)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _OngoingSessionCard(
                            session: s,
                            accessToken: auth?.accessToken ?? '',
                            onChat: () => _joinSession(context, s),
                            onChanged: _loadUpcomingSession,
                          )),
                  const SizedBox(height: 18),
                  const SectionLabel('Video call mendatang',
                      icon: Icons.videocam_rounded),
                  if (_upcomingLoadFailed)
                    const Text('Video call mendatang belum dapat dimuat.')
                  else if (upcomingVideos.isEmpty)
                    const SoftCard(
                        child: Text('Tidak ada video call mendatang.'))
                  else
                    for (final s in upcomingVideos)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _UpcomingSessionCard(
                            session: s,
                            accessToken: auth?.accessToken ?? '',
                            onJoin: () => _joinSession(context, s),
                            onCancel: () => _cancelSession(context, s),
                            onChanged: _loadUpcomingSession,
                          )),
                  if (_ongoingLoadFailed || _upcomingLoadFailed)
                    TextButton(
                        onPressed: _loadUpcomingSession,
                        child: const Text('Coba lagi')),
                  if (upcomingChats.isNotEmpty) ...[
                    const SizedBox(height: 18),
                    const SectionLabel('Chat mendatang',
                        icon: Icons.chat_bubble_rounded),
                    for (final s in upcomingChats)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _UpcomingSessionCard(
                            session: s,
                            accessToken: auth?.accessToken ?? '',
                            onJoin: () => _joinSession(context, s),
                            onCancel: () => _cancelSession(context, s),
                            onChanged: _loadUpcomingSession,
                          )),
                  ],
                  const SizedBox(height: 18),

                  // === 2. DAILY CHECK-IN interaktif ===
                  // emoji -> obat -> tidur -> energi -> popup streak
                  DailyCheckInFlow(
                    onSaved: () => setState(() {}),
                  ),
                  const SizedBox(height: 22),

                  // === 3. SELF CARE ===
                  const SectionLabel('Self Care', center: true),
                  _HomeSectionGrid(
                    items: [
                      _GridItem(
                        icon: Icons.flag_rounded,
                        label: 'Goals & Habits',
                        color: MalvaColors.seed,
                        onTap: () => _push(const GoalsScreen()),
                      ),
                      _GridItem(
                        icon: Icons.edit_note_rounded,
                        label: 'Diary History',
                        color: MalvaColors.orchid,
                        onTap: () => _push(DiaryHistoryScreen(
                          session: widget.session,
                          apiClient: widget.apiClient,
                        )),
                      ),
                      _GridItem(
                        icon: Icons.psychology_rounded,
                        label: 'Psychological Therapy',
                        color: MalvaColors.pink,
                        onTap: () => _push(const TherapyCatalogScreen()),
                      ),
                      _GridItem(
                        icon: Icons.folder_shared_rounded,
                        label: 'Health Record',
                        color: MalvaColors.mint,
                        onTap: () => _push(RecordScreen(
                          session: widget.session,
                          apiClient: widget.apiClient,
                        )),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // === 4. PROFESSIONAL CARE ===
                  const SectionLabel('Professional Care', center: true),
                  _FindProfessionalsButton(
                    onTap: () => _openDoctorDiscovery(context),
                  ),
                  const SizedBox(height: 12),
                  _HomeSectionGrid(
                    items: [
                      _GridItem(
                        icon: Icons.fact_check_rounded,
                        label: 'Assessment',
                        color: MalvaColors.seed,
                        onTap: widget.onOpenAssessment,
                      ),
                      _GridItem(
                        icon: Icons.timeline_rounded,
                        label: 'History Log',
                        color: MalvaColors.amber,
                        onTap: () => _push(HistoryLogScreen(
                          session: widget.session,
                          apiClient: widget.apiClient,
                        )),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // === 5. MOOD MEDICATION CHECK-IN ===
                  _MoodMedicationBanner(
                    onTap: () => _push(
                      MoodMedicationCheckinScreen(
                        session: widget.session,
                        apiClient: widget.apiClient,
                        medicationReminderService:
                            widget.medicationReminderService,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _push(Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  void _joinSession(BuildContext context, BackendCareSession session) {
    if (!session.canJoinNow) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUserName: session.professionalName.isEmpty
              ? 'Profesional'
              : session.professionalName,
          otherUserId: session.professionalId,
        ),
      ),
    );
  }

  Future<void> _cancelSession(
    BuildContext context,
    BackendCareSession session,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan sesi?'),
        content: const Text(
            'Pembatalan minimal 24 jam sebelum sesi. Kurang dari itu sesi hangus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: compactFilledButtonStyle.copyWith(
              backgroundColor: const WidgetStatePropertyAll(MalvaColors.danger),
            ),
            child: const Text('Batalkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final apiClient = _api;
    final token = _session?.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      await apiClient.updateCareSession(
        accessToken: token,
        sessionId: session.id,
        status: 'cancelled_by_patient',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesi dibatalkan.')),
      );
      await _loadUpcomingSession();
      setState(() {});
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }

  void _openDoctorDiscovery(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DoctorDiscoveryScreen(
          session: widget.session,
          apiClient: widget.apiClient,
        ),
      ),
    );
  }
}

// ============================================================
// WIDGET LOKAL
// ============================================================

/// Kartu sesi mendatang: nama profesional riil, tipe & durasi riil,
/// tanggal, tombol Join / Cancel.
class _UpcomingSessionCard extends StatelessWidget {
  const _UpcomingSessionCard({
    required this.session,
    required this.onJoin,
    required this.onCancel,
    required this.accessToken,
    required this.onChanged,
  });

  final BackendCareSession session;
  final VoidCallback onJoin;
  final VoidCallback onCancel;
  final String accessToken;
  final Future<void> Function() onChanged;

  static const _days = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu'
  ];
  static const _months = [
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

  @override
  Widget build(BuildContext context) {
    final isVideo = session.isVideo;
    final date = session.scheduledDateTime;
    final dateLabel = date != null
        ? '${_days[date.weekday - 1]}, ${date.day.toString().padLeft(2, '0')} '
            '${_months[date.month - 1]} ${date.year} • '
            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
        : '-';
    final name = session.professionalName.isEmpty
        ? 'Profesional'
        : session.professionalName;
    return SoftCard(
      bordered: true,
      color: MalvaColors.seed.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProfessionalAvatar(
                displayName: name,
                radius: 22,
                photoUrl: session.photoIntroUrl,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          isVideo
                              ? Icons.videocam_rounded
                              : Icons.chat_bubble_rounded,
                          size: 14,
                          color: MalvaColors.seed,
                        ),
                        const SizedBox(width: 4),
                        Flexible(
                            child: Text(
                          '${isVideo ? 'Video' : 'Chat'} Session, ${session.durationMinutes} menit',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.black54),
                        )),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            dateLabel,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (isVideo) ...[
            MeetJoinButton(
                session: session,
                accessToken: accessToken,
                expanded: true,
                canCreateLink: false,
                onSessionChanged: (_) => onChanged()),
            const SizedBox(height: 8),
          ],
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onJoin,
                  icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                  label: const Text('Chat'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  child: const Text('Cancel'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Tombol "Find Professionals" di bawah label Professional Care.
class _FindProfessionalsButton extends StatelessWidget {
  const _FindProfessionalsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
      ),
      icon: const Icon(Icons.search_rounded),
      label: const Text('Find Professionals'),
    );
  }
}

/// Banner Mood Medication Check-in (Mood + Medication Tracker).
class _MoodMedicationBanner extends StatelessWidget {
  const _MoodMedicationBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      bordered: true,
      onTap: onTap,
      color: MalvaColors.orchid.withValues(alpha: 0.10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: MalvaColors.orchid.withValues(alpha: 0.18),
            child: const Icon(Icons.monitor_heart_rounded,
                color: MalvaColors.orchid),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mood Medication Check-in',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
                Text(
                  'Mood Tracker & Medication Tracker',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: MalvaColors.orchid),
        ],
      ),
    );
  }
}

/// Grid 2 kolom: ikon + label.
class _HomeSectionGrid extends StatelessWidget {
  const _HomeSectionGrid({required this.items});

  final List<_GridItem> items;

  @override
  Widget build(BuildContext context) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 2.6,
      padding: EdgeInsets.zero,
      children: [for (final item in items) _HomeGridTile(item: item)],
    );
  }
}

class _GridItem {
  const _GridItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

class _HomeGridTile extends StatelessWidget {
  const _HomeGridTile({required this.item});

  final _GridItem item;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      bordered: true,
      onTap: item.onTap,
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 21,
            backgroundColor: item.color.withValues(alpha: 0.12),
            child: Icon(item.icon, color: item.color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              item.label,
              style: const TextStyle(fontWeight: FontWeight.w800),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationBell extends StatefulWidget {
  const _NotificationBell({this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell> {
  int _unread = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      return;
    }
    try {
      final items = await apiClient.listNotifications(accessToken: accessToken);
      if (!mounted) return;
      setState(() {
        _unread = items.where((n) => !n.isRead).length;
      });
    } on Object catch (_) {
      // Badge opsional - jangan ganggu home bila gagal.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          tooltip: 'Notifikasi',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => NotificationsScreen(
                  session: widget.session,
                  apiClient: widget.apiClient,
                ),
              ),
            ).then((_) => _load());
          },
          icon: const Icon(Icons.notifications_rounded, color: Colors.white),
        ),
        if (_unread > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: MalvaColors.danger,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white, width: 1.5),
              ),
              child: Text(
                _unread > 9 ? '9+' : '$_unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Kartu "Sesi berjalan" di home pasien. Menampilkan nama profesional, jam
/// WIB, tipe sesi, tombol Gabung (video, via [MeetJoinButton]) dan Chat.
/// Ditampilkan selama sesi scheduled berada di dalam jendela waktu.
class _OngoingSessionCard extends StatelessWidget {
  const _OngoingSessionCard({
    required this.session,
    required this.accessToken,
    required this.onChat,
    required this.onChanged,
  });

  final BackendCareSession session;
  final String accessToken;
  final VoidCallback onChat;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) {
    final at = session.scheduledDateTime;
    final dateLabel = at == null
        ? '-'
        : '${at.day}/${at.month}/${at.year} '
            '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return SoftCard(
      bordered: true,
      accent: MalvaColors.mint,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ProfessionalAvatar(
                displayName: session.professionalName.isEmpty
                    ? 'Profesional'
                    : session.professionalName,
                radius: 22,
                photoUrl: session.photoIntroUrl.isNotEmpty
                    ? session.photoIntroUrl
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.professionalName.isEmpty
                          ? 'Sesi ${session.isVideo ? 'Video' : 'Chat'}'
                          : session.professionalName,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '${session.isVideo ? 'Video' : 'Chat'} • $dateLabel',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const StatusPill(label: 'Berjalan', color: MalvaColors.mint),
            ],
          ),
          const SizedBox(height: 10),
          if (session.isVideo) ...[
            MeetJoinButton(
              session: session,
              accessToken: accessToken,
              expanded: true,
              canCreateLink: false,
              onSessionChanged: (_) => onChanged(),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onChat,
              style: compactFilledButtonStyle,
              icon: const Icon(Icons.chat_bubble_rounded, size: 16),
              label: const Text('Chat'),
            ),
          ),
          const SizedBox(height: 10),
          SessionAttendanceActions(
              session: session,
              role: UserRole.patient,
              accessToken: accessToken,
              onChanged: onChanged),
        ],
      ),
    );
  }
}
