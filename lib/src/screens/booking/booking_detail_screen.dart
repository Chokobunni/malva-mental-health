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
  DateTime _date = DateTime.now();
  String? _selectedSlot;
  List<BackendDoctorSlot> _slots = const [];
  bool _isLoadingSlots = false;
  bool _isSubmitting = false;
  String? _error;

  String get _dateStr =>
      '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  /// Continuous care: tanggal mulai + 6 hari = periode 7 hari.
  DateTime get _endDate => _date.add(const Duration(days: 6));

  /// 7 hari pilihan (hari ini s/d +6). Hari lampau tidak pernah muncul.
  List<DateTime> get _next7Days {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return [for (var i = 0; i < 7; i++) today.add(Duration(days: i))];
  }

  /// Tanggal unik yang tersedia pada range 7 hari (untuk continuous).
  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Kalender asli: pilih tanggal mulai dalam range 7 hari ke depan.
  Future<void> _pickStartDate() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: _date.isBefore(today) ? today : _date,
      firstDate: today,
      lastDate: today.add(const Duration(days: 6)),
      helpText: 'Pilih tanggal mulai (7 hari ke depan)',
      cancelText: 'Batal',
      confirmText: 'Pilih',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _date = DateTime(picked.year, picked.month, picked.day);
      _selectedSlot = null;
    });
    _loadSlots();
  }

  @override
  void initState() {
    super.initState();
    _loadSlots();
  }

  /// Set pilihan tanggal dari chip 7 hari.
  void _selectDay(DateTime day) {
    setState(() {
      _date = DateTime(day.year, day.month, day.day);
      _selectedSlot = null;
    });
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    // Continuous Support: tanpa slot spesifik (7 hari penuh).
    if (widget.isContinuousSupport) {
      if (mounted) setState(() => _slots = const []);
      return;
    }
    setState(() {
      _isLoadingSlots = true;
      _selectedSlot = null;
    });
    List<BackendDoctorSlot> slots = const [];
    final apiClient = widget.apiClient;
    final rawToken = widget.session?.accessToken;
    final accessToken =
        (rawToken == null || rawToken.isEmpty) ? null : rawToken;
    if (apiClient != null) {
      try {
        final remote = await apiClient.getDoctorAvailableSlots(
          accessToken: accessToken,
          userId: widget.doctorUserId,
          date: _dateStr,
        );
        slots = remote.where((s) => s.available).toList(growable: false);
      } on Object {
        // Fallback ke slot demo di bawah.
      }
    }
    // Jaminan UX: pasien SELALU disediakan pilihan jam. Bila server kosong
    // (offline / jadwal belum diatur), pakai jadwal demo 09:00-16:00.
    if (slots.isEmpty) {
      slots = _demoSlots();
    }
    if (!mounted) return;
    setState(() {
      _slots = slots;
      _isLoadingSlots = false;
    });
  }

  /// Slot demo deterministik 09:00-16:00 per 30 menit; pola ketersediaan
  /// stabil per tanggal agar tidak berubah saat refresh.
  List<BackendDoctorSlot> _demoSlots() {
    final seed = _dateStr.hashCode.abs();
    final out = <BackendDoctorSlot>[];
    for (var h = 9; h < 16; h++) {
      for (final m in const [0, 30]) {
        final label =
            '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
        final available = (h * 2 + (m ~/ 30) + seed) % 4 != 0;
        out.add(BackendDoctorSlot(time: label, available: available));
      }
    }
    return out;
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
          // === RINGKASAN JADWAL: kapan sesi/perawatan dimulai ===
          SoftCard(
            color: MalvaColors.seed.withValues(alpha: 0.06),
            child: Row(
              children: [
                const Icon(Icons.event_available_rounded,
                    color: MalvaColors.seed),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.isContinuousSupport
                            ? 'Continuous Support dimulai'
                            : 'Sesi dimulai',
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 13.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.isContinuousSupport
                            ? '${_prettyDate(_date)} — berakhir ${_prettyDate(_endDate)} (7 hari)'
                            : '${_prettyDate(_date)}'
                                '${_selectedSlot == null ? ' • pilih jam di bawah' : ' • pukul $_selectedSlot'}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: Colors.black87),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (widget.isContinuousSupport) ...[
            const SectionLabel('Tanggal Mulai'),
            SoftCard(
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: MalvaColors.mint.withValues(alpha: 0.15),
                    child: const Icon(Icons.calendar_month_rounded,
                        color: MalvaColors.mint),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Mulai: ${_prettyDate(_date)}',
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 15),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Berakhir: ${_prettyDate(_endDate)} • 7 hari perawatan',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _pickStartDate,
                    icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                    label: const Text('Pilih'),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SectionLabel('Pilih Tanggal (7 hari ke depan)'),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final day in _next7Days)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _DayChip(
                        day: day,
                        selected: _isSameDay(day, _date),
                        onTap: () => _selectDay(day),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SoftCard(
              child: Row(
                children: [
                  const Icon(Icons.event_rounded,
                      color: MalvaColors.seed, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _prettyDate(_date),
                      style: const TextStyle(
                          fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _pickStartDate,
                    icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                    label: const Text('Kalender'),
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
          ],
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
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(_error!,
                  style: const TextStyle(
                      color: MalvaColors.danger, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 14),
            // SATU tombol: continuous support -> consent -> payment.
            FilledButton.icon(
              onPressed: _isSubmitting ? null : _submitBooking,
              icon: const Icon(Icons.handshake_rounded),
              label: Text(_isSubmitting
                  ? 'Memproses...'
                  : 'Mulai Continuous Support — Rp ${_formatRupiah(_price)}'),
            ),
            const SizedBox(height: 6),
            Text(
              'Chat 24/7 selama 7 hari (${_prettyDate(_date)} – ${_prettyDate(_endDate)}). Batalkan kapan saja.',
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
    // Continuous Support: consent checklist DULU (sesuai Figma flow:
    // pilih paket -> isi consent -> bayar -> connected). Batal = tidak ada
    // booking yatim di server.
    if (widget.isContinuousSupport) {
      final granted = await showConsentRequestSheet(
        context: context,
        professionalId: widget.doctorUserId,
      );
      if (!granted || !mounted) return;
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
        // Continuous: tanpa slot (server simpan NULL). Quick: slot wajib.
        slotTime: widget.isContinuousSupport ? null : _selectedSlot,
        durationMinutes: widget.isContinuousSupport ? 7 * 24 * 60 : 30,
        price: _price,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentScreen(
            booking: booking,
            doctorName: widget.doctorName,
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

/// Chip satu hari pada pemilih 7 hari (hanya hari ini s/d +6).
class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.selected,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final VoidCallback onTap;

  static const _dayNames = [
    'Sen',
    'Sel',
    'Rab',
    'Kam',
    'Jum',
    'Sab',
    'Min',
  ];

  static const _monthNames = [
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
    'Des',
  ];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        width: 66,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? MalvaColors.seed
              : MalvaColors.seed.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? MalvaColors.seed
                : MalvaColors.seed.withValues(alpha: 0.18),
          ),
        ),
        child: Column(
          children: [
            Text(
              isToday ? 'Hari ini' : _dayNames[day.weekday - 1],
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : Colors.black54,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${day.day}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: selected ? Colors.white : MalvaColors.plum,
              ),
            ),
            Text(
              _monthNames[day.month - 1],
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                color: selected ? Colors.white70 : Colors.black45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
