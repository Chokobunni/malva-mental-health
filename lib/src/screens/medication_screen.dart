import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/malva_api_client.dart';
import '../services/medication_reminder_service.dart';
import '../store/malva_store.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';

class MedicationScreen extends StatelessWidget {
  const MedicationScreen({
    super.key,
    required this.store,
    this.session,
    this.apiClient,
    this.medicationReminderService,
  });

  final MalvaStore store;
  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final MedicationReminderService? medicationReminderService;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        return Scaffold(
          floatingActionButton: FloatingActionButton(
            heroTag: 'medication_add_fab',
            onPressed: () => _openMedicationForm(context),
            child: const Icon(Icons.add_rounded),
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              final accessToken = session?.accessToken;
              if (apiClient == null || accessToken == null || accessToken.isEmpty) {
                await Future<void>.delayed(const Duration(milliseconds: 500));
                return;
              }
              try {
                final backendMeds = await apiClient!.listMedications(
                  accessToken: accessToken,
                );
                final meds = backendMeds
                    .map(
                      (b) => Medication(
                        id: b.id,
                        name: b.name,
                        dosage: b.dosage,
                        form: b.form,
                        reminders: [
                          MedicationReminder(
                            time: _parseReminderTime(b.reminderTime),
                            relationToMeal: 'Setelah makan',
                          ),
                        ],
                        currentStock: b.currentStock,
                        alertBelow: b.alertBelow,
                        source: 'Profesional',
                      ),
                    )
                    .toList();
                store.replaceMedications(meds);
              } on Object catch (_) {
                await Future<void>.delayed(const Duration(milliseconds: 500));
              }
            },
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
              const GradientHeader(
                title: 'Medication',
                subtitle: 'Reminder, stok, dan adherence',
                leading: Icon(Icons.medication_rounded,
                    color: Colors.white, size: 34),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SoftCard(
                      color: MalvaColors.plum,
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Weekly Adherence',
                                  style: TextStyle(
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w800),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  '${store.adherencePercent}% hari ini',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                                const SizedBox(height: 6),
                                const Text('Tap Take Now setelah obat diminum.',
                                    style: TextStyle(color: Colors.white70)),
                              ],
                            ),
                          ),
                          CircleAvatar(
                            radius: 34,
                            backgroundColor: Colors.white,
                            child: Text(
                              '${store.adherencePercent}%',
                              style: const TextStyle(
                                  color: MalvaColors.plum,
                                  fontWeight: FontWeight.w900),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    const SectionLabel('Jadwal hari ini'),
                    if (store.medications.isEmpty)
                      SoftCard(
                        child: Column(
                          children: [
                            const Icon(Icons.medication_rounded,
                                size: 48, color: MalvaColors.seed),
                            const SizedBox(height: 12),
                            const Text(
                              'Belum ada obat',
                              style: TextStyle(fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Tambahkan obat pertama Anda untuk mulai melacak.',
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => _openMedicationForm(context),
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Tambah Obat Pertama'),
                            ),
                          ],
                        ),
                      )
                    else
                      for (final med in store.medications) ...[
                        _MedicationCard(
                          medication: med,
                          onTake: () => _takeMedication(context, med),
                          onEdit: () => _openMedicationForm(context, med),
                        ),
                        const SizedBox(height: 12),
                      ],
                    const SizedBox(height: 70),
                  ],
                ),
              ),
            ],
          ),
        ),
        );
      },
    );
  }

  void _openMedicationForm(BuildContext context, [Medication? medication]) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => MedicationFormSheet(
        initial: medication,
        onSave: (value) {
          store.upsertMedication(value);
          unawaited(_syncMedication(context, value));
          unawaited(
              medicationReminderService?.scheduleMedicationReminder(value));
          Navigator.pop(context);
        },
        onDelete: medication != null
            ? () {
                Navigator.pop(context);
                _deleteMedication(context, medication);
              }
            : null,
      ),
    );
  }

  void _deleteMedication(BuildContext context, Medication medication) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Hapus ${medication.name}?'),
        content: const Text('Obat dan reminder akan dihapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              store.deleteMedication(medication.id);
              unawaited(
                  medicationReminderService?.cancelReminder(medication.id));
            },
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  void _takeMedication(BuildContext context, Medication medication) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Log ${medication.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle_rounded, color: MalvaColors.mint),
              title: const Text('Taken'),
              subtitle: const Text('Obat sudah diminum'),
              onTap: () {
                Navigator.pop(context);
                _logMedication(context, medication, 'taken');
              },
            ),
            ListTile(
              leading: const Icon(Icons.skip_next_rounded, color: MalvaColors.amber),
              title: const Text('Skipped'),
              subtitle: const Text('Dilewati dengan sengaja'),
              onTap: () {
                Navigator.pop(context);
                _logMedication(context, medication, 'skipped');
              },
            ),
            ListTile(
              leading: const Icon(Icons.cancel_rounded, color: MalvaColors.danger),
              title: const Text('Missed'),
              subtitle: const Text('Terlewat tanpa sengaja'),
              onTap: () {
                Navigator.pop(context);
                _logMedication(context, medication, 'missed');
              },
            ),
            ListTile(
              leading: const Icon(Icons.hourglass_bottom_rounded, color: MalvaColors.orchid),
              title: const Text('Partial'),
              subtitle: const Text('Sebagian diminum'),
              onTap: () {
                Navigator.pop(context);
                _logMedication(context, medication, 'partial');
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
        ],
      ),
    );
  }

  void _logMedication(BuildContext context, Medication medication, String status) {
    store.takeMedication(medication.id);
    unawaited(_syncMedicationLog(context, medication, status));
  }

  Future<void> _syncMedication(
    BuildContext context,
    Medication medication,
  ) async {
    final accessToken = session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      return;
    }
    try {
      final reminder = medication.reminders.first;
      await apiClient!.createMedication(
        accessToken: accessToken,
        name: medication.name,
        dosage: medication.dosage,
        form: medication.form,
        reminderTime: reminder.label,
        relationToMeal: reminder.relationToMeal,
        currentStock: medication.currentStock,
        alertBelow: medication.alertBelow,
        source: medication.source,
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Obat tersimpan lokal, sync backend gagal: $error'),
        ),
      );
    }
  }

  Future<void> _syncMedicationLog(
    BuildContext context,
    Medication medication,
    String status,
  ) async {
    final accessToken = session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      return;
    }
    try {
      await apiClient!.createMedicationLog(
        accessToken: accessToken,
        medicationName: medication.name,
        status: status,
        takenAt: DateTime.now(),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Log obat tersimpan lokal, sync backend gagal: $error'),
        ),
      );
    }
  }
}

