import 'package:flutter/material.dart';

import '../../models.dart';
import '../../time/wib.dart';

/// The server-validated session snapshot remains readable in the conversation.
class SessionSummaryChatCard extends StatelessWidget {
  const SessionSummaryChatCard({super.key, required this.message});

  final ChatMessage message;
  static const _purple = Color(0xFF9954B4);
  static const _ink = Color(0xFF26232C);
  static const _muted = Color(0xFF8E8993);

  Widget _icon(IconData icon, Color color, double size) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            color: color.withValues(alpha: .14),
            borderRadius: BorderRadius.circular(size * .24)),
        child: Icon(icon, color: color, size: size * .68),
      );

  (IconData, Color) _goalIcon(String title) {
    final text = title.toLowerCase();
    if (RegExp(r'tidur|sleep|istirahat').hasMatch(text)) {
      return (Icons.bed_outlined, _purple);
    }
    if (RegExp(r'berenang|renang|swim').hasMatch(text)) {
      return (Icons.pool_outlined, const Color(0xFF5C82AE));
    }
    if (RegExp(r'jalan|walk|lari|run').hasMatch(text)) {
      return (Icons.directions_walk_rounded, const Color(0xFF5D9B8D));
    }
    if (RegExp(r'bike|sepeda|elliptical|olahraga').hasMatch(text)) {
      return (Icons.directions_bike_outlined, const Color(0xFF5C82AE));
    }
    return (Icons.flag_outlined, _purple);
  }

  Widget _goal(Map goal, int index) {
    final title = goal['title']?.toString().trim() ?? '';
    final target = goal['target_per_week'];
    final validTarget = target is num &&
        target.isFinite &&
        target > 0 &&
        target <= 7 &&
        target == target.roundToDouble();
    final (icon, color) = _goalIcon(title);
    return Container(
        constraints: const BoxConstraints(minHeight: 76),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: const Color(0xFFDEDBE2)),
            borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          _icon(icon, color, 36),
          const SizedBox(width: 6),
          Expanded(
              child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title.isEmpty ? 'Goal tersimpan' : title,
                    style: const TextStyle(
                        fontSize: 12,
                        height: 1.2,
                        fontWeight: FontWeight.w700,
                        color: _ink)),
                const SizedBox(height: 6),
                Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    decoration: BoxDecoration(
                        color: index % 3 == 0
                            ? const Color(0xFFD7F1E8)
                            : const Color(0xFFEFE1F4),
                        borderRadius: BorderRadius.circular(18)),
                    child: Text(
                        validTarget
                            ? 'Target: ${target.toInt()}x / minggu'
                            : 'Target belum tercatat',
                        style: const TextStyle(
                            fontSize: 8, height: 1.2, color: _ink))),
              ])),
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final meta = message.metadata ?? const <String, dynamic>{};
    final rawGoals = meta['goals'];
    final goals = (rawGoals is List ? rawGoals : const [])
        .whereType<Map>()
        .toList(growable: false);
    final rawIds = meta['goal_ids'];
    final goalCount = rawIds is List ? rawIds.length : 0;
    final insight = meta['insight']?.toString().trim() ?? '';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xFFFAEFF8),
          borderRadius: BorderRadius.circular(26)),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(
              color: const Color(0xFFFFF1F1),
              padding: const EdgeInsets.all(12),
              child: Column(children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('Detail Record',
                            style: TextStyle(
                                color: _ink,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                        SizedBox(height: 3),
                        Text('Dibagikan',
                            style: TextStyle(color: _muted, fontSize: 11)),
                      ])),
                  const SizedBox(width: 8),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.calendar_today_outlined,
                          color: _purple, size: 14),
                      const SizedBox(width: 6),
                      Text(formatWibDate(message.timestamp),
                          style: const TextStyle(fontSize: 11, color: _ink)),
                    ]),
                    const SizedBox(height: 7),
                    Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.schedule, color: _purple, size: 14),
                      const SizedBox(width: 6),
                      Text(formatWibBubbleTime(message.timestamp),
                          style: const TextStyle(fontSize: 11, color: _muted)),
                    ]),
                  ]),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  _icon(Icons.assignment_turned_in_outlined,
                      const Color(0xFF5D9B8D), 30),
                  const SizedBox(width: 8),
                  const Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('Rangkuman Sesi',
                            style: TextStyle(
                                color: _ink,
                                fontSize: 15,
                                fontWeight: FontWeight.w700)),
                        SizedBox(height: 3),
                        Text('Catatan & Target Konseling',
                            style: TextStyle(color: _muted, fontSize: 11)),
                      ])),
                ]),
              ])),
          Container(
              color: const Color(0xFFF8FBFD),
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Goals & Habits',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _ink)),
                    const SizedBox(height: 10),
                    if (goals.isEmpty)
                      Text(
                          goalCount > 0
                              ? '$goalCount goals tersimpan. Detail goal belum tersedia.'
                              : 'Belum ada goals dalam rangkuman ini.',
                          style: const TextStyle(fontSize: 11, color: _muted))
                    else
                      LayoutBuilder(builder: (context, constraints) {
                        final columns = constraints.maxWidth < 280 ||
                                MediaQuery.textScalerOf(context).scale(1) > 1.25
                            ? 1
                            : 2;
                        return Column(children: [
                          for (var i = 0; i < goals.length; i += columns)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: IntrinsicHeight(
                                    child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                      for (var j = 0; j < columns; j++) ...[
                                        if (j > 0) const SizedBox(width: 10),
                                        Expanded(
                                            child: i + j < goals.length
                                                ? _goal(goals[i + j], i + j)
                                                : const SizedBox()),
                                      ],
                                    ]))),
                        ]);
                      }),
                    const SizedBox(height: 6),
                    const Text('Insight',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: _ink)),
                    const SizedBox(height: 12),
                    Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                            color: const Color(0xFFF0EAF9),
                            borderRadius: BorderRadius.circular(16)),
                        child: Row(children: [
                          _icon(Icons.lightbulb_outline_rounded, _purple, 40),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                const Text('INSIGHT',
                                    style:
                                        TextStyle(color: _muted, fontSize: 10)),
                                const SizedBox(height: 4),
                                Text(
                                    insight.isEmpty
                                        ? 'Belum ada insight tersimpan.'
                                        : insight,
                                    style: const TextStyle(
                                        color: _ink,
                                        fontSize: 11,
                                        height: 1.4)),
                              ])),
                        ])),
                  ])),
        ]),
      ),
    );
  }
}
