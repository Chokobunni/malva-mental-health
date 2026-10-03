import '../services/malva_api_client.dart';

// ============================================================
// DIREKTORI PROFESIONAL DEMO — cermin data seed backend
// (migrations/007_seed_professionals.sql).
// Dipakai sebagai fallback rapi saat server tidak terjangkau,
// sehingga "Cari Profesional" tidak pernah kosong.
// ============================================================

class DemoProfessional {
  const DemoProfessional({
    required this.entry,
    required this.packages,
    required this.isAvailableToday,
  });

  final BackendDoctorSearchResult entry;
  final List<BackendServicePackage> packages;
  final bool isAvailableToday;

  BackendDoctorProfile toProfile() {
    return BackendDoctorProfile(
      credential: BackendProfessionalCredential(
        id: 'demo-cred-${entry.userId}',
        userId: entry.userId,
        specialization: entry.specialization,
        verificationStatus: 'VERIFIED',
        strNumber: 'STR-${entry.userId}',
        sippNumber: 'SIP-${entry.userId}',
        hospitalName: entry.hospitalName,
        bio: entry.bio,
        isBpjsSupported: entry.isBpjsSupported,
        yearsExperience: entry.yearsExperience,
        addressDetails: entry.addressDetails,
        priceFrom: entry.priceFrom,
      ),
      packages: packages,
    );
  }

  /// Slot contoh Senin-Jumat 09:00-16:00 tiap 30 menit.
  List<BackendDoctorSlot> demoSlotsFor(DateTime date) {
    // Sabtu (6) & Minggu (7): tutup, kecuali id tertentu.
    final weekend = date.weekday >= 6;
    final saturdayOpen =
        entry.userId == 'demo-hafid' || entry.userId == 'demo-rina';
    if (weekend && !(date.weekday == 6 && saturdayOpen)) {
      return const [];
    }
    final endHour = (date.weekday == 6) ? 12 : 16;
    final slots = <BackendDoctorSlot>[];
    for (var h = 9; h < endHour; h++) {
      for (final m in [0, 30]) {
        final label =
            '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
        // Pola ketersediaan deterministik agar stabil.
        final available = (h + (m ~/ 30) + entry.userId.length) % 3 != 0;
        slots.add(BackendDoctorSlot(time: label, available: available));
      }
    }
    return slots;
  }
}

List<BackendServicePackage> _packages(String prefix) => [
      BackendServicePackage(
        id: '$prefix-chat',
        packageSessions: 1,
        packageDurationDays: 1,
        price: 150000,
        label: 'Konsultasi Chat 30 menit',
      ),
      BackendServicePackage(
        id: '$prefix-video',
        packageSessions: 1,
        packageDurationDays: 1,
        price: 250000,
        label: 'Konsultasi Video 45 menit',
      ),
      BackendServicePackage(
        id: '$prefix-paket',
        packageSessions: 4,
        packageDurationDays: 30,
        price: 799000,
        label: 'Paket 4 Sesi Hemat',
      ),
    ];

List<DemoProfessional> demoProfessionals() => [
      DemoProfessional(
        entry: const BackendDoctorSearchResult(
          userId: 'demo-hafid',
          displayName: 'dr. Hafid Algistian, Sp.KJ',
          specialization: 'Sp.KJ',
          legacyCount: 480,
          helpfulnessCount: 3,
          reviewCount: 4,
          yearsExperience: 12,
          isBpjsSupported: true,
          isAvailableToday: true,
          hospitalName: 'RSUD Dr. Soetomo, Surabaya',
          addressDetails: 'Jl. Prof. Dr. Moestopo No. 6-8, Airlangga, Gubeng',
          hospitalLat: -7.2891,
          hospitalLng: 112.7251,
          priceFrom: 180000,
          bio: 'Psikiater dengan 12 tahun pengalaman menangani depresi, '
              'ansietas, dan gangguan tidur. Pendekatan suportif dan berbasis bukti.',
        ),
        packages: _packages('demo-hafid'),
        isAvailableToday: true,
      ),
      DemoProfessional(
        entry: const BackendDoctorSearchResult(
          userId: 'demo-sinta',
          displayName: 'dr. Sinta Maharani, Sp.KJ',
          specialization: 'Sp.KJ',
          legacyCount: 320,
          helpfulnessCount: 3,
          reviewCount: 4,
          yearsExperience: 9,
          isBpjsSupported: false,
          isAvailableToday: false,
          hospitalName: 'RS Universitas Airlangga, Surabaya',
          addressDetails: 'Jl. Mayjend. Prof. Dr. Moestopo No. 44, Airlangga',
          hospitalLat: -7.2757,
          hospitalLng: 112.7166,
          priceFrom: 220000,
          bio: 'Psikiater fokus pada kesehatan jiwa perempuan, trauma, dan '
              'pemulihan pasca krisis. Ramah dan terbuka untuk pasien baru.',
        ),
        packages: _packages('demo-sinta'),
        isAvailableToday: false,
      ),
      DemoProfessional(
        entry: const BackendDoctorSearchResult(
          userId: 'demo-rina',
          displayName: 'Rina Prasetyo, M.Psi',
          specialization: 'M.Psi',
          legacyCount: 210,
          helpfulnessCount: 3,
          reviewCount: 4,
          yearsExperience: 7,
          isBpjsSupported: true,
          isAvailableToday: true,
          hospitalName: 'Puskesmas Kedungdoro, Surabaya',
          addressDetails: 'Jl. Kedungdoro No. 62, Tegalsari',
          hospitalLat: -7.2683,
          hospitalLng: 112.7424,
          priceFrom: 120000,
          bio:
              'Psikolog klinis berpengalaman dalam CBT, manajemen stres kerja, '
              'dan konseling remaja. Praktik di faskes BPJS.',
        ),
        packages: _packages('demo-rina'),
        isAvailableToday: true,
      ),
      DemoProfessional(
        entry: const BackendDoctorSearchResult(
          userId: 'demo-andi',
          displayName: 'Andi Wijaya, M.Psi',
          specialization: 'M.Psi',
          legacyCount: 95,
          helpfulnessCount: 3,
          reviewCount: 4,
          yearsExperience: 5,
          isBpjsSupported: true,
          isAvailableToday: false,
          hospitalName: 'RS Haji Surabaya',
          addressDetails: 'Jl. Raya Genteng Kali No. 97-99, Genteng',
          hospitalLat: -7.3246,
          hospitalLng: 112.7481,
          priceFrom: 150000,
          bio: 'Psikolog dan konselor dengan pendekatan humanistik. Membantu '
              'isu relasi, burnout, dan pengembangan diri.',
        ),
        packages: _packages('demo-andi'),
        isAvailableToday: false,
      ),
    ];

DemoProfessional? findDemoProfessional(String userId) {
  for (final demo in demoProfessionals()) {
    if (demo.entry.userId == userId) return demo;
  }
  return null;
}
