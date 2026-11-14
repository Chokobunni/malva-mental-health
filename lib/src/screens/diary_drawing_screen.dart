import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme.dart';

/// Returns the finished PNG to the diary editor, or null when cancelled.
class DiaryDrawingScreen extends StatefulWidget {
  const DiaryDrawingScreen({super.key});

  @override
  State<DiaryDrawingScreen> createState() => _DiaryDrawingScreenState();
}

enum _DrawingTool { pen, marker, pencil, eraser }

class _DrawingStroke {
  _DrawingStroke(
      {required this.color,
      required this.width,
      required this.opacity,
      required this.erase,
      required Offset first})
      : points = [first];

  final Color color;
  final double width;
  final double opacity;
  final bool erase;
  final List<Offset> points;
}

class _DiaryDrawingScreenState extends State<DiaryDrawingScreen> {
  static const _background = Color(0xFFF2EDF9);
  static const _colors = [
    MalvaColors.ink,
    Color(0xFFE55263),
    Color(0xFFFF9D46),
    Color(0xFFF7D74C),
    Color(0xFFA9CF58),
    Color(0xFF5CC8B3),
    Color(0xFF65A6E9),
    Color(0xFFAE84CE),
  ];
  final _strokes = <_DrawingStroke>[];
  final _redo = <_DrawingStroke>[];
  _DrawingStroke? _active;
  _DrawingTool _tool = _DrawingTool.pen;
  Color _color = MalvaColors.ink;
  Color _paper = Colors.white;
  double _width = .006;
  double _opacity = 1;
  int _turns = 0;
  bool _sticker = false;
  bool _exporting = false;

  Offset _normalized(Offset point, Size size) => Offset(
      (point.dx / size.width).clamp(0, 1),
      (point.dy / size.height).clamp(0, 1));

  void _start(Offset point, Size size) {
    if (_exporting) return;
    setState(() {
      _redo.clear();
      _active = _DrawingStroke(
          color: _color,
          width: _width,
          opacity: _opacity,
          erase: _tool == _DrawingTool.eraser,
          first: _normalized(point, size));
      _strokes.add(_active!);
    });
  }

  void _move(Offset point, Size size) {
    if (_active == null) return;
    setState(() => _active!.points.add(_normalized(point, size)));
  }

  void _selectTool(_DrawingTool tool) {
    setState(() {
      _tool = tool;
      _width = switch (tool) {
        _DrawingTool.pen => .006,
        _DrawingTool.marker => .04,
        _DrawingTool.pencil => .003,
        _DrawingTool.eraser => .045,
      };
      _opacity = switch (tool) {
        _DrawingTool.marker => .35,
        _DrawingTool.pencil => .65,
        _ => 1,
      };
    });
  }

