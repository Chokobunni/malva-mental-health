import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

bool get recordCaptureEnabled =>
    Platform.environment['MALVA_RECORD_QA_DIR'] != null;

Future<void> loadRecordCaptureFonts() async {
  if (!recordCaptureEnabled) return;
  await (FontLoader('Roboto')
        ..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/roboto-bold.ttf')))
      .load();
  await (FontLoader('PlusJakartaSans')
        ..addFont(rootBundle.load('assets/fonts/plus-jakarta-sans-regular.ttf'))
        ..addFont(rootBundle.load('assets/fonts/plus-jakarta-sans-bold.ttf')))
      .load();
  await (FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
      .load();
}

void enableRecordCaptureRendering() {
  debugDisableShadows = false;
  addTearDown(() => debugDisableShadows = true);
}

void resetRecordCaptureRendering() => debugDisableShadows = true;

ThemeData recordCaptureTheme(ThemeData theme) => !recordCaptureEnabled
    ? theme
    : theme.copyWith(
        appBarTheme: theme.appBarTheme.copyWith(
            titleTextStyle: theme.appBarTheme.titleTextStyle
                ?.copyWith(fontFamily: 'Roboto')));

Future<void> captureRecord(
    WidgetTester tester, GlobalKey boundary, String filename) async {
  final output = Platform.environment['MALVA_RECORD_QA_DIR'];
  if (output == null) return;
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final shot = await render.toImage(pixelRatio: 2);
    final png = await shot.toByteData(format: ui.ImageByteFormat.png);
    await File('$output/$filename').writeAsBytes(png!.buffer.asUint8List());
    shot.dispose();
  });
}
