import 'dart:typed_data';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../platform/platform_providers.dart';
import '../models.dart';
import '../models/diary_content.dart';
import '../models/diary_catalog.dart';
import '../widgets/diary_design.dart';
import '../services/malva_api_client.dart';
import '../services/diary_prompt_history.dart';
import '../theme.dart';
import '../time/wib.dart';
import '../widgets/diary_access.dart';
import '../widgets/diary_body.dart';
import '../widgets/friendly_error.dart';
import 'diary_drawing_screen.dart';

class DiaryEditorScreen extends ConsumerStatefulWidget {
  const DiaryEditorScreen(
      {super.key,
      this.initialEntry,
      this.initialPrompt,
      this.onPromptRefresh,
      this.promptHistory,
      required this.api,
      required this.accessToken,
      this.protectRoute,
      this.onManageAccess,
      required this.onSave});
  final DiaryEntry? initialEntry;
  final DiaryPrompt? initialPrompt;
  final VoidCallback? onPromptRefresh;
  final DiaryPromptHistory? promptHistory;
  final MalvaApiClient api;
  final String? accessToken;
  final Widget Function(Widget)? protectRoute;
  final Future<DiaryEntry?> Function(DiaryEntry, bool isUpdate) onSave;
  final Future<void> Function(
          BuildContext, DiaryEntry, ValueChanged<List<DiaryAccessRecipient>>)?
      onManageAccess;
  @override
  ConsumerState<DiaryEditorScreen> createState() => _DiaryEditorScreenState();
}

class _DiaryEditorScreenState extends ConsumerState<DiaryEditorScreen> {
  late DiaryEntry? _persistedEntry = widget.initialEntry;
  late final _title =
      TextEditingController(text: widget.initialEntry?.title ?? '');
  late final _original = widget.initialEntry == null
      ? DiaryContent(
          text: '',
          palette: null,
          promptId: widget.initialPrompt?.id,
          inVault: true)
      : DiaryContent.parse(widget.initialEntry!.note);
  late final _note = TextEditingController(text: _original.text);
  late DateTime _date = widget.initialEntry?.createdAt ?? wibNow();
  late String? _palette = _original.palette;
  late DiaryPrompt? _prompt = _original.prompt;
  late bool _inVault = _original.inVault;
  late final _selfNote = TextEditingController(text: _original.selfNote);
  final _tagInput = TextEditingController();
  late final _tags = [..._original.tags];
  late final _appreciations = {..._original.appreciations};
  late bool _showCards =
      widget.initialEntry == null && widget.initialPrompt != null;

