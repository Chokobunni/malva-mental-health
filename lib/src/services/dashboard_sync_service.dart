import 'dart:async';

enum SyncStatus { idle, syncing, error }

class DashboardSyncEvent {
  const DashboardSyncEvent({
    required this.status,
    this.lastSyncTime,
    this.errorMessage,
  });

  final SyncStatus status;
  final DateTime? lastSyncTime;
  final String? errorMessage;
}

class DashboardSyncService {
  DashboardSyncService({Duration interval = const Duration(seconds: 30)})
      : _interval = interval;

  final Duration _interval;
  Timer? _timer;
  final StreamController<DashboardSyncEvent> _controller =
      StreamController<DashboardSyncEvent>.broadcast();

  DateTime? _lastSyncTime;
  SyncStatus _status = SyncStatus.idle;
  bool _isActive = false;
  Future<void> Function()? _onRefresh;

  Stream<DashboardSyncEvent> get stream => _controller.stream;
  DateTime? get lastSyncTime => _lastSyncTime;
  SyncStatus get status => _status;

  String? get lastSyncAgo {
    final last = _lastSyncTime;
    if (last == null) return null;
    final diff = DateTime.now().difference(last);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void setOnRefresh(Future<void> Function() callback) {
    _onRefresh = callback;
  }

  void startSync() {
    if (_timer?.isActive == true) return;
    _isActive = true;
    _timer = Timer.periodic(_interval, (_) => _performSync());
  }

  void stopSync() {
    _isActive = false;
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    stopSync();
    _controller.close();
  }

  Future<void> refreshNow() async {
    await _performSync();
  }

  Future<void> _performSync() async {
    if (!_isActive || _onRefresh == null) return;

    _status = SyncStatus.syncing;
    _emitEvent();

    try {
      await _onRefresh!();
      _lastSyncTime = DateTime.now();
      _status = SyncStatus.idle;
    } on Object catch (error) {
      _status = SyncStatus.error;
      _controller.add(DashboardSyncEvent(
        status: SyncStatus.error,
        lastSyncTime: _lastSyncTime,
        errorMessage: error.toString(),
      ));
      return;
    }

    _emitEvent();
  }

  void _emitEvent() {
    if (_controller.isClosed) return;
    _controller.add(DashboardSyncEvent(
      status: _status,
      lastSyncTime: _lastSyncTime,
      errorMessage: _status == SyncStatus.error ? 'Sync failed' : null,
    ));
  }
}
