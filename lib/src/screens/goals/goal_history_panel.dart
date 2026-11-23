import 'package:flutter/material.dart';

import '../../services/goal_history.dart';
import '../../services/malva_api_client.dart';
import '../../time/wib.dart';
import 'goal_reference_widgets.dart';

class GoalHistoryPanel extends StatelessWidget {
  const GoalHistoryPanel({
    super.key,
    required this.goals,
    required this.logs,
    required this.range,
    required this.rangeLabel,
    required this.onRangeChanged,
    required this.goalId,
    required this.onGoalChanged,
    required this.onArchive,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final List<BackendGoal> goals;
  final List<BackendHabitLog> logs;
  final DateTimeRange range;
  final String rangeLabel;
  final ValueChanged<int> onRangeChanged;
  final String goalId;
  final ValueChanged<String?> onGoalChanged;
  final VoidCallback onArchive, onRetry;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final selected = goals.where((goal) => goal.id == goalId).firstOrNull;
    final grouped = groupGoalHistory(goals, logs, goalId: selected?.id);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Riwayat progres',
          style: TextStyle(
              fontSize: 22, fontWeight: FontWeight.w800, color: goalInk)),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
            child: _HistoryFilter(
          icon: Icons.calendar_today_outlined,
          label: rangeLabel,
          onSelected: onRangeChanged,
          items: const [
            PopupMenuItem(value: 7, child: Text('7 hari terakhir')),
            PopupMenuItem(value: 30, child: Text('30 hari terakhir')),
            PopupMenuItem(value: 0, child: Text('Pilih rentang tanggal')),
          ],
        )),
        const SizedBox(width: 10),
        Expanded(
            child: _HistoryFilter(
          icon: Icons.adjust_rounded,
          label: selected?.title ?? 'Semua target',
          onSelected: onGoalChanged,
          items: [
            const PopupMenuItem(value: '', child: Text('Semua target')),
            for (final goal in goals)
              PopupMenuItem(value: goal.id, child: Text(goal.title)),
          ],
        )),
      ]),
      const SizedBox(height: 8),
      Text('${formatWibDate(range.start)} - ${formatWibDate(range.end)}',
          style: const TextStyle(color: goalMuted)),
      const SizedBox(height: 16),
      if (loading)
        const Center(child: CircularProgressIndicator(color: goalPurple))
      else if (error != null) ...[
        Text(error!),
        TextButton(onPressed: onRetry, child: const Text('Coba lagi')),
      ] else if (grouped.isEmpty)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Text('Belum ada progres tercatat pada rentang ini.',
                textAlign: TextAlign.center,
                style: TextStyle(color: goalMuted)))
      else
        for (final day in grouped.entries) ...[
          Material(
            color: Colors.white,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: const BorderSide(color: Color(0xFFE8DAF2))),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              key: PageStorageKey('goal-history-${day.key}'),
              backgroundColor: const Color(0xFFFCF8FF),
              textColor: goalPurple,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Row(children: [
                Expanded(
                    child: Text(wibWeekdayDate(parseWibStored(day.key)!),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14))),
                const SizedBox(width: 8),
                Text(
                    '${day.value.where((entry) => entry.log.done).length}/${day.value.length} selesai',
                    style: const TextStyle(
                        color: goalMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ]),
              children: [
                for (final entry in day.value)
                  ListTile(
                    title: Text(entry.goal.title),
                    trailing: entry.goal.details?.method != 'numeric' &&
                            entry.goal.details?.method != 'checklist' &&
                            entry.log.done
                        ? const GoalPill('Selesai',
                            icon: Icons.check,
                            color: Color(0xFF14865B),
                            background: Color(0xFFE0F5EA))
                        : ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 104),
                            child: Text(goalHistoryResult(entry),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.end,
                                style: const TextStyle(color: goalMuted))),
                    onTap: () => _showDetails(context, entry),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],
      const SizedBox(height: 12),
      Material(
        color: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFE8DAF2))),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: const Icon(Icons.archive_outlined, color: goalPurple),
          title: const Text('Target diarsipkan',
              style: TextStyle(fontWeight: FontWeight.w700)),
          trailing: const Icon(Icons.chevron_right),
          onTap: onArchive,
        ),
      ),
    ]);
  }

  void _showDetails(BuildContext context, GoalHistoryEntry entry) {
    final details = entry.goal.details;
    final method = details?.method;
    final numeric = method == 'numeric';
    final checklist = method == 'checklist';
    final total = numeric ? details!.target : details?.steps.length ?? 0;
    final progress = numeric ? entry.log.value : completedGoalSteps(entry);
    showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Detail aktivitas',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              scrollable: true,
              backgroundColor: Colors.white,
              content: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(entry.goal.title,
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(wibWeekdayDate(parseWibStored(entry.log.loggedOn)!),
                        style: const TextStyle(color: goalMuted)),
                    const SizedBox(height: 14),
                    GoalSurface(
                      color: const Color(0xFFF3E9FB),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (numeric || checklist) ...[
                              Text(
                                  'Progres tercatat: ${goalHistoryResult(entry)}',
                                  style: const TextStyle(
                                      color: goalPurple,
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 8),
                              LinearProgressIndicator(
                                  value: total == 0
                                      ? 0
                                      : (progress / total).clamp(0.0, 1.0),
                                  color: goalPurple),
                              const SizedBox(height: 8),
                            ],
                            Text(entry.log.done
                                ? 'Selesai'
                                : numeric
                                    ? 'Belum tercapai'
                                    : 'Belum selesai'),
                          ]),
                    ),
                    if (details != null && details.steps.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Text(checklist ? 'Daftar Langkah' : 'Rincian Aktivitas',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      for (final step in details.steps)
                        Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                      checklist
                                          ? entry.log.completedStepIds
                                                  .contains(step.id)
                                              ? Icons.check_box_outlined
                                              : Icons.check_box_outline_blank
                                          : Icons.circle,
                                      size: checklist ? 18 : 8,
                                      color: goalPurple),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(step.label)),
                                ])),
                    ],
                    if (details?.note.isNotEmpty == true) ...[
                      const SizedBox(height: 10),
                      Text(details!.note),
                    ],
                  ]),
              actions: [
                SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context),
                      style:
                          FilledButton.styleFrom(backgroundColor: goalPurple),
                      child: const Text('Tutup'),
                    )),
              ],
            ));
  }
}

class _HistoryFilter<T> extends StatelessWidget {
  const _HistoryFilter(
      {required this.icon,
      required this.label,
      required this.onSelected,
      required this.items});
  final IconData icon;
  final String label;
  final ValueChanged<T> onSelected;
  final List<PopupMenuEntry<T>> items;

  @override
  Widget build(BuildContext context) => PopupMenuButton<T>(
        tooltip: label,
        onSelected: onSelected,
        itemBuilder: (_) => items,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 11),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE8DAF2))),
          child: Row(children: [
            Icon(icon, color: goalPurple, size: 17),
            const SizedBox(width: 6),
            Expanded(
                child:
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis)),
            const Icon(Icons.expand_more, color: goalMuted, size: 18),
          ]),
        ),
      );
}
