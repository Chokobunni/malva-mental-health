import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../models/goal_details.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../time/wib.dart';
import '../widgets/friendly_error.dart';
import 'goals/goal_editor.dart';
import 'goals/goal_reference_widgets.dart';

class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key, this.now = wibNow});
  final DateTime Function() now;
  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen>
    with WidgetsBindingObserver {
  List<BackendGoal> _serverGoals = const [];
  bool _loading = true, _mutating = false, _ownerChanged = false;
  String? _error;
  String _filter = 'all';
  late String _selectedDate, _today, _screenOwner;
  int _loadRequest = 0;
  Timer? _midnight;

  String _ownerKey(AuthSession? session) =>
      '${session?.role.name}:${session?.backendUserId ?? session?.identifier ?? ''}';
  bool get _current =>
      mounted &&
      !_ownerChanged &&
      _screenOwner == _ownerKey(ref.read(currentSessionProvider));
  bool get _server =>
      (ref.read(currentSessionProvider)?.accessToken ?? '').isNotEmpty;

  @override
  void initState() {
    super.initState();
    _today = _selectedDate = wibDateKey(widget.now());
    _screenOwner = _ownerKey(ref.read(currentSessionProvider));
    ref.listenManual<AuthSession?>(currentSessionProvider, (_, session) {
      if (_ownerKey(session) != _screenOwner) {
        _ownerChanged = true;
        _loadRequest++;
      }
    });
    WidgetsBinding.instance.addObserver(this);
    _scheduleMidnight();
    unawaited(_load());
  }

  @override
  void dispose() {
    _midnight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _rollDate();
      unawaited(_load());
    }
  }

  void _rollDate() {
    final next = wibDateKey(widget.now());
    if (_selectedDate == _today && _selectedDate != next) {
      _selectedDate = next;
      _serverGoals = const [];
    }
    _today = next;
  }

  void _scheduleMidnight() {
    final now = widget.now();
    _midnight = Timer(
        wibFromParts(now.year, now.month, now.day + 1).difference(now), () {
      if (!_current) return;
      _rollDate();
      unawaited(_load());
      _scheduleMidnight();
    });
  }

  Future<void> _load() async {
    if (!_current) return;
    final generation = ++_loadRequest;
    final token = ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    final date = _selectedDate;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final goals = await ref
          .read(apiClientProvider)
          .listGoals(accessToken: token, includeInactive: true, on: date);
      if (!_current || generation != _loadRequest) return;
      setState(() {
        _serverGoals = goals;
        _loading = false;
      });
    } on Object catch (e) {
      if (!_current || generation != _loadRequest) return;
      setState(() {
        _error = friendlyErrorMessage(e);
        _loading = false;
      });
      if (_serverGoals.isNotEmpty) _showError(e);
    }
  }

  BackendGoal _fromLocal(GoalItem g) => BackendGoal(
      id: g.id,
      title: g.title,
      category: 'general',
      targetPerWeek: 3,
      isActive: true,
      details: g.details ??
          GoalDetails(
              startDate: _today,
              note: g.note,
              time:
                  '${g.reminder.hour.toString().padLeft(2, '0')}:${g.reminder.minute.toString().padLeft(2, '0')}',
              recurrence: switch (g.frequency) {
                'Mingguan' => 'weekly',
                'Bulanan' => 'monthly',
                _ => 'daily'
              }),
      doneToday: g.completedToday,
      todayValue: g.value,
      todayCompletedStepIds: g.completedStepIds,
      streakDays: g.streakDays);

  bool _done(BackendGoal goal) =>
      goal.doneToday ?? (goal.lastLoggedOn == _selectedDate);

  @override
  Widget build(BuildContext context) {
    ref.watch(currentSessionProvider);
    ref.listen<int>(clinicalDataRevisionProvider, (_, __) {
      if (!_mutating) unawaited(_load());
    });
    if (!_current)
      return const Scaffold(
          body: Center(
              child: Text('Sesi akun telah berubah. Buka kembali Goals.')));
    final local = ref.watch(malvaStoreProvider).goals;
    final all = _server ? _serverGoals : local.map(_fromLocal).toList();
    final goals =
        all.where((g) => g.isActive || _selectedDate != _today).toList();
    final due = goals.where((g) => g.isActive && g.isDue).toList();
    final completed = due.where(_done).length;
    final ratio = due.isEmpty ? 0.0 : completed / due.length;
    final streak =
        goals.fold<int>(0, (n, g) => g.streakDays > n ? g.streakDays : n);
    final filtered = goals
        .where((g) =>
            _filter == 'all' || (g.details?.method ?? 'yes_no') == _filter)
        .toList();
    return Scaffold(
        backgroundColor: goalPaper,
        body: RefreshIndicator(
            onRefresh: _load,
            child: SingleChildScrollView(
                key: const Key('goals-scroll'),
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                    key: const Key('goal-list-content'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                          decoration: const BoxDecoration(
                              gradient: LinearGradient(colors: [
                                Color(0xFF5B216F),
                                Color(0xFF9D3BAF),
                                Color(0xFFD980E7)
                              ]),
                              borderRadius: BorderRadius.vertical(
                                  bottom: Radius.circular(28))),
                          child: SafeArea(
                              bottom: false,
                              child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(14, 23, 20, 32),
                                  child: Row(children: [
                                    IconButton(
                                        onPressed: () =>
                                            Navigator.maybePop(context),
                                        tooltip: 'Kembali',
                                        icon: const Icon(
                                            Icons.arrow_back_rounded,
                                            color: Colors.white,
                                            size: 23)),
                                    const SizedBox(width: 4),
                                    const Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text('Goals & Habits',
                                              style: TextStyle(
                                                  fontFamily: 'PlusJakartaSans',
                                                  color: Colors.white,
                                                  fontSize: 26,
                                                  height: 1.2,
                                                  fontWeight: FontWeight.w700,
                                                  letterSpacing: -.6)),
                                          SizedBox(height: 2),
                                          Text('Daily focus dan history',
                                              style: TextStyle(
                                                  fontFamily: 'PlusJakartaSans',
                                                  color: Colors.white70,
                                                  fontSize: 13,
                                                  height: 1.2)),
                                        ])),
                                    const SizedBox(width: 8),
                                    TextButton.icon(
                                        onPressed:
                                            _mutating ? null : () => _edit(),
                                        style: TextButton.styleFrom(
                                            foregroundColor: Colors.white,
                                            backgroundColor: Colors.white
                                                .withValues(alpha: .18),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 14),
                                            minimumSize: const Size(0, 38)),
                                        icon: const Icon(Icons.add, size: 20),
                                        label: const Text('Baru',
                                            style: TextStyle(
                                                fontFamily: 'PlusJakartaSans',
                                                fontSize: 14))),
                                  ])))),
                      Center(
                          child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 600),
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 20, vertical: 20),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        GoalSurface(
                                            color: const Color(0xFFF3E9FB),
                                            border: const Color(0xFFE8DAF2),
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(children: [
                                                    Expanded(
                                                        flex: 57,
                                                        child: InkWell(
                                                            onTap: _mutating
                                                                ? null
                                                                : _selectDate,
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        99),
                                                            child: GoalPill(
                                                                '${const [
                                                                  'Senin',
                                                                  'Selasa',
                                                                  'Rabu',
                                                                  'Kamis',
                                                                  'Jumat',
                                                                  'Sabtu',
                                                                  'Minggu'
                                                                ][DateTime.parse(_selectedDate).weekday - 1]}, ${goalDateLabel(_selectedDate)}',
                                                                icon: Icons
                                                                    .calendar_today_outlined,
                                                                background:
                                                                    Colors
                                                                        .white,
                                                                fontSize: 12,
                                                                verticalPadding:
                                                                    6))),
                                                    Expanded(
                                                        flex: 43,
                                                        child: GoalPill(
                                                            '$streak Hari Beruntun',
                                                            icon: Icons
                                                                .local_fire_department_rounded,
                                                            color: const Color(
                                                                0xFFC68722),
                                                            background:
                                                                const Color(
                                                                    0xFFFFF2CC),
                                                            fontSize: 12,
                                                            verticalPadding:
                                                                6)),
                                                  ]),
                                                  const SizedBox(height: 20),
                                                  Row(children: [
                                                    Expanded(
                                                        child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                          const Text(
                                                              'Capaian Kebiasaanmu',
                                                              style: TextStyle(
                                                                  fontFamily:
                                                                      'PlusJakartaSans',
                                                                  fontSize: 17,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w700,
                                                                  color:
                                                                      goalInk)),
                                                          const SizedBox(
                                                              height: 3),
                                                          Text(
                                                              '$completed dari ${due.length} target ${_selectedDate == _today ? 'hari ini' : 'pada tanggal ini'} telah selesai',
                                                              style: const TextStyle(
                                                                  fontFamily:
                                                                      'PlusJakartaSans',
                                                                  fontSize: 13,
                                                                  color: Color(
                                                                      0xFF7F8792))),
                                                        ])),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                        '${(ratio * 100).round()}%',
                                                        style: const TextStyle(
                                                            fontFamily:
                                                                'PlusJakartaSans',
                                                            color: goalPurple,
                                                            fontWeight:
                                                                FontWeight.w800,
                                                            fontSize: 21))
                                                  ]),
                                                  const SizedBox(height: 14),
                                                  ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              99),
                                                      child: LinearProgressIndicator(
                                                          value: ratio,
                                                          minHeight: 7,
                                                          backgroundColor:
                                                              Colors.white,
                                                          color: goalPurple,
                                                          borderRadius:
                                                              BorderRadius
                                                                  .circular(
                                                                      99))),
                                                ])),
                                        const SizedBox(height: 20),
                                        SingleChildScrollView(
                                            scrollDirection: Axis.horizontal,
                                            child: Row(children: [
                                              for (final method in [
                                                'all',
                                                'yes_no',
                                                'numeric',
                                                'checklist'
                                              ]) ...[
                                                if (method != 'all')
                                                  const SizedBox(width: 7),
                                                ChoiceChip(
                                                    materialTapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap,
                                                    key: Key(
                                                        'goal-filter-$method'),
                                                    showCheckmark: false,
                                                    selected: _filter == method,
                                                    onSelected: (_) => setState(
                                                        () => _filter = method),
                                                    backgroundColor:
                                                        Colors.white,
                                                    selectedColor: goalPurple,
                                                    side: BorderSide(
                                                        color: _filter == method
                                                            ? goalPurple
                                                            : const Color(
                                                                0xFFE3E3E8)),
                                                    shape:
                                                        const StadiumBorder(),
                                                    padding: const EdgeInsets
                                                        .symmetric(
                                                        horizontal: 8,
                                                        vertical: 5),
                                                    label: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          if (method !=
                                                              'all') ...[
                                                            Icon(
                                                                goalMethodIcon(
                                                                    method),
                                                                size: 13,
                                                                color: _filter ==
                                                                        method
                                                                    ? Colors
                                                                        .white
                                                                    : method ==
                                                                            'numeric'
                                                                        ? const Color(
                                                                            0xFFD4A12E)
                                                                        : goalPurple),
                                                            const SizedBox(
                                                                width: 5)
                                                          ],
                                                          Text(
                                                              method == 'all'
                                                                  ? 'Semua ( ${goals.length} )'
                                                                  : goalMethodLabel(
                                                                      method),
                                                              style: TextStyle(
                                                                  fontFamily:
                                                                      'PlusJakartaSans',
                                                                  color: _filter ==
                                                                          method
                                                                      ? Colors
                                                                          .white
                                                                      : const Color(
                                                                          0xFF53606D),
                                                                  fontSize: 13,
                                                                  fontWeight: _filter ==
                                                                          method
                                                                      ? FontWeight
                                                                          .w700
                                                                      : FontWeight
                                                                          .w500)),
                                                        ])),
                                              ]
                                            ])),
                                        const SizedBox(height: 26),
                                        if (_error != null &&
                                            _serverGoals.isEmpty)
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 14),
                                              child: Column(children: [
                                                Text(
                                                    'Gagal memuat dari server: $_error',
                                                    style: TextStyle(
                                                        fontFamily:
                                                            'PlusJakartaSans',
                                                        color: Theme.of(context)
                                                            .colorScheme
                                                            .error)),
                                                TextButton(
                                                    onPressed: _load,
                                                    child:
                                                        const Text('Coba lagi'))
                                              ])),
                                        if (_loading && _serverGoals.isEmpty)
                                          const Center(
                                              child: CircularProgressIndicator(
                                                  color: goalPurple))
                                        else if (filtered.isEmpty)
                                          Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 30),
                                              child: Text(
                                                  goals.isEmpty
                                                      ? 'Belum ada target atau kebiasaan.\nMulai dari satu langkah kecil hari ini.'
                                                      : 'Belum ada kebiasaan dengan metode ini.',
                                                  textAlign: TextAlign.center,
                                                  style: const TextStyle(
                                                      fontFamily:
                                                          'PlusJakartaSans',
                                                      color: goalMuted,
                                                      fontSize: 15)))
                                        else
                                          for (final goal in filtered) ...[
                                            _card(goal),
                                            const SizedBox(height: 14),
                                          ],
                                        const SizedBox(height: 22),
                                        GoalButton(
                                            'Tambah Target / Kebiasaan Baru',
                                            icon: Icons.add_circle_outline,
                                            primary: true,
                                            onPressed: _mutating
                                                ? null
                                                : () => _edit()),
                                        const SizedBox(height: 6),
                                      ])))),
                    ]))));
  }

  Widget _card(BackendGoal goal) {
    final method = goal.details?.method ?? 'yes_no';
    final done = _done(goal);
    final configured = goal.details;
    final locked = _mutating ||
        !goal.isActive ||
        !goal.isDue ||
        _selectedDate.compareTo(_today) > 0 ||
        (configured?.lockPast == true &&
            _selectedDate.compareTo(wibDateKey(
                    widget.now().subtract(const Duration(days: 1)))) <
                0);
    final badgeColor = method == 'numeric'
        ? const Color(0xFFA66A1D)
        : method == 'checklist'
            ? const Color(0xFFAB356E)
            : goalPurple;
    final badgeBg = method == 'numeric'
        ? const Color(0xFFFFF2C5)
        : method == 'checklist'
            ? const Color(0xFFFBE6F0)
            : const Color(0xFFF4EBF7);
    return GoalSurface(
        key: ValueKey(goal.id),
        color: done ? const Color(0xFFFCF8FF) : Colors.white,
        border: done ? const Color(0xFFD4BADF) : goalLine,
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
                child: Wrap(spacing: 8, runSpacing: 5, children: [
              GoalPill(goalMethodLabel(method).toUpperCase(),
                  icon: goalMethodIcon(method),
                  color: badgeColor,
                  background: badgeBg,
                  fontSize: 10,
                  verticalPadding: 3),
              if (goal.streakDays > 0)
                GoalPill('${goal.streakDays} hari',
                    icon: Icons.local_fire_department_rounded,
                    color: const Color(0xFFC68D26),
                    background: const Color(0xFFFFF9E5),
                    fontSize: 10,
                    verticalPadding: 3),
              if (!goal.isActive) const GoalPill('Nonaktif'),
            ])),
            SizedBox(
                width: 32,
                height: 22,
                child: IconButton(
                    tooltip: 'Edit goal',
                    onPressed: _mutating ? null : () => _edit(goal),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.edit_outlined,
                        size: 17, color: goalMuted))),
            SizedBox(
                width: 30,
                height: 22,
                child: IconButton(
                    tooltip: 'Hapus goal',
                    onPressed: _mutating ? null : () => _delete(goal),
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.delete_outline,
                        size: 17, color: goalMuted))),
          ]),
          const SizedBox(height: 4),
          Text(goal.title,
              style: TextStyle(
                fontFamily: 'PlusJakartaSans',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.3,
                color: done ? goalMuted : goalInk,
                decoration: done ? TextDecoration.lineThrough : null,
                decorationThickness: done ? 1.5 : null,
              )),
          if ((configured?.note ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(configured!.note,
                style: const TextStyle(
                    fontFamily: 'PlusJakartaSans',
                    fontSize: 12.5,
                    height: 1.6,
                    color: Color(0xFF76818D))),
          ],
          if (method != 'checklist') ...[
            const SizedBox(height: 14),
            _habitSchedule(goal),
          ],
          if (!goal.isDue)
            const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text('Tidak dijadwalkan pada tanggal ini',
                    style: TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        color: goalMuted,
                        fontSize: 12))),
          const SizedBox(height: 12),
          if (method == 'numeric')
            GoalSurface(
                color: const Color(0xFFFAF3FD),
                border: const Color(0xFFF0E7F5),
                radius: 13,
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  Row(children: [
                    Expanded(
                        child: Text.rich(
                            TextSpan(children: [
                              const TextSpan(text: 'Progres: '),
                              TextSpan(
                                  text: '${goal.todayValue}',
                                  style: const TextStyle(
                                      fontFamily: 'PlusJakartaSans',
                                      color: goalPurple)),
                              TextSpan(
                                  text:
                                      ' / ${configured!.target} ${configured.unit}')
                            ]),
                            style: const TextStyle(
                                fontFamily: 'PlusJakartaSans',
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF424C59)))),
                    _progressButton(goal, false, locked),
                    const SizedBox(width: 6),
                    _progressButton(goal, true, locked)
                  ]),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                      value: (goal.todayValue / configured.target).clamp(0, 1),
                      minHeight: 8,
                      color: goalPurple,
                      backgroundColor: Colors.white,
                      borderRadius: BorderRadius.circular(99)),
                ]))
          else if (method == 'checklist')
            GoalSurface(
                color: const Color(0xFFF9F3FC),
                border: const Color(0xFFF0E7F5),
                radius: 13,
                padding: const EdgeInsets.fromLTRB(12, 14, 10, 10),
                child: Column(children: [
                  Row(children: [
                    const Expanded(
                        child: Text('Daftar Langkah',
                            style: TextStyle(
                                fontFamily: 'PlusJakartaSans',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF53606D)))),
                    Text(
                        '${goal.todayCompletedStepIds.where((id) => configured!.steps.any((s) => s.id == id)).length}/${configured!.steps.length} selesai',
                        style: const TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 12,
                            color: goalPurple,
                            fontWeight: FontWeight.w700))
                  ]),
                  const SizedBox(height: 6),
                  for (final step in configured.steps)
                    InkWell(
                        onTap: locked
                            ? null
                            : () => _log(goal, steps: [
                                  for (final id in goal.todayCompletedStepIds)
                                    if (id != step.id) id,
                                  if (!goal.todayCompletedStepIds
                                      .contains(step.id))
                                    step.id,
                                ]),
                        child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(children: [
                              SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: Transform.scale(
                                      scale: .75,
                                      child: Checkbox(
                                          visualDensity: VisualDensity.compact,
                                          activeColor: goalPurple,
                                          fillColor:
                                              WidgetStateProperty.resolveWith(
                                                  (states) => states.contains(
                                                          WidgetState.selected)
                                                      ? goalPurple
                                                      : const Color(
                                                          0xFFD8B2EE)),
                                          side: BorderSide.none,
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(1)),
                                          value: goal.todayCompletedStepIds
                                              .contains(step.id),
                                          onChanged: locked
                                              ? null
                                              : (checked) => _log(goal, steps: [
                                                    for (final id in goal
                                                        .todayCompletedStepIds)
                                                      if (id != step.id) id,
                                                    if (checked == true)
                                                      step.id,
                                                  ])))),
                              const SizedBox(width: 4),
                              Expanded(
                                  child: Text(step.label,
                                      style: TextStyle(
                                          fontFamily: 'PlusJakartaSans',
                                          fontSize: 12.5,
                                          height: 1.5,
                                          color: goal.todayCompletedStepIds
                                                  .contains(step.id)
                                              ? goalMuted
                                              : goalInk,
                                          decoration: goal.todayCompletedStepIds
                                                  .contains(step.id)
                                              ? TextDecoration.lineThrough
                                              : null))),
                            ]))),
                ]))
          else ...[
            const Divider(color: Color(0xFFF1EDF5), height: 1),
            const SizedBox(height: 10),
            Row(children: [
              if (done) ...[
                const Icon(Icons.auto_awesome,
                    size: 12, color: Color(0xFFE0BC48)),
                const SizedBox(width: 3),
              ],
              Expanded(
                  child: Text(
                      done
                          ? 'Ya, selesai ${_selectedDate == _today ? 'hari ini' : 'pada tanggal ini'}'
                          : goal.failedToday
                              ? 'Belum tercapai'
                              : 'Sudah dilakukan?',
                      style: const TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 11,
                          color: goalPurple))),
              _yesNo(goal, true, done, locked),
              const SizedBox(width: 6),
              _yesNo(goal, false, done, locked)
            ]),
          ],
        ]));
  }

  Widget _habitSchedule(BackendGoal goal) {
    if (!goal.weeklyProgressAvailable) {
      return const Text('Riwayat mingguan belum dapat dimuat',
          style: TextStyle(
              fontFamily: 'PlusJakartaSans', fontSize: 11.5, color: goalMuted));
    }
    final details = goal.details;
    if (details?.recurrence == 'weekly' && details?.weeklyTarget == null) {
      final selected = DateTime.parse(_selectedDate);
      final monday = wibFromParts(
          selected.year, selected.month, selected.day - selected.weekday + 1);
      return Column(children: [
        Row(children: [
          Expanded(
              child: Text('Hari terpilih (${details!.weekdays.length}×/minggu)',
                  style: const TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 11.5,
                      color: goalMuted))),
          Text(
              _done(goal)
                  ? 'Selesai ${_selectedDate == _today ? 'hari ini' : 'pada tanggal ini'}'
                  : goal.isDue
                      ? 'Jadwal ${_selectedDate == _today ? 'hari ini' : 'tanggal ini'}'
                      : 'Di luar jadwal',
              style: TextStyle(
                  fontFamily: 'PlusJakartaSans',
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _done(goal) ? const Color(0xFF288873) : goalPurple)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          for (var day = 1; day <= 7; day++) ...[
            if (day > 1) const SizedBox(width: 6),
            Expanded(child: Builder(builder: (_) {
              final date =
                  wibFromParts(monday.year, monday.month, monday.day + day - 1);
              final scheduled = details.isDueOn(date);
              final completed = goal.completedWeekdays.contains(day);
              final current = selected.weekday == day;
              return Container(
                  constraints: const BoxConstraints(minHeight: 41),
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                      color: completed
                          ? goalPurple
                          : scheduled
                              ? goalTint
                              : const Color(0xFFF8F9FB),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(
                          color: current
                              ? goalPurple
                              : scheduled
                                  ? const Color(0xFFE8D9EF)
                                  : const Color(0xFFF0F1F5)),
                      boxShadow: current
                          ? const [
                              BoxShadow(
                                  color: Color(0xFFEBDCF2), spreadRadius: 2)
                            ]
                          : []),
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
                            fontFamily: 'PlusJakartaSans',
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: completed
                                ? Colors.white
                                : scheduled
                                    ? goalPurple
                                    : const Color(0xFFC9CFD7))),
                    SizedBox(
                        height: 10,
                        child: completed
                            ? const Icon(Icons.check,
                                size: 11, color: Colors.white)
                            : current
                                ? const Icon(Icons.circle,
                                    size: 4, color: goalPurple)
                                : null),
                  ]));
            })),
          ]
        ]),
      ]);
    }
    if (details == null ||
        details.recurrence == 'weekly' ||
        (details.method == 'yes_no' && details.recurrence == 'daily')) {
      final target = details?.weeklyTarget ?? goal.targetPerWeek;
      return Column(children: [
        Row(children: [
          const Expanded(
              child: Text('Minggu ini',
                  style: TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 11.5,
                      color: goalMuted))),
          Text(
              target == 0
                  ? '${goal.doneThisWeek} kali'
                  : '${goal.doneThisWeek}/$target kali',
              style: const TextStyle(
                  fontFamily: 'PlusJakartaSans',
                  fontSize: 11.5,
                  color: goalPurple,
                  fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          for (var i = 0; i < 7; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
                child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(99),
                        color: i < goal.doneThisWeek
                            ? goalPurple
                            : i < target
                                ? const Color(0xFFE8D5F6)
                                : const Color(0xFFF1F4F7)))),
          ]
        ]),
      ]);
    }
    return Text(details.scheduleLabel,
        style: const TextStyle(
            fontFamily: 'PlusJakartaSans',
            fontSize: 11.5,
            color: goalPurple,
            height: 1.4));
  }

  Widget _yesNo(BackendGoal goal, bool yes, bool done, bool locked) => SizedBox(
      height: 32,
      child: FilledButton.icon(
          onPressed: locked ? null : () => _log(goal, done: yes),
          style: FilledButton.styleFrom(
              minimumSize: const Size(0, 32),
              backgroundColor: (yes ? done : goal.failedToday)
                  ? goalPurple
                  : const Color(0xFFF0F3F7),
              foregroundColor: (yes ? done : goal.failedToday)
                  ? Colors.white
                  : const Color(0xFF6A7785),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(13)),
              textStyle: const TextStyle(
                  fontFamily: 'PlusJakartaSans',
                  fontSize: 12,
                  fontWeight: FontWeight.w700)),
          icon: Icon(yes ? Icons.check : Icons.close, size: 14),
          label: Text(yes ? 'Ya' : 'Tidak')));

  Widget _progressButton(BackendGoal goal, bool add, bool locked) => SizedBox(
      width: 30,
      height: 30,
      child: IconButton(
          tooltip: add
              ? 'Tambah progres ${goal.title}'
              : 'Kurangi progres ${goal.title}',
          onPressed: locked ||
                  (!add && goal.todayValue <= 0) ||
                  (add && goal.todayValue >= 1000000)
              ? null
              : () => _log(goal, value: goal.todayValue + (add ? 1 : -1)),
          style: IconButton.styleFrom(
              backgroundColor: add ? goalPurple : Colors.white,
              foregroundColor: add ? Colors.white : goalPurple,
              side: add
                  ? BorderSide.none
                  : const BorderSide(color: Color(0xFFE5D5EB)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9)),
              padding: EdgeInsets.zero),
          icon: Icon(add ? Icons.add : Icons.remove, size: 16)));

  Future<void> _log(BackendGoal goal,
      {bool? done, int? value, List<String>? steps}) async {
    if (!_current || _mutating) return;
    // Logs retain historical IDs after a definition edit. Only current steps
    // may be submitted again, including when a historical-date reload failed.
    final currentIds = goal.details?.steps.map((step) => step.id).toSet() ?? {};
    steps = steps?.where(currentIds.contains).toSet().toList();
    setState(() => _mutating = true);
    try {
      if (_server) {
        final token = ref.read(currentSessionProvider)!.accessToken!;
        final date = _selectedDate;
        final log = await ref.read(apiClientProvider).logHabit(
            accessToken: token,
            goalId: goal.id,
            loggedOn: date,
            done: done ?? false,
            value: value,
            completedStepIds: steps);
        if (_current) {
          if (date == _selectedDate) {
            setState(() => _serverGoals = [
                  for (final g in _serverGoals)
                    g.id == goal.id ? g.withProgress(log) : g
                ]);
          }
          if (date == _today) {
            ref.read(acceptedGoalMutationProvider.notifier).state =
                GoalReminderMutation.upsert(
                    ref.read(currentSessionProvider)!, goal.withProgress(log));
          }
          ref.read(clinicalDataRevisionProvider.notifier).state++;
          await _load();
        }
      } else {
        final local = ref
            .read(malvaStoreProvider)
            .goals
            .firstWhere((g) => g.id == goal.id);
        final nextValue = value ?? local.value;
        final nextSteps = steps ?? local.completedStepIds;
        final completed = switch (goal.details?.method) {
          'numeric' => nextValue >= goal.details!.target,
          'checklist' =>
            goal.details!.steps.every((s) => nextSteps.contains(s.id)),
          _ => done ?? false,
        };
        ref.read(malvaStoreProvider.notifier).upsertGoal(local.copyWith(
            completedToday: completed,
            value: nextValue,
            completedStepIds: nextSteps));
      }
    } on Object catch (e) {
      if (_current) _showError(e);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  Future<void> _edit([BackendGoal? goal]) async {
    if (!_current || _mutating) return;
    final useServer = _server;
    final createKey = 'patient_goal_${wibNow().microsecondsSinceEpoch}';
    await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => Consumer(builder: (context, ref, _) {
              ref.watch(currentSessionProvider);
              if (!_current)
                return const Scaffold(
                    body: Center(
                        child: Text(
                            'Sesi akun telah berubah. Buka kembali Goals.')));
              return GoalEditor(
                  goal: goal,
                  onSave: (result) async {
                    if (!_current || _mutating) return false;
                    setState(() => _mutating = true);
                    try {
                      if (useServer) {
                        final api = ref.read(apiClientProvider),
                            token =
                                ref.read(currentSessionProvider)!.accessToken!;
                        final saved = goal == null
                            ? await api.createGoal(
                                accessToken: token,
                                title: result.title,
                                targetPerWeek: 7,
                                idempotencyKey: createKey,
                                details: result.details)
                            : await api.updateGoal(
                                accessToken: token,
                                goalId: goal.id,
                                title: result.title,
                                details: result.details);
                        if (!_current) return false;
                        setState(() => _serverGoals = [
                              if (goal == null) ..._serverGoals,
                              if (goal == null)
                                _selectedDate == _today
                                    ? saved
                                    : BackendGoal(
                                        id: saved.id,
                                        title: saved.title,
                                        category: saved.category,
                                        targetPerWeek: saved.targetPerWeek,
                                        isActive: saved.isActive,
                                      ).withDefinition(saved,
                                        on: DateTime.parse(_selectedDate)),
                              if (goal != null)
                                for (final g in _serverGoals)
                                  g.id == goal.id
                                      ? g.withDefinition(saved,
                                          on: DateTime.parse(_selectedDate))
                                      : g
                            ]);
                        ref.read(acceptedGoalMutationProvider.notifier).state =
                            GoalReminderMutation.upsert(
                                ref.read(currentSessionProvider)!, saved);
                        ref.read(clinicalDataRevisionProvider.notifier).state++;
                        await _load();
                      } else {
                        final existing = ref
                            .read(malvaStoreProvider)
                            .goals
                            .where((g) => g.id == goal?.id)
                            .firstOrNull;
                        final parts = result.details.time.split(':');
                        ref.read(malvaStoreProvider.notifier).upsertGoal(
                            GoalItem(
                                id: goal?.id ??
                                    'goal_${wibNow().microsecondsSinceEpoch}',
                                title: result.title,
                                frequency: switch (result.details.recurrence) {
                                  'daily' => 'Harian',
                                  'monthly' => 'Bulanan',
                                  _ => 'Mingguan'
                                },
                                streakDays: existing?.streakDays ?? 0,
                                completedToday:
                                    existing?.completedToday ?? false,
                                reminder: parts.length == 2
                                    ? TimeOfDay(
                                        hour: int.parse(parts[0]),
                                        minute: int.parse(parts[1]))
                                    : const TimeOfDay(hour: 19, minute: 0),
                                note: result.details.note,
                                details: result.details,
                                value: existing?.value ?? 0,
                                completedStepIds:
                                    existing?.completedStepIds ?? const []));
                      }
                      return _current;
                    } finally {
                      if (mounted) setState(() => _mutating = false);
                    }
                  });
            })));
  }

  Future<void> _delete(BackendGoal goal) async {
    if (!_current || _mutating) return;
    setState(() => _mutating = true);
    try {
      final confirm = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                  title: const Text('Hapus Goal?'),
                  content: const Text(
                      'Tindakan ini tidak dapat dibatalkan. Apakah Anda yakin ingin menghapus goal ini?'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Batal')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Hapus'))
                  ]));
      if (confirm != true || !_current) return;
      if (_server) {
        await ref.read(apiClientProvider).deleteGoal(
            accessToken: ref.read(currentSessionProvider)!.accessToken!,
            goalId: goal.id);
        if (!_current) return;
        setState(() =>
            _serverGoals = _serverGoals.where((g) => g.id != goal.id).toList());
        ref.read(acceptedGoalMutationProvider.notifier).state =
            GoalReminderMutation.delete(
                ref.read(currentSessionProvider)!, goal.id);
        ref.read(clinicalDataRevisionProvider.notifier).state++;
        await _load();
      } else {
        ref.read(malvaStoreProvider.notifier).deleteGoal(goal.id);
      }
    } on Object catch (e) {
      if (_current) _showError(e);
    } finally {
      if (mounted) setState(() => _mutating = false);
    }
  }

  void _showError(Object error) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(friendlyErrorMessage(error)),
          backgroundColor: Theme.of(context).colorScheme.error));

  Future<void> _selectDate() async {
    final date = DateTime.parse(_selectedDate), now = widget.now();
    final selected = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year, now.month, now.day),
        helpText: 'Riwayat kebiasaan (WIB)');
    if (selected == null || !_current) return;
    setState(() {
      _selectedDate =
          wibDateKey(wibFromParts(selected.year, selected.month, selected.day));
      _serverGoals = const [];
    });
    await _load();
  }
}
