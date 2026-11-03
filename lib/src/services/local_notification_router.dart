import 'dart:convert';

import 'package:flutter/foundation.dart';

/// Handler payload push (JSON) — diisi oleh `PushNotificationService`.
typedef PushPayloadHandler = void Function(Map<String, dynamic> data);

/// Handler payload pengingat obat (id obat, bukan JSON).
typedef MedicationPayloadHandler = void Function(String medicationId);

/// Router tap notifikasi LOKAL untuk seluruh aplikasi.
///
/// KENAPA PERLU: sebelumnya `PushNotificationService` dan
/// `MedicationReminderService` sama-sama memanggil `initialize()` pada
/// singleton `FlutterLocalNotificationsPlugin` dengan handler tap
/// masing-masing. Handler yang terdaftar TERAKHIR menimpa yang lain, sehingga
/// tap notifikasi obat bisa masuk ke handler push (jsonDecode gagal → tidak
/// terjadi apa-apa) dan sebaliknya — tergantung urutan inisialisasi.
///
/// Sekarang kedua service memasang [handle] sebagai handler tunggal. Router
/// menentukan tujuan berdasarkan BENTUK payload:
///   - JSON objek  → payload push → diteruskan ke [onPushPayload].
///   - selain itu  → id obat → diteruskan ke [onMedicationPayload] dan layar
///     Medication dibuka lewat [openMedicationScreen].
class LocalNotificationRouter {
  const LocalNotificationRouter._();

  /// Diteruskan ke navigasi push (`_handleNotificationNavigation`).
  static PushPayloadHandler? onPushPayload;

  /// Diteruskan ke `MedicationReminderService.onNotificationTap` (dipakai
  /// layar Medication untuk menyorot obat terkait).
  static MedicationPayloadHandler? onMedicationPayload;

  /// Membuka layar Medication (rute `/medication`).
  static void Function()? openMedicationScreen;

  /// Payload pengingat goals. BUKAN id obat, jadi tidak boleh diperlakukan
  /// sebagai id obat (kalau tidak, tap pengingat goals akan membuka layar
  /// Medication). Tap-nya cukup membuka aplikasi seperti biasa.
  static const String goalReminderPayload = 'goal_reminder';

  /// Handler tunggal untuk tap notifikasi lokal.
  ///
  /// Menerima PAYLOAD saja (bukan `NotificationResponse`) agar berkas ini
  /// tidak mengimpor plugin notifikasi: kode yang menyentuh plugin wajib
  /// berada di `lib/src/platform/` (gate `check_platform_isolation.sh`).
  static void handlePayload(String? payload) {
    if (payload == null || payload.isEmpty) return;

    final data = _decodePushPayload(payload);
    if (data != null) {
      onPushPayload?.call(data);
      return;
    }

    if (payload == goalReminderPayload) {
      // Pengingat goals: tidak ada navigasi khusus (goals ada di beranda).
      return;
    }

    // Payload bukan JSON objek → payload pengingat obat (id obat).
    onMedicationPayload?.call(payload);
    openMedicationScreen?.call();
  }

  /// `null` bila payload bukan JSON objek (mis. id obat atau teks biasa).
  static Map<String, dynamic>? _decodePushPayload(String payload) {
    final trimmed = payload.trimLeft();
    if (!trimmed.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } on Object catch (error) {
      // Payload rusak: jangan sampai tap notifikasi memicu exception.
      if (kDebugMode) {
        debugPrint('Payload notifikasi bukan JSON valid: $error');
      }
    }
    return null;
  }

  /// Lepas semua handler (dipakai test agar state statis tidak bocor).
  @visibleForTesting
  static void reset() {
    onPushPayload = null;
    onMedicationPayload = null;
    openMedicationScreen = null;
  }
}