TimeOfDay _parseReminderTime(String reminderTime) {
  final parts = reminderTime.split(':');
  return TimeOfDay(
    hour: int.tryParse(parts[0]) ?? 8,
    minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
  );
}

class _MedicationCard extends StatelessWidget {
  const _MedicationCard({
    required this.medication,
    required this.onTake,
    required this.onEdit,
  });

  final Medication medication;
  final VoidCallback onTake;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final firstReminder = medication.reminders.first;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: medication.needsRefill
                    ? MalvaColors.danger.withValues(alpha: 0.1)
                    : MalvaColors.mint.withValues(alpha: 0.1),
                child: Icon(
                  medication.needsRefill
                      ? Icons.priority_high_rounded
                      : Icons.medication_liquid_rounded,
                  color: medication.needsRefill
                      ? MalvaColors.danger
                      : MalvaColors.mint,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(medication.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16)),
                    Text(
                        '${medication.dosage} - ${medication.form} - ${firstReminder.relationToMeal}'),
                  ],
                ),
              ),
              IconButton(
                  onPressed: onEdit, icon: const Icon(Icons.edit_rounded)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                label: firstReminder.label,
                color: MalvaColors.seed,
                icon: Icons.schedule_rounded,
              ),
              StatusPill(
                label: '${medication.currentStock} stok',
                color: medication.needsRefill
                    ? MalvaColors.danger
                    : MalvaColors.mint,
                icon: Icons.inventory_2_rounded,
              ),
              StatusPill(
                label: medication.source,
                color: MalvaColors.amber,
                icon: Icons.verified_user_rounded,
              ),
            ],
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed: onTake,
            icon: const Icon(Icons.check_rounded),
            label: const Text('Take Now'),
          ),
        ],
      ),
    );
  }
}

