import 'package:url_launcher/url_launcher.dart';

import '../../services/malva_api_client.dart';
import '../../time/wib.dart';

// ============================================================
// KATALOG PROFESIONAL & MYCARE WEB — LAPISAN DATA
// ============================================================
//
// Berisi aturan tampilan yang murni (tanpa UI): pengelompokan profesi, daftar
// tanggal 7 hari ke depan (WIB), label status, opsi layanan + harga, dan
// pembuka tautan eksternal. Semua waktu memakai helper `time/wib.dart`.

/// Kelompok profesi untuk section katalog.
enum WebDoctorGroup { psychiatrist, psychologist, other }

extension WebDoctorGroupInfo on WebDoctorGroup {
  String get label => switch (this) {
        WebDoctorGroup.psychiatrist => 'Psikiater',
        WebDoctorGroup.psychologist => 'Psikolog',
        WebDoctorGroup.other => 'Lainnya',
      };
}

/// Menentukan kelompok dari teks spesialisasi bebas.
///
/// Aturan disengaja longgar (mengikuti data nyata `professional_credentials`):
/// apa pun yang menyebut KJ/psikiater/psikiatri dianggap psikiater, yang
/// menyebut Psi/psikolog dianggap psikolog, sisanya "Lainnya" agar tidak ada
/// profesional yang hilang dari katalog.
WebDoctorGroup webDoctorGroupOf(String specialization) {
  final value = specialization.toLowerCase();
  if (value.contains('kj') ||
      value.contains('psikiater') ||
      value.contains('psikiatri')) {
    return WebDoctorGroup.psychiatrist;
  }
  if (value.contains('psi') || value.contains('psikolog')) {
    return WebDoctorGroup.psychologist;
  }
  return WebDoctorGroup.other;
}

/// Satu section katalog (kelompok + anggotanya).
class WebDoctorSection {
  const WebDoctorSection({required this.group, required this.doctors});

  final WebDoctorGroup group;
  final List<BackendDoctorSearchResult> doctors;

  String get label => group.label;
  int get count => doctors.length;
}

/// Mengelompokkan hasil pencarian dengan urutan tetap: psikiater, psikolog,
/// lalu lainnya. Kelompok kosong tidak ditampilkan.
List<WebDoctorSection> webGroupDoctors(
  List<BackendDoctorSearchResult> doctors,
) {
  final buckets = <WebDoctorGroup, List<BackendDoctorSearchResult>>{
    WebDoctorGroup.psychiatrist: <BackendDoctorSearchResult>[],
    WebDoctorGroup.psychologist: <BackendDoctorSearchResult>[],
    WebDoctorGroup.other: <BackendDoctorSearchResult>[],
  };
  for (final doctor in doctors) {
    buckets[webDoctorGroupOf(doctor.specialization)]!.add(doctor);
  }
  return <WebDoctorSection>[
    for (final group in WebDoctorGroup.values)
      if (buckets[group]!.isNotEmpty)
        WebDoctorSection(group: group, doctors: buckets[group]!),
  ];
}

/// Kunci tanggal `yyyy-MM-dd` untuk 7 hari ke depan (termasuk hari ini), WIB.
List<String> webNextSevenDayKeys() {
  final today = wibNow();
  return <String>[
    for (var i = 0; i < 7; i++) wibDateKey(today.add(Duration(days: i))),
  ];
}

const List<String> _webDayNames = <String>[
  'Sen',
  'Sel',
  'Rab',
  'Kam',
  'Jum',
  'Sab',
  'Min',
];

const List<String> _webMonthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

/// Label singkat tanggal `yyyy-MM-dd` → `Sen, 3 Nov`.
///
/// Hanya mem-parse string tanggal (tanpa membaca jam perangkat), sehingga
/// hasilnya sama di zona waktu mana pun.
String webShortDateLabel(String dateKey) {
  final parsed = DateTime.tryParse(dateKey);
  if (parsed == null) return dateKey;
  final day = _webDayNames[(parsed.weekday - 1).clamp(0, 6)];
  final month = _webMonthNames[(parsed.month - 1).clamp(0, 11)];
  return '$day, ${parsed.day} $month';
}

/// True bila [dateKey] adalah hari ini (WIB).
bool webIsToday(String dateKey) => dateKey == wibDateKey(wibNow());

