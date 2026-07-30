import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../assessment_engine.dart';
import '../models.dart';
import 'malva_api_client.dart';

// ============================================================
// OFFLINE SYNC QUEUE MODELS
// ============================================================

enum SyncOperation { moodEntry, screeningBundle, medicationLog, diaryEntry }

enum SyncStatus { pending, inProgress, completed, failed }

class SyncItem {
  const SyncItem({
    required this.id,
    required this.operation,
    required this.payload,
    required this.createdAt,
    this.status = SyncStatus.pending,
    this.retryCount = 0,
    this.lastError,
  });

  final String id;
  final SyncOperation operation;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final SyncStatus status;
  final int retryCount;
  final String? lastError;

  static const int maxRetries = 3;

  bool get canRetry => retryCount < maxRetries;

  SyncItem copyWith({
    SyncStatus? status,
    int? retryCount,
    String? lastError,
  }) {
    return SyncItem(
      id: id,
      operation: operation,
      payload: payload,
      createdAt: createdAt,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'operation': operation.name,
        'payload': payload,
        'createdAt': createdAt.toIso8601String(),
        'status': status.name,
        'retryCount': retryCount,
        'lastError': lastError,
      };

  factory SyncItem.fromJson(Map<String, dynamic> json) {
    return SyncItem(
      id: json['id']?.toString() ?? '',
      operation: SyncOperation.values.firstWhere(
        (e) => e.name == json['operation'],
        orElse: () => SyncOperation.moodEntry,
      ),
      payload: Map<String, dynamic>.from(json['payload'] as Map? ?? {}),
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      status: SyncStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => SyncStatus.pending,
      ),
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      lastError: json['lastError']?.toString(),
    );
  }
}

// ============================================================
// OFFLINE SYNC SERVICE
// ============================================================

class OfflineSyncService {
  OfflineSyncService({required this.apiClient});

  final MalvaApiClient apiClient;
  final _queueController = StreamController<List<SyncItem>>.broadcast();
  final _secureStorage = const FlutterSecureStorage();
  static const _queueKey = 'malva_sync_queue';

  List<SyncItem> _queue = [];
  Timer? _periodicSyncTimer;
  StreamSubscription? _connectivitySub;
  bool _isSyncing = false;

  List<SyncItem> get queue => List.unmodifiable(_queue);
  Stream<List<SyncItem>> get queueStream => _queueController.stream;
  bool get isSyncing => _isSyncing;

  int get pendingCount =>
      _queue.where((item) => item.status == SyncStatus.pending).length;

  // ----------------------------------------------------------
  // INITIALIZATION
  // ----------------------------------------------------------

  Future<void> initialize() async {
    await _loadQueue();
    _startPeriodicSync();
    _listenConnectivity();
  }

  void dispose() {
    _periodicSyncTimer?.cancel();
    _connectivitySub?.cancel();
    _queueController.close();
  }

  // ----------------------------------------------------------
  // QUEUE OPERATIONS
  // ----------------------------------------------------------

  Future<void> enqueueMood(MoodEntry entry) async {
    final item = SyncItem(
      id: 'sync_mood_${DateTime.now().millisecondsSinceEpoch}',
      operation: SyncOperation.moodEntry,
      payload: {
        'date': entry.date.toIso8601String(),
        'mood': entry.mood.name,
        'sleepHours': entry.sleepHours,
        'energy': entry.energy,
        'anxiety': entry.anxiety,
        'irritability': entry.irritability,
        'note': entry.note,
      },
      createdAt: DateTime.now(),
    );
    await _addItem(item);
  }

  Future<void> enqueueScreening({
    required List<int> phq9Answers,
    required List<int> gad7Answers,
    required bool isInitial,
    required String source,
  }) async {
    final item = SyncItem(
      id: 'sync_screening_${DateTime.now().millisecondsSinceEpoch}',
      operation: SyncOperation.screeningBundle,
      payload: {
        'phq9': phq9Answers,
        'gad7': gad7Answers,
        'isInitial': isInitial,
        'source': source,
      },
      createdAt: DateTime.now(),
    );
    await _addItem(item);
  }

  Future<void> enqueueMedicationLog({
    required String medicationId,
    required String medicationName,
    required String status,
  }) async {
    final item = SyncItem(
      id: 'sync_medlog_${DateTime.now().millisecondsSinceEpoch}',
      operation: SyncOperation.medicationLog,
      payload: {
        'medication_id': medicationId,
        'medication_name': medicationName,
        'status': status,
        'taken_at': DateTime.now().toIso8601String(),
      },
      createdAt: DateTime.now(),
    );
    await _addItem(item);
  }

  Future<void> enqueueDiary(DiaryEntry entry) async {
    final item = SyncItem(
      id: 'sync_diary_${DateTime.now().millisecondsSinceEpoch}',
      operation: SyncOperation.diaryEntry,
      payload: {
        'id': entry.id,
        'mood': entry.mood.name,
        'title': entry.title,
        'note': entry.note,
        'created_at': entry.createdAt.toIso8601String(),
      },
      createdAt: DateTime.now(),
    );
    await _addItem(item);
  }

