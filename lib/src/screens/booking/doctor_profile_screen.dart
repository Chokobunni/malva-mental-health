import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/malva_components.dart';
import 'booking_detail_screen.dart';

// ============================================================
// DOCTOR PROFILE — STR/SIPP, video, education, topics, packages
// ============================================================

class DoctorProfileScreen extends ConsumerStatefulWidget {
  const DoctorProfileScreen({
    super.key,
    required this.doctorUserId,
    this.session,
    this.apiClient,
  });

  final String doctorUserId;
  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<DoctorProfileScreen> createState() =>
      _DoctorProfileScreenState();
}

class _DoctorProfileScreenState extends ConsumerState<DoctorProfileScreen> {
  BackendDoctorProfile? _profile;
  List<BackendDoctorSlot> _todaySlots = const [];
  bool _isLoading = true;
  String? _error;
  String _serviceType = 'chat';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Login diperlukan untuk melihat profil profesional.';
        });
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final profile = await apiClient.getDoctorProfile(
        accessToken: accessToken,
        userId: widget.doctorUserId,
      );
      final today = DateTime.now();
      final dateStr =
          '${today.year.toString().padLeft(4, '0')}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      List<BackendDoctorSlot> slots = const [];
      try {
        slots = await apiClient.getDoctorAvailableSlots(
          accessToken: accessToken,
          userId: widget.doctorUserId,
          date: dateStr,
        );
      } on Object catch (_) {
        // Slot opsional — profil tetap tampil.
      }
      if (!mounted) return;
      setState(() {
        _profile = profile;
        _todaySlots = slots;
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
        _error = 'Gagal memuat profil: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cred = _profile?.credential;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil Profesional'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: MalvaColors.danger,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
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
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 34,
                                  backgroundColor:
                                      MalvaColors.seed.withValues(alpha: 0.12),
                                  child: const Icon(
                                      Icons.medical_services_rounded,
                                      color: MalvaColors.seed,
                                      size: 34),
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
                                            fontSize: 17),
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          StatusPill(
                                            label: cred.specialization.isEmpty
                                                ? 'Profesional'
                                                : cred.specialization,
                                            color: MalvaColors.orchid,
                                          ),
                                          const StatusPill(
                                            label: 'Terverifikasi',
                                            color: MalvaColors.mint,
                                            icon: Icons.verified_rounded,
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const SectionLabel('Lisensi Praktik'),
                          SoftCard(
                            child: Column(
                              children: [
                                _LicenseRow(
                                    label: 'SIPP',
                                    value: cred.strNumber.isEmpty
                                        ? '-'
                                        : cred.strNumber),
                                const Divider(height: 20),
                                _LicenseRow(
                                    label: 'STR',
                                    value: cred.sippNumber.isEmpty
                                        ? '-'
                                        : cred.sippNumber),
                              ],
                            ),
                          ),
                          SoftCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Review pasien',
                                    style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 15)),
                                const SizedBox(height: 4),
                                const Text(
                                    'Ulasan pasien akan tampil di sini setelah sesi selesai.',
                                    style: TextStyle(color: Colors.black54)),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const SectionLabel('Profil'),
                          SoftCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.play_circle_fill_rounded,
                                        color: MalvaColors.seed),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Tonton Intro Video',
                                        style: TextStyle(
                                            fontWeight: FontWeight.w900),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Video perkenalan profesional segera hadir.',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          const SectionLabel('Jadwal Tersedia Hari Ini'),
                          SoftCard(
                            child: _todaySlots.isEmpty
                                ? const Text(
                                    'Tidak ada slot hari ini. Pilih tanggal lain saat booking.')
                                : Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      for (final slot in _todaySlots.take(8))
                                        Chip(
                                          label: Text(slot.time,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w700)),
                                          backgroundColor: slot.available
                                              ? MalvaColors.mint
                                                  .withValues(alpha: 0.15)
                                              : Colors.black12,
                                        ),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 12),
                          const SectionLabel('Pilih Layanan'),
                          Row(
                            children: [
                              Expanded(
                                child: SegmentedButton<String>(
                                  segments: const [
                                    ButtonSegment(
                                        value: 'chat', label: Text('Online')),
                                    ButtonSegment(
                                        value: 'video', label: Text('Video')),
                                  ],
                                  selected: {_serviceType},
                                  onSelectionChanged: (s) =>
                                      setState(() => _serviceType = s.first),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          SectionLabel(
                            'Pilih Paket',
                            action: _profile!.packages.isEmpty
                                ? null
                                : TextButton(
                                    onPressed: () =>
                                        _openBooking(context, null),
                                    child: const Text('Sekali jalan'),
                                  ),
                          ),
                          if (_profile!.packages.isEmpty)
                            const EmptyState(
                              icon: Icons.card_membership_outlined,
                              title: 'Belum ada paket',
                              subtitle:
                                  'Profesional ini belum mengatur paket sesi.',
                            )
                          else
                            for (final pkg in _profile!.packages) ...[
                              _PackageCard(
                                package: pkg,
                                onBook: () => _openBooking(context, pkg),
                              ),
                              const SizedBox(height: 10),
                            ],
                        ],
                      ),
                    ),
    );
  }

  String get _displayName {
    final cred = _profile?.credential;
    if (cred == null) return 'Profesional';
    return 'dr. Profesional ${cred.specialization}';
  }

  void _openBooking(BuildContext context, BackendServicePackage? package) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingDetailScreen(
          doctorUserId: widget.doctorUserId,
          doctorName: _displayName,
          serviceType: _serviceType,
          package: package,
          session: widget.session,
          apiClient: widget.apiClient,
        ),
      ),
    );
  }
}

class _LicenseRow extends StatelessWidget {
  const _LicenseRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
        ),
        Expanded(
          child: Text(value.isEmpty ? '-' : value,
              style: Theme.of(context).textTheme.bodyMedium),
        ),
        const Icon(Icons.verified_rounded, size: 18, color: MalvaColors.mint),
      ],
    );
  }
}

class _PackageCard extends StatelessWidget {
  const _PackageCard({required this.package, required this.onBook});

  final BackendServicePackage package;
  final VoidCallback onBook;

  String get _priceLabel => 'Rp ${_formatRupiah(package.price)}';

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onBook,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '${package.packageSessions} Sesi',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16),
                      ),
                    ),
                    if (package.label.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: MalvaColors.seed,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          package.label,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Berlaku hingga ${package.packageDurationDays} hari • $_priceLabel',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton(
            onPressed: onBook,
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
            ),
            child: const Text('Booking'),
          ),
        ],
      ),
    );
  }

  static String _formatRupiah(int value) {
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
