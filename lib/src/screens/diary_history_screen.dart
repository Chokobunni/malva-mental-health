import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../models/diary_content.dart';
import '../providers/providers.dart';
import '../platform/platform_providers.dart';
import '../services/malva_api_client.dart';
import '../models/diary_catalog.dart';
import '../models/diary_achievements.dart';
import '../widgets/diary_design.dart';
import '../widgets/diary_body.dart';
import '../widgets/diary_access.dart';
import '../services/diary_prompt_history.dart';
import 'diary_badges_screen.dart';
import 'diary_reader_screen.dart';
import '../time/wib.dart';
import '../widgets/friendly_error.dart';

import 'diary_editor_screen.dart';

class DiaryHistoryScreen extends ConsumerStatefulWidget {
  const DiaryHistoryScreen({super.key, this.session, this.apiClient});
  final AuthSession? session;
  final MalvaApiClient? apiClient;
  @override
  ConsumerState<DiaryHistoryScreen> createState() => _DiaryHistoryScreenState();
}

class _DiaryHistoryScreenState extends ConsumerState<DiaryHistoryScreen> {
  final _search = TextEditingController();
  late final _promptHistory = DiaryPromptHistory(ref.read(secureStoreProvider),
      'diary-prompt-order-v1-${base64Url.encode(utf8.encode(_identity(_session)))}');
  bool _loading = true;
  bool _saving = false;
  DateTime _month = wibNow();
  String? _palette, _day;
  bool _vaultOnly = false, _monthFilter = false;
  final _activities = <String>{}, _readIds = <String>{};
  final _activityRevision = ValueNotifier(0);
  Future<void> _activityWrite = Future.value();
  String? _activityError;
  String get _activityKey =>
      'diary-activity-v1-${base64Url.encode(utf8.encode(_identity(_session)))}';
  List<DiaryEntry> get _all => [...ref.read(malvaStoreProvider).diaryEntries]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  List<DiaryBadgeProgress> get _progress =>
      evaluateDiaryBadges(_all, activities: _activities);
  Future<void> _loadActivity() async {
    final owner = _identity(_session), key = _activityKey;
    if (_session == null) return;
    try {
      final raw = await ref.read(secureStoreProvider).read(key);
      if (!mounted || _accountChanged || owner != _identity(_session)) return;
      if (raw != null) {
        final value = jsonDecode(raw);
        if (value is List) _activities.addAll(value.whereType<String>());
      }
      _record('visit:${diaryDay(wibNow())}');
    } on Object {
      if (mounted && !_accountChanged)
        setState(() => _activityError =
            'Progres aktivitas belum dapat dimuat di perangkat ini.');
    }
  }

  void _record(String event) {
    if (!mounted || _accountChanged) return;
    setState(() => _activities.add(event));
    _activityRevision.value++;
    if (_session == null) return;
    final storage = ref.read(secureStoreProvider);
    final key = _activityKey,
        value = jsonEncode(_activities.toList()),
        owner = _identity(_session);
    _activityWrite = _activityWrite.then((_) async {
      try {
        await storage.write(key, value);
      } on Object {
        if (mounted && !_accountChanged && owner == _identity(_session))
          setState(() => _activityError =
              'Progres aktivitas belum tersimpan di perangkat ini.');
      }
    });
  }

