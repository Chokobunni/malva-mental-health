import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../providers/providers.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';
import '../care_package_screen.dart';
import '../my_care_screen.dart';

// ============================================================
// PAYMENT SUCCESS — reference + receipt + langkah lanjut:
//   Quick consult -> sesi terjadwal (lihat My Care).
//   Paket         -> paket aktif, ajak jadwalkan sesi tersisa.
// ============================================================

class PaymentSuccessScreen extends ConsumerStatefulWidget {
  const PaymentSuccessScreen({
    super.key,
    required this.reference,
    this.package,
    this.doctorUserId = '',
    this.doctorName = 'Profesional',
    this.session,
    this.apiClient,
  });

  final String reference;

  /// Non-null = pembayaran paket (paket sudah aktif di server).
  final BackendCarePackage? package;
  final String doctorUserId;
  final String doctorName;
  final AuthSession? session;
  final MalvaApiClient? apiClient;

  bool get isPackage => package != null;

  @override
  ConsumerState<PaymentSuccessScreen> createState() =>
      _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends ConsumerState<PaymentSuccessScreen> {
  @override
  Widget build(BuildContext context) {
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
                'Transaction reference: #${widget.reference}',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (widget.isPackage) ...[
                const SizedBox(height: 10),
                SoftCard(
                  color: MalvaColors.mint.withValues(alpha: 0.10),
                  child: Row(
                    children: [
                      const Icon(Icons.card_membership_rounded,
                          color: MalvaColors.mint),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Paket aktif: 4 sesi / 6 minggu\n${widget.doctorName}',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                const SizedBox(height: 10),
                SoftCard(
                  color: MalvaColors.seed.withValues(alpha: 0.06),
                  child: Row(
                    children: [
                      const Icon(Icons.event_available_rounded,
                          color: MalvaColors.seed),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Sesi terjadwal dengan ${widget.doctorName}. Chat aktif saat sesi berjalan.',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
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
                onPressed: () => _onContinue(context),
                style: FilledButton.styleFrom(
                  backgroundColor: MalvaColors.mint,
                  minimumSize: const Size.fromHeight(54),
                ),
                child: Text(widget.isPackage
                    ? 'Lihat Paket & Jadwalkan Sesi'
                    : 'Lihat Sesi Saya'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onContinue(BuildContext context) {
    final token = widget.session?.accessToken;
    final MalvaApiClient apiClient =
        widget.apiClient ?? ref.read(apiClientProvider);
    if (widget.isPackage && token != null && token.isNotEmpty) {
      // Muat ulang paket aktif lalu buka layar paket.
      apiClient.listCarePackages(accessToken: token).then((pkgs) {
        if (!context.mounted) return;
        BackendCarePackage? mine;
        for (final p in pkgs) {
          if (p.professionalId == widget.doctorUserId && p.isActive) {
            mine = p;
            break;
          }
        }
        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(
            builder: (_) => CarePackageScreen(
              package: mine ?? widget.package!,
              session: widget.session,
              apiClient: widget.apiClient,
            ),
          ),
          (route) => route.isFirst,
        );
      }).catchError((Object e) {
        if (!context.mounted) return null;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyErrorMessage(e))),
        );
        return null;
      });
      return;
    }
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (_) => MyCareScreen(
          session: widget.session,
          apiClient: widget.apiClient,
        ),
      ),
      (route) => route.isFirst,
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
            _row('Reference', '#${widget.reference}'),
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
