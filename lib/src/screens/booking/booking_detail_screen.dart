import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../providers/providers.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';
import '../../widgets/professional_avatar.dart';
import 'payment_screen.dart';
import 'booking_owner.dart';
import 'consent_request_sheet.dart';
import '../../time/wib.dart';

// ============================================================
// BOOKING DETAIL — Quick Consult satu kali:
// tanggal (dari hari available profesional) + slot jam riil server.
// Tanpa slot demo, tanpa harga dummy (harga dari tarif profesional,
// dihitung ulang oleh server).
// ============================================================

class BookingDetailScreen extends ConsumerStatefulWidget {
  const BookingDetailScreen({
    super.key,
    required this.doctorUserId,
    required this.doctorName,
    required this.serviceType,
    required this.expectedPrice,
    required this.doctorPhotoUrl,
    this.chatPrice,
    this.videoPrice,
    this.durationLabel,
    this.chatDurationLabel,
    this.videoDurationLabel,
    this.session,
    this.apiClient,
  });

  final String doctorUserId;
  final String doctorName;
  final String serviceType;

  /// URL foto profil profesional. Kosong = pakai avatar gradien + inisial.
  final String doctorPhotoUrl;

  /// Harga yang tampil di profil (server menghitung ulang & memvalidasi).
  final int expectedPrice;
  final int? chatPrice;
  final int? videoPrice;
  final String? durationLabel;
  final String? chatDurationLabel;
  final String? videoDurationLabel;
  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<BookingDetailScreen> createState() =>
      _BookingDetailScreenState();
}

class _BookingDetailScreenState extends ConsumerState<BookingDetailScreen> {
  late final BookingOwner _owner;
  late String _method;
  int _slotsRequest = 0;
  String get _category => _method == 'chat' ? 'quick_chat' : 'quick_video';

  int _priceFor(String method) =>
      (method == 'chat' ? widget.chatPrice : widget.videoPrice) ??
      (widget.serviceType == method ? widget.expectedPrice : 0);

