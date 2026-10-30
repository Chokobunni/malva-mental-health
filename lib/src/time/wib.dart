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

/// Inisialisasi zona WIB. Idempoten — aman dipanggil berkali-kali.
void initializeWib() {
  if (_wib != null) return;
  tzdata.initializeTimeZones();
  _wib = tz.getLocation(wibLocationName);
}

/// Zona WIB yang dipakai bersama.
tz.Location get wibLocation {
  initializeWib();
  return _wib!;
}

/// Sekarang, dalam WIB — TIDAK bergantung zona perangkat.
DateTime wibNow() => tz.TZDateTime.now(wibLocation);

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
