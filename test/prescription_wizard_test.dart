import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/portal/e_prescription_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

void main() {
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
    for (final mode in [
      '1x',
      '2x',
      '3x',
      'flexible',
      'hours',
      'days',
      'months',
      'precision',
      'weekdays'
    ])
      (mode: mode, narrow: false),
    (mode: 'flexible', narrow: true),
    (mode: 'precision', narrow: true),
  ]) {
    final mode = variant.mode;
    testWidgets(
        'prescription reference flow persists $mode routine and refill stock ${variant.narrow ? 'at320px and large text' : ''}',
        (tester) async {
      tester.view.physicalSize =
          variant.narrow ? const Size(320, 800) : const Size(393, 925);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final capture = GlobalKey();
      Map<String, dynamic>? sent;
      final api = MalvaApiClient(
          baseUrl: 'https://backend.test',
          httpClient: MockClient((r) async {
            sent = jsonDecode(r.body) as Map<String, dynamic>;
            return http.Response(
                jsonEncode({
                  'prescription': {'id': 'rx1'}
                }),
                201);
          }));
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
              theme: buildMalvaTheme(),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(variant.narrow ? 1.5 : 1)),
                  child: child!),
              home: RepaintBoundary(
                  key: capture,
                  child: EPrescriptionFormScreen(
                    apiClient: api,
                    session: const AuthSession(
                        role: UserRole.professional,
                        identifier: 'pro',
                        displayName: 'Dokter',
                        accessToken: 'token'),
                    preselectedPatientId: 'p1',
                    links: const [
                      BackendPatientProfessionalLink(
                          patientId: 'p1',
                          professionalUserId: 'pro',
                          professionalId: 'pro',
                          patientDisplayName: 'Ami',
                          professionalDisplayName: 'Dokter',
                          status: 'active')
                    ],
                  )))));
      Future<void> screenshot(String name) async {
        expect(tester.takeException(), isNull);
        final output = Platform.environment['MALVA_RX_QA'];
        if (output == null) return;
        debugDisableShadows = false;
        await tester.pump();
        try {
          await tester.runAsync(() async {
            final boundary = capture.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await File(
                    '$output/${variant.narrow ? 'narrow-' : ''}$mode-$name.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        } finally {
          debugDisableShadows = true;
        }
      }

      Future<void> next() async {
        final button = find.byKey(const Key('rx-next'));
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
      }

      await tester.runAsync(() async {
        for (final asset in [
          'pill',
          'tablet',
          'capsule',
          'syrup',
          'injection'
        ]) {
          await precacheImage(AssetImage('assets/prescription/$asset.png'),
              tester.element(find.byType(EPrescriptionFormScreen)));
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('Stok obat yang diberikan'), findsNothing);
      expect(find.byKey(const Key('rx-stock')), findsNothing);
      await screenshot('detail');
      await next();
      expect(find.text('Nama obat tidak boleh kosong.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('rx-name')), 'Aripiprazole');
      await next();
      expect(find.text('Dosis harus lebih dari 0.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('rx-dose')), '10');
      await next();
      expect(find.text('Atur Rutinitas'), findsOneWidget);
      if (!variant.narrow) {
        tester.view.physicalSize = Size(
            393,
            switch (mode) {
              '1x' => 839,
              '2x' => 827,
              '3x' => 824,
              'flexible' => 823,
              'hours' || 'days' => 997,
              'precision' => 924,
              _ => 920
            });
        await tester.pumpAndSettle();
      }
      if (mode == '1x' || mode == '2x' || mode == '3x') {
        await tester.tap(find.text('$mode sehari'));
      } else if (mode == 'flexible') {
        await tester.tap(find.text('3x sehari'));
        await tester.tap(find.text('Fleksibel'));
      } else if (mode == 'hours' || mode == 'days' || mode == 'months') {
        await tester.tap(find.text('Pola Berkala'));
        await tester.pumpAndSettle();
        if (mode == 'days') await tester.tap(find.text('Tiap X hari'));
        if (mode == 'months') {
          await tester.ensureVisible(find.text('Tiap X bulan'));
          await tester.tap(find.text('Tiap X bulan'));
        }
      } else if (mode == 'precision') {
        await tester.ensureVisible(find.text('Jam Presisi'));
        await tester.tap(find.text('Jam Presisi'));
      } else {
        await tester.tap(find.text('Pilih Hari'));
        await tester.pumpAndSettle();
        for (final d in ['Sel', 'Kam', 'Sab', 'Min']) {
          await tester.tap(find.text(d));
        }
      }
      await tester.pumpAndSettle();
      expect(find.text('Jam minum obat (WIB)'), findsNothing);
      await screenshot('routine');
      await next();
      if (mode != 'flexible') {
        expect(find.text('Kapan pasien perlu diingatkan?'), findsOneWidget);
        await screenshot('timing');
        if (mode == 'weekdays') {
          await tester.tap(find.text('+ Tambah waktu pengingat'));
          await tester.pumpAndSettle();
          expect(find.byKey(const Key('rx-time-1')), findsOneWidget);
        }
        await next();
      }
      expect(find.text('Apakah perlu pengingat isi ulang obat untuk pasien?'),
          findsOneWidget);
      expect(find.byKey(const Key('rx-stock')), findsOneWidget);
      await screenshot('refill');
      if (mode == 'flexible') {
        expect(find.byKey(const Key('rx-time-0')), findsNothing);
        await tester.tap(find.byType(Switch));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('rx-stock')), findsOneWidget);
      }
      await next();
      expect(sent, isNotNull);
      final item = (sent!['items'] as List).single as Map;
      expect(item['form'], 'Tablet');
      expect(item['current_stock'], 30);
      expect(item['alert_below'], 3);
      final schedule = item['schedule'] as Map;
      expect(schedule['units_per_dose'], 1);
      expect(schedule['start_at'], endsWith('+07:00'));
      expect(
          schedule['times'],
          switch (mode) {
            '2x' => ['08:00', '20:00'],
            '3x' => ['08:00', '14:00', '20:00'],
            'precision' => ['08:00', '12:00', '16:00', '20:00'],
            'weekdays' => ['08:00', '20:00'],
            'flexible' => <String>[],
            _ => ['08:00']
          });
      expect(schedule['interval_hours'], mode == 'hours' ? 8 : 0);
      expect(schedule['interval_days'], mode == 'days' ? 2 : 0);
      expect(schedule['interval_months'], mode == 'months' ? 1 : 0);
      expect(schedule['refill_enabled'], mode != 'flexible');
      expect(schedule['weekdays'],
          mode == 'weekdays' ? [1, 3, 5] : [1, 2, 3, 4, 5, 6, 7]);
      if (mode == 'flexible') {
        expect(schedule['start_at'], contains('T00:00:00'));
        final med = BackendMedication.fromJson({
          'id': 'm1',
          'name': 'Aripiprazole',
          'current_stock': 30,
          'alert_below': 3,
          'schedule': schedule,
          'reminder_time': ''
        }).toMedication();
        expect(med.reminders, isEmpty);
        expect(med.schedule!.label, 'Fleksibel • tanpa jam minum');
      }
    });
  }
}
