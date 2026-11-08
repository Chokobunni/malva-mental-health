import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/mood_medication_checkin_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

void main() {
  for (final scale in [1.0, 1.5]) {
    testWidgets(
        'prescription without reminder renders, logs, edits and scrolls at text scale $scale',
        (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      const session = AuthSession(
          role: UserRole.patient,
          identifier: 'patient',
          displayName: 'Pasien',
          backendUserId: 'patient',
          accessToken: 'token');
      final medications = [
        {
          'id': '00000000-0000-4000-8000-000000000001',
          'name': 'Lamictal',
          'dosage': '20 mg',
          'form': 'Tablet',
          'reminder_time': '22:00',
          'relation_to_meal': 'Setelah makan',
          'current_stock': 29,
          'source': 'Pasien',
        },
        {
          'id': '00000000-0000-4000-8000-000000000002',
          'name': 'Obat resep tanpa pengingat',
          'dosage': 'Sesuai resep',
          'form': 'Tablet',
          'reminder_time': '',
          'current_stock': 12,
          'source': 'prescription',
        },
      ];
      var logged = false;
      Map<String, dynamic>? saved;
      final api = MalvaApiClient(
          baseUrl: 'https://test.invalid',
          httpClient: MockClient((request) async {
            if (request.method == 'PUT') {
              saved = jsonDecode(request.body) as Map<String, dynamic>;
              return http.Response(
                  jsonEncode({
                    'medication': {...medications.last, ...saved!}
                  }),
                  200);
            }
            if (request.method == 'POST') {
              logged = true;
              return http.Response('{"medication_log":{}}', 200);
            }
            return http.Response(
                jsonEncode({'medications': medications, 'medication_logs': []}),
                200);
          }));
      final container = ProviderContainer(overrides: [
        malvaStoreProvider.overrideWith(
            (ref) => MalvaStoreNotifier(null, null)..applySession(session)),
      ]);
      addTearDown(container.dispose);
      final store = container.read(malvaStoreProvider.notifier);
      await tester
          .runAsync(() => store.loadMedications(api, session.accessToken));
      expect(container.read(malvaStoreProvider).medications.last.reminders,
          isEmpty);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              theme: buildMalvaTheme(),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: MoodMedicationCheckinScreen(
                  session: session, apiClient: api))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Medication'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(ErrorWidget), findsNothing);

      await tester.scrollUntilVisible(
          find.text('Obat resep tanpa pengingat'), 240);
      await tester.pumpAndSettle();
      expect(find.text('Belum diatur'), findsOneWidget);
      final card = find.ancestor(
          of: find.text('Obat resep tanpa pengingat'),
          matching: find.byType(Card));
      final take = find.descendant(of: card, matching: find.text('Take Now'));
      await tester.ensureVisible(take);
      await tester.pumpAndSettle();
      await tester.tap(take);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Taken'));
      await tester.pumpAndSettle();
      expect(logged, isTrue);
      expect(tester.takeException(), isNull);

      final edit =
          find.descendant(of: card, matching: find.byIcon(Icons.edit_rounded));
      await tester.ensureVisible(edit);
      await tester.pumpAndSettle();
      await tester.tap(edit);
      await tester.pumpAndSettle();
      expect(find.text('Edit Medication'), findsOneWidget);
      expect(find.text('Reminder belum diatur'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('Simpan'));
      await tester.tap(find.text('Simpan'));
      await tester.pumpAndSettle();
      expect(saved?['reminder_time'], '');
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView).last, const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.byType(ErrorWidget), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
}
