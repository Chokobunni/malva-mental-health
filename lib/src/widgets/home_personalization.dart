import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../assessment_engine.dart';
import '../models.dart';
import '../providers/providers.dart';
import '../theme.dart';
import 'malva_components.dart';

// ============================================================
// HOME PERSONALIZATION (condition banner + small wins + exercises)
// Warna 100% palet Malva — tidak ada warna baru.
// ============================================================

/// Banner kondisi berdasar screening terakhir pasien.
class ConditionBanner extends StatelessWidget {
  const ConditionBanner({super.key, required this.bundle});

  final ScreeningBundle? bundle;

  @override
  Widget build(BuildContext context) {
    final level = bundle?.overallLevel ?? RiskLevel.minimal;
    final (title, subtitle, color, icon) = switch (level) {
      RiskLevel.crisis => (
          'Butuh perhatian segera',
          'Skor menunjukkan risiko. Kamu tidak sendirian.',
          MalvaColors.danger,
          Icons.warning_amber_rounded,
        ),
      RiskLevel.severe => (
          'Depresi / Energi Rendah',
          'One small win at a time.',
          MalvaColors.seed,
          Icons.battery_0_bar_rounded,
        ),
      RiskLevel.moderate => (
          'Kecemasan / Mood Menurun',
          'Langkah kecil hari ini sangat berarti.',
          MalvaColors.amber,
          Icons.self_improvement_rounded,
        ),
      RiskLevel.mild => (
          'Menjaga Keseimbangan',
          'Pertahankan ritme baikmu hari ini.',
          MalvaColors.mint,
          Icons.spa_rounded,
        ),
      RiskLevel.minimal => (
          'Kondisi Stabil',
          'Bagaimana perasaanmu hari ini?',
          MalvaColors.mint,
          Icons.sentiment_satisfied_alt_rounded,
        ),
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            MalvaColors.plum,
            color == MalvaColors.danger
                ? MalvaColors.danger
                : MalvaColors.orchid,
            color == MalvaColors.amber ? MalvaColors.amber : MalvaColors.pink,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: MalvaColors.plum.withValues(alpha: 0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 17,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.88),
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Inline mood check-in — 5 emoji langsung di home.
class InlineMoodCheckIn extends ConsumerWidget {
  const InlineMoodCheckIn({super.key, required this.onSaved});

  final VoidCallback onSaved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bagaimana perasaanmu hari ini?',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              for (final mood in MoodValue.values)
                _MoodButton(
                  mood: mood,
                  onTap: () {
                    ref.read(malvaStoreProvider.notifier).addMood(
                          MoodEntry(
                            date: DateTime.now(),
                            mood: mood,
                            sleepHours: 0,
                            energy: 5,
                            anxiety: 5,
                            irritability: 5,
                            note: 'Quick check-in dari Home',
                          ),
                        );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Mood "${mood.label}" tersimpan.'),
                        backgroundColor: MalvaColors.mint,
                      ),
                    );
                    onSaved();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MoodButton extends StatelessWidget {
  const _MoodButton({required this.mood, required this.onTap});

  final MoodValue mood;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: MalvaColors.seed.withValues(alpha: 0.08),
              child: Icon(mood.icon, color: MalvaColors.seed, size: 28),
            ),
            const SizedBox(height: 4),
            Text(
              mood.label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

/// Small Wins — behavioral activation micro-tasks.
class SmallWinsCard extends StatefulWidget {
  const SmallWinsCard({super.key});

  @override
  State<SmallWinsCard> createState() => _SmallWinsCardState();
}

class _SmallWinsCardState extends State<SmallWinsCard> {
  static const _wins = [
    'Minum 1 gelas air',
    'Jalan kaki 5 menit',
    'Tulis 1 baris di Diary',
  ];

  final Set<int> _done = {};

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Small Wins Today',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ),
              StatusPill(
                label: '${_done.length}/${_wins.length}',
                color: _done.length == _wins.length
                    ? MalvaColors.mint
                    : MalvaColors.amber,
                icon: Icons.emoji_events_rounded,
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < _wins.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                onTap: () => setState(() {
                  if (_done.contains(i)) {
                    _done.remove(i);
                  } else {
                    _done.add(i);
                  }
                }),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: _done.contains(i)
                        ? MalvaColors.mint.withValues(alpha: 0.12)
                        : MalvaColors.seed.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _done.contains(i)
                            ? Icons.check_circle_rounded
                            : Icons.circle_outlined,
                        color: _done.contains(i)
                            ? MalvaColors.mint
                            : MalvaColors.seed,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _wins[i],
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            decoration: _done.contains(i)
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Grid latihan harian: breathing, CBT, mindfulness, journaling.
class DailyExercisesGrid extends StatelessWidget {
  const DailyExercisesGrid({
    super.key,
    required this.onBreathing,
    required this.onCbt,
    required this.onMindfulness,
    required this.onJournaling,
  });

  final VoidCallback onBreathing;
  final VoidCallback onCbt;
  final VoidCallback onMindfulness;
  final VoidCallback onJournaling;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Daily Exercises & Relief'),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.35,
          children: [
            _ExerciseTile(
              icon: Icons.air_rounded,
              title: '4-7-8 Breathing',
              subtitle: '3 min',
              color: MalvaColors.seed,
              onTap: onBreathing,
            ),
            _ExerciseTile(
              icon: Icons.psychology_rounded,
              title: 'CBT Thought Practice',
              subtitle: '5 min',
              color: MalvaColors.orchid,
              onTap: onCbt,
            ),
            _ExerciseTile(
              icon: Icons.spa_rounded,
              title: 'Mindfulness Session',
              subtitle: '10 min',
              color: MalvaColors.mint,
              onTap: onMindfulness,
            ),
            _ExerciseTile(
              icon: Icons.edit_note_rounded,
              title: 'Mood Journaling',
              subtitle: 'Daily check-in',
              color: MalvaColors.amber,
              onTap: onJournaling,
            ),
          ],
        ),
      ],
    );
  }
}

class _ExerciseTile extends StatelessWidget {
  const _ExerciseTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: Colors.black54),
          ),
        ],
      ),
    );
  }
}

/// Streak ring untuk medication adherence.
class StreakRing extends StatelessWidget {
  const StreakRing({
    super.key,
    required this.percent,
    this.size = 92,
  });

  final int percent;
  final double size;

  @override
  Widget build(BuildContext context) {
    final value = (percent.clamp(0, 100)) / 100.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CircularProgressIndicator(
              value: value,
              strokeWidth: 9,
              color: MalvaColors.mint,
              backgroundColor: MalvaColors.mint.withValues(alpha: 0.15),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$percent%',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: size * 0.2,
                ),
              ),
              Text(
                'streak',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.black54,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