class MedicationFormSheet extends StatefulWidget {
  const MedicationFormSheet({
    super.key,
    required this.onSave,
    this.initial,
    this.onDelete,
  });

  final Medication? initial;
  final ValueChanged<Medication> onSave;
  final VoidCallback? onDelete;

  @override
  State<MedicationFormSheet> createState() => _MedicationFormSheetState();
}

class _MedicationFormSheetState extends State<MedicationFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _dosage;
  late final TextEditingController _form;
  late final TextEditingController _stock;
  late final TextEditingController _alertBelow;
  late TimeOfDay _time;
  String _relation = 'Setelah makan';

  @override
  void initState() {
    super.initState();
    final med = widget.initial;
    _name = TextEditingController(text: med?.name ?? '');
    _dosage = TextEditingController(text: med?.dosage ?? '');
    _form = TextEditingController(text: med?.form ?? 'Tablet');
    _stock = TextEditingController(text: (med?.currentStock ?? 30).toString());
    _alertBelow =
        TextEditingController(text: (med?.alertBelow ?? 5).toString());
    _time = med?.reminders.first.time ?? const TimeOfDay(hour: 8, minute: 0);
    _relation = med?.reminders.first.relationToMeal ?? 'Setelah makan';
  }

  @override
  void dispose() {
    _name.dispose();
    _dosage.dispose();
    _form.dispose();
    _stock.dispose();
    _alertBelow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, bottomInset + 18),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initial == null ? 'Tambah Medication' : 'Edit Medication',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nama obat')),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                    child: TextField(
                        controller: _dosage,
                        decoration:
                            const InputDecoration(labelText: 'Dosage'))),
                const SizedBox(width: 10),
                Expanded(
                    child: TextField(
                        controller: _form,
                        decoration: const InputDecoration(labelText: 'Form'))),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule_rounded),
              label: Text(
                  'Reminder ${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _relation,
              decoration: const InputDecoration(labelText: 'Relasi makan'),
              items: const [
                DropdownMenuItem(
                    value: 'Sebelum makan', child: Text('Sebelum makan')),
                DropdownMenuItem(
                    value: 'Setelah makan', child: Text('Setelah makan')),
                DropdownMenuItem(
                    value: 'Sebelum tidur', child: Text('Sebelum tidur')),
              ],
              onChanged: (value) =>
                  setState(() => _relation = value ?? _relation),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _stock,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Current stock'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _alertBelow,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Alert below'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('Simpan')),
            if (widget.onDelete != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: widget.onDelete,
                icon: const Icon(Icons.delete_rounded, color: MalvaColors.danger),
                label: const Text('Hapus Obat',
                    style: TextStyle(color: MalvaColors.danger)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  void _save() {
    final id =
        widget.initial?.id ?? 'med_${DateTime.now().millisecondsSinceEpoch}';
    widget.onSave(
      Medication(
        id: id,
        name: _name.text.trim().isEmpty ? 'Medication' : _name.text.trim(),
        dosage: _dosage.text.trim().isEmpty ? '0 mg' : _dosage.text.trim(),
        form: _form.text.trim().isEmpty ? 'Tablet' : _form.text.trim(),
        reminders: [
          MedicationReminder(time: _time, relationToMeal: _relation),
        ],
        currentStock: int.tryParse(_stock.text.trim()) ?? 0,
        alertBelow: int.tryParse(_alertBelow.text.trim()) ?? 5,
        source: widget.initial?.source ?? 'Pasien',
      ),
    );
  }
}
