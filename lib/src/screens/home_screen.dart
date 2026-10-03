import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/crisis_hotline.dart';
import '../widgets/home_personalization.dart';
import '../widgets/malva_components.dart';
import '../widgets/sync_status.dart';
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
              trailing: IconButton(
                tooltip: 'Profil',
                onPressed: widget.onOpenMore,
                icon: const CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person_rounded, color: MalvaColors.seed),
                ),
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
                    icon: Icons.edit_note_rounded,
                    title: 'Diary History',
                    subtitle: 'Catat trigger, pikiran, dan respons',
                    onTap: widget.onOpenDiary,
                  ),
                  const SizedBox(height: 10),
                  ActionTile(
                    icon: Icons.folder_shared_rounded,
                    title: 'Health Record',
                    subtitle: 'Diagnosis, file asesmen, dan riwayat obat',
                    onTap: widget.onOpenMore,
                  ),
                  const SizedBox(height: 10),
                  ActionTile(
                    icon: Icons.chat_bubble_outline_rounded,
                    title: 'Chat Profesional',
                    subtitle: 'Kirim pesan langsung ke profesional Anda',
                    onTap: widget.onOpenChat,
                    color: MalvaColors.orchid,
                  ),
                  const SizedBox(height: 22),
                  const SectionLabel('Health Check-in'),
                  ActionTile(
                    icon: Icons.mood_rounded,
                    title: 'Mood Tracker',
                    subtitle: 'Mood, tidur, energi, kecemasan',
                    onTap: widget.onOpenMood,
                    color: MalvaColors.orchid,
                  ),
                  const SizedBox(height: 10),
                  ActionTile(
                    icon: Icons.medication_rounded,
                    title: 'Medication Tracker',
                    subtitle: 'Reminder, stok, dan log minum obat',
                    onTap: widget.onOpenMedication,
                    color: MalvaColors.mint,
                  ),
                  const SizedBox(height: 10),
                  ActionTile(
                    icon: Icons.fact_check_rounded,
                    title: 'Assessment',
                    subtitle: 'PHQ-9, GAD-7, dan rule engine',
                    onTap: widget.onOpenAssessment,
                    color: MalvaColors.amber,
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

    setState(() {
      _isLoadingFollowUps = true;
      _followUpError = null;
    });

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
}

class _FollowUpPanel extends StatelessWidget {
  const _FollowUpPanel({
    required this.followUps,
    required this.isLoading,
    required this.error,
    required this.onRefresh,
  });

  final List<BackendFollowUpMessage> followUps;
  final bool isLoading;
  final String? error;
  final Future<void> Function() onRefresh;

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
              Text(
                followUp.body,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                _dateLabel(followUp.createdAt),
                style: Theme.of(context).textTheme.bodySmall,
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
