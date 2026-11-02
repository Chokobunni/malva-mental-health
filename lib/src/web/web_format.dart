import '../time/wib.dart';

/// Pemformatan nilai untuk dashboard admin web.
///
/// Semua waktu memakai WIB lewat helper `time/wib.dart` — tidak ada
/// `DateTime.now()` maupun `.toLocal()` di sini (aturan WIB-only repo).

/// Format rupiah utuh tanpa desimal: `Rp1.234.567`.
///
/// Nominal backend selalu bilangan bulat rupiah (int64), jadi tidak ada
/// pembulatan yang perlu dijelaskan ke pengguna.
String formatRupiah(num value) {
  final rounded = value.round();
  final negative = rounded < 0;
  final digits = rounded.abs().toString();
  final buffer = StringBuffer();
  for (int i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
    buffer.write(digits[i]);
  }
  return '${negative ? '-' : ''}Rp$buffer';
}

/// Waktu WIB `dd/MM/yyyy HH:mm`, atau `—` bila nil.
String formatWibDateTimeOrDash(DateTime? value) =>
    value == null ? '—' : formatWibDateTime(value);

/// Tanggal WIB `dd/MM/yyyy`, atau `—` bila nil.
String formatWibDateOrDash(DateTime? value) =>
    value == null ? '—' : formatWibDate(value);

/// Tanggal dari date picker (wall-clock) → `yyyy-MM-dd` untuk query API.
///
/// Picker menghasilkan wall-clock, bukan instant; memakai komponen tahun/
/// bulan/tanggal apa adanya mencegah tanggal bergeser di perangkat non-WIB.
String wibDateKeyFromPicker(DateTime value) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

/// Label Bahasa Indonesia untuk status pembayaran.
String paymentStatusLabel(String status) => switch (status.toLowerCase()) {
      'paid' => 'Lunas',
      'pending' => 'Menunggu',
      'failed' => 'Gagal',
      'refunded' => 'Refund',
      'cancelled' => 'Dibatalkan',
      _ => status.isEmpty ? '—' : status,
    };

/// Label Bahasa Indonesia untuk peran pengguna.
String userRoleLabel(String role) => switch (role.toLowerCase()) {
      'patient' => 'Pasien',
      'professional' => 'Profesional',
      'admin' => 'Admin',
      _ => role,
    };

/// Label jenis sesi (`quick_chat` / `quick_video` / paket).
String sessionTypeLabel(String type) => switch (type.toLowerCase()) {
      'quick_chat' => 'Chat cepat',
      'quick_video' => 'Video cepat',
      'package' => 'Paket',
      _ => type.isEmpty ? '—' : type,
    };
