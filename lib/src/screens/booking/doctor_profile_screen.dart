import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models.dart';
import '../../professional_role.dart';
import '../../providers/providers.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../time/wib.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';
import '../../widgets/professional_avatar.dart';
import '../../widgets/professional_availability_summary.dart';
import '../../widgets/doctor_review_actions.dart';
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
  BackendCarePackage? _activePackage;
  bool _isLoading = true;
  Object? _error;
  bool _profileExpanded = true;
  bool _specialityExpanded = true;
  // 'quick' | 'continuous'
  String _selectedPlan = 'quick';
  String? _selectedMethod;
  String get _quickMethod =>
      _selectedMethod ?? (_chatPrice() > 0 ? 'chat' : 'video');
  int get _selectedPrice => _selectedPlan == 'continuous'
      ? _packagePrice()
      : _quickMethod == 'chat'
          ? _chatPrice()
          : _videoPrice();

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Memuat profil profesional. [silent] dipakai saat penyegaran otomatis
  /// (event realtime) agar tidak menampilkan indikator loading.
  Future<void> _load({bool silent = false}) async {
    final MalvaApiClient apiClient =
        widget.apiClient ?? ref.read(apiClientProvider);
    final rawToken =
        (widget.session ?? ref.read(currentSessionProvider))?.accessToken;
    final accessToken =
        (rawToken == null || rawToken.isEmpty) ? null : rawToken;
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    try {
      final profile = await apiClient.getDoctorProfile(
        accessToken: accessToken,
        userId: widget.doctorUserId,
      );
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
    // Profil profesional ini berubah (foto/video intro) → muat ulang senyap.
    ref.listen<int>(professionalProfileRevisionProvider, (previous, next) {
      if (previous == next) return;
      final updatedId = ref.read(professionalProfileUpdatedIdProvider);
      if (updatedId.isEmpty || updatedId == widget.doctorUserId) {
        unawaited(_load(silent: true));
      }
    });
    final cred = _profile?.credential;

    return Scaffold(
      backgroundColor: const Color(0xfff8f8fb),
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Info Profesional'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBar: !_isLoading && _error == null && cred != null
          ? Material(
              color: Colors.white,
              elevation: 4,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            const Text('Layanan dipilih',
                                style: TextStyle(
                                    color: Color(0xff647388), fontSize: 11)),
                            Text(
                                _selectedPlan == 'continuous'
                                    ? 'Continuous Package'
                                    : 'Quick Consult • ${_quickMethod == 'chat' ? 'Chat' : 'Video'}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                          ])),
                      Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            const Text('Total biaya',
                                style: TextStyle(
                                    color: Color(0xff647388), fontSize: 11)),
                            Text(
                                _selectedPrice > 0
                                    ? 'Rp ${_rupiah(_selectedPrice)}'
                                    : 'Belum tersedia',
                                style: const TextStyle(
                                    color: MalvaColors.plum,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900)),
                          ]),
                    ]),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _selectedPrice > 0 ? _proceed : null,
                      style: FilledButton.styleFrom(
                          backgroundColor: MalvaColors.plum,
                          minimumSize: const Size.fromHeight(48)),
                      iconAlignment: IconAlignment.end,
                      icon: const Icon(Icons.arrow_forward_rounded),
                      label: Text(_selectedPlan == 'continuous'
                          ? 'Beli Paket 4 Sesi'
                          : 'Lanjutkan'),
                    ),
                  ],
                ),
              ),
            )
          : null,
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
                          SoftCard(
                            radius: 24,
                            color: Colors.white,
                            outline: const BorderSide(color: Color(0xffe8e8ef)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Stack(clipBehavior: Clip.none, children: [
                                  _ProfessionalPhoto(
                                      photoUrl: cred.photoIntroUrl,
                                      displayName: _shortName),
                                  if (cred.verificationStatus == 'VERIFIED')
                                    const Positioned(
                                        right: 0,
                                        bottom: 0,
                                        child: CircleAvatar(
                                          radius: 13,
                                          backgroundColor: MalvaColors.plum,
                                          child: Icon(Icons.verified_outlined,
                                              color: Colors.white, size: 17),
                                        )),
                                ]),
                                const SizedBox(height: 12),
                                Text(_displayName,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 20)),
                                const SizedBox(height: 4),
                                Text(_specializationLabel(cred),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        color: MalvaColors.plum,
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 12),
                                Wrap(
                                    alignment: WrapAlignment.center,
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      StatusPill(
                                          label: _profile!.reviews.reviewCount >
                                                  0
                                              ? '${_profile!.reviews.averageStars.toStringAsFixed(1)} (${_profile!.reviews.reviewCount})'
                                              : 'Belum ada ulasan',
                                          icon: Icons.star_rounded,
                                          color: const Color(0xff955708)),
                                      if (_profile!.ageYears case final age?)
                                        StatusPill(
                                            label: '$age tahun',
                                            icon: Icons.person_outline_rounded,
                                            color: MalvaColors.plum),
                                      StatusPill(
                                          label:
                                              '${cred.yearsExperience} thn praktik',
                                          icon: Icons.medical_services_outlined,
                                          color: MalvaColors.plum),
                                    ]),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          SoftCard(
                            color: Colors.white,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  const Icon(
                                      Icons.account_balance_wallet_outlined,
                                      size: 20,
                                      color: MalvaColors.plum),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                      child: SectionLabel('Tarif konsultasi')),
                                  if ([_chatPrice(), _videoPrice()]
                                      .any((price) => price > 0))
                                    Text(
                                        'Mulai Rp ${_rupiah(([
                                          _chatPrice(),
                                          _videoPrice()
                                        ]..sort()).firstWhere((price) => price > 0))}',
                                        style: const TextStyle(
                                            fontSize: 11,
                                            color: Color(0xff647388))),
                                ]),
                                _PriceRow(
                                    icon: Icons.chat_bubble_outline_rounded,
                                    label: 'Chat session',
                                    price: _chatPrice()),
                                const Divider(height: 10),
                                _PriceRow(
                                    icon: Icons.videocam_outlined,
                                    label: 'Video session',
                                    price: _videoPrice()),
                                const Divider(height: 10),
                                _PriceRow(
                                    icon: Icons.calendar_month_outlined,
                                    isPackage: true,
                                    label: 'Paket 4 sesi / 6 minggu',
                                    price: _packagePrice()),
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          SoftCard(
                            color: Colors.white,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(children: [
                                  Icon(Icons.local_hospital_rounded,
                                      color: MalvaColors.seed),
                                  SizedBox(width: 8),
                                  Expanded(
                                      child: SectionLabel('Tempat praktik')),
                                ]),
                                if (cred.effectivePracticeLocations.isEmpty)
                                  const Text('Faskes tidak dicantumkan'),
                                for (final (index, location) in cred
                                    .effectivePracticeLocations.indexed) ...[
                                  if (index > 0) const Divider(),
                                  const SizedBox(height: 8),
                                  Text(
                                    location.name.isNotEmpty
                                        ? location.name
                                        : 'Nama faskes tidak dicantumkan',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w800),
                                  ),
                                  if (location.address.isNotEmpty)
                                    Text(location.address),
                                  if (index == 0 &&
                                      cred.hospitalLat != null &&
                                      cred.hospitalLng != null)
                                    Text(_faskesDistanceLabel(cred)),
                                  const SizedBox(height: 4),
                                  StatusPill(
                                    label: location.acceptsBpjs
                                        ? 'Menerima BPJS'
                                        : 'Tidak menerima BPJS',
                                    color: location.acceptsBpjs
                                        ? const Color(0xff107356)
                                        : const Color(0xff647388),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 10),
                          if (cred.videoIntroUrl.trim().isNotEmpty) ...[
                            SoftCard(
                              color: Colors.white,
                              radius: 22,
                              padding: const EdgeInsets.all(10),
                              child: Material(
                                color: const Color(0xff350b5d),
                                borderRadius: BorderRadius.circular(16),
                                clipBehavior: Clip.antiAlias,
                                child: InkWell(
                                  key: const ValueKey(
                                      'professional-intro-video'),
                                  onTap: () =>
                                      _playIntroduction(cred.videoIntroUrl),
                                  child: AspectRatio(
                                    aspectRatio: 1.95,
                                    child: Center(
                                      child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(
                                                Icons
                                                    .play_circle_outline_rounded,
                                                size: 40,
                                                color: Colors.white),
                                            const SizedBox(height: 8),
                                            Text('Video Perkenalan $_shortName',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight:
                                                        FontWeight.w800)),
                                          ]),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          // ===== DROPDOWN: Profile =====
                          _DropdownCard(
                            label: 'Profil',
                            expanded: _profileExpanded,
                            onToggle: () => setState(
                                () => _profileExpanded = !_profileExpanded),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  decoration: BoxDecoration(
                                      color: const Color(0xfff6f8fa),
                                      borderRadius: BorderRadius.circular(14)),
                                  padding: const EdgeInsets.all(10),
                                  child: Column(children: [
                                    if (_profile!.ageYears case final age?)
                                      _InfoLine(
                                          label: 'Usia', value: '$age tahun'),
                                    _InfoLine(
                                        label: 'Pengalaman',
                                        value:
                                            '${cred.yearsExperience} tahun praktik'),
                                    _InfoLine(
                                        label: 'Faskes',
                                        value: cred.hospitalName.isEmpty
                                            ? '—'
                                            : cred.hospitalName),
                                    if (cred.addressDetails.isNotEmpty)
                                      _InfoLine(
                                          label: 'Alamat',
                                          value: cred.addressDetails),
                                  ]),
                                ),
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
                            label: 'Spesialisasi',
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
                                    value: cred.strNumber.isEmpty
                                        ? '—'
                                        : cred.strNumber),
                                _InfoLine(
                                    label: 'SIP',
                                    value:
                                        '${cred.sippNumber.isEmpty ? '-' : cred.sippNumber}'),
                                // Sub-spesialisasi dengan deskripsi detail
                                if (cred.subSpecialties.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Bidang keahlian:',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12.5),
                                  ),
                                  const SizedBox(height: 4),
                                  for (final spec in cred.subSpecialties)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text('• ',
                                              style: TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  color: MalvaColors.seed)),
                                          Expanded(
                                            child: Text(
                                              _specialtyDescription(spec),
                                              style: const TextStyle(
                                                  fontSize: 12.5),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                                // Riwayat pendidikan
                                if (cred.education.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Riwayat pendidikan:',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 12.5),
                                  ),
                                  const SizedBox(height: 4),
                                  for (final edu in cred.education)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(Icons.school_rounded,
                                              size: 14,
                                              color: MalvaColors.seed),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              '${edu['degree'] ?? ''} — ${edu['school'] ?? ''}'
                                              '${edu['year'] != null ? ' (${edu['year']})' : ''}',
                                              style: const TextStyle(
                                                  fontSize: 12.5),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
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
                                const SectionLabel('Ulasan'),
                                for (var i = 0;
                                    i < reviews.reviews.length;
                                    i++) ...[
                                  _ReviewCard(
                                    name: reviews.reviews[i].patientName,
                                    text: reviews.reviews[i].reviewText,
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
                          DoctorReviewActions(
                            apiClient:
                                widget.apiClient ?? ref.read(apiClientProvider),
                            professionalId: widget.doctorUserId,
                            accessToken: (widget.session ??
                                            ref.read(currentSessionProvider))
                                        ?.role ==
                                    UserRole.patient
                                ? (widget.session ??
                                        ref.read(currentSessionProvider))
                                    ?.accessToken
                                : null,
                            onSubmitted: () {
                              ref
                                  .read(professionalProfileRevisionProvider
                                      .notifier)
                                  .state++;
                              unawaited(_load(silent: true));
                            },
                          ),
                          if (_activePackage != null)
                            SoftCard(
                              color: Colors.white,
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

                          Text('Pilih layanan konsultasi',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 10),
                          SoftCard(
                            color: const Color(0xffeff4f8),
                            radius: 16,
                            child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Icon(Icons.gpp_maybe_outlined,
                                      size: 19, color: Color(0xff647388)),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text.rich(
                                          TextSpan(children: [
                                            const TextSpan(
                                                text:
                                                    'Layanan ini untuk dukungan berkelanjutan, bukan darurat. Jika dalam kondisi krisis, segera hubungi '),
                                            WidgetSpan(
                                                alignment:
                                                    PlaceholderAlignment.middle,
                                                child: InkWell(
                                                  onTap: _callEmergency,
                                                  child: const Text('112',
                                                      style: TextStyle(
                                                          color:
                                                              MalvaColors.plum,
                                                          fontWeight:
                                                              FontWeight.w800,
                                                          decoration:
                                                              TextDecoration
                                                                  .underline)),
                                                )),
                                            const TextSpan(text: '.'),
                                          ]),
                                          style: const TextStyle(
                                              color: Color(0xff506074)))),
                                ]),
                          ),
                          const SizedBox(height: 12),

                          // ===== OPSI 1: QUICK CONSULT (ONE-TIME) =====
                          _SupportPlanCard(
                            selected: _selectedPlan == 'quick',
                            onSelect: () =>
                                setState(() => _selectedPlan = 'quick'),
                            title: 'Quick Consult',
                            subtitle: 'Satu sesi konsultasi terjadwal',
                            price: 0,
                            selectedMethod: _quickMethod,
                            onMethod: (label) => setState(() {
                              _selectedMethod = label.toLowerCase();
                              _selectedPlan = 'quick';
                            }),
                            featureIcon: Icons.timer_outlined,
                            methods: [
                              (
                                'Chat',
                                _chatPrice(),
                                Icons.chat_bubble_outline_rounded
                              ),
                              ('Video', _videoPrice(), Icons.videocam_outlined)
                            ],
                            features: const [
                              (
                                'Jadwal fleksibel sesuai ketersediaan profesional',
                                Icons.event_available_outlined
                              ),
                              (
                                'Berbagi data & catatan selama durasi sesi',
                                Icons.share_outlined
                              ),
                            ],
                            onSchedule: () => _showSchedule(false),
                          ),
                          const SizedBox(height: 12),

                          // ===== OPSI 2: PAKET CONTINUOUS (4 SESI / 6 MINGGU) =====
                          _SupportPlanCard(
                            selected: _selectedPlan == 'continuous',
                            onSelect: _packagePrice() > 0 && _canBookPackage
                                ? () =>
                                    setState(() => _selectedPlan = 'continuous')
                                : () => ScaffoldMessenger.of(context)
                                    .showSnackBar(SnackBar(
                                        content:
                                            Text(_packageCapacityMessage))),
                            title: 'Continuous Package',
                            capacity: _profile?.remainingPatientSlots,
                            subtitle: '4 sesi • Masa aktif 6 minggu',
                            onSchedule: () => _showSchedule(true),
                            price: _packagePrice(),
                            comparisonPrice: _videoPrice() * 4,
                            featureIcon: Icons.calendar_month_outlined,
                            features: [
                              (
                                '4 sesi video terjadwal' +
                                    (_durationLabel('package') == null
                                        ? ''
                                        : " • ${_durationLabel('package')} per sesi"),
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
                                'Sisa sesi setelah 6 minggu otomatis hangus. Tidak ada perpanjangan otomatis.',
                            quota:
                                'Termasuk monitoring data selama paket aktif',
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
    final parts = _displayName.split(',').first.split(RegExp(r'\s+'));
    return parts.first.toLowerCase() == 'dr.' && parts.length > 1
        ? parts.take(2).join(' ')
        : parts.first;
  }

  String _specializationLabel(BackendProfessionalCredential credential) =>
      isPsychiatristSpecialization(credential.specialization)
          ? 'Psikiater • Spesialis Kedokteran Jiwa'
          : professionalRoleLabel(credential.specialization);

  Future<void> _playIntroduction(String rawUrl) async {
    final MalvaApiClient api = widget.apiClient ?? ref.read(apiClientProvider);
    final uri = api.baseUri.resolve(rawUrl.trim());
    if (uri.hasAuthority && (uri.scheme == 'https' || uri.scheme == 'http')) {
      try {
        final mode = await supportsLaunchMode(LaunchMode.inAppBrowserView)
            ? LaunchMode.inAppBrowserView
            : LaunchMode.platformDefault;
        if (await launchUrl(uri, mode: mode)) return;
      } on Object catch (_) {
        // Show a recoverable error if the platform cannot open the video.
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Video perkenalan belum bisa diputar.')),
      );
    }
  }

  Future<void> _callEmergency() async {
    try {
      if (await launchUrl(Uri(scheme: 'tel', path: '112'))) return;
    } on Object catch (_) {
      // Preserve the number on platforms without a dialer.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hubungi 112 melalui telepon.')),
      );
    }
  }

  /// Harga quick consult dari tarif profesional (tanpa angka dummy).
  /// 0 = profesional belum mengatur harga.
  int _chatPrice() => _profile?.pricing.quickChatPrice ?? 0;

  int _videoPrice() => _profile?.pricing.quickVideoPrice ?? 0;

  int _packagePrice() => _profile?.pricing.packagePrice ?? 0;

  String _faskesDistanceLabel(BackendProfessionalCredential cred) {
    final pos = ref.watch(patientLocationProvider).position;
    final km = distanceKmBetween(
      fromLat: pos?.latitude,
      fromLng: pos?.longitude,
      toLat: cred.hospitalLat,
      toLng: cred.hospitalLng,
    );
    return professionalDistanceLabel(
      km: km,
      hospitalLat: cred.hospitalLat,
      hospitalLng: cred.hospitalLng,
    );
  }

  static const _dayNamesId = [
    'Minggu',
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
  ];

  /// Ringkasan jadwal mingguan profesional dari server.
  String? _durationLabel(String category) {
    final durations = _schedulesFor(category)
        .map((slot) => slot.slotDurationMinutes.clamp(60, 180))
        .toSet();
    if (durations.length != 1) return null;
    final minutes = durations.single;
    return minutes == 60 ? '1 jam' : '$minutes menit';
  }

  List<BackendProfessionalSchedule> _schedulesFor(String category) {
    final schedules =
        _profile?.schedules ?? const <BackendProfessionalSchedule>[];
    return professionalServiceSchedules(schedules, category,
            usePrimarySchedule: _profile?.usePrimarySchedule ?? const {})
        .where((s) => s.isActive)
        .toList();
  }

  bool get _canBookPackage =>
      _profile?.remainingPatientSlots != 0 ||
      _profile?.canRenewPackage == true ||
      _profile?.canResumePackage == true;

  List<String> _scheduleLines(String category) {
    final schedules = _schedulesFor(category);
    if (schedules.isEmpty) {
      return const ['Jadwal belum diatur profesional'];
    }
    final byDay = <int, List<BackendProfessionalSchedule>>{};
    for (final s in schedules) {
      (byDay[s.dayOfWeek % 7] ??= []).add(s);
    }
    final days = byDay.keys.toList()
      ..sort((a, b) => ((a + 6) % 7).compareTo((b + 6) % 7));
    return [
      for (final d in days)
        '${_dayNamesId[d]}: ${byDay[d]!.map((s) => '${s.startTime}–${s.endTime}').join(', ')}',
    ];
  }

  String get _packageCapacityMessage => _canBookPackage
      ? 'Profesional belum mengatur harga paket.'
      : 'Kuota pasien untuk paket ini penuh.';

  void _proceed() {
    final cred = _profile?.credential;
    if (cred == null) return;
    if (_selectedPlan == 'continuous') {
      if (_packagePrice() <= 0 || !_canBookPackage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_packageCapacityMessage)),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PackageBookingScreen(
            durationLabel: _durationLabel('package'),
            doctorUserId: widget.doctorUserId,
            doctorName: _displayName,
            doctorSpecialization: _specializationLabel(cred),
            doctorVerified: cred.verificationStatus == 'VERIFIED',
            price: _packagePrice(),
            scheduleLines: _scheduleLines('package'),
            remainingPatientSlots: _profile?.remainingPatientSlots,
            canRenewPackage: _profile?.canRenewPackage == true,
            canResumePackage: _profile?.canResumePackage == true,
            doctorPhotoUrl: cred.photoIntroUrl,
            session: widget.session ?? ref.read(currentSessionProvider),
            apiClient: widget.apiClient,
          ),
        ),
      );
    } else {
      final price = _selectedPrice;
      if (price <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Profesional belum mengatur harga sesi ini.')),
        );
        return;
      }
      _openBooking(context, price, _quickMethod);
    }
  }

  static String _reviewDate(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final d = toWibOrNull(DateTime.tryParse(iso));
    if (d == null) return '';
    return '${d.day}/${d.month}/${d.year}';
  }

  void _openBooking(BuildContext context, int price, String method) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingDetailScreen(
          chatDurationLabel: _durationLabel('quick_chat'),
          videoDurationLabel: _durationLabel('quick_video'),
          doctorUserId: widget.doctorUserId,
          doctorName: _displayName,
          serviceType: method,
          expectedPrice: price,
          chatPrice: _chatPrice(),
          videoPrice: _videoPrice(),
          doctorPhotoUrl: _profile?.credential.photoIntroUrl ?? '',
          session: widget.session ?? ref.read(currentSessionProvider),
          apiClient: widget.apiClient,
        ),
      ),
    );
  }

  Future<void> _showSchedule(bool package) => showDialog<void>(
        context: context,
        barrierColor: MalvaColors.plum.withValues(alpha: 0.65),
        builder: (context) => AlertDialog(
          backgroundColor: Colors.white,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          titlePadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Row(children: [
            Icon(package ? Icons.calendar_month_outlined : Icons.timer_outlined,
                color: MalvaColors.seed, size: 28),
            const SizedBox(width: 10),
            Expanded(
                child: Text(
                    package
                        ? 'Jadwal Continuous Package'
                        : 'Jadwal Quick Consult',
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w900))),
          ]),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(package
                    ? 'Jadwal mingguan • WIB\n4 sesi video • 6 minggu'
                    : 'Jadwal mingguan • WIB'),
                const SizedBox(height: 12),
                for (final (label, category) in [
                  if (package)
                    ('Video', 'package')
                  else ...[
                    if (_chatPrice() > 0) ('Chat', 'quick_chat'),
                    if (_videoPrice() > 0) ('Video', 'quick_video'),
                  ],
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: SoftCard(
                      color: const Color(0xFFF2E6FA),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (!package)
                            Text(label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900)),
                          for (final line in _scheduleLines(category))
                            Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 4),
                                child: Text(line)),
                        ],
                      ),
                    ),
                  ),
                if (package && _profile?.remainingPatientSlots != null)
                  StatusPill(
                      label: '${_profile!.remainingPatientSlots} slot tersisa',
                      color: MalvaColors.seed),
                const SizedBox(height: 12),
                FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Tutup')),
              ],
            ),
          ),
        ),
      );

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

  /// Deskripsi detail untuk setiap sub-spesialisasi.
  static String _specialtyDescription(String spec) {
    const descriptions = {
      'depresi':
          'Depresi — gangguan suasana hati yang menyebabkan perasaan sedih berkepanjangan, kehilangan minat, dan kelelahan mental.',
      'ansietas':
          'Ansietas — kecemasan berlebihan yang mengganggu aktivitas sehari-hari, termasuk gangguan panik dan fobia.',
      'gangguan_tidur':
          'Gangguan Tidur — insomnia, hipersomnia, dan masalah kualitas tidur yang berdampak pada kesehatan mental.',
      'bipolar':
          'Bipolar — gangguan mood dengan episode manik dan depresif yang bergantian, memerlukan penanganan farmakologis.',
      'suicidal_ideation':
          'Ideasi Suicidal — pikiran untuk mengakhiri hidup yang memerlukan intervensi krisis segera dan pendampingan intensif.',
      'stress_pasca_trauma':
          'Stress Pasca Trauma (PTSD) — reaksi psikologis setelah peristiwa traumatis, termasuk flashbacks dan hypervigilance.',
      'kesehatan_jiwa_perempuan':
          'Kesehatan Jiwa Perempuan — isu mental health spesifik perempuan: postpartum depression, PMDD, menopause-related mood changes.',
      'trauma':
          'Trauma — pengalaman menyakitkan yang meninggalkan dampak psikologis jangka panjang, ditangani dengan EMDR dan trauma-focused CBT.',
      'pemulihan_krisis':
          'Pemulihan Krisis — pendampingan intensif pasca kejadian kritis (bencana, kehilangan mendadak, kekerasan).',
      'kekerasan_domestik':
          'Kekerasan Domestik — pendampingan korban KDRT, pemulihan trauma interpersonal, dan perencanaan keselamatan.',
      'pranikah':
          'Konseling Pranikah — persiapan mental dan emosional menjelang pernikahan, komunikasi pasangan, dan manajemen ekspektasi.',
      'seksualitas':
          'Seksualitas — isu terkait identitas seksual, orientasi, disfungsi seksual, dan kesehatan reproduksi mental.',
      'cbt':
          'CBT (Cognitive Behavioral Therapy) — terapi berbasis bukti yang mengubah pola pikir dan perilaku negatif menjadi lebih adaptif.',
      'manajemen_stres':
          'Manajemen Stres — teknik pengelolaan stres kerja, akademik, dan kehidupan sehari-hari melalui relaksasi dan restrukturisasi kognitif.',
      'konseling_remaja':
          'Konseling Remaja — pendampingan remaja menghadapi krisis identitas, tekanan akademik, konflik keluarga, dan peer pressure.',
      'bullying':
          'Bullying — penanganan korban dan pelaku bullying, pemulihan harga diri, dan strategi coping di lingkungan sekolah/sosial.',
      'gangguan_makan':
          'Gangguan Makan — anorexia, bulimia, binge eating disorder, dan body image issues yang memerlukan pendekatan multidisiplin.',
      'self_harm':
          'Self-Harm — perilaku melukai diri sendiri sebagai mekanisme coping maladaptif, memerlukan intervensi DBT dan safety planning.',
      'relasi':
          'Relasi — konseling pasangan dan individu untuk memperbaiki komunikasi, menyelesaikan konflik, dan membangun hubungan sehat.',
      'burnout':
          'Burnout — kelelahan emosional, depersonalisasi, dan penurunan pencapaian pribadi akibat stres kerja kronis.',
      'pengembangan_diri':
          'Pengembangan Diri — eksplorasi potensi, penetapan tujuan hidup, peningkatan self-awareness dan self-efficacy.',
      'kecemasan_sosial':
          'Kecemasan Sosial — ketakutan berlebihan dalam situasi sosial, ditangani dengan exposure therapy dan social skills training.',
      'parenting':
          'Parenting — konseling pengasuhan anak, manajemen stres orang tua, dan strategi disiplin positif.',
      'grief':
          'Grief/Duka — pendampingan proses kehilangan (kematian, perceraian, perubahan besar), tahapan duka, dan meaning-making.',
    };
    return descriptions[spec.toLowerCase()] ?? spec;
  }
}

