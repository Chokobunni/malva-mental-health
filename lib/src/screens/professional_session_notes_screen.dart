import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../time/wib.dart';
import '../widgets/friendly_error.dart';

const sessionNoteSections = [
  'Keluhan Utama',
  'Asesmen & Evaluasi Klinis',
  'Rekomendasi Praktis',
  'Rencana Terapi & Tindak Lanjut',
  'Target Sesi Berikutnya'
];
const _draftMarker = '\n\n[MALVA_DRAF_SESI_V1]\n';

String formatSessionNotes(List<String> values) => [
      for (var i = 0; i < sessionNoteSections.length; i++)
        if (values[i].trim().isNotEmpty)
          '${sessionNoteSections[i]}\n${values[i].trim()}'
    ].join('\n\n');
List<String> parseSessionNotes(String text) {
  final values = List.filled(sessionNoteSections.length, '');
  if (!sessionNoteSections
      .any((h) => text.startsWith('$h\n') || text.contains('\n\n$h\n'))) {
    values[0] = text;
    return values;
  }
  for (var i = 0; i < sessionNoteSections.length; i++) {
    final header = '${sessionNoteSections[i]}\n';
    final start = text.indexOf(header);
    if (start < 0) continue;
    var end = text.length;
    for (final h in sessionNoteSections) {
      final next = text.indexOf('\n\n$h\n', start + header.length);
      if (next >= 0 && next < end) end = next;
    }
    values[i] = text.substring(start + header.length, end).trim();
  }
  return values;
}

/// Uses existing shared-summary and professional-only private-note contracts.
class ProfessionalSessionNotesScreen extends ConsumerStatefulWidget {
  const ProfessionalSessionNotesScreen(
      {super.key, required this.session, this.accessToken, this.apiClient});
  final BackendCareSession session;
  final String? accessToken;
  final MalvaApiClient? apiClient;
  @override
  ConsumerState<ProfessionalSessionNotesScreen> createState() =>
      _ProfessionalSessionNotesScreenState();
}

