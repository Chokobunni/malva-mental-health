import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';

class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key});

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen> {
  String? _selectedFileName;
  String _searchQuery = '';
  String _typeFilter = 'All';

  List<String> get _typeOptions =>
      const ['All', 'PDF', 'IMAGE', 'DOC', 'OTHER'];

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
      body: ListView(
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
                SoftCard(
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
                        storeState.patient.diagnosisSummary,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: Colors.white),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.lock_rounded,
                              size: 18, color: Colors.white70),
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
                ),
                const SizedBox(height: 22),
                const SectionLabel('Medication'),
                for (final med in storeState.medications) ...[
                  SoftCard(
                    child: Row(
                      children: [
                        Container(
                          width: 7,
                          height: 58,
                          decoration: BoxDecoration(
                            color: med.needsRefill
                                ? MalvaColors.danger
                                : MalvaColors.mint,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${med.name} ${med.dosage}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900)),
                              Text(
                                  '${med.reminders.first.label} - ${med.reminders.first.relationToMeal}'),
                              Text('Source: ${med.source}',
                                  style: Theme.of(context).textTheme.bodySmall),
                            ],
                          ),
                        ),
                        StatusPill(
                          label: '${med.currentStock} left',
                          color: med.needsRefill
                              ? MalvaColors.danger
                              : MalvaColors.seed,
                        ),
                      ],
                    ),
                  ),
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
