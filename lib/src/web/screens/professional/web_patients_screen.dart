import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/providers.dart';
import '../../../services/malva_api_client.dart';
import '../../../theme.dart';
import '../../services/web_assessment_service.dart';
import '../../web_format.dart';
import '../../web_theme.dart';
import '../../widgets/web_admin_widgets.dart';
import '../../widgets/web_page_header.dart';

/// Daftar pasien terhubung untuk profesional (`/pasien`).
///
/// Jumlah screening & status krisis diambil per pasien saat detail dibuka
/// (bukan untuk semua baris) agar tidak terjadi N+1 permintaan saat halaman
/// dimuat.
class WebPatientsScreen extends ConsumerStatefulWidget {
  const WebPatientsScreen({super.key});

  @override
  ConsumerState<WebPatientsScreen> createState() => _WebPatientsScreenState();
}

class _WebPatientsScreenState extends ConsumerState<WebPatientsScreen> {
  List<BackendPatientProfessionalLink> _links =
      const <BackendPatientProfessionalLink>[];
  bool _loading = true;
  Object? _error;
  String _query = '';

  String get _token => ref.read(authStateProvider).session?.accessToken ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final links = await ref
          .read(apiClientProvider)
          .listPatientProfessionalLinks(accessToken: _token);
      if (!mounted) return;
      setState(() {
        _links = links;
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

  List<BackendPatientProfessionalLink> get _filtered {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _links;
    return _links
        .where((BackendPatientProfessionalLink link) =>
            link.patientDisplayName.toLowerCase().contains(query))
        .toList(growable: false);
  }

  Future<void> _openSummary(BackendPatientProfessionalLink link) async {
    await showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) => _PatientSummaryDialog(
        link: link,
        accessToken: _token,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final patients = _filtered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WebPageHeader(
          title: 'Pasien',
          subtitle: 'Pasien yang terhubung dengan Anda. Buka ringkasan untuk '
              'melihat hasil skrining terakhir.',
          trailing: OutlinedButton.icon(
            onPressed: _loading ? null : () => unawaited(_load()),
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Muat ulang'),
          ),
        ),
        const SizedBox(height: WebSpacing.section),
        WebAdminCard(
          child: SizedBox(
            width: 300,
            child: TextField(
              key: const Key('web-patients-search'),
              onChanged: (String value) => setState(() => _query = value),
              decoration: const InputDecoration(
                labelText: 'Cari nama pasien',
                prefixIcon: Icon(Icons.search_rounded, size: 20),
                isDense: true,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        WebAdminCard(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: _buildBody(patients),
        ),
      ],
    );
  }

  Widget _buildBody(List<BackendPatientProfessionalLink> patients) {
    if (_loading) return const WebAdminLoading(label: 'Memuat pasien...');
    if (_error != null) {
      return WebAdminError(error: _error!, onRetry: () => unawaited(_load()));
    }
    return WebAdminTable(
      minWidth: 900,
      emptyMessage: 'Belum ada pasien terhubung.',
      columns: const <WebAdminColumn>[
        WebAdminColumn('PASIEN', 280),
        WebAdminColumn('STATUS HUBUNGAN', 180),
        WebAdminColumn('PROFESIONAL', 240),
        WebAdminColumn('', 140, align: Alignment.centerRight),
      ],
      rowKeyBuilder: (int index) =>
          Key('patient-row-${patients[index].patientId}'),
      rows: patients
          .map(
            (BackendPatientProfessionalLink link) => <Widget>[
              Text(
                link.patientDisplayName.isEmpty
                    ? link.patientId
                    : link.patientDisplayName,
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              WebStatusPill(
                label: link.status.isEmpty ? 'terhubung' : link.status,
                color: link.status.toLowerCase() == 'active'
                    ? MalvaColors.mint
                    : const Color(0xFF8B8194),
              ),
              Text(
                link.professionalDisplayName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12),
              ),
              TextButton(
                key: Key('patient-open-${link.patientId}'),
                onPressed: () => unawaited(_openSummary(link)),
                child: const Text('Ringkasan'),
              ),
            ],
          )
          .toList(growable: false),
    );
  }
}

/// Dialog ringkas pasien: jumlah screening, status krisis terakhir, sesi.
class _PatientSummaryDialog extends ConsumerStatefulWidget {
  const _PatientSummaryDialog({
    required this.link,
    required this.accessToken,
  });

  final BackendPatientProfessionalLink link;
  final String accessToken;

  @override
  ConsumerState<_PatientSummaryDialog> createState() =>
      _PatientSummaryDialogState();
}

class _PatientSummaryDialogState extends ConsumerState<_PatientSummaryDialog> {
  List<BackendScreeningSession> _screenings = const <BackendScreeningSession>[];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final screenings = await ref.read(apiClientProvider).listScreenings(
            accessToken: widget.accessToken,
            patientId: widget.link.patientId,
            limit: 20,
          );
      if (!mounted) return;
      setState(() {
        _screenings = screenings;
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

  @override
  Widget build(BuildContext context) {
    final latest = _screenings.isEmpty ? null : _screenings.first;
    final hasCrisis =
        _screenings.any((BackendScreeningSession s) => s.crisisFlag);
    return AlertDialog(
      title: Text(
        widget.link.patientDisplayName.isEmpty
            ? 'Ringkasan pasien'
            : widget.link.patientDisplayName,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (_loading)
              const WebAdminLoading(label: 'Memuat data pasien...')
            else if (_error != null)
              WebAdminError(error: _error!, onRetry: () => unawaited(_load()))
            else ...<Widget>[
              Text(
                'Total screening: ${_screenings.length}',
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 6),
              Text(
                latest == null
                    ? 'Belum ada screening.'
                    : 'Terakhir: ${formatWibDateTimeOrDash(latest.createdAt)} WIB · '
                        'level ${webRiskLevelLabel(latest.overallLevel)}',
                style: const TextStyle(
                  fontSize: 12.5,
                  color: Color(0xFF6B6377),
                ),
              ),
              const SizedBox(height: 10),
              if (hasCrisis)
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: MalvaColors.danger.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'Ada indikator krisis pada riwayat screening pasien ini. '
                    'Tinjau sebagai prioritas.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      fontWeight: FontWeight.w600,
                      color: MalvaColors.danger,
                    ),
                  ),
                )
              else
                const Text(
                  'Tidak ada indikator krisis pada screening terakhir.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF1F7A66)),
                ),
              const SizedBox(height: 10),
              Text(
                'Status hubungan: ${widget.link.status.isEmpty ? 'terhubung' : widget.link.status}',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF8B8194),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: <Widget>[
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Tutup'),
        ),
      ],
    );
  }
}
