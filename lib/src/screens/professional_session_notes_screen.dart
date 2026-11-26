import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../services/client_intent_id.dart';
import '../professional_role.dart';
import 'goals/goal_editor.dart';
import 'portal/prescription_wizard_screen.dart';
import '../time/wib.dart';
import '../widgets/friendly_error.dart';

const sessionNoteSections = [
  'Keluhan Utama',
  'Asesmen & Evaluasi Klinis',
  'Rekomendasi Praktis',
  'Rencana Terapi & Tindak Lanjut',
  'Target Sesi Berikutnya',
  'Resep Elektronik',
  'Target & Kebiasaan Terapi'
];
const _draftMarker = '\n\n[MALVA_DRAF_SESI_V1]\n';

String formatSessionNotes(List<String> values) => [
      for (var i = 0; i < sessionNoteSections.length; i++)
        if (i < values.length && values[i].trim().isNotEmpty)
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
      {super.key,
      required this.session,
      this.accessToken,
      this.apiClient,
      this.packageLabel});
  final BackendCareSession session;
  final String? packageLabel;
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
  bool _ownerChanged = false;
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
            (draft.length == 5 || draft.length == sessionNoteSections.length) &&
            draft.every((v) => v is String)) {
          values = List<String>.of(draft.cast<String>());
          if (values.length == 5) values.addAll(['', '']);
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
            : [if (recommendations.isNotEmpty) recommendations])
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
      !_ownerChanged &&
      owner?.role == UserRole.professional &&
      owner?.backendUserId == _ownerId &&
      _ownerId == widget.session.professionalId;

  List<String> get _values =>
      _fields.map((controller) => controller.text).toList();

  Future<void> _preview() async {
    final values = _values;
    final session = widget.session;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetContext) => Consumer(builder: (context, ref, _) {
        if (!_isOwner(ref.watch(currentSessionProvider))) {
          return const SafeArea(
              child: Padding(
                  padding: EdgeInsets.all(24),
                  child:
                      Text('Catatan ini hanya tersedia untuk profesional.')));
        }
        return FractionallySizedBox(
          heightFactor: .92,
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DecoratedBox(
              decoration: const BoxDecoration(gradient: _notesGradient),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Row(children: [
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        const Text('Pratinjau Ringkasan Sesi',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 19)),
                        const SizedBox(height: 4),
                        Text(
                            [
                              session.patientName.isEmpty
                                  ? 'Pasien'
                                  : session.patientName,
                              if (widget.packageLabel case final label?) label,
                              session.id
                            ].join(' • '),
                            style: const TextStyle(color: Colors.white)),
                      ])),
                  IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      tooltip: 'Tutup',
                      icon: const Icon(Icons.close, color: Colors.white)),
                ]),
              ),
            ),
            Expanded(
                child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: sessionPublishedNoteCards(values)),
            )),
            SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: FilledButton(
                    style:
                        FilledButton.styleFrom(backgroundColor: _notesPurple),
                    onPressed: () => Navigator.pop(sheetContext),
                    child: const Text('Tutup Pratinjau'),
                  ),
                )),
          ]),
        );
      }),
    );
  }

  void _append(int section, String line) {
    final prior = _fields[section].text.trim();
    setState(() => _fields[section].text =
        [if (prior.isNotEmpty) prior, line].join('\n\n'));
  }

  Future<void> _addPrescription() async {
    final owner = ref.read(currentSessionProvider);
    if (!_isOwner(owner) || owner == null) return;
    final token = owner.accessToken ?? widget.accessToken;
    final api = widget.apiClient ?? ref.read(apiClientProvider);
    if (api == null ||
        token == null ||
        token.isEmpty ||
        widget.session.patientId.isEmpty) return;
    try {
      final credential = await api.getMyCredentials(accessToken: token);
      if (!mounted || !_isOwner(ref.read(currentSessionProvider))) return;
      if (credential == null ||
          !isPsychiatristSpecialization(credential.specialization) ||
          credential.verificationStatus.toUpperCase() != 'VERIFIED') {
        throw StateError(
            'Resep hanya dapat diterbitkan psikiater terverifikasi.');
      }
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => EPrescriptionFormScreen(
                    session: owner,
                    apiClient: api,
                    preselectedPatientId: widget.session.patientId,
                    preselectedPatientName: widget.session.patientName,
                    lockPatient: true,
                    onIssued: (rx) {
                      if (!mounted ||
                          !_isOwner(ref.read(currentSessionProvider)) ||
                          rx.patientId != widget.session.patientId) return;
                      for (final item in rx.items) {
                        _append(
                            5,
                            [
                              '${item.name} ${item.dosage}',
                              [
                                item.schedule?.label ?? item.frequency,
                                item.form,
                                if (item.schedule?.relationToMeal.isNotEmpty ==
                                    true)
                                  item.schedule!.relationToMeal,
                                'Stok ${item.remainingStock ?? item.currentStock}'
                              ].where((part) => part.isNotEmpty).join(' • '),
                            ].join('\n'));
                      }
                    },
                  )));
    } catch (error) {
      if (mounted && _isOwner(ref.read(currentSessionProvider))) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error is StateError
                ? error.message
                : friendlyErrorMessage(error))));
      }
    }
  }

  Future<void> _addGoal() async {
    final owner = ref.read(currentSessionProvider);
    if (!_isOwner(owner) || owner == null || widget.session.patientId.isEmpty)
      return;
    final api = widget.apiClient ?? ref.read(apiClientProvider);
    if (api == null) return;
    final intent = newClientIntentId();
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => GoalEditor(
                  onSave: (result) async {
                    if (!mounted) return false;
                    final current = ref.read(currentSessionProvider);
                    if (!_isOwner(current)) return false;
                    final token = current?.accessToken ?? widget.accessToken;
                    if (token == null || token.isEmpty) return false;
                    final goal = await api.createGoal(
                      accessToken: token,
                      patientId: widget.session.patientId,
                      title: result.title,
                      details: result.details,
                      targetPerWeek: result.details.weeklyTarget ??
                          result.details.weekdays.length,
                      idempotencyKey: intent,
                    );
                    if (!mounted || !_isOwner(ref.read(currentSessionProvider)))
                      return false;
                    final details = goal.details;
                    _append(
                        6,
                        [
                          goal.title,
                          if (details != null) details.scheduleLabel,
                          if (details != null && details.steps.isNotEmpty)
                            for (final step in details.steps) '• ${step.label}',
                          if (details?.note.isNotEmpty == true) details!.note,
                        ].join('\n'));
                    return true;
                  },
                )));
  }

  Future<void> _save({required bool publish}) async {
    if (_busy) return;
    final owner = ref.read(currentSessionProvider);
    if (!_isOwner(owner)) return;
    final api = widget.apiClient ?? ref.read(apiClientProvider);
    final token = owner?.accessToken ?? widget.accessToken ?? '';
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
      if (!mounted || !_isOwner(ref.read(currentSessionProvider))) return;
      Navigator.pop(context, updated);
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _field(int index, String hint, {int minLines = 3}) => TextField(
        key: ValueKey(sessionNoteSections[index]),
        controller: _fields[index],
        minLines: minLines,
        maxLines: null,
        decoration: _noteInput(hint),
      );

  Widget _add(String label, VoidCallback action) => SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _busy ? null : action,
          icon: const Icon(Icons.add),
          style: OutlinedButton.styleFrom(
              foregroundColor: _notesPurple,
              backgroundColor: const Color(0xfffaf6fc)),
          label: Text(label),
        ),
      );

  Widget _resource(int index, String empty, String label, VoidCallback action) {
    final lines = _fields[index]
        .text
        .trim()
        .split('\n\n')
        .where((text) => text.isNotEmpty)
        .toList();
    return _NotesPanel(
      section: index,
      count: lines.length,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (lines.isEmpty) _noteInset(Center(child: Text(empty))),
        for (final (position, line) in lines.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _noteInset(Row(children: [
              Expanded(child: _snapshotRow(line, prescription: index == 5)),
              IconButton(
                  tooltip: 'Lepas dari ringkasan',
                  icon: const Icon(Icons.link_off),
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                            lines.removeAt(position);
                            _fields[index].text = lines.join('\n\n');
                          })),
            ])),
          ),
        const SizedBox(height: 8),
        _add(label, action),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(currentSessionProvider, (_, next) {
      if (!_isOwner(next)) _ownerChanged = true;
    });
    if (!_isOwner(ref.watch(currentSessionProvider))) {
      return Scaffold(
          appBar: AppBar(title: const Text('Catatan Sesi')),
          body: const Center(
              child: Text('Catatan ini hanya tersedia untuk profesional.')));
    }
    final session = widget.session;
    return Scaffold(
      backgroundColor: const Color(0xfff7f7fa),
      appBar: AppBar(
        toolbarHeight: 78,
        foregroundColor: Colors.white,
        backgroundColor: _notesPurple,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(25))),
        flexibleSpace: const DecoratedBox(
            decoration: BoxDecoration(
                gradient: _notesGradient,
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(25)))),
        title: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Tulis Catatan Sesi',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20)),
              Text('Rekam Medis & Evaluasi Pasien',
                  style: TextStyle(color: Colors.white70, fontSize: 13)),
            ]),
        actions: [
          IconButton(
            tooltip: 'Simpan Draf',
            onPressed: _busy ? null : () => _save(publish: false),
            icon: const Icon(Icons.save_as_outlined),
          ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(15), children: [
        sessionNoteIdentity(session,
            session.patientName.isEmpty ? 'Pasien' : session.patientName,
            packageLabel: widget.packageLabel),
        sessionNoteId(context, session.id),
        if (_restoredDraft)
          const Align(
              alignment: Alignment.centerLeft,
              child: Chip(label: Text('Draf tersimpan'))),
        _NotesPanel(
            section: 0,
            child: _field(0,
                'Tuliskan keluhan utama, durasi gejala, dan pemicu yang disampaikan pasien…')),
        _NotesPanel(
            section: 1,
            child: _field(1,
                'Catat hasil observasi afek, perilaku, insight, serta perkembangan klinis…')),
        _NotesPanel(
            section: 2,
            count: _recommendations.length,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_recommendations.isEmpty)
                    _noteInset(const Center(
                        child: Text('Belum ada rekomendasi praktis'))),
                  for (var n = 0; n < _recommendations.length; n++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(children: [
                        Text('${n + 1}.',
                            style: const TextStyle(
                                color: _notesPurple,
                                fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        Expanded(
                            child: TextField(
                          key: ValueKey(_recommendations[n]),
                          controller: _recommendations[n],
                          minLines: 1,
                          maxLines: null,
                          onChanged: (_) => _updateRecommendations(),
                          decoration: _noteInput('Rekomendasi'),
                        )),
                        IconButton(
                            tooltip: 'Hapus rekomendasi ${n + 1}',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: _busy
                                ? null
                                : () => setState(() {
                                      final removed =
                                          _recommendations.removeAt(n);
                                      WidgetsBinding.instance
                                          .addPostFrameCallback(
                                              (_) => removed.dispose());
                                      _updateRecommendations();
                                    })),
                      ]),
                    ),
                  const SizedBox(height: 8),
                  _add(
                      'Tambah Rekomendasi',
                      () => setState(
                          () => _recommendations.add(TextEditingController()))),
                ])),
        _resource(
            5, 'Tidak ada obat diresepkan', 'Tambah Obat', _addPrescription),
        _resource(6, 'Belum ada target kebiasaan',
            'Tambah Target / Kebiasaan Baru', _addGoal),
        _NotesPanel(
            section: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field(3,
                    'Tuliskan rencana pendekatan terapi, evaluasi, atau jadwal sesi berikutnya…'),
                const SizedBox(height: 16),
                const Text('Target Sesi Berikutnya',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                _field(4, 'Contoh: Evaluasi pola tidur dan latihan relaksasi',
                    minLines: 1),
              ],
            )),
        ExpansionTile(
            title: const Text('Catatan pribadi profesional'),
            children: [
              TextField(
                  controller: _private,
                  minLines: 3,
                  maxLines: null,
                  decoration: _noteInput(
                      'Catatan pribadi tidak dibagikan kepada pasien.')),
            ]),
      ]),
      bottomNavigationBar: SafeArea(
          top: false,
          child: Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(15, 9, 15, 10),
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: _notesPurple),
                        onPressed: _busy ? null : () => _save(publish: true),
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_busy ? 'Menyimpan…' : 'Simpan Catatan')),
                    OutlinedButton.icon(
                        onPressed: _busy ? null : _preview,
                        icon: const Icon(Icons.visibility_outlined),
                        label: const Text('Pratinjau Ringkasan')),
                  ]),
            ),
          )),
    );
  }
}

