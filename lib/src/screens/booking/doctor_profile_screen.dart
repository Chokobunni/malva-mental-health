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
import '../chat_screen.dart';
import 'booking_detail_screen.dart';

// ============================================================
// PROFESSIONAL INFO — layout persis Figma "Professional Info":
//   Header nama + rating + usia
//   Intro video button
//   Harga per sesi (Chat/Video/Offline) + faskes + jarak + jadwal
//   BPJS badge
//   Dropdown Profile & Speciality
//   Reviews (rating + list ulasan)
//   Choose Your Support Level:
//     - Quick Consult (One-Time)     [dengan fitur + cross sharing]
//     - Continuous Support (Best Value)  [7 Days of Asynchronous Care]
//   CTA: Book Session / 7 Days Continuous Care (+ tombol Chat bila terhubung)
// ============================================================

class DoctorProfileScreen extends ConsumerStatefulWidget {
  const DoctorProfileScreen({
    super.key,
    required this.doctorUserId,
    this.doctorName,
    this.session,
    this.apiClient,
    this.demoProfile,
  });

  final String doctorUserId;
  final String? doctorName;
  final AuthSession? session;
  final MalvaApiClient? apiClient;

  /// Profil demo (offline) — bila diisi, tidak ada panggilan jaringan.
  final BackendDoctorProfile? demoProfile;

  @override
  ConsumerState<DoctorProfileScreen> createState() =>
      _DoctorProfileScreenState();
}

