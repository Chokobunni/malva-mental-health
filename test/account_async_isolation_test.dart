import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/malva_app.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/web/web_app.dart';

const _a = AuthSession(
    role: UserRole.patient,
    identifier: 'a@synthetic.test',
    displayName: 'A',
    backendUserId: 'a',
    accessToken: 'access-a',
    refreshToken: 'refresh-a');
const _b = AuthSession(
    role: UserRole.patient,
    identifier: 'b@synthetic.test',
    displayName: 'B',
    backendUserId: 'b',
    accessToken: 'access-b',
    refreshToken: 'refresh-b');

class _Storage implements SecureStore {
  final values = <String, String>{};
  Future<void> Function(String key, String value)? beforeWrite;
  Future<String?> Function(String key, String? value)? readOverride;
  @override
  Future<String?> read(String key) async =>
      readOverride == null ? values[key] : readOverride!(key, values[key]);
  @override
  Future<void> write(String key, String value) async {
    await beforeWrite?.call(key, value);
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _Client extends http.BaseClient {
  _Client(this.handler);
  final Future<http.Response> Function(http.BaseRequest) handler;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await handler(request);
    return http.StreamedResponse(
        Stream.value(response.bodyBytes), response.statusCode,
        headers: {'content-type': 'application/json'});
  }
}

http.Response _json(Object value) => http.Response(jsonEncode(value), 200);
http.Response _refreshedA() => _json({
      'user': {
        'id': 'a',
        'email': 'a@synthetic.test',
        'role': 'patient',
        'display_name': 'A'
      },
      'access_token': 'access-a-rotated',
      'refresh_token': 'refresh-a-rotated'
    });
http.Response _meds(String id) => _json({
      'medications': [
        {
          'id': id,
          'name': 'Synthetic',
          'dosage': '1',
          'form': 'Tablet',
          'reminder_time': '08:00',
          'current_stock': 1,
          'alert_below': 0,
          'source': 'manual'
        }
      ]
    });

Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
      'same-account token refresh does not discard an in-flight medication hydration',
      () async {
    final lateMeds = Completer<http.Response>();
    final started = Completer<void>();
    final api = MalvaApiClient(
        baseUrl: 'http://synthetic.test',
        httpClient: _Client((request) async {
          if (request.url.path == '/v1/auth/refresh') return _refreshedA();
          if (request.url.path == '/v1/medications') {
            if (!started.isCompleted) started.complete();
            return lateMeds.future;
          }
          return _json({});
        }));
    final store = MalvaStoreNotifier(api, null, secureStore: _Storage());
    addTearDown(store.dispose);
    store.applySession(_a);
    await started.future;
    await store.refreshSessionOnline('refresh-a');
    lateMeds.complete(_meds('med-a'));
    await pumpEventQueue();
    expect(store.state.medications.map((m) => m.id), ['med-a']);
  });

  for (final web in [false, true]) {
    for (final logout in [false, true]) {
      testWidgets(
          '${web ? 'web' : 'mobile'} slow initial session read cannot overwrite ${logout ? 'logout' : 'a newer B login'}',
          (tester) async {
        final readStarted = Completer<void>();
        final releaseRead = Completer<void>();
        final storage = _Storage();
        final api = MalvaApiClient(
            baseUrl: 'http://synthetic.test',
            httpClient: _Client((_) async => _json({})));
        final container = ProviderContainer(overrides: [
          apiClientProvider.overrideWithValue(api),
          secureStoreProvider.overrideWithValue(storage),
          capabilitiesProvider.overrideWithValue(const PlatformCapabilities(
              canScheduleOsReminders: false,
              canRegisterPush: false,
              canExportFiles: false,
              canDialTel: false,
              canPickFiles: false,
              canGeolocate: false,
              canBindGoogleCalendar: false,
              isWebBuild: false))
        ]);
        final store = container.read(malvaStoreProvider.notifier);
        await store.persistSession(_a);
        storage.readOverride = (key, value) async {
          if (key == 'malva_active_session') {
            if (!readStarted.isCompleted) readStarted.complete();
            await releaseRead.future;
          }
          return value;
        };
        await tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: web ? const MalvaWebApp() : const MalvaApp()));
        await _flush(tester);
        expect(readStarted.isCompleted, isTrue);
        if (logout) {
          await store.clearSession();
          container.read(authStateProvider.notifier).clearSession();
        } else {
          store.applySession(_b);
          await store.persistSession(_b);
          container.read(authStateProvider.notifier).setSession(_b);
        }
        releaseRead.complete();
        await _flush(tester);
        expect(container.read(authStateProvider).session?.backendUserId,
            logout ? isNull : 'b');
        storage.readOverride = null;
        expect((await store.restoreSession())?.backendUserId,
            logout ? isNull : 'b');
        await tester.pumpWidget(const SizedBox());
        container.dispose();
        await tester.pump(const Duration(seconds: 2));
      });
    }

    testWidgets(
        '${web ? 'web' : 'mobile'} preexisting B auth wins over stored A',
        (tester) async {
      final storage = _Storage();
      final api = MalvaApiClient(
          baseUrl: 'http://synthetic.test',
          httpClient: _Client((_) async => _json({})));
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(api),
        secureStoreProvider.overrideWithValue(storage),
        capabilitiesProvider.overrideWithValue(const PlatformCapabilities(
            canScheduleOsReminders: false,
            canRegisterPush: false,
            canExportFiles: false,
            canDialTel: false,
            canPickFiles: false,
            canGeolocate: false,
            canBindGoogleCalendar: false,
            isWebBuild: false)),
      ]);
      final store = container.read(malvaStoreProvider.notifier);
      await store.persistSession(_a);
      store.applySession(_b);
      container.read(authStateProvider.notifier).setSession(_b);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: web ? const MalvaWebApp() : const MalvaApp()));
      await _flush(tester);
      expect(container.read(authStateProvider).session?.backendUserId, 'b');
      expect(container.read(malvaStoreProvider).patient.id, 'b');
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.pump(const Duration(seconds: 2));
    });
  }

  test('late account A medications cannot populate account B', () async {
    final lateA = Completer<http.Response>();
    var startedA = false;
    final api = MalvaApiClient(
        baseUrl: 'http://synthetic.test',
        httpClient: _Client((request) async {
          if (request.url.path == '/v1/medications') {
            if (request.headers['Authorization'] == 'Bearer access-a') {
              startedA = true;
              return lateA.future;
            }
            return _meds('med-b');
          }
          return _json({});
        }));
    final store = MalvaStoreNotifier(api, null, secureStore: _Storage());
    addTearDown(store.dispose);
    store.applySession(_a);
    await pumpEventQueue();
    expect(startedA, isTrue);
    store.applySession(_b);
    await pumpEventQueue();
    expect(store.state.medications.map((m) => m.id), ['med-b']);
    lateA.complete(_meds('med-a'));
    await pumpEventQueue();
    expect(store.state.patient.id, 'b');
    expect(store.state.medications.map((m) => m.id), ['med-b']);
  });

  for (final logout in [false, true]) {
    test('late refresh cannot persist A after ${logout ? 'logout' : 'B login'}',
        () async {
      final lateA = Completer<http.Response>();
      final storage = _Storage();
      final api = MalvaApiClient(
          baseUrl: 'http://synthetic.test',
          httpClient: _Client((request) async =>
              request.url.path == '/v1/auth/refresh'
                  ? lateA.future
                  : _json({})));
      final store = MalvaStoreNotifier(api, null, secureStore: storage);
      addTearDown(store.dispose);
      store.applySession(_a);
      await store.persistSession(_a);
      final refresh = store.refreshSessionOnline('refresh-a');
      final rejected = expectLater(refresh, throwsA(isA<AuthFailure>()));
      await pumpEventQueue();
      if (logout) {
        store.resetForAccount();
        await store.clearSession();
      } else {
        store.applySession(_b);
        await store.persistSession(_b);
      }
      lateA.complete(_refreshedA());
      await rejected;
      final saved = await store.restoreSession();
      expect(saved?.backendUserId, logout ? isNull : 'b');
    });
  }

  for (final web in [false, true]) {
    testWidgets(
        '${web ? 'web' : 'mobile'} restored refresh cannot replace B auth session',
        (tester) async {
      final lateA = Completer<http.Response>();
      var refreshStarted = false;
      final storage = _Storage();
      final api = MalvaApiClient(
          baseUrl: 'http://synthetic.test',
          httpClient: _Client((request) async {
            if (request.url.path == '/v1/auth/refresh') {
              refreshStarted = true;
              return lateA.future;
            }
            return _json({});
          }));
      final container = ProviderContainer(overrides: [
        apiClientProvider.overrideWithValue(api),
        secureStoreProvider.overrideWithValue(storage),
        capabilitiesProvider.overrideWithValue(const PlatformCapabilities(
            canScheduleOsReminders: false,
            canRegisterPush: false,
            canExportFiles: false,
            canDialTel: false,
            canPickFiles: false,
            canGeolocate: false,
            canBindGoogleCalendar: false,
            isWebBuild: false)),
      ]);
      final store = container.read(malvaStoreProvider.notifier);
      await store.persistSession(_a);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: web ? const MalvaWebApp() : const MalvaApp()));
      await _flush(tester);
      expect(refreshStarted, isTrue);
      store.applySession(_b);
      await store.persistSession(_b);
      container.read(authStateProvider.notifier).setSession(_b);
      lateA.complete(_refreshedA());
      await _flush(tester);
      expect(container.read(authStateProvider).session?.backendUserId, 'b');
      expect((await store.restoreSession())?.backendUserId, 'b');
      await tester.pumpWidget(const SizedBox());
      container.dispose();
      await tester.pump(const Duration(seconds: 2));
    });
  }

  test(
      'an already-started refresh storage write cannot finish after B session storage',
      () async {
    final writeStarted = Completer<void>();
    final releaseWrite = Completer<void>();
    final storage = _Storage();
    final api = MalvaApiClient(
        baseUrl: 'http://synthetic.test',
        httpClient: _Client((request) async =>
            request.url.path == '/v1/auth/refresh'
                ? _refreshedA()
                : _json({})));
    final store = MalvaStoreNotifier(api, null, secureStore: storage);
    addTearDown(store.dispose);
    store.applySession(_a);
    await store.persistSession(_a);
    storage.beforeWrite = (key, value) async {
      if (key == 'malva_active_session' && value.contains('access-a-rotated')) {
        writeStarted.complete();
        await releaseWrite.future;
      }
    };
    final refresh = store.refreshSessionOnline('refresh-a');
    final rejected = expectLater(refresh, throwsA(isA<AuthFailure>()));
    await writeStarted.future;
    store.applySession(_b);
    final savedB = store.persistSession(_b);
    await pumpEventQueue();
    releaseWrite.complete();
    await Future.wait([rejected, savedB]);
    expect((await store.restoreSession())?.backendUserId, 'b');
  });
}
