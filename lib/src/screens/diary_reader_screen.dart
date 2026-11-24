import 'package:flutter/material.dart';
import '../models.dart';
import '../models/diary_content.dart';
import '../services/malva_api_client.dart';
import '../widgets/diary_body.dart';
import '../widgets/diary_design.dart';

class DiaryReaderScreen extends StatefulWidget {
  const DiaryReaderScreen(
      {super.key,
      required this.entries,
      required this.initialId,
      required this.api,
      this.token,
      required this.onEdit,
      required this.onDelete,
      required this.onVault,
      required this.onRead});
  final List<DiaryEntry> entries;
  final String initialId;
  final MalvaApiClient api;
  final String? token;
  final ValueChanged<DiaryEntry> onEdit;
  final Future<bool> Function(DiaryEntry) onDelete;
  final Future<bool> Function(DiaryEntry) onVault;
  final void Function(DiaryEntry, bool) onRead;
  @override
  State<DiaryReaderScreen> createState() => _DiaryReaderScreenState();
}

class _DiaryReaderScreenState extends State<DiaryReaderScreen> {
  late final _entries = [...widget.entries];
  late int _index = _entries.indexWhere((e) => e.id == widget.initialId);
  bool _busy = false;
  String? _error;
  DiaryEntry get _entry => _entries[_index];
  @override
  Widget build(BuildContext context) {
    final content = DiaryContent.parse(_entry.note);
    return DiaryTheme(
        child: Scaffold(
            backgroundColor: diaryPaper,
            appBar: AppBar(
                backgroundColor: diaryPaper,
                foregroundColor: diaryPlum,
                title: const Text('Halaman Cerita Jurnal',
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: diaryPlum)),
                actions: [
                  PopupMenuButton<String>(
                      tooltip: 'Aksi jurnal',
                      enabled: !_busy,
                      onSelected: (v) async {
                        if (v == 'edit') widget.onEdit(_entry);
                        if (v == 'delete') {
                          setState(() => _busy = true);
                          await widget.onDelete(_entry);
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                      itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'edit', child: Text('Edit Jurnal')),
                            PopupMenuItem(
                                value: 'delete', child: Text('Hapus Jurnal'))
                          ])
                ]),
            body: SafeArea(
                child: ListView(padding: const EdgeInsets.all(16), children: [
              DiaryCard(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                    Row(children: [
                      Expanded(
                          child: Text(diaryDate(_entry.createdAt),
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: diaryPlum,
                                  fontWeight: FontWeight.w700))),
                      DiaryPalettePill(palette: content.palette)
                    ]),
                    const SizedBox(height: 20),
                    Text(_entry.title,
                        style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            height: 1.3)),
                    const SizedBox(height: 20),
                    DiaryBody(
                        note: _entry.note,
                        api: widget.api,
                        token: widget.token),
                    if (_entry.professionalFeedback?.trim().isNotEmpty ??
                        false) ...[
                      const Divider(height: 32),
                      Text(
                          'Catatan profesional: ${_entry.professionalFeedback}',
                          style: const TextStyle(fontSize: 13, height: 1.6))
                    ],
                    const SizedBox(height: 24),
                    FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                final next = _entry.copyWith(
                                    note: content
                                        .copyWith(inVault: !content.inVault)
                                        .encode());
                                setState(() {
                                  _busy = true;
                                  _error = null;
                                });
                                final success = await widget.onVault(next);
                                if (!mounted) return;
                                setState(() {
                                  _busy = false;
                                  if (success) {
                                    _entries[_index] = next;
                                  } else {
                                    _error =
                                        'Perubahan Ruang Positif belum tersimpan. Coba lagi.';
                                  }
                                });
                              },
                        icon: Icon(content.inVault
                            ? Icons.bookmark
                            : Icons.bookmark_border),
                        label: Text(content.inVault
                            ? 'Tersimpan di Ruang Positif'
                            : 'Simpan ke Ruang Positif')),
                    if (_busy) const LinearProgressIndicator(),
                    if (_error != null)
                      Text(_error!,
                          style:
                              const TextStyle(color: Colors.red, fontSize: 12))
                  ])),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                    child: TextButton.icon(
                        onPressed: _busy || _index == _entries.length - 1
                            ? null
                            : () => _move(1),
                        icon: const Icon(Icons.chevron_left),
                        label: const Text('Sebelumnya',
                            style: TextStyle(fontSize: 11)))),
                Expanded(
                    child: TextButton.icon(
                        onPressed:
                            _busy || _index == 0 ? null : () => _move(-1),
                        icon: const Icon(Icons.chevron_right),
                        label: const Text('Berikutnya',
                            style: TextStyle(fontSize: 11))))
              ])
            ]))));
  }

  void _move(int delta) {
    setState(() {
      _index += delta;
      _error = null;
    });
    widget.onRead(_entry, true);
  }
}
