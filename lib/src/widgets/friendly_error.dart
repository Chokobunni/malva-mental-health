import 'package:flutter/material.dart';

import '../models.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import 'malva_components.dart';

// ============================================================
// PESAN ERROR RAMAH — tidak pernah menampilkan teks teknis
// mentah (FormatException, SocketException, stack trace, HTML,
// ATAU kalimat Inggris dari server) ke pengguna.
// ============================================================

/// Kata penanda bahwa sebuah pesan sudah berbahasa Indonesia. Dipakai oleh
/// heuristik [looksLikeTechnicalEnglish] agar pesan Indonesia yang sah tidak
/// ikut diganti. Sengaja memakai bentuk dengan spasi di kiri-kanan untuk
/// menghindari salah cocok di tengah kata.
const List<String> _indonesianMarkers = <String>[
  'dan ',
  'yang ',
  'tidak ',
  'belum ',
  'sudah ',
  'anda ',
  'kamu ',
  'pasien ',
  'sesi ',
  'gagal ',
  'silakan ',
  'coba ',
  'atau ',
  'dengan ',
  'untuk ',
  'dari ',
  'ini ',
  'itu ',
  'pada ',
  'harus ',
  'dapat ',
  'wajib ',
  'maksimal ',
  'minimal ',
];

/// Pola kata Inggris teknis yang TIDAK boleh tampil mentah ke pengguna.
final RegExp _englishTechnicalPattern = RegExp(
  r'\b(not|cannot|invalid|required|failed|forbidden|unauthorized|denied|'
  r'must|error|expired|missing|unknown|unexpected|refused)\b',
);

/// true bila [lower] tampak seperti pesan Inggris teknis yang belum ramah.
///
/// Heuristik sederhana (sesuai arahan): bila TIDAK mengandung penanda kata
/// Indonesia DAN cocok dengan pola kata Inggris teknis, anggap teknis. Pesan
/// Indonesia yang sah (mengandung "tidak", "pasien", dst.) selalu diloloskan.
bool looksLikeTechnicalEnglish(String lower) {
  final hasIndonesian = _indonesianMarkers.any(lower.contains);
  if (hasIndonesian) return false;
  return _englishTechnicalPattern.hasMatch(lower);
}

/// Menerjemahkan pesan server (sering berbahasa Inggris) menjadi teks Indonesia
/// yang ramah. Ini SATU sumber kebenaran untuk seluruh aplikasi — dipakai
/// [friendlyErrorMessage] dan layar yang perlu memetakan pesan server sendiri.
///
/// Urutan pencocokan penting dan sengaja eksplisit: consent/berbagi data lebih
/// dulu, lalu auth, lalu akses/otorisasi, lalu not-found, lalu jaringan, lalu
/// server, terakhir fallback generik. Bila pesan tidak dikenali tetapi tampak
/// teknis/Inggris, pesan asli TIDAK ditampilkan — dicatat ke log debug dan
/// diganti teks generik Indonesia.
String friendlyServerMessage(String raw) {
  final message = raw.trim();
  if (message.isEmpty) {
    return 'Terjadi kendala. Silakan coba lagi.';
  }
  final lower = message.toLowerCase();

  // 1. Consent / data sharing (paling sering muncul di dashboard profesional).
  if (lower.contains('belum membagikan') ||
      lower.contains('has not shared') ||
      lower.contains('not shared') ||
      lower.contains('not been shared') ||
      lower.contains('not sharing')) {
    if (lower.contains('screening') || lower.contains('skrining')) {
      return 'Pasien belum membagikan data skrining.';
    }
    if (lower.contains('goal') || lower.contains('tujuan')) {
      return 'Pasien belum membagikan data tujuan terapi.';
    }
    if (lower.contains('health record')) {
      return 'Pasien belum membagikan Health Record.';
    }
    if (lower.contains('mood') || lower.contains('diary')) {
      return 'Pasien belum membagikan data mood/diary.';
    }
    if (lower.contains('medication') || lower.contains('obat')) {
      return 'Pasien belum membagikan data obat.';
    }
    if (lower.contains('timeline')) {
      return 'Pasien belum membagikan data timeline.';
    }
    return 'Pasien belum membagikan data yang diminta.';
  }

  // 2. Auth / sesi login.
  if (lower.contains('unauthorized') ||
      lower.contains('invalid token') ||
      lower.contains('token expired') ||
      lower.contains('sesi berakhir') ||
      lower.contains('sesi tidak valid')) {
    return 'Sesi login kamu berakhir. Silakan masuk kembali.';
  }

  // 3. Akses / otorisasi.
  if (lower.contains('not linked') || lower.contains('users are not linked')) {
    return 'Anda belum terhubung dengan pengguna ini.';
  }
  // Pola "only <peran> can ..." → tindakan tidak tersedia untuk peran ini.
  if (lower.contains('only ') && lower.contains(' can ')) {
    return 'Tindakan ini tidak tersedia untuk peran Anda.';
  }
  if (lower.contains('forbidden') ||
      lower.contains('access denied') ||
      lower.contains('access_denied') ||
      lower.contains('not allowed') ||
      lower.contains('not permitted')) {
    return 'Kamu tidak punya akses ke data ini.';
  }

  // 4. Tidak ditemukan.
  if (lower.contains('not found') || lower.contains('tidak ditemukan')) {
    return 'Data tidak ditemukan.';
  }

  // 5. Jaringan.
  if (lower.contains('timeout') ||
      lower.contains('timed out') ||
      lower.contains('connection') ||
      lower.contains('network') ||
      lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('unreachable') ||
      lower.contains('handshake')) {
    return 'Koneksi ke server bermasalah. Periksa jaringan lalu coba lagi.';
  }

  // 6. Galat server.
  if (lower.contains('internal server') ||
      lower.contains('internal error') ||
      lower.contains('server error')) {
    return 'Server sedang bermasalah. Silakan coba lagi nanti.';
  }

  // 7. Fallback: jangan pernah tampilkan kalimat Inggris mentah.
  if (looksLikeTechnicalEnglish(lower)) {
    debugPrint('[friendlyServerMessage] pesan server tak dikenali: $message');
    return 'Terjadi kendala. Silakan coba lagi.';
  }
  return message;
}

String friendlyErrorMessage(Object error) {
  // Pesan yang sudah ramah (dari provider/lapisan atas) diteruskan apa adanya.
  if (error is String) return error;
  // Pesan server bisa berbahasa Inggris — terjemahkan lewat satu sumber.
  if (error is MalvaApiException) return friendlyServerMessage(error.message);
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
