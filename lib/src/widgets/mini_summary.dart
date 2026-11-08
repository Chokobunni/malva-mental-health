import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/weekly_summary_service.dart';
import '../services/malva_api_client.dart';
import 'mood_insights.dart';
import '../theme.dart';
import 'malva_components.dart';
import '../time/wib.dart';

// ============================================================
// CHAT MINI SUMMARY (14 hari) — ringkasan 14 hari untuk dokter
// Angka mood/tidur/kepatuhan diambil dari SERVER (fallback ke store lokal),
// karena store tidak selalu terhidrasi saat chat dibuka — dulu kartu ini
// menampilkan 0 check-in / 0.0 jam / 0% padahal data pasien ada.
// ============================================================

class MiniSummaryButton extends ConsumerWidget {
  const MiniSummaryButton({super.key, this.patientId});
  final String? patientId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
        onPressed: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          builder: (_) => _MiniSummarySheet(patientId: patientId),
        ),
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
  List<BackendDiaryEntry>? _diaries;
  List<BackendGoal>? _goals;

  @override
  void initState() {
    super.initState();
    _owner = ref.read(currentSessionProvider);
    unawaited(_loadMetrics());
  }

  /// Muat metrik 14 hari sekali saat sheet dibuka.
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
            localMoods: [
              for (final entry in store.moodEntries)
                if (widget.patientId == null)
                  (
                    at: entry.date,
                    sleepHours: entry.sleepHours,
                    moodScore: entry.mood.score
                  )
            ],
            localLogs: [
              for (final log in store.medicationLogs)
                if (widget.patientId == null)
                  (at: log.takenAt, status: log.status)
            ],
          );
        } on Object {/* Unknown stays visible. */}
        if (isCurrent()) setState(() => _metrics = metrics);
      }(),
      () async {
        try {
          final diaries = await api.listDiaryEntries(
              accessToken: token, patientId: widget.patientId, limit: 0);
          if (isCurrent()) setState(() => _diaries = diaries);
        } on Object {/* Unknown stays visible. */}
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
    final cutoff = wibNow().subtract(const Duration(days: 14));

    final diaries = (_diaries ?? <BackendDiaryEntry>[])
        .where((e) => e.occurredAt != null && e.occurredAt!.isAfter(cutoff))
        .toList()
      ..sort((a, b) => b.occurredAt!.compareTo(a.occurredAt!));
    final activeGoals =
        (_goals ?? <BackendGoal>[]).where((g) => g.isActive).toList();

    // Angka mood/tidur/kepatuhan hanya ditampilkan bila benar-benar diketahui.
    final moodKnown = metrics?.moodKnown ?? false;
    final moodCount = metrics?.moodCount ?? 0;
    final avgSleep = metrics?.avgSleepHours ?? 0.0;
    final logsKnown = metrics?.logsKnown ?? false;
    final taken = metrics?.takenLogs ?? 0;
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
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.all(20),
        children: [
          Center(
            child: Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: Colors.black26,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Mini Summary (14 hari)',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
          ),
          const SizedBox(height: 4),
          Text(
            'Ringkasan 14 hari terakhir — dihitung dari data tersimpan.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_isLoading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 2),
          ],
          const SizedBox(height: 16),
          _SummaryTile(
            icon: Icons.show_chart_rounded,
            color: MalvaColors.seed,
            title: 'Mood Trend',
            value: moodKnown
                ? '$moodTrend ($moodCount check-in)'
                : 'Data check-in belum dimuat',
          ),
          if (metrics != null && metrics.entries.isNotEmpty) ...[
            const SectionLabel('Tren mood — 7 hari terakhir'),
            MoodTrendChart(entries: metrics.entries),
            const SizedBox(height: 12),
            const SectionLabel('Keseimbangan gejala — 7 hari terakhir'),
            SymptomsBalanceChart(entries: metrics.entries),
            const SizedBox(height: 12),
          ],
          _SummaryTile(
            icon: Icons.bedtime_rounded,
            color: MalvaColors.orchid,
            title: 'Rata-rata Jam Tidur',
            value: moodKnown && moodCount > 0
                ? '${avgSleep.toStringAsFixed(1)} jam/malam'
                : 'Belum ada data check-in',
          ),
          _SummaryTile(
            icon: Icons.medication_rounded,
            color: MalvaColors.mint,
            title: 'Ketaatan Obat',
            value: logsKnown
                ? '$adherence% ($taken dari $totalLogs log)'
                : 'Data log obat belum dimuat',
          ),
          _SummaryTile(
            icon: Icons.edit_note_rounded,
            color: MalvaColors.amber,
            title: 'Last Diary Entry',
            value: _diaries == null
                ? 'Data diary belum dimuat'
                : diaries.isEmpty
                    ? 'Belum ada diary 14 hari terakhir'
                    : '"${_truncate(diaries.first.note.isEmpty ? diaries.first.title : diaries.first.note, 90)}"',
          ),
          const SizedBox(height: 8),
          const SectionLabel('Current Goals'),
          if (_goals == null)
            const Text('Data goals belum dimuat.')
          else if (activeGoals.isEmpty)
            const Text('Belum ada goal aktif.')
          else
            for (final goal in activeGoals) ...[
              _GoalRow(
                  name: goal.title,
                  progress:
                      '${goal.doneThisWeek}/${goal.targetPerWeek} minggu ini'),
              const SizedBox(height: 6),
            ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MalvaColors.seed.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'Ringkasan 14 hari dari data tersimpan. Grafik menampilkan 7 hari terakhir.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  String _truncate(String text, int max) {
    if (text.length <= max) return text;
    return '${text.substring(0, max)}…';
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SoftCard(
        padding: const EdgeInsets.all(14),
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
                  const SizedBox(height: 2),
                  Text(value, style: Theme.of(context).textTheme.bodyMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GoalRow extends StatelessWidget {
  const _GoalRow({required this.name, required this.progress});

  final String name;
  final String progress;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child:
                Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          StatusPill(
            label: progress,
            color: MalvaColors.mint,
            icon: Icons.local_fire_department_rounded,
          ),
        ],
      ),
    );
  }
}
