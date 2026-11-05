import 'dart:async';

import 'malva_api_client.dart';
import 'server_clock.dart';

/// Refresh persisted state periodically and rebuild exactly at session borders.
class CareSessionRefresh {
  CareSessionRefresh(this.onRefresh, {bool poll = true}) : _pollEnabled = poll;

  final void Function() onRefresh;
  final bool _pollEnabled;
  Timer? _poll;
  Timer? _boundary;
  List<BackendCareSession> _scheduled = const [];

  void update(Iterable<BackendCareSession> sessions) {
    _scheduled = sessions.where((s) => s.isScheduled).toList();
    if (_pollEnabled && _scheduled.isNotEmpty) {
      _poll ??= Timer.periodic(const Duration(seconds: 30), (_) => onRefresh());
    } else {
      _poll?.cancel();
      _poll = null;
    }
    _armBoundary();
  }

  void _armBoundary({DateTime? after}) {
    _boundary?.cancel();
    final now = ServerClock.now();
    // A fired boundary is already handled, even if a clock adjustment moved
    // the server estimate backwards while the timer was pending.
    final cursor = after != null && after.isAfter(now) ? after : now;
    DateTime? next;
    for (final session in _scheduled) {
      final start = session.scheduledDateTime;
      if (start == null) continue;
      for (final time in [
        start.subtract(BackendCareSession.joinOpensBefore),
        start.add(Duration(minutes: session.durationMinutes)),
      ]) {
        if (time.isAfter(cursor) && (next == null || time.isBefore(next))) {
          next = time;
        }
      }
    }
    if (next != null) {
      final deadline = next;
      _boundary = Timer(deadline.difference(cursor), () {
        // Arm the next cached boundary before a reload can fail or be skipped.
        _armBoundary(after: deadline);
        onRefresh();
      });
    }
  }

  void dispose() {
    _poll?.cancel();
    _boundary?.cancel();
  }
}
