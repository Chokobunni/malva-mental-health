import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../professional_role.dart';
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
  int _loadGeneration = 0;

  static const _sortOptions = [
    ('name_asc', 'Nama A-Z'),
    ('name_desc', 'Nama Z-A'),
    ('availability', 'Kesediaan Jadwal'),
    ('sessions', 'Sesi Terbanyak'),
    ('popular', 'Populer'),
    ('distance', 'Terdekat'),
  ];

  static const _filters = [
    ('', 'Semua'),
    ('Sp.KJ', 'Sp.KJ'),
    ('M.Psi', 'M.Psi'),
    ('bpjs', 'BPJS (Offline)'),
  ];

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

  /// Muat direktori profesional dari server (tanpa data demo).
  /// [silent] dipakai saat penyegaran otomatis agar daftar tidak berkedip.
  Future<void> _load({bool silent = false}) async {
    final generation = ++_loadGeneration;
    final MalvaApiClient apiClient =
        widget.apiClient ?? ref.read(apiClientProvider);
    final rawToken = widget.session?.accessToken;
    final accessToken =
        (rawToken == null || rawToken.isEmpty) ? null : rawToken;
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
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
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _doctors = doctors;
        _offlineMode = false;
        _isLoading = false;
      });
    } on Object catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _doctors = const [];
        _offlineMode = true;
        _error = e;
        _isLoading = false;
      });
    }
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
    ref.listen<PatientLocationState>(patientLocationProvider, (previous, next) {
      if (previous?.position != next.position) unawaited(_load(silent: true));
    });
    // Foto profesional berubah → segarkan daftar tanpa mengganggu pencarian.
    ref.listen<int>(professionalProfileRevisionProvider, (previous, next) {
      if (previous != next) {
        unawaited(_load(silent: true));
      }
    });
    return Scaffold(
      backgroundColor: const Color(0xfff8f8fb),
      appBar: AppBar(
        title: const Text('Cari Profesional'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 4,
                  child: _LabeledControl(
                    label: 'URUTKAN',
                    child: DropdownButtonFormField<String>(
                      initialValue: _sortBy,
                      isExpanded: true,
                      decoration: _discoveryInput(),
                      items: [
                        for (final (value, label) in _sortOptions)
                          DropdownMenuItem(
                            value: value,
                            child: Text(label, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() => _sortBy = value);
                        unawaited(_load());
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 6,
                  child: _LabeledControl(
                    label: 'CARI',
                    child: TextField(
                      controller: _searchController,
                      decoration: _discoveryInput(
                        hintText: 'Nama profesional…',
                        suffixIcon: const Icon(Icons.search_rounded),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final wrap = constraints.maxWidth < 320 ||
                    MediaQuery.textScalerOf(context).scale(1) > 1.3;
                final selectedFilter =
                    _bpjsOnly == true ? 'bpjs' : _specialization;
                final buttons = [
                  for (final (filter, label) in _filters)
                    Semantics(
                      selected: selectedFilter == filter,
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 48),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          backgroundColor: selectedFilter == filter
                              ? MalvaColors.plum
                              : Colors.white,
                          foregroundColor: selectedFilter == filter
                              ? Colors.white
                              : const Color(0xff4c5a6a),
                          side: const BorderSide(color: Color(0xffe6e8ef)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                        onPressed: () {
                          setState(() {
                            _specialization = filter == 'bpjs' ? '' : filter;
                            _bpjsOnly = filter == 'bpjs' ? true : null;
                          });
                          unawaited(_load());
                        },
                        child: Text(
                          selectedFilter.isEmpty && filter.isEmpty
                              ? '✓ $label'
                              : label,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ];
                if (wrap) {
                  return Wrap(spacing: 6, runSpacing: 6, children: buttons);
                }
                return Row(spacing: 6, children: [
                  for (final button in buttons) Expanded(child: button),
                ]);
              },
            ),
            const Divider(height: 28),
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
                  message: 'Tidak terhubung ke server. '
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

InputDecoration _discoveryInput({String? hintText, Widget? suffixIcon}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(18),
    borderSide: const BorderSide(color: Color(0xffe5e8ef)),
  );
  return InputDecoration(
    hintText: hintText,
    hintStyle: const TextStyle(color: Color(0xff8694a5)),
    suffixIcon: suffixIcon,
    suffixIconColor: const Color(0xff8694a5),
    filled: true,
    fillColor: const Color(0xfff5f7fa),
    enabledBorder: border,
    border: border,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  );
}

class _LabeledControl extends StatelessWidget {
  const _LabeledControl({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xff738297),
                  fontSize: 11,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          child,
        ],
      );
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

  @override
  Widget build(BuildContext context) {
    final km = distanceKmBetween(
      fromLat: patientLat,
      fromLng: patientLng,
      toLat: doctor.hospitalLat,
      toLng: doctor.hospitalLng,
    );
    final showInlineBpjs = doctor.isBpjsSupported &&
        MediaQuery.sizeOf(context).width >= 380 &&
        MediaQuery.textScalerOf(context).scale(1) <= 1.15;
    const bpjs = StatusPill(label: 'BPJS (Offline)', color: Color(0xff107356));
    return SoftCard(
      radius: 22,
      color: Colors.white,
      outline: const BorderSide(color: Color(0xffe8e8ef)),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ProfessionalAvatar(
              displayName: doctor.displayName,
              radius: 26,
              photoUrl: doctor.photoIntroUrl,
              borderRadius: BorderRadius.circular(15),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(spacing: 4, children: [
                      Expanded(
                        child: Text(doctor.displayName,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16),
                            maxLines: showInlineBpjs ? 1 : 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (showInlineBpjs) bpjs,
                    ]),
                    const SizedBox(height: 3),
                    Text(professionalRoleLabel(doctor.specialization),
                        style: const TextStyle(color: Color(0xff647388))),
                    if (doctor.isBpjsSupported && !showInlineBpjs) ...[
                      const SizedBox(height: 4),
                      bpjs,
                    ],
                    const SizedBox(height: 6),
                    Wrap(
                        spacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Icon(
                              doctor.reviewCount == 0
                                  ? Icons.star_border_rounded
                                  : Icons.star_rounded,
                              size: 17,
                              color: MalvaColors.amber),
                          Text(
                              doctor.reviewCount == 0
                                  ? 'Belum ada ulasan'
                                  : '${doctor.averageStars.toStringAsFixed(1)} / 5',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          if (doctor.reviewCount > 0)
                            Text(
                                '(${doctor.helpfulnessPercent}% terbantu • ${doctor.reviewCount} ulasan)',
                                style: const TextStyle(
                                    color: Color(0xff708096), fontSize: 11)),
                        ]),
                  ]),
            ),
            const CircleAvatar(
                radius: 13,
                backgroundColor: Color(0xfff5f7fa),
                child: Icon(Icons.chevron_right_rounded,
                    size: 19, color: Color(0xff728296))),
          ]),
          const Divider(height: 22, color: Color(0xFFF0EDF2)),
          Row(children: [
            const Icon(Icons.add_box_outlined,
                size: 20, color: MalvaColors.plum),
            const SizedBox(width: 8),
            Expanded(
                child: Text(doctor.hospitalName.isEmpty
                    ? 'Faskes tidak dicantumkan'
                    : doctor.hospitalName)),
            if (km != null)
              StatusPill(
                  label: '${km.toStringAsFixed(1)} km',
                  icon: Icons.near_me_rounded,
                  color: MalvaColors.plum),
          ]),
          if (km == null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  professionalDistanceLabel(
                      km: km,
                      hospitalLat: doctor.hospitalLat,
                      hospitalLng: doctor.hospitalLng),
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          const Divider(height: 22, color: Color(0xFFF0EDF2)),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
                child: _prices(const Color(0xfff6f7fa), [
              const Text('Biaya Quick Consult',
                  style: TextStyle(fontSize: 11, color: Color(0xff566980))),
              _quick(Icons.chat_bubble_outline_rounded, doctor.quickChatPrice),
              _quick(Icons.videocam_outlined, doctor.quickVideoPrice),
            ])),
            const SizedBox(width: 8),
            Expanded(
                child: _prices(const Color(0xffedf9f6), [
              const Text('Continuous Package',
                  style: TextStyle(fontSize: 11, color: Color(0xff177457))),
              Text(_price(doctor.packagePrice),
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, color: Color(0xff12624d))),
              const Text('4 sesi / 6 minggu',
                  style: TextStyle(fontSize: 11, color: Color(0xff177457))),
            ])),
          ]),
        ],
      ),
    );
  }

  Widget _quick(IconData icon, int price) => Row(children: [
        Icon(icon, size: 14, color: MalvaColors.plum),
        const SizedBox(width: 5),
        Flexible(
            child: Text(_price(price),
                style: const TextStyle(fontWeight: FontWeight.w800))),
      ]);

  Widget _prices(Color color, List<Widget> children) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: const Color(0xffe9ebf0)),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 4,
            children: children),
      );

  static String _price(int amount) => amount <= 0
      ? 'Belum tersedia'
      : 'Rp ${amount.toString().replaceAllMapped(RegExp(r"(\d)(?=(\d{3})+$)"), (m) => "${m[1]}.")}';
}
