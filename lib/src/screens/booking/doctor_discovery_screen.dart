import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/demo_professionals.dart';
import '../../models.dart';
import '../../providers/providers.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';
import '../../widgets/professional_avatar.dart';
import 'doctor_profile_screen.dart';

// ============================================================
// DOCTOR DISCOVERY — search + sort + trust signals
// ============================================================

class DoctorDiscoveryScreen extends ConsumerStatefulWidget {
  const DoctorDiscoveryScreen({super.key, this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<DoctorDiscoveryScreen> createState() =>
      _DoctorDiscoveryScreenState();
}

class _DoctorDiscoveryScreenState extends ConsumerState<DoctorDiscoveryScreen> {
  final _searchController = TextEditingController();
  String _sortBy = 'name_asc';
  String _specialization = '';
  bool? _bpjsOnly;
  bool _isLoading = true;
  Object? _error;
  bool _offlineMode = false;
  List<BackendDoctorSearchResult> _doctors = const [];

  static const _sortOptions = [
    ('name_asc', 'Nama A-Z'),
    ('name_desc', 'Nama Z-A'),
    ('availability', 'Kesediaan Jadwal'),
    ('sessions', 'Sesi Terbanyak'),
    ('popular', 'Populer'),
    ('distance', 'Terdekat'),
  ];

  static const _specOptions = ['', 'Sp.KJ', 'M.Psi'];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// Muat dari server bila terjangkau; selalu fallback ke direktori demo
  /// agar daftar tidak pernah kosong dan tidak menampilkan error mentah.
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
      final location = ref.read(patientLocationProvider);
      final pos = location.position;
      final doctors = await apiClient.searchDoctors(
        accessToken: accessToken,
        specialization: _specialization,
        isBpjsSupported: _bpjsOnly,
        sortBy: _sortBy,
        patientLat: pos?.latitude,
        patientLng: pos?.longitude,
      );
      if (!mounted) return;
      if (doctors.isEmpty) {
        setState(() {
          _doctors = _demoDirectory();
          _offlineMode = true;
          _isLoading = false;
        });
      } else {
        setState(() {
          _doctors = doctors;
          _offlineMode = false;
          _isLoading = false;
        });
      }
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _doctors = _demoDirectory();
        _offlineMode = true;
        _error = e;
        _isLoading = false;
      });
    }
  }

  /// Direktori demo dengan filter & urutan yang sama seperti server.
  /// Jarak dihitung lokal dari posisi pasien (bila ada) ke koordinat faskes.
  List<BackendDoctorSearchResult> _demoDirectory() {
    final pos = ref.read(patientLocationProvider).position;
    var list = demoProfessionals()
        .map((demo) => demo.entry.copyWith(
              distanceKm: distanceKmBetween(
                fromLat: pos?.latitude,
                fromLng: pos?.longitude,
                toLat: demo.entry.hospitalLat,
                toLng: demo.entry.hospitalLng,
              ),
            ))
        .toList(growable: false);
    if (_specialization.isNotEmpty) {
      list = list
          .where((d) => d.specialization == _specialization)
          .toList(growable: false);
    }
    if (_bpjsOnly == true) {
      list = list.where((d) => d.isBpjsSupported).toList(growable: false);
    }
    final sorted = list.toList();
    switch (_sortBy) {
      case 'name_desc':
        sorted.sort((a, b) => b.displayName.compareTo(a.displayName));
      case 'sessions':
        sorted.sort((a, b) => b.legacyCount.compareTo(a.legacyCount));
      case 'popular':
        sorted.sort((a, b) => b.reviewCount.compareTo(a.reviewCount));
      case 'distance':
        sorted.sort((a, b) {
          final da = a.distanceKm;
          final db = b.distanceKm;
          if (da == null && db == null) return 0;
          if (da == null) return 1;
          if (db == null) return -1;
          return da.compareTo(db);
        });
      case 'availability':
        sorted.sort((a, b) {
          final ab = (b.isAvailableToday == true ? 1 : 0) -
              (a.isAvailableToday == true ? 1 : 0);
          if (ab != 0) return ab;
          return a.displayName.compareTo(b.displayName);
        });
      default:
        sorted.sort((a, b) => a.displayName.compareTo(b.displayName));
    }
    return sorted;
  }

  List<BackendDoctorSearchResult> get _filtered {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _doctors;
    return _doctors
        .where((d) => d.displayName.toLowerCase().contains(q))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Jadwal Profesional'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _sortBy,
                    decoration: const InputDecoration(
                      labelText: 'Urutkan',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      for (final (value, label) in _sortOptions)
                        DropdownMenuItem(value: value, child: Text(label)),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _sortBy = v);
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      labelText: 'Nama profesional',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.search_rounded),
                        onPressed: () => setState(() {}),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    onSubmitted: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final spec in _specOptions)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(spec.isEmpty ? 'Semua' : spec),
                        selected: _specialization == spec,
                        onSelected: (_) {
                          setState(() => _specialization = spec);
                          _load();
                        },
                        selectedColor: MalvaColors.seed.withValues(alpha: 0.15),
                        checkmarkColor: MalvaColors.seed,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: const Text('BPJS'),
                      selected: _bpjsOnly == true,
                      onSelected: (_) {
                        setState(() {
                          _bpjsOnly = _bpjsOnly == true ? null : true;
                        });
                        _load();
                      },
                      selectedColor: MalvaColors.mint.withValues(alpha: 0.2),
                      checkmarkColor: MalvaColors.mint,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (ref.watch(patientLocationProvider).permissionDenied ||
                ref.watch(patientLocationProvider).serviceDisabled) ...[
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => ref.read(patientLocationProvider.notifier).retry(),
                child: const OfflineNoticeBanner(
                  message:
                      'Izin lokasi nonaktif. Aktifkan untuk melihat jarak faskes (km). Ketuk untuk coba lagi.',
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (_offlineMode) ...[
              InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: _isLoading ? null : _load,
                child: const OfflineNoticeBanner(
                  message: 'Menampilkan direktori contoh. '
                      'Ketuk untuk memuat ulang dari server.',
                ),
              ),
              const SizedBox(height: 14),
            ],
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_filtered.isEmpty && _error != null)
              FriendlyErrorCard(error: _error!, onRetry: _load)
            else if (_filtered.isEmpty)
              const EmptyState(
                icon: Icons.medical_services_outlined,
                title: 'Tidak ada yang cocok',
                subtitle: 'Coba ubah kata kunci atau atur ulang filter.',
              )
            else
              for (final doctor in _filtered) ...[
                _DoctorCard(
                  doctor: doctor,
                  patientLat:
                      ref.watch(patientLocationProvider).position?.latitude,
                  patientLng:
                      ref.watch(patientLocationProvider).position?.longitude,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DoctorProfileScreen(
                          doctorUserId: doctor.userId,
                          doctorName: doctor.displayName,
                          session: widget.session,
                          apiClient: widget.apiClient,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }
}

class _DoctorCard extends StatelessWidget {
  const _DoctorCard({
    required this.doctor,
    required this.onTap,
    this.patientLat,
    this.patientLng,
  });

  final BackendDoctorSearchResult doctor;
  final VoidCallback onTap;
  final double? patientLat;
  final double? patientLng;

  double? get _effectiveKm {
    if (doctor.distanceKm != null) return doctor.distanceKm;
    return distanceKmBetween(
      fromLat: patientLat,
      fromLng: patientLng,
      toLat: doctor.hospitalLat,
      toLng: doctor.hospitalLng,
    );
  }

  @override
  Widget build(BuildContext context) {
    final helpful =
        doctor.reviewCount == 0 ? 0 : doctor.helpfulnessPercent.clamp(0, 100);
    final km = _effectiveKm;
    return SoftCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfessionalAvatar(displayName: doctor.displayName, radius: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      doctor.displayName,
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 15.5),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      doctor.specialization.isEmpty
                          ? 'Profesional kesehatan jiwa'
                          : (doctor.specialization == 'Sp.KJ'
                              ? 'Psikiater'
                              : 'Psikolog Klinis'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.black54, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 16, color: MalvaColors.amber),
                        const SizedBox(width: 2),
                        const Text(
                          '4.8',
                          style: TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 12.5),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '($helpful% terbantu • ${doctor.reviewCount} ulasan)',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.black54),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.local_hospital_rounded,
                  size: 15, color: MalvaColors.seed),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  doctor.hospitalName.isEmpty
                      ? 'Faskes tidak dicantumkan'
                      : doctor.hospitalName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 12.5),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (km != null) ...[
                const SizedBox(width: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.near_me_rounded,
                        size: 14, color: MalvaColors.orchid),
                    const SizedBox(width: 3),
                    Text(
                      '${km.toStringAsFixed(1)} km',
                      style: const TextStyle(
                        color: MalvaColors.orchid,
                        fontWeight: FontWeight.w900,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
          const Divider(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Estimasi biaya',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.black54),
                    ),
                    Text(
                      doctor.priceFrom > 0
                          ? 'Rp ${_rupiah(doctor.priceFrom)}${doctor.isBpjsSupported ? ' • BPJS tersedia' : ''}'
                          : (doctor.isBpjsSupported
                              ? 'BPJS tersedia'
                              : 'Harga saat booking'),
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Lihat profil',
                    style: TextStyle(
                        color: MalvaColors.seed,
                        fontWeight: FontWeight.w800,
                        fontSize: 13),
                  ),
                  Icon(Icons.chevron_right_rounded,
                      size: 20, color: MalvaColors.seed),
                ],
              ),
            ],
          ),
        ],
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
