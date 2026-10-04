import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../theme.dart';
import 'malva_components.dart';

// ============================================================
// DAILY CHECK-IN (Home paling atas) — alur interaktif bertahap:
//   1. Emoticon lucu (mood) — Figma "How are you today?"
//   2. List obat yang perlu diminum (checklist)
//   3. "How long did you sleep?" — jam (1-12) + menit
//   4. "How is your energy?" — baterai penuh / setengah / habis
//   5. Popup "Good job!" + streak total hari
// Semua tersimpan via MalvaStore (MoodEntry + MedicationLog lokal).
// ============================================================

/// Cek apakah hari ini sudah check-in lengkap (ada mood dengan sleep).
bool hasCheckedInToday(List<MoodEntry> moods) {
  final now = DateTime.now();
  return moods.any((m) =>
      m.date.year == now.year &&
      m.date.month == now.month &&
      m.date.day == now.day &&
      m.sleepHours > 0);
}

/// Streak hari beruntun check-in (mood tersimpan > 0 hari berturut-turut).
int checkInStreak(List<MoodEntry> moods) {
  if (moods.isEmpty) return 0;
  final days = moods
      .map((m) => DateTime(m.date.year, m.date.month, m.date.day))
      .toSet()
      .toList()
    ..sort((a, b) => b.compareTo(a));
  var streak = 0;
  var cursor = DateTime.now();
  for (final day in days) {
    final diff = cursor.difference(day).inDays;
    if (diff == 0 || diff == 1) {
      streak++;
      cursor = day;
    } else {
      break;
    }
  }
  return streak;
}

class DailyCheckInFlow extends ConsumerStatefulWidget {
  const DailyCheckInFlow({super.key, required this.onSaved});

  final VoidCallback onSaved;

  @override
  ConsumerState<DailyCheckInFlow> createState() => _DailyCheckInFlowState();
}

class _DailyCheckInFlowState extends ConsumerState<DailyCheckInFlow> {
  MoodValue? _mood;
  int _step = 0; // 0 mood, 1 meds, 2 sleep, 3 energy, 4 done
  final Set<String> _takenMeds = {};
  int _sleepHours = 7;
  int _sleepMinutes = 30;
  int _energyLevel = 2; // 0 habis, 1 setengah, 2 penuh

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final store = ref.read(malvaStoreProvider);
      if (hasCheckedInToday(store.moodEntries)) {
        setState(() => _step = 4);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(malvaStoreProvider);
    final done = _step == 4;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Daily Check-in',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
              if (done)
                const Icon(Icons.check_circle_rounded, color: MalvaColors.mint),
            ],
          ),
          const SizedBox(height: 12),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: switch (_step) {
              0 => _MoodPicker(
                  key: const ValueKey('mood'),
                  selected: _mood,
                  onSelect: (m) => setState(() {
                    _mood = m;
                    _step = 1;
                  }),
                ),
              1 => _MedicationPicker(
                  key: const ValueKey('meds'),
                  meds: store.medications,
                  taken: _takenMeds,
                  onToggle: (id) => setState(() {
                    if (_takenMeds.contains(id)) {
                      _takenMeds.remove(id);
                    } else {
                      _takenMeds.add(id);
                    }
                  }),
                  onNext: () => setState(() => _step = 2),
                ),
              2 => _SleepPicker(
                  key: const ValueKey('sleep'),
                  hours: _sleepHours,
                  minutes: _sleepMinutes,
                  onHours: (h) => setState(() => _sleepHours = h),
                  onMinutes: (m) => setState(() => _sleepMinutes = m),
                  onNext: () => setState(() => _step = 3),
                ),
              3 => _EnergyPicker(
                  key: const ValueKey('energy'),
                  level: _energyLevel,
                  onSelect: (l) => setState(() {
                    _energyLevel = l;
                    _save(store);
                  }),
                ),
              _ => _DoneCard(
                  key: const ValueKey('done'),
                  streak: checkInStreak(store.moodEntries),
                ),
            },
          ),
        ],
      ),
    );
  }

  void _save(MalvaStoreState store) {
    final mood = _mood ?? MoodValue.okay;
    ref.read(malvaStoreProvider.notifier).addMood(
          MoodEntry(
            date: DateTime.now(),
            mood: mood,
            sleepHours: _sleepHours + _sleepMinutes / 60.0,
            energy: switch (_energyLevel) { 0 => 2, 1 => 5, _ => 9 },
            anxiety: 5,
            irritability: 5,
            note: 'Daily check-in',
          ),
        );
    // Tandai obat yang dicentang sudah diminum hari ini.
    final notifier = ref.read(malvaStoreProvider.notifier);
    for (final id in _takenMeds) {
      notifier.takeMedication(id);
    }
    widget.onSaved();
    setState(() => _step = 4);
    _showStreakPopup();
  }

  void _showStreakPopup() {
    final streak = checkInStreak(ref.read(malvaStoreProvider).moodEntries);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🎉', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 10),
            const Text('Good job!',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20)),
            const SizedBox(height: 6),
            Text(
              streak > 0
                  ? 'Streak check-in kamu: $streak hari berturut-turut!'
                  : 'Check-in pertamamu tercatat. Mulai streak-mu sekarang!',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(46),
            ),
            child: const Text('Lanjut'),
          ),
        ],
      ),
    );
  }
}