  // ----------------------------------------------------------
  // SYNC EXECUTION
  // ----------------------------------------------------------

  Future<void> syncNow({String? accessToken}) async {
    if (_isSyncing) return;
    _isSyncing = true;
    _notifyQueue();

    final pending =
        _queue.where((item) => item.status == SyncStatus.pending).toList();

    for (final item in pending) {
      if (!item.canRetry) {
        _updateItem(item.copyWith(status: SyncStatus.failed));
        continue;
      }

      _updateItem(item.copyWith(status: SyncStatus.inProgress));

      try {
        await _executeItem(item, accessToken);
        _updateItem(item.copyWith(status: SyncStatus.completed));
      } catch (e) {
        _updateItem(item.copyWith(
          status: SyncStatus.pending,
          retryCount: item.retryCount + 1,
          lastError: e.toString(),
        ));
      }
    }

    // Remove completed items older than 24h
    final now = DateTime.now();
    _queue.removeWhere((item) =>
        item.status == SyncStatus.completed &&
        now.difference(item.createdAt).inHours > 24);

    await _saveQueue();
    _isSyncing = false;
    _notifyQueue();
  }

  Future<void> _executeItem(SyncItem item, String? accessToken) async {
    if (accessToken == null || accessToken.isEmpty) {
      throw Exception('No access token available for sync');
    }

    switch (item.operation) {
      case SyncOperation.moodEntry:
        await apiClient.createMoodCheckin(
          accessToken: accessToken,
          mood: item.payload['mood'] as String,
          sleepHours: (item.payload['sleepHours'] as num).toDouble(),
          energy: (item.payload['energy'] as num).toInt(),
          anxiety: (item.payload['anxiety'] as num).toInt(),
          irritability: (item.payload['irritability'] as num).toInt(),
          note: item.payload['note'] as String,
          occurredAt: DateTime.parse(item.payload['date'] as String),
        );
      case SyncOperation.screeningBundle:
        await apiClient.submitScreening(
          accessToken: accessToken,
          bundle: ScreeningBundle(
            id: '',
            phq9: AssessmentResult(
              type: AssessmentType.phq9,
              score: 0,
              maxScore: 27,
              level: RiskLevel.minimal,
              summary: '',
              crisisFlag: false,
              rulesFired: const [],
              createdAt: DateTime.now(),
              ruleVersion: 'offline-queue',
            ),
            gad7: AssessmentResult(
              type: AssessmentType.gad7,
              score: 0,
              maxScore: 21,
              level: RiskLevel.minimal,
              summary: '',
              crisisFlag: false,
              rulesFired: const [],
              createdAt: DateTime.now(),
              ruleVersion: 'offline-queue',
            ),
            createdAt: DateTime.now(),
            isInitial: item.payload['isInitial'] as bool,
            source: item.payload['source'] as String,
          ),
          phq9Answers: List<int>.from(item.payload['phq9'] as List),
          gad7Answers: List<int>.from(item.payload['gad7'] as List),
        );
      case SyncOperation.medicationLog:
        await apiClient.createMedicationLog(
          accessToken: accessToken,
          medicationId: item.payload['medication_id'] as String,
          medicationName: item.payload['medication_name'] as String,
          status: item.payload['status'] as String,
          takenAt: DateTime.parse(item.payload['taken_at'] as String),
        );
      case SyncOperation.diaryEntry:
        await apiClient.createDiaryEntry(
          accessToken: accessToken,
          mood: item.payload['mood'] as String,
          title: item.payload['title'] as String,
          note: item.payload['note'] as String,
          sharedWithProfessionals: false,
        );
    }
  }

  // ----------------------------------------------------------
  // INTERNAL HELPERS
  // ----------------------------------------------------------

  Future<void> _addItem(SyncItem item) async {
    _queue.add(item);
    await _saveQueue();
    _notifyQueue();

    // Try immediate sync if online
    final connectivity = await Connectivity().checkConnectivity();
    if (connectivity != ConnectivityResult.none) {
      unawaited(syncNow());
    }
  }

  void _updateItem(SyncItem updated) {
    final idx = _queue.indexWhere((i) => i.id == updated.id);
    if (idx >= 0) _queue[idx] = updated;
  }

  void _notifyQueue() {
    if (!_queueController.isClosed) {
      _queueController.add(queue);
    }
  }

  void _startPeriodicSync() {
    _periodicSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (pendingCount > 0) {
        unawaited(syncNow());
      }
    });
  }

  void _listenConnectivity() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline && pendingCount > 0) {
        unawaited(syncNow());
      }
    });
  }

  Future<void> _saveQueue() async {
    final data = jsonEncode(_queue.map((i) => i.toJson()).toList());
    await _secureStorage.write(key: _queueKey, value: data);
  }

  Future<void> _loadQueue() async {
    try {
      final data = await _secureStorage.read(key: _queueKey);
      if (data == null || data.isEmpty) return;
      final list = jsonDecode(data) as List;
      _queue = list
          .whereType<Map<String, dynamic>>()
          .map(SyncItem.fromJson)
          .toList();
    } on Object {
      _queue = [];
    }
  }
}