const _notesPurple = Color(0xff78349d);
const _notesGradient =
    LinearGradient(colors: [Color(0xff64248b), Color(0xff8c3eac)]);
const _noteAssets = [
  'complaint',
  'assessment',
  'recommendation',
  'followup',
  '',
  'prescription',
  'goals'
];
const _noteSubtitles = [
  'Alasan kunjungan dan gejala yang dirasakan pasien',
  'Observasi objektif, status mental, dan perkembangan klinis',
  'Langkah tindakan cepat yang dapat diterapkan pasien',
  'Fokus intervensi dan jadwal pertemuan selanjutnya',
  '',
  'Hanya diisi oleh dokter atau psikiater berwenang',
  'Aktivitas terstruktur yang dipantau di aplikasi pasien',
];

InputDecoration _noteInput(String hint) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: const Color(0xfff7f8fa),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xffe8e7ed))),
    );

Widget _noteInset(Widget child) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xfff7f4fa),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: const Color(0xffece8f1))),
      child: child,
    );

class _NotesPanel extends StatelessWidget {
  const _NotesPanel(
      {required this.section,
      required this.child,
      this.count,
      this.readOnly = false});
  final int section;
  final Widget child;
  final int? count;
  final bool readOnly;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(19),
            border: Border.all(color: const Color(0xffeeecf1)),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x07000000),
                  blurRadius: 12,
                  offset: Offset(0, 3))
            ]),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Image.asset('assets/care/session-note-${_noteAssets[section]}.png',
                width: 34, height: 34, excludeFromSemantics: true),
            const SizedBox(width: 10),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(sessionNoteSections[section],
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800)),
                  if (!(readOnly && section == 5))
                    Text(_noteSubtitles[section],
                        style: const TextStyle(
                            color: Color(0xff697684), fontSize: 12)),
                ])),
            if (count case final value?) ...[
              const SizedBox(width: 8),
              CircleAvatar(
                  radius: 13,
                  backgroundColor: const Color(0xfff0e6f7),
                  child: Text('$value',
                      style:
                          const TextStyle(color: _notesPurple, fontSize: 12))),
            ],
          ]),
          const SizedBox(height: 13),
          child,
        ]),
      );
}

