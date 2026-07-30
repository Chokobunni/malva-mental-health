import 'package:flutter/material.dart';

import '../models.dart';
import '../store/malva_store.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';

class GoalsScreen extends StatelessWidget {
  const GoalsScreen({super.key, required this.store});

  final MalvaStore store;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        return Scaffold(
          floatingActionButton: FloatingActionButton(
            heroTag: 'goals_add_fab',
            onPressed: () => _openGoalForm(context),
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
                  icon:
                      const Icon(Icons.arrow_back_rounded, color: Colors.white),
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
                            '${store.completedGoalPercent}% completed',
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const SizedBox(height: 12),
                          ProgressStrip(
                            value: store.completedGoalPercent / 100,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    const SectionLabel('Today focus'),
                    for (final goal in store.goals) ...[
                      _GoalCard(
                        goal: goal,
                        onToggle: () => store.toggleGoal(goal.id),
                        onEdit: () => _openGoalForm(context, goal: goal),
                      ),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 70),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openGoalForm(BuildContext context, {GoalItem? goal}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _GoalFormSheet(
        initialGoal: goal,
        onSave: (savedGoal) {
          store.upsertGoal(savedGoal);
          Navigator.pop(context);
        },
        onDelete: goal == null
            ? null
            : () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    icon: const Icon(Icons.delete_rounded, color: MalvaColors.danger),
                    title: const Text('Hapus Goal?'),
                    content: const Text('Tindakan ini tidak dapat dibatalkan. Apakah Anda yakin ingin menghapus goal ini?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Batal'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: FilledButton.styleFrom(backgroundColor: MalvaColors.danger),
                        child: const Text('Hapus'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  store.deleteGoal(goal.id);
                  Navigator.pop(context);
                }
              },
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
    required this.onSave,
    this.onDelete,
  });

  final GoalItem? initialGoal;
  final ValueChanged<GoalItem> onSave;
  final VoidCallback? onDelete;

  @override
  State<_GoalFormSheet> createState() => _GoalFormSheetState();
}

class _GoalFormSheetState extends State<_GoalFormSheet> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late String _frequency;
  late TimeOfDay _reminder;

  bool get _isEditing => widget.initialGoal != null;

  @override
  void initState() {
    super.initState();
    final goal = widget.initialGoal;
    _title = TextEditingController(text: goal?.title ?? '');
    _note = TextEditingController(text: goal?.note ?? '');
    _frequency = goal?.frequency ?? 'Harian';
    _reminder = goal?.reminder ?? const TimeOfDay(hour: 20, minute: 0);
  }

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

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
    widget.onSave(
      GoalItem(
        id: existingGoal?.id ?? 'goal_${DateTime.now().millisecondsSinceEpoch}',
        title: _title.text.trim().isEmpty ? 'Goal baru' : _title.text.trim(),
        frequency: _frequency,
        streakDays: existingGoal?.streakDays ?? 0,
        completedToday: existingGoal?.completedToday ?? false,
        reminder: _reminder,
        note: _note.text.trim(),
      ),
    );
  }
}
