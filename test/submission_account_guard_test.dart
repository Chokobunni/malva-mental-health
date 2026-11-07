import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';
import 'package:malva_mental_health/src/widgets/therapy_library.dart';

http.Response _json(Object value) => http.Response(jsonEncode(value), 200,
    headers: {'content-type': 'application/json; charset=utf-8'});

void main() {
  for (final delayedStage in ['save', 'links', 'packages']) {
    testWidgets(
        'account switch during $delayedStage cancels stale form operation',
        (tester) async {
      tester.view.physicalSize = const Size(900, 12000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final pending = Completer<http.Response>();
      var started = false;
      Object response(String stage) => switch (stage) {
            'save' => {
                'submission': {'id': 'saved', 'module_id': 'who5'}
              },
            'links' => {
                'links': [
                  {
                    'professional_user_id': 'old-pro',
                    'professional_display_name':
                        'Previous account professional',
                    'status': 'active'
                  }
                ]
              },
            _ => {
                'packages': [
                  {
                    'id': 'pkg',
                    'professional_id': 'old-pro',
                    'status': 'active'
                  }
                ]
              },
          };
      final api = MalvaApiClient(
          baseUrl: 'https://synthetic.test',
          httpClient: MockClient((request) async {
            final stage = switch (request.url.path) {
              '/v1/therapy-submissions' => 'save',
              '/v1/patient-professional-links' => 'links',
              _ => 'packages',
            };
            if (stage == delayedStage) {
              started = true;
              return pending.future;
            }
            return _json(response(stage));
          }));
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(api),
        authStateProvider.overrideWith((ref) => AuthNotifier()
          ..setSession(const AuthSession(
              role: UserRole.patient,
              identifier: 'a',
              displayName: 'A',
              backendUserId: 'a',
              accessToken: 'a'))),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              theme: buildMalvaTheme(),
              home: const TherapyDetailScreen(module: who5Module))));
      await tester.pumpAndSettle();
      final choices = find.widgetWithText(ChoiceChip, '2');
      for (var i = 0; i < 5; i++) {
        await tester.tap(choices.at(i));
        await tester.pump();
      }
      await tester.tap(find.text('Simpan & Kirim ke Profesional'));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      expect(started, isTrue);
      container.read(authStateProvider.notifier).setSession(const AuthSession(
          role: UserRole.patient,
          identifier: 'b',
          displayName: 'B',
          backendUserId: 'b',
          accessToken: 'b'));
      await tester.pump();
      pending.complete(_json(response(delayedStage)));
      await tester.pumpAndSettle();
      expect(find.text('Previous account professional'), findsNothing);
      expect(find.text('Bagikan ke profesional'), findsNothing);
      expect(
          tester
              .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Simpan ke Therapy Record'))
              .onPressed,
          isNotNull);
      expect(tester.takeException(), isNull);
    });
  }
}
