import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/services/offline_sync_service.dart';
import 'package:malva_mental_health/src/time/wib.dart';

// ============================================================
// ROUND-TRIP NILAI WAKTU LEWAT PENYIMPANAN LOKAL
//
// Cacat yang dikunci di sini: `TZDateTime.toIso8601String()` (warisan
// `DateTime`) MEMBUANG offset untuk waktu non-UTC, jadi
// `wibNow().toIso8601String()` menghasilkan `2026-11-01T10:00:00.000` tanpa
// `+07:00`. Saat dibaca kembali di perangkat non-WIB, string itu ditafsirkan
// sebagai jam lokal perangkat → antrean offline (mood, diary, obat) terkirim
// dengan jam salah 7 jam.
//
// Aturan: MENULIS pakai `wibIso()` (offset eksplisit), MEMBACA pakai
// `parseWibStored()` (toleran data lama tanpa offset). Test ini tidak
// bergantung zona perangkat karena tidak ada yang membaca jam perangkat.
// ============================================================

void main() {
  setUpAll(initializeWib);

  test('wibIso menyertakan offset +07:00', () {
    final text = wibIso(wibNow());
    expect(text, endsWith('+07:00'));
    expect(text, isNot(endsWith('Z')));
    expect(
      text,
      matches(
        RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}\+07:00$'),
      ),
    );
  });

  test('parseWibStored memahami nilai lama tanpa offset sebagai WIB', () {
    // Data lama hasil toIso8601String(): tanpa offset. WAJIB dibaca sebagai
    // wall-clock WIB, bukan jam perangkat.
    final parsed = parseWibStored('2026-11-01T10:00:00.000');
    expect(parsed, isNotNull);
    expect(parsed!.hour, 10);
    expect(parsed.minute, 0);
    expect(parsed.timeZoneOffset, const Duration(hours: 7));
    expect(wibApiDateTime(parsed), '2026-11-01T10:00');
    // Bentuk tanpa detik dan bentuk tanggal saja juga diterima.
    expect(parseWibStored('2026-11-01T10:00')!.hour, 10);
    expect(parseWibStored('2026-11-01')!.hour, 0);
  });

  test('parseWibStored memahami nilai ber-offset', () {
    final dariZ = parseWibStored('2026-11-01T03:00:00.000Z');
    expect(dariZ, isNotNull);
    expect(dariZ!.hour, 10);
    expect(dariZ.timeZoneOffset, const Duration(hours: 7));

    final dariOffset = parseWibStored('2026-11-01T10:00:00.000+07:00');
    expect(dariOffset, isNotNull);
    expect(dariOffset!.hour, 10);
    expect(dariOffset.isAtSameMomentAs(dariZ), isTrue);
  });

  test('round-trip wibIso -> parseWibStored menghasilkan instant yang sama',
      () {
    // Nilai dengan presisi milidetik (batas presisi wibIso).
    final asli = wibFromParts(2026, 11, 1, 10, 0);
    final kembali = parseWibStored(wibIso(asli));
    expect(kembali, isNotNull);
    expect(kembali!.isAtSameMomentAs(asli), isTrue);
    expect(kembali.hour, 10);
    expect(kembali.timeZoneOffset, const Duration(hours: 7));

    // Jam nyata (presisi mikrodetik dipangkas ke milidetik oleh wibIso).
    final sekarang = wibNow();
    final sekarangKembali = parseWibStored(wibIso(sekarang));
    expect(sekarangKembali, isNotNull);
    expect(
      sekarangKembali!.millisecondsSinceEpoch,
      sekarang.millisecondsSinceEpoch,
    );
    expect(sekarangKembali.hour, sekarang.hour);
  });

  test('parseWibStored null untuk input kosong/rusak', () {
    expect(parseWibStored(null), isNull);
    expect(parseWibStored(''), isNull);
    expect(parseWibStored('   '), isNull);
    expect(parseWibStored('bukan tanggal'), isNull);
    expect(parseWibStored('2026-13-01T10:00:00'), isNull);
    expect(parseWibStored('2026-11-01T25:00:00'), isNull);
  });

  test('wibFromParts membangun wall-clock WIB, bukan instant perangkat', () {
    final d = wibFromParts(2026, 11, 1, 10, 30);
    expect(d.year, 2026);
    expect(d.month, 11);
    expect(d.day, 1);
    expect(d.hour, 10);
    expect(d.minute, 30);
    expect(d.timeZoneOffset, const Duration(hours: 7));
    expect(wibDateKey(d), '2026-11-01');
  });

  test('antrean offline mempertahankan instant setelah disimpan dan dimuat',
      () {
    // Regresi inti: payload antrean dulu ditulis tanpa offset, sehingga jam
    // mood/diary/obat bergeser 7 jam saat dibaca di perangkat non-WIB.
    final jadwal = wibFromParts(2026, 11, 1, 10, 0);
    final item = SyncItem(
      id: 'sync_mood_1',
      operation: SyncOperation.moodEntry,
      payload: <String, dynamic>{
        'date': wibIso(jadwal),
        'mood': 'baik',
        'taken_at': wibIso(jadwal),
        'created_at': wibIso(jadwal),
      },
      createdAt: jadwal,
      userId: 'user_pasien_1',
    );

    final restored = SyncItem.fromJson(item.toJson());

    expect(restored.createdAt.isAtSameMomentAs(jadwal), isTrue);
    expect(restored.createdAt.hour, 10);
    expect(restored.userId, 'user_pasien_1');
    expect(parseWibStored(restored.payload['date'] as String)!.hour, 10);
    expect(parseWibStored(restored.payload['taken_at'] as String)!.hour, 10);
    expect(parseWibStored(restored.payload['created_at'] as String)!.hour, 10);
  });
}
