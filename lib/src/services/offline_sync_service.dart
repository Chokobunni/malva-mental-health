import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../assessment_engine.dart';
import '../models.dart';
import 'malva_api_client.dart';
import 'server_clock.dart';

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
    this.userId,
  });

  final String id;
  final SyncOperation operation;
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final SyncStatus status;
  final int retryCount;
  final String? lastError;

  /// Pemilik item (backend user id). Antrean bersifat per akun: item milik
  /// akun lain tidak pernah dikirim, sehingga berganti akun di perangkat yang
  /// sama tidak lagi mengunggah data pribadi ke akun yang salah.
  final String? userId;

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
      userId: userId,
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
        'userId': userId,
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
      userId: json['userId']?.toString(),
    );
  }
}

// ============================================================
// OFFLINE SYNC SERVICE
// ============================================================

class OfflineSyncService {
  OfflineSyncService({
    required this.apiClient,
    String? Function()? accessTokenReader,
    String? Function()? activeUserIdReader,
  })  : _readAccessToken = accessTokenReader,
        _readActiveUserId = activeUserIdReader;

  final MalvaApiClient apiClient;

  /// Membaca access token aktif saat dibutuhkan — bukan disalin sekali saat
  /// service dibuat — supaya token hasil refresh langsung terpakai.
  final String? Function()? _readAccessToken;

  /// Membaca id pemilik antrean yang sedang login.
  final String? Function()? _readActiveUserId;

  final _queueController = StreamController<List<SyncItem>>.broadcast();
  final _secureStorage = const FlutterSecureStorage();
  static const _queueKey = 'malva_sync_queue';

  List<SyncItem> _queue = [];
  Timer? _periodicSyncTimer;
  StreamSubscription? _connectivitySub;
  bool _isSyncing = false;

  /// Pemilik antrean saat ini. null berarti belum ada akun yang login.
  String? get _activeUserId {
    final id = _readActiveUserId?.call()?.trim();
    if (id == null || id.isEmpty) return null;
    return id;
  }

  /// Antrean yang terlihat pengguna: hanya milik akun yang sedang aktif.
  List<SyncItem> get queue {
    final owner = _activeUserId;
    if (owner == null) return const [];
    return List.unmodifiable(_queue.where((item) => item.userId == owner));
  }

  Stream<List<SyncItem>> get queueStream => _queueController.stream;
  bool get isSyncing => _isSyncing;

  int get pendingCount =>
      queue.where((item) => item.status == SyncStatus.pending).length;

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
      userId: _activeUserId,
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
      userId: _activeUserId,
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
        // Waktu minum memakai acuan SERVER, bukan jam perangkat: log yang
        // dikirim belakangan tetap tercatat pada jam yang benar, dan "hari
        // ini" tidak bergeser bila jam perangkat meleset.
        'taken_at': ServerClock.now().toIso8601String(),
      },
      createdAt: DateTime.now(),
      userId: _activeUserId,
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
      userId: _activeUserId,
    );
    await _addItem(item);
  }

  // ----------------------------------------------------------
  // SYNC EXECUTION
  // ----------------------------------------------------------

  Future<void> syncNow({String? accessToken}) async {
    if (_isSyncing) return;

    final owner = _activeUserId;
    final token = accessToken ?? _readAccessToken?.call();

    // Tanpa akun aktif atau tanpa token, antrean tidak boleh disentuh sama
    // sekali. Sebelumnya timer periodik memanggil syncNow() tanpa token,
    // setiap item langsung gagal, jatah retry habis, lalu item ditandai
    // 'failed' permanen — data pengguna hilang hanya karena aplikasi dibuka
    // dalam keadaan belum login.
    if (owner == null || token == null || token.isEmpty) return;

    _isSyncing = true;
    _notifyQueue();

    // Hanya item milik akun yang sedang login. Item akun lain (mis. sisa
    // sebelum logout) tetap disimpan dan baru dikirim saat akunnya kembali
    // login, sehingga tidak pernah terunggah ke akun yang salah.
    final pending = _queue
        .where(
            (item) => item.status == SyncStatus.pending && item.userId == owner)
        .toList();

    for (final item in pending) {
      if (!item.canRetry) {
        _updateItem(item.copyWith(status: SyncStatus.failed));
        continue;
      }

      _updateItem(item.copyWith(status: SyncStatus.inProgress));

      try {
        // WAJIB token hasil resolusi, bukan parameter mentah: pemanggil dari
        // timer/connectivity tidak mengirim accessToken, sehingga dulu setiap
        // item langsung gagal dengan "No access token available".
        await _executeItem(item, token);
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
        // Harus sama dengan jalur online (diary_history_screen):
        //   - sharedWithProfessionals:true — entri yang ditulis online
        //     dibagikan ke profesional, jadi entri yang ditulis offline tidak
        //     boleh berperilaku lain. Dulu di sini `false`, sehingga pasien
        //     mengira tulisannya sampai ke terapis padahal tidak.
        //   - occurredAt diambil dari waktu tulis asli (created_at saat masuk
        //     antrean). Tanpa ini, entri hasil sinkronisasi tercap dengan jam
        //     server dan linimasa mood pasien bergeser.
        final occurredAt = DateTime.tryParse(
          (item.payload['created_at'] as String?) ?? '',
        );
        await apiClient.createDiaryEntry(
          accessToken: accessToken,
          mood: item.payload['mood'] as String,
          title: item.payload['title'] as String,
          note: item.payload['note'] as String,
          sharedWithProfessionals: true,
          occurredAt: occurredAt ?? item.createdAt,
        );
    }
  }

  // ----------------------------------------------------------
  // INTERNAL HELPERS
  // ----------------------------------------------------------

  Future<void> _addItem(SyncItem item) async {
    // Item tanpa pemilik tidak akan pernah bisa dikirim (lihat syncNow), jadi
    // jangan pernah dimasukkan ke antrean: data tetap tersimpan di store lokal,
    // dan antrean tidak dipenuhi sampah yang mustahil dikirim.
    if (item.userId == null) return;

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
    _periodicSyncTimer = Timer.periodic(const Duration(minutes: 5), (_) async {
      if (pendingCount == 0) return;
      // Perangkat offline bukan kegagalan permanen: jangan panggil syncNow
      // (yang akan menambah retryCount) saat tidak ada koneksi, supaya jatah
      // retry tidak habis hanya karena aplikasi lama terbuka tanpa internet.
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) return;
      unawaited(syncNow());
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
          // Item sisa versi sebelumnya tidak punya pemilik, sehingga tidak
          // mungkin dikirim tanpa berisiko masuk ke akun yang salah. Dibuang
          // saat dimuat agar antrean tidak menyimpan data yang mustahil
          // dikirim; salinan lokalnya tetap ada di store perangkat.
          .where((item) => (item.userId ?? '').trim().isNotEmpty)
          .toList();
    } on Object {
      _queue = [];
    }
  }
}