  List<BackendAvailabilityDay> _days = const [];
  String? _selectedDate;
  String? _selectedSlot;
  List<BackendDoctorSlot> _slots = const [];
  bool _isLoadingDays = true;
  bool _isLoadingSlots = false;
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _owner = BookingOwner(ref, widget.session);
    _method = widget.serviceType;
    _loadDays();
  }

  Future<void> _loadDays() async {
    final MalvaApiClient apiClient =
        widget.apiClient ?? ref.read(apiClientProvider);
    final rawToken = _owner.session?.accessToken;
    final accessToken =
        (rawToken == null || rawToken.isEmpty) ? null : rawToken;
    final request = ++_slotsRequest;
    setState(() {
      _isLoadingDays = true;
      _isLoadingSlots = false;
      _selectedDate = null;
      _selectedSlot = null;
      _slots = const [];
      _error = null;
    });
    try {
      final days = await apiClient.getDoctorAvailability(
        accessToken: accessToken,
        userId: widget.doctorUserId,
        serviceCategory: _category,
      );
      if (!mounted || request != _slotsRequest) return;
      final bookable = days.where((d) => d.bookable).toList(growable: false);
      setState(() {
        _days = bookable;
        _isLoadingDays = false;
        _selectedDate = bookable.isEmpty ? null : bookable.first.date;
      });
      if (_selectedDate != null) _loadSlots();
    } on Object catch (e) {
      if (!mounted || request != _slotsRequest) return;
      setState(() {
        _isLoadingDays = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  void _selectDate(String date) {
    setState(() {
      _selectedDate = date;
      _selectedSlot = null;
      _slots = const [];
    });
    _loadSlots();
  }

  Future<void> _loadSlots() async {
    final date = _selectedDate;
    if (date == null) return;
    final request = ++_slotsRequest;
    setState(() {
      _isLoadingSlots = true;
      _selectedSlot = null;
      _error = null;
    });
    try {
      final MalvaApiClient apiClient =
          widget.apiClient ?? ref.read(apiClientProvider);
      final rawToken = _owner.session?.accessToken;
      final accessToken =
          (rawToken == null || rawToken.isEmpty) ? null : rawToken;
      final slots = await apiClient.getDoctorAvailableSlots(
        accessToken: accessToken,
        userId: widget.doctorUserId,
        date: date,
        serviceCategory: _category,
      );
      if (!mounted || request != _slotsRequest) return;
      setState(() {
        _slots = slots;
        _isLoadingSlots = false;
      });
    } on Object catch (e) {
      if (!mounted || request != _slotsRequest) return;
      setState(() {
        _slots = const [];
        _isLoadingSlots = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isVideo = _method == 'video';
    final durationLabel =
        (isVideo ? widget.videoDurationLabel : widget.chatDurationLabel) ??
            widget.durationLabel;
    return Scaffold(
      backgroundColor: const Color(0xFFF9F3FD),
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Booking Detail'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SoftCard(
            color: Colors.white,
            child: Row(
              children: [
                ProfessionalAvatar(
                  displayName: widget.doctorName,
                  radius: 28,
                  photoUrl: widget.doctorPhotoUrl,
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
                      const StatusPill(
                        label: 'Quick Consult • 1 sesi',
                        color: MalvaColors.seed,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const SectionLabel('Pilih metode'),
          Row(
            children: [
              for (final (method, label, icon) in const [
                ('chat', 'Chat', Icons.chat_bubble_outline_rounded),
                ('video', 'Video', Icons.videocam_outlined),
              ]) ...[
                if (method == 'video') const SizedBox(width: 8),
                Expanded(
                  child: ChoiceChip(
                    showCheckmark: false,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 7),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    label: Row(
                      children: [
                        Icon(icon, color: MalvaColors.seed),
                        const SizedBox(width: 8),
                        Expanded(child: Text(label)),
                        if (_method == method)
                          const Icon(Icons.check_circle,
                              color: MalvaColors.seed, size: 19),
                      ],
                    ),
                    selected: _method == method,
                    selectedColor: const Color(0xFFF0DFF9),
                    backgroundColor: Colors.white,
                    side: BorderSide(
                        color: _method == method
                            ? MalvaColors.seed
                            : const Color(0xFFCCC3D0)),
                    labelStyle: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15),
                    onSelected: _priceFor(method) <= 0 || _isSubmitting
                        ? null
                        : (_) {
                            if (_method == method) return;
                            setState(() => _method = method);
                            _loadDays();
                          },
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 18),
          const SectionLabel('Pilih tanggal'),
          const Text('Jadwal profesional • WIB'),
          const SizedBox(height: 8),
          if (_isLoadingDays)
            const Center(child: CircularProgressIndicator())
          else if (_days.isEmpty || _selectedDate == null)
            const EmptyState(
              icon: Icons.event_busy_rounded,
              title: 'Belum ada jadwal tersedia',
              subtitle:
                  'Profesional belum mengatur hari praktik / semua penuh 14 hari ke depan.',
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final day in _days)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _DayChip(
                        date: day.date,
                        bookable: day.bookable,
                        freeSlots: day.freeSlots,
                        selected: _selectedDate == day.date,
                        onTap: day.bookable && !_isSubmitting
                            ? () => _selectDate(day.date)
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 14),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: SectionLabel('Pilih jam')),
              StatusPill(label: 'WIB', color: MalvaColors.seed),
            ],
          ),
          if (_selectedDate != null) Text(_prettyDate(_selectedDate!)),
          const SizedBox(height: 8),
          if (_isLoadingSlots)
            const Center(child: CircularProgressIndicator())
          else if (_selectedDate == null)
            const EmptyState(
              icon: Icons.schedule_rounded,
              title: 'Pilih tanggal dulu',
              subtitle: 'Jam tersedia muncul setelah tanggal dipilih.',
            )
          else if (_slots.where((s) => s.available).isEmpty)
            const EmptyState(
              icon: Icons.event_busy_rounded,
              title: 'Tidak ada slot bebas',
              subtitle:
                  'Semua slot tanggal ini sudah terisi. Coba tanggal lain.',
            )
          else
            LayoutBuilder(builder: (context, constraints) {
              final count = _slots.length <= 3 ? 3 : 4;
              final width = (constraints.maxWidth - 8 * (count - 1)) / count;
              return Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final slot in _slots)
                    SizedBox(
                      width: width,
                      child: ChoiceChip(
                        showCheckmark: false,
                        backgroundColor: Colors.white,
                        label: Center(
                            child: Text(slot.time,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800))),
                        selected: _selectedSlot == slot.time,
                        onSelected: slot.available && !_isSubmitting
                            ? (_) => setState(() => _selectedSlot = slot.time)
                            : null,
                        selectedColor: MalvaColors.seed.withValues(alpha: 0.2),
                      ),
                    ),
                ],
              );
            }),
          const SizedBox(height: 14),
          SoftCard(
            color: MalvaColors.plum,
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    isVideo ? 'Sesi Video' : 'Sesi Chat',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  'Rp ${_formatRupiah(_priceFor(_method))}',
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
            onPressed: (_selectedSlot == null ||
                    _isSubmitting ||
                    _priceFor(_method) <= 0)
                ? null
                : _submitBooking,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(_isSubmitting ? 'Memproses...' : 'Proceed to Payment'),
          ),
          const SizedBox(height: 6),
          Text(
            durationLabel == null
                ? 'Durasi mengikuti slot praktik'
                : 'Durasi sesi $durationLabel',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Future<void> _submitBooking() async {
    // Fallback ke provider bila apiClient tidak dioper eksplisit (mis.
    // deep-link), konsisten dengan _loadDays/_loadSlots, agar booking tetap
    // bisa dikirim ke server.
    final MalvaApiClient apiClient =
        widget.apiClient ?? ref.read(apiClientProvider);
    final accessToken = _owner.session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      setState(() => _error = 'Mode offline aktif. '
          'Hubungkan ke server untuk membuat booking.');
      return;
    }
    final date = _selectedDate;
    final slot = _selectedSlot;
    if (_isSubmitting || date == null || slot == null) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final granted = await showConsentRequestSheet(
        context: context,
        professionalId: widget.doctorUserId,
        oneTime: true,
        ownerSession: () => mounted ? _owner.session : null,
      );
      if (!granted || !mounted) return;
      final checkoutSession = _owner.session;
      final checkoutToken = checkoutSession?.accessToken;
      if (checkoutToken == null || checkoutToken.isEmpty) return;
      final booking = await apiClient.createBooking(
        accessToken: checkoutToken,
        professionalId: widget.doctorUserId,
        serviceType:
            _method == 'video' ? 'quick_consult_video' : 'quick_consult',
        sessionType: _method,
        bookingDate: date,
        slotTime: slot,
        durationMinutes: 60,
        price: _priceFor(_method),
      );
      if (!mounted || _owner.session == null) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentScreen(
            booking: booking,
            doctorName: widget.doctorName,
            session: _owner.session,
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

  static String _prettyDate(String yyyyMmDd) {
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
    final d = DateTime.tryParse(yyyyMmDd);
    if (d == null) return yyyyMmDd;
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

/// Chip satu hari dari availability server (hanya yang bisa di-booking).
class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.date,
    required this.bookable,
    required this.freeSlots,
    required this.selected,
    required this.onTap,
  });

  final String date;
  final bool bookable;
  final int freeSlots;
  final bool selected;
  final VoidCallback? onTap;

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
    final day = DateTime.tryParse(date) ?? wibNow();
    final now = wibNow();
    final isToday =
        day.year == now.year && day.month == now.month && day.day == now.day;
    return InkWell(
      onTap: bookable ? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: Opacity(
        opacity: bookable ? 1 : 0.45,
        child: Container(
          width: 76,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? MalvaColors.seed : Colors.white,
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
                day.day.toString().padLeft(2, '0'),
                style: TextStyle(
                  fontSize: 23,
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
              Text(
                bookable ? '$freeSlots slot' : 'Penuh',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: selected ? Colors.white70 : Colors.black45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