class _DoctorProfileScreenState extends ConsumerState<DoctorProfileScreen> {
  BackendDoctorProfile? _profile;
  List<BackendDoctorSlot> _todaySlots = const [];
  bool _isLoading = true;
  Object? _error;
  bool _profileExpanded = true;
  bool _specialityExpanded = true;
  // 'quick' | 'continuous'
  String _selectedPlan = 'quick';
  String _serviceType = 'chat';
  bool _checkingLink = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Jalur demo/offline: data lokal langsung tampil.
    final demoOverride = widget.demoProfile ??
        findDemoProfessional(widget.doctorUserId)?.toProfile();
    if (demoOverride != null) {
      final demo = findDemoProfessional(widget.doctorUserId);
      if (!mounted) return;
      setState(() {
        _profile = demoOverride;
        _todaySlots = demo?.demoSlotsFor(DateTime.now()) ?? const [];
        _isLoading = false;
        _error = null;
      });
      return;
    }
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
    } on Object catch (e) {
      if (!mounted) return;
      // Fallback terakhir: direktori demo agar tidak kosong.
      final demo = findDemoProfessional(widget.doctorUserId);
      if (demo != null) {
        setState(() {
          _profile = demo.toProfile();
          _todaySlots = demo.demoSlotsFor(DateTime.now());
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = e;
          _isLoading = false;
        });
      }
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
                          // ===== HEADER: nama + rating + usia =====
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ProfessionalAvatar(
                                displayName: _displayName,
                                radius: 32,
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                            size: 17, color: MalvaColors.amber),
                                        const SizedBox(width: 3),
                                        const Text(
                                          '4.8 (15)',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13),
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          '${_genderLabel}, 45 y.o',
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
                          const SizedBox(height: 14),

                          // ===== INTRO VIDEO — Figma Group 276 =====
                          SoftCard(
                            onTap: () {},
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor:
                                      MalvaColors.seed.withValues(alpha: 0.12),
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

                          // ===== HARGA PER SESI + FASKES + JADWAL =====
                          _PriceRow(
                              label: 'Chat session', price: _chatPrice(cred)),
                          _PriceRow(
                              label: 'Video session', price: _videoPrice(cred)),
                          _PriceRow(
                              label: 'Offline session',
                              price: _offlinePrice(cred)),
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
                          if (_todaySlots.isNotEmpty)
                            Text(
                              '${_todayName()}: ${_todaySlots.first.time} - ${_todaySlots.last.time}',
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

                          // ===== REVIEWS =====
                          const SectionLabel('Reviews'),
                          const _ReviewCard(
                            name: 'Dahlia',
                            text: 'Amazing Doctor.',
                            date: '27 September 2024, 15.40',
                            stars: 5,
                          ),
                          const SizedBox(height: 8),
                          const _ReviewCard(
                            name: 'Vincent',
                            text: 'Sangat membantu, komunikasi enak.',
                            date: '15 September 2024, 16.00',
                            stars: 5,
                          ),
                          const SizedBox(height: 8),
                          const _ReviewCard(
                            name: 'Naomi',
                            text: 'Penjelasan jelas dan menenangkan.',
                            date: '1 September 2024, 17.28',
                            stars: 5,
                          ),
                          const SizedBox(height: 16),

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
                            'This service is for ongoing support, not emergencies. If you are in crisis, call 112',
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
                            subtitle: null,
                            price:
                                'Rp. ${_rupiah(_quickFrom(cred))} - ${_rupiah(_quickTo(cred))} / Session',
                            featureIcon: Icons.payments_rounded,
                            features: [
                              (
                                'Rp. ${_rupiah(_quickFrom(cred))} - ${_rupiah(_quickTo(cred))} / Session',
                                Icons.payments_rounded
                              ),
                              (
                                '30-minute chat/video session',
                                Icons.record_voice_over_rounded
                              ),
                              (
                                'No data sharing or follow-up',
                                Icons.cancel_rounded
                              ),
                            ],
                            scheduleChips: const ['Chat', 'Video'],
                            scheduleLines: _scheduleLines(),
                          ),
                          const SizedBox(height: 12),

                          // ===== OPSI 2: CONTINUOUS SUPPORT =====
                          _SupportPlanCard(
                            selected: _selectedPlan == 'continuous',
                            onSelect: () =>
                                setState(() => _selectedPlan = 'continuous'),
                            title: 'Continuous Support (Best Value)',
                            subtitle: 'Write anytime 24/7. Replies Mon-Fri.',
                            badge: (
                              '7 Days of Asynchronous Care',
                              Icons.handshake_rounded
                            ),
                            price: 'Rp.199rb / week',
                            featureIcon: Icons.bar_chart_rounded,
                            features: const [
                              ('Data Monitoring', Icons.insert_chart_rounded),
                              (
                                '24/7 Asynchronous Chat',
                                Icons.schedule_rounded
                              ),
                              ('20% OFF Video Sessions', Icons.savings_rounded),
                            ],
                            footnote:
                                '7 hari penuh sejak tanggal mulai. Tanpa perpanjangan otomatis.',
                            quota: 'Termasuk monitoring data 7 hari',
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
                                ? '7 Days Continuous Care'
                                : 'Book Session'),
                          ),
                          const SizedBox(height: 8),
                          OutlinedButton.icon(
                            onPressed:
                                _checkingLink ? null : () => _openChat(context),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48),
                            ),
                            icon: _checkingLink
                                ? const SizedBox.square(
                                    dimension: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.chat_bubble_rounded),
                            label:
                                Text(_checkingLink ? 'Memeriksa...' : 'Chat'),
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
    final cred = _profile?.credential;
    if (cred == null) return 'Profesional';
    return 'dr. Profesional ${cred.specialization}';
  }

  String get _shortName {
    final parts = _displayName.split(' ');
    final name = parts
        .skip(1)
        .takeWhile((p) => !p.contains(','))
        .toList(growable: false);
    return name.isEmpty ? _displayName : name.first;
  }

  String get _genderLabel => 'Male';

  int _chatPrice(BackendProfessionalCredential cred) =>
      cred.priceFrom > 0 ? cred.priceFrom : 80000;

  int _videoPrice(BackendProfessionalCredential cred) =>
      cred.priceFrom > 0 ? (cred.priceFrom * 1.9).round() : 150000;

  int _offlinePrice(BackendProfessionalCredential cred) =>
      cred.priceFrom > 0 ? (cred.priceFrom * 2).round() : 300000;

  int _quickFrom(BackendProfessionalCredential cred) =>
      cred.priceFrom > 0 ? cred.priceFrom : 80000;

  int _quickTo(BackendProfessionalCredential cred) =>
      cred.priceFrom > 0 ? (cred.priceFrom * 1.9).round() : 150000;

  String _faskesDistanceLabel(BackendProfessionalCredential cred) {
    final faskes = cred.hospitalName.isEmpty
        ? 'Faskes tidak dicantumkan'
        : cred.hospitalName;
    final pos = ref.watch(patientLocationProvider).position;
    final km = distanceKmBetween(
      fromLat: pos?.latitude,
      fromLng: pos?.longitude,
      toLat: _hospitalLat(cred),
      toLng: _hospitalLng(cred),
    );
    if (km == null) return faskes;
    return '$faskes, ${km.toStringAsFixed(1)} km';
  }

  double? _hospitalLat(BackendProfessionalCredential cred) {
    // Demo profile tidak menyimpan koordinat pada credential; ambil dari demo.
    final demo = findDemoProfessional(widget.doctorUserId);
    return demo?.entry.hospitalLat;
  }

  double? _hospitalLng(BackendProfessionalCredential cred) {
    final demo = findDemoProfessional(widget.doctorUserId);
    return demo?.entry.hospitalLng;
  }

  String _todayName() {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    return days[DateTime.now().weekday - 1];
  }

  List<String> _scheduleLines() {
    if (_todaySlots.isEmpty) {
      return const ['Monday: 09:00 - 11:00', 'Tuesday: 09:00 - 11:00'];
    }
    return [
      '$_todayName(): ${_todaySlots.first.time} - ${_todaySlots.last.time}',
    ];
  }

  void _proceed() {
    final cred = _profile?.credential;
    if (cred == null) return;
    if (_selectedPlan == 'continuous') {
      _openContinuousBooking(cred);
    } else {
      _openBooking(context, null);
    }
  }

  /// Tombol Chat: bila sudah terhubung (link aktif) langsung buka chat
  /// dengan dokter ini; bila belum, arahkan mulai 7 Days Continuous Care.
  Future<void> _openChat(BuildContext context) async {
    final MalvaApiClient apiClient =
        widget.apiClient ?? ref.read(apiClientProvider);
    final accessToken = widget.session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Masuk dulu untuk chat dengan profesional.')),
      );
      return;
    }
    setState(() => _checkingLink = true);
    try {
      final links = await apiClient.listPatientProfessionalLinks(
        accessToken: accessToken,
      );
      final linked = links.any((l) =>
          l.status == 'active' &&
          (l.professionalUserId == widget.doctorUserId ||
              l.professionalId == widget.doctorUserId));
      if (!mounted) return;
      setState(() => _checkingLink = false);
      if (!linked) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Kamu belum terhubung dengan dokter ini. Mulai 7 Days Continuous Care untuk chat 24/7.')),
        );
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            otherUserName: _displayName,
            otherUserId: widget.doctorUserId,
          ),
        ),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _checkingLink = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(e))),
      );
    }
  }

  void _openContinuousBooking(BackendProfessionalCredential cred) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BookingDetailScreen(
          doctorUserId: widget.doctorUserId,
          doctorName: _displayName,
          serviceType: _serviceType,
          isContinuousSupport: true,
          package: null,
          session: widget.session,
          apiClient: widget.apiClient,
        ),
      ),
    );
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
              for (var i = 0; i < stars; i++)
                const Icon(Icons.star_rounded,
                    size: 14, color: MalvaColors.amber),
            ],
          ),
          const SizedBox(height: 6),
          Text(text, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 4),
          Text(date,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.black54)),
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
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: MalvaColors.seed.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(chip,
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 12.5)),
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
