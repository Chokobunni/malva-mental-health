import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/widgets/therapy_library.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/screens/chat/chat_shared_record_card.dart';

import 'record_render_capture.dart';

void main() {
  setUpAll(() async {
    await loadRecordCaptureFonts();
    if (recordCaptureEnabled) {
      await (FontLoader('packages/cupertino_icons/CupertinoIcons')
            ..addFont(rootBundle
                .load('packages/cupertino_icons/assets/CupertinoIcons.ttf')))
          .load();
    }
  });
  testWidgets('short therapy sheet fits its contents within the viewport',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                      body: TextButton(
                          onPressed: () => showTherapySubmissionDetail(context,
                                  moduleId: 'pmr',
                                  title: pmrModule.title,
                                  answers: const {
                                    'muscle_groups': ['Betis', 'Kaki'],
                                    'difference': 'Rileks'
                                  }),
                          child: const Text('Open')),
                    )))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(TherapySubmissionView)).height,
        lessThan(900));
    expect(find.text('Selesai'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  for (final module
      in allTherapyModules.where((module) => module.id != 'psychoeducation')) {
    testWidgets('therapy ${module.id} renders all canonical saved fields',
        (tester) async {
      tester.view.physicalSize = const Size(390, 1500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final answers = <String, dynamic>{
        for (final field in module.worksheetFields)
          field.id: switch (field.kind) {
            TherapyFieldKind.choiceMulti => field.choices.take(2).toList(),
            TherapyFieldKind.choice => field.choices.first,
            TherapyFieldKind.points => List.filled(field.pointCount, 'X'),
            TherapyFieldKind.beforeAfter => {'before': 6, 'after': 1},
            TherapyFieldKind.number => 4,
            _ => 'X',
          },
      }..remove(switch (module.id) {
          'thinking_traps' => 'friend_advice',
          'behavioral_activation' => 'schedule_time',
          'tipp' => 'exercise',
          _ => module.worksheetFields.last.id,
        });
      final boundary = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          theme: recordCaptureTheme(buildMalvaTheme()),
          home: Scaffold(
              body: RepaintBoundary(
                  key: boundary,
                  child: ColoredBox(
                      color: Colors.white,
                      child: TherapySubmissionView(
                          moduleId: module.id,
                          title: module.title,
                          answers: answers,
                          standalone: true,
                          createdAt:
                              DateTime.parse('2026-11-27T14:10:00+07:00')))))));
      await tester.pumpAndSettle();
      expect(
          find.text(
              '${module.worksheetFields.length - 1}/${module.worksheetFields.length} Terisi'),
          findsOneWidget);
      expect(find.text('Salin Catatan'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureRecord(tester, boundary, 'therapy-${module.id}.png');
    });
  }
  testWidgets('therapy chat records expose the explicit history action',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final boundary = GlobalKey();
    var opened = 0;
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: recordCaptureTheme(buildMalvaTheme()),
            home: Scaffold(
                body: RepaintBoundary(
                    key: boundary,
                    child: ColoredBox(
                      color: const Color(0xfff5f4f9),
                      child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(children: [
                            for (final module in [
                              thinkingTrapsModule,
                              abcdeModule,
                              behavioralActivationModule
                            ]) ...[
                              ChatSharedRecordCard(
                                  message: ChatMessage(
                                      id: module.id,
                                      senderId: 'patient',
                                      senderName: 'Pasien',
                                      text: module.title,
                                      timestamp: DateTime.parse(
                                          '2026-11-27T20:04:00+07:00'),
                                      isMine: true,
                                      kind: 'worksheet',
                                      metadata: {
                                        'module_id': module.id,
                                        'title': module.title
                                      }),
                                  onOpenRecord: () => opened++),
                              const SizedBox(height: 16),
                            ],
                          ])),
                    ))))));
    await tester.pumpAndSettle();
    expect(find.text('Lihat riwayat'), findsNWidgets(3));
    await tester.tap(find.text('Lihat riwayat').first);
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(tester.takeException(), isNull);
    await captureRecord(tester, boundary, 'therapy-chat-cards.png');
  });
  testWidgets(
      'therapy detail handles token refresh and permanently hides after account change',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    const owner = AuthSession(
        role: UserRole.patient, identifier: 'one', displayName: 'One');
    container.read(authStateProvider.notifier).setSession(owner);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                      body: TextButton(
                          onPressed: () => showTherapySubmissionDetail(context,
                              moduleId: 'legacy-module',
                              title: 'Catatan lama',
                              answers: {'old_label': 'Jawaban pribadi lama'},
                              summary: 'Ringkasan tersimpan'),
                          child: const Text('Open')),
                    )))));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('Jawaban pribadi lama'), findsOneWidget);
    expect(find.text('Ringkasan tersimpan'), findsOneWidget);
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'one',
        displayName: 'One',
        accessToken: 'new-token'));
    await tester.pumpAndSettle();
    expect(find.text('Jawaban pribadi lama'), findsOneWidget);
    container.read(authStateProvider.notifier).clearSession();
    container.read(authStateProvider.notifier).setSession(owner);
    await tester.pumpAndSettle();
    expect(find.text('Jawaban pribadi lama'), findsNothing);
    expect(find.text('Sesi akun telah berubah.'), findsOneWidget);
  });
  testWidgets(
      'saved therapy details show missing fields and actual before after difference',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: Builder(
              builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => showTherapyRecordDetail(
                            context,
                            const BackendTherapySubmission(
                              id: 'saved',
                              moduleId: 'breathing',
                              title: 'Latihan Pernapasan Teratur',
                              answers: {
                                'cycles': 4,
                                'tension': {'before': 6, 'after': 1}
                              },
                              summary: '',
                              createdAt: '2026-11-27T14:10:00+07:00',
                            )),
                        child: const Text('Open')),
                  ))),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.text('2/3 Terisi'), findsOneWidget);
    expect(find.text('Turun 5 poin'), findsOneWidget);
    await tester.drag(
        find.byType(SingleChildScrollView).last, const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Belum dijawab pada sesi ini'), findsOneWidget);
    expect(find.text('Salin Catatan'), findsOneWidget);
    expect(find.text('Selesai'), findsOneWidget);
  });

  testWidgets(
      'therapy history search and saved shared filters use stored state',
      (tester) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((_) async => http.Response(
            jsonEncode({
              'submissions': [
                {
                  'id': 'one',
                  'module_id': 'breathing',
                  'title': 'Latihan Pernapasan Teratur',
                  'answers': {},
                  'summary': '',
                  'created_at': '2026-11-27T14:10:00+07:00'
                },
                {
                  'id': 'two',
                  'module_id': 'pmr',
                  'title': 'Relaksasi Otot Progresif',
                  'answers': {},
                  'summary': '',
                  'shared_with_professional_id': 'pro',
                  'created_at': '2026-11-27T11:30:00+07:00'
                },
              ]
            }),
            200)));
    final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)]);
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'patient',
        displayName: 'Pasien',
        accessToken: 'token'));
    final boundary = GlobalKey();
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
            key: boundary,
            child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: recordCaptureTheme(buildMalvaTheme()),
                home: const TherapySubmissionsScreen()))));
    await tester.pumpAndSettle();
    expect(find.text('Semua (2)'), findsOneWidget);
    if (recordCaptureEnabled) {
      await tester.runAsync(() async {
        final context = tester.element(find.byType(TherapySubmissionsScreen));
        await precacheImage(
            const AssetImage('assets/reference/breathing.png'), context);
        if (context.mounted)
          await precacheImage(
              const AssetImage('assets/reference/pmr.png'), context);
      });
      await tester.pumpAndSettle();
    }
    await captureRecord(tester, boundary, 'therapy-history.png');
    await tester.tap(find.widgetWithText(ChoiceChip, 'Dibagikan'));
    await tester.pumpAndSettle();
    expect(find.text('Relaksasi Otot Progresif'), findsOneWidget);
    expect(find.text('Latihan Pernapasan Teratur'), findsNothing);
    await tester.enterText(find.byType(TextField), 'tidak ada');
    await tester.pumpAndSettle();
    expect(find.text('Relaksasi Otot Progresif'), findsNothing);
    expect(find.text('Tidak ada riwayat yang cocok'), findsOneWidget);
  });
}
