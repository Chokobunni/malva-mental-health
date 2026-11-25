import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../providers/providers.dart';
import '../../services/malva_api_client.dart';
import '../../time/wib.dart';
import '../../web/web_format.dart';
import '../care_package_screen.dart';
import 'booking_owner.dart';

const _navy = Color(0xff111829);
const _muted = Color(0xff596a7d);
const _blue = Color(0xff4d46b4);
const _teal = Color(0xff087864);
const _mint = Color(0xffe9faf4);
const _paper = Color(0xfff6f8fa);

class PaymentSuccessScreen extends ConsumerStatefulWidget {
  const PaymentSuccessScreen({
    super.key,
    required this.reference,
    this.package,
    this.doctorUserId = '',
    this.doctorName = 'Profesional',
    this.session,
    this.apiClient,
    this.payment,
    this.booking,
    this.sessionScheduled = true,
  });

  final String reference;
  final BackendCarePackage? package;
  final String doctorUserId;
  final String doctorName;
  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final BackendPayment? payment;
  final BackendBooking? booking;
  final bool sessionScheduled;

  bool get isPackage => package != null;

  @override
  ConsumerState<PaymentSuccessScreen> createState() =>
      _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends ConsumerState<PaymentSuccessScreen> {
  late final BookingOwner _owner;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _owner = BookingOwner(ref, widget.session);
  }

