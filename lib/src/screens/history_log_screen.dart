import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';

// ============================================================
// HISTORY LOG — sesuai Figma "Mood Tracker" bagian Recent:
//   Kartu entry terbaru: nama mood (Anxious), "Yesterday",
//   baris pill: Anxiety (High) / Irritability (Severe) / Energy + "11 h"
// Dipakai untuk tab History Log di Home.
// ============================================================

class HistoryLogScreen extends ConsumerWidget {
  const HistoryLogScreen({super.key, this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(malvaStoreProvider).moodEntries;
    final sorted = entries.toList()..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      appBar: AppBar(
        title: const Text('History Log'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: sorted.isEmpty
          ? const EmptyState(
              icon: Icons.history_rounded,
              title: 'Belum ada riwayat check-in',
              subtitle:
                  'Riwayat mood, energi, dan kecemasanmu akan muncul di sini '
                  'setelah Daily Check-in.',
            )
          : RefreshIndicator(
              onRefresh: () async {
                await Future<void>.delayed(const Duration(milliseconds: 300));
              },
              child: ListView(
                padding: const EdgeInsets.all(18),
                children: [
                  const Text(
                    'Recent',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                  ),
                  const SizedBox(height: 12),
                  for (final entry in sorted.take(20)) ...[
                    _HistoryEntryCard(entry: entry),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
            ),
    );
  }
}

class _HistoryEntryCard extends StatelessWidget {
  const _HistoryEntryCard({required this.entry});

  final MoodEntry entry;

  String get _relativeDay {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(entry.date.year, entry.date.month, entry.date.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${entry.date.day} ${months[entry.date.month - 1]}';
  }

  String _level(int score) {
    if (score >= 7) return 'High';
    if (score >= 4) return 'Med';
    return 'Low';
  }

  String _severity(int score) {
    if (score >= 7) return 'Severe';
    if (score >= 4) return 'Moderate';
    return 'Mild';
  }

  @override
  Widget build(BuildContext context) {
    final moodColor =
        entry.mood == MoodValue.great || entry.mood == MoodValue.good
            ? MalvaColors.mint
            : (entry.mood == MoodValue.okay
                ? MalvaColors.amber
                : MalvaColors.danger);
    return SoftCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                entry.mood.label,
                style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    color: moodColor),
              ),
              const Spacer(),
              Text(
                _relativeDay,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.black54),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _LevelPill(label: 'Anxiety', value: _severity(entry.anxiety)),
              _LevelPill(
                  label: 'Irritability', value: _severity(entry.irritability)),
              _LevelPill(label: 'Energy', value: _level(entry.energy)),
              _LevelPill(
                  label: 'Sleep',
                  value: '${entry.sleepHours.toStringAsFixed(0)} h'),
            ],
          ),
        ],
      ),
    );
  }
}

class _LevelPill extends StatelessWidget {
  const _LevelPill({required this.label, required this.value});

  final String label;
  final String value;

  Color get _color {
    if (value == 'High' || value == 'Severe') return MalvaColors.danger;
    if (value == 'Med' || value == 'Moderate') return MalvaColors.amber;
    return MalvaColors.mint;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style:
            TextStyle(color: _color, fontWeight: FontWeight.w800, fontSize: 12),
      ),
    );
  }
}
