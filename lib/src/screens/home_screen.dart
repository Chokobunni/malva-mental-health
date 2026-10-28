import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../services/medication_reminder_service.dart';
import '../theme.dart';
import '../widgets/crisis_hotline.dart';
import '../widgets/daily_checkin_flow.dart';
import '../widgets/malva_components.dart';
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

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _isInitialLoading = true;
  BackendCareSession? _upcomingSession;

  @override
  void initState() {
    super.initState();
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
    final apiClient = widget.apiClient;
    if (apiClient == null) {
      if (mounted) setState(() => _upcomingSession = null);
      return;
    }
    final rawToken = widget.session?.accessToken;
    final accessToken =
        (rawToken == null || rawToken.isEmpty) ? null : rawToken;
    if (accessToken == null) {
      if (mounted) setState(() => _upcomingSession = null);
      return;
    }
    try {
      final sessions = await apiClient.listCareSessions(
        accessToken: accessToken,
        scope: 'upcoming',
      );
      if (!mounted) return;
      sessions
          .sort((a, b) => (a.scheduledAt ?? '').compareTo(b.scheduledAt ?? ''));
      setState(
          () => _upcomingSession = sessions.isEmpty ? null : sessions.first);
    } on Object {
      if (mounted) setState(() => _upcomingSession = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeState = ref.watch(malvaStoreProvider);
    final upcoming = _upcomingSession;
    // Nama sapaan diambil dari sesi login asli, fallback ke store.
    final displayName = (widget.session?.displayName.trim().isNotEmpty ?? false)
        ? widget.session!.displayName
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
                    session: widget.session,
                    apiClient: widget.apiClient,
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
                  // === 1. SESI MENDATANG (paling atas) ===
                  if (upcoming != null) ...[
                    _UpcomingSessionCard(
                      session: upcoming,
                      onJoin: () => _joinSession(context, upcoming),
                      onCancel: () => _cancelSession(context, upcoming),
                    ),
                    const SizedBox(height: 18),
                  ],

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
                  // Tombol Join Meeting — akses cepat ke video call yang
                  // sudah dijadwalkan. Menampilkan sesi video terdekat yang
                  // punya meeting_url.
                  _JoinMeetingBanner(
                    session: widget.session,
                    apiClient: widget.apiClient,
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
    final apiClient = widget.apiClient;
    final token = widget.session?.accessToken;
    if (apiClient == null || token == null || token.isEmpty) return;
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
  });

  final BackendCareSession session;
  final VoidCallback onJoin;
  final VoidCallback onCancel;

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
    final date = session.scheduledDateTime?.toLocal();
    final dateLabel = date != null
        ? '${_days[date.weekday - 1]}, ${date.day.toString().padLeft(2, '0')} '
            '${_months[date.month - 1]} ${date.year} • '
            '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
        : '-';
    final name = session.professionalName.isEmpty
        ? 'Profesional'
        : session.professionalName;
    return SoftCard(bordered: true, 
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
                        Text(
                          '${isVideo ? 'Video' : 'Chat'} Session, ${session.durationMinutes} menit',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.black54),
                        ),
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
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: onJoin,
                  icon: const Icon(Icons.videocam_rounded, size: 18),
                  label: const Text('Join'),
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
    return SoftCard(bordered: true, 
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
    return SoftCard(bordered: true, 
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

/// Banner "Join Meeting" di homescreen pasien. Menampilkan sesi video
/// terdekat yang punya meeting_url, dengan tombol untuk langsung gabung.
/// Bila tidak ada sesi video mendatang, banner disembunyikan.
class _JoinMeetingBanner extends ConsumerStatefulWidget {
  const _JoinMeetingBanner({this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<_JoinMeetingBanner> createState() => _JoinMeetingBannerState();
}

class _JoinMeetingBannerState extends ConsumerState<_JoinMeetingBanner> {
  BackendCareSession? _nextVideoSession;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadNextVideoSession();
  }

  Future<void> _loadNextVideoSession() async {
    final token = widget.session?.accessToken;
    if (token == null || token.isEmpty) {
      setState(() => _loaded = true);
      return;
    }
    try {
      final apiClient = widget.apiClient ?? ref.read(apiClientProvider);
      final sessions = await apiClient!.listCareSessions(
        accessToken: token,
        scope: 'upcoming',
      );
      // Cari sesi video terjadwal terdekat (dengan atau tanpa link Meet).
      // Tanpa link, banner menawarkan "Siapkan link Meet".
      BackendCareSession? found;
      for (final s in sessions) {
        if (s.isVideo && s.isScheduled) {
          found = s;
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _nextVideoSession = found;
        _loaded = true;
      });
    } on Object catch (_) {
      if (!mounted) return;
      setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _nextVideoSession == null) return const SizedBox.shrink();
    final s = _nextVideoSession!;
    final at = s.scheduledDateTime?.toLocal();
    final dateLabel = at == null
        ? ''
        : '${at.day}/${at.month}/${at.year} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    return InkWell(
      onTap: () => _joinMeeting(s),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: MalvaColors.mint.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: MalvaColors.mint.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            const CircleAvatar(
              radius: 20,
              backgroundColor: MalvaColors.mint,
              child: Icon(Icons.videocam_rounded,
                  color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.meetingUrl.trim().isEmpty
                        ? 'Siapkan Link Meet'
                        : (s.isBeforeJoinWindow
                            ? 'Video call • ${s.joinStateLabel}'
                            : 'Join Video Call'),
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 13),
                  ),
                  if (dateLabel.isNotEmpty)
                    Text(
                      '${s.professionalName.isNotEmpty ? s.professionalName : 'Sesi video'} • $dateLabel',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: MalvaColors.mint),
          ],
        ),
      ),
    );
  }

  Future<void> _joinMeeting(BackendCareSession s) async {
    final token = widget.session?.accessToken;
    // Link belum ada: minta backend membuatkannya sekarang.
    if (s.meetingUrl.trim().isEmpty) {
      if (token == null || token.isEmpty) return;
      try {
        final MalvaApiClient apiClient =
            widget.apiClient ?? ref.read(apiClientProvider);
        await apiClient.ensureMeetLink(
          accessToken: token,
          sessionId: s.id,
        );
        await _loadNextVideoSession();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link Google Meet sudah siap.')),
        );
      } on Object catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e))),
        );
      }
      return;
    }
    if (s.isBeforeJoinWindow) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Belum bisa bergabung — ${s.joinStateLabel}.')),
      );
      return;
    }
    final uri = Uri.parse(s.meetingUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak dapat membuka Google Meet.')),
      );
    }
  }
}
