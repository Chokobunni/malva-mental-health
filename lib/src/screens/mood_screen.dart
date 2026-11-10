import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../services/mood_insights.dart';
import 'mood_entry_screen.dart';
import '../widgets/malva_components.dart';
import '../widgets/mood_insights.dart';

String formatMoodCalendarDate(DateTime date) => moodCalendarDate(date);

class MoodScreen extends ConsumerStatefulWidget {
  const MoodScreen(
      {super.key, this.session, this.apiClient, this.embedded = false});
  final bool embedded;
  final AuthSession? session;
  final MalvaApiClient? apiClient;
  @override
  ConsumerState<MoodScreen> createState() => _MoodScreenState();
}

class _MoodScreenState extends ConsumerState<MoodScreen> {
  List<MoodEntry> _entries = [];
  bool _loading = true;
  bool _saving = false;
  bool _accountInvalidated = false;
  String? _error;
  int _generation = 0;
  String? _owner(AuthSession? session) => session == null
      ? null
      : '${session.role.name}|${session.backendUserId ?? session.identifier}';
  AuthSession? get _session {
    if (_accountInvalidated) return null;
    final active = ref.read(authStateProvider).session;
    if (active == null) return widget.session;
    if (widget.session != null && _owner(active) != _owner(widget.session))
      return null;
    return active;
  }

  MalvaApiClient get _api => widget.apiClient ?? ref.read(apiClientProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_refreshData());
    });
  }

  @override
  void didUpdateWidget(covariant MoodScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_owner(oldWidget.session) != _owner(widget.session)) {
      _generation++;
      _entries = [];
      _loading = true;
      _saving = false;
      _accountInvalidated = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_refreshData());
      });
    }
  }

  bool _current(int generation, AuthSession? auth) =>
      mounted &&
      generation == _generation &&
      _owner(ref.read(authStateProvider).session) == _owner(auth);

  Future<void> _refreshData() async {
    if (!mounted) return;
    final generation = ++_generation;
    final auth = ref.read(authStateProvider).session;
    final token = _session?.accessToken;
    setState(() {
      _loading = true;
      _error = null;
    });
    if (token == null || token.isEmpty) {
      setState(() {
        _entries = [];
        _loading = false;
        _error = 'Masuk ke akun untuk memuat check-in.';
      });
      return;
    }
    try {
      final values = await _api.listMoodCheckins(accessToken: token, limit: 0);
      if (!_current(generation, auth)) return;
      final entries = values
          .where((e) => e.occurredAt != null)
          .map(moodEntryFromBackend)
          .toList();
      ref.read(malvaStoreProvider.notifier).replaceMoodEntries(entries);
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } on Object {
      if (!_current(generation, auth)) return;
      setState(() {
        _loading = false;
        _error = 'Riwayat mood belum dapat dimuat. Tarik untuk mencoba lagi.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateProvider, (previous, next) {
      if (previous?.session != null &&
          _owner(previous?.session) != _owner(next.session)) {
        _generation++;
        _accountInvalidated = true;
        setState(() {
          _entries = [];
          _loading = false;
          _saving = false;
          _error = 'Akun berubah. Buka kembali check-in dari akun aktif.';
        });
      }
    });
    final content = RefreshIndicator(
        onRefresh: _refreshData,
        child: ListView(
            padding: EdgeInsets.zero,
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              if (!widget.embedded)
                const GradientHeader(
                    title: 'Mood Tracker',
                    subtitle: 'Mood, tidur, energi, kecemasan',
                    leading: Icon(Icons.mood_rounded,
                        color: Colors.white, size: 34)),
              if (_loading) const LinearProgressIndicator(),
              Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_error != null)
                          Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: Text(_error!,
                                  style: TextStyle(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error))),
                        FilledButton.icon(
                            onPressed: _saving ? null : _openEntry,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Add Mood Entry')),
                        const SizedBox(height: 18),
                        MoodInsights(
                            entries: _entries,
                            ownerKey: _session?.backendUserId ??
                                _session?.identifier),
                      ])),
            ]));
    return widget.embedded ? content : Scaffold(body: content);
  }

  Future<void> _openEntry() async {
    if (_saving) return;
    final startedSession = _session;
    final startedAuth = ref.read(authStateProvider).session;
    final startedGeneration = _generation;
    if (startedSession == null) return;
    setState(() => _saving = true);
    final saved = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
            builder: (_) =>
                MoodEntryScreen(session: startedSession, apiClient: _api)));
    if (mounted && _current(startedGeneration, startedAuth)) {
      setState(() => _saving = false);
    }
    if (saved != true ||
        !_current(startedGeneration, startedAuth) ||
        _owner(_session) != _owner(startedSession)) return;
    await _refreshData();
    if (mounted &&
        _owner(ref.read(authStateProvider).session) == _owner(startedAuth)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Mood entry tersimpan.')));
    }
  }
}
