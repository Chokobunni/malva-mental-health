import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Hasil upaya membuka tautan Google Meet.
enum MeetLaunchResult {
  /// Tautan dibuka oleh aplikasi eksternal (aplikasi Meet / browser).
  openedExternal,

  /// Tautan dibuka di dalam browser in-app (fallback bila eksternal gagal).
  openedInApp,

  /// Tautan tidak valid (bukan https atau bukan host meet.google.com).
  invalid,

  /// Semua jalur gagal — pemanggil sebaiknya menyalin tautan agar pengguna
  /// dapat menempelnya manual.
  failed,
}

/// Membuka tautan Google Meet dari dalam aplikasi.
///
/// Tidak memakai `canLaunchUrl` sebagai gerbang: di Android 11+ `canLaunchUrl`
/// mengembalikan `false` untuk skema `https` bila `<queries>` tidak dideklarasikan,
/// sehingga gerbang itu membuat tombol "Gabung" gagal padahal tautan valid.
/// Alih-alih memeriksa lebih dulu, kita langsung mencoba `launchUrl` dan
/// menangani kegagalan lewat fallback.
Future<MeetLaunchResult> openMeetLink(String rawUrl) async {
  final uri = _validMeetUri(rawUrl);
  if (uri == null) return MeetLaunchResult.invalid;

  // Jalur utama: buka di aplikasi eksternal (aplikasi Meet / browser default).
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (ok) return MeetLaunchResult.openedExternal;
  } on Object {
    // Lanjut ke fallback in-app browser.
  }

  // Fallback: buka di dalam browser in-app agar sesi tetap bisa diikuti.
  try {
    final ok = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
    if (ok) return MeetLaunchResult.openedInApp;
  } on Object {
    // Jatuh ke `failed` di bawah.
  }

  return MeetLaunchResult.failed;
}

/// Menyalin tautan Google Meet ke clipboard. Best-effort; tidak melempar galat.
Future<void> copyMeetLink(String url) async {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return;
  await Clipboard.setData(ClipboardData(text: trimmed));
}

/// Memvalidasi tautan Meet: wajib `https` dan host `meet.google.com`.
/// Mengembalikan `null` bila tidak valid.
Uri? _validMeetUri(String rawUrl) {
  final trimmed = rawUrl.trim();
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (uri.scheme != 'https') return null;
  if (uri.host.toLowerCase() != 'meet.google.com') return null;
  return uri;
}
