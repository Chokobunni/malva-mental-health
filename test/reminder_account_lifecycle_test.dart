import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/malva_app.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/services/goal_reminder_service.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/medication_reminder_service.dart';

const _patient = AuthSession(
    role: UserRole.patient,
    identifier: 'synthetic',
    displayName: 'Synthetic',
    backendUserId: 'patient-a',
    accessToken: 'synthetic');
const _professional = AuthSession(
    role: UserRole.professional,
    identifier: 'synthetic-prof',
    displayName: 'Synthetic',
    backendUserId: 'professional-a',
    accessToken: 'synthetic-prof');
const _medication = Medication(
    id: 'synthetic-med',
    name: 'Synthetic',
    dosage: '1',
    form: 'Tablet',
    reminders: [
      MedicationReminder(
          time: TimeOfDay(hour: 8, minute: 0), relationToMeal: '')
    ],
    currentStock: 1,
    alertBelow: 0,
    source: 'manual');

class _MedicationScheduler extends MedicationReminderService {
  final List<List<String>> scheduled = [];
  final List<String> cancelled = [];
  final orphanAlarms = <String>{};
  @override
  Future<void> initialize() async {}
  @override
  Future<void> scheduleAll(Iterable<Medication> medications) async {
    scheduled.add(medications.map((m) => m.id).toList());
  }

  @override
  Future<void> cancelRemindersFor(Iterable<String> ids) async {
    cancelled.addAll(ids);
  }

  @override
  Future<void> cancelObsoleteReminders(Iterable<String> currentIds) async {
    orphanAlarms.removeWhere((id) => !currentIds.contains(id));
  }
}

class _GoalScheduler extends GoalReminderService {
  final List<bool> scheduled = [];
  final List<List<String>> snapshots = [];
  int cancellations = 0;
  @override
  Future<void> initialize() async {}
  @override
  Future<GoalReminderSettings> loadSettings() async =>
      const GoalReminderSettings();
  @override
  Future<void> syncGoals(
      {required List<BackendGoal> goals,
      required GoalReminderSettings settings,
      DateTime? now,
      bool Function()? isCurrent}) async {
    if (!(isCurrent?.call() ?? true)) return;
    snapshots.add(goals.map((goal) => goal.id).toList());
    await sync(
        hasActiveGoals: goals.any((goal) => goal.isActive),
        enabled: settings.enabled,
        hour: settings.hour,
        minute: settings.minute);
  }

  @override
  Future<void> sync(
      {required bool hasActiveGoals,
      required bool enabled,
      required int hour,
      required int minute}) async {
    scheduled.add(hasActiveGoals && enabled);
  }

  @override
  Future<void> cancel() async {
    cancellations++;
  }
}

class _Client extends http.BaseClient {
  _Client(this.goals);
  final Future<http.Response> Function() goals;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = request.url.path == '/v1/goals'
        ? await goals()
        : http.Response('{}', 200);
    return http.StreamedResponse(
        Stream.value(response.bodyBytes), response.statusCode,
        headers: {'content-type': 'application/json'});
  }
}

http.Response _goals() => http.Response(
    jsonEncode({
      'goals': [
        {'id': 'g', 'is_active': true}
      ]
    }),
    200);

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump();
  }
}

