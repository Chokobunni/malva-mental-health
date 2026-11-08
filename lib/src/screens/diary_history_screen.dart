import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../time/wib.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';
import 'diary_form_sheet.dart';

class DiaryHistoryScreen extends ConsumerStatefulWidget {
  const DiaryHistoryScreen({super.key, this.session, this.apiClient});
  final AuthSession? session;
  final MalvaApiClient? apiClient;
  @override
  ConsumerState<DiaryHistoryScreen> createState() => _DiaryHistoryScreenState();
}

class _DiaryHistoryScreenState extends ConsumerState<DiaryHistoryScreen> {
  final _search = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _generation = 0;
  bool _accountChanged = false;
  AuthSession? get _session => _accountChanged
      ? null
      : ref.read(currentSessionProvider) ?? widget.session;
  MalvaApiClient get _api => widget.apiClient ?? ref.read(apiClientProvider);
  String _identity(AuthSession? s) =>
      '${s?.role}:${s?.backendUserId ?? s?.identifier}';
  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  DiaryEntry _entry(BackendDiaryEntry e) => DiaryEntry(
      id: e.id,
      createdAt: e.occurredAt ?? wibNow(),
      mood: MoodValue.values
          .firstWhere((m) => m.name == e.mood, orElse: () => MoodValue.okay),
      title: e.title,
      note: e.note,
      professionalFeedback: e.professionalFeedback);

