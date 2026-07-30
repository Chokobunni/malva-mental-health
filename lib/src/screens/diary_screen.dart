import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/malva_api_client.dart';
import '../store/malva_store.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';

class DiaryScreen extends StatefulWidget {
  const DiaryScreen({
    super.key,
    required this.store,
    this.session,
    this.apiClient,
  });

  final MalvaStore store;
  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  State<DiaryScreen> createState() => _DiaryScreenState();
}

class _DiaryScreenState extends State<DiaryScreen> {
  final _searchController = TextEditingController();
  bool _isInitialLoading = true;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 500)).then((_) {
      if (mounted) setState(() => _isInitialLoading = false);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return;
    }
    try {
      final backendEntries = await apiClient.listDiaryEntries(
        accessToken: accessToken,
      );
      final entries = backendEntries
          .map(
            (b) => DiaryEntry(
              id: b.id,
              createdAt: b.occurredAt ?? DateTime.now(),
              mood: MoodValue.values.firstWhere(
                (m) => m.name == b.mood,
                orElse: () => MoodValue.okay,
              ),
              title: b.title,
              note: b.note,
              professionalFeedback: b.professionalFeedback,
            ),
          )
          .toList();
      widget.store.replaceDiaryEntries(entries);
      if (mounted) setState(() {});
    } on Object catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final query = _searchController.text.trim().toLowerCase();
        final entries = query.isEmpty
            ? widget.store.diaryEntries
            : widget.store.diaryEntries.where((entry) {
                final haystack =
                    '${entry.title} ${entry.note} ${entry.mood.label}'
                        .toLowerCase();
                return haystack.contains(query);
              }).toList(growable: false);

        return Scaffold(
          floatingActionButton: FloatingActionButton(
            heroTag: 'diary_add_fab',
            onPressed: () => _openDiaryForm(context),
            child: const Icon(Icons.add_rounded),
          ),
          body: RefreshIndicator(
            onRefresh: _refreshData,
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                if (_isInitialLoading) const LinearProgressIndicator(),
                const GradientHeader(
                title: 'Diary History',
                subtitle: 'Catat trigger, pikiran, dan feedback',
                leading: Icon(Icons.edit_note_rounded,
                    color: Colors.white, size: 34),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        hintText: 'Cari entry atau perasaan',
                        suffixIcon: _searchController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    if (entries.isEmpty)
                      SoftCard(
                        child: Column(
                          children: [
                            const Icon(Icons.edit_note_rounded,
                                size: 48, color: MalvaColors.seed),
                            const SizedBox(height: 12),
                            const Text(
                              'Belum ada diary',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Mulai catat trigger, pikiran, dan respons Anda hari ini.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => _openDiaryForm(context),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Tambah Diary Pertama'),
                            ),
                          ],
                        ),
                      )
                    else
                      for (final entry in entries) ...[
                        _DiaryCard(
                          entry: entry,
                          onEdit: () => _openDiaryForm(context, entry: entry),
                        ),
                        const SizedBox(height: 12),
                      ],
                    const SizedBox(height: 70),
                  ],
                ),
              ),
            ],
          ),
          ),
        );
      },
    );
  }

  void _openDiaryForm(BuildContext context, {DiaryEntry? entry}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _DiaryFormSheet(
        initialEntry: entry,
        onSave: (savedEntry) {
          widget.store.upsertDiary(savedEntry);
          unawaited(_syncDiary(savedEntry));
          Navigator.pop(context);
        },
        onDelete: entry == null
            ? null
            : () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    icon: const Icon(Icons.delete_rounded, color: MalvaColors.danger),
                    title: const Text('Hapus Diary?'),
                    content: const Text('Tindakan ini tidak dapat dibatalkan. Apakah Anda yakin ingin menghapus diary ini?'),
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
                  widget.store.deleteDiary(entry.id);
                  Navigator.pop(context);
                }
              },
      ),
    );
  }

  Future<void> _syncDiary(DiaryEntry entry) async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      return;
    }
    try {
      await apiClient.createDiaryEntry(
        accessToken: accessToken,
        mood: entry.mood.name,
        title: entry.title,
        note: entry.note,
        sharedWithProfessionals: true,
        occurredAt: entry.createdAt,
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Diary tersimpan lokal, sync backend gagal: $error'),
        ),
      );
    }
  }
}

class _DiaryCard extends StatelessWidget {
  const _DiaryCard({
    required this.entry,
    required this.onEdit,
  });

  final DiaryEntry entry;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: MalvaColors.pink.withValues(alpha: 0.24),
                child: Icon(entry.mood.icon, color: MalvaColors.plum),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(entry.title,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text(_dateLabel(entry.createdAt),
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Edit diary',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(entry.note),
          if (entry.professionalFeedback != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: MalvaColors.seed.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border(
                  left: BorderSide(
                    color: MalvaColors.seed.withValues(alpha: 0.5),
                    width: 4,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Professional Feedback',
                      style: TextStyle(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(entry.professionalFeedback!),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _dateLabel(DateTime date) {
    final h = date.hour.toString().padLeft(2, '0');
    final m = date.minute.toString().padLeft(2, '0');
    return '${date.day}/${date.month}/${date.year} $h:$m';
  }
}

class _DiaryFormSheet extends StatefulWidget {
  const _DiaryFormSheet({
    this.initialEntry,
    required this.onSave,
    this.onDelete,
  });

  final DiaryEntry? initialEntry;
  final ValueChanged<DiaryEntry> onSave;
  final VoidCallback? onDelete;

  @override
  State<_DiaryFormSheet> createState() => _DiaryFormSheetState();
}

class _DiaryFormSheetState extends State<_DiaryFormSheet> {
  late final TextEditingController _title;
  late final TextEditingController _note;
  late MoodValue _mood;

  bool get _isEditing => widget.initialEntry != null;

  @override
  void initState() {
    super.initState();
    final entry = widget.initialEntry;
    _title = TextEditingController(text: entry?.title ?? '');
    _note = TextEditingController(text: entry?.note ?? '');
    _mood = entry?.mood ?? MoodValue.okay;
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
              _isEditing ? 'Edit Diary' : 'Tambah Diary',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: MoodValue.values.map((mood) {
                return ChoiceChip(
                  avatar: Icon(mood.icon, size: 18),
                  label: Text(mood.label),
                  selected: _mood == mood,
                  onSelected: (_) => setState(() => _mood = mood),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Judul'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _note,
              minLines: 5,
              maxLines: 8,
              decoration: const InputDecoration(labelText: 'Catatan diary'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _save,
              child: Text(_isEditing ? 'Simpan Perubahan' : 'Simpan Entry'),
            ),
            if (widget.onDelete != null) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_rounded),
                label: const Text('Delete Diary'),
                style:
                    TextButton.styleFrom(foregroundColor: MalvaColors.danger),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _save() {
    final existingEntry = widget.initialEntry;
    widget.onSave(
      DiaryEntry(
        id: existingEntry?.id ??
            'diary_${DateTime.now().millisecondsSinceEpoch}',
        createdAt: existingEntry?.createdAt ?? DateTime.now(),
        mood: _mood,
        title: _title.text.trim().isEmpty ? _mood.label : _title.text.trim(),
        note: _note.text.trim().isEmpty
            ? 'Tidak ada catatan.'
            : _note.text.trim(),
        professionalFeedback: existingEntry?.professionalFeedback,
      ),
    );
  }
}
