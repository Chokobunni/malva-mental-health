import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
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
      if (!mounted) return;
      setState(() {
        _prescriptions = results[0] as List<BackendEPrescription>;
        _links = results[1] as List<BackendPatientProfessionalLink>;
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
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'erx_add_fab',
        onPressed: () => _openCreate(context),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Resep Baru',
            style: TextStyle(fontWeight: FontWeight.w800)),
      ),
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

class _PrescriptionCard extends StatelessWidget {
  const _PrescriptionCard({required this.rx, required this.onTap});

  final BackendEPrescription rx;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
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

const _kFrequencies = [
  '1x daily',
  '2x daily',
  '3x daily',
  '4x daily',
  'prn',
];

class EPrescriptionFormScreen extends ConsumerStatefulWidget {
  const EPrescriptionFormScreen({
    super.key,
    this.session,
    this.apiClient,
    this.links = const [],
    this.preselectedPatientId = '',
    this.preselectedPatientName = '',
    this.onCreated,
  });

  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final List<BackendPatientProfessionalLink> links;
  final String preselectedPatientId;
  final String preselectedPatientName;
  final VoidCallback? onCreated;

  @override
  ConsumerState<EPrescriptionFormScreen> createState() =>
      _EPrescriptionFormScreenState();
}

class _ItemDraft {
  String name = '';
  String dosage = '';
  String frequency = '1x daily';
  int days = 30;
  int unitsPerDay = 1;
}

class _EPrescriptionFormScreenState
    extends ConsumerState<EPrescriptionFormScreen> {
  String? _patientId;
  final _instructions = TextEditingController();
  final _notes = TextEditingController();
  final List<_ItemDraft> _items = [_ItemDraft()];
  bool _isSubmitting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.preselectedPatientId.isNotEmpty) {
      _patientId = widget.preselectedPatientId;
    }
  }

  @override
  void dispose() {
    _instructions.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Resep Baru'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const SectionLabel('Pasien'),
          if (widget.links.isEmpty)
            const Text('Tidak ada pasien terhubung.')
          else
            DropdownButtonFormField<String>(
              initialValue: _patientId,
              decoration: const InputDecoration(labelText: 'Pilih pasien'),
              items: [
                for (final link in widget.links)
                  DropdownMenuItem(
                    value: link.patientId,
                    child: Text(link.patientDisplayName.isEmpty
                        ? link.patientId
                        : link.patientDisplayName),
                  ),
              ],
              onChanged: (v) => setState(() => _patientId = v),
            ),
          const SizedBox(height: 14),
          SectionLabel(
            'Item Obat',
            action: TextButton.icon(
              onPressed: () => setState(() => _items.add(_ItemDraft())),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Tambah'),
            ),
          ),
          for (var i = 0; i < _items.length; i++) ...[
            _ItemEditor(
              index: i,
              draft: _items[i],
              canRemove: _items.length > 1,
              onRemove: () => setState(() => _items.removeAt(i)),
              onChanged: () => setState(() {}),
            ),
            const SizedBox(height: 10),
          ],
          const SectionLabel('Instruksi & Catatan'),
          TextField(
            controller: _instructions,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Instruksi pemakaian',
              hintText: 'cth: Diminum setelah makan...',
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Catatan (opsional)',
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: MalvaColors.seed.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'Resep diterbitkan dengan digital signature (STR/SIP) + QR verifikasi otomatis.',
              style: TextStyle(fontSize: 12),
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
            style: FilledButton.styleFrom(backgroundColor: MalvaColors.mint),
            icon: const Icon(Icons.send_rounded),
            label: Text(
                _isSubmitting ? 'Menerbitkan...' : 'Issue & Send Prescription'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      setState(() => _error = 'Mode offline aktif. '
          'Hubungkan ke server untuk menerbitkan resep.');
      return;
    }
    if (_patientId == null || _patientId!.isEmpty) {
      setState(() => _error = 'Pilih pasien terlebih dahulu.');
      return;
    }
    final items = <BackendEPrescriptionItem>[];
    for (final d in _items) {
      if (d.name.trim().isEmpty) {
        setState(() => _error = 'Nama obat tidak boleh kosong.');
        return;
      }
      items.add(BackendEPrescriptionItem(
        name: d.name.trim(),
        dosage: d.dosage.trim(),
        frequency: d.frequency,
        days: d.days,
        unitsPerDay: d.unitsPerDay,
      ));
    }
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      await apiClient.createEPrescription(
        accessToken: accessToken,
        patientId: _patientId!,
        instructions: _instructions.text.trim(),
        notes: _notes.text.trim(),
        items: items,
      );
      widget.onCreated?.call();
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Resep diterbitkan dengan QR verifikasi.'),
          backgroundColor: MalvaColors.mint,
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
}

class _ItemEditor extends StatefulWidget {
  const _ItemEditor({
    required this.index,
    required this.draft,
    required this.canRemove,
    required this.onRemove,
    required this.onChanged,
  });

  final int index;
  final _ItemDraft draft;
  final bool canRemove;
  final VoidCallback onRemove;
  final VoidCallback onChanged;

  @override
  State<_ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<_ItemEditor> {
  late final TextEditingController _name;
  late final TextEditingController _dosage;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.draft.name);
    _dosage = TextEditingController(text: widget.draft.dosage);
  }

  @override
  void dispose() {
    widget.draft.name = _name.text;
    widget.draft.dosage = _dosage.text;
    _name.dispose();
    _dosage.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Obat ${widget.index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              const Spacer(),
              if (widget.canRemove)
                IconButton(
                  tooltip: 'Hapus item',
                  onPressed: widget.onRemove,
                  icon: const Icon(Icons.delete_outline_rounded,
                      color: MalvaColors.danger),
                ),
            ],
          ),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'Nama obat'),
            onChanged: (_) => widget.onChanged(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _dosage,
                  decoration: const InputDecoration(labelText: 'Dosis'),
                  onChanged: (_) => widget.onChanged(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: widget.draft.frequency,
                  decoration: const InputDecoration(labelText: 'Frekuensi'),
                  items: [
                    for (final f in _kFrequencies)
                      DropdownMenuItem(value: f, child: Text(f)),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setState(() => widget.draft.frequency = v);
                    widget.onChanged();
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
                                    const Text(
                                      'Tunjukkan kode ini untuk verifikasi apotek.',
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.black54),
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
