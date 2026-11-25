import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/medication_screen.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/time/wib.dart';

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
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  for (final narrow in [false, true]) {
    testWidgets('medication reference panels and cards fit narrow=$narrow',
        (tester) async {
      tester.view.physicalSize = Size(narrow ? 320 : 390, 1800);
      tester.view.devicePixelRatio = 1;
      debugDisableShadows = false;
      addTearDown(() => debugDisableShadows = true);
      addTearDown(tester.view.reset);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final now = wibNow();
      final start = wibFromParts(now.year, now.month, now.day)
          .subtract(const Duration(days: 5));
      final meds = [
        for (var i = 0; i < 2; i++)
          Medication(
              id: '00000000-0000-4000-8000-00000000000$i',
              name: i == 0 ? 'Lamictal' : 'Aripiprazole',
              dosage: '20 mg',
              form: 'Tablet',
              reminders: const [],
              currentStock: 24,
              alertBelow: 3,
              source: i == 0 ? 'Pasien' : 'resep',
              schedule: i == 0
                  ? MedicationSchedule(
                      times: const ['08:00'],
                      weekdays: const [1, 2, 3, 4, 5, 6, 7],
                      startAt: start)
                  : null),
      ];
      container.read(malvaStoreProvider.notifier).replaceMedications(meds);
      container.read(malvaStoreProvider.notifier).replaceMedicationLogs([
        for (var day = 0; day < 3; day++)
          MedicationLog(
              medicationId: meds.first.id,
              medicationName: meds.first.name,
              takenAt: start.add(Duration(days: day, hours: 8)),
              status: 'taken'),
      ]);
      final capture = GlobalKey();
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              theme: buildMalvaTheme().copyWith(
                  filledButtonTheme: FilledButtonThemeData(
                      style: FilledButton.styleFrom(
                          textStyle: const TextStyle(
                              fontFamily: 'Roboto',
                              fontSize: 16,
                              fontWeight: FontWeight.w700)))),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(narrow ? 1.5 : 1)),
                  child: child!),
              home: RepaintBoundary(
                  key: capture,
                  child: const MedicationScreen(
                      session: AuthSession(
                          role: UserRole.patient,
                          identifier: 'p',
                          displayName: 'Pasien',
                          accessToken: 'token'))))));
      await tester.pumpAndSettle();
      Future<void> snapshot(String name) async {
        expect(tester.takeException(), isNull);
        final output = Platform.environment['MALVA_MEDICATION_QA'];
        if (output == null) return;
        await tester.runAsync(() async {
          final boundary = capture.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('$output/${narrow ? 'narrow-' : ''}$name.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      expect(find.text('TARGET HARIAN'), findsOneWidget);
      await snapshot('medication-weekly');
      await tester.ensureVisible(find.text('Runtutan'));
      await tester.tap(find.text('Runtutan'));
      await tester.pumpAndSettle();
      expect(find.text('Rekor terlama: 3 hari'), findsOneWidget);
      await snapshot('medication-streak');
      await tester.scrollUntilVisible(find.text('Aripiprazole'), 300,
          scrollable: find.byType(Scrollable).first);
      await tester.pumpAndSettle();
      await snapshot('medication-cards');
      await tester.pumpWidget(const SizedBox());
      debugDisableShadows = true;
    });
  }
}