  late String _font = _original.font;
  late double _size = _original.size, _height = _original.height;
  late int _color = _original.color;
  late TextAlign _align = _original.align;
  late final _media = [..._original.media];
  late String _savedTitle = widget.initialEntry?.title ?? '';
  late String _savedNote = _original.encode();
  late List<DiaryAccessRecipient> _recipients =
      widget.initialEntry?.accessRecipients ?? const [];
  bool _busy = false, _mediaChanged = false;
  String? _error;
  DiaryContent get _content => DiaryContent(
      text: _note.text.trim(),
      font: _font,
      size: _size,
      height: _height,
      color: _color,
      align: _align,
      media: _media,
      palette: _palette,
      promptId: _prompt?.id,
      selfNote: _selfNote.text.trim(),
      tags: _tags,
      appreciations: _appreciations.toList(),
      brushColors: _original.brushColors,
      inVault: _inVault);
  bool get _dirty =>
      _mediaChanged ||
      _title.text != _savedTitle ||
      _content.encode() != _savedNote;
  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _selfNote.dispose();
    _tagInput.dispose();
    _affirmationFocus.dispose();
    super.dispose();
  }

  Future<bool> _discard() async {
    if (_busy) return false;
    if (!_dirty) return true;
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

  Future<DiaryEntry?> _save({bool close = true}) async {
    if (_busy) return null;
    final content = _content;
    if (content.text.isEmpty && _media.isEmpty) {
      setState(() =>
          _error = 'Tuliskan cerita atau tambahkan gambar terlebih dahulu.');
      return null;
    }
    final note = content.encode();
    if (utf8.encode(_title.text.trim()).length > 160) {
      setState(() =>
          _error = 'Judul terlalu panjang. Gunakan judul yang lebih singkat.');
      return null;
    }
    if (utf8.encode(note).length > 6000) {
      setState(() => _error =
          'Catatan terlalu panjang. Ringkas tulisan atau kurangi lampiran agar dapat disimpan.');
      return null;
    }
    if (!close) {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialog) {
            final confirmation = AlertDialog(
                title: const Text('Simpan diary terlebih dahulu?'),
                content:
                    const Text('Setelah disimpan, kamu bisa memilih penerima.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialog, false),
                      child: const Text('Batal')),
                  FilledButton(
                      onPressed: () => Navigator.pop(dialog, true),
                      child: const Text('Simpan dan lanjutkan'))
                ]);
            return widget.protectRoute?.call(confirmation) ?? confirmation;
          });
      if (confirmed != true || !mounted || _busy) return null;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final previous = _persistedEntry;
      final title = _title.text;
      final result = await widget.onSave(
          DiaryEntry(
              id: previous?.id ?? 'diary_${_date.microsecondsSinceEpoch}',
              createdAt: _date,
              mood: previous?.mood ?? MoodValue.okay,
              title: title.trim().isEmpty ? 'Catatan harian' : title.trim(),
              note: note,
              professionalFeedback: previous?.professionalFeedback),
          previous != null);
      if (!mounted) return null;
      if (result != null) {
        setState(() {
          _persistedEntry = result;
          _savedTitle = title;
          _savedNote = note;
          _mediaChanged = false;
          _recipients = result.accessRecipients;
        });
        if (close) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }
      } else {
        setState(() => _error =
            'Diary belum tersimpan. Ceritamu tetap di sini, silakan coba lagi.');
      }
      return result;
    } on Object catch (e) {
      if (mounted)
        setState(
            () => _error = 'Diary belum tersimpan: ${friendlyErrorMessage(e)}');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _manageAccess() async {
    final manage = widget.onManageAccess;
    if (_busy || manage == null) return;
    FocusScope.of(context).unfocus();
    final entry = _persistedEntry ?? await _save(close: false);
    if (!mounted || entry == null) return;
    await manage(context, entry, (recipients) {
      if (mounted) setState(() => _recipients = recipients);
    });
  }

  Future<void> _upload(Uint8List bytes, String kind,
      {DiaryMedia? replace, List<int> colors = const []}) async {
    final token = widget.accessToken;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Masuk ke akun untuk menyimpan gambar diary.');
      return;
    }
    if (replace == null && _media.length >= 6) {
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
        final item = DiaryMedia(url: url, kind: kind, colors: colors);
        if (item.resolve(widget.api.baseUri) == null)
          throw const FormatException('Alamat gambar tidak valid.');
        setState(() {
          if (replace == null) {
            _media.add(item);
          } else {
            final index = _media.indexOf(replace);
            if (index < 0) return;
            _media[index] = item;
          }
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

  Future<void> _pick(String kind, {DiaryMedia? replace}) async {
    if (_busy) return;
    if (replace == null) Navigator.pop(context);
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final file = await ref
          .read(filePickerProvider)
          .pick(kind, maxWidth: 1600, maxHeight: 1600, imageQuality: 90);
      if (file == null || !mounted) return;
      await _upload(file.bytes, 'photo', replace: replace);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _draw({DiaryMedia? replace}) async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      _busy = true;
      _error = null;
    });
    ui.Image? initialImage;
    try {
      if (replace != null) {
        final bytes = await widget.api.fetchDiaryImage(
            accessToken: widget.accessToken ?? '', url: replace.url);
        if (!mounted) return;
        final codec = await ui.instantiateImageCodec(bytes);
        try {
          initialImage = (await codec.getNextFrame()).image;
        } finally {
          codec.dispose();
        }
        if (!mounted) return;
      }
      var colors = <int>[...?replace?.colors];
      final drawing = DiaryDrawingScreen(
          initialImage: initialImage,
          onColorsUsed: (used) => colors = {...colors, ...used}.toList());
      final png = await Navigator.push<Uint8List>(
          context,
          MaterialPageRoute(
              builder: (_) => widget.protectRoute?.call(drawing) ?? drawing));
      if (png != null && mounted)
        await _upload(png, 'drawing', replace: replace, colors: colors);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      initialImage?.dispose();
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addMedia() {
    FocusManager.instance.primaryFocus?.unfocus();
    showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        backgroundColor: MalvaColors.paper,
        builder: (sheet) => (widget.protectRoute ?? (child) => child)(SafeArea(
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
                ])))));
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
        builder: (sheet) => (widget.protectRoute ?? (child) => child)(
                StatefulBuilder(builder: (context, update) {
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
            })));
  }

  void _addTag() {
    final value = _tagInput.text.trim().replaceAll(RegExp(r'^#+'), '');
    if (value.isEmpty) return;
    if (value.length > 32 || _tags.length >= 20) {
      setState(() =>
          _error = 'Gunakan maksimal 20 topik, masing-masing 32 karakter.');
      return;
    }
    if (!_tags.any((t) => t.toLowerCase() == value.toLowerCase()))
      setState(() => _tags.add(value));
    _tagInput.clear();
  }

  Future<void> _chooseDate() async {
    if (_persistedEntry != null || _busy) return;
    final now = toWib(wibNow()), current = toWib(_date);
    final picked = await showDatePicker(
        context: context,
        initialDate: DateTime(current.year, current.month, current.day),
        firstDate: DateTime(2000),
        lastDate: DateTime(now.year, now.month, now.day));
    if (picked != null && mounted)
      setState(() => _date = wibFromParts(
          picked.year, picked.month, picked.day, current.hour, current.minute));
  }

  @override
  Widget build(BuildContext context) {
    final at = toWib(_date), paper = diaryEditorPaper(_palette);
    return DiaryTheme(
        child: PopScope(
            canPop: !_dirty && !_busy,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) _back();
            },
            child: Scaffold(
                backgroundColor: paper,
                appBar: AppBar(
                    backgroundColor: paper,
                    foregroundColor: diaryPlum,
                    centerTitle: true,
                    leading: IconButton(
                        tooltip: 'Kembali',
                        onPressed: _busy ? null : _back,
                        icon: const Icon(Icons.arrow_back)),
                    title: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                            _persistedEntry == null
                                ? 'Tambah Diary'
                                : 'Edit Diary',
                            style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 16,
                                color: diaryPlum,
                                fontWeight: FontWeight.w800))),
                    actions: [
                      Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: FilledButton(
                              onPressed: _busy ? null : _save,
                              child: const Text('Simpan')))
                    ]),
                body: SafeArea(
                    child: Column(children: [
                  if (_busy) const LinearProgressIndicator(minHeight: 2),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(_error!,
                            style: const TextStyle(
                                color: MalvaColors.danger, fontSize: 12))),
                  Expanded(
                      child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                LayoutBuilder(
                                    builder: (context, box) => Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.center,
                                            children: [
                                              Expanded(
                                                  child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                    FittedBox(
                                                        fit: BoxFit.scaleDown,
                                                        child: Row(
                                                            crossAxisAlignment:
                                                                CrossAxisAlignment
                                                                    .center,
                                                            children: [
                                                              Text(
                                                                  '${at.day}'
                                                                      .padLeft(2,
                                                                          '0'),
                                                                  style: const TextStyle(
                                                                      fontSize:
                                                                          44,
                                                                      height: 1,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w800,
                                                                      color:
                                                                          diaryPlum)),
                                                              const SizedBox(
                                                                  width: 7),
                                                              Text(
                                                                  '${diaryMonths[at.month - 1].substring(0, 3)} ${at.year}',
                                                                  style: const TextStyle(
                                                                      fontSize:
                                                                          14,
                                                                      fontWeight:
                                                                          FontWeight
                                                                              .w700,
                                                                      color:
                                                                          diaryPlum))
                                                            ])),
                                                    if (_persistedEntry == null)
                                                      TextButton(
                                                          onPressed: _busy
                                                              ? null
                                                              : _chooseDate,
                                                          style: TextButton.styleFrom(
                                                              padding:
                                                                  EdgeInsets
                                                                      .zero,
                                                              minimumSize:
                                                                  const Size(
                                                                      0, 28),
                                                              tapTargetSize:
                                                                  MaterialTapTargetSize
                                                                      .shrinkWrap),
                                                          child: const Text(
                                                              'Ubah Tanggal ⌄',
                                                              style: TextStyle(
                                                                  fontSize:
                                                                      10)))
                                                  ])),
                                              Container(
                                                  width: 1,
                                                  height: 48,
                                                  margin: const EdgeInsets
                                                      .symmetric(
                                                      horizontal: 12),
                                                  color:
                                                      const Color(0xffe9deed)),
                                              Flexible(
                                                  child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                    Text(
                                                        'Palet: ${diaryPalettes[_palette]?.$1 ?? 'Belum Dipilih'}',
                                                        style: const TextStyle(
                                                            fontSize: 10,
                                                            color: diaryPlum)),
                                                    const SizedBox(height: 6),
                                                    Container(
                                                        padding:
                                                            const EdgeInsets
                                                                .all(3),
                                                        decoration: BoxDecoration(
                                                            color: Colors.white
                                                                .withValues(
                                                                    alpha: .8),
                                                            borderRadius:
                                                                BorderRadius
                                                                    .circular(
                                                                        24)),
                                                        child: Row(
                                                            mainAxisSize:
                                                                MainAxisSize
                                                                    .min,
                                                            children: [
                                                              for (final key
                                                                  in diaryPalettes
                                                                      .keys)
                                                                Expanded(
                                                                    child: Semantics(
                                                                        selected:
                                                                            _palette ==
                                                                                key,
                                                                        child: IconButton(
                                                                            tooltip:
                                                                                'Palet ${diaryPalettes[key]!.$1}',
                                                                            onPressed: _busy
                                                                                ? null
                                                                                : () => setState(() => _palette = key),
                                                                            padding: const EdgeInsets.all(3),
                                                                            constraints: const BoxConstraints(minWidth: 20, minHeight: 30),
                                                                            style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                                                                            icon: Container(width: 17, height: 17, decoration: BoxDecoration(color: diaryPalettes[key]!.$2, shape: BoxShape.circle, border: _palette == key ? Border.all(color: diaryPurple, width: 2) : null)))))
                                                            ]))
                                                  ]))
                                            ])),
                                const SizedBox(height: 2),
                                TextField(
                                    controller: _title,
                                    enabled: !_busy,
                                    maxLength: 160,
                                    textInputAction: TextInputAction.next,
                                    onChanged: (_) => setState(() {}),
                                    style: const TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 24,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xff1f2937)),
                                    decoration: const InputDecoration(
                                        hintText: 'Judul',
                                        hintStyle:
                                            TextStyle(color: Color(0xff9ca3af)),
                                        border: InputBorder.none,
                                        enabledBorder: InputBorder.none,
                                        focusedBorder: InputBorder.none,
                                        filled: false,
                                        contentPadding: EdgeInsets.zero,
                                        counterText: '')),
                                const SizedBox(height: 4),
                                Row(children: [
                                  Expanded(
                                      child: _editorAction(
                                          Icons.help_outline,
                                          'Pertanyaan Refleksi',
                                          () => setState(
                                              () => _showCards = !_showCards),
                                          selected: _showCards)),
                                  const SizedBox(width: 10),
                                  Expanded(
                                      child: _editorAction(
                                          _inVault
                                              ? Icons.bookmark
                                              : Icons.bookmark_border,
                                          'Positive Vault',
                                          () => setState(
                                              () => _inVault = !_inVault),
                                          selected: _inVault))
                                ]),
                                if (_showCards) ...[
                                  const SizedBox(height: 14),
                                  IgnorePointer(
                                      ignoring: _busy,
                                      child: DailyPromptCards(
                                          history: widget.promptHistory,
                                          onSelected: (p) =>
                                              setState(() => _prompt = p),
                                          onClose: () => setState(
                                              () => _showCards = false),
                                          onRefresh: widget.onPromptRefresh,
                                          onAnswer: (p) => setState(() {
                                                _prompt = p;
                                                _showCards = false;
                                              })))
                                ],
                                if (_prompt != null && !_showCards) ...[
                                  const SizedBox(height: 14),
                                  DiaryCard(
                                      padding: const EdgeInsets.all(14),
                                      color: Colors.white.withValues(alpha: .8),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            Row(children: [
                                              Expanded(
                                                  child: Text(
                                                      _prompt!.category
                                                          .toUpperCase(),
                                                      style: const TextStyle(
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          color: diaryPurple))),
                                              IconButton(
                                                  tooltip:
                                                      'Pilih pertanyaan lain',
                                                  onPressed: _busy
                                                      ? null
                                                      : () => setState(() =>
                                                          _showCards = true),
                                                  icon: const Icon(
                                                      Icons.refresh,
                                                      color: diaryPurple,
                                                      size: 18)),
                                              IconButton(
                                                  tooltip: 'Lepas pertanyaan',
                                                  onPressed: _busy
                                                      ? null
                                                      : () => setState(
                                                          () => _prompt = null),
                                                  icon: const Icon(Icons.close,
                                                      color: diaryPurple,
                                                      size: 18))
                                            ]),
                                            Text('“${_prompt!.question}”',
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                    fontStyle: FontStyle.italic,
                                                    height: 1.6,
                                                    color: diaryPlum))
                                          ]))
                                ],
                                if (widget.onManageAccess != null) ...[
                                  const SizedBox(height: 6),
                                  DiaryAccessRow(
                                      recipients: _recipients,
                                      showNames: true,
                                      onPressed: _busy ||
                                              widget.accessToken?.isNotEmpty !=
                                                  true
                                          ? null
                                          : _manageAccess),
                                ],
                                const SizedBox(height: 10),
                                DiaryCard(
                                    padding: const EdgeInsets.all(18),
                                    color: Colors.white.withValues(alpha: .82),
                                    radius: 24,
                                    child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                            minHeight:
                                                MediaQuery.sizeOf(context)
                                                        .height *
                                                    .40),
                                        child: TextField(
                                            controller: _note,
                                            enabled: !_busy,
                                            minLines: 10,
                                            maxLines: null,
                                            maxLength: 5000,
                                            onChanged: (_) => setState(() {}),
                                            textAlign: _align,
                                            style: _content.style,
                                            decoration: const InputDecoration(
                                                hintText:
                                                    'Tulis ceritamu di sini...',
                                                hintStyle: TextStyle(
                                                    fontFamily: 'Inter',
                                                    fontSize: 14,
                                                    color: Color(0xff6b7280)),
                                                border: InputBorder.none,
                                                enabledBorder: InputBorder.none,
                                                focusedBorder: InputBorder.none,
                                                filled: false,
                                                contentPadding: EdgeInsets.zero,
                                                counterText: '')))),
                                for (final media in _media)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 14),
                                      child: DiaryImage(
                                          media: media,
                                          api: widget.api,
                                          token: widget.accessToken,
                                          onEdit: _busy
                                              ? null
                                              : () => media.kind == 'drawing'
                                                  ? _draw(replace: media)
                                                  : _pick('image',
                                                      replace: media),
                                          onRemove: _busy
                                              ? null
                                              : () => setState(() {
                                                    _media.remove(media);
                                                    _mediaChanged = true;
                                                  }))),
                                const SizedBox(height: 10),
                                DiaryCard(
                                    padding: const EdgeInsets.all(16),
                                    color: Colors.white.withValues(alpha: .85),
                                    radius: 24,
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Row(children: [
                                            const Icon(Icons.sell_outlined,
                                                color: diaryPurple, size: 19),
                                            const SizedBox(width: 10),
                                            const Expanded(
                                                child: Text(
                                                    'Tandai Topik Cerita',
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: diaryPlum))),
                                            IconButton(
                                                tooltip: 'Tambah Topik',
                                                visualDensity:
                                                    VisualDensity.compact,
                                                constraints:
                                                    const BoxConstraints(
                                                        minWidth: 28,
                                                        minHeight: 28),
                                                padding: EdgeInsets.zero,
                                                style: IconButton.styleFrom(
                                                    tapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap),
                                                onPressed:
                                                    _busy ? null : _addTag,
                                                icon: const Icon(Icons.add,
                                                    color: diaryPurple,
                                                    size: 20))
                                          ]),
                                          if (_tags.isNotEmpty)
                                            Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                children: [
                                                  for (final tag in _tags)
                                                    InputChip(
                                                        label: Text('#$tag',
                                                            style:
                                                                const TextStyle(
                                                                    fontSize:
                                                                        11)),
                                                        onDeleted: _busy
                                                            ? null
                                                            : () => setState(
                                                                () => _tags
                                                                    .remove(
                                                                        tag)))
                                                ]),
                                          TextField(
                                              controller: _tagInput,
                                              enabled: !_busy,
                                              maxLength: 32,
                                              onSubmitted: (_) => _addTag(),
                                              decoration: const InputDecoration(
                                                  isDense: true,
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                          vertical: 4),
                                                  hintText: 'Tambah topik...',
                                                  prefixIcon: Padding(
                                                      padding: EdgeInsets.only(
                                                          right: 6),
                                                      child: Text('#',
                                                          style: TextStyle(
                                                              fontSize: 15,
                                                              color:
                                                                  diaryPurple))),
                                                  prefixIconConstraints:
                                                      BoxConstraints(
                                                          minWidth: 18,
                                                          minHeight: 20),
                                                  border: InputBorder.none,
                                                  enabledBorder:
                                                      InputBorder.none,
                                                  focusedBorder:
                                                      InputBorder.none,
                                                  filled: false,
                                                  counterText: ''),
                                              style: const TextStyle(
                                                  fontSize: 12)),
                                          const Divider(
                                              height: 12,
                                              color: Color(0xfff3e8ff)),
                                          Row(children: [
                                            const Icon(Icons.favorite_border,
                                                color: diaryPurple, size: 20),
                                            const SizedBox(width: 10),
                                            const Expanded(
                                                child: Text(
                                                    'Pesan Penguat Diri',
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: diaryPlum))),
                                            IconButton(
                                                tooltip:
                                                    'Tulis pesan penguat diri',
                                                visualDensity:
                                                    VisualDensity.compact,
                                                constraints:
                                                    const BoxConstraints(
                                                        minWidth: 28,
                                                        minHeight: 28),
                                                padding: EdgeInsets.zero,
                                                style: IconButton.styleFrom(
                                                    tapTargetSize:
                                                        MaterialTapTargetSize
                                                            .shrinkWrap),
                                                onPressed: _busy
                                                    ? null
                                                    : () => _affirmationFocus
                                                        .requestFocus(),
                                                icon: const Icon(Icons.add,
                                                    color: diaryPurple,
                                                    size: 20))
                                          ]),
                                          TextField(
                                              controller: _selfNote,
                                              focusNode: _affirmationFocus,
                                              enabled: !_busy,
                                              maxLength: 300,
                                              maxLines: null,
                                              onChanged: (_) => setState(() {}),
                                              style:
                                                  const TextStyle(fontSize: 12),
                                              decoration: const InputDecoration(
                                                  isDense: true,
                                                  contentPadding:
                                                      EdgeInsets.symmetric(
                                                          vertical: 4),
                                                  hintText:
                                                      'Tulis satu kalimat afirmasi hangat untuk dirimu...',
                                                  border: InputBorder.none,
                                                  enabledBorder:
                                                      InputBorder.none,
                                                  focusedBorder:
                                                      InputBorder.none,
                                                  filled: false,
                                                  counterText: ''))
                                        ]))
                              ]))),
                  Material(
                      color: Colors.white,
                      elevation: 4,
                      child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          child: Row(children: [
                            _tool(Icons.add_photo_alternate_outlined, 'Media',
                                'Tambah media', _addMedia),
                            _tool(Icons.draw_outlined, 'Gambar', 'Menggambar',
                                _draw),
                            _tool(Icons.text_fields_rounded, 'Font',
                                'Pengaturan font', _fonts)
                          ])))
                ])))));
  }

  final _affirmationFocus = FocusNode();
  Widget _editorAction(IconData icon, String label, VoidCallback action,
          {bool selected = false}) =>
      Semantics(
          selected: selected,
          child: OutlinedButton.icon(
              onPressed: _busy ? null : action,
              icon: Icon(icon, size: 19),
              style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white.withValues(alpha: .4),
                  foregroundColor: diaryPlum,
                  side: const BorderSide(color: Color(0xffe9deed)),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                  shape: const StadiumBorder()),
              label: Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w700))));

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
                    Text(label,
                        maxLines: 1,
                        style:
                            const TextStyle(fontFamily: 'Inter', fontSize: 11)),
                  ]))));
}
