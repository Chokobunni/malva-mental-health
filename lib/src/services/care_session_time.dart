/// Helper waktu MURNI (tanpa I/O, tanpa `DateTime.now()`) untuk menentukan
/// apakah sebuah care session sedang "berjalan" pada suatu instant.
///
/// Dipisah ke berkas sendiri agar bisa diuji unit tanpa Flutter/HTTP, dan agar
/// aturan jendela waktu punya SATU sumber kebenaran. Nilai `now` dan
/// `scheduledAt` dioper oleh pemanggil — pemanggil wajib memakai `ServerClock.now()` /
/// `parseWibStored()` (WIB) untuk nilai bisnis, bukan `DateTime.now()`.
library;

/// Pintu "sesi berjalan" dibuka 10 menit sebelum jadwal — konsisten dengan
/// `BackendCareSession.joinOpensBefore`.
const Duration careSessionJoinOpensBefore = Duration(minutes: 10);

/// Jendela ditutup TEPAT saat durasi sesi berakhir — tanpa kelonggaran tambahan.
/// Chat/Meet harus tertutup begitu waktu sesi habis. Konsisten dengan
/// `BackendCareSession.joinClosesAfterEnd` dan backend `inSessionWindow`.
const Duration careSessionJoinClosesAfterEnd = Duration.zero;

/// `true` bila [now] berada di dalam jendela "sesi berjalan" untuk sesi yang
/// dijadwalkan pada [scheduledAt] dengan durasi [durationMinutes].
///
/// Batas pembukaan inklusif; batas penutupan eksklusif:
///
/// ```
/// scheduledAt - 10 menit  <=  now  <  scheduledAt + durationMinutes
/// ```
///
/// [durationMinutes] negatif diperlakukan sebagai 0 agar input tak wajar tidak
/// menghasilkan jendela terbalik.
bool isCareSessionOngoing(
  DateTime now,
  DateTime scheduledAt,
  int durationMinutes,
) {
  final safeDuration = durationMinutes < 0 ? 0 : durationMinutes;
  final opensAt = scheduledAt.subtract(careSessionJoinOpensBefore);
  final closesAt = scheduledAt
      .add(Duration(minutes: safeDuration))
      .add(careSessionJoinClosesAfterEnd);
  return !now.isBefore(opensAt) && now.isBefore(closesAt);
}
