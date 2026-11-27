import 'package:flutter/material.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../time/wib.dart';
import '../../widgets/assessment_reference.dart';
import '../../widgets/therapy_library.dart';
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
    final therapy = message.kind == 'therapy_request';
    if (assessment || therapy) {
      return _requestCard(meta['module_id']?.toString() ?? '', assessment);
    }
    final attachment = message.kind == 'attachment';
    final rawGoals = meta['goals'];
    final goals = (rawGoals is List ? rawGoals : const []).whereType<Map>();
    final rawGoalIds = meta['goal_ids'];
    final goalIds = rawGoalIds is List ? rawGoalIds : const [];
    final insight = meta['insight']?.toString() ?? '';
    final filename = meta['filename']?.toString() ?? 'Lampiran';
    if (attachment) {
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
            child:
                const Icon(Icons.attach_file_rounded, color: MalvaColors.seed),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(filename,
                    style: const TextStyle(
                        color: MalvaColors.ink,
                        fontWeight: FontWeight.w900,
                        fontSize: 14)),
                if (size is num && size.isFinite && size > 0) ...[
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
                  icon: const Icon(Icons.download_outlined, size: 17),
                  label: const Text('Buka lampiran'),
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

  Widget _requestCard(String moduleId, bool assessment) {
    final instrument =
        assessment ? AssessmentInstrument.fromId(moduleId) : null;
    final module = assessment ? null : findTherapyModuleById(moduleId);
    final title = (instrument == AssessmentInstrument.phqGad
            ? 'PHQ-9 & GAD-7'
            : instrument?.title) ??
        module?.title ??
        (assessment ? 'Asesmen' : 'Terapi Psikologis');
    final color = instrument?.color ?? MalvaColors.seed;
    final tint = instrument?.tint ?? const Color(0xfff4e8fb);
    final description = assessment
        ? 'Isi sendiri untuk mencatat kondisi terkini. Hasil tersimpan otomatis di Riwayat Asesmen.'
        : 'Isi lembar kerja dan simpan hasilnya di Riwayat Terapi.';
    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: tint),
        borderRadius: BorderRadius.circular(19),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (instrument != null)
            instrument.icon(41)
          else if (module != null)
            TherapyModuleIcon(module: module, size: 41)
          else
            Icon(Icons.assignment_outlined, color: color, size: 31),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              color: MalvaColors.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w800))),
                  if (instrument != null) ...[
                    const SizedBox(width: 6),
                    Flexible(
                        child: DecoratedBox(
                      decoration: BoxDecoration(
                          color: tint, borderRadius: BorderRadius.circular(6)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 4),
                        child: Text('${instrument.questionCount} Soal',
                            style: TextStyle(
                                color: color,
                                fontSize: 11,
                                fontWeight: FontWeight.w800)),
                      ),
                    )),
                  ],
                ]),
                const SizedBox(height: 6),
                Text(description,
                    style: const TextStyle(
                        color: Color(0xff68727e), fontSize: 13, height: 1.45)),
                const Divider(height: 18, color: Color(0xffeff0f2)),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (assessment || isPatient)
                      Flexible(
                          child: FilledButton.tonalIcon(
                        onPressed: (instrument != null || module != null)
                            ? onAction
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: tint,
                          foregroundColor: color,
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          textStyle: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w800),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: Icon(
                            isPatient
                                ? Icons.edit_outlined
                                : Icons.history_rounded,
                            size: 16),
                        label: Text(isPatient
                            ? (assessment ? 'Isi asesmen' : 'Isi lembar kerja')
                            : 'Lihat Riwayat'),
                      )),
                    const SizedBox(width: 7),
                    if (!assessment && !isPatient) const Spacer(),
                    Text(formatWibBubbleTime(message.timestamp),
                        style: const TextStyle(
                            color: Color(0xff7a8591), fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
