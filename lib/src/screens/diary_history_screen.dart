import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';

// ============================================================
// MY DIARY HISTORY — sesuai Figma frame "Diary History":
//   Pencarian + entri dikelompokkan per tanggal:
//     "03 January 2025"
//     [emoji] Anxious (8/10)      13:05
//     Severe Anxiety              [severity pill]
//     "The major project deadline is tomorrow..."
//     Sleep: 11h Energy: 5 Irritability: 3  [Medication taken]
// Data diambil dari server (mood-checkins + diary-entries) sehingga
// tersimpan permanen dan tidak hilang saat aplikasi dibuka ulang.
// ============================================================

/// Satu baris riwayat: gabungan mood check-in & diary entry.
class _HistoryRow {
  const _HistoryRow({
    required this.at,
    required this.mood,
    required this.moodScore,
    required this.sleepHours,
    required this.energy,
    required this.anxiety,
    required this.irritability,
    required this.note,
    required this.medicationTaken,
    required this.professionalFeedback,
    required this.title,
    this.isDiary = false,
  });

  final DateTime at;
  final MoodValue mood;
  final int moodScore; // 1-10 untuk tampilan "(x/10)"
  final double sleepHours;
  final int energy;
  final int anxiety;
  final int irritability;
  final String note;
  final bool medicationTaken;
  final String professionalFeedback;
  final String title;
  final bool isDiary;

