import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/services/assessment_database_service.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

class MemoryStore implements SecureStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

const existing = AuthSession(
    role: UserRole.patient,
    identifier: 'existing',
    displayName: 'Existing',
    backendUserId: 'existing',
    accessToken: 'existing-token');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryStore storage;
  late int googleStatus;
  late MalvaStoreNotifier store;

  MalvaStoreNotifier createStore() {
    final api = MalvaApiClient(
        baseUrl: 'https://synthetic.test',
        httpClient: MockClient((request) async {
          if (request.url.path.startsWith('/v1/auth/')) {
            return http.Response(
                jsonEncode({
                  'user': {
                    'id': 'registered',
                    'email': 'new@example.test',
                    'role': 'patient',
                    'display_name': 'New'
                  },
                  'access_token': 'new-token',
                  'refresh_token': 'new-refresh',
                }),
                request.url.path.endsWith('google') ? googleStatus : 201);
          }
          return http.Response('{}', 200);
        }));
    final notifier = MalvaStoreNotifier(
        api, AssessmentDatabaseService(store: storage),
        secureStore: storage);
    addTearDown(() {
      if (notifier.mounted) notifier.dispose();
    });
    return notifier;
  }

  Future<void> flush() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  setUp(() {
    storage = MemoryStore();
    googleStatus = 201;
    store = createStore();
  });

  test('existing patient reaches Home without registration consent', () async {
    store.applySession(existing);
    await flush();
    expect(store.state.needsInitialScreeningDecision, isFalse);
  });

  test('cancelled registration entry cannot cross an account reset', () async {
    final session = await store.registerPatientOnline(
        email: 'new@example.test',
        password: 'Synthetic123!',
        displayName: 'New');
    store.resetForAccount();
    store.applySession(session);
    await flush();
    expect(store.state.needsInitialScreeningDecision, isFalse);
    expect(store.state.assessments, isEmpty);
  });

  test(
      'late Google registration response cannot re-arm entry after account switch',
      () async {
    final response = Completer<http.Response>();
    final delayedStore = MalvaStoreNotifier(
        MalvaApiClient(
            baseUrl: 'https://synthetic.test',
            httpClient: MockClient((request) async =>
                request.url.path == '/v1/auth/google'
                    ? response.future
                    : http.Response('{}', 200))),
        AssessmentDatabaseService(store: storage),
        secureStore: storage);
    addTearDown(delayedStore.dispose);
    final registration =
        delayedStore.loginPatientWithGoogle(idToken: 'synthetic');
    delayedStore.applySession(existing);
    response.complete(http.Response(
        jsonEncode({
          'user': {
            'id': 'late',
            'email': 'late@example.test',
            'role': 'patient',
            'display_name': 'Late'
          },
          'access_token': 'late-token',
          'refresh_token': 'late-refresh',
        }),
        201));
    final session = await registration;
    delayedStore.applySession(session);
    await flush();
    expect(delayedStore.state.needsInitialScreeningDecision, isFalse);
  });

  test('registration offers entry once; skip survives restart and re-login',
      () async {
    final session = await store.registerPatientOnline(
        email: 'new@example.test',
        password: 'Synthetic123!',
        displayName: 'New');
    store.applySession(session);
    await flush();
    expect(store.state.needsInitialScreeningDecision, isTrue);
    store.skipInitialScreening();
    await flush();
    final restarted = createStore()..applySession(session);
    await flush();
    expect(restarted.state.needsInitialScreeningDecision, isFalse);
    restarted.resetForAccount();
    restarted.applySession(session);
    await flush();
    expect(restarted.state.needsInitialScreeningDecision, isFalse);
    expect(restarted.state.assessments, isEmpty);
    expect(restarted.state.screeningBundles, isEmpty);
  });

  test(
      'closing registration without answering never replays or creates results',
      () async {
    final session = await store.registerPatientOnline(
        email: 'new@example.test',
        password: 'Synthetic123!',
        displayName: 'New');
    store.applySession(session);
    await flush();
    expect(store.state.needsInitialScreeningDecision, isTrue);
    final restarted = createStore()..applySession(session);
    await flush();
    expect(restarted.state.needsInitialScreeningDecision, isFalse);
    expect(restarted.state.assessments, isEmpty);
    expect(restarted.state.screeningBundles, isEmpty);
  });

  test(
      'only Google HTTP 201 starts registration; existing Google account does not',
      () async {
    final fresh = await store.loginPatientWithGoogle(idToken: 'synthetic');
    store.applySession(fresh);
    await flush();
    expect(store.state.needsInitialScreeningDecision, isTrue);
    store.resetForAccount();
    googleStatus = 200;
    final returning = await store.loginPatientWithGoogle(idToken: 'synthetic');
    store.applySession(returning);
    await flush();
    expect(store.state.needsInitialScreeningDecision, isFalse);
  });

  test('completion remains completed after account switch and token rotation',
      () async {
    final fresh = await store.registerPatientOnline(
        email: 'new@example.test',
        password: 'Synthetic123!',
        displayName: 'New');
    store.applySession(fresh);
    store.completeInitialScreening();
    await store.persistTokenRotation(fresh);
    await flush();
    store.applySession(existing);
    await flush();
    expect(store.state.needsInitialScreeningDecision, isFalse);
    store.applySession(fresh);
    await flush();
    expect(
        store.state.initialScreeningStatus, InitialScreeningStatus.completed);
    expect(store.state.assessments, isEmpty);
  });
}
