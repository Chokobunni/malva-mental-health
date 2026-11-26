import 'dart:convert';

import 'package:flutter/material.dart';

import '../services/client_intent_id.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../time/wib.dart';
import 'clinical_profile_cards.dart';
import 'friendly_error.dart';
import 'malva_components.dart';

const _reactionTypes = {
  'allergy': 'Alergi Obat',
  'side_effect': 'Efek Samping'
};
const _severities = {
  'mild': 'Ringan',
  'moderate': 'Sedang',
  'high': 'Risiko Tinggi'
};

class ClinicalAllergySection extends StatefulWidget {
  const ClinicalAllergySection({
    super.key,
    required this.records,
    this.onAdd,
    this.onEdit,
    this.onDelete,
    this.status,
    this.prescribing = false,
  });

  final List<BackendHealthRecordAllergy> records;
  final VoidCallback? onAdd;
  final ValueChanged<BackendHealthRecordAllergy>? onEdit;
  final ValueChanged<BackendHealthRecordAllergy>? onDelete;
  final Widget? status;
  final bool prescribing;

  @override
  State<ClinicalAllergySection> createState() => _ClinicalAllergySectionState();
}

class _ClinicalAllergySectionState extends State<ClinicalAllergySection> {
  String _filter = '';

  @override
  Widget build(BuildContext context) {
    final records = widget.records;
    final visible = records
        .where((record) => _filter.isEmpty || record.reactionType == _filter);
    return ClinicalProfileSection(
      title: 'Alergi & Reaksi Obat',
      art: 'allergy',
      action: widget.onAdd == null
          ? null
          : TextButton.icon(
              onPressed: widget.onAdd,
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Tambah'),
            ),
      children: [
        if (widget.status case final status?)
          status
        else ...[
          if (widget.prescribing && records.isNotEmpty)
            const Align(
              alignment: Alignment.centerLeft,
              child: StatusPill(
                  label: 'Perhatikan sebelum meresepkan',
                  color: MalvaColors.danger),
            ),
          Wrap(
            spacing: 6,
            runSpacing: 2,
            children: [
              for (final option in {'': 'Semua', ..._reactionTypes}.entries)
                ChoiceChip(
                  label: Text(
                      '${option.value} (${records.where((r) => option.key.isEmpty || r.reactionType == option.key).length})'),
                  labelStyle: TextStyle(
                    fontSize: 12,
                    color: _filter == option.key ? Colors.white : null,
                    fontWeight: FontWeight.w600,
                  ),
                  backgroundColor: Colors.white,
                  selectedColor: MalvaColors.plum,
                  shape: const StadiumBorder(),
                  side: const BorderSide(color: Color(0xFFEDE8F1)),
                  selected: _filter == option.key,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _filter = option.key),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (visible.isEmpty)
            SoftCard(
                child: Text(records.isEmpty
                    ? 'Tidak ada riwayat alergi obat tercatat.'
                    : 'Tidak ada catatan untuk jenis ini.')),
          for (final record in visible) ...[
            _AllergyCard(
              record,
              onEdit: record.reportedBy == 'patient' && widget.onEdit != null
                  ? () => widget.onEdit!(record)
                  : null,
              onDelete:
                  record.reportedBy == 'patient' && widget.onDelete != null
                      ? () => widget.onDelete!(record)
                      : null,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

class _AllergyCard extends StatelessWidget {
  const _AllergyCard(this.record, {this.onEdit, this.onDelete});
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  final BackendHealthRecordAllergy record;

  @override
  Widget build(BuildContext context) {
    final tone = switch (record.severity) {
      'high' => MalvaColors.danger,
      'moderate' => const Color(0xFF93601A),
      _ => const Color(0xFF06789D),
    };
    final author = switch (record.reportedBy) {
      'professional' => 'Tercatat oleh Profesional',
      'patient' => 'Laporan Pasien',
      _ => '',
    };
    final occurrence = record.occurredWhen.isNotEmpty
        ? record.occurredWhen
        : record.createdAt == null
            ? ''
            : formatWibDate(record.createdAt!);
    return SoftCard(
      color: Colors.white,
      accent: tone,
      outline: BorderSide(color: tone.withValues(alpha: 0.18)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClinicalProfileArt(switch (record.severity) {
            'high' => 'high',
            'moderate' => 'moderate',
            _ => 'mild',
          }),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    StatusPill(
                        label: (_reactionTypes[record.reactionType] ??
                                record.reactionType)
                            .toUpperCase(),
                        color: tone),
                    StatusPill(
                        label: _severities[record.severity] ?? record.severity,
                        color: tone),
                  ],
                ),
                const SizedBox(height: 6),
                if (onEdit != null || onDelete != null)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (onEdit != null)
                        IconButton(
                            tooltip: 'Edit alergi',
                            onPressed: onEdit,
                            icon: const Icon(Icons.edit_outlined, size: 18)),
                      if (onDelete != null)
                        IconButton(
                            tooltip: 'Hapus alergi',
                            onPressed: onDelete,
                            icon: const Icon(Icons.delete_outline, size: 18)),
                    ],
                  ),
                Text(record.substance,
                    style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 15)),
                const SizedBox(height: 4),
                Text('Reaksi: ${record.symptoms}'),
                if (author.isNotEmpty || occurrence.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    [author, occurrence].where((v) => v.isNotEmpty).join(' • '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

typedef AllergySave = Future<BackendHealthRecordAllergy> Function(
    String clientId,
    String reaction,
    String substance,
    String symptoms,
    String severity);

class AddClinicalAllergySheet extends StatefulWidget {
  const AddClinicalAllergySheet(
      {super.key, required this.onSave, this.initial});
  final BackendHealthRecordAllergy? initial;

  final AllergySave onSave;

  @override
  State<AddClinicalAllergySheet> createState() =>
      _AddClinicalAllergySheetState();
}

class _AddClinicalAllergySheetState extends State<AddClinicalAllergySheet> {
  final _form = GlobalKey<FormState>();
  late final _substance =
      TextEditingController(text: widget.initial?.substance);
  late final _symptoms = TextEditingController(text: widget.initial?.symptoms);
  late String _reaction = widget.initial?.reactionType ?? 'allergy';
  late String _severity = widget.initial?.severity ?? 'moderate';
  String? _clientId;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _substance.dispose();
    _symptoms.dispose();

    super.dispose();
  }

  String? _validate(String? value, int limit) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Wajib diisi.';
    return utf8.encode(text).length > limit ? 'Isian terlalu panjang.' : null;
  }

  void _edit() {
    _clientId = null;
    if (_error != null) setState(() => _error = null);
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final record = await widget.onSave(_clientId ??= newClientIntentId(),
          _reaction, _substance.text.trim(), _symptoms.text.trim(), _severity);
      if (mounted) Navigator.pop(context, record);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = friendlyErrorMessage(error);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
        canPop: !_saving,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
            child: Form(
              key: _form,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const ClinicalIconTile(
                          icon: Icons.health_and_safety_outlined,
                          color: MalvaColors.danger),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                            widget.initial == null
                                ? 'Tambah Alergi & Reaksi Obat'
                                : 'Edit Alergi & Reaksi Obat',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w900)),
                      ),
                      IconButton(
                        tooltip: 'Tutup',
                        onPressed:
                            _saving ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text('Membantu profesional memilih terapi yang aman'),
                  const SizedBox(height: 16),
                  const Text('Jenis Reaksi',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final option in _reactionTypes.entries)
                        ChoiceChip(
                          label: Text(option.value),
                          selected: _reaction == option.key,
                          onSelected: _saving
                              ? null
                              : (_) => setState(() {
                                    _reaction = option.key;
                                    _edit();
                                  }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _substance,
                    enabled: !_saving,
                    onChanged: (_) => _edit(),
                    decoration: const InputDecoration(
                      labelText: 'Nama Obat atau Zat Pemicu *',
                      hintText: 'Contoh: Ibuprofen',
                      prefixIcon: Icon(Icons.medication_outlined),
                    ),
                    validator: (value) => _validate(value, 240),
                  ),
                  const SizedBox(height: 14),
                  const Text('Gejala yang Muncul *',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final symptom in const [
                        'Ruam / Gatal',
                        'Kaku Otot / Tremor',
                        'Sesak / Bengkak',
                        'Mual / Pusing',
                      ])
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 16),
                          label: Text(symptom),
                          onPressed: _saving
                              ? null
                              : () {
                                  final current = _symptoms.text.trim();
                                  if (current.split(', ').contains(symptom))
                                    return;
                                  final text = current.isEmpty
                                      ? symptom
                                      : '$current, $symptom';
                                  _symptoms.value = TextEditingValue(
                                      text: text,
                                      selection: TextSelection.collapsed(
                                          offset: text.length));
                                  _edit();
                                },
                        ),
                    ],
                  ),
                  TextFormField(
                    controller: _symptoms,
                    enabled: !_saving,
                    onChanged: (_) => _edit(),
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                        hintText: 'Jelaskan reaksi yang dirasakan'),
                    validator: (value) => _validate(value, 2000),
                  ),
                  const SizedBox(height: 14),
                  const Text('Tingkat Keparahan',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final option in _severities.entries)
                        ChoiceChip(
                          label: Text(
                              option.key == 'high' ? 'Tinggi' : option.value),
                          selected: _severity == option.key,
                          onSelected: _saving
                              ? null
                              : (_) => setState(() {
                                    _severity = option.key;
                                    _edit();
                                  }),
                        ),
                    ],
                  ),
                  if (_error case final error?) ...[
                    const SizedBox(height: 8),
                    Text(error,
                        style: const TextStyle(color: MalvaColors.danger)),
                  ],
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed:
                              _saving ? null : () => Navigator.pop(context),
                          child: const Text('Batal'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : _save,
                          style: FilledButton.styleFrom(
                            textStyle: const TextStyle(
                              fontFamily: 'Roboto',
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          child:
                              Text(_saving ? 'Menyimpan…' : 'Simpan Catatan'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
