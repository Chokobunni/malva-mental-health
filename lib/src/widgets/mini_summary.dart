import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../theme.dart';
import 'malva_components.dart';

// ============================================================
// CHAT MINI SUMMARY (Weekly) — ringkasan 14 hari untuk dokter
// Dihitung lokal dari store; backend Gemini menyusul (kontrak sama).
// ============================================================

class MiniSummaryButton extends ConsumerWidget {
  const MiniSummaryButton({super.key});

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
          builder: (_) => const _MiniSummarySheet(),
        ),
      ),
    );
  }
}

class _MiniSummarySheet extends ConsumerWidget {
  const _MiniSummarySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(malvaStoreProvider);
    final cutoff = DateTime.now().subtract(const Duration(days: 14));

    final moods =
        store.moodEntries.where((e) => e.date.isAfter(cutoff)).toList();
    final diaries =
        store.diaryEntries.where((e) => e.createdAt.isAfter(cutoff)).toList();
    final logs =
        store.medicationLogs.where((l) => l.takenAt.isAfter(cutoff)).toList();

    final avgSleep = moods.isEmpty
        ? 0.0
        : moods.map((e) => e.sleepHours).reduce((a, b) => a + b) / moods.length;
    final taken = logs.where((l) => l.status == 'taken').length;
    final adherence = logs.isEmpty ? 0 : ((taken / logs.length) * 100).round();
    final activeGoals =
        store.goals.where((g) => !g.completedToday).take(3).toList();

    String moodTrend = 'Belum ada data';
    if (moods.length >= 2) {
      final first = moods.last.mood.score;
      final last = moods.first.mood.score;
      if (last > first) {
        moodTrend = 'Membaik ↗';
      } else if (last < first) {
        moodTrend = 'Menurun ↘';
      } else {
        moodTrend = 'Stabil →';
      }
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
            'Mini Summary (Weekly)',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
          ),
          const SizedBox(height: 4),
          Text(
            'Ringkasan 14 hari terakhir — dihitung dari data tersimpan.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _SummaryTile(
            icon: Icons.show_chart_rounded,
            color: MalvaColors.seed,
            title: 'Mood Trend',
            value: '$moodTrend (${moods.length} check-in)',
          ),
          _SummaryTile(
            icon: Icons.bedtime_rounded,
            color: MalvaColors.orchid,
            title: 'Rata-rata Jam Tidur',
            value: '${avgSleep.toStringAsFixed(1)} jam/malam',
          ),
          _SummaryTile(
            icon: Icons.medication_rounded,
            color: MalvaColors.mint,
            title: 'Ketaatan Obat',
            value: '$adherence% ($taken dari ${logs.length} log)',
          ),
          _SummaryTile(
            icon: Icons.edit_note_rounded,
            color: MalvaColors.amber,
            title: 'Last Diary Entry',
            value: diaries.isEmpty
                ? 'Belum ada diary 14 hari terakhir'
                : '"${_truncate(diaries.first.note.isEmpty ? diaries.first.title : diaries.first.note, 90)}"',
          ),
          const SizedBox(height: 8),
          const SectionLabel('Current Goals'),
          if (store.goals.isEmpty)
            const Text('Belum ada goal aktif.')
          else
            for (final goal in activeGoals) ...[
              _GoalRow(name: goal.title, streak: goal.streakDays),
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
              'Ringkasan ini dihitung lokal dari data perangkat. Versi AI (Gemini) menyusul via backend.',
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
  const _GoalRow({required this.name, required this.streak});

  final String name;
  final int streak;

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
            label: '$streak streak',
            color: streak > 0 ? MalvaColors.mint : Colors.black54,
            icon: Icons.local_fire_department_rounded,
          ),
        ],
      ),
    );
  }
}
