import 'package:flutter/material.dart';

import '../../models.dart';
import '../../time/wib.dart';

class SessionCancellationCard extends StatelessWidget {
  const SessionCancellationCard({super.key, required this.message});

  final ChatMessage message;

  static const _ink = Color(0xff202b39);
  static const _red = Color(0xffa42024);
  static const _bold = TextStyle(fontWeight: FontWeight.w800, color: _ink);

  @override
  Widget build(BuildContext context) {
    final data = message.metadata ?? const {};
    final package = data['package'] == true;
    final patient = data['actor_role'] == 'patient';
    final reason = data['reason']?.toString().trim() ?? '';
    final date = parseWibStored(data['scheduled_at']?.toString() ?? '');
    final method = data['session_type'] == 'video' ? 'Video' : 'Chat';
    final day = date == null ? '' : wibWeekdayName(date);
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    final schedule = date == null
        ? ''
        : '${package ? day : day.substring(0, 3)}, ${date.day} '
            '${months[date.month - 1]} ${date.year} '
            '(${formatWibBubbleTime(date)} WIB)';
    final amount = data['refund_amount'];
    final rupiah = amount is num && amount > 0
        ? ' Rp ${amount.toInt().toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.')}'
        : '';
    final (emphasis, explanation) = switch (data['outcome']) {
      'credit' => (
          '+1 Kredit Sesi',
          patient
              ? ' otomatis dikembalikan ke akun pasien dan siap dijadwalkan ulang.'
              : ' otomatis dikembalikan dan siap dijadwalkan ulang.',
        ),
      'refund' => (
          'Dana${patient ? '' : rupiah} otomatis direfund',
          ' ke metode pembayaran pasien${patient ? '' : ' (estimasi 1–3 hari kerja)'}.',
        ),
      'penalty' => (
          package
              ? 'Kredit Sesi pasien tidak dapat dikembalikan'
              : 'Dana pasien tidak dapat direfund',
          ' karena pembatalan melewati batas waktu kebijakan.',
        ),
      _ => ('', ''),
    };
    final penalty = data['outcome'] == 'penalty';
    final professionalSingle = !patient && !package;
    final panelColor =
        penalty ? const Color(0xff854717) : const Color(0xff125948);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xffedd5d4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xfffdf0f0),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.event_busy_outlined, color: _red, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                              maxWidth:
                                  professionalSingle ? 160 : double.infinity),
                          child: Text(
                            'Sesi Dibatalkan oleh ${patient ? 'Pasien' : 'Profesional'}',
                            style: _bold.copyWith(color: _red, fontSize: 15),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(formatWibBubbleTime(message.timestamp),
                        style: const TextStyle(
                            color: Color(0xff98a5b1), fontSize: 11)),
                  ],
                ),
                if (schedule.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text.rich(
                      TextSpan(children: [
                        if (!package) const TextSpan(text: 'Jadwal '),
                        TextSpan(
                            text: package
                                ? 'Jadwal Sesi Paket'
                                : 'Sekali Sesi ($method)',
                            style: _bold),
                        const TextSpan(text: ' pada '),
                        TextSpan(text: schedule, style: _bold),
                        TextSpan(
                            text:
                                ' telah dibatalkan${patient ? ' oleh pasien' : ''}.'),
                      ]),
                      style: const TextStyle(
                          color: Color(0xff485462),
                          fontSize: 14,
                          height: 1.55)),
                ],
                if (reason.isNotEmpty) ...[
                  const Divider(height: 25, color: Color(0xffeee5e5)),
                  const Text('Alasan pembatalan:', style: _bold),
                  const SizedBox(height: 4),
                  Text('"$reason"',
                      style: const TextStyle(
                        color: Color(0xff485462),
                        fontStyle: FontStyle.italic,
                        height: 1.45,
                      )),
                ],
                if (emphasis.isNotEmpty) ...[
                  const SizedBox(height: 13),
                  Container(
                    padding: const EdgeInsets.all(11),
                    decoration: BoxDecoration(
                      color: penalty
                          ? const Color(0xfffdf9e8)
                          : const Color(0xffebfcf4),
                      border: Border.all(
                          color: penalty
                              ? const Color(0xffefe3a5)
                              : const Color(0xffc2eddb)),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Row(children: [
                      Container(
                        padding: EdgeInsets.all(!patient && package ? 0 : 5),
                        decoration: BoxDecoration(
                          color: !patient && package
                              ? Colors.transparent
                              : penalty
                                  ? const Color(0xfffbefc0)
                                  : const Color(0xffd2f8e9),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          penalty
                              ? Icons.error_outline_rounded
                              : Icons.replay_rounded,
                          color: penalty
                              ? const Color(0xffb67519)
                              : const Color(0xff138a6d),
                          size: 17,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                          child: Text.rich(
                        TextSpan(children: [
                          TextSpan(
                              text: emphasis,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          TextSpan(text: explanation),
                        ]),
                        style: TextStyle(
                            color: panelColor,
                            fontSize: professionalSingle ? 14 : 13,
                            height: 1.45),
                      )),
                    ]),
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
