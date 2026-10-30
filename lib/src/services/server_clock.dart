import 'dart:async';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../time/wib.dart';

/// Jam acuan bersama: waktu perangkat + offset terhadap server.
///
/// Sumber waktu yang benar adalah SERVER, bukan jam perangkat. Offset dihitung
/// dari header HTTP `Date` (dikirim Go net/http pada setiap respons) dengan
/// kompensasi setengah RTT, lalu dipersist agar tetap terpakai saat offline.
///
/// Kenapa penting untuk obat: `taken_at` yang dikirim memakai jam perangkat.
/// Bila jam perangkat meleset berjam-jam, dosis pukul 23:50 bisa tersimpan
/// sebagai "besok" (atau sebaliknya) sehingga kepatuhan "hari ini" salah.
///
/// Catatan platform: file ini SENGAJA tidak memakai `dart:io` (`HttpDate`)
/// karena aplikasi juga di-build untuk web (`flutter build web`). Parsing
/// RFC1123 dilakukan manual di [_parseRfc1123Utc].
class ServerClock {
  ServerClock._();

  /// Key secure storage untuk offset (milidetik, bisa negatif).
  static const String offsetStorageKey = 'malva_server_clock_offset_ms';

  /// Key secure storage untuk waktu penyimpanan offset (audit/usia cache).
  static const String savedAtStorageKey = 'malva_server_clock_saved_at';

  /// Batas kewajaran offset. Selisih lebih dari 24 jam hampir pasti berasal
  /// dari header rusak / proxy yang menyisipkan tanggal sendiri, bukan dari
  /// jam perangkat yang salah — offset seperti itu justru merusak data.
  static const Duration _maxPlausibleOffset = Duration(hours: 24);

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  static Duration _offset = Duration.zero;
  static bool _isSynced = false;
  static bool _hasLoadedPersisted = false;

  /// Selisih waktu server terhadap waktu perangkat.
  static Duration get offset => _offset;

  /// True bila offset pernah dihitung dari respons server (atau cache lokal).
  static bool get isSynced => _isSynced;

  /// Waktu sekarang menurut acuan server (fallback: jam perangkat), dalam WIB.
  static DateTime now() => toWib(wibDeviceInstant().add(_offset));

  /// Terapkan header `Date` dari respons HTTP.
  ///
  /// [requestStarted] dan [responseReceived] adalah jam perangkat saat
  /// permintaan dikirim dan saat respons diterima. Waktu server diperkirakan
  /// jatuh di tengah rentang itu (kompensasi setengah RTT).
  ///
  /// Aman dipanggil dengan header null/rusak: offset tidak berubah dan tidak
  /// ada exception yang dilempar.
  static void applyHttpDate(
    String? httpDate, {
    required DateTime requestStarted,
    required DateTime responseReceived,
  }) {
    if (httpDate == null || httpDate.trim().isEmpty) return;
    final serverTime = _parseRfc1123Utc(httpDate);
    if (serverTime == null) return;

    final rtt = responseReceived.difference(requestStarted);
    final halfRtt = rtt.isNegative
        ? Duration.zero
        : Duration(microseconds: rtt.inMicroseconds ~/ 2);
    final deviceTimeAtServerAnswer = requestStarted.add(halfRtt);
    final candidate = serverTime.difference(deviceTimeAtServerAnswer);

    if (candidate.abs() > _maxPlausibleOffset) {
      // Header tidak masuk akal (mis. tanggal dari proxy) — abaikan.
      return;
    }

    _offset = candidate;
    _isSynced = true;
    // Fire-and-forget: kegagalan storage tidak boleh mengganggu request API.
    unawaited(persist());
  }

  /// Simpan offset ke secure storage agar tetap terpakai saat offline.
  ///
  /// Tidak pernah melempar: storage bisa tidak tersedia (test/web/izin).
  static Future<void> persist() async {
    try {
      await _storage.write(
        key: offsetStorageKey,
        value: _offset.inMilliseconds.toString(),
      );
      await _storage.write(
        key: savedAtStorageKey,
        value: wibNow().toIso8601String(),
      );
    } on Object {
      // Storage tidak tersedia: offset tetap berlaku untuk sesi berjalan.
    }
  }

  /// Muat offset tersimpan. Dipanggil sekali saat boot/applySession.
  ///
  /// Idempoten: pemanggilan kedua tidak membaca storage lagi. Kegagalan
  /// membaca tidak pernah melempar; aplikasi memakai jam perangkat.
  static Future<void> loadPersisted() async {
    if (_hasLoadedPersisted) return;
    _hasLoadedPersisted = true;
    try {
      final rawOffset = await _storage.read(key: offsetStorageKey);
      if (rawOffset == null || rawOffset.trim().isEmpty) return;
      final milliseconds = int.tryParse(rawOffset.trim());
      if (milliseconds == null) return;
      final candidate = Duration(milliseconds: milliseconds);
      if (candidate.abs() > _maxPlausibleOffset) return;
      _offset = candidate;
      _isSynced = true;
    } on Object {
      // Storage tidak tersedia: biarkan offset 0 (jam perangkat).
    }
  }

  /// Kembalikan ke kondisi awal (dipakai test dan saat logout total).
  static void reset() {
    _offset = Duration.zero;
    _isSynced = false;
    _hasLoadedPersisted = false;
  }

  // ============================================================
  // PARSING RFC1123 (manual, tanpa dart:io)
  // ============================================================

  static const List<String> _monthNames = <String>[
    'jan',
    'feb',
    'mar',
    'apr',
    'may',
    'jun',
    'jul',
    'aug',
    'sep',
    'oct',
    'nov',
    'dec',
  ];

  /// Parse tanggal RFC1123 gaya `Wed, 30 Oct 2026 03:20:00 GMT` menjadi UTC.
  ///
  /// Mengembalikan null bila bentuknya tidak dikenali. Nama zona selain GMT
  /// diabaikan (server selalu mengirim GMT), sehingga tidak ada ketergantungan
  /// pada zona waktu perangkat.
  static DateTime? _parseRfc1123Utc(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    // Buang prefix nama hari ("Wed,") bila ada.
    final commaIndex = text.indexOf(',');
    final body =
        (commaIndex >= 0 ? text.substring(commaIndex + 1) : text).trim();
    final parts = body.split(RegExp(r'\s+'));
    if (parts.length < 4) return null;

    final day = int.tryParse(parts[0]);
    final monthName = parts[1].toLowerCase();
    final monthIndex = _monthNames.indexOf(monthName);
    final year = int.tryParse(parts[2]);
    final timeParts = parts[3].split(':');
    if (day == null ||
        monthIndex < 0 ||
        year == null ||
        timeParts.length != 3) {
      return null;
    }
    final hour = int.tryParse(timeParts[0]);
    final minute = int.tryParse(timeParts[1]);
    final second = int.tryParse(timeParts[2]);
    if (hour == null || minute == null || second == null) return null;
    if (day < 1 ||
        day > 31 ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59 ||
        second < 0 ||
        second > 59) {
      return null;
    }

    final parsed =
        DateTime.utc(year, monthIndex + 1, day, hour, minute, second);
    // Tolak tanggal yang "meluber" (mis. 31 Feb) yang digeser oleh DateTime.
    if (parsed.month != monthIndex + 1 || parsed.day != day) return null;
    return parsed;
  }
}
