import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/malva_app.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/goals_screen.dart';
import 'package:malva_mental_health/src/services/goal_reminder_service.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/medication_reminder_service.dart';
import 'goal_configured_reminder_test.dart' show MemoryStore, Scheduler;

const patient = AuthSession(
    role: UserRole.patient,
    identifier: 'p',
    backendUserId: 'p',
    displayName: 'P',
    accessToken: 't');

class Server {
  bool accepted = false;
  int failedReads = 0;
  Completer<void>? writeGate;
  final goals = <Map<String, dynamic>>[
    {
      'id': 'edit',
      'title': 'Goal edit',
      'category': 'general',
      'target_per_week': 7,
      'is_active': true,
      'details': {
        'method': 'yes_no',
        'start_date': '2026-01-01',
        'time': '07:00',
        'reminders': [30]
      }
    },
    {
      'id': 'keep',
      'title': 'Goal keep',
      'category': 'general',
      'target_per_week': 7,
      'is_active': true,
      'details': {
        'method': 'yes_no',
        'start_date': '2026-01-01',
        'time': '18:00',
        'reminders': [0]
      }
    },
  ];
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path != '/v1/goals' &&
        !request.url.path.startsWith('/v1/goals/'))
      return http.Response('{}', 200);
    if (request.method == 'GET') {
      if (accepted) {
        failedReads++;
        return http.Response('{"error":"reload gagal"}', 503);
      }
      return http.Response(jsonEncode({'goals': goals}), 200);
    }
    await writeGate?.future;
    accepted = true;
    if (request.method == 'DELETE') {
      goals.removeWhere((g) => g['id'] == 'edit');
      return http.Response('{}', 200);
    }
    goals.first.addAll(jsonDecode(request.body) as Map<String, dynamic>);
    return http.Response(jsonEncode({'goal': goals.first}), 200);
  }
}

Future<void> flush(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump();
  }
}

Future<void> tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.tap(finder);
  await tester.pumpAndSettle();
  await flush(tester);
}

Future<ProviderContainer> open(
    WidgetTester tester, Server server, Scheduler scheduler) async {
  FlutterSecureStorage.setMockInitialValues({});
  tester.view.physicalSize = const Size(430, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final container = ProviderContainer(overrides: [
    apiClientProvider.overrideWithValue(MalvaApiClient(
        baseUrl: 'https://goals.test', httpClient: MockClient(server.handle))),
    capabilitiesProvider.overrideWithValue(const PlatformCapabilities(
        canScheduleOsReminders: true,
        canRegisterPush: false,
        canExportFiles: false,
        canDialTel: false,
        canPickFiles: false,
        canGeolocate: false,
        canBindGoogleCalendar: false,
        isWebBuild: false))
  ]);
  await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MalvaApp(
          goalReminderService:
              GoalReminderService(store: MemoryStore(), scheduler: scheduler),
          medicationReminderService:
              MedicationReminderService(enabled: false))));
  await flush(tester);
  container.read(authStateProvider.notifier).setSession(patient);
  await flush(tester);
  await tester.pump(const Duration(seconds: 2));
  navigatorKey.currentState!
      .push(MaterialPageRoute<void>(builder: (_) => const GoalsScreen()));
  await tester.pumpAndSettle();
  await flush(tester);
  return container;
}

void main() {
  testWidgets(
      'account switch cancels a late native write from an accepted mutation snapshot',
      (tester) async {
    final server = Server();
    final scheduler = Scheduler();
    final container = await open(tester, server, scheduler);
    final gate = Completer<void>();
    scheduler.block = gate;
    await tap(tester, find.byTooltip('Hapus goal').first);
    await tap(tester, find.widgetWithText(FilledButton, 'Hapus'));
    expect(server.accepted, isTrue);
    expect(scheduler.block, isNull,
        reason: 'accepted snapshot has entered the native scheduler');
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.professional,
        identifier: 'other',
        backendUserId: 'other',
        displayName: 'Other',
        accessToken: 'other'));
    gate.complete();
    await flush(tester);
    expect(scheduler.pending, isEmpty);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 2));
  });
  for (final delete in [false, true]) {
    testWidgets(
        'accepted ${delete ? 'delete' : 'reminder removal'} updates real OS schedules when refresh fails',
        (tester) async {
      final server = Server();
      final scheduler = Scheduler();
      final container = await open(tester, server, scheduler);
      expect(scheduler.pending.values.any((t) => t.hour == 6 && t.minute == 30),
          isTrue);
      expect(scheduler.pending.values.any((t) => t.hour == 18), isTrue);
      if (delete) {
        await tap(tester, find.byTooltip('Hapus goal').first);
        await tap(tester, find.widgetWithText(FilledButton, 'Hapus'));
      } else {
        await tap(tester, find.byTooltip('Edit goal').first);
        await tap(tester, find.byTooltip('Hapus pengingat 30 menit'));
        await tap(tester, find.text('Simpan Perubahan'));
      }
      expect(server.accepted, isTrue);
      expect(server.failedReads, greaterThan(0));
      expect(scheduler.pending.values.any((t) => t.hour == 6 && t.minute == 30),
          isFalse);
      expect(scheduler.pending.values.any((t) => t.hour == 18), isTrue,
          reason: 'another valid goal must remain scheduled');
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