  String get searchable =>
      '${mood.label} $note $title $professionalFeedback'.toLowerCase();
}

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
  List<_HistoryRow> _rows = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFromServer();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Ambil riwayat dari server; fallback ke data lokal bila offline.
  Future<void> _loadFromServer() async {
    final session = ref.read(currentSessionProvider) ?? widget.session;
    final apiClient = ref.read(apiClientProvider);
    final token = session?.accessToken;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    if (token == null || token.isEmpty) {
      _loadFromLocalStore();
      return;
    }
    try {
      final moods = await apiClient.listMoodCheckins(
        accessToken: token,
        limit: 100,
      );
      List<BackendDiaryEntry> diaries = const [];
      try {
        diaries = await apiClient.listDiaryEntries(
          accessToken: token,
          limit: 100,
        );
      } on Object {
        // Diary opsional: kalau gagal, tetap tampilkan mood check-in.
      }
      if (!mounted) return;
      final rows = <_HistoryRow>[
        for (final item in moods)
          _HistoryRow(
            at: item.occurredAt ?? DateTime.now(),
            mood: _moodFromString(item.mood),
            moodScore: _moodScore(item.mood, item.energy),
            sleepHours: item.sleepHours,
            energy: item.energy,
            anxiety: item.anxiety,
            irritability: item.irritability,
            note: item.note,
            medicationTaken: item.medicationTaken,
            professionalFeedback: item.professionalFeedback,
            title: '',
          ),
        for (final entry in diaries)
          _HistoryRow(
            at: entry.occurredAt ?? DateTime.now(),
            mood: _moodFromString(entry.mood),
            moodScore: _moodFromString(entry.mood).score * 2,
            sleepHours: 0,
            energy: 0,
            anxiety: 0,
            irritability: 0,
            note: entry.note,
            medicationTaken: false,
            professionalFeedback: entry.professionalFeedback ?? '',
            title: entry.title,
            isDiary: true,
          ),
      ]..sort((a, b) => b.at.compareTo(a.at));
      setState(() {
        _rows = rows;
        _isLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      // Offline / server error: pakai data lokal agar layar tetap berguna.
      _loadFromLocalStore(fallbackMessage: friendlyErrorMessage(e));
    }
  }

  void _loadFromLocalStore({String? fallbackMessage}) {
    final store = ref.read(malvaStoreProvider);
    final rows = <_HistoryRow>[
      for (final entry in store.moodEntries)
        _HistoryRow(
          at: entry.date,
          mood: entry.mood,
          moodScore: entry.mood.score * 2,
          sleepHours: entry.sleepHours,
          energy: entry.energy,
          anxiety: entry.anxiety,
          irritability: entry.irritability,
          note: entry.note,
          medicationTaken: false,
          professionalFeedback: '',
          title: '',
        ),
      for (final entry in store.diaryEntries)
        _HistoryRow(
          at: entry.createdAt,
          mood: entry.mood,
          moodScore: entry.mood.score * 2,
          sleepHours: 0,
          energy: 0,
          anxiety: 0,
          irritability: 0,
          note: entry.note,
          medicationTaken: false,
          professionalFeedback: entry.professionalFeedback ?? '',
          title: entry.title,
          isDiary: true,
        ),
    ]..sort((a, b) => b.at.compareTo(a.at));
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _isLoading = false;
      _error = fallbackMessage;
    });
  }

  static MoodValue _moodFromString(String mood) {
    return switch (mood.toLowerCase()) {
      'great' => MoodValue.great,
      'good' => MoodValue.good,
      'okay' => MoodValue.okay,
      'sad' => MoodValue.sad,
      'awful' => MoodValue.awful,
      _ => MoodValue.okay,
    };
  }

  static int _moodScore(String mood, int energy) {
    final base = _moodFromString(mood).score * 2;
    if (energy > 0) return ((base + energy) / 2).round().clamp(1, 10);
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? _rows
        : _rows
            .where((r) => r.searchable.contains(_query.toLowerCase()))
            .toList();

    // Kelompokkan per hari (format "3 January 2026").
    final groups = <String, List<_HistoryRow>>{};
    for (final row in filtered) {
      final key = _groupKey(row.at);
      groups.putIfAbsent(key, () => []).add(row);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Diary History'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Muat ulang dari server',
            onPressed: _isLoading ? null : _loadFromServer,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
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
          if (_error != null && _rows.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
              child: Text(
                'Menampilkan data lokal: $_error',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : filtered.isEmpty
                    ? const EmptyState(
                        icon: Icons.auto_stories_outlined,
                        title: 'Belum ada catatan diary',
                        subtitle:
                            'Check-in harianmu akan tersimpan di sini dan '
                            'tidak hilang meskipun aplikasi ditutup.',
                      )
                    : RefreshIndicator(
                        onRefresh: _loadFromServer,
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
                              for (final row in group.value)
                                _DiaryEntryCard(row: row),
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

  static String _groupKey(DateTime date) {
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
      'December',
    ];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }
}

class _DiaryEntryCard extends StatelessWidget {
  const _DiaryEntryCard({required this.row});

  final _HistoryRow row;

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
    final hh = row.at.hour.toString().padLeft(2, '0');
    final mm = row.at.minute.toString().padLeft(2, '0');
    final hasNote = row.note.isNotEmpty && row.note != 'Tidak ada catatan.';
    final moodColor = row.mood == MoodValue.great || row.mood == MoodValue.good
        ? MalvaColors.mint
        : (row.mood == MoodValue.okay ? MalvaColors.amber : MalvaColors.danger);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: SoftCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(row.mood.emoji, style: const TextStyle(fontSize: 26)),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${row.mood.label} (${row.moodScore}/10)',
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
            if (row.isDiary && row.title.isNotEmpty) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.book_rounded,
                      size: 14, color: MalvaColors.orchid),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(row.title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 13)),
                  ),
                ],
              ),
            ],
            if (!row.isDiary) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    '${_severityLabel(row.anxiety)} Anxiety',
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        color: _severityColor(row.anxiety)),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color:
                          _severityColor(row.anxiety).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _severityLabel(row.anxiety),
                      style: TextStyle(
                          color: _severityColor(row.anxiety),
                          fontWeight: FontWeight.w800,
                          fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
            if (hasNote) ...[
              const SizedBox(height: 6),
              Text('"${row.note}"',
                  style: Theme.of(context).textTheme.bodyMedium),
            ],
            if (row.professionalFeedback.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: MalvaColors.mint.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.medical_services_rounded,
                        size: 16, color: MalvaColors.mint),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Catatan profesional: ${row.professionalFeedback}',
                        style: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const Divider(height: 18),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                if (row.sleepHours > 0)
                  _Meta('Sleep: ${row.sleepHours.toStringAsFixed(0)}h'),
                if (row.energy > 0) _Meta('Energy: ${row.energy}'),
                if (row.anxiety > 0) _Meta('Anxiety: ${row.anxiety}'),
                if (row.irritability > 0)
                  _Meta('Irritability: ${row.irritability}'),
                if (row.medicationTaken) const _Meta('✓ Medication taken'),
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
