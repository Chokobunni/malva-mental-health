import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';

// ============================================================
// DIARY HISTORY — sesuai Figma frame "Diary History":
//   Pencarian + entri dikelompokkan per tanggal:
//     "03 January 2025"
//     [emoji] Anxious (8/10)      13:05
//     Severe Anxiety              [severity pill]
//     "The major project deadline is tomorrow..."
//     Okay 05:00  Sleep: 11h Energy: 5  "Woke up feeling rested."
// ============================================================

class DiaryHistoryScreen extends ConsumerStatefulWidget {
  const DiaryHistoryScreen({super.key, this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<DiaryHistoryScreen> createState() => _DiaryHistoryScreenState();
}

class _DiaryHistoryScreenState extends ConsumerState<DiaryHistoryScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(malvaStoreProvider);
    final moods = store.moodEntries.toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    final filtered = _query.isEmpty
        ? moods
        : moods
            .where((m) =>
                m.mood.label.toLowerCase().contains(_query.toLowerCase()) ||
                m.note.toLowerCase().contains(_query.toLowerCase()))
            .toList();

    // Kelompokkan per hari.
    final groups = <String, List<MoodEntry>>{};
    for (final entry in filtered) {
      const months = [
        'January',
        'February',
        'March',
        'April',
        'May',
        'June',
        'July',
        'August',
        'September',
        'October',
        'November',
        'December'
      ];
      final key =
          '${entry.date.day} ${months[entry.date.month - 1]} ${entry.date.year}';
      groups.putIfAbsent(key, () => []).add(entry);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Diary History'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (v) => setState(() => _query = v.trim()),
              decoration: InputDecoration(
                hintText: 'Search entries or feeling',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? const EmptyState(
                    icon: Icons.auto_stories_outlined,
                    title: 'Belum ada catatan diary',
                    subtitle: 'Check-in harianmu akan tersimpan di sini.',
                  )
                : RefreshIndicator(
                    onRefresh: () async {
                      await Future<void>.delayed(
                          const Duration(milliseconds: 300));
                    },
                    child: ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
                        for (final group in groups.entries) ...[
                          Text(
                            group.key,
                            style: const TextStyle(
                                fontWeight: FontWeight.w900, fontSize: 15),
                          ),
                          const SizedBox(height: 8),
                          for (final entry in group.value)
                            _DiaryEntryCard(entry: entry),
                          const SizedBox(height: 14),
                        ],
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _DiaryEntryCard extends StatelessWidget {
  const _DiaryEntryCard({required this.entry});

  final MoodEntry entry;

  String get _emoji => entry.mood.emoji;

  String _severityLabel(int score) {
    if (score >= 7) return 'Severe';
    if (score >= 4) return 'Moderate';
    return 'Mild';
  }

  Color _severityColor(int score) {
    if (score >= 7) return MalvaColors.danger;
    if (score >= 4) return MalvaColors.amber;
    return MalvaColors.mint;
  }

  @override
  Widget build(BuildContext context) {
    final hh = entry.date.hour.toString().padLeft(2, '0');
    final mm = entry.date.minute.toString().padLeft(2, '0');
    final hasNote = entry.note.isNotEmpty && entry.note != 'Tidak ada catatan.';
    final moodColor =
        entry.mood == MoodValue.great || entry.mood == MoodValue.good
            ? MalvaColors.mint
            : (entry.mood == MoodValue.okay
                ? MalvaColors.amber
                : MalvaColors.danger);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(_emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${entry.mood.label} (${entry.mood.score}/10)',
                    style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                        color: moodColor),
                  ),
                ),
                Text('$hh:$mm',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.black54)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Text(
                  '${_severityLabel(entry.anxiety)} Anxiety',
                  style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13,
                      color: _severityColor(entry.anxiety)),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color:
                        _severityColor(entry.anxiety).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    _severityLabel(entry.anxiety),
                    style: TextStyle(
                        color: _severityColor(entry.anxiety),
                        fontWeight: FontWeight.w800,
                        fontSize: 11),
                  ),
                ),
              ],
            ),
            if (hasNote) ...[
              const SizedBox(height: 6),
              Text('"${entry.note}"',
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
            const Divider(height: 18),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                _Meta('Sleep: ${entry.sleepHours.toStringAsFixed(0)}h'),
                _Meta('Energy: ${entry.energy}'),
                _Meta('Anxiety: ${entry.anxiety}'),
                _Meta('Irritability: ${entry.irritability}'),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context)
          .textTheme
          .bodySmall
          ?.copyWith(color: Colors.black54, fontWeight: FontWeight.w700),
    );
  }
}
