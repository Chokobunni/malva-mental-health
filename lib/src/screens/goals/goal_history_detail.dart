import 'package:flutter/material.dart';

import '../../models/goal_details.dart';
import '../../services/goal_history.dart';
import '../../services/malva_api_client.dart';
import '../../time/wib.dart';
import 'goal_reference_widgets.dart';

class GoalHistoryDetail extends StatefulWidget {
  const GoalHistoryDetail(
      {super.key, required this.day, required this.entry, this.loadGoal});
  final String day;
  final GoalHistoryEntry entry;
  final Future<BackendGoal?> Function(String id, String day)? loadGoal;

  @override
  State<GoalHistoryDetail> createState() => _GoalHistoryDetailState();
}

class _GoalHistoryDetailState extends State<GoalHistoryDetail> {
  late Future<BackendGoal?> _loaded = _load();
  Future<BackendGoal?> _load() =>
      widget.loadGoal?.call(widget.entry.goal.id, widget.day) ??
      Future.value(null);

  @override
  Widget build(BuildContext context) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: 460,
                maxHeight: MediaQuery.sizeOf(context).height * .9),
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Center(
                          child: Container(
                              width: 40,
                              height: 4,
                              decoration: BoxDecoration(
                                  color: const Color(0xFFE4DFEB),
                                  borderRadius: BorderRadius.circular(99)))),
                      const SizedBox(height: 16),
                      Row(children: [
                        const GoalPill('Detail aktivitas', fontSize: 12),
                        const Spacer(),
                        IconButton.filledTonal(
                            tooltip: 'Tutup detail aktivitas',
                            onPressed: () => Navigator.pop(context),
                            style: IconButton.styleFrom(
                                backgroundColor: const Color(0xFFF8F5FA),
                                foregroundColor: const Color(0xFF797484)),
                            icon: const Icon(Icons.close)),
                      ]),
                      const SizedBox(height: 16),
                      FutureBuilder<BackendGoal?>(
                          future: _loaded,
                          builder: (context, snapshot) {
                            if (snapshot.connectionState !=
                                ConnectionState.done) {
                              return const Padding(
                                  padding: EdgeInsets.all(30),
                                  child: Center(
                                      child: CircularProgressIndicator(
                                          color: goalPurple)));
                            }
                            if (snapshot.hasError ||
                                (widget.loadGoal != null &&
                                    snapshot.data == null)) {
                              return Column(children: [
                                const Text(
                                    'Detail tanggal ini belum dapat dimuat.'),
                                TextButton(
                                    onPressed: () =>
                                        setState(() => _loaded = _load()),
                                    child: const Text('Coba lagi')),
                              ]);
                            }
                            final goal = snapshot.data ?? widget.entry.goal;
                            final entry = snapshot.data == null
                                ? widget.entry
                                : (
                                    goal: goal,
                                    log: BackendHabitLog(
                                        id: widget.entry.log?.id ?? '',
                                        goalId: goal.id,
                                        loggedOn: widget.day,
                                        done: goal.doneToday == true,
                                        value: goal.todayValue,
                                        sessions: goal.todaySessions,
                                        completedStepIds:
                                            goal.todayCompletedStepIds)
                                  );
                            return _content(entry,
                                projected: snapshot.data != null);
                          }),
                      const SizedBox(height: 24),
                      DecoratedBox(
                          decoration: BoxDecoration(
                              gradient: const LinearGradient(colors: [
                                Color(0xFF8D28B0),
                                Color(0xFFAA36C8)
                              ]),
                              borderRadius: BorderRadius.circular(99),
                              boxShadow: const [
                                BoxShadow(
                                    color: Color(0x269853A4),
                                    blurRadius: 16,
                                    offset: Offset(0, 7))
                              ]),
                          child: FilledButton(
                              onPressed: () => Navigator.pop(context),
                              style: FilledButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  minimumSize: const Size.fromHeight(48),
                                  textStyle: const TextStyle(
                                      fontFamily: 'PlusJakartaSans',
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15)),
                              child: const Text('Tutup'))),
                    ]))),
      );

  Widget _content(GoalHistoryEntry entry, {required bool projected}) {
    final goal = entry.goal;
    final details = goal.details;
    final method = details?.method ?? 'yes_no';
    final numeric = method == 'numeric', checklist = method == 'checklist';
    final progress =
        numeric ? entry.log?.value ?? 0 : completedGoalSteps(entry);
    final total = numeric ? details!.target : details?.steps.length ?? 0;
    final ratio = total > 0 ? (progress / total).clamp(0.0, 1.0) : 0.0;
    final done = entry.log?.done == true;
    final day = parseWibStored(widget.day)!;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 6, children: [
        GoalPill(goalMethodLabel(method).toUpperCase(),
            icon: goalMethodIcon(method),
            color: numeric
                ? const Color(0xFF9D7A26)
                : checklist
                    ? const Color(0xFFAB356E)
                    : goalPurple,
            background: numeric
                ? const Color(0xFFFFF7D8)
                : checklist
                    ? const Color(0xFFFBE8F1)
                    : goalTint),
        if (projected && goal.streakDays > 0)
          GoalPill('${goal.streakDays} hari',
              icon: Icons.local_fire_department_rounded,
              color: const Color(0xFFC68D26),
              background: const Color(0xFFFFF9E5)),
      ]),
      const SizedBox(height: 16),
      Text(goal.title,
          style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: goalInk,
              height: 1.3)),
      const SizedBox(height: 5),
      Text('${wibWeekdayName(day)}, ${goalDateLabel(widget.day)}',
          style: const TextStyle(color: goalMuted, fontSize: 13)),
      const SizedBox(height: 20),
      GoalSurface(
          color: const Color(0xFFF8F1FC),
          border: const Color(0xFFEAE0F0),
          radius: 20,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (numeric) ...[
              Row(children: [
                Expanded(
                    child: Text('Progres tercatat: ${goalHistoryResult(entry)}',
                        style: const TextStyle(
                            color: goalPurple,
                            fontSize: 13,
                            fontWeight: FontWeight.w800))),
                const SizedBox(width: 8),
                GoalPill('${(ratio * 100).round()}%',
                    background: Colors.white, fontSize: 12),
              ]),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                  value: ratio,
                  minHeight: 8,
                  color: goalPurple,
                  backgroundColor: const Color(0xFFE5CFF0),
                  borderRadius: BorderRadius.circular(99)),
            ] else if (checklist) ...[
              Row(children: [
                const Expanded(
                    child: Text('Daftar Langkah',
                        style: TextStyle(fontWeight: FontWeight.w800))),
                Text('$progress/$total selesai',
                    style: const TextStyle(
                        color: goalPurple, fontWeight: FontWeight.w800)),
              ]),
              for (final step in details!.steps)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(children: [
                      Icon(
                          entry.log?.completedStepIds.contains(step.id) == true
                              ? Icons.check_box_rounded
                              : Icons.check_box_outline_blank_rounded,
                          size: 21,
                          color: goalPurple),
                      const SizedBox(width: 9),
                      Expanded(child: Text(step.label)),
                    ])),
            ] else
              Row(children: [
                CircleAvatar(
                    radius: 12,
                    backgroundColor:
                        done ? goalPurple : const Color(0xFFECE5F2),
                    child: Icon(
                        done ? Icons.check : Icons.remove_circle_outline,
                        size: 18,
                        color: done ? Colors.white : const Color(0xFF84798E))),
                const SizedBox(width: 10),
                Expanded(
                    child: Text(done ? 'Selesai dilakukan' : 'Tidak dilakukan',
                        style: TextStyle(
                            fontWeight:
                                done ? FontWeight.w700 : FontWeight.w500))),
              ]),
          ])),
      if (details?.note.isNotEmpty == true) ...[
        const SizedBox(height: 18),
        Text(details!.note,
            style: const TextStyle(color: Color(0xFF55505D), height: 1.6)),
      ],
      if (!checklist && details?.steps.isNotEmpty == true) ...[
        const SizedBox(height: 20),
        const Text('Rincian Aktivitas',
            style: TextStyle(fontWeight: FontWeight.w800)),
        for (final step in details!.steps)
          Padding(
              padding: const EdgeInsets.only(top: 10),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(Icons.circle, size: 8, color: goalPurple)),
                const SizedBox(width: 10),
                Expanded(child: Text(step.label)),
              ])),
      ],
      if (projected) ...[
        const SizedBox(height: 20),
        const Divider(color: goalLine),
        const SizedBox(height: 12),
        if (details?.recurrence == 'weekly' && details?.weeklyTarget == null)
          _fixedSchedule(goal)
        else if (details == null ||
            details.recurrence == 'weekly' ||
            details.recurrence == 'daily')
          _weeklyProgress(goal, day)
        else
          Text(details.scheduleLabel,
              style: const TextStyle(color: goalMuted, height: 1.5)),
      ],
    ]);
  }

  Widget _fixedSchedule(BackendGoal goal) {
    final weekdays = goal.details!.weekdays.toSet();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Hari terpilih (${weekdays.length}×/minggu)',
          style: const TextStyle(color: goalMuted)),
      const SizedBox(height: 12),
      Row(children: [
        for (var day = 1; day <= 7; day++) ...[
          if (day > 1) const SizedBox(width: 5),
          Expanded(
              child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: goal.completedWeekdays.contains(day)
                          ? goalPurple
                          : weekdays.contains(day)
                              ? goalTint
                              : const Color(0xFFF8F9FB)),
                  child: Column(children: [
                    Text(
                        const [
                          'Sen',
                          'Sel',
                          'Rab',
                          'Kam',
                          'Jum',
                          'Sab',
                          'Min'
                        ][day - 1],
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: goal.completedWeekdays.contains(day)
                                ? Colors.white
                                : weekdays.contains(day)
                                    ? goalPurple
                                    : goalMuted)),
                    const SizedBox(height: 4),
                    SizedBox(
                        height: 10,
                        child: goal.completedWeekdays.contains(day)
                            ? const Icon(Icons.check,
                                color: Colors.white, size: 12)
                            : null),
                  ]))),
        ]
      ]),
    ]);
  }

  Widget _weeklyProgress(BackendGoal goal, DateTime day) {
    final target = goal.effectiveWeeklyTarget(day);
    final frequency = goal.details?.recurrence == 'weekly' &&
        goal.details?.weeklyTarget != null;
    return Column(children: [
      Row(children: [
        const Expanded(
            child: Text('Progres pekan tersebut',
                style: TextStyle(color: goalMuted))),
        Text(
            '${goal.doneThisWeek}${target > 0 ? '/$target' : ''} ${frequency ? 'sesi' : 'kali'}',
            style: const TextStyle(
                color: goalPurple, fontWeight: FontWeight.w800)),
      ]),
      const SizedBox(height: 12),
      if (target > 7)
        LinearProgressIndicator(
            value: (goal.doneThisWeek / target).clamp(0, 1),
            minHeight: 8,
            color: goalPurple,
            backgroundColor: goalTint,
            borderRadius: BorderRadius.circular(99))
      else
        Row(children: [
          for (var i = 0; i < 7; i++) ...[
            if (i > 0) const SizedBox(width: 5),
            Expanded(
                child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        color: i < goal.doneThisWeek
                            ? goalPurple
                            : i < target
                                ? const Color(0xFFE8D5F6)
                                : const Color(0xFFF1F1F5)))),
          ]
        ]),
    ]);
  }
}