  Future<void> _finish() async {
    if (_exporting) return;
    setState(() {
      _exporting = true;
      _active = null;
    });
    ui.Image? image;
    ui.Picture? picture;
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const baseSize = Size(1200, 900);
      final rotated = _turns.isOdd;
      final size = rotated ? const Size(900, 1200) : baseSize;
      switch (_turns) {
        case 1:
          canvas.translate(size.width, 0);
          canvas.rotate(math.pi / 2);
        case 2:
          canvas.translate(size.width, size.height);
          canvas.rotate(math.pi);
        case 3:
          canvas.translate(0, size.height);
          canvas.rotate(-math.pi / 2);
      }
      _DrawingPainter(strokes: _strokes, paper: _sticker ? null : _paper)
          .paint(canvas, baseSize);
      picture = recorder.endRecording();
      image = await picture.toImage(size.width.toInt(), size.height.toInt());
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('PNG unavailable');
      if (mounted && ModalRoute.of(context)?.isCurrent == true)
        Navigator.of(context).pop<Uint8List>(data.buffer.asUint8List());
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Gambar belum dapat disimpan. Silakan coba lagi.')));
      }
    } finally {
      image?.dispose();
      picture?.dispose();
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _chooseColor() async {
    var hsv = HSVColor.fromColor(_color);
    if (hsv.saturation == 0) hsv = hsv.withSaturation(1).withValue(1);
    final selected = await showModalBottomSheet<Color>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: _background,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => SafeArea(
            child: SingleChildScrollView(
                child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Pilih warna',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 20),
            Container(
                height: 48,
                decoration: BoxDecoration(
                    color: hsv.toColor(),
                    borderRadius: BorderRadius.circular(14))),
            const SizedBox(height: 12),
            _colorSlider('Hue', 'drawing-hue', hsv.hue, 360,
                (value) => update(() => hsv = hsv.withHue(value)),
                activeColor: HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor()),
            _colorSlider('Saturasi', 'drawing-saturation', hsv.saturation, 1,
                (value) => update(() => hsv = hsv.withSaturation(value))),
            _colorSlider('Kecerahan', 'drawing-brightness', hsv.value, 1,
                (value) => update(() => hsv = hsv.withValue(value))),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: () => Navigator.pop(context, hsv.toColor()),
                child: const Text('Gunakan warna')),
          ]),
        ))),
      ),
    );
    if (selected != null && mounted) setState(() => _color = selected);
  }

  Widget _colorSlider(String label, String key, double value, double max,
          ValueChanged<double> onChanged,
          {Color? activeColor}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label),
          Slider(
              key: Key(key),
              semanticFormatterCallback: (value) => '${value.round()}',
              label: label,
              value: value,
              max: max,
              activeColor: activeColor,
              onChanged: onChanged)
        ],
      );

  Future<void> _choosePaper() async {
    final selected = await showModalBottomSheet<Color>(
      context: context,
      showDragHandle: true,
      backgroundColor: _background,
      builder: (context) => SafeArea(
          child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('Latar kertas',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 20),
          Wrap(
              spacing: 16,
              runSpacing: 16,
              alignment: WrapAlignment.center,
              children: [
                for (final paper in <(String, Color)>[
                  ('putih', Colors.white),
                  ('krem', const Color(0xFFFFF8E7)),
                  ('merah muda', const Color(0xFFFCE8F0)),
                  ('lavender', const Color(0xFFECE4F7)),
                  ('mint', const Color(0xFFE3F4EC)),
                  ('transparan', Colors.transparent),
                ])
                  Tooltip(
                      message: 'Kertas ${paper.$1}',
                      child: Semantics(
                          button: true,
                          label: 'Kertas ${paper.$1}',
                          child: InkWell(
                            onTap: () => Navigator.pop(context, paper.$2),
                            borderRadius: BorderRadius.circular(14),
                            child: Container(
                                width: 56,
                                height: 56,
                                decoration: BoxDecoration(
                                    color: paper.$2,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                        color: MalvaColors.plum
                                            .withValues(alpha: .25))),
                                child: paper.$2 == Colors.transparent
                                    ? const Icon(Icons.grid_on_rounded,
                                        color: MalvaColors.plum)
                                    : null),
                          ))),
              ]),
        ]),
      )),
    );
    if (selected != null && mounted) {
      setState(() {
        _sticker = selected == Colors.transparent;
        if (!_sticker) _paper = selected;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: _background,
        body: AbsorbPointer(
            absorbing: _exporting,
            child: SafeArea(
                child: Column(children: [
              Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(children: [
                    IconButton(
                        tooltip: 'Kembali',
                        onPressed:
                            _exporting ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.arrow_back_rounded)),
                    IconButton(
                        tooltip: 'Putar kanvas 90°',
                        onPressed: _exporting
                            ? null
                            : () => setState(() => _turns = (_turns + 1) % 4),
                        icon: const Icon(Icons.rotate_right_rounded)),
                    IconButton(
                        tooltip: 'Urungkan',
                        onPressed: _strokes.isEmpty || _exporting
                            ? null
                            : () => setState(() {
                                  _active = null;
                                  _redo.add(_strokes.removeLast());
                                }),
                        icon: const Icon(Icons.undo_rounded)),
                    IconButton(
                        tooltip: 'Ulangi',
                        onPressed: _redo.isEmpty || _exporting
                            ? null
                            : () => setState(
                                () => _strokes.add(_redo.removeLast())),
                        icon: const Icon(Icons.redo_rounded)),
                    Expanded(
                        child: TextButton(
                            onPressed: _exporting ? null : _finish,
                            style: TextButton.styleFrom(
                                foregroundColor: MalvaColors.plum,
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 8)),
                            child: _exporting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2))
                                : const Text('Selesai',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w700)))),
                  ])),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child:
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    const Flexible(
                        child: Text('Gambar sebagai stiker',
                            style: TextStyle(
                                color: MalvaColors.plum,
                                fontSize: 13,
                                fontWeight: FontWeight.w600))),
                    const SizedBox(width: 8),
                    Switch(
                        value: _sticker,
                        onChanged: _exporting
                            ? null
                            : (value) => setState(() => _sticker = value)),
                  ])),
              Expanded(
                  child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                child: Center(
                    child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 720),
                  child: AspectRatio(
                    aspectRatio: _turns.isOdd ? 3 / 4 : 4 / 3,
                    child: DecoratedBox(
                      decoration:
                          BoxDecoration(color: Colors.white, boxShadow: [
                        BoxShadow(
                            color: MalvaColors.plum.withValues(alpha: .06),
                            blurRadius: 24,
                            offset: const Offset(0, 8))
                      ]),
                      child: RotatedBox(
                          quarterTurns: _turns,
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final size = constraints.biggest;
                              return ClipRect(
                                  child: GestureDetector(
                                key: const Key('diary-drawing-canvas'),
                                behavior: HitTestBehavior.opaque,
                                onPanDown: (details) =>
                                    _start(details.localPosition, size),
                                onPanUpdate: (details) =>
                                    _move(details.localPosition, size),
                                onPanEnd: (_) => _active = null,
                                onPanCancel: () => _active = null,
                                child: CustomPaint(
                                    size: size,
                                    foregroundPainter: _DrawingPainter(
                                        strokes: _strokes,
                                        paper: _sticker ? null : _paper),
                                    painter: _sticker
                                        ? const _CheckerPainter()
                                        : null),
                              ));
                            },
                          )),
                    ),
                  ),
                )),
              )),
              _controls(),
            ]))),
      );

  Widget _controls() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
              height: 52,
              child: Row(children: [
                Expanded(
                    child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  scrollDirection: Axis.horizontal,
                  itemCount: _colors.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 6),
                  itemBuilder: (context, index) {
                    final color = _colors[index];
                    return Semantics(
                      button: true,
                      selected: color == _color,
                      label: 'Warna ${[
                        'hitam',
                        'merah',
                        'oranye',
                        'kuning',
                        'hijau limau',
                        'mint',
                        'biru',
                        'ungu'
                      ][index]}',
                      child: InkResponse(
                          onTap: () => setState(() => _color = color),
                          radius: 24,
                          child: Center(
                              child: Container(
                                  width: 30,
                                  height: 30,
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: color,
                                      border: Border.all(
                                          color: Colors.white,
                                          width: color == _color ? 3 : 0),
                                      boxShadow: color == _color
                                          ? [
                                              const BoxShadow(
                                                  color: MalvaColors.plum,
                                                  spreadRadius: 2)
                                            ]
                                          : null)))),
                    );
                  },
                )),
                const SizedBox(width: 8),
                IconButton(
                    tooltip: 'Warna lainnya',
                    onPressed: _chooseColor,
                    style: IconButton.styleFrom(backgroundColor: Colors.white),
                    icon: const Icon(Icons.color_lens_rounded,
                        color: MalvaColors.plum)),
              ])),
          const SizedBox(height: 6),
          _setting(
              'Ukuran',
              Slider(
                  key: const Key('drawing-width'),
                  min: .002,
                  max: .08,
                  value: _width,
                  semanticFormatterCallback: (value) =>
                      '${(value * 900).round()} piksel',
                  onChanged: (value) => setState(() => _width = value)),
              '${(_width * 900).round()}'),
          _setting(
              'Opasitas',
              Slider(
                  key: const Key('drawing-opacity'),
                  min: .05,
                  max: 1,
                  value: _opacity,
                  semanticFormatterCallback: (value) =>
                      '${(value * 100).round()} persen',
                  onChanged: (value) => setState(() => _opacity = value)),
              '${(_opacity * 100).round()}%'),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _toolButton('PEN', Icons.edit_rounded, _DrawingTool.pen),
            _toolButton('MARKER', Icons.brush_rounded, _DrawingTool.marker),
            _toolButton('PENCIL', Icons.draw_outlined, _DrawingTool.pencil),
            _toolButton(
                'ERASER', Icons.backspace_outlined, _DrawingTool.eraser),
            Expanded(
                child: _toolTile(
                    'PAPER', Icons.layers_outlined, false, _choosePaper)),
          ]),
        ]),
      );

  Widget _setting(String label, Widget slider, String value) => SizedBox(
        height: 42,
        child: Row(children: [
          SizedBox(
              width: 64,
              child: Text(label,
                  style:
                      const TextStyle(fontSize: 11, color: MalvaColors.plum))),
          Expanded(child: slider),
          SizedBox(
              width: 38,
              child: Text(value,
                  textAlign: TextAlign.end,
                  style:
                      const TextStyle(fontSize: 11, color: MalvaColors.plum))),
        ]),
      );

  Widget _toolButton(String label, IconData icon, _DrawingTool tool) =>
      Expanded(
        child: _toolTile(label, icon, tool == _tool, () => _selectTool(tool)),
      );

  Widget _toolTile(
          String label, IconData icon, bool selected, VoidCallback onTap) =>
      Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                    width: 46,
                    height: 44,
                    decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFDED2EF)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(14)),
                    child: Icon(icon, color: MalvaColors.plum, size: 27)),
                const SizedBox(height: 4),
                Text(label,
                    style: TextStyle(
                        fontSize: 9,
                        color: MalvaColors.plum,
                        fontWeight:
                            selected ? FontWeight.w800 : FontWeight.w500)),
              ])),
        ),
      );
}

