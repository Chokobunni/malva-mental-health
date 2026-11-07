import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/assessment_engine.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/assessment_screen.dart';
import 'package:malva_mental_health/src/screens/initial_symptoms_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

void _phoneSize(WidgetTester tester) {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  testWidgets(
      'WHO instructions and saved conclusion disclose mechanics on demand',
      (tester) async {
    _phoneSize(tester);
    const session = AuthSession(
      role: UserRole.patient,
      identifier: 'synthetic',
      displayName: 'Synthetic',
      accessToken: 'test-token',
    );
    final api = MalvaApiClient(
      baseUrl: 'https://backend.test',
      httpClient: MockClient((request) async => http.Response(
          jsonEncode({
            'submission': {
              'id': 'complete-who',
              'module_id': 'who5',
              'title': 'WHO-5',
              'answers': jsonDecode(request.body)['answers'],
            }
          }),
          201)),
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authStateProvider
            .overrideWith((ref) => AuthNotifier()..setSession(session)),
      ],
      child: MaterialApp(
        theme: buildMalvaTheme(),
        home: InitialSymptomsScreen(
            session: session, apiClient: api, onComplete: () {}, onBack: () {}),
      ),
    ));
    expect(find.textContaining('Jumlah 5 jawaban'), findsNothing);
    await tester.tap(find.text('Lihat cara penilaian'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Jumlah 5 jawaban'), findsOneWidget);
    await tester.tap(find.text('Lihat cara penilaian'));
    await tester.pumpAndSettle();
    for (var i = 1; i <= 5; i++) {
      final chip = find.byKey(ValueKey('initial-who5-q$i-5'));
      await tester.ensureVisible(chip);
      await tester.pumpAndSettle();
      await tester.tap(chip);
      await tester.pump();
    }
    final submit = find.byKey(const ValueKey('initial-who5-submit'));
    await tester.ensureVisible(submit);
    await tester.pumpAndSettle();
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(find.text('Kondisi Mental Sangat Baik'), findsOneWidget);
    expect(find.text('WHO-5: 100%'), findsOneWidget);
    expect(find.textContaining('Versi aturan:'), findsNothing);
    expect(find.textContaining('CF adalah'), findsNothing);
    await tester.ensureVisible(find.text('Lihat cara penilaian'));
    await tester.tap(find.text('Lihat cara penilaian'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Versi aturan:'), findsOneWidget);
    expect(find.textContaining('CF adalah'), findsOneWidget);
  });

  testWidgets('PHQ and GAD introductions keep score mechanics collapsed',
      (tester) async {
    _phoneSize(tester);
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
          theme: buildMalvaTheme(),
          home: const AssessmentScreen(isInitialScreening: true)),
    ));
    expect(find.text('Jawab sesuai 2 minggu terakhir'), findsNothing);
    expect(find.textContaining('Jumlah 9 jawaban'), findsNothing);
    expect(find.textContaining('Jumlah 7 jawaban'), findsNothing);
    expect(find.text('Lihat cara penilaian'), findsNWidgets(2));
    await tester.ensureVisible(find.text('Lihat cara penilaian').first);
    await tester.tap(find.text('Lihat cara penilaian').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Jumlah 9 jawaban'), findsOneWidget);
    expect(find.textContaining('Jumlah 7 jawaban'), findsNothing);
  });

  testWidgets(
      'initial result offers DASS only and keeps crisis support outside disclosure',
      (tester) async {
    _phoneSize(tester);
    final bundle = ScreeningBundle(
      id: 'synthetic-crisis',
      phq9: AssessmentEngine.score(
          type: AssessmentType.phq9, answers: [0, 0, 0, 0, 0, 0, 0, 0, 1]),
      gad7: AssessmentEngine.score(
          type: AssessmentType.gad7, answers: List.filled(7, 0)),
      createdAt: DateTime(2026, 11, 7),
      isInitial: true,
      source: 'test',
    );
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
          theme: buildMalvaTheme(),
          home: AssessmentResultScreen(bundle: bundle, onDone: () {})),
    ));
    expect(find.textContaining('WHO-5'), findsNothing);
    expect(find.textContaining('DASS-21'), findsWidgets);
    expect(find.textContaining('CF menunjukkan'), findsNothing);
    final safety = find.widgetWithText(FilledButton, 'Buka Safety Protocol');
    await tester.ensureVisible(safety);
    await tester.pumpAndSettle();
    expect(safety.hitTestable(), findsOneWidget);
    expect(find.textContaining('Crisis Support:'), findsOneWidget);
    await tester.ensureVisible(find.text('Lihat cara penilaian'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Lihat cara penilaian'));
    await tester.pumpAndSettle();
    expect(find.textContaining('CF menunjukkan'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
