import 'package:flutter/material.dart';

import '../models.dart';
import '../services/malva_api_client.dart';
import '../services/medication_adherence.dart';
import '../services/medication_reminder_service.dart';
import '../theme.dart';
import '../time/wib.dart';
import 'malva_components.dart';

class ClinicalProfileSection extends StatelessWidget {
  const ClinicalProfileSection({
    super.key,
    required this.title,
    required this.children,
    this.art,
    this.icon,
    this.action,
    this.subtitle,
  });

  final String title;
  final List<Widget> children;
  final String? art;
  final IconData? icon;
  final Widget? action;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => SoftCard(
        radius: 22,
        color: Colors.white,
        outline: const BorderSide(color: Color(0xFFF0EBF3)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (art case final asset?)
                  ClinicalProfileArt(asset)
                else if (icon case final glyph?)
                  ClinicalIconTile(icon: glyph, color: MalvaColors.seed),
                if (art != null || icon != null) const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w800)),
                      if (subtitle != null)
                        Text(subtitle!,
                            style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                if (action != null) ...[const SizedBox(width: 6), action!],
              ],
            ),
            if (children.isNotEmpty) const SizedBox(height: 12),
            ...children,
          ],
        ),
      );
}

class ClinicalProfileArt extends StatelessWidget {
  const ClinicalProfileArt(this.asset, {super.key, this.size = 36});

  final String asset;
  final double size;

  @override
  Widget build(BuildContext context) => Image.asset(
        'assets/care/clinical_$asset.png',
        width: size,
        height: size,
        excludeFromSemantics: true,
      );
}

class ClinicalSectionMessage extends StatelessWidget {
  const ClinicalSectionMessage({
    super.key,
    required this.message,
    required this.icon,
    this.title,
    this.positive = false,
  });

  final String message;
  final IconData icon;
  final String? title;
  final bool positive;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          color: positive ? const Color(0xFFEDFAF4) : const Color(0xFFF7F8FA),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFEBEDF2)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon,
                  color: positive ? const Color(0xFF147C52) : MalvaColors.plum,
                  size: 20),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (title != null)
                    Text(title!,
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(message),
                ],
              )),
            ],
          ),
        ),
      );
}

class ClinicalDiagnosisCard extends StatelessWidget {
  const ClinicalDiagnosisCard({super.key, required this.record, this.onEdit});

