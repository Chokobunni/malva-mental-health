import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/screens/diary_drawing_screen.dart';
import 'package:malva_mental_health/src/theme.dart';

import 'record_render_capture.dart';

void main() {
  setUpAll(loadRecordCaptureFonts);

  Future<void> open(WidgetTester tester, ValueChanged<Uint8List?> result,
      {Size size = const Size(390, 844), double scale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: recordCaptureTheme(buildMalvaTheme()),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: Builder(
          builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () async {
                      result(await Navigator.of(context).push<Uint8List>(
                        MaterialPageRoute(
                            builder: (_) => const DiaryDrawingScreen()),
                      ));
                    },
                    child: const Text('Open')),
              )),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> stroke(WidgetTester tester,
      {double y = .5, double from = .2, double to = .8}) async {
    final rect = tester.getRect(find.byKey(const Key('diary-drawing-canvas')));
    final gesture = await tester.startGesture(
        rect.topLeft + Offset(rect.width * from, rect.height * y));
    await gesture
        .moveTo(rect.topLeft + Offset(rect.width * to, rect.height * y));
    await gesture.up();
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.tap(find.text('Selesai'));
      await Future<void>.delayed(const Duration(milliseconds: 150));
    });
    await tester.pumpAndSettle();
  }

  Future<({int width, int height, Uint8List pixels})> decode(
      WidgetTester tester, Uint8List bytes) async {
    return (await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      final data =
          await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final result = (
        width: frame.image.width,
        height: frame.image.height,
        pixels: data!.buffer.asUint8List()
      );
      frame.image.dispose();
      codec.dispose();
      return result;
    }))!;
  }

  testWidgets('drawing exports a real PNG with ink and an opaque paper',
      (tester) async {
    Uint8List? result;
    await open(tester, (value) => result = value);
    await stroke(tester);
    await finish(tester);
    expect(result, isNotNull);
    final image = await decode(tester, result!);
    expect((image.width, image.height), (1200, 900));
    expect(
        image.pixels
            .sublist((450 * 1200 + 600) * 4, (450 * 1200 + 600) * 4 + 4),
        [32, 27, 36, 255]);
    expect(image.pixels.sublist(0, 4), [255, 255, 255, 255]);
  });

  testWidgets('undo and redo restore strokes and a new stroke clears redo',
      (tester) async {
    await open(tester, (_) {});
    IconButton button(String label) =>
        tester.widget<IconButton>(find.byWidgetPredicate(
            (widget) => widget is IconButton && widget.tooltip == label));
    expect(button('Urungkan').onPressed, isNull);
    await stroke(tester);
    expect(button('Urungkan').onPressed, isNotNull);
    await tester.tap(find.byTooltip('Urungkan'));
    await tester.pump();
    expect(button('Urungkan').onPressed, isNull);
    expect(button('Ulangi').onPressed, isNotNull);
    await tester.tap(find.byTooltip('Ulangi'));
    await tester.pump();
    expect(button('Urungkan').onPressed, isNotNull);
    await tester.tap(find.byTooltip('Urungkan'));
    await tester.pump();
    await stroke(tester, y: .3);
    expect(button('Ulangi').onPressed, isNull);
  });

  testWidgets(
      'sticker eraser clears ink to transparency and rotation preserves PNG orientation',
      (tester) async {
    Uint8List? result;
    await open(tester, (value) => result = value);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await stroke(tester);
    await tester.tap(find.text('ERASER'));
    await tester.pump();
    await stroke(tester, from: .4, to: .6);
    await tester.tap(find.byTooltip('Putar kanvas 90°'));
    await tester.pump();
    await finish(tester);
    final image = await decode(tester, result!);
    expect((image.width, image.height), (900, 1200));
    expect(image.pixels[3], 0);
    expect(image.pixels[(600 * 900 + 450) * 4 + 3], 0);
    expect(image.pixels[(300 * 900 + 450) * 4 + 3], 255);
  });

  testWidgets('paper chooser changes exported paper', (tester) async {
    Uint8List? result;
    await open(tester, (value) => result = value);
    await tester.tap(find.text('PAPER'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Kertas krem'));
    await tester.pumpAndSettle();
    await finish(tester);
    final image = await decode(tester, result!);
    expect(image.pixels.sublist(0, 4), [255, 248, 231, 255]);
  });

  testWidgets('eraser opacity can partially erase transparent sticker ink',
      (tester) async {
    Uint8List? result;
    await open(tester, (value) => result = value);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await stroke(tester);
    await tester.tap(find.text('ERASER'));
    await tester.pump();
    tester
        .widget<Slider>(find.byKey(const Key('drawing-opacity')))
        .onChanged!(.5);
    await tester.pump();
    await stroke(tester, from: .4, to: .6);
    await finish(tester);
    final image = await decode(tester, result!);
    expect(image.pixels[(450 * 1200 + 600) * 4 + 3], closeTo(127, 1));
  });

  testWidgets('marker and pencil keep their opacity after resize and half turn',
      (tester) async {
    Uint8List? result;
    await open(tester, (value) => result = value);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.text('MARKER'));
    await tester.pump();
    await stroke(tester, y: .25);
    await tester.tap(find.text('PENCIL'));
    await tester.pump();
    await stroke(tester, y: .75);
    tester.view.physicalSize = const Size(320, 740);
    await tester.pump();
    await tester.tap(find.byTooltip('Putar kanvas 90°'));
    await tester.pump();
    await tester.tap(find.byTooltip('Putar kanvas 90°'));
    await tester.pump();
    await finish(tester);
    final image = await decode(tester, result!);
    expect((image.width, image.height), (1200, 900));
    expect(image.pixels[(225 * 1200 + 600) * 4 + 3], closeTo(166, 1));
    expect(image.pixels[(675 * 1200 + 600) * 4 + 3], closeTo(89, 1));
  });

  testWidgets('all brush tools and custom color controls work', (tester) async {
    Uint8List? result;
    await open(tester, (value) => result = value);
    await tester.tap(find.text('MARKER'));
    await tester.pump();
    await tester.tap(find.text('PENCIL'));
    await tester.pump();
    await tester.tap(find.text('PEN'));
    await tester.pump();
    await tester.tap(find.byTooltip('Warna lainnya'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('drawing-hue')), findsOneWidget);
    final hue = tester.widget<Slider>(find.byKey(const Key('drawing-hue')));
    hue.onChanged!(120);
    await tester.pump();
    await tester.tap(find.text('Gunakan warna'));
    await tester.pumpAndSettle();
    final width = tester.widget<Slider>(find.byKey(const Key('drawing-width')));
    width.onChanged!(.03);
    await tester.pump();
    final opacity =
        tester.widget<Slider>(find.byKey(const Key('drawing-opacity')));
    opacity.onChanged!(.5);
    await tester.pump();
    await stroke(tester);
    await finish(tester);
    final image = await decode(tester, result!);
    final pixel = image.pixels
        .sublist((450 * 1200 + 600) * 4, (450 * 1200 + 600) * 4 + 4);
    expect(pixel[1], greaterThan(pixel[0]));
    expect(pixel[0], greaterThan(80));
  });

  testWidgets('back cancels without an attachment', (tester) async {
    Uint8List? result = Uint8List(1);
    await open(tester, (value) => result = value);
    await tester.tap(find.byTooltip('Kembali'));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('back during PNG export keeps the editor route open',
      (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
        navigatorKey: navigator, home: const Scaffold(body: Text('Home'))));
    navigator.currentState!.push<void>(MaterialPageRoute(
        builder: (_) => const Scaffold(body: Text('Editor'))));
    await tester.pumpAndSettle();
    navigator.currentState!.push<Uint8List>(
        MaterialPageRoute(builder: (_) => const DiaryDrawingScreen()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Selesai'));
    navigator.currentState!.pop();
    await tester.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 150)));
    await tester.pumpAndSettle();
    expect(find.text('Editor'), findsOneWidget);
    expect(find.text('Home'), findsNothing);
  });

  for (final size in [const Size(320, 740), const Size(390, 844)]) {
    testWidgets('drawing controls fit ${size.width} at large text',
        (tester) async {
      enableRecordCaptureRendering();
      await open(tester, (_) {}, size: size, scale: 1.35);
      expect(tester.takeException(), isNull);
      expect(
          tester
              .getSize(find.byKey(const Key('diary-drawing-canvas')))
              .aspectRatio,
          closeTo(4 / 3, .01));
      expect(find.text('Selesai').hitTestable(), findsOneWidget);
      expect(find.text('ERASER').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Warna lainnya').hitTestable(), findsOneWidget);
      final boundary = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: recordCaptureTheme(buildMalvaTheme()),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: const TextScaler.linear(1.35)),
                  child: child!),
              home: const DiaryDrawingScreen())));
      await tester.pumpAndSettle();
      await captureRecord(
          tester, boundary, 'diary-drawing-${size.width.toInt()}.png');
      expect(tester.takeException(), isNull);
      resetRecordCaptureRendering();
    });
  }
}
