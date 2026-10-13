import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models.dart';
import '../../providers/providers.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';
import '../../widgets/professional_avatar.dart';
import 'booking_detail_screen.dart';
import 'package_booking_screen.dart';

// ============================================================
// PROFESSIONAL INFO:
//   Header nama + rating riil + spesialisasi
//   Intro video (hanya bila profesional mengisi URL)
//   Harga per sesi dari tarif profesional + faskes + jarak + jadwal
//   BPJS badge
//   Dropdown Profile & Speciality
//   Reviews riil dari DB (atau "Belum ada ulasan")
//   Choose Your Support Level:
//     - Quick Consult (One-Time)
//     - Continuous Package (4 sesi / 6 minggu)
//   CTA: Book Session / Beli Paket 4 Sesi
// ============================================================

class DoctorProfileScreen extends ConsumerStatefulWidget {
  const DoctorProfileScreen({
    super.key,
    required this.doctorUserId,
    this.doctorName,
    this.session,
    this.apiClient,
  });

  final String doctorUserId;
  final String? doctorName;
  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<DoctorProfileScreen> createState() =>
      _DoctorProfileScreenState();
}

class _DoctorProfileScreenState extends ConsumerState<DoctorProfileScreen> {
  BackendDoctorProfile? _profile;
  List<BackendAvailabilityDay> _availability = const [];
  BackendCarePackage? _activePackage;
  bool _isLoading = true;
  Object? _error;
  bool _profileExpanded = true;
  bool _specialityExpanded = true;
  // 'quick' | 'continuous'
  String _selectedPlan = 'quick';
  String _serviceType = 'chat';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final MalvaApiClient apiClient =
        widget.apiClient ?? ref.read(apiClientProvider);
    final rawToken = widget.session?.accessToken;
    final accessToken =
        (rawToken == null || rawToken.isEmpty) ? null : rawToken;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final profile = await apiClient.getDoctorProfile(
        accessToken: accessToken,
        userId: widget.doctorUserId,
      );
      List<BackendAvailabilityDay> availability = const [];
      try {
        availability = await apiClient.getDoctorAvailability(
          accessToken: accessToken,
          userId: widget.doctorUserId,
        );
      } on Object catch (_) {
        // Ketersediaan opsional — profil tetap tampil.
      }
      BackendCarePackage? activePackage;
      if (accessToken != null) {
        try {
          final pkgs =
              await apiClient.listCarePackages(accessToken: accessToken);
          for (final p in pkgs) {
            if (p.professionalId == widget.doctorUserId && p.isActive) {
              activePackage = p;
              break;
            }
          }
        } on Object catch (_) {
          // Paket aktif opsional.
        }
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _availability = availability;
        _activePackage = activePackage;
        _isLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cred = _profile?.credential;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Psychiatrist Info'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: FriendlyErrorCard(error: _error!, onRetry: _load),
                  ),
                )
              : cred == null
                  ? const Center(child: Text('Profil tidak ditemukan.'))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(
                        padding: const EdgeInsets.all(18),
                        children: [
                          // ===== HEADER: nama + rating riil + spesialisasi =====
                          Builder(builder: (context) {
                            final reviews = _profile?.reviews ??
                                const BackendDoctorReviews();
                            final ratingLabel = reviews.reviewCount > 0
                                ? '${reviews.averageStars.toStringAsFixed(1)} (${reviews.reviewCount})'
                                : 'Belum ada ulasan';
                            final specLabel = cred.specialization == 'Sp.KJ'
                                ? 'Psikiater (Sp.KJ)'
                                : 'Psikolog Klinis (M.Psi)';
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ProfessionalAvatar(
                                  displayName: _displayName,
                                  radius: 32,
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _displayName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 16.5),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          const Icon(Icons.star_rounded,
                                              size: 17,
                                              color: MalvaColors.amber),
                                          const SizedBox(width: 3),
                                          Text(
                                            ratingLabel,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 13),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        specLabel,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                                color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            );
                          }),
                          const SizedBox(height: 14),

                          // ===== INTRO VIDEO (hanya bila ada URL) =====
                          if (cred.videoIntroUrl.trim().isNotEmpty) ...[
                            SoftCard(
                              onTap: () =>
                                  _openIntroVideo(cred.videoIntroUrl),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 18,
                                    backgroundColor: MalvaColors.seed
                                        .withValues(alpha: 0.12),
                                    child: const Icon(
                                        Icons.play_circle_fill_rounded,
                                        color: MalvaColors.seed),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      "Watch ${_shortName}'s Intro Video",
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 13.5),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],

                          // ===== HARGA PER SESI + FASKES + JADWAL =====
                          _PriceRow(label: 'Chat session', price: _chatPrice()),
                          _PriceRow(
                              label: 'Video session', price: _videoPrice()),
                          _PriceRow(
                              label: 'Paket 4 sesi / 6 minggu',
                              price: _packagePrice()),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(Icons.local_hospital_rounded,
                                  size: 15, color: MalvaColors.seed),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  _faskesDistanceLabel(cred),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          if (_bookableDays.isNotEmpty)
                            Text(
                              'Tersedia: ${_bookableDays.take(3).map((d) => _shortDate(d.date)).join(', ')}',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: Colors.black54),
                            ),
                          const SizedBox(height: 8),
                          if (cred.isBpjsSupported)
                            const Row(
                              children: [
                                Icon(Icons.check_circle_rounded,
                                    size: 18, color: MalvaColors.mint),
                                SizedBox(width: 6),
                                Text(
                                  'BPJS',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 13),
                                ),
                              ],
                            ),
                          const SizedBox(height: 14),

                          // ===== DROPDOWN: Profile =====
                          _DropdownCard(
                            label: 'Profile',
                            expanded: _profileExpanded,
                            onToggle: () => setState(
                                () => _profileExpanded = !_profileExpanded),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _InfoLine(
                                    label: 'Pengalaman',
                                    value:
                                        '${cred.yearsExperience} tahun praktik'),
                                _InfoLine(
                                    label: 'Faskes',
                                    value: cred.hospitalName.isEmpty
                                        ? '-'
                                        : cred.hospitalName),
                                if (cred.addressDetails.isNotEmpty)
                                  _InfoLine(
                                      label: 'Alamat',
                                      value: cred.addressDetails),
                                if (cred.bio.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Text(
                                      cred.bio,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                          // ===== DROPDOWN: Speciality =====
                          _DropdownCard(
                            label: 'Speciality',
                            expanded: _specialityExpanded,
                            onToggle: () => setState(() =>
                                _specialityExpanded = !_specialityExpanded),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _InfoLine(
                                    label: 'Spesialisasi',
                                    value: cred.specialization.isEmpty
                                        ? 'Profesional'
                                        : (cred.specialization == 'Sp.KJ'
                                            ? 'Psikiater (Sp.KJ)'
                                            : 'Psikolog Klinis (M.Psi)')),
                                _InfoLine(
                                    label: 'Lisensi',
                                    value:
                                        'STR ${cred.strNumber.isEmpty ? '-' : cred.strNumber}'),
                                _InfoLine(
                                    label: 'SIP',
                                    value:
                                        '${cred.sippNumber.isEmpty ? '-' : cred.sippNumber}'),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // ===== REVIEWS (riil dari DB) =====
                          Builder(builder: (context) {
                            final reviews = _profile?.reviews ??
                                const BackendDoctorReviews();
                            if (reviews.reviews.isEmpty) {
                              return const EmptyState(
                                icon: Icons.rate_review_outlined,
                                title: 'Belum ada ulasan',
                                subtitle:
                                    'Jadilah yang pertama memberi ulasan setelah sesi selesai.',
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SectionLabel('Reviews'),
                                for (var i = 0;
                                    i < reviews.reviews.length;
                                    i++) ...[
                                  _ReviewCard(
                                    name: reviews
                                        .reviews[i].patientName,
                                    text: reviews.reviews[i].reviewText
                                            .isEmpty
                                        ? 'Membantu.'
                                        : reviews
                                            .reviews[i].reviewText,
                                    date: _reviewDate(
                                        reviews.reviews[i].createdAt),
                                    stars: reviews.reviews[i].stars,
                                  ),
                                  if (i < reviews.reviews.length - 1)
                                    const SizedBox(height: 8),
                                ],
                              ],
                            );
                          }),
                          const SizedBox(height: 16),

                          // ===== PAKET AKTIF (bila ada) =====
                          if (_activePackage != null)
                            SoftCard(
                              color:
                                  MalvaColors.mint.withValues(alpha: 0.10),
                              child: Row(
                                children: [
                                  const Icon(Icons.card_membership_rounded,
                                      color: MalvaColors.mint),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Paket aktif: ${_activePackage!.remainingSessions}/${_activePackage!.totalSessions} sesi tersisa',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (_activePackage != null)
                            const SizedBox(height: 12),

                          // ===== CHOOSE YOUR SUPPORT LEVEL =====
                          Text(
                            'Choose Your Support Level',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Layanan ini untuk dukungan berkelanjutan, bukan darurat. Jika krisis, hubungi 112.',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: Colors.black54),
                          ),
                          const SizedBox(height: 14),

                          // ===== OPSI 1: QUICK CONSULT (ONE-TIME) =====
                          _SupportPlanCard(
                            selected: _selectedPlan == 'quick',
                            onSelect: () =>
                                setState(() => _selectedPlan = 'quick'),
                            title: 'Quick Consult (One-Time)',
                            subtitle: _serviceType == 'video'
                                ? 'Sesi video sekali pertemuan'
                                : 'Sesi chat sekali pertemuan',
                            price: _chatPrice() <= 0 && _videoPrice() <= 0
                                ? 'Harga belum diatur'
                                : 'Rp. ${_rupiah(_serviceType == 'video' ? _videoPrice() : _chatPrice())} / sesi',
                            featureIcon: Icons.payments_rounded,
                            features: [
                              (
                                _serviceType == 'video'
                                    ? 'Sesi video terjadwal'
                                    : 'Sesi chat terjadwal',
                                Icons.record_voice_over_rounded
                              ),
                              (
                                'Jadwal sesuai ketersediaan profesional',
                                Icons.event_available_rounded
                              ),
                              (
                                'Tanpa data sharing & tanpa follow-up',
                                Icons.cancel_rounded
                              ),
                            ],
                            scheduleChips: const ['Chat', 'Video'],
                            onChipSelect: (chip) => setState(() =>
                                _serviceType = chip.toLowerCase()),
                            selectedChip:
                                _serviceType == 'video' ? 'Video' : 'Chat',
                            scheduleLines: _scheduleLines(),
                          ),
                          const SizedBox(height: 12),

                          // ===== OPSI 2: PAKET CONTINUOUS (4 SESI / 6 MINGGU) =====
                          _SupportPlanCard(
                            selected: _selectedPlan == 'continuous',
                            onSelect: _packagePrice() > 0
                                ? () => setState(
                                    () => _selectedPlan = 'continuous')
                                : () => ScaffoldMessenger.of(context)
                                    .showSnackBar(const SnackBar(
                                        content: Text(
                                            'Profesional belum mengatur harga paket.'))),
                            title: 'Continuous Package (Best Value)',
                            subtitle:
                                '4 sesi pertemuan, berlaku 6 minggu',
                            badge: (
                              '4 Sesi • 6 Minggu',
                              Icons.handshake_rounded
                            ),
                            price: _packagePrice() > 0
                                ? 'Rp. ${_rupiah(_packagePrice())} / paket'
                                : 'Harga belum diatur',
                            featureIcon: Icons.bar_chart_rounded,
                            features: const [
                              (
                                '4 sesi chat/video terjadwal',
                                Icons.event_available_rounded
                              ),
                              (
                                'Kirim diary, goals, assessment & worksheet (selama paket aktif)',
                                Icons.send_rounded
                              ),
                              (
                                'Profesional membahas kiriman saat sesi (tanpa kewajiban balas di luar sesi)',
                                Icons.forum_rounded
                              ),
                              (
                                'Tidak hadir = sesi hangus • Profesional batal = kredit kembali / reschedule',
                                Icons.info_outline_rounded
                              ),
                            ],
                            footnote:
                                'Sisa sesi setelah 6 minggu hangus. Tanpa perpanjangan otomatis.',
                            quota: 'Termasuk monitoring data selama paket aktif',
                          ),
                          const SizedBox(height: 16),

                          // ===== CTA: 1 tombol per plan terpilih =====
                          FilledButton.icon(
                            onPressed: _proceed,
                            style: FilledButton.styleFrom(
                              minimumSize: const Size.fromHeight(52),
                            ),
                            icon: const Icon(Icons.arrow_forward_rounded),
                            label: Text(_selectedPlan == 'continuous'
                                ? 'Beli Paket 4 Sesi'
                                : 'Book Session'),
                          ),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
    );
  }

  // ---------- Helpers ----------

  String get _displayName {
    final hint = widget.doctorName?.trim() ?? '';
    if (hint.isNotEmpty) return hint;
    return 'Profesional';
  }

  String get _shortName {
    final parts = _displayName.split(' ');
    final name = parts
        .skip(1)
        .takeWhile((p) => !p.contains(','))
        .toList(growable: false);
    return name.isEmpty ? _displayName : name.first;
  }

  /// Harga quick consult dari tarif profesional (tanpa angka dummy).
  /// 0 = profesional belum mengatur harga.
  int _chatPrice() => _profile?.pricing.quickChatPrice ?? 0;

  int _videoPrice() => _profile?.pricing.quickVideoPrice ?? 0;

  int _packagePrice() => _profile?.pricing.packagePrice ?? 0;

  String _faskesDistanceLabel(BackendProfessionalCredential cred) {
    final faskes = cred.hospitalName.isEmpty
        ? 'Faskes tidak dicantumkan'
        : cred.hospitalName;
    final pos = ref.watch(patientLocationProvider).position;
    final km = distanceKmBetween(
      fromLat: pos?.latitude,
      fromLng: pos?.longitude,
      toLat: cred.hospitalLat,
      toLng: cred.hospitalLng,
    );
    if (km == null) return faskes;
    return '$faskes, ${km.toStringAsFixed(1)} km';
  }

  static const _dayNamesId = [
    '',
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu',
  ];

  /// Ringkasan jadwal mingguan profesional dari server.
  List<String> _scheduleLines() {
    final schedules = _profile?.schedules ?? const [];
    if (schedules.isEmpty) {
      return const ['Jadwal belum diatur profesional'];
    }
    final byDay = <int, List<BackendProfessionalSchedule>>{};
    for (final s in schedules) {
      (byDay[s.dayOfWeek] ??= []).add(s);
    }
    final days = byDay.keys.toList()..sort();
    return [
      for (final d in days)
        '${_dayNamesId[d]}: ${byDay[d]!.map((s) => '${s.startTime}–${s.endTime}').join(', ')}',
    ];
  }

  /// Hari-hari ke depan yang bisa di-booking (dari availability server).
  List<BackendAvailabilityDay> get _bookableDays =>
      _availability.where((d) => d.bookable).toList(growable: false);

  void _proceed() {
    final cred = _profile?.credential;
    if (cred == null) return;
    if (_selectedPlan == 'continuous') {
      if (_packagePrice() <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Profesional belum mengatur harga paket. Pilih Quick Consult.')),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PackageBookingScreen(
            doctorUserId: widget.doctorUserId,
            doctorName: _displayName,
            price: _packagePrice(),
            session: widget.session,
            apiClient: widget.apiClient,
          ),
        ),
      );
    } else {
      final price = _serviceType == 'video' ? _videoPrice() : _chatPrice();
      if (price <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Profesional belum mengatur harga sesi ini.')),
        );
        return;
      }
      _openBooking(context, price);
    }
  }

  static String _reviewDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final d = DateTime.tryParse(iso)?.toLocal();
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year}';
  }

  static String _shortDate(String yyyyMmDd) {
    final d = DateTime.tryParse(yyyyMmDd);
    if (d == null) return yyyyMmDd;
    const months = [
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
      'Des'
    ];
    return '${d.day} ${months[d.month - 1]}';
  }

  void _openBooking(BuildContext context, int price) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingDetailScreen(
          doctorUserId: widget.doctorUserId,
          doctorName: _displayName,
          serviceType: _serviceType,
          expectedPrice: price,
          session: widget.session,
          apiClient: widget.apiClient,
        ),
      ),
    );
  }

  Future<void> _openIntroVideo(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tidak bisa membuka video intro.')),
      );
    }
  }

  static String _rupiah(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final pos = s.length - i;
      buf.write(s[i]);
      if (pos > 1 && pos % 3 == 1) buf.write('.');
    }
    return buf.toString();
  }
}

