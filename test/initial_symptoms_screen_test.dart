import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/assessment_screen.dart';
import 'package:malva_mental_health/src/screens/initial_symptoms_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

const _session = AuthSession(
  role: UserRole.patient,
  identifier: 'patient',
  displayName: 'Patient',
  accessToken: 'test-token',
);

Future<ProviderContainer> _pump(
    WidgetTester tester, Future<http.Response> Function(http.Request) respond,
    {VoidCallback? onComplete}) async {
  tester.view.physicalSize = const Size(600, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final api = MalvaApiClient(
      baseUrl: 'https://backend.test', httpClient: MockClient(respond));
  final container = ProviderContainer(overrides: [
    apiClientProvider.overrideWithValue(api),
    authStateProvider.overrideWith((ref) {
      final notifier = AuthNotifier();
      notifier.setSession(_session);
      return notifier;
    }),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
          theme: buildMalvaTheme(),
          home: InitialSymptomsScreen(
              session: _session,
              apiClient: api,
              onComplete: onComplete ?? () {},
              onBack: () {}))));
  await tester.pumpAndSettle();
  return container;
}

http.Response _saved() => http.Response(
    jsonEncode({
      'submission': {
        'id': 'saved-who',
        'module_id': 'who5',
        'title': 'WHO-5',
        'answers': {'q1': 5},
      }
    }),
    201,
    headers: {'content-type': 'application/json'});

Future<void> _answer(WidgetTester tester, List<int> answers) async {
  for (var i = 0; i < answers.length; i++) {
    final chip = find.byKey(ValueKey('initial-who5-q${i + 1}-${answers[i]}'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pump();
  }
  await tester.ensureVisible(find.byKey(const ValueKey('initial-who5-submit')));
}

void main() {
  test('late PHQ/GAD response cannot add results after an account reset',
      () async {
    final response = Completer<http.Response>();
    final api = MalvaApiClient(
        baseUrl: 'https://backend.test',
        httpClient: MockClient((_) => response.future));
    final store = MalvaStoreNotifier(api, null);
    addTearDown(store.dispose);
    final pending = store.submitScreeningBundle(
        phq9Answers: List.filled(9, 0),
        gad7Answers: List.filled(7, 0),
        isInitial: true,
        source: 'Initial patient screening',
        session: _session);
    store.resetForAccount();
    response.complete(http.Response('{"screening":{"id":"old"}}', 201));
    await expectLater(pending, throwsA(isA<AuthFailure>()));
    expect(store.state.screeningBundles, isEmpty);
    expect(store.state.assessments, isEmpty);
    expect(store.state.initialScreeningStatus, InitialScreeningStatus.pending);
  });

  testWidgets('requires all WHO answers before submission', (tester) async {
    var sent = false;
    await _pump(tester, (_) async {
      sent = true;
      return _saved();
    });
    await _answer(tester, [5, 5, 5, 5]);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('initial-who5-submit')))
            .onPressed,
        isNull);
    expect(sent, isFalse);
  });

  testWidgets(
      'save failure retains answers and retries before stable conclusion',
      (tester) async {
    var attempts = 0;
    Map<String, dynamic>? payload;
    var done = false;
    final container = await _pump(tester, (request) async {
      attempts++;
      payload = jsonDecode(request.body) as Map<String, dynamic>;
      return attempts == 1
          ? http.Response('{"error":"Coba lagi"}', 500)
          : _saved();
    }, onComplete: () => done = true);
    await _answer(tester, [5, 5, 5, 5, 5]);
    await tester.tap(find.byKey(const ValueKey('initial-who5-submit')));
    await tester.pumpAndSettle();
    expect(find.textContaining('belum tersimpan'), findsOneWidget);
    expect(find.text('Kondisi Mental Sangat Baik'), findsNothing);
    expect(container.read(malvaStoreProvider).initialScreeningStatus,
        InitialScreeningStatus.pending);
    await tester.tap(find.byKey(const ValueKey('initial-who5-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Kondisi Mental Sangat Baik'), findsOneWidget);
    expect(payload!['module_id'], 'who5');
    expect(payload!['answers'], {
      'q1': 5,
      'q2': 5,
      'q3': 5,
      'q4': 5,
      'q5': 5,
      'scale_version': 2,
      'scale_min': 0,
      'scale_max': 5,
    });
    expect(container.read(malvaStoreProvider).screeningBundles, isEmpty);
    expect(container.read(malvaStoreProvider).assessments, isEmpty);
    await tester.tap(find.text('Lanjut ke Home'));
    await tester.pumpAndSettle();
    expect(done, isTrue);
    expect(container.read(malvaStoreProvider).initialScreeningStatus,
        InitialScreeningStatus.completed);
  });

  testWidgets('R2 continuation waits for save and repeated taps send once',
      (tester) async {
    final response = Completer<http.Response>();
    var attempts = 0;
    await _pump(tester, (_) {
      attempts++;
      return response.future;
    });
    await _answer(tester, [1, 5, 5, 5, 5]);
    await tester.tap(find.byKey(const ValueKey('initial-who5-submit')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('initial-who5-submit')));
    await tester.pump();
    expect(find.byType(AssessmentScreen), findsNothing);
    response.complete(_saved());
    await tester.pumpAndSettle();
    expect(attempts, 1);
    expect(find.textContaining('Mohon lanjut mengisi'), findsOneWidget);
    await tester.tap(find.text('Lanjut PHQ-9 + GAD-7'));
    await tester.pumpAndSettle();
    expect(find.byType(AssessmentScreen), findsOneWidget);
    expect(find.byIcon(Icons.local_florist_rounded), findsOneWidget);
  });

  testWidgets(
      'old-account save completion cannot show conclusion or finish new account',
      (tester) async {
    final response = Completer<http.Response>();
    final container = await _pump(tester, (_) => response.future);
    await _answer(tester, [5, 5, 5, 5, 5]);
    await tester.tap(find.byKey(const ValueKey('initial-who5-submit')));
    await tester.pump();
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'different',
        displayName: 'Other',
        accessToken: 'other-token'));
    response.complete(_saved());
    await tester.pumpAndSettle();
    expect(find.text('Kondisi Mental Sangat Baik'), findsNothing);
    expect(container.read(malvaStoreProvider).initialScreeningStatus,
        InitialScreeningStatus.pending);
  });
}
