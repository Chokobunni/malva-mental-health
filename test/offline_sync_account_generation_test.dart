import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/offline_sync_service.dart';
import 'package:malva_mental_health/src/time/wib.dart';

class _Storage implements SecureStore {
  String? value;
  bool failWrite = false;
  @override
  Future<String?> read(String key) async => value;
  @override
  Future<void> write(String key, String value) async {
    if (failWrite) throw StateError('storage unavailable');
    this.value = value;
  }

  @override
  Future<void> delete(String key) async => value = null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('dev.fluttercommunity.plus/connectivity'),
            (_) async => ['none']);
  });

  test(
      'account round trip stops an old sync run and durably retains later logs',
      () async {
    final firstStarted = Completer<void>(), releaseFirst = Completer<void>();
    final requests = <String>[], confirmations = <String>[];
    var owner = 'a', generation = 0;
    final storage = _Storage()
      ..value = jsonEncode([
        for (final id in ['first', 'second'])
          SyncItem(
                  id: id,
                  operation: SyncOperation.medicationLog,
                  payload: {
                    'medication_id': id,
                    'medication_name': id,
                    'status': 'taken',
                    'taken_at': '2026-11-10T08:00:00+07:00'
                  },
                  createdAt: wibNow(),
                  userId: 'a')
              .toJson()
      ]);
    final service = OfflineSyncService(
        apiClient: MalvaApiClient(
            baseUrl: 'https://fixture.test',
            httpClient: MockClient((r) async {
              final body = jsonDecode(r.body) as Map<String, dynamic>;
              final id = body['medication_id'] as String;
              requests.add(id);
              if (!firstStarted.isCompleted) {
                firstStarted.complete();
                await releaseFirst.future;
              }
              return http.Response(
                  jsonEncode({
                    'medication_log': {'id': id, ...body}
                  }),
                  200);
            })),
        activeUserIdReader: () => owner,
        accessTokenReader: () => 'token-$owner',
        accountGenerationReader: () => generation,
        onMedicationLogSynced: (id, _) => confirmations.add(id),
        secureStore: storage);
    addTearDown(service.dispose);
    await service.initialize();
    final running = service.syncNow();
    await firstStarted.future;
    owner = 'b';
    generation++;
    owner = 'a';
    generation++;
    releaseFirst.complete();
    await running;
    expect(requests, ['first']);
    expect(confirmations, isEmpty);
    expect(service.isSyncing, isFalse);
    final persisted = (jsonDecode(storage.value!) as List)
        .map((v) => SyncItem.fromJson(Map<String, dynamic>.from(v as Map)))
        .toList();
    expect(persisted.first.status, SyncStatus.completed);
    expect(persisted.last.status, SyncStatus.pending);
    expect(persisted.last.retryCount, 0);
    await service.syncNow();
    expect(requests, ['first', 'second']);
    expect(confirmations, ['second']);
    expect(service.pendingCount, 0);
  });

  test('failed final persistence releases sync lock for a later retry',
      () async {
    final storage = _Storage()..failWrite = true;
    final service = OfflineSyncService(
        apiClient: MalvaApiClient(baseUrl: 'https://fixture.test'),
        activeUserIdReader: () => 'a',
        accessTokenReader: () => 'token',
        secureStore: storage);
    addTearDown(service.dispose);
    await expectLater(service.syncNow(), throwsStateError);
    expect(service.isSyncing, isFalse);
    storage.failWrite = false;
    await service.syncNow();
    expect(storage.value, '[]');
  });
}