/// Label jenis sesi.
String webSessionTypeLabel(String sessionType) =>
    switch (sessionType.toLowerCase()) {
      'video' => 'Video',
      'chat' => 'Chat',
      'package' || 'package_session' => 'Paket',
      _ => sessionType.isEmpty ? '—' : sessionType,
    };

/// Label status sesi.
String webSessionStatusLabel(String status) => switch (status.toLowerCase()) {
      'scheduled' => 'Terjadwal',
      'completed' => 'Selesai',
      'cancelled' || 'cancelled_by_patient' => 'Dibatalkan pasien',
      'cancelled_by_professional' => 'Dibatalkan profesional',
      'pending' => 'Menunggu',
      'ongoing' => 'Berlangsung',
      'no_show' => 'Tidak hadir',
      _ => status.isEmpty ? '—' : status,
    };

/// Label status paket perawatan.
String webCarePackageStatusLabel(String status) =>
    switch (status.toLowerCase()) {
      'pending_payment' => 'Menunggu pembayaran',
      'active' => 'Aktif',
      'expired' => 'Kedaluwarsa',
      'completed' => 'Selesai',
      'cancelled' => 'Dibatalkan',
      _ => status.isEmpty ? '—' : status,
    };

/// Satu opsi layanan pada langkah 1 booking.
class WebServiceOption {
  const WebServiceOption({
    required this.id,
    required this.label,
    required this.description,
    required this.price,
    required this.durationMinutes,
    required this.serviceType,
    required this.sessionType,
    this.isPackage = false,
  });

  /// `quick_chat` | `quick_video` | `package`.
  final String id;
  final String label;
  final String description;
  final int price;
  final int durationMinutes;

  /// Nilai `service_type` untuk `POST /v1/bookings` (sama dengan mobile).
  final String serviceType;
  final String sessionType;
  final bool isPackage;
}

/// Opsi layanan + harga dari `GET /v1/professionals/{id}/pricing`.
List<WebServiceOption> webServiceOptions(BackendProfessionalPricing pricing) {
  return <WebServiceOption>[
    WebServiceOption(
      id: 'quick_video',
      label: 'Video cepat',
      description: 'Konsultasi tatap muka video, 1 jam.',
      price: pricing.quickVideoPrice,
      durationMinutes: 60,
      serviceType: 'quick_consult_video',
      sessionType: 'video',
    ),
    WebServiceOption(
      id: 'package',
      label: 'Paket perawatan',
      description:
          '4 sesi video, masing-masing 1 jam, dengan profesional yang sama.',
      price: pricing.packagePrice,
      durationMinutes: 60,
      serviceType: 'care_package',
      sessionType: 'video',
      isPackage: true,
    ),
  ];
}

/// Membuka tautan eksternal (halaman pembayaran Midtrans, dsb).
///
/// Mengembalikan `false` bila tautan kosong/tidak valid atau browser menolak.
/// Tautan TIDAK pernah ditampilkan mentah ke pengguna (bisa memuat token).
Future<bool> openWebExternalUrl(String url) async {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return false;
  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return false;
  if (uri.scheme != 'https' && uri.scheme != 'http') return false;
  try {
    return await launchUrl(uri, mode: LaunchMode.externalApplication);
  } on Object {
    return false;
  }
}

/// True bila server menolak booking video karena link Meet belum aktif.
///
/// Kondisi ini bukan kegagalan pengguna: akun Google profesional belum siap.
/// UI wajib menampilkan penjelasan, bukan pesan teknis.
bool webIsMeetNotReady(Object error) {
  if (error is! MalvaApiException) return false;
  final code = (error.code ?? '').toLowerCase();
  if (code.contains('meet_belum_aktif') || code.contains('meet')) return true;
  final message = error.message.toLowerCase();
  return message.contains('meet') &&
      (message.contains('belum') || message.contains('aktif'));
}

/// Pesan ramah untuk kegagalan booking/pembayaran.
String webBookingErrorMessage(Object error) {
  if (webIsMeetNotReady(error)) {
    return 'Video call belum bisa dijadwalkan karena akun Google profesional '
        'belum aktif. Hubungi profesional untuk menyiapkan video call.';
  }
  return error is MalvaApiException
      ? error.message
      : 'Terjadi kendala saat memproses booking. Silakan coba lagi.';
}
