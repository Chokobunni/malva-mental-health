import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/malva_components.dart';

// ============================================================
// PAYMENT SUCCESS — reference + receipt + continue
// ============================================================

class PaymentSuccessScreen extends ConsumerWidget {
  const PaymentSuccessScreen({
    super.key,
    required this.reference,
    this.session,
    this.apiClient,
  });

  final String reference;
  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MalvaColors.mint.withValues(alpha: 0.15),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  color: MalvaColors.mint,
                  size: 64,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Payment Received!',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24),
              ),
              const SizedBox(height: 8),
              Text(
                'Transaction reference: #$reference',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              TextButton(
                onPressed: () => _showReceipt(context),
                child: const Text(
                  'View Receipt',
                  style: TextStyle(
                    color: MalvaColors.seed,
                    decoration: TextDecoration.underline,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: () =>
                    Navigator.popUntil(context, (route) => route.isFirst),
                style: FilledButton.styleFrom(
                  backgroundColor: MalvaColors.mint,
                  minimumSize: const Size.fromHeight(54),
                ),
                child: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showReceipt(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Receipt'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _row('Reference', '#$reference'),
            _row('Status', 'PAID'),
            _row(
                'Tanggal',
                DateTime.now()
                    .toString()
                    .substring(0, 16)
                    .replaceAll('T', ' ')),
            const SizedBox(height: 8),
            const Text(
              'Simpan nomor referensi ini untuk keperluan audit dan refund.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