// ============================================================
// WIDGETS LOKAL
// ============================================================

class _PriceRow extends StatelessWidget {
  const _PriceRow({required this.label, required this.price});

  final String label;
  final int price;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Text(
        '$label : Rp. ${_rupiah(price)}',
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5),
      ),
    );
  }

  static String _rupiah(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final pos = s.length - i;
      buf.write(s[i]);
      if (pos > 1 && pos % 3 == 1) buf.write('.');
    }
    return buf.toString();
  }
}

class _DropdownCard extends StatelessWidget {
  const _DropdownCard({
    required this.label,
    required this.expanded,
    required this.onToggle,
    required this.child,
  });

  final String label;
  final bool expanded;
  final VoidCallback onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 14.5)),
                  ),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: MalvaColors.seed,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(bottom: 12, left: 2, right: 2),
              child: child,
            ),
        ],
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: Text(label,
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                    color: Colors.black54)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

class _ReviewCard extends StatelessWidget {
  const _ReviewCard({
    required this.name,
    required this.text,
    required this.date,
    required this.stars,
  });

  final String name;
  final String text;
  final String date;
  final int stars;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: MalvaColors.seed.withValues(alpha: 0.12),
                child: Text(
                  name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                  style: const TextStyle(
                      color: MalvaColors.seed,
                      fontWeight: FontWeight.w900,
                      fontSize: 12),
                ),
              ),
              const SizedBox(width: 8),
              Text(name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 13)),
              const Spacer(),
              for (var i = 0; i < 5; i++)
                Icon(
                    i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
                    size: 14,
                    color: MalvaColors.amber),
            ],
          ),
          const SizedBox(height: 6),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
          if (date.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                date,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.black54),
              ),
            ),
        ],
      ),
    );
  }
}