/// Widget foto profil profesional. Menampilkan gambar dari URL bila tersedia,
/// fallback ke InitialAvatar dengan inisial nama.
class _ProfessionalPhoto extends StatelessWidget {
  const _ProfessionalPhoto({
    required this.photoUrl,
    required this.displayName,
  });

  final String photoUrl;
  final String displayName;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 120,
      height: 120,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
            color: MalvaColors.seed.withValues(alpha: 0.3), width: 3),
        boxShadow: [
          BoxShadow(
            color: MalvaColors.seed.withValues(alpha: 0.15),
            blurRadius: 12,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: photoUrl.isEmpty
            ? _fallbackAvatar()
            : ProfessionalPhoto(
                photoUrl: photoUrl,
                width: 120,
                height: 120,
                fit: BoxFit.cover,
                fallback: _fallbackAvatar(),
              ),
      ),
    );
  }

  Widget _fallbackAvatar() {
    return CircleAvatar(
      radius: 60,
      backgroundColor: MalvaColors.seed.withValues(alpha: 0.12),
      child: Text(
        displayName.isEmpty ? '?' : displayName,
        style: const TextStyle(
          color: MalvaColors.seed,
          fontWeight: FontWeight.w900,
          fontSize: 17,
        ),
      ),
    );
  }
} // ============================================================
// WIDGETS LOKAL
// ============================================================

