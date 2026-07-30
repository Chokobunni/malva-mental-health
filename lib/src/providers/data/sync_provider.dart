import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/offline_sync_service.dart';
import '../auth_providers.dart';

// ============================================================
// OFFLINE SYNC PROVIDERS
// ============================================================

final offlineSyncServiceProvider = Provider<OfflineSyncService>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  final service = OfflineSyncService(apiClient: apiClient);
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