  Widget _protect(Widget Function() builder, String owner) =>
      Consumer(builder: (context, ref, _) {
        ref.watch(authStateProvider);
        if (!mounted || _accountChanged || _identity(_session) != owner)
          return const Scaffold(
              body: Center(
                  child: Text(
                      'Sesi akun telah berubah. Buka kembali jurnal dari akun aktif.')));
        return builder();
      });
  void _badges() {
    final owner = _identity(_session);
    Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => _protect(
                () => ValueListenableBuilder<int>(
                    valueListenable: _activityRevision,
                    builder: (context, _, child) =>
                        Consumer(builder: (context, ref, _) {
                          ref.watch(malvaStoreProvider);
                          return DiaryBadgesScreen(
                              progress: _progress, onAppreciation: _appreciate);
                        })),
                owner)));
  }

  Future<void> _appreciate() async {
    if (_saving || _accountChanged) return;
    final owner = _identity(_session), entries = _all;
    String? selectedId, error;
    var choices = <int>{};
    var saving = false;
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: diaryPaper,
        builder: (sheet) => _protect(
            () => StatefulBuilder(
                builder: (form, update) => SizedBox(
                    height: MediaQuery.sizeOf(form).height * .85,
                    child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Pengalaman yang kuapresiasi',
                                  style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                      color: diaryPlum)),
                              const SizedBox(height: 12),
                              if (entries.isEmpty)
                                const Text(
                                    'Tulis jurnal terlebih dahulu untuk mencatat pengalamanmu.')
                              else ...[
                                DropdownButtonFormField<String>(
                                    initialValue: selectedId,
                                    isExpanded: true,
                                    decoration: const InputDecoration(
                                        labelText: 'Pilih jurnal'),
                                    items: entries
                                        .map((e) => DropdownMenuItem(
                                            value: e.id,
                                            child: Text(e.title,
                                                maxLines: 1,
                                                overflow:
                                                    TextOverflow.ellipsis)))
                                        .toList(),
                                    onChanged: saving
                                        ? null
                                        : (id) => update(() {
                                              selectedId = id;
                                              choices = DiaryContent.parse(
                                                      entries
                                                          .firstWhere(
                                                              (e) => e.id == id)
                                                          .note)
                                                  .appreciations
                                                  .toSet();
                                              error = null;
                                            })),
                                const SizedBox(height: 8),
                                const Text(
                                    'Pilih sesuai pengalamanmu dalam jurnal ini. Progres mengikuti isi jurnal yang tersimpan.',
                                    style: TextStyle(
                                        fontSize: 12, color: diaryPlum)),
                              ],
                              const SizedBox(height: 8),
                              Expanded(
                                  child: ListView(children: [
                                if (selectedId != null)
                                  for (final badge in diaryBadges.where((b) =>
                                      diarySubjectiveBadges.contains(b.id)))
                                    CheckboxListTile(
                                        contentPadding: EdgeInsets.zero,
                                        value: choices.contains(badge.id),
                                        title: Text(badge.title,
                                            style:
                                                const TextStyle(fontSize: 13)),
                                        subtitle: Text(badge.description,
                                            style:
                                                const TextStyle(fontSize: 11)),
                                        onChanged: saving
                                            ? null
                                            : (value) => update(() {
                                                  if (value == true) {
                                                    choices.add(badge.id);
                                                  } else {
                                                    choices.remove(badge.id);
                                                  }
                                                })),
                              ])),
                              if (error != null)
                                Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Text(error!,
                                        style: TextStyle(
                                            color: Theme.of(form)
                                                .colorScheme
                                                .error))),
                              FilledButton(
                                  onPressed: selectedId == null || saving
                                      ? null
                                      : () async {
                                          if (_accountChanged ||
                                              _identity(_session) != owner)
                                            return;
                                          final current = _all
                                              .where((e) => e.id == selectedId)
                                              .firstOrNull;
                                          if (current == null) {
                                            update(() => error =
                                                'Jurnal ini sudah tidak tersedia.');
                                            return;
                                          }
                                          final note =
                                              DiaryContent.parse(current.note)
                                                  .copyWith(
                                                      appreciations:
                                                          choices.toList()
                                                            ..sort())
                                                  .encode();
                                          if (utf8.encode(note).length > 6000) {
                                            update(() => error =
                                                'Jurnal beserta pilihan apresiasi melebihi batas 6000 byte. Kurangi pilihan atau isi jurnal.');
                                            return;
                                          }
                                          update(() {
                                            saving = true;
                                            error = null;
                                          });
                                          final saved = await _save(
                                              current.copyWith(note: note),
                                              isUpdate: true,
                                              owner: owner);
                                          if (!form.mounted ||
                                              !mounted ||
                                              _accountChanged ||
                                              _identity(_session) != owner)
                                            return;
                                          if (saved != null) {
                                            Navigator.pop(sheet);
                                          } else {
                                            update(() {
                                              saving = false;
                                              error =
                                                  'Pilihan belum tersimpan. Coba lagi.';
                                            });
                                          }
                                        },
                                  child: Text(saving
                                      ? 'Menyimpan...'
                                      : 'Simpan pengalaman')),
                              TextButton(
                                  onPressed: saving
                                      ? null
                                      : () => Navigator.pop(sheet),
                                  child: const Text('Batal')),
                            ])))),
            owner));
  }

  void _read(DiaryEntry entry, {bool random = false}) {
    if (random) {
      _record('randomVault');
    }
    void mark(DiaryEntry e, bool adjacent) {
      final today = diaryDay(wibNow());
      if (DiaryContent.parse(e.note).inVault &&
          diaryDay(e.createdAt).compareTo(today) < 0 &&
          _all.any((d) =>
              diaryDay(d.createdAt) == today &&
              const ['redup', 'sendu']
                  .contains(DiaryContent.parse(d.note).palette))) {
        _record('hardDayVault');
      }
      _readIds.add(e.id);
      if (adjacent) _record('adjacentRead');
      if (wibNow().difference(e.createdAt) > const Duration(days: 7))
        _record('oldRead');
      if (_readIds.length >= 5) _record('reviewFive');
    }

    mark(entry, false);
    final owner = _identity(_session);
    Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (readerContext) => _protect(
                () => DiaryReaderScreen(
                    entries: _all,
                    initialId: entry.id,
                    api: _api,
                    token: _session?.accessToken,
                    onRead: mark,
                    onEdit: (e) {
                      Navigator.pop(readerContext);
                      _open(entry: e);
                    },
                    onDelete: (e) async {
                      final deleted = await _delete(e);
                      if (deleted && readerContext.mounted)
                        Navigator.pop(readerContext);
                      return deleted;
                    },
                    onVault: (e) async =>
                        await _save(e, isUpdate: true, owner: owner) != null),
                owner)));
  }

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
    unawaited(_loadActivity());
  }

  @override
  void dispose() {
    _search.dispose();
    _activityRevision.dispose();
    _promptHistory.dispose();
    super.dispose();
  }

  DiaryEntry _entry(BackendDiaryEntry e) => DiaryEntry(
      id: e.id,
      createdAt: e.occurredAt ?? wibNow(),
      mood: MoodValue.values
          .firstWhere((m) => m.name == e.mood, orElse: () => MoodValue.okay),
      title: e.title,
      note: e.note,
      professionalFeedback: e.professionalFeedback,
      accessRecipients: e.accessRecipients);

  Future<void> _load() async {
    if (_saving || _accountChanged) return;
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

  void _open({DiaryEntry? entry, DiaryPrompt? prompt}) {
    final owner = _identity(_session);
    Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => Consumer(builder: (context, ref, _) {
                  ref.watch(authStateProvider);
                  if (_accountChanged || _identity(_session) != owner) {
                    return const Scaffold(
                        body: Center(
                            child: Text(
                                'Sesi akun telah berubah. Buka kembali jurnal dari akun aktif.')));
                  }
                  return DiaryEditorScreen(
                      initialEntry: entry,
                      initialPrompt: entry == null
                          ? prompt ?? _promptHistory.selected
                          : null,
                      promptHistory: _promptHistory,
                      onPromptRefresh: () => _record('refreshPrompt'),
                      api: _api,
                      accessToken: _session?.accessToken,
                      protectRoute: (child) =>
                          Consumer(builder: (context, ref, _) {
                            ref.watch(authStateProvider);
                            if (!mounted ||
                                _accountChanged ||
                                _identity(_session) != owner) {
                              return Scaffold(
                                  appBar: AppBar(),
                                  body: const Center(
                                      child: Text(
                                          'Sesi akun telah berubah. Buka kembali jurnal dari akun aktif.')));
                            }
                            return child;
                          }),
                      onSave: (value, isUpdate) =>
                          _save(value, isUpdate: isUpdate, owner: owner),
                      onManageAccess: (editorContext, value, onChanged) =>
                          _showAccess(editorContext, value, owner,
                              onChanged: onChanged));
                })));
  }

  Future<void> _showAccess(BuildContext source, DiaryEntry entry, String owner,
      {ValueChanged<List<DiaryAccessRecipient>>? onChanged}) async {
    String? currentToken() {
      if (!mounted || _accountChanged || _identity(_session) != owner) {
        return null;
      }
      return _session?.accessToken;
    }

    if (currentToken()?.isNotEmpty != true || _saving) return;
    final api = _api;
    await showModalBottomSheet<void>(
      context: source,
      isScrollControlled: true,
      barrierColor: const Color(0x99502b54),
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _protect(
          () => DiaryAccessSheet(
                entry: entry,
                api: api,
                accessToken: currentToken,
                onChanged: (recipients) {
                  if (currentToken() == null) return;
                  if (_loading) {
                    setState(() {
                      _generation++;
                      _loading = false;
                    });
                  }
                  for (final current in _all) {
                    if (current.id != entry.id) continue;
                    ref.read(malvaStoreProvider.notifier).upsertDiary(
                        current.copyWith(accessRecipients: recipients));
                    break;
                  }
                  onChanged?.call(recipients);
                },
              ),
          owner),
    );
  }

  Future<DiaryEntry?> _save(DiaryEntry entry,
      {required bool isUpdate, required String owner}) async {
    if (_saving || _accountChanged || _identity(_session) != owner) return null;
    final session = _session;
    final identity = _identity(session);
    final token = session?.accessToken;
    setState(() {
      _saving = true;
      _generation++;
      _loading = false;
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
                sharedWithProfessionals: false,
                occurredAt: entry.createdAt);
        if (response.id.isEmpty) {
          throw const MalvaApiException('Respons jurnal tidak valid.');
        }
        saved = _entry(response);
      }
      if (!mounted || _accountChanged || _identity(_session) != identity)
        return null;
      if (isUpdate) {
        for (final current in _all) {
          if (current.id != saved.id) continue;
          saved = saved.copyWith(accessRecipients: current.accessRecipients);
          break;
        }
      }
      ref.read(malvaStoreProvider.notifier).upsertDiary(saved);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Jurnal tersimpan.')));
      return saved;
    } on Object catch (e) {
      if (!mounted || _accountChanged || _identity(_session) != identity)
        return null;
      setState(
          () => _error = 'Jurnal belum tersimpan: ${friendlyErrorMessage(e)}');
      return null;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _delete(DiaryEntry entry) async {
    if (_saving || _accountChanged) return false;
    final owner = _identity(_session);
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => _protect(
            () => AlertDialog(
                    title: const Text('Hapus Jurnal?'),
                    content:
                        Text('Hapus “${entry.title}” dari riwayat jurnal?'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialog, false),
                          child: const Text('Batal')),
                      FilledButton(
                          onPressed: () => Navigator.pop(dialog, true),
                          child: const Text('Hapus'))
                    ]),
            owner));
    if (confirmed != true ||
        !mounted ||
        _accountChanged ||
        _identity(_session) != owner) return false;
    final session = _session;
    final identity = _identity(session);
    setState(() {
      _saving = true;
      _generation++;
      _loading = false;
    });
    try {
      final token = session?.accessToken;
      if (token != null && token.isNotEmpty)
        await _api.deleteDiaryEntry(accessToken: token, diaryId: entry.id);
      if (!mounted || _accountChanged || _identity(_session) != identity)
        return false;
      ref.read(malvaStoreProvider.notifier).deleteDiary(entry.id);
      return true;
    } on Object catch (e) {
      if (!mounted || _accountChanged || _identity(_session) != identity)
        return false;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Jurnal belum dihapus: ${friendlyErrorMessage(e)}')));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentSessionProvider);
    ref.listen(authStateProvider, (old, next) {
      if (_identity(old?.session) != _identity(next.session)) {
        _accountChanged = true;
        _generation++;
        _search.clear();
        _activities.clear();
        _readIds.clear();
        setState(() {});
      }
    });
    if (_accountChanged)
      return const Scaffold(
          body: Center(
              child: Text(
                  'Sesi akun telah berubah. Buka kembali jurnal dari akun aktif.')));
    ref.watch(malvaStoreProvider);
    final query = _search.text.trim().toLowerCase();
    final all = _all;
    final entries = all.where((e) {
      final c = DiaryContent.parse(e.note), d = toWib(e.createdAt);
      return (!_vaultOnly || c.inVault) &&
          (_palette == null || c.palette == _palette) &&
          (_day == null || diaryDay(e.createdAt) == _day) &&
          (!_monthFilter ||
              (d.year == _month.year && d.month == _month.month)) &&
          '${e.title} ${c.plainText} ${e.professionalFeedback ?? ''}'
              .toLowerCase()
              .contains(query);
    }).toList();
    final vault = all.where((e) => DiaryContent.parse(e.note).inVault).toList();
    final unlocked = _progress.where((p) => p.unlocked).length;
    return DiaryTheme(
        child: Scaffold(
            backgroundColor: diaryPaper,
            body: SafeArea(
                child: RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.only(bottom: 32),
                        children: [
                          DiaryHeader(
                              unlocked: unlocked,
                              onBadges: _badges,
                              onBack: Navigator.canPop(context)
                                  ? () => Navigator.pop(context)
                                  : null),
                          Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    FilledButton.icon(
                                        onPressed:
                                            _saving ? null : () => _open(),
                                        icon: const Icon(Icons.add, size: 20),
                                        label: const Padding(
                                            padding: EdgeInsets.symmetric(
                                                vertical: 14),
                                            child: Text(
                                                'Tulis Cerita Jurnal Baru',
                                                style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w700)))),
                                    const SizedBox(height: 16),
                                    DailyPromptCards(
                                        history: _promptHistory,
                                        onAnswer: (p) => _open(prompt: p),
                                        onRefresh: () =>
                                            _record('refreshPrompt')),
                                    const SizedBox(height: 16),
                                    DiaryVaultCard(
                                        count: vault.length,
                                        vaultOnly: _vaultOnly,
                                        onRandom: () {
                                          if (vault.isEmpty) {
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(const SnackBar(
                                                    content: Text(
                                                        'Simpan cerita ke Ruang Positif terlebih dahulu.')));
                                            return;
                                          }
                                          _read(
                                              vault[Random()
                                                  .nextInt(vault.length)],
                                              random: true);
                                        },
                                        onAll: () => setState(() {
                                              _vaultOnly = !_vaultOnly;
                                              _day = null;
                                              _palette = null;
                                              _monthFilter = false;
                                            })),
                                    const SizedBox(height: 16),
                                    DiaryCalendar(
                                        month: _month,
                                        entries: all,
                                        palette: _palette,
                                        selectedDay: _day,
                                        onMonth: (delta) => setState(() {
                                              _month = wibFromParts(_month.year,
                                                  _month.month + delta, 1);
                                              _monthFilter = true;
                                              _day = null;
                                            }),
                                        onDay: (date) {
                                          final matches = all
                                              .where((e) =>
                                                  diaryDay(e.createdAt) ==
                                                  diaryDay(date))
                                              .toList();
                                          if (matches.length == 1) {
                                            _read(matches.single);
                                          } else {
                                            setState(() {
                                              _day = diaryDay(date);
                                              _palette = null;
                                              _vaultOnly = false;
                                            });
                                          }
                                        },
                                        onPalette: (p) {
                                          setState(() {
                                            _palette = p;
                                            _day = null;
                                          });
                                          if (p != null) _record('colorFilter');
                                        }),
                                    const SizedBox(height: 20),
                                    TextField(
                                        controller: _search,
                                        onChanged: (_) => setState(() {}),
                                        decoration: InputDecoration(
                                            hintText:
                                                'Cari judul atau isi jurnal',
                                            prefixIcon:
                                                const Icon(Icons.search),
                                            suffixIcon: query.isEmpty
                                                ? null
                                                : IconButton(
                                                    tooltip:
                                                        'Bersihkan pencarian',
                                                    onPressed: () {
                                                      _search.clear();
                                                      setState(() {});
                                                    },
                                                    icon: const Icon(
                                                        Icons.close)))),
                                    const SizedBox(height: 16),
                                    Row(children: [
                                      Expanded(
                                          child: Text(
                                              _vaultOnly
                                                  ? 'Kenangan di Ruang Positif'
                                                  : 'Daftar Cerita Jurnal',
                                              style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight:
                                                      FontWeight.w800))),
                                      Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 12, vertical: 5),
                                          decoration: BoxDecoration(
                                              color: const Color(0xfff2e2f3),
                                              borderRadius:
                                                  BorderRadius.circular(20)),
                                          child: Text(
                                              '${entries.length} Cerita',
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: diaryPurple,
                                                  fontWeight: FontWeight.w800)))
                                    ]),
                                    const SizedBox(height: 4),
                                    const Text(
                                        'Ketuk salah satu kartu untuk membaca halaman isi jurnal.',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Color(0xff6b7280))),
                                    const SizedBox(height: 12),
                                    if (_day != null ||
                                        _palette != null ||
                                        _monthFilter ||
                                        _vaultOnly)
                                      Align(
                                          alignment: Alignment.centerLeft,
                                          child: TextButton.icon(
                                              onPressed: () => setState(() {
                                                    _day = null;
                                                    _palette = null;
                                                    _monthFilter = false;
                                                    _vaultOnly = false;
                                                  }),
                                              icon: const Icon(
                                                  Icons.filter_alt_off_outlined,
                                                  size: 16),
                                              label: const Text(
                                                  'Tampilkan semua cerita',
                                                  style: TextStyle(
                                                      fontSize: 11)))),
                                    const SizedBox(height: 12),
                                    if (_loading || _saving)
                                      const LinearProgressIndicator(),
                                    if (_error != null)
                                      Text(_error!,
                                          style: const TextStyle(
                                              color: Colors.red, fontSize: 12)),
                                    if (_activityError != null)
                                      Text(_activityError!,
                                          style: const TextStyle(
                                              color: Colors.red, fontSize: 11)),
                                    if (_error != null)
                                      Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton.icon(
                                              onPressed:
                                                  _loading ? null : _load,
                                              icon: const Icon(Icons.refresh,
                                                  size: 16),
                                              label: const Text(
                                                  'Muat ulang jurnal',
                                                  style: TextStyle(
                                                      fontSize: 11)))),
                                    if (!_loading && entries.isEmpty)
                                      const DiaryCard(
                                          child: Column(children: [
                                        Image(
                                            image: AssetImage(
                                                'assets/reference/diary-empty.png'),
                                            height: 82,
                                            excludeFromSemantics: true),
                                        SizedBox(height: 12),
                                        Text('Belum ada catatan jurnal',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                fontWeight: FontWeight.w700)),
                                        SizedBox(height: 8),
                                        Text(
                                            'Ceritamu boleh dimulai dari hal kecil. Semua perasaan mendapat ruang di sini.',
                                            textAlign: TextAlign.center,
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Color(0xff6b7280),
                                                height: 1.5))
                                      ])),
                                  ])),
                          for (final entry in entries)
                            Padding(
                                key: ValueKey('diary-story-${entry.id}'),
                                padding:
                                    const EdgeInsets.fromLTRB(16, 0, 16, 12),
                                child: _storyCard(entry))
                        ])))));
  }

  Widget _storyCard(DiaryEntry entry) {
    final c = DiaryContent.parse(entry.note), d = toWib(entry.createdAt);
    final color = diaryPalettes[c.palette];
    final compact = MediaQuery.sizeOf(context).width < 350 ||
        MediaQuery.textScalerOf(context).scale(1) > 1.2;
    final previews = <DiaryMedia>[];
    for (final kind in ['photo', 'drawing']) {
      final matches = c.media
          .where((m) => (m.kind == 'drawing' ? 'drawing' : 'photo') == kind);
      if (matches.isNotEmpty) previews.add(matches.first);
    }
    const weekdays = [
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu',
      'Minggu'
    ];
    return InkWell(
        onTap: () => _read(entry),
        borderRadius: BorderRadius.circular(26),
        child: DiaryCard(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                        width: 44,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                            color: color?.$2 ?? const Color(0xfff0e5f3),
                            borderRadius: BorderRadius.circular(16)),
                        child: Column(children: [
                          Text('${d.day}',
                              style: TextStyle(
                                  color: color?.$3 ?? diaryPlum,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800)),
                          Text(
                              diaryMonths[d.month - 1]
                                  .substring(0, 3)
                                  .toUpperCase(),
                              style: TextStyle(
                                  color: color?.$3 ?? diaryPurple,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700))
                        ])),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text('${weekdays[d.weekday - 1]}, ${diaryDate(d)}',
                              style: const TextStyle(
                                  fontSize: 10, color: Color(0xff9ca3af))),
                          if (c.inVault)
                            Padding(
                                padding:
                                    const EdgeInsets.only(top: 6, bottom: 6),
                                child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 7, vertical: 3),
                                    decoration: BoxDecoration(
                                        color: const Color(0xfff5eaf7),
                                        borderRadius: BorderRadius.circular(6)),
                                    child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.bookmark,
                                              color: diaryPurple, size: 11),
                                          SizedBox(width: 4),
                                          Flexible(
                                              child: Text('Ruang Positif',
                                                  style: TextStyle(
                                                      color: diaryPurple,
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight.w800)))
                                        ]))),
                          if (!compact)
                            Text(entry.title,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    height: 1.4,
                                    color: Color(0xff111827)))
                        ])),
                    const SizedBox(width: 6),
                    DiaryPalettePill(palette: c.palette)
                  ]),
                  if (compact)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(entry.title,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                height: 1.4,
                                color: Color(0xff111827)))),
                  if (c.text.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: Text(c.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                height: 1.65,
                                color: Color(0xff4b5563)))),
                  if (previews.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Row(children: [
                          for (var index = 0;
                              index < previews.length;
                              index++) ...[
                            if (index > 0) const SizedBox(width: 8),
                            Expanded(
                                child: SizedBox(
                                    height: 94,
                                    child: DiaryImage(
                                        media: previews[index],
                                        api: _api,
                                        token: _session?.accessToken,
                                        preview: true))),
                          ],
                        ])),
                  if (c.tags.isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: DiaryTags(tags: c.tags)),
                  const Divider(height: 18, color: Color(0xffeadfed)),
                  DiaryAccessRow(
                      recipients: entry.accessRecipients,
                      onPressed: _loading ||
                              _saving ||
                              _session?.accessToken?.isNotEmpty != true
                          ? null
                          : () =>
                              _showAccess(context, entry, _identity(_session))),
                ])));
  }
}
