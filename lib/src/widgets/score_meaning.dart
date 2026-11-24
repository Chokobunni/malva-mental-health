import 'package:flutter/material.dart';

import '../ai/assessment_scoring.dart';
import '../theme.dart';

/// Pembungkus lipat untuk tabel "Apa arti skormu?" agar layar tidak panjang.
class ScoreMeaningExpansion extends StatelessWidget {
  const ScoreMeaningExpansion({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    return Theme(
      // Hilangkan garis pemisah bawaan ExpansionTile agar menyatu dengan kartu.
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 4, bottom: 4),
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: MalvaColors.seed,
        collapsedIconColor: onSurfaceVariant,
        title: Row(
          children: [
            Icon(Icons.info_outline_rounded, size: 16, color: onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Apa arti skormu?',
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w900,
                  color: onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        children: children,
      ),
    );
  }
}

/// Tabel rentang skor (rentang → label → saran) dengan baris skor di-highlight.
class ScoreRangeTable extends StatelessWidget {
  const ScoreRangeTable({
    required this.title,
    required this.score,
    required this.maxScore,
    required this.color,
    required this.ranges,
  });

  final String title;
  final int score;
  final int maxScore;
  final Color color;
  final List<ScoreRangeRow> ranges;

  @override
  Widget build(BuildContext context) {
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MalvaColors.seed.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$title — $score/$maxScore',
              style: TextStyle(
                  fontWeight: FontWeight.w900, fontSize: 12, color: color)),
          const SizedBox(height: 6),
          for (final row in ranges)
            Semantics(
              selected: row.contains(score),
              child: Container(
                margin: const EdgeInsets.only(bottom: 3),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                decoration: BoxDecoration(
                  color: row.contains(score)
                      ? color.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  border: row.contains(score)
                      ? Border.all(color: color.withValues(alpha: 0.4))
                      : null,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 44,
                      child: Text(
                        row.rangeLabel,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          color: row.contains(score) ? color : onSurfaceVariant,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 68,
                      child: Text(
                        row.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                          color: row.contains(score) ? color : onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(row.advice,
                          style: const TextStyle(fontSize: 11)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
