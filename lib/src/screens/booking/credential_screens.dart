import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/malva_components.dart';

// ============================================================
// PROFESSIONAL CREDENTIAL UPLOAD (STR/SIP)
// ============================================================

class CredentialUploadScreen extends ConsumerStatefulWidget {
  const CredentialUploadScreen({super.key, this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<CredentialUploadScreen> createState() =>
      _CredentialUploadScreenState();
}

class _CredentialUploadScreenState
    extends ConsumerState<CredentialUploadScreen> {
  final _str = TextEditingController();
  final _sip = TextEditingController();
  final _sipp = TextEditingController();
  final _hospital = TextEditingController();
  final _bio = TextEditingController();
  String _specialization = 'M.Psi';
  bool _isBpjs = false;
  bool _isSubmitting = false;
  String? _error;
  BackendProfessionalCredential? _submitted;

  @override
  void dispose() {
    _str.dispose();
    _sip.dispose();
    _sipp.dispose();
    _hospital.dispose();
    _bio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verifikasi STR/SIP'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: MalvaColors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: MalvaColors.amber.withValues(alpha: 0.35),
              ),
            ),
            child: const Row(
              children: [
                Icon(Icons.verified_outlined, color: MalvaColors.amber),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Akun profesional wajib diverifikasi admin (STR/SIP) sebelum bisa mengakses data pasien.',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          if (_submitted != null) ...[
            SoftCard(
              color: MalvaColors.mint.withValues(alpha: 0.1),
              child: Column(
                children: [
                  const Icon(Icons.mark_email_read_rounded,
                      color: MalvaColors.mint, size: 44),
                  const SizedBox(height: 8),
                  const Text(
                    'Dokumen Terkirim',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Status: ${_submitted!.verificationStatus}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Selesai'),
                  ),
                ],
              ),
            ),
          ] else ...[
            const SectionLabel('Spesialisasi'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'M.Psi', label: Text('Psikolog M.Psi')),
                ButtonSegment(value: 'Sp.KJ', label: Text('Psikiater Sp.KJ')),
              ],
              selected: {_specialization},
              onSelectionChanged: (s) =>
                  setState(() => _specialization = s.first),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _str,
              decoration: const InputDecoration(
                labelText: 'Nomor STR',
                hintText: 'cth: 1234567890123456',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _sip,
              decoration: const InputDecoration(
                labelText: 'Nomor SIP',
                hintText: 'cth: 20180844-2020-02-0261',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _sipp,
              decoration: const InputDecoration(
                labelText: 'Nomor SIPP (opsional)',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _hospital,
              decoration: const InputDecoration(
                labelText: 'Rumah sakit / klinik praktik',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _bio,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Bio singkat & pendekatan terapi',
                hintText: 'cth: CBT, mindfulness, relaksasi...',
              ),
            ),
            SwitchListTile(
              value: _isBpjs,
              onChanged: (v) => setState(() => _isBpjs = v),
              title: const Text('Mendukung BPJS',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              activeThumbColor: MalvaColors.mint,
              contentPadding: EdgeInsets.zero,
            ),
            if (_error != null) ...[
              Text(_error!,
                  style: const TextStyle(
                      color: MalvaColors.danger, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
            ],
            FilledButton(
              onPressed: _isSubmitting ? null : _submit,
              child: Text(
                  _isSubmitting ? 'Mengirim...' : 'Kirim untuk Verifikasi'),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      setState(() => _error = 'Login diperlukan.');
      return;
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final cred = await apiClient.uploadProfessionalCredentials(
        accessToken: accessToken,
        strNumber: _str.text.trim(),
        sipNumber: _sip.text.trim(),
        sippNumber: _sipp.text.trim(),
        specialization: _specialization,
        hospitalName: _hospital.text.trim(),
        isBpjsSupported: _isBpjs,
        bio: _bio.text.trim(),
      );
      if (!mounted) return;
      setState(() => _submitted = cred);
    } on MalvaApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = 'Gagal mengirim: $e');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}

// ============================================================
// WAITING VERIFICATION
// ============================================================

class WaitingVerificationScreen extends StatelessWidget {
  const WaitingVerificationScreen({super.key, this.status = 'PENDING'});

  final String status;

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
                  color: MalvaColors.amber.withValues(alpha: 0.15),
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  color: MalvaColors.amber,
                  size: 56,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Menunggu Verifikasi',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24),
              ),
              const SizedBox(height: 8),
              Text(
                'Dokumen STR/SIP kamu sedang direview tim admin Malva (status: $status). Kamu akan diberi tahu setelah disetujui.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Kembali'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