class _PriceRow extends StatelessWidget {
  const _PriceRow(
      {required this.label,
      required this.price,
      required this.icon,
      this.isPackage = false});

  final String label;
  final int price;
  final IconData icon;
  final bool isPackage;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon,
              size: 17,
              color: isPackage ? MalvaColors.plum : const Color(0xff718196)),
          const SizedBox(width: 8),
          Expanded(
              child: Text(label,
                  style: const TextStyle(color: Color(0xff4c5a6a)))),
          const SizedBox(width: 8),
          Flexible(
              child: Text(
            price > 0
                ? 'Rp ${_DoctorProfileScreenState._rupiah(price)}'
                : 'Belum diatur',
            textAlign: TextAlign.end,
            style: TextStyle(
                fontWeight: FontWeight.w900,
                color: isPackage ? MalvaColors.plum : null),
          )),
        ],
      );
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
    required this.subtitle,
    required this.price,
    required this.features,
    required this.featureIcon,
    required this.onSchedule,
    this.methods = const [],
    this.selectedMethod,
    this.onMethod,
    this.capacity,
    this.comparisonPrice = 0,
    this.footnote,
    this.quota,
  });

  final bool selected;
  final VoidCallback onSelect;
  final String title;
  final String subtitle;
  final List<(String, IconData)> features;
  final IconData featureIcon;
  final VoidCallback onSchedule;
  final int price;
  final int comparisonPrice;
  final List<(String, int, IconData)> methods;
  final String? selectedMethod;
  final ValueChanged<String>? onMethod;
  final String? footnote;
  final String? quota;
  final int? capacity;

  static const _ink = Color(0xff222d3b);
  static const _muted = Color(0xff576577);
  static const _pale = Color(0xfff7f0fb);
  String _price(int amount) =>
      'Rp ${_DoctorProfileScreenState._rupiah(amount)}';

  @override
  Widget build(BuildContext context) {
    final package = methods.isEmpty;
    final showSaving = package && price > 0 && comparisonPrice > price;
    return SoftCard(
      padding: const EdgeInsets.all(16),
      radius: 22,
      color: Colors.white,
      outline: BorderSide(
        width: selected ? 1.8 : 1,
        color: selected ? MalvaColors.plum : const Color(0xffe6e8ef),
      ),
      onTap: onSelect,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showSaving) ...[
            Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(
                    label:
                        'Hemat ${_price(comparisonPrice - price)} • Pendampingan Intensif',
                    color: const Color(0xff106e55),
                    icon: Icons.trending_down_rounded)),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                    color: _pale, borderRadius: BorderRadius.circular(14)),
                child: Icon(featureIcon, color: MalvaColors.plum, size: 27),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: _ink,
                            fontWeight: FontWeight.w900,
                            fontSize: 18)),
                    Text(subtitle,
                        style: const TextStyle(color: _muted, fontSize: 12)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: selected ? MalvaColors.plum : const Color(0xffc8d1dc)),
            ],
          ),
          const SizedBox(height: 12),
          if (package) ...[
            SoftCard(
              color: const Color(0xfff5f7fa),
              radius: 14,
              padding: const EdgeInsets.all(10),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showSaving)
                      Text(_price(comparisonPrice),
                          style: const TextStyle(
                              color: _muted,
                              decoration: TextDecoration.lineThrough,
                              fontSize: 12)),
                    Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                              price > 0
                                  ? '${_price(price)} / paket'
                                  : 'Harga belum diatur',
                              style: const TextStyle(
                                  color: _ink,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 17)),
                          if (price > 0)
                            StatusPill(
                                label: '${_price(price ~/ 4)} / sesi',
                                color: MalvaColors.plum),
                        ]),
                  ]),
            ),
            if (capacity case final remaining?)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text('$remaining slot tersisa',
                    style: const TextStyle(color: _muted, fontSize: 11)),
              ),
          ] else ...[
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final (label, amount, icon) in methods) ...[
                if (label == 'Video') const SizedBox(width: 8),
                Expanded(child: _method(label, amount, icon)),
              ],
            ]),
            const Divider(height: 22),
          ],
          if (package) const SizedBox(height: 10),
          for (final (label, icon) in features)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 18, color: MalvaColors.plum),
                const SizedBox(width: 8),
                Expanded(
                    child: Text(label, style: const TextStyle(color: _muted))),
              ]),
            ),
          if (footnote != null)
            SoftCard(
              color: const Color(0xfffaf6fc),
              padding: const EdgeInsets.all(12),
              radius: 14,
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                        'Setiap pembelian paket menambah 4 sesi dan 6 minggu masa aktif.',
                        style: TextStyle(
                            color: _ink, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 5),
                    Text(footnote!, style: const TextStyle(color: _muted)),
                    if (quota != null) ...[
                      const SizedBox(height: 8),
                      Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.monitor_heart_outlined,
                                size: 17, color: MalvaColors.plum),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(quota!,
                                    style: const TextStyle(
                                        color: MalvaColors.plum,
                                        fontWeight: FontWeight.w700))),
                          ]),
                    ],
                  ]),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              backgroundColor: selected ? _pale : Colors.white,
              foregroundColor: MalvaColors.plum,
              side: const BorderSide(color: Color(0xffe4d7ee)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              textStyle: const TextStyle(fontWeight: FontWeight.w800),
            ),
            onPressed: onSchedule,
            icon: const Icon(Icons.calendar_today_outlined, size: 18),
            label: const Text('Lihat ketersediaan jadwal'),
          ),
        ],
      ),
    );
  }

  Widget _method(String label, int amount, IconData icon) {
    final active = selected && selectedMethod == label.toLowerCase();
    final border = BorderRadius.circular(13);
    return Semantics(
      selected: active,
      button: true,
      child: Material(
        color: active ? _pale : const Color(0xfff7f8fa),
        shape: RoundedRectangleBorder(
            borderRadius: border,
            side: BorderSide(
                color: active ? MalvaColors.plum : const Color(0xffe6e8ef),
                width: active ? 1.7 : 1)),
        child: InkWell(
          borderRadius: border,
          onTap: amount > 0 ? () => onMethod?.call(label) : null,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(icon, size: 16, color: active ? MalvaColors.plum : _muted),
                const SizedBox(width: 5),
                Expanded(
                    child: Text(label,
                        style: const TextStyle(fontWeight: FontWeight.w800))),
                if (active)
                  const Icon(Icons.circle, size: 8, color: MalvaColors.plum),
              ]),
              const SizedBox(height: 6),
              Text(amount > 0 ? '${_price(amount)} / sesi' : 'Belum tersedia',
                  style: const TextStyle(
                      color: _ink, fontWeight: FontWeight.w800, fontSize: 12)),
            ]),
          ),
        ),
      ),
    );
  }
}
