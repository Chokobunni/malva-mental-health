import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';

class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key, this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen> {
  String? _selectedFileName;
  String _searchQuery = '';
  String _typeFilter = 'All';

  BackendHealthRecord? _healthRecord;
  List<BackendMedication> _medications = const [];
  bool _isLoading = true;
  String? _loadError;

  List<String> get _typeOptions =>
      const ['All', 'PDF', 'IMAGE', 'DOC', 'OTHER'];

  @override
  void initState() {
    super.initState();
    _loadFromServer();
  }

  Future<void> _loadFromServer() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    try {
      final results = await Future.wait([
        apiClient.getHealthRecord(accessToken: accessToken),
        apiClient.listMedications(accessToken: accessToken),
      ]);
      if (!mounted) return;
      final record = results[0] as BackendHealthRecord;
      final meds = (results[1] as List<BackendMedication>)
          .where((m) => m.source.toLowerCase() != 'pasien')
          .toList(growable: false);
      setState(() {
        _healthRecord = record;
        _medications = meds;
        _isLoading = false;
      });
      ref
          .read(malvaStoreProvider.notifier)
          .setPatientDiagnosis(record.diagnosisSummary);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _loadError = e is MalvaApiException ? e.message : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeState = ref.watch(malvaStoreProvider);
    final records = storeState.records.where((r) {
      final matchesType =
          _typeFilter == 'All' || r.type.toUpperCase() == _typeFilter;
      final matchesQuery = _searchQuery.isEmpty ||
          r.title.toLowerCase().contains(_searchQuery.toLowerCase());
      return matchesType && matchesQuery;
    }).toList();
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadFromServer,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            GradientHeader(
              title: 'Health Record',
              subtitle: 'Data klinis terkunci dan audit-ready',
              leading: IconButton(
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Diagnosis'),
                  if (_isLoading)
                    const SoftCard(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    )
                  else if (_healthRecord?.hasDiagnosis == true)
                    _DiagnosisCard(
                      diagnosis: _healthRecord!.diagnosisSummary,
                      professional: _healthRecord!.primaryProfessional,
                      updatedAt: _healthRecord!.updatedAt,
                    )
                  else
                    const _NoDiagnosisCard(),
                  if (_loadError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _loadError!,
                      style: const TextStyle(
                          color: MalvaColors.danger,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                  const SizedBox(height: 22),
                  const SectionLabel('Medication'),
                  if (_isLoading)
                    const SizedBox.shrink()
                  else if (_medications.isEmpty)
                    const SoftCard(
                      child: Column(
                        children: [
                          Icon(Icons.medication_outlined,
                              size: 42, color: MalvaColors.seed),
                          SizedBox(height: 10),
                          Text(
                            'Belum ada obat',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Obat hanya dapat ditambahkan oleh profesional '
                            'setelah sesi konsultasi & diagnosis.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    for (final med in _medications) ...[
                      _MedicationCard(med: med),
                      const SizedBox(height: 12),
                    ],
                  const SizedBox(height: 22),
                  SectionLabel(
                    'Record',
                    action: OutlinedButton.icon(
                      onPressed: () => _showAddRecordDialog(context),
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('Add File'),
                    ),
                  ),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search',
                      hintText: 'Cari dokumen...',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (v) => setState(() => _searchQuery = v),
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final option in _typeOptions)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(option),
                              selected: _typeFilter == option,
                              onSelected: (_) =>
                                  setState(() => _typeFilter = option),
                              selectedColor:
                                  MalvaColors.seed.withValues(alpha: 0.15),
                              checkmarkColor: MalvaColors.seed,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (records.isEmpty)
                    SoftCard(
                      child: Column(
                        children: [
                          const Icon(Icons.folder_open_rounded,
                              size: 48, color: MalvaColors.seed),
                          const SizedBox(height: 12),
                          Text(
                            storeState.records.isEmpty
                                ? 'Belum ada record'
                                : 'Tidak ada dokumen yang cocok',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Upload dokumen, hasil tes, atau riwayat kesehatan Anda.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    for (final record in records) ...[
                      SoftCard(
                        child: Row(
                          children: [
                            CircleAvatar(
                              child: Icon(_getRecordIcon(record.type)),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(record.title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900)),
                                  Text(
                                      '${record.type} - ${record.date.day}/${record.date.month}/${record.date.year}'),
                                ],
                              ),
                            ),
                            if (record.lockedByProfessional)
                              const Icon(Icons.lock_rounded,
                                  color: Colors.black45),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getRecordIcon(String type) {
    switch (type.toUpperCase()) {
      case 'PDF':
        return Icons.picture_as_pdf_rounded;
      case 'IMAGE':
      case 'JPG':
      case 'PNG':
        return Icons.image_rounded;
      case 'DOC':
      case 'DOCX':
        return Icons.description_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  void _showAddRecordDialog(BuildContext context) {
    final titleController = TextEditingController();
    String selectedType = 'PDF';

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tambah Record'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Nama file',
                    hintText: 'contoh: Hasil_Tes_MMPI',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Tipe file:',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['PDF', 'IMAGE', 'DOC', 'OTHER'].map((type) {
                    return ChoiceChip(
                      label: Text(type),
                      selected: selectedType == type,
                      onSelected: (_) =>
                          setDialogState(() => selectedType = type),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles();
                    if (result != null && result.files.isNotEmpty) {
                      _selectedFileName = result.files.single.name;
                      setDialogState(() {});
                    }
                  },
                  icon: const Icon(Icons.attach_file_rounded),
                  label: Text(_selectedFileName ?? 'Pilih File'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isEmpty) return;
                ref.read(malvaStoreProvider.notifier).addRecord(
                      HealthRecord(
                        id: 'record_${DateTime.now().millisecondsSinceEpoch}',
                        date: DateTime.now(),
                        title: title,
                        type: selectedType,
                        lockedByProfessional: false,
                      ),
                    );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Record "${title}" berhasil ditambahkan.'),
                  ),
                );
              },
              style: compactFilledButtonStyle,
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kartu diagnosis dari profesional (read-only untuk pasien).
class _DiagnosisCard extends StatelessWidget {
  const _DiagnosisCard({
    required this.diagnosis,
    required this.professional,
    this.updatedAt,
  });

  final String diagnosis;
  final String professional;
  final DateTime? updatedAt;

  @override
  Widget build(BuildContext context) {
    final updated = updatedAt;
    return SoftCard(
      color: MalvaColors.plum,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Diagnosis',
            style: TextStyle(
              color: Colors.white70,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            diagnosis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: Colors.white,
                ),
          ),
          if (professional.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Oleh: $professional',
              style: const TextStyle(
                  color: Colors.white70, fontWeight: FontWeight.w700),
            ),
          ],
          if (updated != null) ...[
            const SizedBox(height: 2),
            Text(
              'Diperbarui: ${updated.day}/${updated.month}/${updated.year}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.lock_rounded, size: 18, color: Colors.white70),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Only your doctor can edit — pasien read-only.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.white70),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Empty state diagnosis: belum ada diagnosis profesional.
class _NoDiagnosisCard extends StatelessWidget {
  const _NoDiagnosisCard();

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: MalvaColors.amber.withValues(alpha: 0.10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.medical_information_outlined,
                  color: MalvaColors.amber),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Belum ada diagnosis',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Diagnosis hanya dapat diberikan oleh psikolog/psikiater '
            'terverifikasi setelah sesi konsultasi (meeting). Silakan booking '
            'dan ikuti sesi dengan profesional terlebih dahulu.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.lock_rounded, size: 18, color: Colors.black45),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pasien read-only — data ini terisi otomatis setelah '
                  'profesional menyimpan diagnosis.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.black54),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Kartu obat dari server (resep profesional).
class _MedicationCard extends StatelessWidget {
  const _MedicationCard({required this.med});

  final BackendMedication med;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Row(
        children: [
          Container(
            width: 7,
            height: 58,
            decoration: BoxDecoration(
              color: med.needsRefill ? MalvaColors.danger : MalvaColors.mint,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${med.name} ${med.dosage}',
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                Text(med.reminderTime.isEmpty
                    ? med.form
                    : '${med.reminderTime} • ${med.form}'),
                Text(
                  med.source.isEmpty
                      ? 'Source: Profesional'
                      : 'Source: ${med.source}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          StatusPill(
            label: '${med.currentStock} left',
            color: med.needsRefill ? MalvaColors.danger : MalvaColors.seed,
          ),
        ],
      ),
    );
  }
}
