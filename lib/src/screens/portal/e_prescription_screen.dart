export 'prescription_wizard_screen.dart' show EPrescriptionFormScreen;

import 'prescription_wizard_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../professional_role.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';

// ============================================================
// E-PRESCRIPTION (professional, psikiater only)
// ============================================================

class EPrescriptionScreen extends ConsumerStatefulWidget {
  const EPrescriptionScreen({
    super.key,
    this.session,
    this.apiClient,
    this.preselectedPatientId = '',
    this.preselectedPatientName = '',
  });

  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final String preselectedPatientId;
  final String preselectedPatientName;

  @override
  ConsumerState<EPrescriptionScreen> createState() =>
      _EPrescriptionScreenState();
}

class _EPrescriptionScreenState extends ConsumerState<EPrescriptionScreen> {
  List<BackendEPrescription> _prescriptions = const [];
  List<BackendPatientProfessionalLink> _links = const [];
  bool _isLoading = true;
  String? _error;

  /// True bila profesional yang login adalah Psikiater (Sp.KJ) — satu-satunya
  /// peran yang boleh menerbitkan resep. Default false (terkunci) sampai
  /// kredensial termuat.
  bool _isPsychiatrist = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Mode offline aktif. '
              'Hubungkan ke server untuk melihat resep.';
        });
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        apiClient.listEPrescriptions(accessToken: accessToken),
        apiClient.listPatientProfessionalLinks(accessToken: accessToken),
      ]);
      // Muat kredensial sendiri untuk menentukan apakah Psikiater. Kegagalan
      // memuat kredensial tidak boleh menjatuhkan seluruh layar — perlakukan
      // sebagai bukan psikiater (terkunci, aman; server tetap menegakkan).
      BackendProfessionalCredential? cred;
      try {
        cred = await apiClient.getMyCredentials(accessToken: accessToken);
      } on Object {
        cred = null;
      }
      if (!mounted) return;
      setState(() {
        _prescriptions = results[0] as List<BackendEPrescription>;
        _links = results[1] as List<BackendPatientProfessionalLink>;
        _isPsychiatrist =
            cred != null && isPsychiatristSpecialization(cred.specialization);
        _isLoading = false;
      });
    } on MalvaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorMessage(e);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('E-Prescription'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      floatingActionButton: (!_isLoading && _isPsychiatrist)
          ? FloatingActionButton.extended(
              heroTag: 'erx_add_fab',
              onPressed: () => _openCreate(context),
              backgroundColor: MalvaColors.seed,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Resep Baru',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
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
                      'Hanya psikiater (Sp.KJ) terverifikasi yang dapat menerbitkan resep dengan digital signature + QR.',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              SoftCard(
                bordered: true,
                child: Column(
                  children: [
                    Text(_error!,
                        style: const TextStyle(
                            color: MalvaColors.danger,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _load,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Coba Lagi'),
                    ),
                  ],
                ),
              )
            else if (!_isPsychiatrist)
              const _LockedPrescriptionCard()
            else if (_prescriptions.isEmpty)
              const EmptyState(
                icon: Icons.medication_liquid_outlined,
                title: 'Belum ada resep',
                subtitle: 'Resep yang diterbitkan akan tercatat di sini.',
              )
            else
              for (final rx in _prescriptions) ...[
                _PrescriptionCard(
                  rx: rx,
                  onTap: () => _openDetail(context, rx),
                ),
                const SizedBox(height: 12),
              ],
          ],
        ),
      ),
    );
  }

  void _openCreate(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EPrescriptionFormScreen(
          session: widget.session,
          apiClient: widget.apiClient,
          links: _links,
          preselectedPatientId: widget.preselectedPatientId,
          preselectedPatientName: widget.preselectedPatientName,
          onCreated: _load,
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, BackendEPrescription rx) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EPrescriptionDetailScreen(
          session: widget.session,
          apiClient: widget.apiClient,
          prescriptionId: rx.id,
        ),
      ),
    );
  }
}

