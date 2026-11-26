import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../models/goal_details.dart';
import '../providers/providers.dart';
import '../services/weekly_summary_service.dart';
import '../services/malva_api_client.dart';
import '../time/wib.dart';
import 'clinical_profile_cards.dart';
import 'mood_insights.dart';
import '../theme.dart';
import 'malva_components.dart';

// ============================================================
// CHAT MINI SUMMARY (7 hari) — ringkasan 7 hari untuk dokter
// Angka mood/tidur/kepatuhan diambil dari SERVER (fallback ke store lokal),
// karena store tidak selalu terhidrasi saat chat dibuka — dulu kartu ini
// menampilkan 0 check-in / 0.0 jam / 0% padahal data pasien ada.
// ============================================================

class MiniSummaryButton extends ConsumerWidget {
  const MiniSummaryButton({super.key, this.patientId, this.iconOnly = false});
  final String? patientId;
  final bool iconOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void openSummary() => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: const Color(0xfff9f5fc),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          builder: (_) => _MiniSummarySheet(patientId: patientId),
        );
    if (iconOnly) {
      return Padding(
        padding: const EdgeInsets.only(right: 12),
        child: IconButton.filledTonal(
          tooltip: 'Mini Summary (7 hari)',
          style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: .16),
              foregroundColor: const Color(0xFFF2D6A2),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24))),
          icon: const Icon(Icons.auto_awesome_rounded, size: 20),
          onPressed: openSummary,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ActionChip(
        avatar: const Icon(Icons.auto_awesome_rounded,
            size: 16, color: Colors.white),
        label: const Text(
          'Mini Summary',
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
        ),
        backgroundColor: MalvaColors.seed,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        onPressed: openSummary,
      ),
    );
  }
}

class _MiniSummarySheet extends ConsumerStatefulWidget {
  const _MiniSummarySheet({this.patientId});
  final String? patientId;

  @override
  ConsumerState<_MiniSummarySheet> createState() => _MiniSummarySheetState();
}

class _MiniSummarySheetState extends ConsumerState<_MiniSummarySheet> {
  /// Metrik dari server (fallback store). null = belum selesai dimuat.
  WeeklySummaryMetrics? _metrics;
  bool _isLoading = true;
  late final AuthSession? _owner;
  List<BackendGoal>? _goals;

  @override
  void initState() {
    super.initState();
    _owner = ref.read(currentSessionProvider);
    unawaited(_loadMetrics());
  }