void main() {
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  Future<ProviderContainer> mount(
      WidgetTester tester,
      _MedicationScheduler medications,
      _GoalScheduler goals,
      Future<http.Response> Function() response) async {
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(MalvaApiClient(
          baseUrl: 'http://synthetic.test', httpClient: _Client(response))),
      capabilitiesProvider.overrideWithValue(const PlatformCapabilities(
          canScheduleOsReminders: true,
          canRegisterPush: false,
          canExportFiles: false,
          canDialTel: false,
          canPickFiles: false,
          canGeolocate: false,
          canBindGoogleCalendar: false,
          isWebBuild: false)),
    ]);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MalvaApp(
            medicationReminderService: medications,
            goalReminderService: goals)));
    await _flush(tester);
    return container;
  }

  testWidgets(
      'signed-out cold start clears medication alarms left by a previous process',
      (tester) async {
    final meds = _MedicationScheduler()..orphanAlarms.add('old-account-med');
    final goals = _GoalScheduler();
    final container = await mount(tester, meds, goals, () async => _goals());
    expect(container.read(authStateProvider).session, isNull);
    expect(meds.orphanAlarms, isEmpty);
    expect(goals.cancellations, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
      'same-activity account changes request posted-only native shade cleanup',
      (tester) async {
    const channel = MethodChannel('malva/notifications');
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return null;
    });
    addTearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    final container = await mount(
        tester, _MedicationScheduler(), _GoalScheduler(), () async => _goals());
    container.read(authStateProvider.notifier).setSession(_patient);
    await _flush(tester);
    calls.clear();
    container.read(authStateProvider.notifier).setSession(_professional);
    await _flush(tester);
    expect(calls, ['clearPosted']);
    container.read(authStateProvider.notifier).clearSession();
    await _flush(tester);
    expect(calls, ['clearPosted', 'clearPosted']);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
      'medications hydrated after login receive a schedule; role switch cancels it',
      (tester) async {
    final meds = _MedicationScheduler();
    final goals = _GoalScheduler();
    final container = await mount(tester, meds, goals, () async => _goals());
    container.read(malvaStoreProvider.notifier).applySession(_patient);
    container.read(authStateProvider.notifier).setSession(_patient);
    await _flush(tester);
    container
        .read(malvaStoreProvider.notifier)
        .replaceMedications([_medication]);
    await _flush(tester);
    expect(meds.scheduled.where((ids) => ids.contains('synthetic-med')),
        hasLength(1));
    container.read(authStateProvider.notifier).setSession(_professional);
    await _flush(tester);
    expect(meds.cancelled, contains('synthetic-med'));
    final count = meds.scheduled.length;
    container
        .read(malvaStoreProvider.notifier)
        .replaceMedications([_medication.copyWith(currentStock: 2)]);
    await _flush(tester);
    expect(meds.scheduled.length, count,
        reason: 'professional accounts must not schedule medication');
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('goals response after logout cannot recreate a daily reminder',
      (tester) async {
    final pending = Completer<http.Response>();
    final meds = _MedicationScheduler();
    final goals = _GoalScheduler();
    final container = await mount(tester, meds, goals, () => pending.future);
    container.read(malvaStoreProvider.notifier).applySession(_patient);
    container.read(authStateProvider.notifier).setSession(_patient);
    await _flush(tester);
    container.read(authStateProvider.notifier).clearSession();
    await _flush(tester);
    pending.complete(_goals());
    await _flush(tester);
    expect(goals.scheduled, isEmpty);
    expect(goals.cancellations, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('clinical revisions and resume refresh the goal schedule',
      (tester) async {
    var fetches = 0;
    final goals = _GoalScheduler();
    final container =
        await mount(tester, _MedicationScheduler(), goals, () async {
      fetches++;
      return _goals();
    });
    container.read(authStateProvider.notifier).setSession(_patient);
    await _flush(tester);
    expect(fetches, 1);
    container.read(clinicalDataRevisionProvider.notifier).state++;
    await _flush(tester);
    expect(fetches, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _flush(tester);
    expect(fetches, 3);
    expect(goals.snapshots, [
      ['g'],
      ['g'],
      ['g']
    ]);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('older goal fetch cannot replace a newer revised schedule',
      (tester) async {
    final first = Completer<http.Response>();
    var fetches = 0;
    final goals = _GoalScheduler();
    final container =
        await mount(tester, _MedicationScheduler(), goals, () async {
      fetches++;
      return fetches == 1 ? first.future : http.Response('{"goals":[]}', 200);
    });
    container.read(authStateProvider.notifier).setSession(_patient);
    await _flush(tester);
    container.read(clinicalDataRevisionProvider.notifier).state++;
    await _flush(tester);
    first.complete(_goals());
    await _flush(tester);
    expect(goals.snapshots, [<String>[]]);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets(
      'professional login does not fetch or schedule patient goal reminders',
      (tester) async {
    var fetches = 0;
    final meds = _MedicationScheduler();
    final goals = _GoalScheduler();
    final container = await mount(tester, meds, goals, () async {
      fetches++;
      return _goals();
    });
    container.read(authStateProvider.notifier).setSession(_professional);
    await _flush(tester);
    expect(fetches, 0);
    expect(goals.scheduled, isEmpty);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 2));
  });
}
