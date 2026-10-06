import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';

class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  String _tab = 'Goals';
  List<BackendGoal> _serverGoals = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFromServer();
  }

  /// Goals tersimpan di server sehingga tidak hilang saat aplikasi ditutup.
  Future<void> _loadFromServer() async {
    final token = ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (mounted) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final goals = await ref
          .read(apiClientProvider)
          .listGoals(accessToken: token, includeInactive: true);
      if (!mounted) return;
      setState(() {
        _serverGoals = goals;
        _isLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  bool get _hasServer =>
      (ref.read(currentSessionProvider)?.accessToken ?? '').isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final storeState = ref.watch(malvaStoreProvider);
    final store = ref.read(malvaStoreProvider.notifier);
    final useServer = _hasServer;
    final localGoals = storeState.goals;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'goals_add_fab',
        onPressed: () => _openGoalForm(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientHeader(
            title: 'Goals & Habits',
            subtitle: 'Daily focus dan history',
            leading: IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SoftCard(
                  color: MalvaColors.seed,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Daily Progress',
                        style: TextStyle(
                          color: Colors.white70,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        useServer
                            ? '${_serverDonePercent()}% completed'
                            : '${storeState.completedGoalPercent}% completed',
                        style:
                            Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                      const SizedBox(height: 12),
                      ProgressStrip(
                        value: (useServer
                                ? _serverDonePercent()
                                : storeState.completedGoalPercent) /
                            100,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Center(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'Goals', label: Text('Goals')),
                      ButtonSegment(value: 'History', label: Text('History')),
                    ],
                    selected: {_tab},
                    onSelectionChanged: (s) => setState(() => _tab = s.first),
                  ),
                ),
                const SizedBox(height: 14),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Gagal memuat dari server: $_error',
                      style: const TextStyle(
                          fontSize: 12, color: MalvaColors.danger),
                    ),
                  ),
                if (useServer && _isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (_tab == 'History') ...[
                  if ((useServer ? _serverGoals : localGoals).isEmpty)
                    const EmptyState(
                      icon: Icons.history_rounded,
                      title: 'Belum ada history',
                      subtitle: 'Goals yang selesai akan tercatat di sini.',
                    )
                  else if (useServer)
                    for (final goal in _serverGoals) ...[
                      SoftCard(
                        child: Row(
                          children: [
                            Icon(
                              goal.doneThisWeek >= goal.targetPerWeek
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: goal.doneThisWeek >= goal.targetPerWeek
                                  ? MalvaColors.mint
                                  : Colors.black38,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(goal.title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900)),
                                  Text(
                                    '${goal.doneThisWeek}/${goal.targetPerWeek} minggu ini'
                                    '${goal.lastLoggedOn != null ? ' • terakhir ${goal.lastLoggedOn}' : ''}',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            StatusPill(
                              label: goal.doneThisWeek >= goal.targetPerWeek
                                  ? 'SELESAI'
                                  : 'Aktif',
                              color: goal.doneThisWeek >= goal.targetPerWeek
                                  ? MalvaColors.mint
                                  : MalvaColors.amber,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ]
                  else
                    for (final goal in localGoals) ...[
                      SoftCard(
                        child: Row(
                          children: [
                            Icon(
                              goal.completedToday
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked_rounded,
                              color: goal.completedToday
                                  ? MalvaColors.mint
                                  : Colors.black38,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(goal.title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900)),
                                  Text(
                                    '${goal.streakDays} hari streak',
                                    style:
                                        Theme.of(context).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            StatusPill(
                              label: goal.completedToday ? 'ACHIEVED' : 'Aktif',
                              color: goal.completedToday
                                  ? MalvaColors.mint
                                  : MalvaColors.amber,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                ] else ...[
                  const SectionLabel('Today focus'),
                  if (useServer) ...[
                    if (_serverGoals.isEmpty)
                      const EmptyState(
                        icon: Icons.flag_rounded,
                        title: 'Belum ada goal',
                        subtitle: 'Tekan + untuk menambah goal pertamamu. '
                            'Semua goal tersimpan permanen di server.',
                      )
                    else
                      for (final goal in _serverGoals) ...[
                        _ServerGoalCard(
                          goal: goal,
                          onToggle: () => _toggleServerGoal(goal),
                          onEdit: () =>
                              _openGoalForm(context, ref, serverGoal: goal),
                        ),
                        const SizedBox(height: 12),
                      ],
                  ] else
                    for (final goal in localGoals) ...[
                      _GoalCard(
                        goal: goal,
                        onToggle: () => store.toggleGoal(goal.id),
                        onEdit: () => _openGoalForm(context, ref, goal: goal),
                      ),
                      const SizedBox(height: 12),
                    ],
                ],
                const SizedBox(height: 70),
              ],
            ),
          ),
        ],
      ),
    );
  }

  int _serverDonePercent() {
    if (_serverGoals.isEmpty) return 0;
    final done = _serverGoals
        .where((g) => g.doneThisWeek >= g.targetPerWeek && g.targetPerWeek > 0)
        .length;
    return ((done / _serverGoals.length) * 100).round();
  }

  /// Centang habit hari ini (server) & update daftar.
  Future<void> _toggleServerGoal(BackendGoal goal) async {
    final token = ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) return;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final alreadyDone = goal.lastLoggedOn == today;
    try {
      await ref.read(apiClientProvider).logHabit(
            accessToken: token,
            goalId: goal.id,
            loggedOn: today,
            done: !alreadyDone,
          );
      await _loadFromServer();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }

  void _openGoalForm(BuildContext context, WidgetRef ref,
      {GoalItem? goal, BackendGoal? serverGoal}) {
    final useServer = serverGoal != null || _hasServer;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _GoalFormSheet(
        initialGoal: goal,
        initialServerGoal: serverGoal,
        serverMode: useServer,
        onSave: (savedGoal, serverForm) async {
          if (serverGoal != null || (_hasServer && serverForm != null)) {
            await _saveServerGoal(serverGoal, serverForm!);
          } else {
            ref.read(malvaStoreProvider.notifier).upsertGoal(savedGoal);
          }
          if (context.mounted) Navigator.pop(context);
        },
        onDelete: (goal == null && serverGoal == null)
            ? null
            : () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    icon: const Icon(Icons.delete_rounded,
                        color: MalvaColors.danger),
                    title: const Text('Hapus Goal?'),
                    content: const Text(
                        'Tindakan ini tidak dapat dibatalkan. Apakah Anda yakin ingin menghapus goal ini?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Batal'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: compactFilledButtonStyle.copyWith(
                          backgroundColor:
                              const WidgetStatePropertyAll(MalvaColors.danger),
                        ),
                        child: const Text('Hapus'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  if (serverGoal != null) {
                    await _deleteServerGoal(serverGoal);
                  } else if (goal != null) {
                    ref.read(malvaStoreProvider.notifier).deleteGoal(goal.id);
                  }
                  if (context.mounted) Navigator.pop(context);
                }
              },
      ),
    );
  }

  Future<void> _saveServerGoal(
      BackendGoal? existing, _ServerGoalForm form) async {
    final token = ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) return;
    final api = ref.read(apiClientProvider);
    try {
      if (existing == null) {
        await api.createGoal(
          accessToken: token,
          title: form.title,
          category: form.category,
          targetPerWeek: form.targetPerWeek,
        );
      } else {
        await api.updateGoal(
          accessToken: token,
          goalId: existing.id,
          title: form.title,
          category: form.category,
          targetPerWeek: form.targetPerWeek,
        );
      }
      await _loadFromServer();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Goal tersimpan di server.'),
            backgroundColor: MalvaColors.mint,
          ),
        );
      }
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }

  Future<void> _deleteServerGoal(BackendGoal goal) async {
    final token = ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      await ref
          .read(apiClientProvider)
          .deleteGoal(accessToken: token, goalId: goal.id);
      await _loadFromServer();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }
}

/// Data form goal versi server.
class _ServerGoalForm {
  const _ServerGoalForm({
    required this.title,
    required this.category,
    required this.targetPerWeek,
  });

  final String title;
  final String category;
  final int targetPerWeek;
}

/// Kartu goal versi server (tersimpan di database).
class _ServerGoalCard extends StatelessWidget {
  const _ServerGoalCard({
    required this.goal,
    required this.onToggle,
    required this.onEdit,
  });

  final BackendGoal goal;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final doneToday = goal.lastLoggedOn == today;
    return SoftCard(
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onToggle,
            child: CircleAvatar(
              radius: 28,
              backgroundColor: doneToday
                  ? MalvaColors.mint
                  : Colors.black.withValues(alpha: 0.06),
              child: Icon(
                doneToday
                    ? Icons.check_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: doneToday ? Colors.white : Colors.black38,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goal.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    decoration: doneToday ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${goal.category} • target ${goal.targetPerWeek}x/minggu'
                  '${doneToday ? ' • ✓ hari ini' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 5,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Container(
                        width: 22,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i < goal.doneThisWeek.clamp(0, 7)
                              ? MalvaColors.seed
                              : Colors.black12,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit goal',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded),
          ),
        ],
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({
    required this.goal,
    required this.onToggle,
    required this.onEdit,
  });

  final GoalItem goal;
  final VoidCallback onToggle;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final time =
        '${goal.reminder.hour.toString().padLeft(2, '0')}:${goal.reminder.minute.toString().padLeft(2, '0')}';

    return SoftCard(
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: onToggle,
            child: CircleAvatar(
              radius: 28,
              backgroundColor: goal.completedToday
                  ? Colors.green
                  : Colors.black.withValues(alpha: 0.06),
              child: Icon(
                goal.completedToday
                    ? Icons.check_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: goal.completedToday ? Colors.white : Colors.black38,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  goal.title,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    decoration:
                        goal.completedToday ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text('${goal.frequency} - reminder $time'),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 5,
                  children: [
                    for (var i = 0; i < 7; i++)
                      Container(
                        width: 22,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i < goal.streakDays.clamp(0, 7).toInt()
                              ? MalvaColors.seed
                              : Colors.black12,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Edit goal',
            onPressed: onEdit,
            icon: const Icon(Icons.edit_rounded),
          ),
        ],
      ),
    );
  }
}

class _GoalFormSheet extends StatefulWidget {
  const _GoalFormSheet({
    this.initialGoal,
    this.initialServerGoal,
    this.serverMode = false,
    required this.onSave,
    this.onDelete,
  });

  final GoalItem? initialGoal;
  final BackendGoal? initialServerGoal;
  final bool serverMode;

  /// Callback: (goal lokal, form server). Salah satu terisi sesuai mode.
  final void Function(GoalItem, _ServerGoalForm?) onSave;
  final VoidCallback? onDelete;

  @override
  State<_GoalFormSheet> createState() => _GoalFormSheetState();
}

class _GoalFormSheetState extends State<_GoalFormSheet> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late String _frequency;
  late TimeOfDay _reminder;
  late int _targetPerWeek;
  late String _category;

  bool get _isEditing =>
      widget.initialGoal != null || widget.initialServerGoal != null;

  @override
  void initState() {
    super.initState();
    final goal = widget.initialGoal;
    final serverGoal = widget.initialServerGoal;
    _title =
        TextEditingController(text: goal?.title ?? serverGoal?.title ?? '');
    _note = TextEditingController(text: goal?.note ?? '');
    _frequency = goal?.frequency ?? 'Harian';
    _reminder = goal?.reminder ?? const TimeOfDay(hour: 20, minute: 0);
    _targetPerWeek = serverGoal?.targetPerWeek ?? 3;
    _category = serverGoal?.category ?? 'general';
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  static const _categories = [
    ('general', 'Umum'),
    ('health', 'Kesehatan'),
    ('activity', 'Aktivitas'),
    ('sleep', 'Tidur'),
    ('social', 'Sosial'),
  ];

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, bottomInset + 18),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _isEditing ? 'Edit Goal' : 'New Goal',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Goal title'),
            ),
            const SizedBox(height: 10),
            if (widget.serverMode) ...[
              DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Kategori'),
                items: [
                  for (final (value, label) in _categories)
                    DropdownMenuItem(value: value, child: Text(label)),
                ],
                onChanged: (value) =>
                    setState(() => _category = value ?? _category),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Expanded(
                    child: Text('Target per minggu',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  IconButton(
                    onPressed: _targetPerWeek > 1
                        ? () => setState(() => _targetPerWeek--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline_rounded),
                  ),
                  Text('$_targetPerWeek',
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 18)),
                  IconButton(
                    onPressed: _targetPerWeek < 7
                        ? () => setState(() => _targetPerWeek++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
            ] else ...[
              DropdownButtonFormField<String>(
                initialValue: _frequency,
                decoration: const InputDecoration(labelText: 'Frequency'),
                items: const [
                  DropdownMenuItem(value: 'Harian', child: Text('Harian')),
                  DropdownMenuItem(value: 'Mingguan', child: Text('Mingguan')),
                  DropdownMenuItem(
                      value: 'Sesuai sesi', child: Text('Sesuai sesi')),
                ],
                onChanged: (value) =>
                    setState(() => _frequency = value ?? _frequency),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _pickTime,
                icon: const Icon(Icons.schedule_rounded),
                label: Text(
                  'Reminder ${_reminder.hour.toString().padLeft(2, '0')}:${_reminder.minute.toString().padLeft(2, '0')}',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _note,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Note'),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _save,
              child: Text(_isEditing ? 'Save Goal' : 'Create Goal'),
            ),
            if (widget.onDelete != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_rounded),
                label: const Text('Delete Goal'),
                style:
                    TextButton.styleFrom(foregroundColor: MalvaColors.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked =
        await showTimePicker(context: context, initialTime: _reminder);
    if (picked != null) setState(() => _reminder = picked);
  }

  void _save() {
    final existingGoal = widget.initialGoal;
    final title = _title.text.trim().isEmpty ? 'Goal baru' : _title.text.trim();
    widget.onSave(
      GoalItem(
        id: existingGoal?.id ?? 'goal_${DateTime.now().millisecondsSinceEpoch}',
        title: title,
        frequency: _frequency,
        streakDays: existingGoal?.streakDays ?? 0,
        completedToday: existingGoal?.completedToday ?? false,
        reminder: _reminder,
        note: _note.text.trim(),
      ),
      widget.serverMode
          ? _ServerGoalForm(
              title: title,
              category: _category,
              targetPerWeek: _targetPerWeek,
            )
          : null,
    );
  }
}
