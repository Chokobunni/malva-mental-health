import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../providers/providers.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';
import '../care_package_screen.dart';
import 'payment_success_screen.dart';

// ============================================================
// PAYMENT — break-down + metode.
// Mode internal/simulasi: pembayaran dikonfirmasi langsung dan
// tercatat di DB (belum memakai gateway eksternal).
// ============================================================

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({
    super.key,
    this.booking,
    this.package,
    this.doctorName = 'Profesional',
    this.session,
    this.apiClient,
  }) : assert(booking != null || package != null,
            'booking atau package wajib diisi');

  /// Quick consult (sesi satu kali).
  final BackendBooking? booking;

  /// Pembelian paket continuous (4 sesi). Payment paket masih lewat
  /// booking pending milik paket — dibuat server saat createCarePackage?
  /// Tidak: paket dibayar lewat booking tersendiri di bawah ini.
  final BackendCarePackage? package;
  final String doctorName;
  final AuthSession? session;
  final MalvaApiClient? apiClient;

  bool get isPackage => package != null;

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  String _method = 'qris';
  bool _isPaying = false;
  String? _error;

  /// Semua e-wallet utama Indonesia.
  static const _wallets = [
    ('gopay', 'GoPay', Icons.account_balance_wallet_rounded),
    ('ovo', 'OVO', Icons.wallet_rounded),
    ('dana', 'DANA', Icons.payments_rounded),
    ('shopeepay', 'ShopeePay', Icons.shopping_bag_rounded),
    ('linkaja', 'LinkAja', Icons.link_rounded),
    ('isaku', 'i.Saku', Icons.credit_score_rounded),
    ('jenius', 'Jenius', Icons.bolt_rounded),
    ('sakuku', 'Sakuku', Icons.paypal_rounded),
  ];

  static const _banks = [
    ('bca_va', 'BCA Virtual Account', Icons.account_balance_rounded),
    ('mandiri_va', 'Mandiri VA', Icons.account_balance_rounded),
    ('bni_va', 'BNI VA', Icons.account_balance_rounded),
    ('bri_va', 'BRI VA', Icons.account_balance_rounded),
    ('permata_va', 'Permata VA', Icons.account_balance_rounded),
    ('cimb_va', 'CIMB Niaga VA', Icons.account_balance_rounded),
    ('cc', 'Credit Card', Icons.credit_card_rounded),
    ('qris', 'QRIS', Icons.qr_code_2_rounded),
  ];

  int get _consultationPrice {
    if (widget.isPackage) return widget.package!.price;
    return widget.booking!.price;
  }

  /// Biaya layanan flat (sama dengan server: 2000).
  static const int _serviceFee = 2000;
  int get _total => _consultationPrice + _serviceFee;

  String get _itemLabel {
    if (widget.isPackage) {
      return 'Paket Continuous (4 sesi / 6 minggu) • ${widget.doctorName}';
    }
    return 'Konsultasi (30 mnt) • ${widget.doctorName}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payment'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const SectionLabel('Payment Detail'),
          SoftCard(
            child: Column(
              children: [
                _Line(label: _itemLabel, value: 'Rp ${_rupiah(_consultationPrice)}'),
                const SizedBox(height: 6),
                _Line(
                    label: 'Service Fee', value: 'Rp ${_rupiah(_serviceFee)}'),
                const Divider(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Total',
                          style: TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                    Text(
                      'Rp ${_rupiah(_total)}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        color: MalvaColors.seed,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Mode pembayaran internal (simulasi gateway). Transaksi tercatat di server.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, color: Colors.black54),
          ),
          const SizedBox(height: 12),
          const SectionLabel('E-Wallet'),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.85,
            children: [
              for (final (value, label, icon) in _wallets)
                _MethodTile(
                  label: label,
                  icon: icon,
                  selected: _method == value,
                  onTap: () => setState(() => _method = value),
                ),
            ],
          ),
          const SizedBox(height: 12),
          const SectionLabel('Virtual Account, Bank & QRIS'),
          GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: 0.85,
            children: [
              for (final (value, label, icon) in _banks)
                _MethodTile(
                  label: label,
                  icon: icon,
                  selected: _method == value,
                  onTap: () => setState(() => _method = value),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(
                    color: MalvaColors.danger, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _isPaying ? null : _pay,
            child: Text(_isPaying ? 'Memproses...' : 'Bayar Sekarang'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Setelah pembayaran berhasil, kamu akan diminta memilih data yang dibagikan ke profesional.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Future<void> _pay() async {
    // Fallback ke provider bila apiClient tidak dioper eksplisit (mis.
    // deep-link), konsisten dengan layar lain.
    final MalvaApiClient apiClient =
        widget.apiClient ?? ref.read(apiClientProvider);
    final accessToken = widget.session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      setState(() => _error = 'Mode offline aktif. '
          'Hubungkan ke server untuk melakukan pembayaran.');
      return;
    }
    setState(() {
      _isPaying = true;
      _error = null;
    });
    try {
      if (widget.isPackage) {
        await _payPackage(apiClient, accessToken);
        return;
      }
      final response = await apiClient.createPayment(
        accessToken: accessToken,
        bookingId: widget.booking!.id,
        paymentMethod: _method,
      );
      final reference = response.payment.reference;
      await apiClient.markPaymentPaid(
        accessToken: accessToken,
        reference: reference,
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentSuccessScreen(
            reference: reference,
            doctorUserId: widget.booking!.professionalId,
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
      if (mounted) setState(() => _isPaying = false);
    }
  }

  /// Bayar paket: pasien memilih slot sesi PERTAMA (chat/video) di sini
  /// lewat sheet yang sama dengan penjadwalan sesi paket — tidak ada lagi
  /// slot otomatis "pertama yang bebas". Setelah bayar, paket aktif dan
  /// sesi pertama langsung terjadwal sesuai pilihan pasien.
  Future<void> _payPackage(
      MalvaApiClient apiClient, String accessToken) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => PackageFirstSessionSheet(
        apiClient: apiClient,
        accessToken: accessToken,
        professionalId: widget.package!.professionalId,
      ),
    );
    if (picked == null || !mounted) return;
    final parts = picked.split('|');
    final booking = await apiClient.createPackageSessionBooking(
      accessToken: accessToken,
      packageId: widget.package!.id,
      bookingDate: parts[0].split('T')[0],
      slotTime: parts[0].split('T')[1],
      sessionType: parts.length > 1 ? parts[1] : 'chat',
    );
    final response = await apiClient.createPayment(
      accessToken: accessToken,
      bookingId: booking.id,
      paymentMethod: _method,
    );
    final reference = response.payment.reference;
    await apiClient.markPaymentPaid(
      accessToken: accessToken,
      reference: reference,
    );
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => PaymentSuccessScreen(
          reference: reference,
          package: widget.package,
          doctorUserId: widget.package!.professionalId,
          doctorName: widget.doctorName,
          session: widget.session,
          apiClient: widget.apiClient,
        ),
      ),
    );
  }

  static String _rupiah(int value) {
    return _rupiahFmt(value);
  }

  static String _rupiahFmt(int value) {
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

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
      ],
    );
  }
}

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: selected
                ? MalvaColors.seed.withValues(alpha: 0.12)
                : MalvaColors.seed.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? MalvaColors.seed
                  : MalvaColors.seed.withValues(alpha: 0.35),
              width: selected ? 2 : 1.5,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: MalvaColors.seed,
                child: Icon(icon, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 15)),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle_rounded, color: MalvaColors.seed),
            ],
          ),
        ),
      );
  }
}
