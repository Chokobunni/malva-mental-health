import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/providers.dart';
import '../../../services/malva_api_client.dart';
import '../../../theme.dart';
import '../../../widgets/friendly_error.dart';
import '../../services/web_care_service.dart';
import '../../web_format.dart';

/// Dialog booking 4 langkah: layanan → jadwal → ringkasan → pembayaran.
///
/// Langkah pembayaran mengikuti perilaku mobile: `createBooking` (atau
/// `createCarePackage` + `createPackageSessionBooking` untuk paket) lalu
/// `createPayment`, buka `redirectUrl` di tab baru, dan pantau status lewat
/// `getPaymentStatus` tiap 5 detik sampai `paid`/`failed` (batas 5 menit).
class WebBookingDialog extends ConsumerStatefulWidget {
  const WebBookingDialog({
    super.key,
    required this.doctor,
    required this.pricing,
    required this.onGoToSchedule,
  });

  final BackendDoctorSearchResult doctor;
  final BackendProfessionalPricing pricing;

  /// Dipanggil saat pengguna memilih "Lihat jadwal" setelah pembayaran lunas.
  final VoidCallback onGoToSchedule;

  @override
  ConsumerState<WebBookingDialog> createState() => _WebBookingDialogState();
}

class _WebBookingDialogState extends ConsumerState<WebBookingDialog> {
  static const int _maxPollTicks = 60; // 60 × 5 dtk = 5 menit

  late final List<WebServiceOption> _options =
      webServiceOptions(widget.pricing);
  late WebServiceOption _service = _options.first;
  late final List<String> _days = webNextSevenDayKeys();
  late String _date = _days.first;

  String? _slot;
  List<BackendDoctorSlot> _slots = const <BackendDoctorSlot>[];
  bool _slotsLoading = false;
  Object? _slotsError;

  bool _agreed = false;
  int _step = 0;

  bool _busy = false;
  String? _error;
  BackendPayment? _payment;
  String _paymentStatus = '';
  Timer? _pollTimer;
  int _pollTicks = 0;
  bool _checking = false;
  bool _paid = false;
  bool _failed = false;

