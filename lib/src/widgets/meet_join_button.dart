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
///   - link belum ada, pemanggil boleh membuatnya -> tombol "Buat link Meet"
///   - link belum ada, pemanggil TIDAK boleh membuatnya (pasien) ->
///     keterangan "Menunggu link video"
///   - terlalu awal    -> tombol nonaktif + hitung mundur
///   - jendela terbuka -> tombol "Gabung video call" aktif
///   - sesi berakhir   -> tombol nonaktif
///
/// Tidak ada penyedia fallback: bila link tidak bisa dibuat, pengguna melihat
/// pesan kesalahan yang jelas dan dapat mencoba lagi.
///
/// Catatan aturan bisnis: sesi video BOLEH lahir tanpa link ("menunggu link")
/// ketika akun Google profesional belum aktif. Pasien tidak boleh diberi
/// tombol yang membuka URL kosong, dan tidak boleh disuruh memperbaiki akun
/// Google milik profesional — karena itu [canCreateLink] = false untuk pasien.
class MeetJoinButton extends ConsumerStatefulWidget {
  const MeetJoinButton({
    super.key,
    required this.session,
    required this.accessToken,
    required this.onSessionChanged,
    this.expanded = false,
    this.canCreateLink = true,
  });

  final BackendCareSession session;
  final String accessToken;

  /// Dipanggil setelah link berhasil dibuat agar pemanggil menyegarkan data.
  final ValueChanged<BackendCareSession> onSessionChanged;

  /// True = tombol melebar penuh (dipakai di kartu detail sesi).
  final bool expanded;

  /// True = tampilkan tombol "Buat link Meet" saat link belum ada
  /// (profesional). False = tampilkan keterangan "Menunggu link video"
  /// (pasien) tanpa aksi yang pasti gagal.
  final bool canCreateLink;

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

  /// Fallback manual: profesional menempelkan link Google Meet sendiri ketika
  /// pembuatan otomatis tidak bisa (mis. diblokir access_denied). Validasi
  /// klien disamakan dengan server: wajib https + host meet.google.com.
  Future<void> _pasteMeetLink() async {
    if (_busy) return;
    final controller = TextEditingController();
    final input = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Tempel link Meet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Buat link Google Meet sendiri (mis. dari Google Calendar), lalu '
              'tempel di sini. Pasien akan melihat link ini di detail sesi.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                labelText: 'Link Google Meet',
                hintText: 'https://meet.google.com/abc-defg-hij',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    final url = (input ?? '').trim();
    if (url.isEmpty || !mounted) return;
    final validationError = _validateMeetUrl(url);
    if (validationError != null) {
      setState(() => _error = validationError);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final updated = await ref.read(apiClientProvider).setManualMeetLink(
            accessToken: widget.accessToken,
            sessionId: widget.session.id,
            meetUrl: url,
          );
      widget.onSessionChanged(updated);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Validasi klien link Meet manual. Mengembalikan pesan error Indonesia bila
  /// tidak valid, atau null bila lolos. Sama ketat dengan normalizeManualMeetURL
  /// di server (wajib https, host meet.google.com).
  String? _validateMeetUrl(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length > 500) return 'Link terlalu panjang.';
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return 'Link tidak valid.';
    if (uri.scheme != 'https') return 'Link harus diawali https://';
    if (uri.host.toLowerCase() != 'meet.google.com') {
      return 'Link harus berupa link Google Meet (meet.google.com).';
    }
    if (uri.path.isEmpty || uri.path == '/') {
      return 'Link Google Meet tidak lengkap.';
    }
    return null;
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
      if (!widget.canCreateLink) {
        // Pasien: link dibuat oleh profesional. Jangan tampilkan tombol yang
        // pasti gagal atau membuka URL kosong.
        return const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(Icons.hourglass_top_rounded,
                    size: 18, color: MalvaColors.amber),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Menunggu link video',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              'Link Google Meet dibuat oleh profesional dan akan tersedia '
              'sebelum sesi dimulai.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FilledButton.icon(
            onPressed: _busy ? null : _createLink,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.video_call_rounded, size: 18),
            label: Text(_busy ? 'Menyiapkan link...' : 'Buat link Meet'),
            style: FilledButton.styleFrom(
              backgroundColor: MalvaColors.plum,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          // Fallback manual: tetap bisa menyelenggarakan sesi video walau
          // pembuatan otomatis diblokir (mis. access_denied Google).
          OutlinedButton.icon(
            onPressed: _busy ? null : _pasteMeetLink,
            icon: const Icon(Icons.content_paste_rounded, size: 18),
            label: const Text('Tempel link Meet'),
          ),
        ],
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
