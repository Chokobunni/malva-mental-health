import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';
import 'payment_success_screen.dart';

// ============================================================
// PAYMENT — break-down + 4 metode
// ============================================================

class PaymentScreen extends ConsumerStatefulWidget {
  const PaymentScreen({
    super.key,
    required this.booking,
    this.session,
    this.apiClient,
  });

  final BackendBooking booking;
  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends ConsumerState<PaymentScreen> {
  String _method = 'gopay';
  bool _isPaying = false;
  String? _error;

  static const _wallets = [
    ('gopay', 'GoPay', Icons.account_balance_wallet_rounded),
    ('ovo', 'OVO', Icons.wallet_rounded),
    ('dana', 'DANA', Icons.payments_rounded),
    ('shopeepay', 'ShopeePay', Icons.shopping_bag_rounded),
  ];

  static const _banks = [
    ('bca_va', 'BCA Virtual Account', Icons.account_balance_rounded),
    ('mandiri_va', 'Mandiri VA', Icons.account_balance_rounded),
    ('bri_va', 'BRI VA', Icons.account_balance_rounded),
    ('cc', 'Credit Card', Icons.credit_card_rounded),
  ];

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
                _Line(label: 'Konsultasi', value: 'Rp ${_rupiah(150000)}'),
                const SizedBox(height: 6),
                _Line(label: 'Service Fee', value: 'Rp ${_rupiah(2000)}'),
                const Divider(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: Text('Total',
                          style: TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16)),
                    ),
                    Text(
                      'Rp ${_rupiah(152000)}',
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
          const SizedBox(height: 14),
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
          const SectionLabel('Virtual Account & Bank'),
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
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      setState(() => _error = 'Mode offline aktif. '
          'Hubungkan ke server untuk melakukan pembayaran.');
      return;
    }
    setState(() {
      _isPaying = true;
      _error = null;
    });
    try {
      final response = await apiClient.createPayment(
        accessToken: accessToken,
        bookingId: widget.booking.id,
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
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: selected
              ? MalvaColors.seed.withValues(alpha: 0.12)
              : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? MalvaColors.seed
                : Colors.black.withValues(alpha: 0.12),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: selected ? MalvaColors.seed : Colors.black54),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
                color: selected ? MalvaColors.seed : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