Widget sessionNoteIdentity(BackendCareSession session, String name,
    {String? packageLabel}) {
  final at = session.scheduledDateTime;
  final initials = name
      .trim()
      .replaceFirst(RegExp(r'^dr\.?\s+', caseSensitive: false), '')
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .take(2)
      .map((word) => word.characters.first)
      .join()
      .toUpperCase();
  return Container(
    margin: const EdgeInsets.only(bottom: 14),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
        gradient: _notesGradient, borderRadius: BorderRadius.circular(21)),
    child: DefaultTextStyle(
      style: const TextStyle(color: Colors.white, fontSize: 13),
      child: Column(children: [
        Row(children: [
          Container(
              width: 43,
              height: 43,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(13)),
              child: Text(initials,
                  style: const TextStyle(
                      color: _notesPurple,
                      fontSize: 16,
                      fontWeight: FontWeight.w800))),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(name,
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Text(session.isVideo ? 'Konsultasi Video' : 'Konsultasi Chat'),
              ])),
          if (packageLabel case final label?) ...[
            const SizedBox(width: 6),
            Flexible(
                child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(20)),
              child: Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            )),
          ],
        ]),
        if (at != null) ...[
          const Divider(height: 23, color: Colors.white30),
          Wrap(
              spacing: 18,
              runSpacing: 6,
              alignment: WrapAlignment.spaceBetween,
              children: [
                Text('${wibWeekdayName(at)}, ${formatWibDate(at)}'),
                Text(
                    '${formatWibBubbleTime(at)}–${formatWibBubbleTime(at.add(Duration(minutes: session.durationMinutes)))} WIB'),
              ]),
        ],
      ]),
    ),
  );
}

