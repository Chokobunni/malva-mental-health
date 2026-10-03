import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/crisis_hotline.dart';
import '../widgets/friendly_error.dart';
import '../widgets/home_personalization.dart';
import '../widgets/malva_components.dart';
import '../widgets/sync_status.dart';
import 'booking/doctor_discovery_screen.dart';
import 'notifications_screen.dart';
import 'safety/guided_grounding_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.onOpenMood,
    required this.onOpenMedication,
    required this.onOpenDiary,
    required this.onOpenChat,
    required this.onOpenMore,
    required this.onOpenAssessment,
    this.session,
    this.apiClient,
  });

  final VoidCallback onOpenMood;
  final VoidCallback onOpenMedication;
  final VoidCallback onOpenDiary;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenMore;
  final VoidCallback onOpenAssessment;
  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  List<BackendFollowUpMessage> _followUps = const [];
  bool _isLoadingFollowUps = false;
  String? _followUpError;
  bool _isInitialLoading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadFollowUps().then((_) {
      if (mounted) setState(() => _isInitialLoading = false);
    }));
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session?.accessToken != widget.session?.accessToken ||
        oldWidget.apiClient != widget.apiClient) {
      unawaited(_loadFollowUps());
    }
  }

  Future<void> _refreshAll() async {
    await _loadFollowUps();
  }

  Future<void> _loadFollowUps() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      if (!mounted) return;
      setState(() {
        _followUps = const [];
        _followUpError = null;
        _isLoadingFollowUps = false;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingFollowUps = true;
        _followUpError = null;
      });
    }

    try {
      final followUps = await apiClient.listFollowUps(
        accessToken: accessToken,
        limit: 5,
      );
      if (!mounted) return;
      setState(() {
        _followUps = followUps;
        _isLoadingFollowUps = false;
      });
    } on MalvaApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _followUpError = error.message;
        _isLoadingFollowUps = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _followUpError = 'Follow-up belum bisa dimuat: $error';
        _isLoadingFollowUps = false;
      });
    }
  }

  Future<void> _markFollowUpRead(BackendFollowUpMessage followUp) async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      return;
    }
    try {
      final updated = await apiClient.markFollowUpRead(
        accessToken: accessToken,
        followUpId: followUp.id,
      );
      if (!mounted) return;
      setState(() {
        _followUps = [
          for (final item in _followUps)
            if (item.id == updated.id) updated else item,
        ];
      });
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeState = ref.watch(malvaStoreProvider);
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
                children: [
                  if (storeState.activeAlerts.isNotEmpty) ...[
                    _AlertBanner(alerts: storeState.activeAlerts),
                    const SizedBox(height: 18),
                  ],
                  if (_shouldShowFollowUps) ...[
                    _FollowUpPanel(
                      followUps: _followUps,
                      isLoading: _isLoadingFollowUps,
                      error: _followUpError,
                      onRefresh: _loadFollowUps,
                      onMarkRead: _markFollowUpRead,
                    ),
                    const SizedBox(height: 18),
                  ],
                  ConditionBanner(
                    bundle: storeState.latestScreeningBundle,
                  ),
                  const SizedBox(height: 18),
                  InlineMoodCheckIn(
                    onSaved: () => setState(() {}),
                  ),
                  const SizedBox(height: 18),
                  const SmallWinsCard(),
                  const SizedBox(height: 18),
                  DailyExercisesGrid(
                    onBreathing: () => _openGrounding(context),
                    onCbt: widget.onOpenDiary,
                    onMindfulness: () => _openGrounding(context),
                    onJournaling: widget.onOpenMood,
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: MetricTile(
                          icon: Icons.medication_liquid_rounded,
                          value: '${storeState.adherencePercent}%',
                          label: 'Adherence hari ini',
                          color: MalvaColors.mint,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MetricTile(
                          icon: Icons.flag_rounded,
                          value: '${storeState.completedGoalPercent}%',
                          label: 'Goals hari ini',
                          color: MalvaColors.amber,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const SectionLabel('Self-care'),
                  ActionTile(
                    icon: Icons.task_alt_rounded,
                    title: 'Goals & Habits',
                    subtitle: 'Lihat target harian dan streak',
                    onTap: widget.onOpenMore,
                  ),
                  const SizedBox(height: 10),
                  ActionTile(
                    icon: Icons.calendar_month_rounded,
                    title: 'Find Professionals',
                    subtitle: 'Cari psikiater & psikolog terverifikasi',
                    color: MalvaColors.seed,
                    onTap: () => _openDoctorDiscovery(context),
                  ),
                  const SizedBox(height: 22),
                  const SectionLabel('Health Check-in'),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.1,
                    children: [
                      _HomeGridTile(
                        icon: Icons.edit_note_rounded,
                        title: 'Diary',
                        subtitle: 'History',
                        color: MalvaColors.seed,
                        onTap: widget.onOpenDiary,
                      ),
                      _HomeGridTile(
                        icon: Icons.folder_shared_rounded,
                        title: 'Record',
                        subtitle: 'Health record',
                        color: MalvaColors.mint,
                        onTap: widget.onOpenMore,
                      ),
                      _HomeGridTile(
                        icon: Icons.mood_rounded,
                        title: 'Full Check In',
                        subtitle: 'Mood tracker',
                        color: MalvaColors.orchid,
                        onTap: widget.onOpenMood,
                      ),
                      _HomeGridTile(
                        icon: Icons.fact_check_rounded,
                        title: 'Assessment',
                        subtitle: 'PHQ-9 & GAD-7',
                        color: MalvaColors.amber,
                        onTap: widget.onOpenAssessment,
                      ),
                      _HomeGridTile(
                        icon: Icons.medication_rounded,
                        title: 'Obat',
                        subtitle: 'Medication',
                        color: MalvaColors.seed,
                        onTap: widget.onOpenMedication,
                      ),
                      _HomeGridTile(
                        icon: Icons.chat_bubble_outline_rounded,
                        title: 'Chat',
                        subtitle: 'Profesional',
                        color: MalvaColors.orchid,
                        onTap: widget.onOpenChat,
                      ),
                    ],
                  ),
                  const SizedBox(height: 76),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _shouldShowFollowUps =>
      widget.session?.accessToken?.isNotEmpty == true &&
      widget.apiClient != null;

  void _openGrounding(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const GuidedGroundingScreen()),
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
      // Badge opsional — jangan ganggu home bila gagal.
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

class _HomeGridTile extends StatelessWidget {
  const _HomeGridTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
          ),
          Text(
            subtitle,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

class _FollowUpPanel extends StatelessWidget {
  const _FollowUpPanel({
    required this.followUps,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
    required this.onMarkRead,
  });

  final List<BackendFollowUpMessage> followUps;
  final bool isLoading;
  final String? error;
  final Future<void> Function() onRefresh;
  final Future<void> Function(BackendFollowUpMessage followUp) onMarkRead;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: MalvaColors.orchid.withValues(alpha: 0.08),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.mark_email_unread_rounded,
                  color: MalvaColors.orchid),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Follow-up profesional',
                  style: TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              IconButton(
                tooltip: 'Refresh follow-up',
                onPressed: isLoading ? null : onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          if (isLoading) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ] else if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              error!,
              style: const TextStyle(
                color: MalvaColors.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ] else if (followUps.isEmpty) ...[
            const SizedBox(height: 8),
            const Text('Belum ada arahan follow-up baru.'),
          ] else
            for (final followUp in followUps.take(3)) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          followUp.body,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          _dateLabel(followUp.createdAt),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (followUp.readAt == null)
                    TextButton(
                      onPressed: () => onMarkRead(followUp),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text(
                        'Tandai dibaca',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                    )
                  else
                    const Icon(Icons.check_circle_rounded,
                        color: MalvaColors.mint, size: 20),
                ],
              ),
            ],
        ],
      ),
    );
  }

  static String _dateLabel(DateTime? date) {
    if (date == null) return 'Baru saja';
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '${date.day}/${date.month}/${date.year} $h:$m';
  }
}

class _AlertBanner extends StatelessWidget {
  const _AlertBanner({required this.alerts});

  final List<String> alerts;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MalvaColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MalvaColors.danger.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.notifications_active_rounded,
                  color: MalvaColors.danger),
              SizedBox(width: 8),
              Text('Alert aktif',
                  style: TextStyle(fontWeight: FontWeight.w900)),
            ],
          ),
          const SizedBox(height: 8),
          for (final alert in alerts)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(alert, style: Theme.of(context).textTheme.bodyMedium),
            ),
        ],
      ),
    );
  }
}