  /// Muat metrik 7 hari sekali saat sheet dibuka.
  Future<void> _loadMetrics() async {
    final store = ref.read(malvaStoreProvider);
    final token = ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }
    final api = ref.read(apiClientProvider);
    bool isCurrent() => mounted && ref.read(currentSessionProvider) == _owner;
    await Future.wait([
      () async {
        WeeklySummaryMetrics? metrics;
        try {
          metrics = await loadWeeklySummary(
            api: api,
            accessToken: token,
            patientId: widget.patientId,
            includeMedicationSnapshot: true,
            localMoods: [
              for (final entry in store.moodEntries)
                if (_owner?.role == UserRole.patient &&
                    widget.patientId == null)
                  (
                    at: entry.date,
                    sleepHours: entry.sleepHours,
                    moodScore: entry.mood.score
                  )
            ],
          );
        } on Object {/* Unknown stays visible. */}
        if (isCurrent()) setState(() => _metrics = metrics);
      }(),
      () async {
        try {
          final goals = await api.listGoals(
              accessToken: token, patientId: widget.patientId);
          if (isCurrent()) setState(() => _goals = goals);
        } on Object {/* Unknown stays visible. */}
      }(),
    ]);
    if (isCurrent()) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(currentSessionProvider) != _owner) {
      return const Padding(
          padding: EdgeInsets.all(24), child: Text('Sesi akun telah berubah.'));
    }
    final metrics = _metrics;
    final activeGoals =
        (_goals ?? <BackendGoal>[]).where((g) => g.isActive).toList();

    // Angka mood/tidur/kepatuhan hanya ditampilkan bila benar-benar diketahui.
    final moodKnown = metrics?.moodKnown ?? false;
    final moodCount = metrics?.moodCount ?? 0;
    final avgSleep = metrics?.avgSleepHours ?? 0.0;
    final medications = metrics?.medications;
    final logsKnown = metrics?.logsKnown ?? false;
    final totalLogs = metrics?.totalLogs ?? 0;
    final adherence = metrics?.adherencePercent ?? 0;

    String moodTrend = 'Belum ada data';
    if (moodKnown && moodCount >= 2) {
      moodTrend = switch (metrics!.moodTrend) {
        1 => 'Membaik ↗',
        -1 => 'Menurun ↘',
        _ => 'Stabil →',
      };
    }

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, controller) => CustomScrollView(
        controller: controller,
        slivers: [
          PinnedHeaderSliver(
            child: Material(
              color: const Color(0xfff9f5fc),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 10, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.black26,
                            borderRadius: BorderRadius.circular(99),
                          ),
                        ),
                      ),
                      Row(children: [
                        const Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 3,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text('Mini Summary (7 hari)',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 17)),
                              StatusPill(
                                  label: 'Live', color: MalvaColors.seed),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: 'Tutup',
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close, size: 18),
                        ),
                      ]),
                      Text(
                          'Ringkasan 7 hari terakhir • dihitung dari data tersimpan.',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
            sliver: SliverList.list(children: [
              if (_isLoading) ...[
                const LinearProgressIndicator(minHeight: 2),
                const SizedBox(height: 10),
              ],
              SoftCard(
                color: Colors.white,
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const CircleAvatar(
                      backgroundColor: Color(0xfff3e8fa),
                      child: Icon(Icons.show_chart_rounded,
                          color: MalvaColors.seed),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Tren Mood',
                              style: TextStyle(fontWeight: FontWeight.w800)),
                          Text(
                              moodKnown
                                  ? '$moodTrend ($moodCount check-in)'
                                  : 'Data check-in belum dimuat',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('Rata-rata Tidur',
                              textAlign: TextAlign.end,
                              style: Theme.of(context).textTheme.bodySmall),
                          Text(
                              moodKnown && moodCount > 0
                                  ? '${avgSleep.toStringAsFixed(1)} jam/malam'
                                  : 'Belum ada data',
                              textAlign: TextAlign.end,
                              style: const TextStyle(
                                  color: MalvaColors.plum,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (metrics != null && metrics.entries.isNotEmpty) ...[
                const SizedBox(height: 12),
                const SectionLabel('Tren mood — 7 hari terakhir'),
                MoodTrendChart(entries: metrics.entries),
                const SizedBox(height: 12),
                const SectionLabel('Keseimbangan gejala'),
                SymptomsBalanceChart(entries: metrics.entries),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Text(
                      medications == null
                          ? 'Obat Aktif'
                          : 'Obat Aktif (${medications.length})',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  if (logsKnown && totalLogs > 0)
                    Tooltip(
                      message: '${metrics!.takenLogs} dari $totalLogs dosis',
                      child: StatusPill(
                          label: 'Kepatuhan $adherence% (7 hr)',
                          color: MalvaColors.seed),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              if (medications == null)
                const Text('Data obat belum dimuat.')
              else if (medications.isEmpty)
                const Text('Belum ada obat aktif.')
              else
                for (final medication in medications)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ClinicalMedicationCard(med: medication),
                  ),
              if (!logsKnown && medications?.isNotEmpty == true)
                const Text('Data kepatuhan obat belum dimuat.'),
              const SizedBox(height: 12),
              SoftCard(
                color: Colors.white,
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      const CircleAvatar(
                        backgroundColor: Color(0xfff3e8fa),
                        child:
                            Icon(Icons.flag_outlined, color: MalvaColors.seed),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Progres Target & Kebiasaan',
                                style: TextStyle(fontWeight: FontWeight.w800)),
                            Text('Pembaruan Target Mingguan',
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    if (_goals == null)
                      const Text('Data target belum dimuat.')
                    else if (activeGoals.isEmpty)
                      const Text('Belum ada target aktif.')
                    else
                      for (final goal in activeGoals) ...[
                        const Divider(),
                        _GoalProgress(goal: goal),
                      ],
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }
}

class _GoalProgress extends StatelessWidget {
  const _GoalProgress({required this.goal});

  final BackendGoal goal;

  @override
  Widget build(BuildContext context) {
    final details = goal.details;
    final numeric = details?.method == 'numeric';
    final weeklyTarget = goal.effectiveWeeklyTarget(wibNow());
    final target = numeric ? details!.target : weeklyTarget;
    final done = numeric ? goal.todayValue : goal.doneThisWeek;
    final known =
        target > 0 && (numeric ? goal.isDue : goal.weeklyProgressAvailable);
    final unit = numeric && details!.unit.isNotEmpty ? ' ${details.unit}' : '';
    final stepIds = goal.todayCompletedStepIds.toSet();
    final steps =
        details?.method == 'checklist' ? details!.steps : const <GoalStep>[];
    final stepsDone = steps.where((step) => stepIds.contains(step.id)).length;
    final note = details?.note.trim() ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
                child: Text(goal.title,
                    style: const TextStyle(fontWeight: FontWeight.w800))),
            if (known) ...[
              const SizedBox(width: 8),
              Flexible(
                  child: Text('$done/$target$unit',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                          color: done > 0 ? MalvaColors.mint : Colors.black54,
                          fontWeight: FontWeight.w700))),
            ],
          ]),
          if (details != null) ...[
            const SizedBox(height: 4),
            Text(details.scheduleLabel,
                style: Theme.of(context).textTheme.bodySmall),
          ],
          if (steps.isNotEmpty) ...[
            const SizedBox(height: 8),
            _GoalDetails(
              title: 'Daftar Langkah',
              trailing: '$stepsDone/${steps.length} selesai',
              children: [
                for (final step in steps)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [
                      Icon(
                          stepIds.contains(step.id)
                              ? Icons.check_box_outlined
                              : Icons.check_box_outline_blank,
                          size: 16,
                          color: MalvaColors.seed,
                          semanticLabel: stepIds.contains(step.id)
                              ? 'Selesai'
                              : 'Belum selesai'),
                      const SizedBox(width: 7),
                      Expanded(child: Text(step.label)),
                    ]),
                  ),
              ],
            ),
          ],
          if (known) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (done / target).clamp(0.0, 1.0),
              borderRadius: BorderRadius.circular(99),
              backgroundColor: const Color(0xfff1e5f8),
              color: MalvaColors.mint,
            ),
          ],
          if (note.isNotEmpty) ...[
            const SizedBox(height: 8),
            _GoalDetails(title: 'Rincian Aktivitas', children: [Text(note)]),
          ],
        ],
      ),
    );
  }
}

class _GoalDetails extends StatelessWidget {
  const _GoalDetails(
      {required this.title, this.trailing, required this.children});

  final String title;
  final String? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xfff6effa),
          borderRadius: BorderRadius.circular(13),
        ),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800))),
            if (trailing != null)
              Text(trailing!, style: const TextStyle(color: MalvaColors.plum)),
          ]),
          const SizedBox(height: 4),
          ...children,
        ]),
      );
}
