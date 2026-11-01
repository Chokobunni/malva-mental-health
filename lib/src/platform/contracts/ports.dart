import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Widget, ValueChanged;

/// Penyimpanan kunci-nilai rahasia (sesi, token, antrean sync, offset jam).
///
/// Implementasi web saat ini = flutter_secure_storage (localStorage) —
/// keputusan sementara. Menggantinya dengan cookie httpOnly / IndexedDB
/// cukup menambah satu kelas di lib/src/platform/web/ dan satu baris di
/// platform_factory_web.dart; tidak ada berkas UI yang tersentuh.
abstract interface class SecureStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Berkas yang sudah dibaca ke memori. Sengaja berbasis byte, bukan path,
/// karena path tidak ada di web (XFile.path = blob URL, bukan berkas nyata).
class PickedFile {
  const PickedFile({
    required this.name,
    required this.bytes,
    required this.mimeType,
  });

  final String name;
  final Uint8List bytes;
  final String mimeType;

  int get size => bytes.length;
}

/// Memilih berkas dari perangkat. Batas ukuran divalidasi di pemanggil.
abstract interface class FilePickerPort {
  /// [kind]: image | video
  ///
  /// [maxWidth]/[maxHeight]/[imageQuality] hanya berlaku untuk gambar dan
  /// diteruskan apa adanya ke `ImagePicker.pickImage` (mobile) dan
  /// `image_picker_for_web` (canvas resize). Parameter ini WAJIB ada agar
  /// foto kamera 12 MP tidak terkirim mentah melewati batas unggah backend.
  Future<PickedFile?> pick(
    String kind, {
    int? maxWidth,
    int? maxHeight,
    int? imageQuality,
  });
}

/// Menyimpan teks sebagai berkas yang bisa diunduh/dibagikan pengguna.
/// io  : temp file + share_plus (lembar bagikan Android)
/// web : Blob + <a download> (unduhan browser)
abstract interface class FileExporter {
  Future<void> saveText({
    required String filename,
    required String content,
    required String mimeType, // 'text/csv' | 'application/json' | 'text/plain'
    /// Subjek/teks pendamping (dipakai share sheet mobile). Di web diabaikan
    /// karena unduhan browser tidak punya konsep subjek.
    String? subject,
  });
}

/// Pengingat obat berbasis OS. Di web tidak ada penjadwal lokal.
abstract interface class ReminderScheduler {
  /// false di web → UI wajib menampilkan "kelola pengingat dari aplikasi".
  bool get canScheduleOsReminders;

  Future<void> initialize();
  Future<bool> requestPermissions();
  Future<void> scheduleAll(List<dynamic> medications); // List<Medication>
  Future<void> cancelAll();
  Future<void> showTestNotification();

  /// Pengingat saat aplikasi terbuka (dipakai hanya bila
  /// canScheduleOsReminders == false). Memancarkan medicationId yang jatuh tempo.
  Stream<String> get inAppDueReminders;
}

/// Registrasi token push (FCM).
abstract interface class PushRegistrar {
  /// false di web fase 1 (butuh service worker + VAPID, fase 2).
  bool get canRegister;

  Future<void> initialize({void Function(String route)? onForegroundTap});
  Future<void> requestPermission();
  Future<String?> obtainToken();
  Stream<String> get tokenRefreshes;
  void Function(String route)? onTap;
}

/// Hasil percobaan menelepon.
enum DialOutcome { opened, fallbackShown, failed }

/// Menelepon nomor telepon. Browser tidak punya penangan `tel:` di desktop.
abstract interface class Dialer {
  bool get canDialTel;
  Future<DialOutcome> call(String phoneNumber, {String? displayName});
}

/// Manipulasi riwayat/URL browser. io = no-op (URL tidak relevan).
abstract interface class BrowserHistory {
  String get currentPath;
  void push(String path);
  void replace(String path);
  void attachPopHandler(void Function() onPop);
}

/// Konfigurasi Google Sign-In per target.
class GoogleClientConfig {
  const GoogleClientConfig({required this.clientId, this.serverClientId});

  /// Web OAuth Client ID — sama untuk Android (serverClientId) dan web (clientId)
  /// agar `aud` pada ID token konsisten dengan `idtoken.Validate` di backend.
  final String clientId;
  final String? serverClientId;
}

/// Login Google. Mobile memakai alur imperatif (`authenticate()`), web WAJIB
/// memakai tombol resmi Google (`renderButton`) karena `authenticate()` tidak
/// didukung di web (melempar UnimplementedError).
abstract interface class GoogleSignInPort {
  /// True di web: UI harus memanggil [buildButton], bukan [signInIdToken].
  bool get usesButtonWidget;

  /// Mobile: jalankan alur imperatif → ID token (null bila batal).
  /// Web: tidak dipakai (lempar UnsupportedError).
  Future<String?> signInIdToken();

  /// Web: bangun tombol resmi Google (renderButton). Saat berhasil, ID token
  /// dikirim ke [onIdToken]; kegagalan ke [onError]. Mobile: null.
  Widget? buildButton({
    required ValueChanged<String> onIdToken,
    required ValueChanged<Object> onError,
  });
}

/// Kemampuan platform — SATU-SATUNYA cara UI bertanya "bisakah ini?".
class PlatformCapabilities {
  const PlatformCapabilities({
    required this.canScheduleOsReminders,
    required this.canRegisterPush,
    required this.canExportFiles,
    required this.canDialTel,
    required this.canPickFiles,
    required this.canGeolocate,
    required this.canBindGoogleCalendar,
    required this.isWebBuild,
  });

  final bool canScheduleOsReminders;
  final bool canRegisterPush;
  final bool canExportFiles;
  final bool canDialTel;
  final bool canPickFiles;
  final bool canGeolocate;
  final bool canBindGoogleCalendar;
  final bool isWebBuild;
}
