import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../providers/providers.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';
import '../../widgets/professional_avatar.dart';
import 'consent_request_sheet.dart';
import 'payment_screen.dart';

// ============================================================
// PACKAGE BOOKING — beli paket Continuous 4 sesi / 6 minggu.
// Alur: ringkasan aturan -> consent sharing -> buat paket
// (pending_payment) -> payment -> paket aktif -> jadwalkan sesi.
// ============================================================

class PackageBookingScreen extends ConsumerStatefulWidget {
  const PackageBookingScreen({
    super.key,
    required this.doctorUserId,
    required this.doctorName,
    required this.price,
    required this.doctorPhotoUrl,
    this.session,
    this.apiClient,
  });

  final String doctorUserId;
  final String doctorName;
  final int price;

  /// URL foto profil profesional. Kosong = pakai avatar gradien + inisial.
  final String doctorPhotoUrl;
  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<PackageBookingScreen> createState() =>
      _PackageBookingScreenState();
}

class _PackageBookingScreenState extends ConsumerState<PackageBookingScreen> {
  bool _isSubmitting = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paket Continuous'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SoftCard(
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
                        label: 'Paket 4 Sesi • 6 Minggu',
                        color: MalvaColors.mint,
                        icon: Icons.handshake_rounded,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SoftCard(
            color: MalvaColors.seed.withValues(alpha: 0.06),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Aturan paket',
                    style:
                        TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                const SizedBox(height: 8),
                for (final rule in const [
                  '4 sesi pertemuan (chat/video) dengan profesional ini.',
                  'Berlaku 6 minggu sejak pembayaran — sisa sesi setelah itu hangus.',
                  'Tidak hadir saat sesi = sesi hangus (tetap dihitung berkurang).',
                  'Profesional membatalkan = kredit sesi kembali, bisa dijadwalkan ulang.',
                  'Kamu bisa mengirim diary, goals, assessment & worksheet selama paket aktif.',
                  'Profesional membahas kirimanmu saat sesi — tanpa kewajiban membalas di luar sesi.',
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check_circle_rounded,
                            size: 16, color: MalvaColors.mint),
                        const SizedBox(width: 8),
                        Expanded(child: Text(rule)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SoftCard(
            color: MalvaColors.plum,
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Paket 4 sesi / 6 minggu',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  'Rp ${_formatRupiah(widget.price)}',
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
            onPressed: _isSubmitting ? null : _submit,
            icon: const Icon(Icons.handshake_rounded),
            label: Text(_isSubmitting
                ? 'Memproses...'
                : 'Beli Paket — Rp ${_formatRupiah(widget.price)}'),
          ),
          const SizedBox(height: 6),
          const Text(
            'Setelah pembayaran, paket aktif 6 minggu dan kamu bisa menjadwalkan 4 sesi.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    // Fallback ke provider agar pembelian paket tetap jalan bila apiClient
    // tidak dioper eksplisit (deep-link), konsisten dengan layar lain.
    final MalvaApiClient apiClient =
        widget.apiClient ?? ref.read(apiClientProvider);
    final accessToken = widget.session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      setState(() => _error = 'Mode offline aktif. '
          'Hubungkan ke server untuk membeli paket.');
      return;
    }
    // Consent DULU (sebelum ada paket yatim di server).
    final granted = await showConsentRequestSheet(
      context: context,
      professionalId: widget.doctorUserId,
    );
    if (!granted || !mounted) return;
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final pkg = await apiClient.createCarePackage(
        accessToken: accessToken,
        professionalId: widget.doctorUserId,
      );
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentScreen(
            package: pkg,
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
      if (mounted) setState(() => _isSubmitting = false);
    }
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
