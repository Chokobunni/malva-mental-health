import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/widgets/shared_record_detail.dart';
import 'package:malva_mental_health/src/time/wib.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/roboto-bold.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')
          ..addFont(rootBundle
              .load('packages/cupertino_icons/assets/CupertinoIcons.ttf')))
        .load();
  });
  for (final variant in [
    (width: 360.0, scale: 1.0, label: '360'),
    (width: 390.0, scale: 1.0, label: '390'),
    (width: 360.0, scale: 1.4, label: '360-large')
  ]) {
    for (final kind in [
      'prescription',
      'goals',
      'diary',
      'summary',
      'assessment'
    ]) {
      testWidgets('$kind detail fits ${variant.label} and preserves real data',
          (tester) async {
        tester.view.physicalSize = Size(variant.width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final metadata = switch (kind) {
          'prescription' => {
              'medications': [
                {
                  'name': 'Quetiapine',
                  'dosage': '300 mg',
                  'form': 'Tablet',
                  'reminder_time': '20:00'
                },
                {
                  'name': 'Aripiprazole',
                  'dosage': '20 mg',
                  'form': 'Tablet',
                  'reminder_time': '20:00'
                },
                {
                  'name': 'Lamictal',
                  'dosage': '20 mg',
                  'form': 'Tablet',
                  'reminder_time': '22:00'
                }
              ]
            },
          'goals' => {
              'goals': [
                {
                  'title': 'Berjalan pagi setiap hari',
                  'target_per_week': 3,
                  'done_this_week': 1,
                  'is_active': true
                },
                {
                  'title': 'Menggunakan Elliptical Bike',
                  'target_per_week': 3,
                  'done_this_week': 1,
                  'is_active': true
                },
                {
                  'title': 'Tidur jam 22.00',
                  'target_per_week': 7,
                  'done_this_week': 1,
                  'is_active': true
                }
              ]
            },
          'diary' => {
              'title': 'Hari yang baik',
              'note': 'Saya mengunjungi taman.',
              'occurred_at': '2026-11-09T06:43:00+07:00'
            },
          'summary' => {
              'mood_count': 9,
              'avg_sleep_hours': 7.7,
              'medication_adherence': 100
            },
          _ => {
              'phq9_score': 23,
              'gad7_score': 21,
              'overall_level': 'crisis',
              'crisis_flag': true,
              'phq9_level': 'severe',
              'gad7_level': 'severe',
              'cf': 0.95
            },
        };
        final capture = GlobalKey();
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: MediaQuery(
                    data: MediaQueryData(
                        textScaler: TextScaler.linear(variant.scale)),
                    child: SingleChildScrollView(
                        child: RepaintBoundary(
                            key: capture,
                            child: SharedRecordDetail(
                                showClinicalAudit: true,
                                message: ChatMessage(
                                    id: 'm',
                                    senderId: 'p',
                                    senderName: 'Pasien',
                                    text: kind == 'summary'
                                        ? 'Ringkasan 7 hari: 9 mood check-in, tidur rata-rata 7.7 jam, ketaatan obat 100%.'
                                        : 'Record dibagikan',
                                    timestamp: wibFromParts(2026, 11, 9, 6, 43),
                                    isMine: false,
                                    kind: kind,
                                    metadata: metadata))))))));
        expect(find.text('Detail Record'), findsOneWidget);
        expect(find.text('09/11/2026'), findsWidgets);
        expect(find.text('06:43'), findsOneWidget);
        expect(find.textContaining('occurred at'), findsNothing);
        if (kind == 'goals')
          expect(find.byType(LinearProgressIndicator), findsNWidgets(3));
        if (kind == 'summary')
          expect(find.text('METRIK 7 HARI TERAKHIR'), findsOneWidget);
        if (kind == 'diary')
          expect(
              find.textContaining('Saya mengunjungi taman.'), findsOneWidget);
        if (kind == 'assessment') expect(find.text('KRISIS'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final output = Platform.environment['MALVA_CHAT_DETAIL_QA'];
        if (output != null) {
          await tester.runAsync(() async {
            final boundary = capture.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await File('$output/detail-$kind-${variant.label}.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
      });
    }
  }
}
