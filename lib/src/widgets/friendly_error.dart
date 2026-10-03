import 'package:flutter/material.dart';

import '../models.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import 'malva_components.dart';

// ============================================================
// PESAN ERROR RAMAH — tidak pernah menampilkan teks teknis
// mentah (FormatException, SocketException, stack trace, HTML)
// ke pengguna.
// ============================================================

String friendlyErrorMessage(Object error) {
  // Pesan yang sudah ramah (dari provider/lapisan atas) diteruskan apa adanya.
  if (error is String) return error;
  if (error is MalvaApiException) return error.message;
  if (error is AuthFailure) return error.message;
  final text = error.toString();
  if (text.contains('TimeoutException') || text.contains('timed out')) {
    return 'Koneksi lambat. Periksa internet lalu coba lagi.';
  }
  if (text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('Connection refused') ||
      text.contains('Failed host lookup') ||
      text.contains('Network is unreachable') ||
      text.contains('No route to host') ||
      text.contains('Connection reset') ||
      text.contains('HandshakeException')) {
    return 'Tidak dapat terhubung ke server Malva. '
        'Pastikan HP dan server dalam jaringan yang sama, lalu coba lagi.';
  }
  if (text.contains('FormatException')) {
    return 'Data dari server tidak valid. Coba lagi nanti.';
  }
  return 'Terjadi kendala. Silakan coba lagi.';
}

/// Kartu error standar: pesan ramah + tombol Coba Lagi.
class FriendlyErrorCard extends StatelessWidget {
  const FriendlyErrorCard({
    super.key,
    required this.error,
    required this.onRetry,
    this.title,
  });

  final Object error;
  final VoidCallback onRetry;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            friendlyErrorMessage(error),
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: MalvaColors.danger,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Coba Lagi'),
          ),
        ],
      ),
    );
  }
}

/// Banner info offline: ramah, tanpa nada error.
class OfflineNoticeBanner extends StatelessWidget {
  const OfflineNoticeBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MalvaColors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: MalvaColors.amber.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: MalvaColors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