/// Kartu pilihan support level — layout Figma Group 333/334/336/337/338/479.
class _SupportPlanCard extends StatelessWidget {
  const _SupportPlanCard({
    required this.selected,
    required this.onSelect,
    required this.title,
    required this.price,
    required this.features,
    required this.featureIcon,
    this.subtitle,
    this.badge,
    this.footnote,
    this.quota,
    this.scheduleChips,
    this.selectedChip,
    this.onChipSelect,
    this.scheduleLines,
  });

  final bool selected;
  final VoidCallback onSelect;
  final String title;
  final String? subtitle;
  final String price;
  final (String, IconData)? badge;
  final List<(String, IconData)> features;
  final IconData featureIcon;
  final String? footnote;
  final String? quota;
  final List<String>? scheduleChips;
  final String? selectedChip;
  final ValueChanged<String>? onChipSelect;
  final List<String>? scheduleLines;

  @override
  Widget build(BuildContext context) {
    final borderColor =
        selected ? MalvaColors.seed : MalvaColors.seed.withValues(alpha: 0.18);
    return InkWell(
      onTap: onSelect,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? MalvaColors.seed.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: borderColor,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 14.5)),
                ),
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? MalvaColors.seed : Colors.black26,
                ),
              ],
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(subtitle!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.black54)),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(featureIcon, size: 16, color: MalvaColors.seed),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(price,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 14)),
                ),
              ],
            ),
            if (badge != null) ...[
              const SizedBox(height: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: MalvaColors.mint.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(badge!.$2, size: 15, color: MalvaColors.mint),
                    const SizedBox(width: 6),
                    Text(
                      badge!.$1,
                      style: const TextStyle(
                          color: MalvaColors.mint,
                          fontWeight: FontWeight.w800,
                          fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 10),
            for (final (text, icon) in features)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(icon,
                        size: 16,
                        color: text.startsWith('No')
                            ? MalvaColors.danger
                            : MalvaColors.seed),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(text,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12.5)),
                    ),
                  ],
                ),
              ),
            if (scheduleChips != null && scheduleChips!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                children: [
                  for (final chip in scheduleChips!)
                    InkWell(
                      onTap: onChipSelect == null
                          ? null
                          : () => onChipSelect!(chip),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: selectedChip == chip
                              ? MalvaColors.seed
                              : MalvaColors.seed.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(999),
                          border: selectedChip == chip
                              ? null
                              : Border.all(
                                  color: MalvaColors.seed
                                      .withValues(alpha: 0.25)),
                        ),
                        child: Text(chip,
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12.5,
                                color: selectedChip == chip
                                    ? Colors.white
                                    : null)),
                      ),
                    ),
                ],
              ),
            ],
            if (scheduleLines != null && scheduleLines!.isNotEmpty) ...[
              const SizedBox(height: 8),
              for (final line in scheduleLines!)
                Text(line,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.black54)),
            ],
            if (footnote != null) ...[
              const SizedBox(height: 6),
              Text(footnote!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.black54)),
            ],
            if (quota != null) ...[
              const SizedBox(height: 2),
              Text(quota!,
                  style: const TextStyle(
                      color: MalvaColors.orchid,
                      fontWeight: FontWeight.w800,
                      fontSize: 12)),
            ],
          ],
        ),
      ),
    );
  }
}
