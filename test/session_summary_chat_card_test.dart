import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/chat/clinical_chat_card.dart';
import 'package:malva_mental_health/src/time/wib.dart';

ChatMessage _summary(Map<String, dynamic> metadata) => ChatMessage(
    id: 'saved-summary',
    senderId: 'professional',
    senderName: 'Profesional',
    text: 'Rangkuman sesi',
    timestamp: wibFromParts(2026, 11, 6, 13, 8),
    isMine: false,
    kind: 'session_summary',
    metadata: metadata);

void main() {
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/roboto-bold.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });

  for (final patient in [true, false]) {
    for (final large in [false, true]) {
      testWidgets(
          'saved summary stays inline for ${patient ? 'patient' : 'professional'} ${large ? 'narrow large text' : 'phone'}',
          (tester) async {
        tester.view.physicalSize = Size(large ? 300 : 390, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final boundary = GlobalKey();
        final message = _summary({
          'goals': [
            {'title': 'Tidur jam 22.00', 'target_per_week': 7},
            {'title': 'Menggunakan Elliptical Bike', 'target_per_week': 3},
            {'title': 'Berenang', 'target_per_week': 2},
            {'title': 'Jalan Pagi', 'target_per_week': 3},
          ],
          'insight': 'Jangan lupa untuk meditasi setiap hari dan buat situasi '
              'sekitar kita senyaman mungkin',
        });
        await tester.pumpWidget(MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: ThemeData(fontFamily: 'Roboto'),
            home: MediaQuery(
                data: MediaQueryData(
                    textScaler: TextScaler.linear(large ? 1.6 : 1)),
                child: Scaffold(
                    body: SingleChildScrollView(
                        child: RepaintBoundary(
                            key: boundary,
                            child: SizedBox(
                                width: (large ? 300 : 390) - 32,
                                child: ClinicalChatCard(
                                    message: message,
                                    isPatient: patient,
                                    onAction: () =>
                                        fail('Summary opened detail')))))))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Target: 7x / minggu'), findsOneWidget);
        expect(find.text('Target: 3x / minggu'), findsNWidgets(2));
        expect(find.text('Target: 2x / minggu'), findsOneWidget);
        expect(
            find.text(message.metadata!['insight'] as String), findsOneWidget);
        expect(find.byType(TextButton), findsNothing);
        expect(find.byType(ExpansionTile), findsNothing);
        expect(find.byType(InkWell), findsNothing);
        final output = Platform.environment['MALVA_RECORD_QA_DIR'];
        if (output != null && patient && !large) {
          await tester.runAsync(() async {
            final render = boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
            final shot = await render.toImage(pixelRatio: 2);
            final png = await shot.toByteData(format: ui.ImageByteFormat.png);
            await File('$output/session-summary.png')
                .writeAsBytes(png!.buffer.asUint8List());
            shot.dispose();
          });
        }
      });
    }
  }

  testWidgets('invalid weekly targets never become a fabricated default',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: ClinicalChatCard(
                    message: _summary({
                      'goals': [
                        {'title': 'Target tidak tercatat'},
                        {'title': 'Target invalid', 'target_per_week': -1},
                        {'title': 'Target nol', 'target_per_week': 0},
                        {'title': 'Target di luar batas', 'target_per_week': 8},
                        {'title': 'Target pecahan', 'target_per_week': 2.5},
                        {'title': 'Target teks', 'target_per_week': '3'},
                      ],
                      'insight': '',
                    }),
                    isPatient: true)))));
    expect(find.text('Target belum tercatat'), findsNWidgets(6));
    expect(find.textContaining('Target: 3x'), findsNothing);
    expect(find.text('Belum ada insight tersimpan.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('historical goal IDs without snapshots remain honest',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ClinicalChatCard(
                message: _summary({
                  'goal_ids': ['one', 'two'],
                  'goals': 'malformed',
                  'insight': 'Catatan asli.',
                }),
                isPatient: false))));
    expect(find.text('2 goals tersimpan. Detail goal belum tersedia.'),
        findsOneWidget);
    expect(find.text('Catatan asli.'), findsOneWidget);
    expect(find.text('Lihat detail'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
