import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';
import '../chat_screen.dart';
import 'consent_request_sheet.dart';

// ============================================================
// PAYMENT SUCCESS — reference + receipt + connect + chat
// ============================================================

class PaymentSuccessScreen extends ConsumerStatefulWidget {
  const PaymentSuccessScreen({
    super.key,
    required this.reference,
    this.isContinuousSupport = false,
    this.doctorUserId = '',
    this.doctorName = 'Profesional',
    this.periodLabel = '',
    this.session,
    this.apiClient,
  });

  final String reference;

  /// true = Continuous Support: Continue -> link profesional ->
  /// dialog "You're Connected!" -> chat dengan psikiater.
  /// Quick Consult langsung pulang (tanpa sharing).
  final bool isContinuousSupport;
  final String doctorUserId;
  final String doctorName;
  final String periodLabel;
  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<PaymentSuccessScreen> createState() =>
      _PaymentSuccessScreenState();
}

class _PaymentSuccessScreenState extends ConsumerState<PaymentSuccessScreen> {
  bool _connecting = false;
  bool _connected = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Continuous Support: begitu pembayaran sukses, langsung hubungkan ke
    // profesional & tampilkan "You're Connected!" -> chat (tanpa klik ulang).
    if (widget.isContinuousSupport) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_connected && !_connecting) {
          _onContinue(context);
        }
      });
    }
  }

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
              if (widget.isContinuousSupport &&
                  widget.periodLabel.isNotEmpty) ...[
                const SizedBox(height: 10),
                SoftCard(
                  color: MalvaColors.mint.withValues(alpha: 0.10),
                  child: Row(
                    children: [
                      const Icon(Icons.calendar_month_rounded,
                          color: MalvaColors.mint),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${widget.doctorName}\n${widget.periodLabel}',
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
              if (_error != null) ...[
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: MalvaColors.danger,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
              ],
              FilledButton(
                onPressed: (_connecting || _connected)
                    ? null
                    : () => _onContinue(context),
                style: FilledButton.styleFrom(
                  backgroundColor: MalvaColors.mint,
                  minimumSize: const Size.fromHeight(54),
                ),
                child: Text(_connecting
                    ? 'Menghubungkan...'
                    : _connected
                        ? 'Terhubung ✓'
                        : widget.isContinuousSupport
                            ? 'Connect & Continue'
                            : 'Continue'),
              ),
              // Ubah izin sharing kapan saja (satu UI consent yang sama).
              if (widget.isContinuousSupport) ...[
                const SizedBox(height: 10),
                OutlinedButton(
                  onPressed: _connecting
                      ? null
                      : () => showConsentRequestSheet(
                            context: context,
                            professionalId: widget.doctorUserId,
                          ),
                  child: const Text('Atur Data Sharing'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _onContinue(BuildContext context) async {
    if (!widget.isContinuousSupport) {
      // Quick Consult: selesai, pulang ke Home.
      Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null ||
        accessToken == null ||
        accessToken.isEmpty ||
        widget.doctorUserId.isEmpty) {
      setState(() => _error =
          'Tidak bisa terhubung: sesi atau data dokter tidak lengkap.');
      return;
    }
    setState(() {
      _connecting = true;
      _error = null;
    });
    try {
      // Pastikan link pasien-profesional aktif (idempotent di server).
      await apiClient.linkProfessional(
        accessToken: accessToken,
        professionalId: widget.doctorUserId,
      );
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _connected = true;
      });
      _showConnectedDialog(context);
    } on MalvaApiException catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = e.message;
        });
      }
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _connecting = false;
          _error = friendlyErrorMessage(e);
        });
      }
    }
  }

  /// Notifikasi "You're Connected!" -> langsung chat dengan psikiater.
  void _showConnectedDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: MalvaColors.mint.withValues(alpha: 0.15),
          ),
          child: const Icon(Icons.handshake_rounded,
              color: MalvaColors.mint, size: 40),
        ),
        title: const Text("You're Connected!"),
        content: Text(
          'Kamu terhubung dengan ${widget.doctorName}'
          '${widget.periodLabel.isEmpty ? '' : '\n${widget.periodLabel}'}\n\n'
          'Chat 24/7 selama 7 hari. Kamu bisa berbagi ringkasan, '
          'hasil assessment, resep, goals & habits langsung di chat.',
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.popUntil(context, (route) => route.isFirst);
            },
            child: const Text('Nanti'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pushReplacement(
                context,
                MaterialPageRoute(
                  builder: (_) => ChatScreen(
                    otherUserName: widget.doctorName,
                    otherUserId: widget.doctorUserId,
                  ),
                ),
              );
            },
            style: compactFilledButtonStyle,
            child: const Text('Chat Sekarang'),
          ),
        ],
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
