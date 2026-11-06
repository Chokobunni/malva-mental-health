import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../services/server_clock.dart';
import 'malva_components.dart';
import 'friendly_error.dart';

/// Each participant confirms their own attendance; completion is professional-only.
class SessionAttendanceActions extends ConsumerStatefulWidget {
  const SessionAttendanceActions(
      {super.key,
      required this.session,
      required this.role,
      required this.onChanged,
      this.accessToken,
      this.apiClient});
  final BackendCareSession session;
  final UserRole role;
  final Future<void> Function() onChanged;
  final String? accessToken;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<SessionAttendanceActions> createState() =>
      _SessionAttendanceActionsState();
}

class _SessionAttendanceActionsState
    extends ConsumerState<SessionAttendanceActions> {
  bool _busy = false;

  Future<void> _mark(String status) async {
    if (_busy) return;
    final owner = ref.read(currentSessionProvider);
    bool sameOwner() {
      final current = ref.read(currentSessionProvider);
      return current?.backendUserId == owner?.backendUserId &&
          current?.identifier == owner?.identifier &&
          current?.role == owner?.role;
    }

    final token =
        widget.accessToken ?? ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) return;
    if (status == 'absent') {
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
                title: const Text('Konfirmasi tidak hadir'),
                content: Text(widget.role == UserRole.professional
                    ? 'Sesi dibatalkan dan kuota pasien dikembalikan.'
                    : 'Sesi dicatat tidak hadir dan kuota sesi terpakai.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Kembali')),
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Tidak hadir'))
                ],
              ));
      if (confirmed != true || !mounted || !sameOwner()) return;
    }
    setState(() => _busy = true);
    try {
      final MalvaApiClient api =
          widget.apiClient ?? ref.read(apiClientProvider);
      await api.updateCareSession(
          accessToken: token, sessionId: widget.session.id, status: status);
      if (!mounted || !sameOwner()) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(status == 'attended'
              ? 'Kehadiran dicatat. Sesi tetap berjalan sampai waktu habis.'
              : status == 'completed'
                  ? 'Sesi ditandai selesai.'
                  : 'Ketidakhadiran dicatat.')));
      await widget.onChanged();
    } on Object catch (error) {
      if (mounted && sameOwner()) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final professional = widget.role == UserRole.professional;
    final attendance = professional
        ? session.professionalAttendance
        : session.patientAttendance;
    final start = session.scheduledDateTime;
    final now = ServerClock.now();
    final opened = start != null &&
        !now.isBefore(start.subtract(BackendCareSession.joinOpensBefore));
    final ended = start != null &&
        !now.isBefore(start.add(Duration(minutes: session.durationMinutes)));
    if (!session.isScheduled || !opened) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(
          'Kehadiran saya${attendance.isEmpty ? '' : ': ${attendance == 'attended' ? 'Hadir' : 'Tidak hadir'}'}',
          style: const TextStyle(fontWeight: FontWeight.w700)),
      if (session.isScheduled && opened)
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (attendance.isEmpty) ...[
            OutlinedButton.icon(
                onPressed: _busy ? null : () => _mark('attended'),
                icon: const Icon(Icons.check_rounded, size: 16),
                label: const Text('Hadir')),
            OutlinedButton.icon(
                onPressed: _busy ? null : () => _mark('absent'),
                icon: const Icon(Icons.person_off_rounded, size: 16),
                label: const Text('Tidak hadir')),
          ],
          if (professional && ended)
            FilledButton.icon(
                style: compactFilledButtonStyle,
                onPressed: _busy ? null : () => _mark('completed'),
                icon: const Icon(Icons.task_alt_rounded, size: 16),
                label: const Text('Selesaikan sesi')),
        ]),
    ]);
  }
}