  final BackendHealthRecord record;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final lines = record.diagnosisSummary
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    final pattern = RegExp(r'^[A-Z]\d{2}(?:\.\d+)?\b');
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF692C8D), Color(0xFF481B65)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final line in lines)
                if (pattern.firstMatch(line) case final code?)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      child: Text('ICD-10 • ${code.group(0)}',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800)),
                    ),
                  ),
              if (record.updatedAt case final updated?)
                Text('Diperbarui: ${formatWibDateShort(updated)}',
                    style:
                        const TextStyle(color: Colors.white70, fontSize: 12)),
            ],
          ),
          for (final (index, line) in lines.indexed) ...[
            const SizedBox(height: 12),
            if (lines.length > 1 && pattern.hasMatch(line))
              Text(index == 0 ? 'PRIMARY' : 'SECONDARY',
                  style: const TextStyle(
                      color: Colors.white70,
                      fontWeight: FontWeight.w800,
                      fontSize: 11)),
            Text(line,
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16)),
          ],
          if (record.authorName.isNotEmpty || onEdit != null) ...[
            const Divider(color: Colors.white24, height: 26),
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 6,
              children: [
                if (record.authorName.isNotEmpty)
                  Text(record.authorName,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                if (onEdit != null)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: MalvaColors.plum,
                      minimumSize: const Size(0, 42),
                      textStyle: const TextStyle(
                          fontFamily: 'Roboto', fontWeight: FontWeight.w700),
                    ),
                    onPressed: onEdit,
                    child: const Text('Kelola ICD-10'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class ClinicalMedicationCard extends StatelessWidget {
  const ClinicalMedicationCard({super.key, required this.med});

  final BackendMedication med;

  @override
  Widget build(BuildContext context) {
    final schedule = med.schedule;
    final source = sharedMedicationSourceLabel(med.source);
    final label = switch (source) {
      'Profesional' => 'Resep Profesional',
      'Pasien' => 'Input Pasien',
      _ => '',
    };
    final time = switch (schedule) {
      final s? when s.intervalHours > 0 => 'Setiap ${s.intervalHours} jam',
      final s? when s.intervalDays > 1 =>
        'Setiap ${s.intervalDays} hari • ${s.times.join(', ')}',
      final s? when s.intervalMonths > 0 =>
        'Setiap ${s.intervalMonths} bulan • ${s.times.join(', ')}',
      final s? when s.times.isNotEmpty => [
          s.times.join(', '),
          if (s.weekdays.isNotEmpty && s.weekdays.length < 7)
            s.weekdays
                .where((day) => day >= 1 && day <= 7)
                .map((day) => const [
                      'Sen',
                      'Sel',
                      'Rab',
                      'Kam',
                      'Jum',
                      'Sab',
                      'Min'
                    ][day - 1])
                .join(', '),
        ].join(' • '),
      _ => med.reminderTime,
    };
    final details = [
      time,
      med.form,
      if (med.relationToMeal.isNotEmpty) med.relationToMeal,
    ].where((part) => part.isNotEmpty).join(' • ');
    final instructions = schedule?.instructions.trim() ?? '';
    final now = wibNow();
    final dailyDoses = schedule == null
        ? (med.reminderTime.isEmpty ? 0 : 1)
        : MedicationReminderService.routineOccurrences(
            schedule,
            now: now,
            until: now.add(const Duration(days: 1)),
          ).length;
    final dosesPerDay = dailyDoses * (schedule?.unitsPerDose ?? 1);
    final isDaily = schedule == null ||
        (schedule.intervalMonths == 0 &&
            schedule.intervalDays <= 1 &&
            schedule.weekdays.length == 7);
    final days =
        isDaily && dosesPerDay > 0 ? med.currentStock ~/ dosesPerDay : null;
    final tone = source == 'Pasien' ? MalvaColors.mint : MalvaColors.seed;
    return SoftCard(
      color: Colors.white,
      outline: const BorderSide(color: Color(0xFFEDE8F1)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClinicalIconTile(icon: Icons.medication_outlined, color: tone),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    [med.name, med.dosage]
                        .where((value) => value.isNotEmpty)
                        .join(' '),
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                if (details.isNotEmpty) Text(details),
                if (instructions.isNotEmpty) Text(instructions),
                if (label.isNotEmpty) ...[
                  const SizedBox(height: 5),
                  StatusPill(
                      label: label, color: tone, icon: Icons.verified_outlined),
                ],
              ],
            ),
          ),
          const SizedBox(width: 6),
          Column(
            children: [
              StatusPill(
                  label: 'Sisa ${med.currentStock}', color: MalvaColors.seed),
              if (days != null)
                Text('± $days hari',
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
    );
  }
}

class ClinicalIconTile extends StatelessWidget {
  const ClinicalIconTile({super.key, required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color, size: 21),
      );
}

int? clinicalMedicationAdherence(
    List<BackendMedication> medications, List<BackendMedicationLog> logs) {
  final now = wibNow();
  final adherence = MedicationAdherence.calculate(
    medications: medications.map((med) => med.toMedication()).toList(),
    logs: [
      for (final log in logs)
        if ((log.takenAt ?? log.createdAt) case final timestamp?)
          MedicationLog(
            medicationId: log.medicationId,
            medicationName: log.medicationName,
            takenAt: timestamp,
            status: log.status,
          ),
    ],
    start: medicationDay(now).subtract(const Duration(days: 6)),
    end: now,
  );
  return adherence.rows.isEmpty ? null : adherence.percent;
}
