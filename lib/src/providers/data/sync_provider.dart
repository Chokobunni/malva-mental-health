import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/platform_providers.dart';
import '../../services/offline_sync_service.dart';
import '../auth_providers.dart';
import '../malva_store_provider.dart';

// ============================================================
// OFFLINE SYNC PROVIDERS
// ============================================================

final offlineSyncServiceProvider = Provider<OfflineSyncService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  // Token & pemilik antrean dibaca dari container SAAT DIBUTUHKAN, bukan
  // disalin sekali saat provider dibuat: sesi bisa di-refresh atau diganti
  // akun kapan saja, dan antrean offline tidak boleh memakai token/pemilik
  // yang sudah tidak berlaku.
  final container = ref.container;
  var generation = 0;
  ref.listen(authStateProvider, (before, after) {
    final old = before?.session;
    final next = after.session;
    if (old?.role != next?.role ||
        (old?.backendUserId ?? old?.identifier) !=
            (next?.backendUserId ?? next?.identifier)) generation++;
  });
  final service = OfflineSyncService(
    accountGenerationReader: () => generation,
    onMedicationLogConfirmed: (id, owner, attemptedAt, accepted) {
      if (container.read(authStateProvider).session?.backendUserId == owner) {
        final store = container.read(malvaStoreProvider.notifier);
        store.confirmMedicationLog(id, attemptedAt, accepted);
        unawaited(store.loadMedications());
      }
    },
    apiClient: apiClient,
    accessTokenReader: () =>
        container.read(authStateProvider).session?.accessToken,
    activeUserIdReader: () =>
        container.read(authStateProvider).session?.backendUserId,
    secureStore: ref.watch(secureStoreProvider),
  );
  ref.onDispose(service.dispose);
  return service;
});

final syncQueueProvider =
    StreamNotifierProvider<SyncQueueNotifier, List<SyncItem>>(
        SyncQueueNotifier.new);

class SyncQueueNotifier extends StreamNotifier<List<SyncItem>> {
  @override
  Stream<List<SyncItem>> build() {
    final syncService = ref.read(offlineSyncServiceProvider);
    return syncService.queueStream;
  }

  Future<void> enqueueMood(dynamic entry) =>
      ref.read(offlineSyncServiceProvider).enqueueMood(entry);

  Future<void> enqueueScreening({
    required List<int> phq9Answers,
    required List<int> gad7Answers,
    required bool isInitial,
    required String source,
  }) =>
      ref.read(offlineSyncServiceProvider).enqueueScreening(
            phq9Answers: phq9Answers,
            gad7Answers: gad7Answers,
            isInitial: isInitial,
            source: source,
          );

  Future<void> enqueueMedicationLog({
    required String medicationId,
    required String medicationName,
    required String status,
  }) =>
      ref.read(offlineSyncServiceProvider).enqueueMedicationLog(
            medicationId: medicationId,
            medicationName: medicationName,
            status: status,
          );

  Future<void> enqueueDiary(dynamic entry) =>
      ref.read(offlineSyncServiceProvider).enqueueDiary(entry);
}

final pendingSyncCountProvider = Provider<int>((ref) {
  final syncService = ref.watch(offlineSyncServiceProvider);
  return syncService.pendingCount;
});

final isSyncingProvider = Provider<bool>((ref) {
  final syncService = ref.watch(offlineSyncServiceProvider);
  return syncService.isSyncing;
});

// ============================================================
// CONNECTIVITY PROVIDER
// ============================================================

final connectivityProvider =
    StreamNotifierProvider<ConnectivityNotifier, ConnectivityResult>(
        ConnectivityNotifier.new);

class ConnectivityNotifier extends StreamNotifier<ConnectivityResult> {
  @override
  Stream<ConnectivityResult> build() {
    return Connectivity().onConnectivityChanged.map((results) {
      return results.isNotEmpty ? results.first : ConnectivityResult.none;
    });
  }
}

final isOnlineProvider = Provider<bool>((ref) {
  final connectivity = ref.watch(connectivityProvider);
  return connectivity != ConnectivityResult.none;
});