// ---------------- Step widgets ----------------

class _MoodPicker extends StatelessWidget {
  const _MoodPicker(
      {super.key, required this.selected, required this.onSelect});

  final MoodValue? selected;
  final ValueChanged<MoodValue> onSelect;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('How are you today?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final mood in MoodValue.values)
              InkWell(
                onTap: () => onSelect(mood),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: selected == mood
                        ? MalvaColors.seed.withValues(alpha: 0.14)
                        : Colors.transparent,
                  ),
                  child: Text(mood.emoji, style: const TextStyle(fontSize: 30)),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _MedicationPicker extends StatelessWidget {
  const _MedicationPicker({
    super.key,
    required this.meds,
    required this.taken,
    required this.onToggle,
    required this.onNext,
  });

  final List<Medication> meds;
  final Set<String> taken;
  final ValueChanged<String> onToggle;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Obat yang perlu diminum hari ini',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
        const SizedBox(height: 8),
        if (meds.isEmpty)
          const Text('Tidak ada jadwal obat hari ini. 👍',
              style: TextStyle(color: Colors.black54)),
        for (final med in meds)
          CheckboxListTile(
            value: taken.contains(med.id),
            onChanged: (_) => onToggle(med.id),
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            activeColor: MalvaColors.mint,
            title: Text(med.name,
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(
                '${med.dosage}${med.reminders.isNotEmpty ? ' • ${med.reminders.map((r) => r.time).join(', ')}' : ''}',
                style: const TextStyle(fontSize: 12)),
            secondary:
                const Icon(Icons.medication_rounded, color: MalvaColors.seed),
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: onNext,
          child: const Text('Lanjut'),
        ),
      ],
    );
  }
}

class _SleepPicker extends StatelessWidget {
  const _SleepPicker({
    super.key,
    required this.hours,
    required this.minutes,
    required this.onHours,
    required this.onMinutes,
    required this.onNext,
  });

  final int hours;
  final int minutes;
  final ValueChanged<int> onHours;
  final ValueChanged<int> onMinutes;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('How long did you sleep?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _NumberWheel(
                label: 'jam',
                value: hours,
                min: 1,
                max: 12,
                onChanged: onHours,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _NumberWheel(
                label: 'menit',
                value: minutes,
                min: 0,
                max: 59,
                step: 15,
                onChanged: onMinutes,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        FilledButton(onPressed: onNext, child: const Text('Lanjut')),
      ],
    );
  }
}

/// Dropdown angka dengan tombol +/- (jam 1-12, menit langkah 15).
class _NumberWheel extends StatelessWidget {
  const _NumberWheel({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.step = 1,
  });

  final String label;
  final int value;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: MalvaColors.seed.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed:
                value - step >= min ? () => onChanged(value - step) : null,
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
          Expanded(
            child: Column(
              children: [
                Text('$value',
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 18)),
                Text(label,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.black54)),
              ],
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed:
                value + step <= max ? () => onChanged(value + step) : null,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _EnergyPicker extends StatelessWidget {
  const _EnergyPicker({
    super.key,
    required this.level,
    required this.onSelect,
  });

  final int level;
  final ValueChanged<int> onSelect;

  static const _options = [
    (0, Icons.battery_1_bar_rounded, 'Habis', MalvaColors.danger),
    (1, Icons.battery_3_bar_rounded, 'Setengah', MalvaColors.amber),
    (2, Icons.battery_full_rounded, 'Penuh', MalvaColors.mint),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('How is your energy?',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            for (final (value, icon, label, color) in _options)
              InkWell(
                onTap: () => onSelect(value),
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: level == value
                        ? color.withValues(alpha: 0.14)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: level == value
                          ? color
                          : Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(icon, size: 30, color: color),
                      const SizedBox(height: 4),
                      Text(label,
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color: level == value ? color : Colors.black54)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _DoneCard extends StatelessWidget {
  const _DoneCard({super.key, required this.streak});

  final int streak;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text('🎉', style: TextStyle(fontSize: 30)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            streak > 0
                ? 'Check-in hari ini selesai. Streak $streak hari! 🔥'
                : 'Check-in hari ini selesai. 👏',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}