class _DrawingPainter extends CustomPainter {
  const _DrawingPainter({required this.strokes, required this.paper});
  final List<_DrawingStroke> strokes;
  final Color? paper;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.save();
    canvas.clipRect(bounds);
    if (paper != null) canvas.drawRect(bounds, Paint()..color = paper!);
    // Keep the paper outside the ink layer so clearing reveals its real color.
    canvas.saveLayer(bounds, Paint());
    for (final stroke in strokes) {
      final paint = Paint()
        ..color = stroke.color.withValues(alpha: stroke.opacity)
        ..strokeWidth = stroke.width * size.shortestSide
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..blendMode = stroke.erase
            ? (stroke.opacity == 1 ? BlendMode.clear : BlendMode.dstOut)
            : BlendMode.srcOver;
      final points = stroke.points
          .map((p) => Offset(p.dx * size.width, p.dy * size.height));
      if (stroke.points.length == 1) {
        canvas.drawCircle(points.first, paint.strokeWidth / 2,
            paint..style = PaintingStyle.fill);
      } else {
        final path = Path()..moveTo(points.first.dx, points.first.dy);
        for (final point in points.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, paint);
      }
    }
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DrawingPainter oldDelegate) => true;
}

class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);
    final paint = Paint()..color = const Color(0xFFECE9EF);
    const cell = 12.0;
    for (var y = 0; y < size.height / cell; y++) {
      for (var x = 0; x < size.width / cell; x++) {
        if ((x + y).isEven)
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _CheckerPainter oldDelegate) => false;
}
