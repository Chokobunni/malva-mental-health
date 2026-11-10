import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/mood_screen.dart';
import 'package:malva_mental_health/src/screens/medication_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

const patient = AuthSession(
    role: UserRole.patient,
    identifier: 'p',
    backendUserId: 'p',
    displayName: 'Pasien',
    accessToken: 'token');
void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
      'Add Mood Entry opens a full page with reference form and no modal',
      (tester) async {
    final api = MalvaApiClient(
        baseUrl: 'https://test.invalid',
        httpClient: MockClient(
            (r) async => http.Response(jsonEncode({'moods': []}), 200)));
    await tester.pumpWidget(ProviderScope(
        child:
            MaterialApp(home: MoodScreen(session: patient, apiClient: api))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Mood Entry'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Bagaimana perasaan\nAnda?'), findsOneWidget);
    expect(find.text('Suasana Hati Keseluruhan'), findsOneWidget);
    expect(find.byType(Slider), findsNWidgets(3));
    expect(find.byKey(const Key('sleep-hours-plus')), findsOneWidget);
    expect(find.byKey(const Key('sleep-minutes-plus')), findsOneWidget);
  });
  testWidgets('medication logs are reached through one dedicated history route',
      (tester) async {
    final api = MalvaApiClient(
        baseUrl: 'https://test.invalid',
        httpClient: MockClient((r) async =>
            http.Response(jsonEncode({'medication_logs': []}), 200)));
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: MedicationScreen(session: patient, apiClient: api))));
    await tester.pumpAndSettle();
    final button = find.widgetWithText(OutlinedButton, 'Riwayat minum obat');
    await tester.ensureVisible(button);
    await tester.pumpAndSettle();
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.text('Riwayat Minum Obat'), findsOneWidget);
    expect(find.text('Belum ada riwayat minum obat.'), findsOneWidget);
  });
}
