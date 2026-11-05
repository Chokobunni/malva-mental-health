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
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/web/web_app.dart';

const _a = AuthSession(
    role: UserRole.patient,
    identifier: 'a@example.test',
    displayName: 'A',
    backendUserId: 'a',
    accessToken: 'expired-a',
    refreshToken: 'refresh-a',
    backendSynced: true);
const _b = AuthSession(
    role: UserRole.patient,
    identifier: 'b@example.test',
    displayName: 'B',
    backendUserId: 'b',
    accessToken: 'access-b',
    refreshToken: 'refresh-b',
    backendSynced: true);

class _Storage implements SecureStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

http.Response _json(Object value, [int status = 200]) =>
    http.Response(jsonEncode(value), status,
        headers: {'content-type': 'application/json'});
http.Response _rotation() => _json({
      'user': {
        'id': 'unexpected',
        'email': 'ignored@example.test',
        'role': 'admin',
        'display_name': 'Ignored'
      },
      'access_token': 'fresh-a',
      'refresh_token': 'rotated-a'
    });
Future<void> _flush(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump();
  }
}

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
      'web logout rejects an in-flight refresh before slow server revoke finishes',
      (tester) async {
    final storage = _Storage();
    final pending = Completer<http.Response>();
    final revoke = Completer<http.Response>();
    var refreshing = false;
    var revoking = false;
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/auth/refresh') {
            refreshing = true;
            return pending.future;
          }
          if (request.url.path == '/v1/auth/logout') {
            revoking = true;
            return revoke.future;
          }
          if (request.url.path == '/v1/bookings')
            return request.headers['authorization'] == 'Bearer fresh-a'
                ? _json({'bookings': []})
                : _json({'error': 'unauthorized'}, 401);
          return _json({});
        }));
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(api),
      secureStoreProvider.overrideWithValue(storage)
    ]);
    final store = container.read(malvaStoreProvider.notifier);
    store.applySession(_a);
    await store.persistSession(_a);
    container.read(authStateProvider.notifier).setSession(_a);
    api.setRefreshToken(_a.refreshToken);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container, child: const MalvaWebApp()));
    await _flush(tester);
    final operation = api.listBookings(accessToken: _a.accessToken!);
    final rejected = expectLater(operation, throwsA(isA<MalvaApiException>()));
    await _flush(tester);
    expect(refreshing, isTrue);
    await tester.tap(find.byTooltip('Keluar').first);
    await _flush(tester);
    expect(revoking, isTrue);
    pending.complete(_rotation());
    await _flush(tester);
    await rejected;
    expect(container.read(authStateProvider).session, isNull);
    expect(await store.restoreSession(), isNull);
    revoke.complete(_json({}));
    await _flush(tester);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump(const Duration(seconds: 2));
  });
  for (final web in [false, true]) {
    for (final switchAccount in [false, true]) {
      testWidgets(
          '${web ? 'web' : 'mobile'} API refresh ${switchAccount ? 'cannot overwrite a different account' : 'persists rotated credentials without clearing profile'}',
          (tester) async {
        final storage = _Storage();
        final pending = Completer<http.Response>();
        final started = Completer<void>();
        final api = MalvaApiClient(
            baseUrl: 'http://backend.test',
            httpClient: MockClient((request) async {
              if (request.url.path == '/v1/auth/refresh') {
                if (!started.isCompleted) started.complete();
                return pending.future;
              }
              if (request.url.path == '/v1/bookings')
                return request.headers['authorization'] == 'Bearer fresh-a'
                    ? _json({'bookings': []})
                    : _json({'error': 'unauthorized'}, 401);
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
              isWebBuild: false))
        ]);
        final store = container.read(malvaStoreProvider.notifier);
        store.applySession(_a);
        await store.persistSession(_a);
        store.setPatientIdentity(name: 'Profile kept');
        container.read(authStateProvider.notifier).setSession(_a);
        api.setRefreshToken(_a.refreshToken);
        final previous = api.onTokenRefreshed;
        await tester.pumpWidget(UncontrolledProviderScope(
            container: container,
            child: web ? const MalvaWebApp() : const MalvaApp()));
        final operation = api.listBookings(accessToken: _a.accessToken!);
        Future<void>? rejected;
        if (switchAccount)
          rejected = expectLater(operation, throwsA(isA<MalvaApiException>()));
        await _flush(tester);
        expect(started.isCompleted, isTrue);
        if (switchAccount) {
          store.applySession(_b);
          await store.persistSession(_b);
          container.read(authStateProvider.notifier).setSession(_b);
          api.setRefreshToken(_b.refreshToken);
        }
        pending.complete(_rotation());
        await _flush(tester);
        if (switchAccount) {
          await rejected;
        } else {
          await operation;
        }
        final current = container.read(authStateProvider).session!;
        expect(current.backendUserId, switchAccount ? 'b' : 'a');
        expect(current.role, UserRole.patient);
        expect(
            current.identifier, switchAccount ? _b.identifier : _a.identifier);
        expect(current.displayName, switchAccount ? 'B' : 'A');
        expect(current.backendSynced, isTrue);
        expect(current.accessToken, switchAccount ? 'access-b' : 'fresh-a');
        expect(current.refreshToken, switchAccount ? 'refresh-b' : 'rotated-a');
        if (!switchAccount)
          expect(
              container.read(malvaStoreProvider).patient.name, 'Profile kept');
        final restarted = MalvaStoreNotifier(null, null, secureStore: storage);
        final restored = await restarted.restoreSession();
        restarted.dispose();
        expect(restored?.accessToken, current.accessToken);
        expect(restored?.refreshToken, current.refreshToken);
        expect(restored?.backendUserId, current.backendUserId);
        await tester.pumpWidget(const SizedBox());
        expect(api.onTokenRefreshed, same(previous));
        container.dispose();
        await tester.pump(const Duration(seconds: 2));
      });
    }
  }
}