class _ProfessionalSessionNotesScreenState
    extends ConsumerState<ProfessionalSessionNotesScreen> {
  late List<TextEditingController> _fields;
  late TextEditingController _private;
  bool _busy = false;
  bool _restoredDraft = false;
  late final List<TextEditingController> _recommendations;
  String? _ownerId;
  @override
  void initState() {
    super.initState();
    _ownerId = ref.read(currentSessionProvider)?.backendUserId;
    var values = parseSessionNotes(widget.session.summaryForPatient);
    var private = widget.session.privateNote;
    final marker = private.lastIndexOf(_draftMarker);
    if (marker >= 0) {
      try {
        final draft =
            jsonDecode(private.substring(marker + _draftMarker.length));
        if (draft is List &&
            draft.length == sessionNoteSections.length &&
            draft.every((v) => v is String)) {
          values = draft.cast<String>();
          private = private.substring(0, marker);
          _restoredDraft = true;
        }
      } catch (_) {/* Preserve unrecognized legacy text intact. */}
    }
    _fields = values.map((v) => TextEditingController(text: v)).toList();
    _private = TextEditingController(text: private);
    final recommendations = values[2].trim();
    _recommendations = (RegExp(r'^1[.)]\s').hasMatch(recommendations)
            ? recommendations
                .split(RegExp(r'\n(?=\d+[.)]\s)'))
                .map((line) => line.replaceFirst(RegExp(r'^\d+[.)]\s*'), ''))
            : [recommendations])
        .map((text) => TextEditingController(text: text))
        .toList();
  }

  @override
  void dispose() {
    for (final c in _fields) {
      c.dispose();
    }
    _private.dispose();
    for (final controller in _recommendations) {
      controller.dispose();
    }
    super.dispose();
  }

  void _updateRecommendations() {
    _fields[2].text = [
      for (final entry
          in _recommendations.where((c) => c.text.trim().isNotEmpty).indexed)
        '${entry.$1 + 1}. ${entry.$2.text.trim()}',
    ].join('\n');
  }

  bool _isOwner(AuthSession? owner) =>
      owner?.role == UserRole.professional && owner?.backendUserId == _ownerId;

  Future<void> _preview() async {
    await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        builder: (sheetContext) => Consumer(builder: (context, ref, _) {
              if (!_isOwner(ref.watch(currentSessionProvider))) {
                return const SafeArea(
                    child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                            'Catatan ini hanya tersedia untuk profesional.')));
              }
              return SafeArea(
                  child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * .85),
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(children: [
                                  const Expanded(
                                      child: Text('Pratinjau Catatan Sesi',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 20))),
                                  IconButton(
                                      tooltip: 'Tutup',
                                      onPressed: () =>
                                          Navigator.pop(sheetContext),
                                      icon: const Icon(Icons.close))
                                ]),
                                Text(widget.session.patientName.isEmpty
                                    ? 'Pasien'
                                    : widget.session.patientName),
                                const SizedBox(height: 16),
                                for (var i = 0; i < _fields.length; i++)
                                  if (_fields[i].text.trim().isNotEmpty) ...[
                                    Text(sessionNoteSections[i],
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800)),
                                    const SizedBox(height: 4),
                                    Text(_fields[i].text.trim()),
                                    const SizedBox(height: 16),
                                  ],
                                const Text(
                                    'Ringkasan ini akan dibagikan kepada pasien. Catatan pribadi tetap hanya terlihat oleh Anda.'),
                                const SizedBox(height: 16),
                                FilledButton(
                                    onPressed: _busy
                                        ? null
                                        : () {
                                            Navigator.pop(sheetContext);
                                            _save(publish: true);
                                          },
                                    child: const Text('Simpan & Selesai')),
                              ]))));
            }));
  }

  Future<void> _save({required bool publish}) async {
    if (_busy) return;
    final owner = ref.read(currentSessionProvider);
    if (owner?.role != UserRole.professional ||
        owner?.backendUserId != _ownerId) return;
    final api = widget.apiClient ?? ref.read(apiClientProvider);
    final token = widget.accessToken ?? owner?.accessToken ?? '';
    if (api == null || token.isEmpty) return;
    setState(() => _busy = true);
    try {
      final values = _fields.map((c) => c.text).toList();
      final updated = await api.updateCareSession(
          accessToken: token,
          sessionId: widget.session.id,
          summaryForPatient: publish ? formatSessionNotes(values) : null,
          privateNote: publish
              ? _private.text
              : '${_private.text}$_draftMarker${jsonEncode(values)}');
      if (!mounted ||
          ref.read(currentSessionProvider)?.backendUserId !=
              owner?.backendUserId ||
          ref.read(currentSessionProvider)?.role != owner?.role) return;
      Navigator.pop(context, updated);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(currentSessionProvider)?.role != UserRole.professional ||
        ref.watch(currentSessionProvider)?.backendUserId != _ownerId)
      return Scaffold(
          appBar: AppBar(title: const Text('Catatan Sesi')),
          body: const Center(
              child: Text('Catatan ini hanya tersedia untuk profesional.')));
    return Scaffold(
        backgroundColor: const Color(0xfff8f5fb),
        appBar: AppBar(title: const Text('Catatan Sesi Klinis')),
        body: ListView(padding: const EdgeInsets.all(16), children: [
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                        widget.session.patientName.isEmpty
                            ? 'Pasien'
                            : widget.session.patientName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 18)),
                    Text('ID Sesi: ${widget.session.id}'),
                    if (widget.session.scheduledDateTime case final at?)
                      Text(
                          '${wibWeekdayName(at)}, ${formatWibDate(at)} · ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')} WIB'),
                    Text(widget.session.sessionType == 'video'
                        ? 'Konsultasi Video'
                        : 'Konsultasi Chat'),
                  ])),
          if (_restoredDraft)
            const Align(
                alignment: Alignment.centerLeft,
                child: Chip(label: Text('Draf tersimpan'))),
          const SizedBox(height: 14),
          const Text(
              'Tinjau ringkasan sebelum menyimpan dan membagikannya kepada pasien.'),
          const SizedBox(height: 14),
          for (var i = 0; i < _fields.length; i++)
            if (i == 2) ...[
              Text(sessionNoteSections[i],
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              for (var n = 0; n < _recommendations.length; n++)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                              padding: const EdgeInsets.only(top: 16, right: 8),
                              child: Text('${n + 1}.')),
                          Expanded(
                              child: TextField(
                                  key: ValueKey(_recommendations[n]),
                                  controller: _recommendations[n],
                                  minLines: 1,
                                  maxLines: null,
                                  onChanged: (_) => _updateRecommendations(),
                                  decoration: const InputDecoration(
                                      labelText: 'Rekomendasi',
                                      filled: true,
                                      fillColor: Colors.white,
                                      border: OutlineInputBorder()))),
                          IconButton(
                              tooltip: 'Hapus rekomendasi ${n + 1}',
                              onPressed: () => setState(() {
                                    final removed =
                                        _recommendations.removeAt(n);
                                    removed.dispose();
                                    _updateRecommendations();
                                  }),
                              icon: const Icon(Icons.remove_circle_outline)),
                        ])),
              Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                      onPressed: () => setState(
                          () => _recommendations.add(TextEditingController())),
                      icon: const Icon(Icons.add),
                      label: const Text('Tambah rekomendasi'))),
              const SizedBox(height: 14),
            ] else
              Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: TextField(
                      controller: _fields[i],
                      minLines: 3,
                      maxLines: null,
                      decoration: InputDecoration(
                          labelText: sessionNoteSections[i],
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: Colors.white,
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(15))))),
          TextField(
              controller: _private,
              minLines: 3,
              maxLines: null,
              decoration: const InputDecoration(
                  labelText: 'Catatan pribadi profesional',
                  helperText:
                      'Catatan pribadi dan draf tidak dibagikan kepada pasien.',
                  border: OutlineInputBorder())),
          const SizedBox(height: 24)
        ]),
        bottomNavigationBar: SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: [
                  Expanded(
                      child: OutlinedButton(
                          onPressed: _busy ? null : () => _save(publish: false),
                          child: const Text('Simpan Draf'))),
                  const SizedBox(width: 10),
                  Expanded(
                      child: FilledButton(
                          onPressed: _busy ? null : _preview,
                          child: Text(_busy ? 'Menyimpan…' : 'Pratinjau')))
                ]))));
  }
}
