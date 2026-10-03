import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';
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
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PostPaymentConsentSheet(
                      session: session,
                      apiClient: apiClient,
                    ),
                  ),
                ),
                child: const Text('Atur Data Sharing'),
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

class PostPaymentConsentSheet extends ConsumerStatefulWidget {
  const PostPaymentConsentSheet({super.key, this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<PostPaymentConsentSheet> createState() =>
      _PostPaymentConsentSheetState();
}

class _PostPaymentConsentSheetState
    extends ConsumerState<PostPaymentConsentSheet> {
  bool _mood = true;
  bool _diary = true;
  bool _medication = true;
  bool _healthRecord = true;
  bool _goals = true;
  bool _isSaving = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Sharing'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Submit & Connect',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                ),
                SizedBox(height: 4),
                Text(
                  'Kamu berhasil berlangganan Continuous Support. Pilih data yang boleh dibaca profesional.',
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ConsentRow(
            label: 'Mood Check-In',
            value: _mood,
            onChanged: (v) => setState(() => _mood = v),
          ),
          _ConsentRow(
            label: 'Diary',
            value: _diary,
            onChanged: (v) => setState(() => _diary = v),
          ),
          _ConsentRow(
            label: 'Medication Check-In',
            value: _medication,
            onChanged: (v) => setState(() => _medication = v),
          ),
          _ConsentRow(
            label: 'Health Record',
            value: _healthRecord,
            onChanged: (v) => setState(() => _healthRecord = v),
          ),
          _ConsentRow(
            label: 'Goals',
            value: _goals,
            onChanged: (v) => setState(() => _goals = v),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(
                    color: MalvaColors.danger, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _isSaving ? null : _save,
            child: Text(_isSaving ? 'Menyimpan...' : 'Submit & Connect'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    final apiClient = widget.apiClient;
    final session = widget.session;
    if (apiClient == null || session == null) {
      if (!mounted) return;
      Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }
    final accessToken = session.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      if (!mounted) return;
      Navigator.popUntil(context, (route) => route.isFirst);
      return;
    }
    setState(() {
      _isSaving = true;
      _error = null;
    });
    try {
      final links = await apiClient.listPatientProfessionalLinks(
        accessToken: accessToken,
      );
      for (final link in links) {
        await apiClient.updatePrivacyConsent(
          accessToken: accessToken,
          professionalId: link.professionalUserId.isEmpty
              ? link.professionalId
              : link.professionalUserId,
          shareScreenings: _healthRecord,
          shareMoodDiary: _mood || _diary,
          shareMedications: _medication,
          shareTimeline: true,
        );
      }
      if (!mounted) return;
      Navigator.popUntil(context, (route) => route.isFirst);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Berhasil terhubung. Selamat datang!')),
      );
    } on MalvaApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }
}

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        activeThumbColor: MalvaColors.seed,
        contentPadding: EdgeInsets.zero,
      ),
    );
  }
}
