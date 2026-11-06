import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/pro_schedule_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/server_clock.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/widgets/session_attendance_actions.dart';

const _pro = AuthSession(
    role: UserRole.professional,
    identifier: 'pro',
    displayName: 'Pro',
    backendUserId: 'pro',
    accessToken: 'pro-token');

BackendCareSession _session(
        {bool ended = false, bool completed = false, bool future = false}) =>
    BackendCareSession(
        id: 'session',
        patientId: 'patient',
        professionalId: 'pro',
        patientName: 'Patient',
        sessionType: 'chat',
        scheduledAt: wibIso(future
            ? ServerClock.now().add(const Duration(days: 2))
            : ServerClock.now().subtract(
                ended ? const Duration(hours: 8) : const Duration(minutes: 5))),
        durationMinutes: 30,
        status: completed ? 'completed' : 'scheduled');

void main() {
  setUp(() {
    initializeWib();
    ServerClock.reset();
  });
  tearDown(ServerClock.reset);

  testWidgets(
      'ended scheduled professional session offers completion without Join or Chat',
      (tester) async {
    final session = _session(ended: true);
    final api = MalvaApiClient(
        baseUrl: 'https://synthetic.test',
        httpClient: MockClient((request) async {
          final scope = request.url.queryParameters['scope'];
          final body = request.url.path == '/v1/care-sessions'
              ? {
                  'sessions': scope == 'past' || scope == 'today'
                      ? [
                          if (scope == 'past')
                            for (var i = 0; i < 12; i++)
                              {
                                'id': 'terminal-$i',
                                'patient_id': 'patient-$i',
                                'professional_id': 'pro',
                                'patient_name': 'Riwayat $i',
                                'scheduled_at': session.scheduledAt,
                                'status': 'completed',
                              },
                          {
                            'id': session.id,
                            'patient_id': session.patientId,
                            'professional_id': session.professionalId,
                            'patient_name': 'Patient',
                            'session_type': 'chat',
                            'scheduled_at': session.scheduledAt,
                            'duration_minutes': 30,
                            'status': 'scheduled',
                            'attended_marked_at': session.scheduledAt,
                          }
                        ]
                      : []
                }
              : {
                  'schedules': [],
                  'time_off': [],
                  'pricing': <String, Object>{}
                };
          return http.Response(jsonEncode(body), 200);
        }));
    final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)]);
    container.read(authStateProvider.notifier).setSession(_pro);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Scaffold(
                body: ProScheduleScreen(session: _pro, apiClient: api)))));
    await tester.pumpAndSettle();
    expect(find.text('Perlu diselesaikan'), findsOneWidget);
    expect(find.text('Join / Chat'), findsNothing);
    expect(find.text('Selesaikan sesi'), findsOneWidget);
    expect(find.text('Selesaikan sesi').hitTestable(), findsOneWidget,
        reason: 'actionable ended session must precede truncated history');
    expect(find.text('Kehadiran saya'), findsOneWidget,
        reason: 'legacy marker must not invent professional self attendance');
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });

  testWidgets(
      'terminal response wins over stale ended session from today scope',
      (tester) async {
    final session = _session(ended: true);
    final api = MalvaApiClient(
        baseUrl: 'https://synthetic.test',
        httpClient: MockClient((request) async {
          final scope = request.url.queryParameters['scope'];
          return http.Response(
              jsonEncode({
                if (request.url.path == '/v1/care-sessions')
                  'sessions': scope == 'today' || scope == 'past'
                      ? [
                          {
                            'id': session.id,
                            'patient_id': session.patientId,
                            'professional_id': session.professionalId,
                            'patient_name': 'Patient',
                            'session_type': 'chat',
                            'scheduled_at': session.scheduledAt,
                            'duration_minutes': 30,
                            'status':
                                scope == 'past' ? 'completed' : 'scheduled',
                            'summary_for_patient':
                                scope == 'past' ? 'Ringkasan akhir' : '',
                          }
                        ]
                      : []
                else ...{
                  'schedules': [],
                  'time_off': [],
                  'pricing': <String, Object>{},
                }
              }),
              200);
        }));
    final container = ProviderContainer(
        overrides: [apiClientProvider.overrideWithValue(api)]);
    container.read(authStateProvider.notifier).setSession(_pro);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Scaffold(
                body: ProScheduleScreen(session: _pro, apiClient: api)))));
    await tester.pumpAndSettle();
    expect(find.text('Selesaikan sesi'), findsNothing);
    expect(find.text('Perlu diselesaikan'), findsNothing);
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('past-session')), 300,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('Patient'), findsOneWidget);
    expect(find.text('Selesai'), findsOneWidget);
    expect(find.text('Ringkasan: Ringkasan akhir'), findsOneWidget);
    expect(find.text('Join / Chat'), findsNothing);
    expect(find.text('Kehadiran saya'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });

  for (final role in [UserRole.patient, UserRole.professional]) {
    testWidgets(
        '$role attendance has own actions and completion only after end',
        (tester) async {
      final container = ProviderContainer();
      Future<void> mount(BackendCareSession session) =>
          tester.pumpWidget(UncontrolledProviderScope(
              container: container,
              child: MaterialApp(
                  home: Scaffold(
                      body: SessionAttendanceActions(
                          session: session,
                          role: role,
                          onChanged: () async {})))));
      await mount(_session());
      await tester.pumpAndSettle();
      expect(find.text('Kehadiran saya'), findsOneWidget);
      expect(find.text('Hadir'), findsOneWidget);
      expect(find.text('Tidak hadir'), findsOneWidget);
      expect(find.text('Selesaikan sesi'), findsNothing);
      await mount(_session(ended: true));
      await tester.pumpAndSettle();
      expect(find.text('Selesaikan sesi'),
          role == UserRole.professional ? findsOneWidget : findsNothing);
      await mount(_session(ended: true, completed: true));
      await tester.pumpAndSettle();
      expect(find.byType(OutlinedButton), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });

    testWidgets('$role future and terminal hide empty attendance controls',
        (tester) async {
      final container = ProviderContainer();
      for (final session in [
        _session(future: true),
        _session(completed: true)
      ]) {
        await tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
                home: Scaffold(
                    body: SessionAttendanceActions(
                        session: session,
                        role: role,
                        onChanged: () async {})))));
        await tester.pumpAndSettle();
        expect(find.text('Kehadiran saya'), findsNothing);
        expect(find.byType(OutlinedButton), findsNothing);
        expect(find.byType(FilledButton), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });
  }

  testWidgets('attendance hides a late error after account switch',
      (tester) async {
    final pending = Completer<http.Response>();
    final api = MalvaApiClient(
        baseUrl: 'https://synthetic.test',
        httpClient: MockClient((_) => pending.future));
    final container = ProviderContainer();
    container.read(authStateProvider.notifier).setSession(_pro);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Scaffold(
                body: SessionAttendanceActions(
                    session: _session(),
                    role: UserRole.professional,
                    apiClient: api,
                    onChanged: () async {})))));
    await tester.tap(find.text('Hadir'));
    await tester.pump();
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.professional,
        identifier: 'other',
        displayName: 'Other',
        backendUserId: 'other',
        accessToken: 'other-token'));
    pending.complete(http.Response('{"error":"old account error"}', 400));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
  });
}
