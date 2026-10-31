import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Helper waktu tunggal aplikasi Malva: **WIB (Asia/Jakarta)**.
///
/// Semua waktu di aplikasi ini adalah WIB, apa pun zona perangkat pengguna.
/// Jangan konversi ke zona perangkat, baca jam perangkat, atau normalisasi ke
/// UTC di luar berkas ini — pakai `wibNow()` / `toWib()` / `toWibOrNull()` dan
/// helper format di bawah. Lihat gate `scripts/check_wib_dart.sh`.

/// Nama zona WIB (IANA).
const String wibLocationName = 'Asia/Jakarta';

tz.Location? _wib;

/// Inisialisasi zona WIB **dan** memaksa zona lokal proses ke WIB.
///
/// Idempoten — aman dipanggil berkali-kali (dan memang dipanggil dari banyak
/// tempat: `main()`, layanan notifikasi, serta setiap helper di bawah).
///
/// KENAPA `setLocalLocation` DI SINI (akar bug pengingat obat telat 7 jam):
/// paket `timezone` menginisialisasi zona lokal ke **Etc/UTC** — lihat
/// `initializeDatabase()` yang memanggil `setLocalLocation(_utc)`. Artinya
/// selama tidak ada yang menyetelnya, `tz.local` adalah UTC, dan kode yang
/// membangun jadwal dengan `tz.local` menghasilkan **10:00 UTC = 17:00 WIB**
/// (telat 7 jam). `flutter_local_notifications` menyimpan jadwal dari
/// `tz.TZDateTime` yang kita berikan, jadi zona itu langsung menentukan jam
/// berbunyinya notifikasi. Karena itu zona lokal proses DIPAKSA ke WIB di sini
/// — satu kali, untuk seluruh aplikasi.
///
/// CATATAN PENTING: `tzdata.initializeTimeZones()` / `initializeTimeZones()`
/// dari `package:timezone/data/*` MENGHAPUS paksaan ini (karena memanggil
/// `setLocalLocation(_utc)`). Jangan panggil `initializeTimeZones()` langsung
/// di kode aplikasi — panggil [initializeWib] (fungsi ini) supaya zona lokal
/// tetap WIB. Gate `scripts/check_wib_dart.sh` melarang `tz.local` di luar
/// berkas ini agar bug yang sama tidak muncul lagi.
void initializeWib() {
  if (_wib == null) {
    tzdata.initializeTimeZones();
    _wib = tz.getLocation(wibLocationName);
  }
  // Selalu (idempoten) pasang ulang: murah, dan menjamin `tz.local` kembali
  // ke WIB walau ada kode lain yang sempat menginisialisasi ulang database.
  tz.setLocalLocation(_wib!);
}

/// Zona WIB yang dipakai bersama.
tz.Location get wibLocation {
  initializeWib();
  return _wib!;
}

/// Sekarang, dalam WIB — TIDAK bergantung zona perangkat.
tz.TZDateTime wibNow() => tz.TZDateTime.now(wibLocation);

/// Instant perangkat mentah (sumber mentah jam sistem).
///
/// INI satu-satunya `DateTime.now()` yang diizinkan di aplikasi; semua kode
/// lain memakai [wibNow]/[toWib]. Dipakai saat instant mentah diperlukan
/// (mis. dijumlahkan dengan offset server), dan hasilnya WAJIB dibungkus
/// [toWib] sebelum dipakai sebagai waktu bisnis.
DateTime wibDeviceInstant() => DateTime.now();

/// Konversi instant apa pun (termasuk `...Z`) ke WIB.
DateTime toWib(DateTime value) => tz.TZDateTime.from(value, wibLocation);

/// Seperti [toWib] tetapi menerima/ mengembalikan null.
DateTime? toWibOrNull(DateTime? value) => value == null ? null : toWib(value);

String _two(int value) => value.toString().padLeft(2, '0');

/// Kunci tanggal `yyyy-MM-dd` dalam WIB (untuk grouping kalender/streak).
String wibDateKey(DateTime value) {
  final d = toWib(value);
  return '${d.year}-${_two(d.month)}-${_two(d.day)}';
}

/// Tanggal `dd/MM/yyyy` dalam WIB.
String formatWibDate(DateTime value) {
  final d = toWib(value);
  return '${_two(d.day)}/${_two(d.month)}/${d.year}';
}

/// Tanggal + jam `dd/MM/yyyy HH:mm` dalam WIB.
String formatWibDateTime(DateTime value) {
  final d = toWib(value);
  return '${_two(d.day)}/${_two(d.month)}/${d.year} '
      '${_two(d.hour)}:${_two(d.minute)}';
}

/// Label pemisah tanggal pesan (`Hari ini HH:mm` / `dd/MM/yyyy HH:mm`).
String formatWibBubbleDate(DateTime value) {
  final d = toWib(value);
  final h = _two(d.hour);
  final m = _two(d.minute);
  if (isWibToday(d)) {
    return 'Hari ini $h:$m';
  }
  return '${d.day}/${d.month}/${d.year} $h:$m';
}

/// True bila [value] jatuh pada hari kalender WIB saat ini.
bool isWibToday(DateTime value) {
  final d = toWib(value);
  final now = wibNow();
  return d.year == now.year && d.month == now.month && d.day == now.day;
}

/// Jam kecil `HH:mm` dalam WIB.
String formatWibBubbleTime(DateTime value) {
  final d = toWib(value);
  return '${_two(d.hour)}:${_two(d.minute)}';
}