/// Kartu terkunci untuk profesional non-Psikiater. Menjelaskan bahwa resep
/// hanya untuk Psikiater (Sp.KJ) — menggantikan form/list agar tidak ada
/// tombol yang pasti ditolak server.
class _LockedPrescriptionCard extends StatelessWidget {
  const _LockedPrescriptionCard();

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      bordered: true,
      child: Column(
        children: [
          const Icon(Icons.lock_outline_rounded,
              size: 40, color: MalvaColors.amber),
          const SizedBox(height: 12),
          const Text(
            'Hanya Psikiater (Sp.KJ) yang dapat meresepkan obat.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 6),
          Text(
            'Psikolog (M.Psi) tidak dapat menerbitkan resep. Fitur ini khusus '
            'untuk Psikiater.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _PrescriptionCard extends StatelessWidget {
  const _PrescriptionCard({required this.rx, required this.onTap});

  final BackendEPrescription rx;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      bordered: true,
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: MalvaColors.mint.withValues(alpha: 0.12),
            child:
                const Icon(Icons.medication_rounded, color: MalvaColors.mint),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${rx.items.length} item obat',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  'QR: ${rx.qrToken.isEmpty ? '-' : rx.qrToken}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const StatusPill(
            label: 'Issued',
            color: MalvaColors.mint,
            icon: Icons.check_circle_rounded,
          ),
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

// ============================================================
// E-PRESCRIPTION FORM
// ============================================================

// ============================================================
// E-PRESCRIPTION DETAIL (signature + QR token)
// ============================================================

class EPrescriptionDetailScreen extends ConsumerStatefulWidget {
  const EPrescriptionDetailScreen({
    super.key,
    this.session,
    this.apiClient,
    required this.prescriptionId,
  });

  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final String prescriptionId;

  @override
  ConsumerState<EPrescriptionDetailScreen> createState() =>
      _EPrescriptionDetailScreenState();
}

class _EPrescriptionDetailScreenState
    extends ConsumerState<EPrescriptionDetailScreen> {
  BackendEPrescription? _rx;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Mode offline aktif. '
              'Hubungkan ke server untuk melihat detail resep.';
        });
      }
      return;
    }
    try {
      final rx = await apiClient.getEPrescription(
        accessToken: accessToken,
        prescriptionId: widget.prescriptionId,
      );
      if (!mounted) return;
      setState(() {
        _rx = rx;
        _isLoading = false;
      });
    } on MalvaApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _isLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorMessage(e);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final sig = _rx?.signatureData ?? const {};
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detail Resep'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _rx == null
                  ? const Center(child: Text('Resep tidak ditemukan.'))
                  : ListView(
                      padding: const EdgeInsets.all(18),
                      children: [
                        SoftCard(
                          bordered: true,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Prescription',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16)),
                              const Divider(height: 20),
                              for (final item in _rx!.items) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(item.name,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w800)),
                                          Text(
                                              '${item.dosage} • ${item.frequency} • ${item.days} hari',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 16),
                              ],
                              if (_rx!.instructions.isNotEmpty) ...[
                                const Text('Instructions',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w900)),
                                Text(_rx!.instructions),
                                const SizedBox(height: 10),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        SoftCard(
                          bordered: true,
                          color: MalvaColors.seed.withValues(alpha: 0.06),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Digital Signature',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 6),
                              Text(
                                  'STR/SIP: ${sig['str_number'] ?? sig['sip_number'] ?? '-'}'),
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: Colors.black12),
                                ),
                                child: Column(
                                  children: [
                                    const Icon(Icons.qr_code_2_rounded,
                                        size: 72, color: MalvaColors.ink),
                                    const SizedBox(height: 4),
                                    SelectableText(
                                      _rx!.qrToken,
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'Tunjukkan kode ini untuk verifikasi apotek.',
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
    );
  }
}
