import 'dart:async';
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
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/screens/chat/chat_shared_record_card.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/time/wib.dart';

const _session = AuthSession(
    role: UserRole.professional,
    identifier: 'pro',
    backendUserId: 'pro',
    displayName: 'Profesional',
    accessToken: 'token');

Map<String, dynamic> _answers(String module, {int value = 2}) => {
      'scale_version': 2,
      for (var i = 1; i <= (module == 'who5' ? 5 : 21); i++) 'q$i': value,
    };

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status,
        headers: {'content-type': 'application/json'});

Future<ProviderContainer> _show(WidgetTester tester,
    {required String kind,
    Map<String, dynamic> metadata = const {},
    String text = '',
    DateTime? timestamp,
    AuthSession session = _session,
    Future<http.Response> Function(http.Request)? respond}) async {
  final container = ProviderContainer(overrides: [
    apiClientProvider.overrideWithValue(MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient(respond ?? (_) async => _json({}, 403)))),
  ]);
  addTearDown(container.dispose);
  container.read(authStateProvider.notifier).setSession(session);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: SizedBox(
                      width: 300,
                      child: ChatSharedRecordCard(
                          message: ChatMessage(
                              id: 'message',
                              senderId: 'patient',
                              senderName: 'Pasien',
                              text: text,
                              timestamp: timestamp ??
                                  wibFromParts(2026, 11, 11, 17, 43),
                              isMine: false,
                              kind: kind,
                              metadata: metadata))))))));
  await tester.pumpAndSettle();
  return container;
}

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
  for (final shape in ['flat', 'nested', 'bundle']) {
    for (final role in [UserRole.patient, UserRole.professional]) {
      testWidgets('$role $shape legacy totals restore independent model CF',
          (tester) async {
        await _show(tester,
            kind: 'assessment',
            session: AuthSession(
                role: role,
                identifier: 'viewer',
                displayName: 'Viewer',
                accessToken: 'token'),
            metadata: switch (shape) {
              'flat' => {'phq9_score': 23, 'gad7_score': 21, 'cf': .99},
              'bundle' => {
                  'bundle': {
                    'phq9': {'score': 23},
                    'gad7': {'score': 21}
                  }
                },
              _ => {
                  'phq9': {'score': 23},
                  'gad7': {'score': 21}
                },
            });
        expect(find.text('23 / 27'), findsOneWidget);
        expect(find.text('21 / 21'), findsOneWidget);
        expect(find.textContaining('0.90', findRichText: true), findsOneWidget);
        expect(find.textContaining('0.85', findRichText: true), findsOneWidget);
        expect(find.textContaining('0.99', findRichText: true), findsNothing);
        expect(find.text('CF belum tersedia'), findsNothing);
      });
    }
    testWidgets('PHQ/GAD $shape snapshot renders compact inline score level CF',
        (tester) async {
      final instruments = {
        'phq9': {'score': 8, 'max_score': 27, 'cf': .684, 'level': 'severe'},
        'gad7': {'score': 6, 'max_score': 21, 'cf': .684},
      };
      await _show(tester,
          kind: 'assessment',
          metadata: switch (shape) {
            'flat' => {
                'phq9_score': 8,
                'gad7_score': 6,
                'phq9_cf': .684,
                'gad7_cf': .684
              },
            'bundle' => {'bundle': instruments},
            _ => instruments,
          });
      expect(find.text('Hasil Screening Klinis'), findsOneWidget);
      expect(find.text('PHQ-9 (Depresi)'), findsOneWidget);
      expect(find.text('8 / 27'), findsOneWidget);
      expect(find.text('6 / 21'), findsOneWidget);
      expect(find.text('Ringan'), findsNWidgets(2));
      expect(find.textContaining('0.68', findRichText: true), findsNWidgets(2));
      expect(
          find.textContaining('(68%)', findRichText: true), findsNWidgets(2));
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.byType(DropdownButton), findsNothing);
      await tester.tap(find.text('PHQ-9 (Depresi)'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('17:43'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('invalid score CF and missing CF never become zero',
      (tester) async {
    await _show(tester, kind: 'screening', metadata: {
      'crisis_flag': true,
      'phq9': {'score': 8.5, 'cf': double.nan},
      'gad7': {'score': -1},
      'cf': .95,
    });
    expect(find.text('— / 27'), findsOneWidget);
    expect(find.text('— / 21'), findsOneWidget);
    expect(find.text('Belum tersedia'), findsNWidgets(2));
    expect(find.text('CF belum tersedia'), findsNWidgets(2));
    expect(find.text('INDIKATOR KESELAMATAN: YA'), findsOneWidget);
    expect(find.textContaining('0.00', findRichText: true), findsNothing);
    expect(find.textContaining('0.95', findRichText: true), findsNothing);
  });

  for (final module in ['who5', 'dass21']) {
    for (final role in [UserRole.patient, UserRole.professional]) {
      for (final status in [403, 404]) {
        testWidgets(
            '$role $module denied detail $status keeps snapshot private',
            (tester) async {
          await _show(tester,
              kind: 'assessment',
              session: AuthSession(
                  role: role,
                  identifier: 'viewer',
                  displayName: 'Viewer',
                  accessToken: 'token'),
              metadata: {
                'submission_id': 'private',
                'module_id': module,
                'answers': _answers(module)
              },
              respond: (_) async => _json({'error': 'Tidak tersedia'}, status));
          expect(find.text('Assessment belum tersedia'), findsOneWidget);
          expect(find.textContaining('CF'), findsNothing);
        });
      }
      testWidgets('$role $module serialized saved detail retains triage CF',
          (tester) async {
        final answers = module == 'who5'
            ? {'scale_version': 2, 'q1': 1, 'q2': 5, 'q3': 5, 'q4': 5, 'q5': 5}
            : _answers('dass21', value: 3);
        await _show(tester,
            kind: 'assessment',
            session: AuthSession(
                role: role,
                identifier: 'viewer',
                displayName: 'Viewer',
                accessToken: 'token'),
            metadata: {'submission_id': 'saved', 'module_id': module},
            respond: (_) async => _json({
                  'submission': {
                    'id': 'saved',
                    'module_id': module,
                    'answers': answers,
                    'summary': 'Ringkasan tanpa CF',
                  }
                }));
        expect(
            find.textContaining(module == 'who5' ? '0.55' : '0.90',
                findRichText: true),
            findsOneWidget);
        expect(find.text('CF belum tersedia'), findsNothing);
        if (module == 'who5') expect(find.text('21 / 25'), findsOneWidget);
        if (module == 'dass21')
          expect(find.text('INDIKATOR KESELAMATAN: YA'), findsOneWidget);
      });
      testWidgets(
          '$role $module score-only snapshot cannot invent triage facts',
          (tester) async {
        await _show(tester,
            kind: 'assessment',
            session: AuthSession(
                role: role,
                identifier: 'viewer',
                displayName: 'Viewer',
                accessToken: 'token'),
            metadata: {
              'module_id': module,
              'score': 21,
              'raw': 21,
              'who5_percent': 84,
              'depression': 28,
              'anxiety': 28,
              'stress': 28
            });
        expect(find.text('CF belum tersedia'), findsOneWidget);
        expect(find.textContaining('0.55', findRichText: true), findsNothing);
        expect(find.textContaining('0.40', findRichText: true), findsNothing);
      });
    }
    testWidgets('$module fetches authorized saved answers inline',
        (tester) async {
      var requests = 0;
      await _show(tester,
          kind: 'assessment',
          metadata: {'submission_id': 'saved', 'module_id': module},
          respond: (request) async {
        expect(request.url.path, '/v1/therapy-submissions/saved');
        expect(request.headers['Authorization'], 'Bearer token');
        requests++;
        return _json({
          'submission': {
            'id': 'saved',
            'module_id': module,
            'answers': _answers(module)
          }
        });
      });
      expect(requests, 1);
      expect(find.text('Hasil Screening Klinis'), findsOneWidget);
      expect(
          find.textContaining('Dukungan aturan triage (CF)'), findsOneWidget);
      if (module == 'who5') {
        expect(find.text('10 / 25'), findsOneWidget);
        expect(find.text('Rendah'), findsOneWidget);
      } else {
        expect(find.textContaining('28 / 42'), findsNWidgets(3));
      }
      expect(find.byType(ExpansionTile), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
    });

    for (final status in [403, 404]) {
      testWidgets('$module denial $status never falls back to snapshot answers',
          (tester) async {
        await _show(tester,
            kind: 'assessment',
            metadata: {
              'submission_id': 'saved',
              'module_id': module,
              'answers': _answers(module)
            },
            respond: (_) async => _json({'error': 'Tidak tersedia'}, status));
        expect(find.text('Assessment belum tersedia'), findsOneWidget);
        expect(find.textContaining('0.55', findRichText: true), findsNothing);
        expect(find.text('10 / 25'), findsNothing);
        expect(find.textContaining('28 / 42'), findsNothing);
      });
    }
  }

  testWidgets('partial WHO answers cannot manufacture a score or CF',
      (tester) async {
    await _show(tester, kind: 'assessment', metadata: {
      'module_id': 'who5',
      'answers': {'q1': 3}
    });
    expect(find.text('— / 25'), findsOneWidget);
    expect(find.text('CF belum tersedia'), findsOneWidget);
    expect(find.text('Belum tersedia'), findsOneWidget);
  });

  for (final status in [200, 403, 404]) {
    testWidgets('screening ID unavailable $status cannot recover snapshot CF',
        (tester) async {
      await _show(tester,
          kind: 'screening',
          metadata: {
            'screening_id': 'private',
            'phq9_score': 23,
            'gad7_score': 21,
            'phq9_cf': .95,
            'gad7_cf': .85
          },
          respond: (_) async => _json(
              status == 200 ? {'screenings': []} : {'error': 'Tidak tersedia'},
              status));
      expect(find.text('Assessment belum tersedia'), findsOneWidget);
      expect(find.textContaining('CF'), findsNothing);
    });
  }

  testWidgets(
      'screening id resolves actual per-instrument CF for selected patient',
      (tester) async {
    await _show(tester,
        kind: 'screening',
        metadata: {'screening_id': 'old', 'phq9_score': 8, 'gad7_score': 6},
        respond: (request) async {
      expect(request.url.queryParameters['patient_id'], 'patient');
      expect(request.url.queryParameters['limit'], '0');
      return _json({
        'screenings': [
          {
            'id': 'old',
            'patient_id': 'patient',
            'bundle': {
              'phq9': {'score': 8, 'max_score': 27, 'cf': .684},
              'gad7': {'score': 6, 'max_score': 21, 'cf': .55}
            }
          }
        ]
      });
    });
    expect(find.textContaining('0.68', findRichText: true), findsOneWidget);
    expect(find.textContaining('0.55', findRichText: true), findsOneWidget);
  });

  testWidgets('goals show actual weekly progress and clamp completed bar',
      (tester) async {
    await _show(tester, kind: 'goals', metadata: {
      'goals': [
        {'title': 'Jalan Pagi', 'done_this_week': 4, 'target_per_week': 3},
        {'title': 'Tidur', 'target_per_week': 7}
      ]
    });
    expect(find.text('Progress Goals & Habits'), findsOneWidget);
    expect(find.text('4/3 minggu ini'), findsOneWidget);
    expect(find.text('—/7 minggu ini'), findsOneWidget);
    final bars = tester
        .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator))
        .toList();
    expect(bars.first.value, 1);
    expect(bars.length, 1);
  });

  testWidgets('diary heading precedes dated cream card and full saved note',
      (tester) async {
    const note = 'Catatan lengkap.\nBaris kedua yang tetap dibaca langsung.';
    await _show(tester, kind: 'diary', metadata: {
      'title': 'Bertemu teman',
      'note': note,
      'occurred_at': '2026-11-08T19:39:00+07:00'
    });
    expect(find.text('Diary'), findsOneWidget);
    expect(find.text(note), findsOneWidget);
    expect(find.text('11/11/2026'), findsOneWidget);
    expect(find.text('17:43'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Diary')).dy,
        lessThan(tester.getTopLeft(find.text('11/11/2026')).dy));
    expect(tester.getTopLeft(find.text('17:43')).dy,
        lessThan(tester.getTopLeft(find.text('08/11/2026 19:39 WIB')).dy));
    expect(find.textContaining('Baca'), findsNothing);
  });

  testWidgets(
      'medication cards retain saved form dose time and meal instructions',
      (tester) async {
    await _show(tester, kind: 'prescription', metadata: {
      'medications': [
        {
          'name': 'Obat tersimpan',
          'form': 'Tablet',
          'dosage': '20 mg',
          'reminder_time': '22:00',
          'relation_to_meal': 'Setelah makan',
        }
      ]
    });
    for (final label in [
      'DAFTAR OBAT AKTIF & RESEP',
      'Obat tersimpan',
      'Tablet',
      '20 mg',
      '22:00',
      'Setelah makan'
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('11/11/2026'), findsOneWidget);
    expect(find.text('17:43'), findsOneWidget);
    expect(tester.getTopLeft(find.text('17:43')).dy,
        lessThan(tester.getTopLeft(find.text('DAFTAR OBAT AKTIF & RESEP')).dy));
    expect(tester.takeException(), isNull);
  });

  testWidgets('single medication share uses the outer record date and clock',
      (tester) async {
    await _show(tester,
        kind: 'medication',
        timestamp: wibFromParts(2026, 11, 9, 1, 25),
        metadata: {
          'medication': {'name': 'Obat tersimpan'}
        });
    expect(find.text('09/11/2026'), findsOneWidget);
    expect(find.text('01:25'), findsOneWidget);
    expect(tester.getTopLeft(find.text('01:25')).dy,
        lessThan(tester.getTopLeft(find.text('DAFTAR OBAT AKTIF & RESEP')).dy));
  });

  testWidgets(
      'seven-day snapshot stays saved and unavailable historical fetch stays unknown',
      (tester) async {
    var calls = 0;
    await _show(tester, kind: 'summary', text: 'Ringkasan 7 hari', metadata: {
      'mood_count': 6,
      'avg_sleep_hours': 5.7,
      'medication_adherence': 100
    }, respond: (_) async {
      calls++;
      return _json({}, 403);
    });
    expect(find.text('6 Kali'), findsOneWidget);
    expect(find.text('5.7 Jam'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(calls, 0);
    await tester.pumpWidget(const SizedBox());
    await _show(tester, kind: 'summary', text: 'Ringkasan 14 hari', metadata: {
      'mood_count': 99,
      'avg_sleep_hours': 14,
      'medication_adherence': 99
    });
    expect(find.text('99 Kali'), findsNothing);
    expect(find.text('14 Jam'), findsNothing);
    expect(find.text('— Kali'), findsOneWidget);
    expect(find.text('— Jam'), findsOneWidget);
    expect(find.text('—%'), findsOneWidget);
  });

  testWidgets(
      'historical 14-day metrics wait for real authorized seven-day data',
      (tester) async {
    final pending = Completer<http.Response>();
    await _show(tester,
        kind: 'summary',
        text: 'Ringkasan 14 hari: 99 mood check-in',
        timestamp: wibNow(),
        metadata: {
          'mood_count': 99,
          'avg_sleep_hours': 14,
          'medication_adherence': 99
        }, respond: (request) async {
      expect(request.url.queryParameters['patient_id'], 'patient');
      if (request.url.path == '/v1/mood-checkins') return pending.future;
      return _json({'logs': []});
    });
    await tester.pumpAndSettle();
    expect(find.text('Ringkasan Periodik (7 Hari)'), findsOneWidget);
    expect(find.text('99 Kali'), findsNothing);
    pending.complete(_json({
      'moods': [
        {
          'id': 'recent',
          'mood': 'good',
          'sleep_hours': 6.5,
          'occurred_at': wibIso(wibNow())
        }
      ]
    }));
    await tester.pumpAndSettle();
    expect(find.text('1 Kali'), findsOneWidget);
    expect(find.text('6.5 Jam'), findsOneWidget);
  });

  testWidgets(
      'historical summary recomputes seven days ending on original message date',
      (tester) async {
    final start = wibFromParts(2025, 1, 5);
    final end = wibFromParts(2025, 1, 12);
    await _show(tester,
        kind: 'summary',
        text: 'Ringkasan 14 hari',
        timestamp: wibFromParts(2025, 1, 11, 17, 43),
        metadata: {
          'mood_count': 99,
          'avg_sleep_hours': 14,
          'medication_adherence': 99
        },
        respond: (request) async =>
            _json(request.url.path == '/v1/mood-checkins'
                ? {
                    'moods': [
                      {
                        'id': 'start',
                        'mood': 'good',
                        'sleep_hours': 6,
                        'occurred_at': wibIso(start)
                      },
                      {
                        'id': 'before',
                        'mood': 'good',
                        'sleep_hours': 1,
                        'occurred_at':
                            wibIso(start.subtract(const Duration(minutes: 1)))
                      },
                      {
                        'id': 'end',
                        'mood': 'good',
                        'sleep_hours': 12,
                        'occurred_at': wibIso(end)
                      },
                      {
                        'id': 'today',
                        'mood': 'good',
                        'sleep_hours': 10,
                        'occurred_at': wibIso(wibNow())
                      },
                    ]
                  }
                : {
                    'medication_logs': [
                      {
                        'id': 'then',
                        'status': 'taken',
                        'taken_at': wibIso(start)
                      },
                      {
                        'id': 'end',
                        'status': 'missed',
                        'taken_at': wibIso(end)
                      },
                      {
                        'id': 'now',
                        'status': 'missed',
                        'taken_at': wibIso(wibNow())
                      },
                    ]
                  }));
    expect(find.text('1 Kali'), findsOneWidget);
    expect(find.text('6 Jam'), findsOneWidget);
    expect(find.text('100%'), findsOneWidget);
    expect(find.text('17:43'), findsOneWidget);
  });

  for (final switchOwner in [false, true]) {
    testWidgets(
        'pending result ${switchOwner ? 'rejects account switch' : 'allows same-owner refresh'}',
        (tester) async {
      final pending = Completer<http.Response>();
      final container = await _show(tester,
          kind: 'assessment',
          metadata: {'submission_id': 'saved', 'module_id': 'who5'},
          respond: (_) => pending.future);
      container.read(authStateProvider.notifier).setSession(AuthSession(
          role: UserRole.professional,
          identifier: switchOwner ? 'other' : 'pro',
          backendUserId: switchOwner ? 'other' : 'pro',
          displayName: 'Profesional',
          accessToken: 'refreshed'));
      await tester.pump();
      pending.complete(_json({
        'submission': {
          'id': 'saved',
          'module_id': 'who5',
          'answers': _answers('who5')
        }
      }));
      await tester.pumpAndSettle();
      expect(find.text('10 / 25'), switchOwner ? findsNothing : findsOneWidget);
    });
  }

  for (final role in [UserRole.patient, UserRole.professional]) {
    testWidgets(
        '$role recovered CF renders all four instruments at phone width',
        (tester) async {
      final boundary = GlobalKey();
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(MalvaApiClient(
            baseUrl: 'http://backend.test',
            httpClient: MockClient((request) async {
              final module = request.url.path.split('/').last;
              return _json({
                'submission': {
                  'id': module,
                  'module_id': module,
                  'answers': module == 'who5'
                      ? {
                          'scale_version': 2,
                          'q1': 1,
                          'q2': 5,
                          'q3': 5,
                          'q4': 5,
                          'q5': 5
                        }
                      : _answers('dass21', value: 3),
                }
              });
            }))),
      ]);
      addTearDown(container.dispose);
      container.read(authStateProvider.notifier).setSession(AuthSession(
          role: role,
          identifier: role.name,
          displayName: 'Viewer',
          accessToken: 'token'));
      final records = <Map<String, dynamic>>[
        {'phq9_score': 23, 'gad7_score': 21},
        {'module_id': 'who5', 'submission_id': 'who5'},
        {'module_id': 'dass21', 'submission_id': 'dass21'},
      ];
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              home: Scaffold(
                  body: SingleChildScrollView(
                      child: RepaintBoundary(
                          key: boundary,
                          child: Container(
                              width: 390,
                              padding: const EdgeInsets.all(16),
                              color: const Color(0xFFF0F3F9),
                              child: Column(
                                  crossAxisAlignment: role == UserRole.patient
                                      ? CrossAxisAlignment.end
                                      : CrossAxisAlignment.start,
                                  children: [
                                    for (var i = 0; i < records.length; i++)
                                      Padding(
                                          padding:
                                              const EdgeInsets.only(top: 14),
                                          child: SizedBox(
                                              width: 390 * .70,
                                              child: ChatSharedRecordCard(
                                                  message: ChatMessage(
                                                      id: 'cf-$i',
                                                      senderId: 'patient',
                                                      senderName: 'Pasien',
                                                      text: '',
                                                      timestamp: wibFromParts(
                                                          2026, 11, 11, 17, 43),
                                                      isMine: role ==
                                                          UserRole.patient,
                                                      kind: 'assessment',
                                                      metadata: records[i])))),
                                  ]))))))));
      await tester.pumpAndSettle();
      expect(find.text('23 / 27'), findsOneWidget);
      expect(find.text('21 / 21'), findsOneWidget);
      expect(find.text('21 / 25'), findsOneWidget);
      expect(find.text('42 / 42'), findsNWidgets(3));
      expect(find.textContaining('0.90', findRichText: true), findsNWidgets(2));
      expect(find.textContaining('0.85', findRichText: true), findsOneWidget);
      expect(find.textContaining('0.55', findRichText: true), findsOneWidget);
      expect(find.text('CF belum tersedia'), findsNothing);
      expect(find.text('INDIKATOR KESELAMATAN: YA'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final output = Platform.environment['MALVA_SCREENING_CF_RENDER_DIR'];
      if (output != null && output.isNotEmpty) {
        await tester.runAsync(() async {
          final render = boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(output).create(recursive: true);
          await File('$output/screening-cf-${role.name}.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    });
  }

  testWidgets('compact cards render at phone width without overflow',
      (tester) async {
    final boundary = GlobalKey();
    final records = <(String, Map<String, dynamic>, String)>[
      (
        'summary',
        {'mood_count': 6, 'avg_sleep_hours': 5.7, 'medication_adherence': 100},
        'Ringkasan 7 hari'
      ),
      (
        'goals',
        {
          'goals': [
            {'title': 'Jalan Pagi', 'done_this_week': 0, 'target_per_week': 3},
            {
              'title': 'Elliptical Bike',
              'done_this_week': 0,
              'target_per_week': 3
            },
            {
              'title': 'Tidur jam 22.00',
              'done_this_week': 4,
              'target_per_week': 7
            },
            {'title': 'Berenang', 'done_this_week': 1, 'target_per_week': 2},
          ]
        },
        ''
      ),
      (
        'screening',
        {
          'phq9': {'score': 8, 'max_score': 27, 'cf': .684},
          'gad7': {'score': 6, 'max_score': 21, 'cf': .684}
        },
        ''
      ),
      ('assessment', {'module_id': 'who5', 'answers': _answers('who5')}, ''),
      (
        'prescription',
        {
          'medications': [
            {
              'name': 'Lamictal',
              'form': 'Tablet',
              'dosage': '20mg',
              'reminder_time': '22:00',
              'relation_to_meal': 'Setelah makan'
            },
            {
              'name': 'Aripiprazole',
              'form': 'Tablet',
              'dosage': '20mg',
              'reminder_time': '20:00',
              'relation_to_meal': 'Setelah makan'
            },
            {
              'name': 'Quetiapine',
              'form': 'Tablet',
              'dosage': '300mg',
              'reminder_time': '20:00',
              'relation_to_meal': 'Setelah makan'
            }
          ]
        },
        ''
      ),
      (
        'diary',
        {
          'title': 'Bertemu dengan teman',
          'note':
              'Saling bercerita soal masa lalu. Percakapan hari ini membuat saya merasa lebih tenang dan terhubung dengan teman.',
          'occurred_at': '2026-11-08T19:39:00+07:00'
        },
        ''
      ),
    ];
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                backgroundColor: const Color(0xFFF0F3F9),
                body: SingleChildScrollView(
                    child: RepaintBoundary(
                        key: boundary,
                        child: Container(
                            width: 390,
                            color: const Color(0xFFF0F3F9),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  for (var i = 0; i < records.length; i++)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 14),
                                        child: SizedBox(
                                            width: 390 *
                                                (i == 1
                                                    ? .50
                                                    : i >= 4
                                                        ? .86
                                                        : .70),
                                            child: ChatSharedRecordCard(
                                                message: ChatMessage(
                                                    id: '$i',
                                                    senderId: 'patient',
                                                    senderName: '',
                                                    text: records[i].$3,
                                                    timestamp: wibFromParts(
                                                        2026, 11, 11, 17, 43),
                                                    isMine: true,
                                                    kind: records[i].$1,
                                                    metadata: records[i].$2)))),
                                ]))))))));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final output = Platform.environment['MALVA_CHAT_RECORD_RENDER'];
    if (output != null && output.isNotEmpty) {
      final bounds = [
        for (var i = 0; i < records.length; i++)
          {
            'kind': records[i].$1,
            'left':
                tester.getRect(find.byType(ChatSharedRecordCard).at(i)).left,
            'top': tester.getRect(find.byType(ChatSharedRecordCard).at(i)).top,
            'width':
                tester.getRect(find.byType(ChatSharedRecordCard).at(i)).width,
            'height':
                tester.getRect(find.byType(ChatSharedRecordCard).at(i)).height,
          }
      ];
      await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await File(output).parent.create(recursive: true);
        await File(output).writeAsBytes(bytes!.buffer.asUint8List());
        await File(output.replaceFirst(RegExp(r'\.png$'), '.json'))
            .writeAsString(jsonEncode(bounds));
        image.dispose();
      });
    }
  });
}
