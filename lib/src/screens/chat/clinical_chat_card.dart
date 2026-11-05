import 'package:flutter/material.dart';
import '../../models.dart';
import '../../theme.dart';

/// Only server-validated clinical messages use this card. File actions fetch
/// authenticated bytes; no public URL is embedded in the message.
class ClinicalChatCard extends StatelessWidget {
  const ClinicalChatCard(
      {super.key,
      required this.message,
      required this.isPatient,
      this.onAction});
  final ChatMessage message;
  final bool isPatient;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final meta = message.metadata ?? const <String, dynamic>{};
    final summary = message.kind == 'session_summary';
    final assessment = message.kind == 'assessment_request';
    final attachment = message.kind == 'attachment';
    final rawGoals = meta['goals'];
    final goals = (rawGoals is List ? rawGoals : const []).whereType<Map>();
    final rawGoalIds = meta['goal_ids'];
    final goalIds = rawGoalIds is List ? rawGoalIds : const [];
    final module = meta['module_id']?.toString() ?? '';
    final assessmentLabel = switch (module) {
      'screening' => 'PHQ-9 & GAD-7',
      'dass21' => 'DASS-21',
      'who5' => 'WHO-5',
      _ => 'Assessment',
    };
    final insight = meta['insight']?.toString() ?? '';
    final filename = meta['filename']?.toString() ?? 'Lampiran';
    final title = attachment
        ? filename
        : assessment
            ? assessmentLabel
            : summary
                ? 'Rangkuman sesi'
                : 'Goals & Habits';
    final action = attachment
        ? 'Buka lampiran'
        : assessment
            ? 'Isi assessment'
            : 'Lihat Goals';
    final canOpen =
        attachment || (isPatient && (assessment || goalIds.isNotEmpty));
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: MalvaColors.seed.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(16)),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              Icon(
                  attachment
                      ? Icons.attach_file
                      : assessment
                          ? Icons.fact_check_outlined
                          : Icons.summarize_outlined,
                  color: MalvaColors.seed),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, color: MalvaColors.ink)))
            ]),
            if (summary || goalIds.isNotEmpty) ...[
              const SizedBox(height: 10),
              if (goals.isEmpty && goalIds.isNotEmpty)
                Text('${goalIds.length} homework goals tersimpan'),
              for (final goal in goals)
                Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.check_circle_outline,
                              size: 18, color: MalvaColors.seed),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                Text(goal['title']?.toString() ?? 'Goal'),
                                Text(
                                    '${goal['target_per_week'] ?? 3} kali per minggu',
                                    style:
                                        Theme.of(context).textTheme.bodySmall)
                              ])),
                        ])),
              if (insight.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Insight',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(insight)
              ],
            ],
            if (assessment)
              const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Text(
                      'Isi sendiri untuk mencatat kondisi terkini. Hasil tersimpan di Assessment Record.')),
            if (attachment)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      '${meta['mime'] ?? ''} · ${((meta['size'] is num ? meta['size'] as num : 0) / 1024).ceil()} KB')),
            if (canOpen)
              TextButton.icon(
                  onPressed: onAction,
                  icon: Icon(
                      attachment ? Icons.download_outlined : Icons.open_in_new,
                      size: 18),
                  label: Text(action)),
          ]),
    );
  }
}