  Future<void> _load() async {
    final request = ++_generation;
    final session = _session;
    final identity = _identity(session);
    final token = session?.accessToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (token != null && token.isNotEmpty) {
        final entries =
            await _api.listDiaryEntries(accessToken: token, limit: 0);
        if (!mounted ||
            request != _generation ||
            _identity(_session) != identity) return;
        ref
            .read(malvaStoreProvider.notifier)
            .replaceDiaryEntries(entries.map(_entry).toList());
      }
    } on Object catch (e) {
      if (mounted && request == _generation && _identity(_session) == identity)
        _error = friendlyErrorMessage(e);
    } finally {
      if (mounted && request == _generation && _identity(_session) == identity)
        setState(() => _loading = false);
    }
  }

  void _open({DiaryEntry? entry}) {
    final owner = _identity(_session);
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => Consumer(builder: (context, ref, _) {
              ref.watch(currentSessionProvider);
              if (_accountChanged || _identity(_session) != owner) {
                return const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                        'Sesi akun telah berubah. Buka kembali diary dari akun aktif.'));
              }
              return DiaryFormSheet(
                  initialEntry: entry,
                  onSave: (value) {
                    Navigator.pop(sheet);
                    if (!_accountChanged && _identity(_session) == owner)
                      unawaited(
                          _save(value, isUpdate: entry != null, owner: owner));
                  });
            }));
  }

  Future<void> _save(DiaryEntry entry,
      {required bool isUpdate, required String owner}) async {
    if (_saving || _accountChanged || _identity(_session) != owner) return;
    final session = _session;
    final identity = _identity(session);
    final token = session?.accessToken;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      var saved = entry;
      if (token != null && token.isNotEmpty) {
        final response = isUpdate
            ? await _api.updateDiaryEntry(
                accessToken: token,
                diaryId: entry.id,
                mood: entry.mood.name,
                title: entry.title,
                note: entry.note)
            : await _api.createDiaryEntry(
                accessToken: token,
                mood: entry.mood.name,
                title: entry.title,
                note: entry.note,
                sharedWithProfessionals: true,
                occurredAt: entry.createdAt);
        saved = _entry(response);
      }
      if (!mounted || _identity(_session) != identity) return;
      ref.read(malvaStoreProvider.notifier).upsertDiary(saved);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Diary tersimpan.')));
    } on Object catch (e) {
      if (!mounted || _identity(_session) != identity) return;
      setState(
          () => _error = 'Diary belum tersimpan: ${friendlyErrorMessage(e)}');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(_error!),
          action: SnackBarAction(
              label: 'Coba lagi',
              onPressed: () =>
                  unawaited(_save(entry, isUpdate: isUpdate, owner: owner)))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(DiaryEntry entry) async {
    final owner = _identity(_session);
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
                title: const Text('Hapus Diary?'),
                content: Text('Hapus “${entry.title}” dari riwayat diary?'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('Batal')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('Hapus'))
                ]));
    if (confirmed != true ||
        !mounted ||
        _accountChanged ||
        _identity(_session) != owner) return;
    final session = _session;
    final identity = _identity(session);
    try {
      final token = session?.accessToken;
      if (token != null && token.isNotEmpty)
        await _api.deleteDiaryEntry(accessToken: token, diaryId: entry.id);
      if (!mounted || _identity(_session) != identity) return;
      ref.read(malvaStoreProvider.notifier).deleteDiary(entry.id);
    } on Object catch (e) {
      if (!mounted || _identity(_session) != identity) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Diary belum dihapus: ${friendlyErrorMessage(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentSessionProvider, (old, next) {
      if (_identity(old) != _identity(next)) {
        _accountChanged = true;
        _generation++;
        _search.clear();
        setState(() {});
      }
    });
    if (_accountChanged)
      return const Scaffold(
          body: Center(
              child: Text(
                  'Sesi akun telah berubah. Buka kembali diary dari akun aktif.')));
    final query = _search.text.trim().toLowerCase();
    final entries = ref
        .watch(malvaStoreProvider)
        .diaryEntries
        .where((e) => '${e.title} ${e.note} ${e.professionalFeedback ?? ''}'
            .toLowerCase()
            .contains(query))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Scaffold(
      appBar: AppBar(
          title: const Text('My Diary History'),
          backgroundColor: MalvaColors.seed,
          foregroundColor: Colors.white,
          actions: [
            IconButton(
                tooltip: 'Muat ulang diary',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh))
          ]),
      floatingActionButton: FloatingActionButton.extended(
          heroTag: 'diary_history_add_fab',
          onPressed: _saving ? null : () => _open(),
          icon: const Icon(Icons.add),
          label: const Text('Tambah')),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(18),
            child: TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                    hintText: 'Cari judul atau isi diary',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Bersihkan pencarian',
                            icon: const Icon(Icons.close),
                            onPressed: () {
                              _search.clear();
                              setState(() {});
                            })))),
        if (_loading || _saving) const LinearProgressIndicator(),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Text(_error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
        Expanded(
            child: RefreshIndicator(
                onRefresh: _load,
                child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 100),
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      if (!_loading && entries.isEmpty)
                        const EmptyState(
                            icon: Icons.auto_stories_outlined,
                            title: 'Belum ada catatan diary',
                            subtitle:
                                'Tambahkan cerita harianmu. Mood check-in tersedia di My Health Check-In.'),
                      for (final entry in entries)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SoftCard(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Row(children: [
                                    const Icon(Icons.book_outlined,
                                        color: MalvaColors.seed),
                                    const SizedBox(width: 10),
                                    Expanded(
                                        child: Text(entry.title,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800))),
                                    PopupMenuButton<String>(
                                        tooltip: 'Aksi diary',
                                        onSelected: (action) {
                                          if (action == 'edit')
                                            _open(entry: entry);
                                          if (action == 'delete')
                                            unawaited(_delete(entry));
                                        },
                                        itemBuilder: (_) => const [
                                              PopupMenuItem(
                                                  value: 'edit',
                                                  child: Text('Edit Diary')),
                                              PopupMenuItem(
                                                  value: 'delete',
                                                  child: Text('Hapus Diary'))
                                            ])
                                  ]),
                                  Text(
                                      '${formatWibDateTime(entry.createdAt)} WIB',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                  const SizedBox(height: 10),
                                  SelectableText(entry.note),
                                  if (entry.professionalFeedback
                                          ?.trim()
                                          .isNotEmpty ??
                                      false) ...[
                                    const Divider(),
                                    Text(
                                        'Catatan profesional: ${entry.professionalFeedback}')
                                  ],
                                ]))),
                    ]))),
      ]),
    );
  }
}
