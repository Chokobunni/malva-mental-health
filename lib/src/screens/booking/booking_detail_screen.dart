import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';
import 'consent_request_sheet.dart';
import 'payment_screen.dart';

// ============================================================
// BOOKING DETAIL â€” tanggal + slot + paket
// ============================================================

class BookingDetailScreen extends ConsumerStatefulWidget {
  const BookingDetailScreen({
    super.key,
    required this.doctorUserId,
    required this.doctorName,
    required this.serviceType,
    this.package,
    this.isContinuousSupport = false,
    this.session,
    this.apiClient,
  });

  final String doctorUserId;
  final String doctorName;
  final String serviceType;
  final BackendServicePackage? package;

  /// True = Continuous Support 7 Days (async care + data monitoring).
  final bool isContinuousSupport;
  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<BookingDetailScreen> createState() =>
      _BookingDetailScreenState();
}

class _BookingDetailScreenState extends ConsumerState<BookingDetailScreen> {
  DateTime _date = DateTime.now().add(const Duration(days: 1));
  String? _selectedSlot;
  List<BackendDoctorSlot> _slots = const [];
  bool _isLoadingSlots = false;
  bool _isSubmitting = false;
  String? _error;

  String get _dateStr =>
      '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) return;
    setState(() {
      _isLoadingSlots = true;
      _selectedSlot = null;
    });
    try {
      final slots = await apiClient.getDoctorAvailableSlots(
        accessToken: accessToken,
        userId: widget.doctorUserId,
        date: _dateStr,
      );
      if (!mounted) return;
      setState(() {
        _slots = slots.where((s) => s.available).toList();
        _isLoadingSlots = false;
      });
    } on Object catch (_) {
      if (!mounted) return;
      setState(() {
        _slots = const [];
        _isLoadingSlots = false;
      });
    }
  }

  int get _price {
    if (widget.isContinuousSupport) return 199000; // Rp.199rb / week
    final pkg = widget.package;
    if (pkg != null) return pkg.price;
    return widget.serviceType == 'video' ? 150000 : 80000;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Detail'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SoftCard(
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: MalvaColors.seed.withValues(alpha: 0.12),
                  child: const Icon(Icons.medical_services_rounded,
                      color: MalvaColors.seed, size: 30),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.doctorName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16)),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        children: [
                          StatusPill(
                            label: widget.serviceType == 'video'
                                ? 'Video'
                                : 'Chat',
                            color: MalvaColors.orchid,
                            icon: widget.serviceType == 'video'
                                ? Icons.videocam_rounded
                                : Icons.chat_bubble_rounded,
                          ),
                          if (widget.package != null)
                            StatusPill(
                              label: '${widget.package!.packageSessions} Sesi',
                              color: MalvaColors.mint,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const SectionLabel('Pilih Tanggal'),
          SoftCard(
            child: Row(
              children: [
                IconButton(
                  onPressed: () {
                    final next = _date.subtract(const Duration(days: 1));
                    if (next.isAfter(
                        DateTime.now().subtract(const Duration(days: 1)))) {
                      setState(() => _date = next);
                      _loadSlots();
                    }
                  },
                  icon: const Icon(Icons.chevron_left_rounded),
                ),
                Expanded(
                  child: Text(
                    _prettyDate(_date),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    setState(() => _date = _date.add(const Duration(days: 1)));
                    _loadSlots();
                  },
                  icon: const Icon(Icons.chevron_right_rounded),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const SectionLabel('Pilih Jam'),
          if (_isLoadingSlots)
            const Center(child: CircularProgressIndicator())
          else if (_slots.isEmpty)
            const EmptyState(
              icon: Icons.event_busy_rounded,
              title: 'Tidak ada slot',
              subtitle:
                  'Tidak ada jadwal tersedia pada tanggal ini. Coba tanggal lain.',
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final slot in _slots)
                  ChoiceChip(
                    label: Text(slot.time,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    selected: _selectedSlot == slot.time,
                    onSelected: (_) =>
                        setState(() => _selectedSlot = slot.time),
                    selectedColor: MalvaColors.seed.withValues(alpha: 0.2),
                  ),
              ],
            ),
          const SizedBox(height: 14),
          if (widget.isContinuousSupport) ...[
            // === CONTINUOUS SUPPORT: tanpa slot, 7 hari + badge ===
            SoftCard(
              color: MalvaColors.mint.withValues(alpha: 0.10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.handshake_rounded, color: MalvaColors.mint),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '7 Days of Asynchronous Care',
                          style: TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 14),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Write anytime 24/7. Replies Mon-Fri. Terhubung selama 7 hari '
                    'berturut-turut sejak pembayaran berhasil.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.black54),
                  ),
                  const SizedBox(height: 6),
                  const Row(
                    children: [
                      Icon(Icons.insert_chart_rounded,
                          size: 16, color: MalvaColors.seed),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Profesional dapat memantau progresmu (sesuai izin).',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SoftCard(
              color: MalvaColors.plum,
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '7 hari continuous care',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    'Rp ${_formatRupiah(_price)} / week',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: const TextStyle(
                      color: MalvaColors.danger, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submitBooking,
              icon: const Icon(Icons.handshake_rounded),
              label: Text(_isSubmitting
                  ? 'Memproses...'
                  : 'Start Weekly Plan — Rp.199rb/week'),
            ),
            const SizedBox(height: 6),
            Text(
              'Renews Weekly. Cancel anytime.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.black54),
            ),
          ] else ...[
            SoftCard(
              color: MalvaColors.plum,
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      '30 menit',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    'Rp ${_formatRupiah(_price)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: const TextStyle(
                      color: MalvaColors.danger, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: (_selectedSlot == null || _isSubmitting)
                  ? null
                  : _submitBooking,
              icon: const Icon(Icons.arrow_forward_rounded),
              label:
                  Text(_isSubmitting ? 'Memproses...' : 'Proceed to Payment'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submitBooking() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      setState(() => _error = 'Mode offline aktif. '
          'Hubungkan ke server untuk membuat booking.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final booking = await apiClient.createBooking(
        accessToken: accessToken,
        professionalId: widget.doctorUserId,
        packageId: widget.package?.id,
        serviceType: widget.isContinuousSupport
            ? 'continuous_support'
            : (widget.serviceType == 'video'
                ? 'quick_consult_video'
                : 'quick_consult'),
        sessionType: widget.serviceType,
        bookingDate: _dateStr,
        slotTime: _selectedSlot!,
        durationMinutes: widget.isContinuousSupport ? 7 * 24 * 60 : 30,
        price: _price,
      );
      if (!mounted) return;
      // Continuous Support: minta izin monitoring data dulu (7 hari).
      if (widget.isContinuousSupport) {
        final granted = await showConsentRequestSheet(context: context);
        if (!granted || !mounted) return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentScreen(
            booking: booking,
            session: widget.session,
            apiClient: widget.apiClient,
          ),
        ),
      );
    } on MalvaApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  static String _prettyDate(DateTime d) {
    const days = [
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu',
      'Minggu'
    ];
    const months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember'
    ];
    return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
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
