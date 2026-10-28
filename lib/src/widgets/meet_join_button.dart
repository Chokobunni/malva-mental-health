import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/auth_providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import 'friendly_error.dart';

/// Tombol gabung sesi video berbasis Google Meet.
///
/// Menangani seluruh keadaan sesi video sehingga pemanggil tidak perlu
/// menduplikasi logika:
///   - link belum ada  -> tombol "Siapkan link Meet" (memanggil backend)
///   - terlalu awal    -> tombol nonaktif + hitung mundur
///   - jendela terbuka -> tombol "Gabung video call" aktif
///   - sesi berakhir   -> tombol nonaktif
///
/// Tidak ada penyedia fallback: bila link tidak bisa dibuat, pengguna melihat
/// pesan kesalahan yang jelas dan dapat mencoba lagi.
class MeetJoinButton extends ConsumerStatefulWidget {
  const MeetJoinButton({
    super.key,
    required this.session,
    required this.accessToken,
    required this.onSessionChanged,
    this.expanded = false,
  });

  final BackendCareSession session;
  final String accessToken;

  /// Dipanggil setelah link berhasil dibuat agar pemanggil menyegarkan data.
  final ValueChanged<BackendCareSession> onSessionChanged;

  /// True = tombol melebar penuh (dipakai di kartu detail sesi).
  final bool expanded;

  @override
  ConsumerState<MeetJoinButton> createState() => _MeetJoinButtonState();
}

class _MeetJoinButtonState extends ConsumerState<MeetJoinButton> {
  bool _busy = false;
  String? _error;

  bool get _hasLink => widget.session.meetingUrl.trim().isNotEmpty;

  Future<void> _createLink() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await ref.read(apiClientProvider).ensureMeetLink(
            accessToken: widget.accessToken,
            sessionId: widget.session.id,
          );
      widget.onSessionChanged(updated);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final url = widget.session.meetingUrl.trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) {
      setState(() => _error = 'Link video call tidak valid.');
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      setState(() => _error = 'Tidak dapat membuka Google Meet.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    if (!session.isVideo) return const SizedBox.shrink();
    if (!session.isScheduled) return const SizedBox.shrink();

    final children = <Widget>[
      if (_error != null) ...[
        Text(
          _error!,
          style: const TextStyle(fontSize: 12, color: MalvaColors.danger),
        ),
        const SizedBox(height: 8),
      ],
      _buildAction(context, session),
    ];

    if (!widget.expanded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: children,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  Widget _buildAction(BuildContext context, BackendCareSession session) {
    if (!_hasLink) {
      return FilledButton.icon(
        onPressed: _busy ? null : _createLink,
        icon: _busy
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.video_call_rounded, size: 18),
        label: Text(_busy ? 'Menyiapkan link...' : 'Siapkan link Meet'),
        style: FilledButton.styleFrom(
          backgroundColor: MalvaColors.plum,
          foregroundColor: Colors.white,
        ),
      );
    }
    if (session.isAfterJoinWindow) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.event_busy_rounded, size: 18),
        label: const Text('Sesi berakhir'),
      );
    }
    if (session.isBeforeJoinWindow) {
      return OutlinedButton.icon(
        onPressed: null,
        icon: const Icon(Icons.schedule_rounded, size: 18),
        label: Text(session.joinStateLabel),
      );
    }
    return FilledButton.icon(
      onPressed: _join,
      icon: const Icon(Icons.videocam_rounded, size: 18),
      label: const Text('Gabung video call'),
      style: FilledButton.styleFrom(
        backgroundColor: MalvaColors.mint,
        foregroundColor: Colors.white,
      ),
    );
  }
}
