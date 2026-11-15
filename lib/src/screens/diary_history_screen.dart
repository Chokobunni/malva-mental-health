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
        ref.watch(currentSessionProvider);
        if (!mounted || _accountChanged || _identity(_session) != owner)
          return const Scaffold(
              body: Center(
                  child: Text(
                      'Sesi akun telah berubah. Buka kembali diary dari akun aktif.')));
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
                          return DiaryBadgesScreen(progress: _progress);
                        })),
                owner)));
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
                    onVault: (e) => _save(e, isUpdate: true, owner: owner)),
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
                  ref.watch(currentSessionProvider);
                  if (_accountChanged || _identity(_session) != owner) {
                    return const Scaffold(
                        body: Center(
                            child: Text(
                                'Sesi akun telah berubah. Buka kembali diary dari akun aktif.')));
                  }
                  return DiaryEditorScreen(
                      initialEntry: entry,
                      initialPrompt: prompt,
                      onPromptRefresh: () => _record('refreshPrompt'),
                      api: _api,
                      accessToken: _session?.accessToken,
                      protectRoute: (child) =>
                          Consumer(builder: (context, ref, _) {
                            ref.watch(currentSessionProvider);
                            if (!mounted ||
                                _accountChanged ||
                                _identity(_session) != owner) {
                              return Scaffold(
                                  appBar: AppBar(),
                                  body: const Center(
                                      child: Text(
                                          'Sesi akun telah berubah. Buka kembali diary dari akun aktif.')));
                            }
                            return child;
                          }),
                      onSave: (value) =>
                          _save(value, isUpdate: entry != null, owner: owner));
                })));
  }

  Future<bool> _save(DiaryEntry entry,
      {required bool isUpdate, required String owner}) async {
    if (_saving || _accountChanged || _identity(_session) != owner)
      return false;
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
                sharedWithProfessionals: true,
                occurredAt: entry.createdAt);
        saved = _entry(response);
      }
      if (!mounted || _accountChanged || _identity(_session) != identity)
        return false;
      ref.read(malvaStoreProvider.notifier).upsertDiary(saved);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Diary tersimpan.')));
      return true;
    } on Object catch (e) {
      if (!mounted || _accountChanged || _identity(_session) != identity)
        return false;
      setState(
          () => _error = 'Diary belum tersimpan: ${friendlyErrorMessage(e)}');
      return false;
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
                    title: const Text('Hapus Diary?'),
                    content: Text('Hapus “${entry.title}” dari riwayat diary?'),
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
          content: Text('Diary belum dihapus: ${friendlyErrorMessage(e)}')));
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentSessionProvider, (old, next) {
      if (_identity(old) != _identity(next)) {
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
                  'Sesi akun telah berubah. Buka kembali diary dari akun aktif.')));
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
                                                'Tulis Cerita Diari Baru',
                                                style: TextStyle(
                                                    fontSize: 13,
                                                    fontWeight:
                                                        FontWeight.w700)))),
                                    const SizedBox(height: 16),
                                    DailyPromptCards(
                                        onAnswer: (p) => _open(prompt: p),
                                        onRefresh: () =>
                                            _record('refreshPrompt')),
                                    const SizedBox(height: 16),
                                    InkWell(
                                        key: const ValueKey('diary-badge-bar'),
                                        onTap: _badges,
                                        borderRadius: BorderRadius.circular(20),
                                        child: DiaryCard(
                                            padding: const EdgeInsets.all(16),
                                            child: Row(children: [
                                              const Icon(Icons.star_rounded,
                                                  color: Color(0xffd6a625),
                                                  size: 28),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                  child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                    const Text(
                                                        'Lencana Apresiasi Diri',
                                                        style: TextStyle(
                                                            color: diaryPlum,
                                                            fontSize: 12,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w800)),
                                                    const SizedBox(height: 6),
                                                    LinearProgressIndicator(
                                                        value: unlocked / 100,
                                                        color: diaryPurple,
                                                        backgroundColor:
                                                            const Color(
                                                                0xfff2e2f3),
                                                        minHeight: 4,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(4)),
                                                    const SizedBox(height: 6),
                                                    Text(
                                                        '$unlocked dari 100 terbuka • Setiap langkah kecil berarti',
                                                        style: const TextStyle(
                                                            fontSize: 10,
                                                            color: Color(
                                                                0xff6b7280)))
                                                  ])),
                                              const SizedBox(width: 8),
                                              const Icon(Icons.chevron_right,
                                                  color: diaryPurple, size: 18)
                                            ]))),
                                    const SizedBox(height: 16),
                                    Container(
                                        padding: const EdgeInsets.all(20),
                                        decoration: BoxDecoration(
                                            gradient: const LinearGradient(
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                                colors: [
                                                  Color(0xff6e2b7e),
                                                  Color(0xffb55cc4)
                                                ]),
                                            borderRadius:
                                                BorderRadius.circular(26)),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.stretch,
                                            children: [
                                              Row(
                                                  crossAxisAlignment:
                                                      CrossAxisAlignment.start,
                                                  children: [
                                                    Container(
                                                        width: 40,
                                                        height: 40,
                                                        decoration: BoxDecoration(
                                                            color: Colors.white
                                                                .withValues(
                                                                    alpha: .2),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        16)),
                                                        child: const Icon(
                                                            Icons.bookmark,
                                                            color: Colors.white,
                                                            size: 21)),
                                                    const SizedBox(width: 12),
                                                    const Expanded(
                                                        child: Column(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .start,
                                                            children: [
                                                          Text('POSITIVE VAULT',
                                                              style: TextStyle(
                                                                  color: Color(
                                                                      0xffe9d5ff),
                                                                  fontSize: 9,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                  letterSpacing:
                                                                      .6)),
                                                          SizedBox(height: 3),
                                                          Text(
                                                              'Kotak Kenangan Baik & Syukur',
                                                              style: TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w800,
                                                                  fontSize: 13,
                                                                  height: 1.3))
                                                        ])),
                                                    const SizedBox(width: 6),
                                                    Text(
                                                        '${vault.length} Tersimpan',
                                                        style: const TextStyle(
                                                            color: Colors.white,
                                                            fontSize: 10,
                                                            fontWeight:
                                                                FontWeight
                                                                    .w700))
                                                  ]),
                                              const SizedBox(height: 14),
                                              const Text(
                                                  'Saat hari terasa berat, buka kembali catatan positif yang pernah kamu tulis sebagai pengingat bahwa kamu sudah melangkah sejauh ini.',
                                                  style: TextStyle(
                                                      color: Color(0xfff3e8ff),
                                                      fontSize: 11,
                                                      height: 1.65)),
                                              const SizedBox(height: 16),
                                              Wrap(
                                                  spacing: 10,
                                                  runSpacing: 8,
                                                  children: [
                                                    FilledButton.icon(
                                                        style: FilledButton
                                                            .styleFrom(
                                                                backgroundColor:
                                                                    Colors
                                                                        .white,
                                                                foregroundColor:
                                                                    diaryPlum),
                                                        onPressed: () {
                                                          if (vault.isEmpty) {
                                                            ScaffoldMessenger
                                                                    .of(context)
                                                                .showSnackBar(
                                                                    const SnackBar(
                                                                        content:
                                                                            Text('Simpan cerita ke Positive Vault terlebih dahulu.')));
                                                            return;
                                                          }
                                                          _read(
                                                              vault[Random()
                                                                  .nextInt(vault
                                                                      .length)],
                                                              random: true);
                                                        },
                                                        icon: const Icon(
                                                            Icons.bookmark,
                                                            size: 14),
                                                        label: const Text(
                                                            'Acak Kenangan Baik',
                                                            style: TextStyle(
                                                                fontSize: 11))),
                                                    TextButton(
                                                        style: TextButton.styleFrom(
                                                            backgroundColor:
                                                                Colors.white.withValues(
                                                                    alpha: .2),
                                                            foregroundColor:
                                                                Colors.white,
                                                            shape: RoundedRectangleBorder(
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                        12))),
                                                        onPressed: () =>
                                                            setState(() {
                                                              _vaultOnly =
                                                                  !_vaultOnly;
                                                              _day = null;
                                                              _palette = null;
                                                              _monthFilter =
                                                                  false;
                                                            }),
                                                        child: Text(
                                                            _vaultOnly
                                                                ? 'Semua Diari'
                                                                : 'Lihat Semua',
                                                            style: const TextStyle(
                                                                fontSize: 11,
                                                                fontWeight:
                                                                    FontWeight.w700)))
                                                  ])
                                            ])),
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
                                    Row(children: [
                                      Expanded(
                                          child: Text(
                                              _vaultOnly
                                                  ? 'Kenangan di Positive Vault'
                                                  : 'Daftar Cerita Diari',
                                              style: const TextStyle(
                                                  fontSize: 15,
                                                  fontWeight:
                                                      FontWeight.w800))),
                                      Text('${entries.length} Cerita',
                                          style: const TextStyle(
                                              fontSize: 10,
                                              color: Color(0xff6b7280)))
                                    ]),
                                    const SizedBox(height: 4),
                                    const Text(
                                        'Ketuk salah satu kartu untuk membaca halaman isi diari',
                                        style: TextStyle(
                                            fontSize: 10,
                                            color: Color(0xff6b7280))),
                                    const SizedBox(height: 12),
                                    TextField(
                                        controller: _search,
                                        onChanged: (_) => setState(() {}),
                                        decoration: InputDecoration(
                                            hintText:
                                                'Cari judul atau isi diary',
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
                                    Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton.icon(
                                            onPressed: _loading ? null : _load,
                                            icon: const Icon(Icons.refresh,
                                                size: 16),
                                            label: const Text(
                                                'Muat ulang diary',
                                                style:
                                                    TextStyle(fontSize: 11)))),
                                    if (!_loading && entries.isEmpty)
                                      const DiaryCard(
                                          child: Column(children: [
                                        Icon(Icons.menu_book_outlined,
                                            size: 30, color: diaryPurple),
                                        SizedBox(height: 12),
                                        Text('Belum ada catatan diary',
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
                                    for (final entry in entries)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(bottom: 12),
                                          child: _storyCard(entry))
                                  ]))
                        ])))));
  }

  Widget _storyCard(DiaryEntry entry) {
    final c = DiaryContent.parse(entry.note), d = toWib(entry.createdAt);
    return InkWell(
        onTap: () => _read(entry),
        borderRadius: BorderRadius.circular(26),
        child: DiaryCard(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                    color: const Color(0xfffaf5ff),
                    borderRadius: BorderRadius.circular(12)),
                child: Column(children: [
                  Text('${d.day}',
                      style: const TextStyle(
                          color: diaryPlum,
                          fontSize: 20,
                          fontWeight: FontWeight.w800)),
                  Text(diaryMonths[d.month - 1].substring(0, 3).toUpperCase(),
                      style: const TextStyle(
                          color: diaryPurple,
                          fontSize: 9,
                          fontWeight: FontWeight.w700))
                ])),
            const SizedBox(width: 10),
            Expanded(
                child: Text(diaryDate(d),
                    style: const TextStyle(
                        fontSize: 10, color: Color(0xff6b7280)))),
            if (c.inVault)
              const Icon(Icons.bookmark, color: diaryPurple, size: 18),
            PopupMenuButton<String>(
                tooltip: 'Aksi diary',
                onSelected: (a) {
                  if (a == 'edit') _open(entry: entry);
                  if (a == 'delete') unawaited(_delete(entry));
                },
                itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit Diary')),
                      PopupMenuItem(value: 'delete', child: Text('Hapus Diary'))
                    ])
          ]),
          const SizedBox(height: 12),
          Text(entry.title,
              style: const TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w800, height: 1.4)),
          const SizedBox(height: 10),
          DiaryPalettePill(palette: c.palette),
          const SizedBox(height: 10),
          if (c.text.isNotEmpty)
            Text(c.text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 11, height: 1.7, color: Color(0xff6b7280))),
          if (c.media.isNotEmpty)
            Text('${c.media.length} gambar terlampir',
                style: const TextStyle(fontSize: 10, color: diaryPurple)),
          if (c.tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 5, runSpacing: 5, children: [
              for (final tag in c.tags)
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: const Color(0xfff3f4f6),
                        borderRadius: BorderRadius.circular(6)),
                    child: Text('#$tag',
                        style: const TextStyle(
                            fontSize: 9, color: Color(0xff6b7280))))
            ])
          ],
          const SizedBox(height: 12),
          const Align(
              alignment: Alignment.centerRight,
              child: Text('Baca Diari ›',
                  style: TextStyle(
                      color: diaryPurple,
                      fontSize: 10,
                      fontWeight: FontWeight.w800)))
        ])));
  }
}
