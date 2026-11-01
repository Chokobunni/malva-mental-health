import '../contracts/ports.dart';

/// Kemampuan platform web — Dart MURNI (tanpa `package:web`) agar bisa diuji
/// di VM tanpa menarik API khusus browser. Dipakai `platform_factory_web.dart`.
const PlatformCapabilities webCapabilities = PlatformCapabilities(
  canScheduleOsReminders: false, // fase 1 — tidak ada penjadwal notifikasi OS
  canRegisterPush: false, // fase 2 (butuh service worker + VAPID)
  canExportFiles: true, // Blob + <a download> berfungsi di browser
  canDialTel: false, // fallback sheet, bukan tel:
  canPickFiles: true,
  canGeolocate: true,
  canBindGoogleCalendar: false, // backend belum punya RedirectURL
  isWebBuild: true,
);
