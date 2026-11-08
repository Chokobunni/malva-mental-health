import 'package:flutter/material.dart';
import '../models.dart';
import '../time/wib.dart';

class DiaryFormSheet extends StatefulWidget {
  const DiaryFormSheet(
      {super.key, this.initialEntry, required this.onSave, this.onDelete});
  final DiaryEntry? initialEntry;
  final ValueChanged<DiaryEntry> onSave;
  final VoidCallback? onDelete;
  @override
  State<DiaryFormSheet> createState() => _DiaryFormSheetState();
}

class _DiaryFormSheetState extends State<DiaryFormSheet> {
  late final _title =
      TextEditingController(text: widget.initialEntry?.title ?? '');
  late final _note =
      TextEditingController(text: widget.initialEntry?.note ?? '');
  String? _error;
  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            18, 0, 18, MediaQuery.viewInsetsOf(context).bottom + 18),
        child: SingleChildScrollView(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              Text(widget.initialEntry == null ? 'Tambah Diary' : 'Edit Diary',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 16),
              TextField(
                  controller: _title,
                  textInputAction: TextInputAction.next,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Judul')),
              const SizedBox(height: 8),
              const Text('Ceritakan harimu secara singkat.'),
              const SizedBox(height: 10),
              TextField(
                  controller: _note,
                  minLines: 5,
                  maxLines: 10,
                  maxLength: 10000,
                  decoration:
                      const InputDecoration(labelText: 'Catatan diary')),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: _save,
                  child: Text(widget.initialEntry == null
                      ? 'Simpan Entry'
                      : 'Simpan Perubahan')),
              if (widget.onDelete != null)
                TextButton.icon(
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Hapus Diary')),
            ])),
      );
  void _save() {
    if (_note.text.trim().isEmpty) {
      setState(() => _error = 'Isi catatan diary terlebih dahulu.');
      return;
    }
    final previous = widget.initialEntry;
    widget.onSave(DiaryEntry(
      id: previous?.id ?? 'diary_${wibNow().microsecondsSinceEpoch}',
      createdAt: previous?.createdAt ?? wibNow(),
      // Retain the legacy wire field without using it as a diary input.
      mood: previous?.mood ?? MoodValue.okay,
      title: _title.text.trim().isEmpty ? 'Catatan harian' : _title.text.trim(),
      note: _note.text.trim(),
      professionalFeedback: previous?.professionalFeedback,
    ));
  }
}