/// Wall-clock WIB `yyyy-MM-ddTHH:mm` (tanpa offset/`Z`) — format yang diterima
/// `parseWIBDateTime` di backend. Pakai ini saat mengirim waktu ke server.
String wibApiDateTime(DateTime value) {
  final d = toWib(value);
  return '${d.year}-${_two(d.month)}-${_two(d.day)}'
      'T${_two(d.hour)}:${_two(d.minute)}';
}

// ============================================================
// SERIALISASI NILAI WAKTU (storage lokal & payload internal)
// ============================================================
//
// KENAPA TIDAK `toIso8601String()` SAJA:
// implementasi Dart MEMBUANG offset untuk waktu non-UTC. Jadi
// `wibNow().toIso8601String()` menghasilkan `2026-11-01T10:00:00.000` TANPA
// `+07:00` — zonanya hilang. Saat string itu dibaca kembali di perangkat
// non-WIB, nilainya ditafsirkan sebagai jam lokal perangkat lalu digeser 7 jam
// (mood, diary, dan log obat terkirim dengan jam salah). Karena itu:
//   - MENULIS nilai waktu -> [wibIso] (offset `+07:00` eksplisit),
//   - MEMBACA nilai tersimpan -> [parseWibStored] (toleran data lama),
//   - nilai dari date/time picker -> [wibFromParts] (wall-clock, bukan instant).

/// ISO 8601 dengan offset eksplisit (`yyyy-MM-ddTHH:mm:ss.SSS+07:00`).
///
/// Berbeda dengan `DateTime.toIso8601String()` yang membuang offset untuk
/// waktu non-UTC, string ini selalu membawa zonanya sehingga pembaca di
/// perangkat mana pun menghasilkan instant yang sama.
String wibIso(DateTime value) {
  final d = toWib(value);
  final offset = d.timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final absOffset = offset.abs();
  return '${d.year}-${_two(d.month)}-${_two(d.day)}'
      'T${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}'
      '.${d.millisecond.toString().padLeft(3, '0')}'
      '$sign${_two(absOffset.inHours)}:${_two(absOffset.inMinutes % 60)}';
}

/// Pola wall-clock tanpa zona: `yyyy-MM-dd`, `yyyy-MM-ddTHH:mm`,
/// `yyyy-MM-dd HH:mm`, dengan detik/pecahan detik opsional.
final RegExp _wallClockPattern = RegExp(
  r'^(\d{4})-(\d{2})-(\d{2})(?:[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,9}))?)?)?$',
);

int _microsecondsFromFraction(String fraction) {
  if (fraction.isEmpty) return 0;
  return int.parse(fraction.padRight(6, '0').substring(0, 6));
}

bool _inRange(int value, int min, int max) => value >= min && value <= max;

/// Baca nilai waktu tersimpan (storage lokal / antrean offline / chat).
///
/// - Kosong atau tidak valid -> `null`.
/// - Punya offset (`+07:00`) atau berakhiran `Z` -> di-parse sebagai instant,
///   lalu dikonversi ke WIB lewat [toWib].
/// - TANPA offset/`Z` (data lama hasil `toIso8601String()` yang membuang zona)
///   -> komponennya ditafsirkan sebagai **wall-clock WIB**, BUKAN jam
///   perangkat. Ini yang mencegah pergeseran 7 jam di perangkat non-WIB.
DateTime? parseWibStored(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  final wall = _wallClockPattern.firstMatch(text);
  if (wall != null) {
    final year = int.parse(wall.group(1)!);
    final month = int.parse(wall.group(2)!);
    final day = int.parse(wall.group(3)!);
    final hour = int.tryParse(wall.group(4) ?? '') ?? 0;
    final minute = int.tryParse(wall.group(5) ?? '') ?? 0;
    final second = int.tryParse(wall.group(6) ?? '') ?? 0;
    final micros = _microsecondsFromFraction(wall.group(7) ?? '');
    final valid = _inRange(month, 1, 12) &&
        _inRange(day, 1, 31) &&
        _inRange(hour, 0, 23) &&
        _inRange(minute, 0, 59) &&
        _inRange(second, 0, 59);
    if (!valid) return null;
    return tz.TZDateTime(
      wibLocation,
      year,
      month,
      day,
      hour,
      minute,
      second,
      micros ~/ 1000,
      micros % 1000,
    );
  }
  final parsed = DateTime.tryParse(text);
  return parsed == null ? null : toWib(parsed);
}

/// Bangun WIB dari komponen kalender (mis. hasil date/time picker).
///
/// Nilai picker adalah **wall-clock** ("user memilih 1 November pukul 10.00"),
/// bukan instant. Membangunnya lewat `DateTime(...)` membuat zona perangkat
/// ikut campur, sehingga tanggal yang dipilih bisa bergeser sehari di
/// perangkat non-WIB. Selalu pakai helper ini untuk nilai dari picker.
///
/// Mengembalikan [tz.TZDateTime] ber-zona WIB (bukan `DateTime` biasa) supaya
/// bisa langsung dipakai `zonedSchedule` tanpa konversi zona tambahan.
tz.TZDateTime wibFromParts(
  int year,
  int month,
  int day, [
  int hour = 0,
  int minute = 0,
]) =>
    tz.TZDateTime(wibLocation, year, month, day, hour, minute);
