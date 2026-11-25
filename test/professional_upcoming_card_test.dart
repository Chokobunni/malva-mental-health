import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/server_clock.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/widgets/care_session_card.dart';
import 'package:malva_mental_health/src/screens/pro_schedule_screen.dart';
import 'record_render_capture.dart';

void main() {
  testWidgets(
      'schedule date filter precedes today card and opens existing picker',
      (tester) async {
    tester.view.physicalSize = const Size(390, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await loadRecordCaptureFonts();
    final boundary = GlobalKey();
    const owner = AuthSession(
        role: UserRole.professional,
        identifier: 'pro',
        displayName: 'Pro',
        backendUserId: 'pro',
        accessToken: 'token');
    final api = MalvaApiClient(
        baseUrl: 'https://synthetic.test',
        httpClient: MockClient((request) async =>
            http.Response(jsonEncode({'sessions': []}), 200)));
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: RepaintBoundary(
                key: boundary,
                child: Scaffold(
                    body:
                        ProScheduleScreen(session: owner, apiClient: api))))));
    await tester.pumpAndSettle();
    final filter = find.widgetWithText(FilledButton, 'Semua tanggal');
    expect(filter, findsOneWidget);
    expect(tester.getTopLeft(find.text('Daftar Sesi')).dy,
        lessThan(tester.getTopLeft(find.text('Sesi hari ini')).dy));
    await captureRecord(tester, boundary, 'professional-schedule-filter.png');
    await tester.tap(filter);
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  for (final (width, scale) in [(390.0, 1.0), (280.0, 1.0), (280.0, 1.8)]) {
    testWidgets(
        'professional upcoming status stays visible at width $width scale $scale',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await loadRecordCaptureFonts();
      final boundary = GlobalKey();
      final session = BackendCareSession(
          id: 'future',
          patientId: 'patient',
          patientName: 'Calvin Citius',
          professionalId: 'pro',
          status: 'scheduled',
          scheduledAt: wibIso(ServerClock.now().add(const Duration(days: 2))));
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(scale)),
                  child: child!),
              home: RepaintBoundary(
                  key: boundary,
                  child: Scaffold(
                      body: SingleChildScrollView(
                          child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: CareSessionCard(
                                  session: session,
                                  role: UserRole.professional,
                                  allowPreSessionChat: true,
                                  onOpenChat: () {},
                                  onChanged: () async {}))))))));
      await tester.pump();
      expect(find.text('Terjadwal'), findsOneWidget);
      expect(find.byIcon(Icons.circle), findsOneWidget);
      expect(find.text('Buka Riwayat Chat'), findsNothing);
      if (width == 390 && scale == 1) {
        expect(tester.getTopLeft(find.text('Terjadwal')).dy,
            lessThan(tester.getBottomLeft(find.text('Calvin Citius')).dy));
        expect(tester.getTopLeft(find.text('Terjadwal')).dx,
            greaterThan(tester.getTopLeft(find.text('Calvin Citius')).dx));
      }
      expect(tester.takeException(), isNull);
      await captureRecord(
          tester, boundary, 'professional-upcoming-$width-$scale.png');
      await tester.pumpWidget(const SizedBox());
    });
  }
}