Widget sessionNoteId(BuildContext context, String id) => Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        const Icon(Icons.tag, color: _notesPurple),
        const SizedBox(width: 10),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ID Sesi Konsultasi',
              style: TextStyle(fontSize: 12, color: Color(0xff657181))),
          SelectableText(id,
              style: const TextStyle(fontWeight: FontWeight.w800)),
        ])),
        TextButton.icon(
            onPressed: () => Clipboard.setData(ClipboardData(text: id)),
            icon: const Icon(Icons.copy_outlined, size: 16),
            label: const Text('Salin')),
      ]),
    );

Widget _snapshotRow(String text, {bool prescription = false}) {
  final parts = text.split('\n');
  final details =
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text(parts.first, style: const TextStyle(fontWeight: FontWeight.w800)),
    if (parts.length > 1)
      Text(parts.skip(1).join('\n'),
          style: const TextStyle(height: 1.45, color: Color(0xff657181))),
    if (prescription)
      const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text('Resep Profesional',
              style: TextStyle(color: _notesPurple, fontSize: 11))),
  ]);
  if (!prescription) return details;
  return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Image.asset('assets/care/session-note-medication-row.png',
        width: 32, height: 32),
    const SizedBox(width: 9),
    Expanded(child: details),
  ]);
}

List<Widget> sessionPublishedNoteCards(List<String> values) => [
      for (final section in [0, 1, 2, 5, 6, 3])
        if (values[section].trim().isNotEmpty ||
            (section == 3 && values[4].trim().isNotEmpty))
          _NotesPanel(
            section: section,
            readOnly: true,
            child: section == 5 || section == 6
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                        for (final row in values[section].trim().split('\n\n'))
                          Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: _noteInset(_snapshotRow(row,
                                  prescription: section == 5))),
                      ])
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                        if (values[section].trim().isNotEmpty)
                          _noteInset(Text(values[section].trim(),
                              style: const TextStyle(height: 1.55))),
                        if (section == 3 && values[4].trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          const Text('Target Sesi Berikutnya',
                              style: TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 6),
                          _noteInset(Text(values[4].trim())),
                        ],
                      ]),
          ),
    ];
