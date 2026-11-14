import 'dart:typed_data';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../platform/platform_providers.dart';
import '../models.dart';
import '../models/diary_content.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../time/wib.dart';
import '../widgets/diary_body.dart';
import '../widgets/friendly_error.dart';
import 'diary_drawing_screen.dart';

class DiaryEditorScreen extends ConsumerStatefulWidget {
  const DiaryEditorScreen(
      {super.key,
      this.initialEntry,
      required this.api,
      required this.accessToken,
      this.protectRoute,
      required this.onSave});
  final DiaryEntry? initialEntry;
  final MalvaApiClient api;
  final String? accessToken;
  final Widget Function(Widget)? protectRoute;
  final Future<bool> Function(DiaryEntry) onSave;
  @override
  ConsumerState<DiaryEditorScreen> createState() => _DiaryEditorScreenState();
}

class _DiaryEditorScreenState extends ConsumerState<DiaryEditorScreen> {
  late final _title =
      TextEditingController(text: widget.initialEntry?.title ?? '');
  late final _original = DiaryContent.parse(widget.initialEntry?.note ?? '');
  late final _note = TextEditingController(text: _original.text);
  late final _date = widget.initialEntry?.createdAt ?? wibNow();
  late String _font = _original.font;
  late double _size = _original.size, _height = _original.height;
  late int _color = _original.color;
  late TextAlign _align = _original.align;
  late final _media = [..._original.media];
  bool _busy = false, _saved = false, _mediaChanged = false;
  String? _error;
  DiaryContent get _content => DiaryContent(
      text: _note.text.trim(),
      font: _font,
      size: _size,
      height: _height,
      color: _color,
      align: _align,
      media: _media);
  bool get _dirty =>
      _mediaChanged ||
      _title.text != (widget.initialEntry?.title ?? '') ||
      _content.encode() != _original.encode();
  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<bool> _discard() async {
    if (_busy) return false;
    if (!_dirty || _saved) return true;
    return await showDialog<bool>(
            context: context,
            builder: (dialog) => AlertDialog(
                    title: const Text('Tinggalkan catatan?'),
                    content: const Text('Perubahan belum tersimpan.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialog, false),
                          child: const Text('Lanjut menulis')),
                      FilledButton(
                          onPressed: () => Navigator.pop(dialog, true),
                          child: const Text('Tinggalkan'))
                    ])) ??
        false;
  }

  Future<void> _back() async {
    if (await _discard() && mounted) Navigator.pop(context);
  }

  Future<void> _save() async {
    if (_busy) return;
    final content = _content;
    if (content.text.isEmpty && _media.isEmpty) {
      setState(() =>
          _error = 'Tuliskan cerita atau tambahkan gambar terlebih dahulu.');
      return;
    }
    final note = content.encode();
    if (utf8.encode(_title.text.trim()).length > 160) {
      setState(() =>
          _error = 'Judul terlalu panjang. Gunakan judul yang lebih singkat.');
      return;
    }
    if (utf8.encode(note).length > 6000) {
      setState(() => _error =
          'Catatan terlalu panjang. Ringkas tulisan atau kurangi lampiran agar dapat disimpan.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final previous = widget.initialEntry;
      final result = await widget.onSave(DiaryEntry(
          id: previous?.id ?? 'diary_${_date.microsecondsSinceEpoch}',
          createdAt: _date,
          mood: previous?.mood ?? MoodValue.okay,
          title: _title.text.trim().isEmpty
              ? 'Catatan harian'
              : _title.text.trim(),
          note: note,
          professionalFeedback: previous?.professionalFeedback));
      if (!mounted) return;
      if (result) {
        setState(() => _saved = true);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.pop(context);
        });
      } else {
        setState(() => _error =
            'Diary belum tersimpan. Ceritamu tetap di sini, silakan coba lagi.');
      }
    } on Object catch (e) {
      if (mounted)
        setState(
            () => _error = 'Diary belum tersimpan: ${friendlyErrorMessage(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _upload(Uint8List bytes, String kind) async {
    final token = widget.accessToken;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Masuk ke akun untuk menyimpan gambar diary.');
      return;
    }
    if (_media.length >= 6) {
      setState(() => _error = 'Maksimal 6 gambar dalam satu diary.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (bytes.length > 20 * 1024 * 1024)
        throw const FormatException('Pilih gambar berukuran maksimal 20 MB.');
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = await ui.ImageDescriptor.encoded(buffer);
      ui.Codec? codec;
      try {
        final scale = 1600 /
            (descriptor.width > descriptor.height
                ? descriptor.width
                : descriptor.height);
        codec = await descriptor.instantiateCodec(
            targetWidth: scale < 1 ? (descriptor.width * scale).round() : null,
            targetHeight:
                scale < 1 ? (descriptor.height * scale).round() : null);
        final frame = await codec.getNextFrame();
        final png =
            await frame.image.toByteData(format: ui.ImageByteFormat.png);
        frame.image.dispose();
        if (png == null || png.lengthInBytes > 5 * 1024 * 1024)
          throw const FormatException(
              'Gambar terlalu besar. Pilih gambar lain.');
        if (!mounted) return;
        final url = await widget.api.uploadDiaryImage(
            accessToken: token,
            fileName: 'diary.png',
            bytes: png.buffer.asUint8List(),
            mimeType: 'image/png');
        if (!mounted) return;
        final item = DiaryMedia(url: url, kind: kind);
        if (item.resolve(widget.api.baseUri) == null)
          throw const FormatException('Alamat gambar tidak valid.');
        setState(() {
          _media.add(item);
          _mediaChanged = true;
        });
      } finally {
        codec?.dispose();
        descriptor.dispose();
        buffer.dispose();
      }
    } on Object catch (e) {
      if (mounted)
        setState(() => _error =
            e is FormatException ? e.message : friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pick(String kind) async {
    Navigator.pop(context);
    try {
      final file = await ref
          .read(filePickerProvider)
          .pick(kind, maxWidth: 1600, maxHeight: 1600, imageQuality: 90);
      if (file == null || !mounted) return;
      await _upload(file.bytes, 'photo');
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    }
  }

  Future<void> _draw() async {
    FocusManager.instance.primaryFocus?.unfocus();
    final png = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(
            builder: (_) =>
                widget.protectRoute?.call(const DiaryDrawingScreen()) ??
                const DiaryDrawingScreen()));
    if (png != null && mounted) await _upload(png, 'drawing');
  }

  void _addMedia() {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: MalvaColors.paper,
        builder: (sheet) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Row(children: [
                    const Expanded(
                        child: Text('Tambah media',
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w800))),
                    IconButton(
                        tooltip: 'Tutup media',
                        onPressed: () => Navigator.pop(sheet),
                        icon: const Icon(Icons.close))
                  ]),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                        child: _mediaOption(Icons.camera_alt_outlined, 'Kamera',
                            MalvaColors.amber, () => _pick('camera'))),
                    const SizedBox(width: 16),
                    Expanded(
                        child: _mediaOption(
                            Icons.photo_library_outlined,
                            'Galeri foto',
                            MalvaColors.orchid,
                            () => _pick('image'))),
                  ])
                ]))));
  }

  Widget _mediaOption(
          IconData icon, String label, Color color, VoidCallback action) =>
      InkWell(
          onTap: action,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                        color: color.withValues(alpha: .15),
                        borderRadius: BorderRadius.circular(22)),
                    child: Icon(icon, color: color, size: 34)),
                const SizedBox(height: 10),
                Text(label, style: const TextStyle(fontWeight: FontWeight.w700))
              ])));

  void _fonts() {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        backgroundColor: MalvaColors.paper,
        builder: (sheet) => StatefulBuilder(builder: (context, update) {
              void change(VoidCallback fn) {
                setState(fn);
                update(() {});
              }

              return SafeArea(
                  child: ConstrainedBox(
                      constraints: BoxConstraints(
                          maxHeight: MediaQuery.sizeOf(context).height * .65),
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(children: [
                                  const Expanded(
                                      child: Text('Font',
                                          style: TextStyle(
                                              fontSize: 22,
                                              fontWeight: FontWeight.w800))),
                                  IconButton(
                                      tooltip: 'Selesai mengatur font',
                                      onPressed: () => Navigator.pop(sheet),
                                      icon: const Icon(Icons.check,
                                          color: MalvaColors.seed))
                                ]),
                                const SizedBox(height: 8),
                                Wrap(spacing: 10, children: [
                                  ChoiceChip(
                                      label: const Text('Roboto'),
                                      selected: _font == 'roboto',
                                      onSelected: (_) =>
                                          change(() => _font = 'roboto')),
                                  ChoiceChip(
                                      label: const Text('Jakarta',
                                          style: TextStyle(
                                              fontFamily: 'PlusJakartaSans')),
                                      selected: _font == 'jakarta',
                                      onSelected: (_) =>
                                          change(() => _font = 'jakarta'))
                                ]),
                                const SizedBox(height: 12),
                                Row(children: [
                                  for (final (label, size) in [
                                    ('H1', 30.0),
                                    ('H2', 24.0),
                                    ('H3', 20.0),
                                    ('H4', 18.0)
                                  ])
                                    Expanded(
                                        child: TextButton(
                                            style: TextButton.styleFrom(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                        horizontal: 4),
                                                backgroundColor: _size == size
                                                    ? const Color(0xffeddef4)
                                                    : null),
                                            onPressed: () =>
                                                change(() => _size = size),
                                            child: FittedBox(
                                                fit: BoxFit.scaleDown,
                                                child: Text(label,
                                                    maxLines: 1,
                                                    style: TextStyle(
                                                        fontSize: size,
                                                        fontWeight:
                                                            FontWeight.w800)))))
                                ]),
                                const SizedBox(height: 12),
                                Row(children: [
                                  for (final (align, icon, tip) in [
                                    (
                                      TextAlign.left,
                                      Icons.format_align_left,
                                      'Rata kiri'
                                    ),
                                    (
                                      TextAlign.center,
                                      Icons.format_align_center,
                                      'Rata tengah'
                                    ),
                                    (
                                      TextAlign.right,
                                      Icons.format_align_right,
                                      'Rata kanan'
                                    )
                                  ])
                                    IconButton(
                                        isSelected: _align == align,
                                        tooltip: tip,
                                        onPressed: () =>
                                            change(() => _align = align),
                                        icon: Icon(icon)),
                                  const Spacer(),
                                  const Icon(Icons.format_line_spacing,
                                      size: 20),
                                  const SizedBox(width: 8),
                                  DropdownButton<double>(
                                      value:
                                          [1.3, 1.6, 1.8, 2.0].contains(_height)
                                              ? _height
                                              : 1.6,
                                      items: [1.3, 1.6, 1.8, 2.0]
                                          .map((v) => DropdownMenuItem(
                                              value: v, child: Text('$v')))
                                          .toList(),
                                      onChanged: (v) {
                                        if (v != null)
                                          change(() => _height = v);
                                      })
                                ]),
                                const SizedBox(height: 12),
                                Wrap(spacing: 10, runSpacing: 10, children: [
                                  for (final color in [
                                    0xff201b24,
                                    0xff606068,
                                    0xff721d36,
                                    0xff8e44ad,
                                    0xffb65acb,
                                    0xffd44380,
                                    0xffe58be8,
                                    0xff365e91,
                                    0xff197c67
                                  ])
                                    Semantics(
                                        label:
                                            'Warna teks ${color.toRadixString(16)}',
                                        selected: _color == color,
                                        button: true,
                                        child: InkWell(
                                            onTap: () =>
                                                change(() => _color = color),
                                            customBorder: const CircleBorder(),
                                            child: Container(
                                                width: 42,
                                                height: 42,
                                                decoration: BoxDecoration(
                                                    shape: BoxShape.circle,
                                                    color: Color(color),
                                                    border: Border.all(
                                                        width: 3,
                                                        color: _color == color
                                                            ? MalvaColors.amber
                                                            : Colors
                                                                .transparent)),
                                                child: _color == color
                                                    ? const Icon(Icons.check,
                                                        color: Colors.white,
                                                        size: 20)
                                                    : null))),
                                  IconButton(
                                      tooltip: 'Pulihkan font',
                                      onPressed: () => change(() {
                                            _color = 0xff201b24;
                                            _size = 18;
                                            _height = 1.6;
                                            _align = TextAlign.left;
                                            _font = 'roboto';
                                          }),
                                      icon: const Icon(Icons.format_clear)),
                                ]),
                              ]))));
            }));
  }

  @override
  Widget build(BuildContext context) {
    final at = toWib(_date);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des'
    ];
    return PopScope(
        canPop: _saved || (!_dirty && !_busy),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: Scaffold(
          backgroundColor: const Color(0xfff6effa),
          appBar: AppBar(
              backgroundColor: const Color(0xfff6effa),
              foregroundColor: MalvaColors.plum,
              leading: IconButton(
                  tooltip: 'Kembali',
                  onPressed: _busy ? null : _back,
                  icon: const Icon(Icons.arrow_back)),
              title: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                      widget.initialEntry == null
                          ? 'Tambah Diary'
                          : 'Edit Diary',
                      maxLines: 1,
                      style: const TextStyle(
                          fontFamily: 'Roboto',
                          color: MalvaColors.plum,
                          fontSize: 18,
                          fontWeight: FontWeight.w800))),
              actions: [
                Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: FilledButton(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(76, 42),
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16)),
                        onPressed: _busy ? null : _save,
                        child: const Text('Simpan',
                            style:
                                TextStyle(fontFamily: 'Roboto', fontSize: 14))))
              ]),
          body: SafeArea(
              child: Column(children: [
            if (_busy) const LinearProgressIndicator(minHeight: 2),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
                  child: Text(_error!,
                      style: const TextStyle(color: MalvaColors.danger))),
            Expanded(
                child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${at.day}'.padLeft(2, '0'),
                                    style: const TextStyle(
                                        fontSize: 54,
                                        height: 1,
                                        fontWeight: FontWeight.w800,
                                        color: MalvaColors.plum)),
                                const SizedBox(width: 10),
                                Expanded(
                                    child: Padding(
                                        padding:
                                            const EdgeInsets.only(bottom: 4),
                                        child: Text(
                                            '${months[at.month - 1]} ${at.year}',
                                            style: const TextStyle(
                                                fontSize: 21,
                                                color: MalvaColors.plum)))),
                              ]),
                          const SizedBox(height: 28),
                          TextField(
                              controller: _title,
                              enabled: !_busy,
                              maxLength: 160,
                              textInputAction: TextInputAction.next,
                              onChanged: (_) => setState(() {}),
                              style: const TextStyle(
                                  fontSize: 27,
                                  fontWeight: FontWeight.w800,
                                  color: MalvaColors.ink),
                              decoration: const InputDecoration(
                                  hintText: 'Judul',
                                  hintStyle: TextStyle(
                                      color: Color(0xff9a8d9f),
                                      fontWeight: FontWeight.w500),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                  contentPadding: EdgeInsets.zero,
                                  counterText: '')),
                          const SizedBox(height: 18),
                          for (final media in _media)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 16),
                                child: DiaryImage(
                                    media: media,
                                    api: widget.api,
                                    token: widget.accessToken,
                                    onRemove: _busy
                                        ? null
                                        : () => setState(() {
                                              _media.remove(media);
                                              _mediaChanged = true;
                                            }))),
                          TextField(
                              controller: _note,
                              enabled: !_busy,
                              minLines: 12,
                              maxLines: null,
                              maxLength: 5000,
                              onChanged: (_) => setState(() {}),
                              textAlign: _align,
                              style: _content.style,
                              decoration: const InputDecoration(
                                  alignLabelWithHint: true,
                                  hintText: 'Catatan diary',
                                  hintStyle:
                                      TextStyle(color: Color(0xff9a8d9f)),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  filled: false,
                                  contentPadding: EdgeInsets.zero,
                                  counterText: '')),
                        ]))),
            Material(
                color: Colors.white,
                elevation: 4,
                child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    child: Row(children: [
                      _tool(Icons.add_photo_alternate_outlined, 'Media',
                          'Tambah media', _addMedia),
                      _tool(Icons.draw_outlined, 'Gambar', 'Menggambar', _draw),
                      _tool(Icons.text_fields_rounded, 'Font',
                          'Pengaturan font', _fonts),
                    ]))),
          ])),
        ));
  }

  Widget _tool(IconData icon, String label, String tooltip, VoidCallback fn) =>
      Expanded(
          child: Tooltip(
              message: tooltip,
              child: TextButton(
                  onPressed: _busy ? null : fn,
                  style: TextButton.styleFrom(
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 6)),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, size: 22),
                    const SizedBox(height: 4),
                    Text(label, maxLines: 1),
                  ]))));
}
