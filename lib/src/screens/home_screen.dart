import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../services/malva_api_client.dart';
import '../store/malva_store.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.onOpenMood,
    required this.onOpenMedication,
    required this.onOpenDiary,
    required this.onOpenMore,
    this.session,
    this.apiClient,
  });

  final MalvaStore store;
  final VoidCallback onOpenMood;
  final VoidCallback onOpenMedication;
  final VoidCallback onOpenDiary;
  final VoidCallback onOpenMore;
  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
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
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        return Scaffold(
          floatingActionButton: FloatingActionButton(
            heroTag: 'home_safety_fab',
            backgroundColor: MalvaColors.danger,
            foregroundColor: Colors.white,
            onPressed: () => _showSafetyDialog(context),
            child: const Icon(Icons.warning_amber_rounded),
          ),
          body: RefreshIndicator(
            onRefresh: _refreshAll,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (_isInitialLoading) const LinearProgressIndicator(),
              GradientHeader(
                title: 'Home',
                subtitle: 'Halo, ${widget.store.patient.name}',
                trailing: IconButton(
                  tooltip: 'Profil',
                  onPressed: widget.onOpenMore,
                  icon: const CircleAvatar(
                    backgroundColor: Colors.white,
                    child: Icon(Icons.person_rounded, color: MalvaColors.seed),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    if (widget.store.activeAlerts.isNotEmpty) ...[
                      _AlertBanner(alerts: widget.store.activeAlerts),
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
                    Row(
                      children: [
                        Expanded(
                          child: MetricTile(
                            icon: Icons.medication_liquid_rounded,
                            value: '${widget.store.adherencePercent}%',
                            label: 'Adherence hari ini',
                            color: MalvaColors.mint,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: MetricTile(
                            icon: Icons.flag_rounded,
                            value: '${widget.store.completedGoalPercent}%',
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
                      onTap: widget.onOpenMore,
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
      },
    );
  }

  bool get _shouldShowFollowUps =>
      widget.session?.accessToken?.isNotEmpty == true &&
      widget.apiClient != null;

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

  void _showSafetyDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded,
            color: MalvaColors.danger, size: 42),
        title: const Text('Butuh bantuan segera?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Jika Anda atau orang lain dalam bahaya, segera hubungi layanan darurat.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 16),
              _CrisisAction(
                icon: Icons.emergency_rounded,
                title: 'Darurat Nasional',
                subtitle: '119 / 112',
                onTap: () => launchUrl(Uri.parse('tel:119')),
              ),
              const SizedBox(height: 8),
              _CrisisAction(
                icon: Icons.local_hospital_rounded,
                title: 'RS Terdekat',
                subtitle: 'Hubungi IGD rumah sakit terdekat',
                onTap: () => launchUrl(Uri.parse('tel:118')),
              ),
              const SizedBox(height: 8),
              _CrisisAction(
                icon: Icons.psychology_rounded,
                title: 'Hotline Kesehatan Mental',
                subtitle: '021-500-454 (24 jam)',
                onTap: () => launchUrl(Uri.parse('tel:021500454')),
              ),
              const SizedBox(height: 16),
              const Text(
                'Langkah keselamatan:',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text('1. Jauhkan diri dari situasi berbahaya'),
              const Text('2. Hubungi orang terdekat yang dipercaya'),
              const Text('3. Jangan tinggal sendirian'),
              const Text('4. Ikuti instruksi layanan darurat'),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Tutup')),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _notifyProfessionalCrisis(context);
            },
            icon: const Icon(Icons.send_rounded),
            label: const Text('Notifikasi Profesional'),
          ),
        ],
      ),
    );
  }

  void _notifyProfessionalCrisis(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notifikasi crisis telah dikirim ke profesional Anda.'),
        backgroundColor: MalvaColors.danger,
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

class _CrisisAction extends StatelessWidget {
  const _CrisisAction({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: MalvaColors.danger.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: MalvaColors.danger),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(subtitle,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: MalvaColors.danger),
          ],
        ),
      ),
    );
  }
}
