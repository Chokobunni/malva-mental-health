import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/initial_screening_consent_screen.dart';
import 'package:malva_mental_health/src/screens/initial_symptoms_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/widgets/therapy_library.dart';

Map<String, dynamic> _complete(String module) => {
      for (var i = 1; i <= (module == 'who5' ? 5 : 21); i++) 'q$i': 2.0,
      scaleVersionKey: 2,
    };

void main() {
  test('completion rejects nonfinite items without changing legacy scores', () {
    for (final module in ['who5', 'dass21']) {
      expect(isCompleteAssessmentAnswers(module, _complete(module)), isTrue);
      for (final bad in [double.nan, double.infinity, 1.5]) {
        expect(
            isCompleteAssessmentAnswers(
                module, {..._complete(module), 'q1': bad}),
            isFalse);
      }
    }
    expect(
        isCompleteAssessmentAnswers(
            'dass21', {..._complete('dass21'), 'q1': 4}),
        isFalse);
    expect(isCompleteAssessmentAnswers('abcde', _complete('who5')), isFalse);
  });

  testWidgets(
      'skip and back from a partially answered WHO never create a result',
      (tester) async {
    tester.view.physicalSize = const Size(600, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var writes = 0;
    var skipped = 0;
    const session = AuthSession(
        role: UserRole.patient,
        identifier: 'patient',
        displayName: 'Patient',
        accessToken: 'test-token');
    final api = MalvaApiClient(
        baseUrl: 'https://backend.test',
        httpClient: MockClient((request) async {
          if (request.method == 'POST') writes++;
          return http.Response('{"submissions":[]}', 200);
        }));
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
      authStateProvider.overrideWith((ref) {
        final auth = AuthNotifier()..setSession(session);
        return auth;
      }),
    ]);
    addTearDown(container.dispose);
    final inForm = ValueNotifier(false);
    addTearDown(inForm.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            theme: buildMalvaTheme(),
            home: ValueListenableBuilder<bool>(
                valueListenable: inForm,
                builder: (context, show, child) => show
                    ? InitialSymptomsScreen(
                        session: session,
                        apiClient: api,
                        onComplete: () {},
                        onBack: () => inForm.value = false)
                    : InitialScreeningConsentScreen(
                        onAgree: () => inForm.value = true,
                        onSkip: () => skipped++)))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Saya setuju'));
    await tester.pumpAndSettle();
    final answer = find.byKey(const ValueKey('initial-who5-q1-2'));
    await tester.ensureVisible(answer);
    await tester.tap(answer);
    await tester.pump();
    final back = find.byIcon(Icons.arrow_back_rounded);
    await tester.scrollUntilVisible(back, -400,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(back);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Skip'));
    await tester.pumpAndSettle();
    expect(skipped, 2);
    expect(writes, 0);
    expect(container.read(malvaStoreProvider).assessments, isEmpty);
    expect(container.read(malvaStoreProvider).screeningBundles, isEmpty);
    expect(container.read(malvaStoreProvider).initialScreeningStatus,
        InitialScreeningStatus.skipped);
  });

  test('history API includes only complete assessments and unique delivery IDs',
      () async {
    final records = <Map<String, dynamic>>[];
    for (final module in ['who5', 'dass21']) {
      for (final bad in [null, '2', -1, 6, 1.5]) {
        records.add({
          'id': '$module-invalid-$bad',
          'module_id': module,
          'answers': {..._complete(module), 'q1': bad},
        });
      }
      records.addAll([
        {
          'id': '$module-empty',
          'module_id': module,
          'answers': {'scale_version': 2}
        },
        {
          'id': '$module-partial',
          'module_id': module,
          'answers': {'q1': 2}
        },
        {
          'id': '$module-valid',
          'module_id': module,
          'answers': _complete(module)
        },
        {
          'id': '$module-valid',
          'module_id': module,
          'answers': _complete(module)
        },
        // A real new assessment may have identical answers and a different ID.
        {
          'id': '$module-retake',
          'module_id': module,
          'answers': _complete(module)
        },
        {
          'id': '$module-legacy',
          'module_id': module,
          'answers': {..._complete(module)}..remove(scaleVersionKey)
        },
      ]);
    }
    records
        .add({'id': 'therapy', 'module_id': 'unknown-therapy', 'answers': {}});
    final api = MalvaApiClient(
      baseUrl: 'https://backend.test',
      httpClient: MockClient((_) async =>
          http.Response(jsonEncode({'submissions': records}), 200)),
    );
    final loaded = await api.listTherapySubmissions(accessToken: 'test-token');
    expect(loaded.map((item) => item.id), [
      'who5-valid',
      'who5-retake',
      'who5-legacy',
      'dass21-valid',
      'dass21-retake',
      'dass21-legacy',
      'therapy',
    ]);
  });

  testWidgets('saving or sharing an unchanged completed WHO form reuses its ID',
      (tester) async {
    tester.view.physicalSize = const Size(900, 12000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var creates = 0;
    final api = MalvaApiClient(
      baseUrl: 'https://backend.test',
      httpClient: MockClient((request) async {
        if (request.method == 'POST' &&
            request.url.path == '/v1/therapy-submissions') {
          creates++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
              jsonEncode({
                'submission': {'id': 'saved-$creates', ...body}
              }),
              201,
              headers: {'content-type': 'application/json; charset=utf-8'});
        }
        return http.Response('{"links":[]}', 200);
      }),
    );
    await tester.pumpWidget(ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(api),
          authStateProvider.overrideWith((ref) {
            final auth = AuthNotifier();
            auth.setSession(const AuthSession(
                role: UserRole.patient,
                identifier: 'patient',
                displayName: 'Patient',
                accessToken: 'test-token'));
            return auth;
          }),
        ],
        child: MaterialApp(
            theme: buildMalvaTheme(),
            home: const TherapyDetailScreen(module: who5Module))));
    await tester.pumpAndSettle();
    expect(creates, 0);
    final choices = find.widgetWithText(ChoiceChip, '2');
    expect(choices, findsNWidgets(5));
    for (var i = 0; i < 5; i++) {
      await tester.tap(choices.at(i));
      await tester.pump();
    }
    expect(creates, 0,
        reason: 'answering without explicit submission is not a test record');
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.text('Simpan ke Therapy Record'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Worksheet tersimpan di Therapy Record'),
          findsWidgets);
    }
    await tester.tap(find.text('Simpan & Kirim ke Profesional'));
    await tester.pumpAndSettle();
    expect(creates, 1,
        reason: 'save/share must reuse the completed submission');
    await tester.tap(find.widgetWithText(ChoiceChip, '3').first);
    await tester.pump();
    await tester.tap(find.text('Simpan ke Therapy Record'));
    await tester.pumpAndSettle();
    expect(creates, 2, reason: 'changed answers represent a new submission');
    expect(tester.takeException(), isNull);
  });
}
