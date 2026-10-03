import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../providers/providers.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/malva_components.dart';
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
  String? _error;
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
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Login diperlukan untuk mencari profesional.';
        });
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final doctors = await apiClient.searchDoctors(
        accessToken: accessToken,
        specialization: _specialization,
        isBpjsSupported: _bpjsOnly,
        sortBy: _sortBy,
      );
      if (!mounted) return;
      setState(() {
        _doctors = doctors;
        _isLoading = false;
      });
    } on MalvaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Gagal memuat daftar profesional: $e';
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
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              _ErrorCard(error: _error!, onRetry: _load)
            else if (_filtered.isEmpty)
              const EmptyState(
                icon: Icons.medical_services_outlined,
                title: 'Belum ada profesional',
                subtitle:
                    'Belum ada profesional terverifikasi yang cocok dengan filter.',
              )
            else
              for (final doctor in _filtered) ...[
                _DoctorCard(
                  doctor: doctor,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => DoctorProfileScreen(
                          doctorUserId: doctor.userId,
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

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        children: [
          Text(error,
              style: const TextStyle(
                  color: MalvaColors.danger, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Coba Lagi'),
          ),
        ],
      ),
    );
  }
}

class _DoctorCard extends StatelessWidget {
  const _DoctorCard({required this.doctor, required this.onTap});

  final BackendDoctorSearchResult doctor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final helpful = doctor.reviewCount == 0
        ? 0
        : ((doctor.helpfulnessPercent)).clamp(0, 100);
    return SoftCard(
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 30,
            backgroundColor: MalvaColors.seed.withValues(alpha: 0.12),
            child: Text(
              doctor.displayName.isEmpty
                  ? '?'
                  : doctor.displayName.characters.first.toUpperCase(),
              style: const TextStyle(
                color: MalvaColors.seed,
                fontWeight: FontWeight.w900,
                fontSize: 22,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    StatusPill(
                      label: doctor.specialization.isEmpty
                          ? 'Profesional'
                          : doctor.specialization,
                      color: MalvaColors.orchid,
                    ),
                    if (doctor.isBpjsSupported)
                      const StatusPill(
                        label: 'BPJS',
                        color: MalvaColors.mint,
                        icon: Icons.verified_rounded,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  doctor.displayName,
                  style: const TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 2,
                  children: [
                    _Stat(Icons.work_history_rounded,
                        '${doctor.legacyCount}+ Sesi'),
                    _Stat(Icons.thumb_up_rounded,
                        '$helpful% Terbantu (${doctor.reviewCount})'),
                    _Stat(Icons.workspace_premium_rounded,
                        '${doctor.yearsExperience} Thn'),
                    if (doctor.distanceKm != null)
                      _Stat(Icons.place_rounded,
                          '${doctor.distanceKm!.toStringAsFixed(1)} km'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: onTap,
            style: FilledButton.styleFrom(
              backgroundColor: MalvaColors.amber,
              foregroundColor: MalvaColors.ink,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              minimumSize: Size.zero,
            ),
            child: const Text('Lihat',
                style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.icon, this.label);

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: MalvaColors.seed),
        const SizedBox(width: 3),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}
