import 'package:flutter/material.dart';
import '../../models.dart';
import '../../theme.dart';
import 'session_summary_chat_card.dart';

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
    if (message.kind == 'session_summary') {
      return SessionSummaryChatCard(message: message);
    }
    final meta = message.metadata ?? const <String, dynamic>{};
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
      _ => 'Asesmen',
    };
    final insight = meta['insight']?.toString() ?? '';
    final filename = meta['filename']?.toString() ?? 'Lampiran';
    if (assessment || attachment) {
      final action = attachment
          ? 'Buka lampiran'
          : isPatient
              ? 'Isi asesmen'
              : 'Lihat detail';
      final size = meta['size'];
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: const Color(0xffece5f2)),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
                color: const Color(0xfff3e8fc),
                borderRadius: BorderRadius.circular(10)),
            child: Icon(
                attachment
                    ? Icons.attach_file_rounded
                    : Icons.fact_check_outlined,
                color: MalvaColors.seed),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(attachment ? filename : assessmentLabel,
                    style: const TextStyle(
                        color: MalvaColors.ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 14)),
                if (assessment) ...[
                  const SizedBox(height: 4),
                  const Text(
                      'Isi sendiri untuk mencatat kondisi terkini. Hasil tersimpan di Riwayat Asesmen.',
                      style: TextStyle(color: MalvaColors.ink, fontSize: 12)),
                ],
                if (attachment && size is num && size.isFinite && size > 0) ...[
                  const SizedBox(height: 4),
                  Text('${(size / 1024).ceil()} KB',
                      style: const TextStyle(
                          color: MalvaColors.ink, fontSize: 12)),
                ],
                const SizedBox(height: 7),
                FilledButton.tonalIcon(
                  onPressed: onAction,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    foregroundColor: MalvaColors.seed,
                    textStyle: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800),
                  ),
                  icon: Icon(
                      attachment
                          ? Icons.download_outlined
                          : Icons.edit_note_rounded,
                      size: 17),
                  label: Text(action),
                ),
              ])),
        ]),
      );
    }
    return InkWell(
        onTap: onAction,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: MalvaColors.seed.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16)),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Row(children: [
                  Icon(Icons.flag_outlined, color: MalvaColors.seed),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text('Target & Kebiasaan',
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: MalvaColors.ink)))
                ]),
                if (goalIds.isNotEmpty ||
                    goals.isNotEmpty ||
                    insight.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  if (goals.isEmpty && goalIds.isNotEmpty)
                    Text('${goalIds.length} homework target tersimpan'),
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
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(goal['title']?.toString() ?? 'Target'),
                                    Text(
                                        '${goal['target_per_week'] ?? 3} kali per minggu',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall)
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
                if (onAction != null)
                  TextButton(
                      onPressed: onAction, child: const Text('Lihat detail')),
              ]),
        ));
  }
}
