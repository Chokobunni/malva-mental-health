import 'package:flutter/material.dart';

import '../../models/goal_details.dart';
import '../../services/goal_history.dart';
import '../../services/malva_api_client.dart';
import '../../time/wib.dart';
import 'goal_reference_widgets.dart';
import 'goal_history_detail.dart';

class GoalHistoryPanel extends StatelessWidget {
  const GoalHistoryPanel({
    super.key,
    required this.goals,
    required this.logs,
    required this.range,
    required this.today,
    required this.rangeLabel,
    required this.onRangeChanged,
    required this.method,
    required this.onMethodChanged,
    required this.onArchive,
    required this.loading,
    required this.error,
    required this.onRetry,
    this.loadGoalForDate,
    this.detailGuard,
  });

  final List<BackendGoal> goals;
  final List<BackendHabitLog> logs;
  final DateTimeRange range;
  final DateTime today;
  final String rangeLabel;
  final ValueChanged<int> onRangeChanged;
  final String method;
  final ValueChanged<String?> onMethodChanged;
  final VoidCallback onArchive, onRetry;
  final bool loading;
  final String? error;
  final Future<BackendGoal?> Function(String id, String day)? loadGoalForDate;
  final Widget Function(Widget child)? detailGuard;

  @override
  Widget build(BuildContext context) {
    const methods = {
      '': 'Semua Target',
      'yes_no': 'Ya/Tidak',
      'numeric': 'Dengan Nilai',
      'checklist': 'Sub-Tugas',
    };
    final filteredGoals = goals.where((goal) =>
        method.isEmpty || (goal.details?.method ?? 'yes_no') == method);
    final grouped = groupGoalHistory(filteredGoals.toList(), logs,
        start: range.start, end: range.end, today: today);
    final start = wibDateKey(range.start), end = wibDateKey(range.end);
    final sameMonth = range.start.year == range.end.year &&
        range.start.month == range.end.month;
    final rangeDate = start == end
        ? goalDateLabel(end)
        : sameMonth
            ? '${range.start.day}–${goalDateLabel(end)}'
            : '${goalDateLabel(start)} – ${goalDateLabel(end)}';
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
          label: methods[method] ?? methods['']!,
          onSelected: onMethodChanged,
          items: [
            for (final method in methods.entries)
              PopupMenuItem(value: method.key, child: Text(method.value)),
          ],
        )),
      ]),
      const SizedBox(height: 8),
      Text(rangeDate, style: const TextStyle(color: goalMuted)),
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
              backgroundColor: const Color(0xFFF5E8FA),
              textColor: goalInk,
              shape: const Border(),
              collapsedShape: const Border(),
              title: Row(children: [
                Expanded(
                    child: Text(_historyDayLabel(day.key, short: true),
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 14))),
                const SizedBox(width: 8),
                Text(
                    '${day.value.where((entry) => entry.log?.done == true).length}/${day.value.length} selesai',
                    style: const TextStyle(
                        color: goalMuted,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ]),
              children: [
                for (final entry in day.value)
                  Material(
                    color: Colors.white,
                    child: Column(children: [
                      if (entry != day.value.first)
                        const Divider(
                            height: 1,
                            indent: 16,
                            endIndent: 16,
                            color: goalLine),
                      ListTile(
                        visualDensity: const VisualDensity(vertical: -2),
                        title: Text(entry.goal.title,
                            style: const TextStyle(
                                fontFamily: 'PlusJakartaSans',
                                fontSize: 14,
                                fontWeight: FontWeight.w600)),
                        trailing:
                            Row(mainAxisSize: MainAxisSize.min, children: [
                          entry.goal.details?.method != 'numeric' &&
                                  entry.goal.details?.method != 'checklist' &&
                                  entry.log?.done == true
                              ? const GoalPill('Selesai',
                                  icon: Icons.check,
                                  color: Color(0xFF14865B),
                                  background: Color(0xFFE0F5EA))
                              : ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 104),
                                  child: Text(goalHistoryResult(entry),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                      textAlign: TextAlign.end,
                                      style:
                                          const TextStyle(color: goalMuted))),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right,
                              color: const Color(0xFFC3BDC9),
                              key: Key(
                                  'goal-history-open-${entry.goal.id}-${day.key}')),
                        ]),
                        onTap: () => _showDetails(context, day.key, entry),
                      ),
                    ]),
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

  void _showDetails(BuildContext context, String day, GoalHistoryEntry entry) {
    final detail =
        GoalHistoryDetail(day: day, entry: entry, loadGoal: loadGoalForDate);
    showDialog<void>(
        context: context, builder: (_) => detailGuard?.call(detail) ?? detail);
  }
}

String _historyDayLabel(String key, {bool short = false}) {
  final date = parseWibStored(key)!;
  final label = goalDateLabel(key);
  if (!short) return '${wibWeekdayName(date)}, $label';
  final month = label.split(' ')[1].substring(0, 3);
  return '${wibWeekdayName(date)}, ${date.day} $month';
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