  bool get _video => widget.booking?.sessionType == 'video';
  IconData get _sessionIcon =>
      _video ? Icons.videocam_outlined : Icons.chat_bubble_outline_rounded;
  String get _sessionType {
    if (widget.isPackage) return 'Paket Konsultasi';
    if (widget.booking == null) return 'Sesi Konsultasi';
    return 'Sesi ${_video ? 'Video' : 'Chat'} (${widget.booking!.durationMinutes} Menit)';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _paper,
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -.57),
            radius: .84,
            colors: [Color(0xffd9f0f0), _paper],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(19, 48, 19, 20),
            children: [
              Center(
                child: Container(
                  width: 96,
                  height: 96,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: const Color(0xff1ab59b), width: 4),
                    boxShadow: const [
                      BoxShadow(color: Color(0x3514ac98), blurRadius: 25),
                    ],
                  ),
                  child: const DecoratedBox(
                    decoration:
                        BoxDecoration(color: _mint, shape: BoxShape.circle),
                    child: Icon(Icons.check_rounded, color: _teal, size: 43),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Center(
                child: _ReceiptPill('Pembayaran Berhasil', icon: Icons.circle),
              ),
              const SizedBox(height: 12),
              const Text('Payment Received!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _navy, fontSize: 27, fontWeight: FontWeight.w900)),
              const SizedBox(height: 7),
              const Text('Terima kasih, transaksi Anda telah terkonfirmasi.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, fontSize: 14)),
              const SizedBox(height: 26),
              _receiptCard(
                Row(children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('TRANSACTION REFERENCE',
                            style: TextStyle(
                                color: _muted,
                                fontSize: 10,
                                letterSpacing: .9)),
                        const SizedBox(height: 4),
                        Text('#${widget.reference}',
                            style: const TextStyle(color: _navy)),
                      ],
                    ),
                  ),
                  IconButton.filledTonal(
                    onPressed: () => _copy(context),
                    tooltip: 'Salin nomor referensi',
                    icon: const Icon(Icons.copy_rounded, size: 20),
                  ),
                ]),
              ),
              const SizedBox(height: 16),
              _receiptCard(
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                        color: const Color(0xffedf0fe),
                        borderRadius: BorderRadius.circular(13)),
                    child: const Icon(Icons.event_available_outlined,
                        color: _blue),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(spacing: 8, runSpacing: 5, children: [
                          Text(
                              widget.isPackage
                                  ? 'PAKET KONSULTASI'
                                  : 'JADWAL KONSULTASI',
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: _blue,
                                  fontWeight: FontWeight.w800)),
                          Text(
                              widget.isPackage
                                  ? 'Paket aktif'
                                  : widget.sessionScheduled
                                      ? 'Terjadwal'
                                      : 'Menunggu jadwal',
                              style: const TextStyle(
                                  color: _muted,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600)),
                        ]),
                        const SizedBox(height: 6),
                        Text(widget.doctorName,
                            style: const TextStyle(
                                color: _navy,
                                fontSize: 15,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        _ReceiptPill(_sessionType,
                            icon: widget.isPackage
                                ? Icons.inventory_2_outlined
                                : _sessionIcon),
                        if (widget.isPackage || widget.sessionScheduled) ...[
                          const SizedBox(height: 8),
                          Text(
                            widget.isPackage
                                ? 'Lihat jadwal dan kuota sesi di paket Anda.'
                                : _video
                                    ? 'Akses ruang video dari Detail Sesi.'
                                    : 'Fitur chat otomatis aktif saat sesi berlangsung.',
                            style: const TextStyle(color: _muted, fontSize: 12),
                          ),
                        ],
                      ],
                    ),
                  ),
                ]),
                accented: true,
              ),
              const SizedBox(height: 14),
              Center(
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: _blue),
                  onPressed: () => _showReceipt(context),
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('View Receipt'),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(19, 8, 19, 18),
        child: FilledButton(
          style: FilledButton.styleFrom(backgroundColor: _teal),
          onPressed: _leaving ? null : _onContinue,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Flexible(
                child: Text(widget.isPackage
                    ? 'Lihat Paket & Jadwalkan Sesi'
                    : 'Lihat Sesi Saya')),
            const SizedBox(width: 9),
            const Icon(Icons.arrow_forward_rounded, size: 19),
          ]),
        ),
      ),
    );
  }

  Widget _receiptCard(Widget child, {bool accented = false}) => Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          boxShadow: const [
            BoxShadow(
                color: Color(0x0f111829), blurRadius: 8, offset: Offset(0, 2))
          ],
        ),
        child: IntrinsicHeight(
          child: Row(children: [
            if (accented)
              const SizedBox(
                  width: 5,
                  child: DecoratedBox(
                      decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [_blue, Color(0xff1bbba5)]),
                  ))),
            Expanded(
                child:
                    Padding(padding: const EdgeInsets.all(13), child: child)),
          ]),
        ),
      );

  Future<void> _onContinue() async {
    if (_owner.session == null && widget.session != null) return;
    final api = widget.apiClient ?? ref.read(apiClientProvider);
    final navigator = Navigator.of(context, rootNavigator: true);
    if (!widget.isPackage) {
      ref.read(patientScheduleRequestProvider.notifier).state++;
      navigator.popUntil((route) => route.isFirst);
      return;
    }

    setState(() => _leaving = true);
    var activePackage = widget.package!;
    final token = _owner.session?.accessToken;
    if (api != null && token != null && token.isNotEmpty) {
      try {
        final packages = await api.listCarePackages(accessToken: token);
        activePackage = packages
                .where((p) =>
                    p.professionalId == widget.doctorUserId && p.isActive)
                .firstOrNull ??
            activePackage;
      } on Object {
        // The confirmed purchase is still available as a fallback.
      }
    }
    if (!mounted || widget.session != null && _owner.session == null) return;
    final session = _owner.session;
    ref.read(patientScheduleRequestProvider.notifier).state++;
    navigator.pushAndRemoveUntil(
      MaterialPageRoute<void>(
          builder: (_) => CarePackageScreen(
                package: activePackage,
                session: session,
                apiClient: api,
              )),
      (route) => route.isFirst,
    );
  }

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: widget.reference));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nomor referensi disalin')),
      );
    }
  }

  void _showReceipt(BuildContext context) {
    final at = widget.payment?.paidAt;
    final total = widget.payment?.totalAmount;
    final date = at == null
        ? '—'
        : '${wibDateKey(toWib(at))} ${formatWibBubbleTime(at)} WIB';
    final formattedTotal = total == null ? '—' : formatRupiah(total);
    showDialog<void>(
      context: context,
      barrierColor: const Color(0x99111829),
      builder: (ctx) => Dialog(
        clipBehavior: Clip.antiAlias,
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(23)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  color: _navy,
                  padding: const EdgeInsets.fromLTRB(20, 14, 15, 21),
                  child: Column(children: [
                    Row(children: [
                      const Icon(Icons.receipt_long_outlined,
                          color: Colors.white),
                      const SizedBox(width: 9),
                      const Expanded(
                          child: Text('E-Receipt',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w900))),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        tooltip: 'Tutup e-receipt',
                        color: Colors.white,
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ]),
                    const SizedBox(height: 9),
                    Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Expanded(
                              child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Status Pembayaran',
                                  style: TextStyle(
                                      color: Color(0xffafbbcb), fontSize: 11)),
                              SizedBox(height: 6),
                              _ReceiptPill('PAID', icon: Icons.circle),
                            ],
                          )),
                          Expanded(
                              child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              const Text('Waktu Transaksi',
                                  style: TextStyle(
                                      color: Color(0xffafbbcb), fontSize: 11)),
                              const SizedBox(height: 6),
                              Text(date,
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12)),
                            ],
                          )),
                        ]),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                              color: _paper,
                              borderRadius: BorderRadius.circular(13)),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  const Expanded(
                                      child: Text('REFERENCE ID',
                                          style: TextStyle(
                                              color: _muted,
                                              fontSize: 11,
                                              letterSpacing: .6))),
                                  TextButton.icon(
                                    onPressed: () => _copy(context),
                                    icon: const Icon(Icons.copy_rounded,
                                        size: 15),
                                    label: const Text('Salin'),
                                  ),
                                ]),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 9),
                                  child: Text('#${widget.reference}',
                                      style: const TextStyle(
                                          color: _navy,
                                          fontWeight: FontWeight.w800)),
                                ),
                              ]),
                        ),
                        const SizedBox(height: 9),
                        _receiptRow('Jenis Sesi', _sessionType),
                        _receiptRow('Profesional', widget.doctorName),
                        _receiptRow('Tanggal', date),
                        _receiptRow('Total Pembayaran', formattedTotal,
                            total: true),
                        Container(
                          margin: const EdgeInsets.only(top: 14, bottom: 18),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xfffff8e7),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(Icons.info_outline_rounded,
                                    size: 17, color: Color(0xffa26221)),
                                SizedBox(width: 8),
                                Expanded(
                                    child: Text(
                                        'Simpan nomor referensi ini untuk keperluan audit dan pengajuan refund.',
                                        style: TextStyle(
                                            color: Color(0xff80501f),
                                            fontSize: 12))),
                              ]),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: FilledButton.styleFrom(backgroundColor: _navy),
                          child: const Text('Tutup'),
                        ),
                      ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _receiptRow(String label, String value, {bool total = false}) =>
      Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: total
            ? null
            : const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xffeff1f3)))),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: total ? _navy : _muted,
                      fontWeight: total ? FontWeight.w800 : FontWeight.w400))),
          const SizedBox(width: 8),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.end,
                style: TextStyle(
                    color: total ? _teal : _navy,
                    fontSize: total ? 18 : 13,
                    fontWeight: FontWeight.w800)),
          ),
        ]),
      );
}

class _ReceiptPill extends StatelessWidget {
  const _ReceiptPill(this.label, {required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 5, horizontal: 9),
        decoration: BoxDecoration(
            color: _mint, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: _teal, size: icon == Icons.circle ? 7 : 13),
          const SizedBox(width: 5),
          Flexible(
              child: Text(label,
                  style: const TextStyle(
                      color: _teal,
                      fontSize: 11,
                      fontWeight: FontWeight.w800))),
        ]),
      );
}
