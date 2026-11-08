import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/providers.dart';
import '../../../services/malva_api_client.dart';
import '../../../theme.dart';
import '../../../widgets/professional_avatar.dart';
import '../../../widgets/doctor_review_actions.dart';
import '../../services/web_care_service.dart';
import '../../web_format.dart';
import '../../web_theme.dart';
import '../../widgets/web_admin_widgets.dart';
import '../../widgets/web_page_header.dart';
import 'web_booking_dialog.dart';

/// Katalog profesional untuk pasien (`/profesional`).
///
/// Dua tampilan internal: katalog (filter + section per profesi) dan detail
/// profesional (profil, harga, ulasan, slot 7 hari) dengan CTA booking.
class WebProfessionalCatalogScreen extends ConsumerStatefulWidget {
  const WebProfessionalCatalogScreen({super.key, required this.onNavigate});

  /// Navigasi rute tingkat atas (mis. ke `/jadwal` setelah pembayaran lunas).
  final ValueChanged<String> onNavigate;

  @override
  ConsumerState<WebProfessionalCatalogScreen> createState() =>
      _WebProfessionalCatalogScreenState();
}

class _WebProfessionalCatalogScreenState
    extends ConsumerState<WebProfessionalCatalogScreen> {
  final TextEditingController _search = TextEditingController();

  List<BackendDoctorSearchResult> _doctors =
      const <BackendDoctorSearchResult>[];
  bool _loading = true;
  Object? _error;
  int _loadGeneration = 0;

  WebDoctorGroup? _group;
  bool _bpjsOnly = false;
  bool _availableTodayOnly = false;
  int? _maxPrice;
  String _sortBy = 'name_asc';

  BackendDoctorSearchResult? _selected;
  BackendDoctorProfile? _profile;
  BackendProfessionalPricing? _pricing;
  bool _detailLoading = false;
  Object? _detailError;
  final List<String> _days = webNextSevenDayKeys();
  String _detailDate = '';
  List<BackendDoctorSlot> _detailSlots = const <BackendDoctorSlot>[];
  bool _slotsLoading = false;
  bool _showAllReviews = false;

  String get _token => ref.read(authStateProvider).session?.accessToken ?? '';

  @override
  void initState() {
    super.initState();
    _detailDate = _days.first;
    unawaited(_loadDoctors());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadDoctors() async {
    final generation = ++_loadGeneration;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final position = ref.read(patientLocationProvider).position;
      final doctors = await ref.read(apiClientProvider).searchDoctors(
            accessToken: _token.isEmpty ? null : _token,
            maxPrice: _maxPrice,
            isBpjsSupported: _bpjsOnly ? true : null,
            sortBy: _sortBy,
            limit: 50,
            patientLat: position?.latitude,
            patientLng: position?.longitude,
          );
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _doctors = doctors;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// Filter yang dikerjakan di klien (server belum mendukung pencarian nama).
  List<BackendDoctorSearchResult> get _filtered {
    final query = _search.text.trim().toLowerCase();
    return _doctors.where((BackendDoctorSearchResult doctor) {
      if (_bpjsOnly && !doctor.isBpjsSupported) return false;
      if (_availableTodayOnly && doctor.isAvailableToday != true) return false;
      if (_group != null && webDoctorGroupOf(doctor.specialization) != _group) {
        return false;
      }
      if (_maxPrice != null && doctor.priceFrom > _maxPrice!) return false;
      if (query.isEmpty) return true;
      return doctor.displayName.toLowerCase().contains(query) ||
          doctor.hospitalName.toLowerCase().contains(query) ||
          doctor.specialization.toLowerCase().contains(query);
    }).toList(growable: false);
  }

  Future<void> _openDetail(BackendDoctorSearchResult doctor) async {
    setState(() {
      _selected = doctor;
      _profile = null;
      _pricing = null;
      _detailError = null;
      _detailLoading = true;
      _showAllReviews = false;
      _detailDate = _days.first;
      _detailSlots = const <BackendDoctorSlot>[];
    });
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait(<Future<Object>>[
        api.getDoctorProfile(
          accessToken: _token.isEmpty ? null : _token,
          userId: doctor.userId,
        ),
        api.getPricing(accessToken: _token, professionalId: doctor.userId),
        // Profil sudah memuat ulasan, tetapi endpoint khusus dipakai agar
        // daftar ulasan terbaru tetap benar bila server memfilternya.
        api.listDoctorReviews(
          accessToken: _token.isEmpty ? null : _token,
          userId: doctor.userId,
        ),
      ]);
      if (!mounted) return;
      final profile = results[0] as BackendDoctorProfile;
      final reviews = results[2] as BackendDoctorReviews;
      setState(() {
        _profile = reviews.reviews.isEmpty
            ? profile
            : BackendDoctorProfile(
                credential: profile.credential,
                packages: profile.packages,
                schedules: profile.schedules,
                pricing: profile.pricing,
                reviews: reviews,
              );
        _pricing = results[1] as BackendProfessionalPricing;
        _detailLoading = false;
      });
      unawaited(_loadDetailSlots());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _detailError = error;
        _detailLoading = false;
      });
    }
  }

  Future<void> _loadDetailSlots() async {
    final doctor = _selected;
    if (doctor == null) return;
    setState(() => _slotsLoading = true);
    try {
      final slots = await ref.read(apiClientProvider).getDoctorAvailableSlots(
            accessToken: _token.isEmpty ? null : _token,
            userId: doctor.userId,
            date: _detailDate,
          );
      if (!mounted) return;
      setState(() {
        _detailSlots = slots
            .where((BackendDoctorSlot slot) => slot.available)
            .toList(growable: false);
        _slotsLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _detailSlots = const <BackendDoctorSlot>[];
        _slotsLoading = false;
      });
    }
  }

  void _backToCatalog() {
    setState(() {
      _selected = null;
      _profile = null;
      _pricing = null;
      _detailError = null;
    });
  }

  Future<void> _openBooking() async {
    final doctor = _selected;
    final pricing = _pricing ?? _profile?.pricing;
    if (doctor == null || pricing == null) return;
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => WebBookingDialog(
        doctor: doctor,
        pricing: pricing,
        onGoToSchedule: () => widget.onNavigate('/jadwal'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PatientLocationState>(patientLocationProvider, (previous, next) {
      if (previous?.position != next.position) unawaited(_loadDoctors());
    });
    ref.listen<int>(professionalProfileRevisionProvider, (previous, next) {
      if (previous != next) unawaited(_loadDoctors());
    });
    final selected = _selected;
    if (selected != null) return _buildDetail(context, selected);
    return _buildCatalog(context);
  }

  // ============================================================
  // KATALOG
  // ============================================================

  Widget _buildCatalog(BuildContext context) {
    final doctors = _filtered;
    final sections = webGroupDoctors(doctors);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WebPageHeader(
          title: 'Cari Profesional',
          subtitle: 'Psikiater dan psikolog terverifikasi. Filter sesuai '
              'kebutuhan Anda, lalu booking sesi langsung dari sini.',
          trailing: OutlinedButton.icon(
            onPressed: _loading ? null : () => unawaited(_loadDoctors()),
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Muat ulang'),
          ),
        ),
        const SizedBox(height: WebSpacing.section),
        WebAdminCard(child: _buildFilters()),
        const SizedBox(height: 16),
        if (_loading)
          const WebAdminCard(
              child: WebAdminLoading(label: 'Memuat profesional...'))
        else if (_error != null)
          WebAdminCard(
            child: WebAdminError(
              error: _error!,
              onRetry: () => unawaited(_loadDoctors()),
            ),
          )
        else if (doctors.isEmpty)
          WebAdminCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 30),
              child: Column(
                children: <Widget>[
                  const Icon(Icons.search_off_rounded,
                      size: 26, color: Color(0xFF8B8194)),
                  const SizedBox(height: 8),
                  const Text(
                    'Tidak ada profesional yang cocok dengan filter ini.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF6B6377)),
                  ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      _search.clear();
                      setState(() {
                        _group = null;
                        _bpjsOnly = false;
                        _availableTodayOnly = false;
                        _maxPrice = null;
                      });
                    },
                    child: const Text('Reset filter'),
                  ),
                ],
              ),
            ),
          )
        else
          for (final WebDoctorSection section in sections) ...<Widget>[
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Text(
                  section.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(width: 8),
                WebStatusPill(
                  label: '${section.count}',
                  color: MalvaColors.seed,
                ),
              ],
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final columns = constraints.maxWidth >= 1200
                    ? 3
                    : (constraints.maxWidth >= 760 ? 2 : 1);
                final width = (constraints.maxWidth -
                        WebSpacing.cardGap * (columns - 1)) /
                    columns;
                return Wrap(
                  spacing: WebSpacing.cardGap,
                  runSpacing: WebSpacing.cardGap,
                  children: section.doctors
                      .map(
                        (BackendDoctorSearchResult doctor) => SizedBox(
                          width: width,
                          child: _DoctorCard(
                            doctor: doctor,
                            onOpen: () => unawaited(_openDetail(doctor)),
                          ),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
            const SizedBox(height: WebSpacing.section),
          ],
      ],
    );
  }

  Widget _buildFilters() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: <Widget>[
        SizedBox(
          width: 260,
          child: TextField(
            key: const Key('web-catalog-search'),
            controller: _search,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Cari nama / rumah sakit',
              prefixIcon: Icon(Icons.search_rounded, size: 20),
              isDense: true,
            ),
          ),
        ),
        SizedBox(
          width: 170,
          child: InputDecorator(
            decoration:
                const InputDecoration(labelText: 'Profesi', isDense: true),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<WebDoctorGroup?>(
                key: const Key('web-catalog-group'),
                value: _group,
                isExpanded: true,
                isDense: true,
                items: const <DropdownMenuItem<WebDoctorGroup?>>[
                  DropdownMenuItem<WebDoctorGroup?>(
                    value: null,
                    child: Text('Semua'),
                  ),
                  DropdownMenuItem<WebDoctorGroup?>(
                    value: WebDoctorGroup.psychiatrist,
                    child: Text('Psikiater'),
                  ),
                  DropdownMenuItem<WebDoctorGroup?>(
                    value: WebDoctorGroup.psychologist,
                    child: Text('Psikolog'),
                  ),
                  DropdownMenuItem<WebDoctorGroup?>(
                    value: WebDoctorGroup.other,
                    child: Text('Lainnya'),
                  ),
                ],
                onChanged: (WebDoctorGroup? value) =>
                    setState(() => _group = value),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 180,
          child: InputDecorator(
            decoration:
                const InputDecoration(labelText: 'Harga maks.', isDense: true),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int?>(
                key: const Key('web-catalog-max-price'),
                value: _maxPrice,
                isExpanded: true,
                isDense: true,
                items: const <DropdownMenuItem<int?>>[
                  DropdownMenuItem<int?>(value: null, child: Text('Semua')),
                  DropdownMenuItem<int?>(
                      value: 100000, child: Text('≤ Rp100.000')),
                  DropdownMenuItem<int?>(
                      value: 250000, child: Text('≤ Rp250.000')),
                  DropdownMenuItem<int?>(
                      value: 500000, child: Text('≤ Rp500.000')),
                ],
                onChanged: (int? value) => setState(() => _maxPrice = value),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 190,
          child: InputDecorator(
            decoration:
                const InputDecoration(labelText: 'Urutkan', isDense: true),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('web-catalog-sort'),
                value: _sortBy,
                isExpanded: true,
                isDense: true,
                items: const <DropdownMenuItem<String>>[
                  DropdownMenuItem<String>(
                      value: 'name_asc', child: Text('Nama (A–Z)')),
                  DropdownMenuItem<String>(
                      value: 'experience_desc', child: Text('Pengalaman')),
                  DropdownMenuItem<String>(
                      value: 'rating_desc', child: Text('Rating')),
                  DropdownMenuItem<String>(
                      value: 'distance', child: Text('Terdekat')),
                ],
                onChanged: (String? value) {
                  setState(() => _sortBy = value ?? 'name_asc');
                  unawaited(_loadDoctors());
                },
              ),
            ),
          ),
        ),
        FilterChip(
          key: const Key('web-catalog-bpjs'),
          label: const Text('BPJS'),
          selected: _bpjsOnly,
          onSelected: (bool value) => setState(() => _bpjsOnly = value),
        ),
        FilterChip(
          key: const Key('web-catalog-today'),
          label: const Text('Tersedia hari ini'),
          selected: _availableTodayOnly,
          onSelected: (bool value) =>
              setState(() => _availableTodayOnly = value),
        ),
        Text(
          '${_filtered.length} profesional',
          style: const TextStyle(fontSize: 12, color: Color(0xFF6B6377)),
        ),
      ],
    );
  }

  // ============================================================
  // DETAIL
  // ============================================================

  Widget _buildDetail(BuildContext context, BackendDoctorSearchResult doctor) {
    final profile = _profile;
    final pricing = _pricing ?? profile?.pricing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WebPageHeader(
          title: doctor.displayName,
          subtitle: '${doctor.specialization} · '
              '${doctor.hospitalName.isEmpty ? 'Praktik mandiri' : doctor.hospitalName}',
          trailing: TextButton.icon(
            key: const Key('web-detail-back'),
            onPressed: _backToCatalog,
            icon: const Icon(Icons.arrow_back_rounded, size: 17),
            label: const Text('Kembali ke katalog'),
          ),
        ),
        const SizedBox(height: WebSpacing.section),
        if (_detailLoading)
          const WebAdminCard(child: WebAdminLoading(label: 'Memuat profil...'))
        else if (_detailError != null)
          WebAdminCard(
            child: WebAdminError(
              error: _detailError!,
              onRetry: () => unawaited(_openDetail(doctor)),
            ),
          )
        else ...<Widget>[
          WebAdminCard(child: _buildProfileHeader(doctor, profile)),
          if (pricing != null) ...<Widget>[
            const SizedBox(height: 16),
            const WebSectionTitle(text: 'HARGA LAYANAN'),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final options = webServiceOptions(pricing);
                final columns = constraints.maxWidth >= 900 ? 3 : 1;
                final width = (constraints.maxWidth -
                        WebSpacing.cardGap * (columns - 1)) /
                    columns;
                return Wrap(
                  spacing: WebSpacing.cardGap,
                  runSpacing: WebSpacing.cardGap,
                  children: options
                      .map(
                        (WebServiceOption option) => SizedBox(
                          width: width,
                          child: WebAdminCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Text(
                                  option.label,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  formatRupiah(option.price),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '${option.durationMinutes} menit',
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    color: Color(0xFF8B8194),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
          ],
          const SizedBox(height: 16),
          WebAdminCard(child: _buildSlotsSection()),
          const SizedBox(height: 16),
          WebAdminCard(child: _buildReviews(profile)),
        ],
      ],
    );
  }

  Widget _buildProfileHeader(
    BackendDoctorSearchResult doctor,
    BackendDoctorProfile? profile,
  ) {
    final credential = profile?.credential;
    final reviews = profile?.reviews;
    final rating = reviews?.averageStars ?? 0;
    final reviewCount = reviews?.reviewCount ?? doctor.reviewCount;
    final education = credential?.education ?? const <Map<String, dynamic>>[];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: ProfessionalPhoto(
                photoUrl: doctor.photoIntroUrl,
                width: 84,
                height: 84,
                fallback: Container(
                  width: 84,
                  height: 84,
                  color: MalvaColors.seed.withValues(alpha: 0.12),
                  alignment: Alignment.center,
                  child: Text(
                    doctor.displayName.isEmpty
                        ? '?'
                        : doctor.displayName.characters.first.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w900,
                      color: MalvaColors.plum,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: <Widget>[
                      WebStatusPill(
                        label: webDoctorGroupOf(doctor.specialization).label,
                        color: MalvaColors.seed,
                      ),
                      if (doctor.isBpjsSupported)
                        const WebStatusPill(
                          label: 'BPJS',
                          color: MalvaColors.mint,
                        ),
                      if (doctor.isAvailableToday == true)
                        const WebStatusPill(
                          label: 'Tersedia hari ini',
                          color: MalvaColors.orchid,
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    doctor.hospitalName.isEmpty
                        ? 'Praktik mandiri'
                        : doctor.hospitalName,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      const Icon(Icons.star_rounded,
                          size: 16, color: MalvaColors.amber),
                      const SizedBox(width: 4),
                      Text(
                        rating > 0
                            ? '${rating.toStringAsFixed(1)} ($reviewCount ulasan)'
                            : 'Belum ada ulasan',
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${doctor.yearsExperience} tahun praktik',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF6B6377),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              key: const Key('web-detail-book'),
              onPressed: () => unawaited(_openBooking()),
              icon: const Icon(Icons.event_available_rounded, size: 18),
              label: const Text('Booking sesi'),
            ),
          ],
        ),
        if ((credential?.bio ?? doctor.bio).isNotEmpty) ...<Widget>[
          const SizedBox(height: 14),
          Text(
            credential?.bio ?? doctor.bio,
            style: const TextStyle(fontSize: 12.5, height: 1.6),
          ),
        ],
        if (education.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          const Text(
            'PENDIDIKAN',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
              color: Color(0xFF8B8194),
            ),
          ),
          const SizedBox(height: 6),
          ...education.take(4).map(
                (Map<String, dynamic> item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• ${item.entries.map((MapEntry<String, dynamic> e) => '${e.value}').where((String v) => v.trim().isNotEmpty).join(' · ')}',
                    style: const TextStyle(fontSize: 12, height: 1.45),
                  ),
                ),
              ),
        ],
        if ((credential?.subSpecialties ?? const <String>[])
            .isNotEmpty) ...<Widget>[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: (credential?.subSpecialties ?? const <String>[])
                .map((String item) => WebStatusPill(
                      label: item,
                      color: const Color(0xFF8B8194),
                    ))
                .toList(growable: false),
          ),
        ],
      ],
    );
  }

  Widget _buildSlotsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const WebSectionTitle(text: 'SLOT 7 HARI KE DEPAN'),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _days.map((String day) {
            final selected = day == _detailDate;
            return InkWell(
              key: Key('web-detail-date-$day'),
              borderRadius: BorderRadius.circular(10),
              onTap: () {
                setState(() => _detailDate = day);
                unawaited(_loadDetailSlots());
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: selected ? MalvaColors.seed : const Color(0xFFF7F3FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color:
                        selected ? MalvaColors.seed : const Color(0xFFEADFF2),
                  ),
                ),
                child: Text(
                  webShortDateLabel(day),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : MalvaColors.ink,
                  ),
                ),
              ),
            );
          }).toList(growable: false),
        ),
        const SizedBox(height: 12),
        if (_slotsLoading)
          const Text(
            'Memuat slot...',
            style: TextStyle(fontSize: 12, color: Color(0xFF8B8194)),
          )
        else if (_detailSlots.isEmpty)
          const Text(
            'Belum ada slot tersedia pada tanggal ini.',
            style: TextStyle(fontSize: 12, color: Color(0xFF8B8194)),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _detailSlots
                .map(
                  (BackendDoctorSlot slot) => Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F3FA),
                      borderRadius: BorderRadius.circular(9),
                      border: Border.all(color: const Color(0xFFEADFF2)),
                    ),
                    child: Text(
                      slot.time.length >= 5
                          ? slot.time.substring(0, 5)
                          : slot.time,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
                .toList(growable: false),
          ),
      ],
    );
  }

  Widget _buildReviews(BackendDoctorProfile? profile) {
    final reviews = profile?.reviews;
    final items = reviews?.reviews ?? const <BackendDoctorReviewItem>[];
    if (items.isEmpty) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Text('Belum ada ulasan untuk profesional ini.',
            style: TextStyle(fontSize: 12.5, color: Color(0xFF8B8194))),
        _reviewActions(),
      ]);
    }
    final visible = _showAllReviews ? items : items.take(5).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            const WebSectionTitle(text: 'ULASAN'),
            const Spacer(),
            Text(
              '${reviews?.reviewCount ?? items.length} ulasan',
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF8B8194)),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...visible.map(
          (BackendDoctorReviewItem review) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text(
                      review.patientName.isEmpty
                          ? 'Pasien'
                          : review.patientName,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      children: List<Widget>.generate(
                        5,
                        (int index) => Icon(
                          index < review.stars
                              ? Icons.star_rounded
                              : Icons.star_border_rounded,
                          size: 13,
                          color: MalvaColors.amber,
                        ),
                      ),
                    ),
                  ],
                ),
                if (review.reviewText.trim().isNotEmpty) ...<Widget>[
                  const SizedBox(height: 4),
                  Text(
                    review.reviewText,
                    style: const TextStyle(fontSize: 12.5, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (!_showAllReviews && items.length > 5)
          TextButton(
            key: const Key('web-detail-all-reviews'),
            onPressed: () => setState(() => _showAllReviews = true),
            child: const Text('Lihat semua ulasan'),
          ),
        _reviewActions(),
      ],
    );
  }

  Widget _reviewActions() => DoctorReviewActions(
        apiClient: ref.read(apiClientProvider),
        professionalId: _selected!.userId,
        accessToken: _token.isEmpty ? null : _token,
        onSubmitted: () {
          ref.read(professionalProfileRevisionProvider.notifier).state++;
          unawaited(_openDetail(_selected!));
        },
      );
}

