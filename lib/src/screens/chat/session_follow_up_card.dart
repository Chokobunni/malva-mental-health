import 'package:flutter/material.dart';

import '../../models.dart';
import '../../theme.dart';
import '../../time/wib.dart';

const sessionFollowUpIntervals = <int, String>{
  7: '1 Minggu Lagi',
  14: '2 Minggu Lagi',
  30: '1 Bulan Lagi',
};

class SessionFollowUpCard extends StatelessWidget {
  const SessionFollowUpCard({super.key, required this.message, this.onBook});

  final ChatMessage message;
  final VoidCallback? onBook;

  @override
  Widget build(BuildContext context) {
    final metadata = message.metadata;
    final days = metadata?['interval_days'];
    final suggested = sessionFollowUpIntervals[days];
    final insight = metadata?['insight']?.toString().trim() ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(19),
        border: Border.all(color: const Color(0xffe3d3e9)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: const Color(0xfff5eafa),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.event_available_outlined,
                size: 19, color: MalvaColors.seed),
          ),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Text('Rekomendasi Sesi Lanjutan',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
                if (message.senderName.trim().isNotEmpty)
                  Text(message.senderName,
                      style:
                          const TextStyle(fontSize: 12, color: Colors.black54)),
              ])),
          const SizedBox(width: 6),
          const DecoratedBox(
            decoration: BoxDecoration(
              color: Color(0xffe5f5ec),
              borderRadius: BorderRadius.all(Radius.circular(15)),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Text('Sesi Lanjutan',
                  style: TextStyle(
                      color: Color(0xff166248),
                      fontSize: 10,
                      fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
        if (suggested != null || insight.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xfff8f2fb),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xffeee2f3)),
            ),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (suggested != null)
                Row(children: [
                  const Icon(Icons.event_outlined,
                      size: 16, color: MalvaColors.seed),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text('Disarankan: $suggested',
                          style: const TextStyle(fontWeight: FontWeight.w800))),
                ]),
              if (insight.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(insight),
              ],
            ]),
          ),
        ],
        if (onBook != null) ...[
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onBook,
            icon: const Icon(Icons.event_available_outlined, size: 17),
            label: const Text('Jadwalkan Sesi Lanjutan'),
            style: FilledButton.styleFrom(
                backgroundColor: const Color(0xff722592)),
          ),
        ],
        const SizedBox(height: 8),
        Text(formatWibBubbleTime(message.timestamp),
            textAlign: TextAlign.end,
            style: const TextStyle(color: Colors.black54, fontSize: 11)),
      ]),
    );
  }
}
