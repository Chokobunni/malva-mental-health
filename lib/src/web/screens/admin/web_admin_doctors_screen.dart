import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/providers.dart';
import '../../../services/malva_api_client.dart';
import '../../../theme.dart';
import '../../../widgets/friendly_error.dart';
import '../../web_format.dart';
import '../../web_theme.dart';
import '../../widgets/web_admin_widgets.dart';
import '../../widgets/web_page_header.dart';

/// Daftar dokter & verifikasi kredensial (`/admin/dokter`).
///
/// Dua bagian: kredensial STR/SIP yang menunggu verifikasi (aksi setuju/tolak)
/// dan seluruh akun dokter (termasuk yang belum/tidak terverifikasi).
class WebAdminDoctorsScreen extends ConsumerStatefulWidget {
  const WebAdminDoctorsScreen({super.key});

  @override
  ConsumerState<WebAdminDoctorsScreen> createState() =>
      _WebAdminDoctorsScreenState();
}

class _WebAdminDoctorsScreenState extends ConsumerState<WebAdminDoctorsScreen> {
  List<BackendProfessionalCredential>? _pending;
  List<BackendDoctorSearchResult>? _doctors;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  String get _accessToken =>
      ref.read(authStateProvider).session?.accessToken ?? '';

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait(<Future<Object>>[
        api.listPendingCredentials(accessToken: _accessToken),
        api.listAdminDoctors(accessToken: _accessToken),
      ]);
      if (!mounted) return;
      setState(() {
        _pending = results[0] as List<BackendProfessionalCredential>;
        _doctors = results[1] as List<BackendDoctorSearchResult>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _verify(
    BackendProfessionalCredential credential, {
    required bool approve,
  }) async {
    String reason = '';
    if (approve) {
      final confirmed = await showWebConfirmDialog(
        context,
        title: 'Setujui kredensial',
        message: 'STR ${credential.strNumber} / SIP ${credential.sipNumber} '
            'akan ditandai terverifikasi. Profesional langsung bisa menerima '
            'pasien.',
        confirmLabel: 'Setujui',
      );
      if (!confirmed || !mounted) return;
    } else {
      final input = await showWebReasonDialog(
        context,
        title: 'Tolak kredensial',
        message: 'Kredensial STR ${credential.strNumber} akan ditolak. Alasan '
            'dikirim ke profesional dan dicatat di audit log.',
        confirmLabel: 'Tolak kredensial',
        destructive: true,
      );
      if (input == null || !mounted) return;
      reason = input;
    }
    try {
      await ref.read(apiClientProvider).verifyCredential(
            accessToken: _accessToken,
            credentialId: credential.id,
            action: approve ? 'approve' : 'reject',
            rejectionReason: reason,
          );
      if (!mounted) return;
      _showMessage(approve
          ? 'Kredensial disetujui.'
          : 'Kredensial ditolak dan alasan tercatat.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showMessage(
          'Gagal memproses kredensial. ${friendlyErrorMessage(error)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WebPageHeader(
          title: 'Dokter',
          subtitle: 'Verifikasi kredensial STR/SIP profesional dan pantau '
              'seluruh akun dokter terdaftar.',
          trailing: OutlinedButton.icon(
            onPressed: _loading ? null : () => unawaited(_load()),
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Muat ulang'),
          ),
        ),
        const SizedBox(height: WebSpacing.section),
        const WebSectionTitle(text: 'KREDENSIAL MENUNGGU VERIFIKASI'),
        const SizedBox(height: 10),
        WebAdminCard(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: _buildPending(),
        ),
        const SizedBox(height: WebSpacing.section),
        const WebSectionTitle(text: 'SEMUA DOKTER'),
        const SizedBox(height: 10),
        WebAdminCard(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: _buildDoctors(),
        ),
      ],
    );
  }

  Widget _buildPending() {
    if (_loading) return const WebAdminLoading(label: 'Memuat kredensial...');
    if (_error != null) {
      return WebAdminError(error: _error!, onRetry: () => unawaited(_load()));
    }
    final pending = _pending ?? const <BackendProfessionalCredential>[];
    return WebAdminTable(
      minWidth: 960,
      emptyMessage: 'Tidak ada kredensial yang menunggu verifikasi.',
      columns: const <WebAdminColumn>[
        WebAdminColumn('ID PENGGUNA', 240),
        WebAdminColumn('NOMOR STR', 170),
        WebAdminColumn('NOMOR SIP', 170),
        WebAdminColumn('SPESIALISASI', 130),
        WebAdminColumn('AKSI', 220, align: Alignment.centerRight),
      ],
      rows: pending
          .map(
            (BackendProfessionalCredential credential) => <Widget>[
              Text(
                credential.userId,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11.5),
              ),
              Text(
                credential.strNumber.isEmpty ? '—' : credential.strNumber,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                credential.sipNumber.isEmpty ? '—' : credential.sipNumber,
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                credential.specialization.isEmpty
                    ? '—'
                    : credential.specialization,
                style: const TextStyle(fontSize: 12),
              ),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 4,
                children: <Widget>[
                  TextButton(
                    onPressed: () =>
                        unawaited(_verify(credential, approve: false)),
                    child: const Text('Tolak'),
                  ),
                  FilledButton(
                    onPressed: () =>
                        unawaited(_verify(credential, approve: true)),
                    child: const Text('Setujui'),
                  ),
                ],
              ),
            ],
          )
          .toList(growable: false),
    );
  }

  Widget _buildDoctors() {
    if (_loading) return const WebAdminLoading(label: 'Memuat dokter...');
    if (_error != null) {
      return WebAdminError(error: _error!, onRetry: () => unawaited(_load()));
    }
    final doctors = _doctors ?? const <BackendDoctorSearchResult>[];
    return WebAdminTable(
      minWidth: 980,
      emptyMessage: 'Belum ada akun dokter.',
      columns: const <WebAdminColumn>[
        WebAdminColumn('NAMA', 210),
        WebAdminColumn('SPESIALISASI', 140),
        WebAdminColumn('RUMAH SAKIT', 220),
        WebAdminColumn('PENGALAMAN', 120),
        WebAdminColumn('BPJS', 90),
        WebAdminColumn('HARGA DARI', 140, align: Alignment.centerRight),
      ],
      rows: doctors
          .map(
            (BackendDoctorSearchResult doctor) => <Widget>[
              Text(
                doctor.displayName.isEmpty ? '—' : doctor.displayName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                doctor.specialization.isEmpty ? '—' : doctor.specialization,
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                doctor.hospitalName.isEmpty ? '—' : doctor.hospitalName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              Text(
                '${doctor.yearsExperience} tahun',
                style: const TextStyle(fontSize: 12),
              ),
              WebStatusPill(
                label: doctor.isBpjsSupported ? 'Ya' : 'Tidak',
                color: doctor.isBpjsSupported
                    ? MalvaColors.mint
                    : const Color(0xFF8B8194),
              ),
              Text(
                formatRupiah(doctor.priceFrom),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          )
          .toList(growable: false),
    );
  }
}