/// Kartu profesional pada katalog.
class _DoctorCard extends ConsumerWidget {
  const _DoctorCard({required this.doctor, required this.onOpen});

  final BackendDoctorSearchResult doctor;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(patientLocationProvider).position;
    final km = distanceKmBetween(
        fromLat: position?.latitude,
        fromLng: position?.longitude,
        toLat: doctor.hospitalLat,
        toLng: doctor.hospitalLng);
    return Container(
      padding: const EdgeInsets.all(WebSpacing.card),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(WebSpacing.radius),
        border: Border.all(color: const Color(0xFFEDE6F1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: ProfessionalPhoto(
                  photoUrl: doctor.photoIntroUrl,
                  width: 46,
                  height: 46,
                  fallback: Container(
                    width: 46,
                    height: 46,
                    color: MalvaColors.seed.withValues(alpha: 0.12),
                    alignment: Alignment.center,
                    child: Text(
                      doctor.displayName.isEmpty
                          ? '?'
                          : doctor.displayName.characters.first.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: MalvaColors.plum,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      doctor.displayName,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      doctor.specialization.isEmpty
                          ? '—'
                          : doctor.specialization,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF6B6377),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            doctor.hospitalName.isEmpty
                ? 'Praktik mandiri'
                : doctor.hospitalName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B6377)),
          ),
          const SizedBox(height: 8),
          Text(
              professionalDistanceLabel(
                  km: km,
                  hospitalLat: doctor.hospitalLat,
                  hospitalLng: doctor.hospitalLng),
              style: const TextStyle(fontSize: 11.5)),
          Row(
            children: <Widget>[
              const Icon(Icons.star_rounded,
                  size: 15, color: MalvaColors.amber),
              const SizedBox(width: 3),
              Text(
                doctor.reviewCount > 0
                    ? '${doctor.averageStars.toStringAsFixed(1)} / 5 (${doctor.reviewCount} ulasan)'
                    : 'Belum ada ulasan',
                style: const TextStyle(fontSize: 11.5),
              ),
              const SizedBox(width: 10),
              Text(
                '${doctor.yearsExperience} thn',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF6B6377),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              if (doctor.isBpjsSupported)
                const WebStatusPill(label: 'BPJS', color: MalvaColors.mint),
              if (doctor.isAvailableToday == true)
                const WebStatusPill(
                  label: 'Hari ini',
                  color: MalvaColors.orchid,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  doctor.priceFrom > 0
                      ? 'Mulai ${formatRupiah(doctor.priceFrom)}'
                      : 'Harga menyusul',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              FilledButton(
                key: Key('web-doctor-open-${doctor.userId}'),
                onPressed: onOpen,
                child: const Text('Lihat'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
