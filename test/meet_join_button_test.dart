import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/time/wib.dart';

// ============================================================
// JENDELA TOMBOL GABUNG GOOGLE MEET — HARUS MENGIKUTI WIB
//
// Aturan bisnis (lihat `BackendCareSession` di
// `lib/src/services/malva_api_client.dart`):
//   - pintu masuk ruang tunggu dibuka `joinOpensBefore` (10 menit) sebelum
//     jadwal,
//   - ditutup `joinClosesAfterEnd` (30 menit) setelah sesi berakhir
//     (durasi + 30 menit),
//   - perbandingan memakai `wibNow()`, jadi TIDAK boleh bergantung zona
//     perangkat pengguna.
//
// Semua jadwal dibangun relatif terhadap `wibNow()` supaya test tidak
// kedaluwarsa dan tidak bergantung jam dinding saat dijalankan.
// ============================================================

String _two(int value) => value.toString().padLeft(2, '0');

/// ISO 8601 dengan offset WIB eksplisit (`+07:00`) — bentuk yang dikirim
/// server Malva. Dibangun manual dari field WIB karena
/// `DateTime.toIso8601String()` membuang offset untuk waktu non-UTC.
String _isoWib(DateTime value) {
  final d = toWib(value);
  return '${d.year}-${_two(d.month)}-${_two(d.day)}'
      'T${_two(d.hour)}:${_two(d.minute)}:${_two(d.second)}'
      '+07:00';
}

/// ISO 8601 dalam UTC (`...Z`) untuk instant yang sama — dipakai membuktikan
/// konversi ke WIB terjadi di klien, bukan mengikuti zona perangkat.
///
/// Presisi dipangkas ke detik agar instant-nya persis sama dengan hasil
/// [_isoWib] (yang juga hanya menuliskan detik, seperti server Malva).
String _isoUtc(DateTime value) => DateTime.fromMillisecondsSinceEpoch(
      value.millisecondsSinceEpoch ~/ 1000 * 1000,
      isUtc: true,
    ).toIso8601String();

/// Sesi video dibangun lewat `fromJson` agar nama field JSON ikut teruji
/// (`scheduled_at`, `duration_minutes`, `meeting_url`).
BackendCareSession _videoSession({
  required String scheduledAt,
  int durationMinutes = 30,
  String meetingUrl = 'https://meet.google.com/abc-defg-hij',
}) =>
    BackendCareSession.fromJson(<String, dynamic>{
      'id': 'sess_video_1',
      'patient_id': 'user_pasien_1',
      'professional_id': 'pro_123',
      'patient_name': 'Pasien',
      'professional_name': 'Dr. Sinta',
      'session_type': 'video',
      'scheduled_at': scheduledAt,
      'duration_minutes': durationMinutes,
      'status': 'scheduled',
      'meeting_url': meetingUrl,
    });

void main() {
  setUpAll(initializeWib);

  test('join window terbuka 10 menit sebelum jadwal', () {
    final session = _videoSession(
      scheduledAt: _isoWib(wibNow().add(const Duration(minutes: 5))),
    );

    expect(session.isVideo, isTrue);
    expect(session.scheduledDateTime, isNotNull);
    expect(session.canJoinNow, isTrue);
    expect(session.isBeforeJoinWindow, isFalse);
    expect(session.isAfterJoinWindow, isFalse);
    // Jendela sudah dibuka, jadi tidak ada hitungan mundur.
    expect(session.timeUntilJoinOpens, isNull);
    expect(session.joinStateLabel, 'Bisa bergabung');
  });

  test('join window belum terbuka bila masih 30 menit lagi', () {
    final session = _videoSession(
      scheduledAt: _isoWib(wibNow().add(const Duration(minutes: 30))),
    );

    expect(session.canJoinNow, isFalse);
    expect(session.isBeforeJoinWindow, isTrue);
    expect(session.isAfterJoinWindow, isFalse);

    // Jendela dibuka 10 menit sebelum jadwal -> sisa ~20 menit.
    final left = session.timeUntilJoinOpens;
    expect(left, isNotNull);
    expect(left!, greaterThan(const Duration(minutes: 19)));
    expect(left, lessThanOrEqualTo(const Duration(minutes: 20)));
    expect(session.joinStateLabel, startsWith('Mulai dalam'));
  });

  test('join window tertutup setelah durasi + toleransi', () {
    final session = _videoSession(
      scheduledAt: _isoWib(wibNow().subtract(const Duration(hours: 3))),
      durationMinutes: 30,
    );

    // Berakhir 3 jam lalu; toleransi 30 menit -> jendela tutup 2 jam lalu.
    expect(session.canJoinNow, isFalse);
    expect(session.isAfterJoinWindow, isTrue);
    expect(session.isBeforeJoinWindow, isFalse);
    expect(session.joinStateLabel, 'Sesi berakhir');
  });

  test('sesi tanpa link Meet melaporkan link belum tersedia', () {
    final session = _videoSession(
      scheduledAt: _isoWib(wibNow().add(const Duration(minutes: 5))),
      meetingUrl: '',
    );

    expect(session.meetingUrl, isEmpty);
    expect(session.joinStateLabel, 'Link belum tersedia');
  });

  test('perhitungan tidak bergantung zona perangkat', () {
    final target = wibNow().add(const Duration(minutes: 5));

    final dariWib = _videoSession(scheduledAt: _isoWib(target));
    final dariUtc = _videoSession(scheduledAt: _isoUtc(target));

    // String berbeda bentuk, instant-nya sama.
    expect(dariUtc.scheduledAt, endsWith('Z'));
    expect(dariWib.scheduledAt, endsWith('+07:00'));
    expect(
      dariUtc.scheduledDateTime!.isAtSameMomentAs(dariWib.scheduledDateTime!),
      isTrue,
    );

    // Keduanya dinilai dengan wibNow() -> hasil identik.
    expect(dariWib.canJoinNow, isTrue);
    expect(dariUtc.canJoinNow, isTrue);
    expect(dariUtc.joinStateLabel, dariWib.joinStateLabel);
    // Dibuktikan juga bahwa hasilnya WIB (+07:00), bukan zona perangkat.
    expect(
      dariUtc.scheduledDateTime!.timeZoneOffset,
      const Duration(hours: 7),
    );
  });
}
