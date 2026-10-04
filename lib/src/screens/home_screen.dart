import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../services/medication_reminder_service.dart';
import '../theme.dart';
import '../widgets/crisis_hotline.dart';
import '../widgets/daily_checkin_flow.dart';
import '../widgets/malva_components.dart';
import '../widgets/sync_status.dart';
import 'booking/doctor_discovery_screen.dart';
import 'goals_screen.dart';
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
  BackendBooking? _upcomingBooking;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadUpcomingBooking());
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
      unawaited(_loadUpcomingBooking());
    }
  }

  Future<void> _refreshAll() async {
    await _loadUpcomingBooking();
  }

  Future<void> _loadUpcomingBooking() async {
    final apiClient = widget.apiClient;
    final rawToken = widget.session?.accessToken;
    final accessToken =
        (rawToken == null || rawToken.isEmpty) ? null : rawToken;
    if (apiClient == null || accessToken == null) {
      if (mounted) setState(() => _upcomingBooking = null);
      return;
    }
    try {
      final bookings = await apiClient.listBookings(
        accessToken: accessToken,
        limit: 20,
      );
      if (!mounted) return;
      final active = bookings
          .where((b) =>
              b.status == 'paid' ||
              b.status == 'pending' ||
              b.status == 'active')
          .toList(growable: false);
      setState(() => _upcomingBooking = active.isEmpty ? null : active.first);
    } on Object {
      if (mounted) setState(() => _upcomingBooking = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeState = ref.watch(malvaStoreProvider);
    final upcoming = _upcomingBooking;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            if (_isInitialLoading) const LinearProgressIndicator(),
            GradientHeader(
              title: 'Home',
              subtitle: 'Halo, ${storeState.patient.name}',
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
                  // === 1. SESI BOOKING AKTIF (paling atas) ===
                  if (upcoming != null) ...[
                    _UpcomingSessionCard(
                      session: upcoming,
                      onJoin: widget.onOpenChat,
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
                  const SectionLabel('Self Care'),
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
                        onTap: widget.onOpenDiary,
                      ),
                      _GridItem(
                        icon: Icons.psychology_rounded,
                        label: 'Psychological Therapy',
                        color: MalvaColors.pink,
                        onTap: widget.onOpenMore,
                      ),
                      _GridItem(
                        icon: Icons.folder_shared_rounded,
                        label: 'Health Record',
                        color: MalvaColors.mint,
                        onTap: () => _push(const RecordScreen()),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // === 4. PROFESSIONAL CARE ===
                  const SectionLabel('Professional Care'),
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
                        onTap: widget.onOpenMood,
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

  Future<void> _cancelSession(
    BuildContext context,
    BackendBooking booking,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan sesi?'),
        content: const Text('Sesi konsultasi ini akan dibatalkan. Lanjutkan?'),
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
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Permintaan pembatalan sesi dikirim.')),
    );
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

/// Kartu sesi mendatang: nama, Video/Chat Session 30 minutes, tanggal,
/// tombol Join / Cancel (Figma Group 238).
class _UpcomingSessionCard extends StatelessWidget {
  const _UpcomingSessionCard({
    required this.session,
    required this.onJoin,
    required this.onCancel,
  });

  final BackendBooking session;
  final VoidCallback onJoin;
  final VoidCallback onCancel;

  static const _days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday'
  ];
  static const _months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December'
  ];

  @override
  Widget build(BuildContext context) {
    final isVideo = session.serviceType.contains('video');
    final date = DateTime.tryParse(session.bookingDate);
    final dateLabel = date != null
        ? '${_days[date.weekday - 1]}, ${date.day.toString().padLeft(2, '0')} '
            '${_months[date.month - 1]} ${date.year}'
        : session.bookingDate;
    return SoftCard(
      color: MalvaColors.seed.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: MalvaColors.seed.withValues(alpha: 0.14),
                child:
                    const Icon(Icons.person_rounded, color: MalvaColors.seed),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      session.professionalId,
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
                          '${isVideo ? 'Video' : 'Chat'} Session, 30 minutes',
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
    return SoftCard(
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
