import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/widgets/account_avatar.dart';

class _Storage implements SecureStore {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

void main() {
  test('a delayed avatar read cannot migrate after an account switch',
      () async {
    final storage = _Storage()
      ..values[profileAvatarKey('patient')] = 'assets/reference/avatar-2.png';
    final started = Completer<void>();
    final response = Completer<http.Response>();
    final requests = <String>[];
    final api = MalvaApiClient(httpClient: MockClient((request) async {
      requests.add(request.method);
      started.complete();
      return response.future;
    }));
    final container = ProviderContainer(overrides: [
      secureStoreProvider.overrideWithValue(storage),
      apiClientProvider.overrideWithValue(api),
    ]);
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'patient',
        backendUserId: 'patient',
        displayName: 'Ami',
        accessToken: 'token'));
    container.read(patientAvatarProvider('patient'));
    await started.future;
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'other',
        backendUserId: 'other',
        displayName: 'Other',
        accessToken: 'other-token'));
    response.complete(http.Response('{"avatar":null}', 200));
    await Future<void>.delayed(Duration.zero);
    expect(requests, ['GET']);
    // The replacement generation is safe to read after the stale request ends.
    await container.read(patientAvatarProvider('patient').future);
  });

  for (final remote in [null, 'assets/reference/avatar-3.png']) {
    test('local avatar migrates only when server has no avatar ($remote)',
        () async {
      final storage = _Storage()
        ..values[profileAvatarKey('patient')] = 'assets/reference/avatar-2.png';
      final requests = <http.Request>[];
      final api = MalvaApiClient(httpClient: MockClient((request) async {
        requests.add(request);
        expect(request.headers['authorization'], 'Bearer token');
        return http.Response(
            jsonEncode({
              'avatar': request.method == 'PUT'
                  ? 'assets/reference/avatar-2.png'
                  : remote
            }),
            200);
      }));
      final container = ProviderContainer(overrides: [
        secureStoreProvider.overrideWithValue(storage),
        apiClientProvider.overrideWithValue(api),
      ]);
      addTearDown(container.dispose);
      container.read(authStateProvider.notifier).setSession(const AuthSession(
          role: UserRole.patient,
          identifier: 'patient',
          backendUserId: 'patient',
          displayName: 'Ami',
          accessToken: 'token'));
      expect(await container.read(patientAvatarProvider('patient').future),
          remote ?? 'assets/reference/avatar-2.png');
      expect(requests.map((r) => r.method),
          remote == null ? ['GET', 'PUT'] : ['GET']);
      if (remote == null) expect(requests.last.headers['if-none-match'], '*');
    });
  }
}