  String get _token => ref.read(authStateProvider).session?.accessToken ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadSlots());
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadSlots() async {
    setState(() {
      _slotsLoading = true;
      _slotsError = null;
      _slot = null;
    });
    try {
      final slots = await ref.read(apiClientProvider).getDoctorAvailableSlots(
            accessToken: _token.isEmpty ? null : _token,
            userId: widget.doctor.userId,
            date: _date,
          );
      if (!mounted) return;
      setState(() {
        _slots = slots.where((BackendDoctorSlot s) => s.available).toList();
        _slotsLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _slotsError = error;
        _slotsLoading = false;
      });
    }
  }

  void _selectDate(String date) {
    if (date == _date) return;
    setState(() => _date = date);
    unawaited(_loadSlots());
  }

  bool get _canGoNext {
    switch (_step) {
      case 0:
        return true;
      case 1:
        return _slot != null;
      case 2:
        return _agreed;
      default:
        return false;
    }
  }

  void _next() {
    if (!_canGoNext) return;
    setState(() {
      _error = null;
      _step = (_step + 1).clamp(0, 3);
    });
  }

  void _back() {
    if (_step == 0) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _step -= 1);
  }

  Future<void> _pay() async {
    if (_busy || _paid) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final BackendBooking booking;
      if (_service.isPackage) {
        // Paket: buat paket pending lalu booking sesi pertama (perilaku mobile).
        final carePackage = await api.createCarePackage(
          accessToken: _token,
          professionalId: widget.doctor.userId,
        );
        booking = await api.createPackageSessionBooking(
          accessToken: _token,
          packageId: carePackage.id,
          bookingDate: _date,
          slotTime: _slot ?? '',
          sessionType: _service.sessionType,
        );
      } else {
        booking = await api.createBooking(
          accessToken: _token,
          professionalId: widget.doctor.userId,
          serviceType: _service.serviceType,
          sessionType: _service.sessionType,
          bookingDate: _date,
          slotTime: _slot,
          durationMinutes: _service.durationMinutes,
          price: _service.price,
        );
      }
      final response = await api.createPayment(
        accessToken: _token,
        bookingId: booking.id,
      );
      if (!mounted) return;
      setState(() {
        _busy = false;
        _payment = response.payment;
        _paymentStatus = response.payment.status;
      });
      if (response.payment.redirectUrl.isNotEmpty) {
        // Tautan TIDAK ditampilkan mentah (memuat token gateway).
        final opened = await openWebExternalUrl(response.payment.redirectUrl);
        if (!mounted) return;
        if (!opened) {
          setState(() => _error =
              'Halaman pembayaran tidak bisa dibuka otomatis. Izinkan pop-up '
                  'lalu tekan "Buka halaman pembayaran".');
        }
      }
      _startPolling();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = webBookingErrorMessage(error);
      });
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTicks = 0;
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (Timer timer) {
      _pollTicks++;
      if (_pollTicks > _maxPollTicks) {
        timer.cancel();
        if (mounted) {
          setState(() =>
              _error = 'Status pembayaran belum terkonfirmasi setelah 5 menit. '
                  'Cek menu Jadwal beberapa saat lagi — pembayaran yang sudah '
                  'dibayar akan otomatis aktif.');
        }
        return;
      }
      unawaited(_checkStatus());
    });
    unawaited(_checkStatus());
  }

  Future<void> _checkStatus() async {
    final payment = _payment;
    if (payment == null || _checking || _paid || _failed) return;
    _checking = true;
    try {
      final status = await ref.read(apiClientProvider).getPaymentStatus(
            accessToken: _token,
            reference: payment.reference,
          );
      if (!mounted) return;
      final value = status.payment.status.toLowerCase();
      setState(() => _paymentStatus = status.payment.status);
      if (value == 'paid' || value == 'settlement') {
        _pollTimer?.cancel();
        setState(() => _paid = true);
      } else if (value == 'failed' || value == 'expired' || value == 'deny') {
        _pollTimer?.cancel();
        setState(() {
          _failed = true;
          _error = 'Pembayaran gagal atau kedaluwarsa. Silakan ulangi booking.';
        });
      }
    } catch (_) {
      // Jaringan bermasalah: biarkan polling berikutnya mencoba lagi.
    } finally {
      _checking = false;
    }
  }

  Future<void> _reopenPayment() async {
    final payment = _payment;
    if (payment == null) return;
    await openWebExternalUrl(payment.redirectUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 880, maxHeight: 780),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Booking · ${widget.doctor.displayName}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _StepIndicator(step: _step),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 470),
                child: SingleChildScrollView(child: _buildStep()),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 12),
                Container(
                  key: const Key('web-booking-error'),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: MalvaColors.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: MalvaColors.danger.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: MalvaColors.danger,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              _buildFooter(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case 0:
        return _buildServiceStep();
      case 1:
        return _buildScheduleStep();
      case 2:
        return _buildSummaryStep();
      default:
        return _buildPaymentStep();
    }
  }

  Widget _buildServiceStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'Pilih layanan',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        for (final option in _options) ...<Widget>[
          InkWell(
            key: Key('web-booking-service-${option.id}'),
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => _service = option),
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _service.id == option.id
                    ? MalvaColors.seed.withValues(alpha: 0.06)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _service.id == option.id
                      ? MalvaColors.seed
                      : const Color(0xFFEADFF2),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(
                    _service.id == option.id
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 18,
                    color: _service.id == option.id
                        ? MalvaColors.seed
                        : const Color(0xFF9C93A6),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          option.label,
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${option.description} · ${option.durationMinutes} menit',
                          style: const TextStyle(
                            fontSize: 11.5,
                            height: 1.45,
                            color: Color(0xFF6B6377),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    formatRupiah(option.price),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (_service.isPackage)
          const Text(
            'Paket memerlukan pemilihan jadwal sesi pertama. Sesi berikutnya '
            'dijadwalkan bersama profesional.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF8B8194)),
          ),
      ],
    );
  }

  Widget _buildScheduleStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const Text(
          'Pilih jadwal',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _days.map((String day) {
            final selected = day == _date;
            return InkWell(
              key: Key('web-booking-date-$day'),
              borderRadius: BorderRadius.circular(10),
              onTap: () => _selectDate(day),
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
        const SizedBox(height: 14),
        if (_slotsLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 18),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text(
                  'Memuat slot...',
                  style: TextStyle(fontSize: 12, color: Color(0xFF6B6377)),
                ),
              ],
            ),
          )
        else if (_slotsError != null)
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  friendlyErrorMessage(_slotsError!),
                  style: const TextStyle(
                    fontSize: 12,
                    color: MalvaColors.danger,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => unawaited(_loadSlots()),
                child: const Text('Coba lagi'),
              ),
            ],
          )
        else if (_slots.isEmpty)
          const Text(
            'Tidak ada slot tersedia pada tanggal ini. Pilih tanggal lain.',
            style: TextStyle(fontSize: 12, color: Color(0xFF8B8194)),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _slots.map((BackendDoctorSlot slot) {
              final selected = _slot == slot.time;
              return InkWell(
                key: Key('web-booking-slot-${slot.time}'),
                borderRadius: BorderRadius.circular(9),
                onTap: () => setState(() => _slot = slot.time),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color:
                        selected ? MalvaColors.seed : const Color(0xFFF7F3FA),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color:
                          selected ? MalvaColors.seed : const Color(0xFFEADFF2),
                    ),
                  ),
                  child: Text(
                    slot.time.length >= 5
                        ? slot.time.substring(0, 5)
                        : slot.time,
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
        if (_slot == null) ...<Widget>[
          const SizedBox(height: 10),
          const Text(
            'Pilih satu slot untuk melanjutkan.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF8B8194)),
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'Ringkasan & persetujuan',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        _SummaryRow(label: 'Profesional', value: widget.doctor.displayName),
        _SummaryRow(label: 'Layanan', value: _service.label),
        _SummaryRow(
          label: 'Jadwal',
          value: '${webShortDateLabel(_date)} · ${_slot ?? '—'} WIB',
        ),
        _SummaryRow(
            label: 'Durasi', value: '${_service.durationMinutes} menit'),
        const Divider(height: 22),
        _SummaryRow(
          label: 'Total',
          value: formatRupiah(_service.price),
          emphasize: true,
        ),
        const SizedBox(height: 14),
        CheckboxListTile(
          key: const Key('web-booking-agree'),
          value: _agreed,
          onChanged: (bool? value) => setState(() => _agreed = value ?? false),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          title: const Text(
            'Saya memahami data saya dibagikan sesuai persetujuan privasi',
            style: TextStyle(fontSize: 12.5, height: 1.45),
          ),
          subtitle: const Text(
            'Profesional akan melihat ringkasan kondisi yang Anda bagikan.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF8B8194)),
          ),
        ),
      ],
    );
  }

  Widget _buildPaymentStep() {
    final payment = _payment;
    if (_paid) {
      return Column(
        key: const Key('web-booking-success'),
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const SizedBox(height: 10),
          const Icon(Icons.check_circle_rounded,
              size: 44, color: MalvaColors.mint),
          const SizedBox(height: 10),
          const Text(
            'Pembayaran diterima',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Sesi Anda pada ${webShortDateLabel(_date)} pukul ${_slot ?? '—'} '
            'WIB sudah terjadwal. Detail ada di menu Jadwal.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: Color(0xFF6B6377),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton(
              key: const Key('web-booking-go-schedule'),
              onPressed: () {
                Navigator.of(context).pop();
                widget.onGoToSchedule();
              },
              child: const Text('Lihat jadwal'),
            ),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const Text(
          'Pembayaran',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Text(
          payment == null
              ? 'Tekan "Bayar sekarang" untuk membuat tagihan. Anda akan '
                  'diarahkan ke halaman pembayaran di tab baru.'
              : 'Selesaikan pembayaran di tab yang sudah dibuka. Halaman ini '
                  'memantau status otomatis setiap 5 detik.',
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.5,
            color: Color(0xFF6B6377),
          ),
        ),
        if (payment != null) ...<Widget>[
          const SizedBox(height: 14),
          _SummaryRow(label: 'Referensi', value: payment.reference),
          _SummaryRow(
            label: 'Status',
            value: paymentStatusLabel(_paymentStatus),
          ),
          _SummaryRow(label: 'Total', value: formatRupiah(_service.price)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              OutlinedButton.icon(
                key: const Key('web-booking-reopen'),
                onPressed: () => unawaited(_reopenPayment()),
                icon: const Icon(Icons.open_in_new_rounded, size: 17),
                label: const Text('Buka halaman pembayaran'),
              ),
              FilledButton.icon(
                key: const Key('web-booking-check'),
                onPressed: () => unawaited(_checkStatus()),
                icon: const Icon(Icons.refresh_rounded, size: 17),
                label: const Text('Saya sudah bayar'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Jangan tutup halaman ini sampai status berubah menjadi Lunas.',
            style: TextStyle(fontSize: 11.5, color: Color(0xFF8B8194)),
          ),
        ],
      ],
    );
  }

  Widget _buildFooter() {
    if (_step == 3) {
      if (_payment == null) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              key: const Key('web-booking-back'),
              onPressed: _busy ? null : _back,
              child: const Text('Kembali'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const Key('web-booking-pay'),
              onPressed: _busy ? null : () => unawaited(_pay()),
              child: Text(_busy ? 'Memproses...' : 'Bayar sekarang'),
            ),
          ],
        );
      }
      return Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tutup'),
        ),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: <Widget>[
        TextButton(
          key: const Key('web-booking-back'),
          onPressed: _back,
          child: Text(_step == 0 ? 'Batal' : 'Kembali'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          key: const Key('web-booking-next'),
          onPressed: _canGoNext ? _next : null,
          child: Text(_step == 2 ? 'Lanjut ke pembayaran' : 'Lanjut'),
        ),
      ],
    );
  }
}

class _StepIndicator extends StatelessWidget {
  const _StepIndicator({required this.step});

  final int step;

  static const List<String> _labels = <String>[
    'Layanan',
    'Jadwal',
    'Ringkasan',
    'Pembayaran',
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        for (var i = 0; i < _labels.length; i++) ...<Widget>[
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: i <= step ? MalvaColors.seed : const Color(0xFFF0E9F6),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${i + 1}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: i <= step ? Colors.white : const Color(0xFF8B8194),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            _labels[i],
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: i == step ? FontWeight.w800 : FontWeight.w500,
              color: i <= step ? MalvaColors.ink : const Color(0xFF8B8194),
            ),
          ),
          if (i != _labels.length - 1) ...<Widget>[
            const SizedBox(width: 8),
            const Expanded(
              child: Divider(height: 1, color: Color(0xFFEADFF2)),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF8B8194)),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: emphasize ? 14 : 12.5,
                fontWeight: emphasize ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
