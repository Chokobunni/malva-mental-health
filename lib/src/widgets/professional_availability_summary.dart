import 'package:flutter/material.dart';

import '../services/malva_api_client.dart';
import '../theme.dart';
import '../time/wib.dart';

class ProfessionalAvailabilitySummary extends StatelessWidget {
  const ProfessionalAvailabilitySummary({
    required this.schedules,
    required this.pricing,
    this.timeOff = const [],
  });

  final List<BackendProfessionalSchedule> schedules;
  final BackendProfessionalPricing pricing;
  final List<BackendTimeOff> timeOff;

  static const _dayNames = [
    'Min',
    'Sen',
    'Sel',
    'Rab',
    'Kam',
    'Jum',
    'Sab',
  ];

  @override
  Widget build(BuildContext context) {
    final byDay = <int, List<BackendProfessionalSchedule>>{};
    for (final s in schedules.where((s) => s.isActive)) {
      (byDay[s.dayOfWeek] ??= []).add(s);
    }
    final todayYmd = wibDateKey(wibNow());
    final upcomingOff = timeOff
        .where((t) => t.offDate.compareTo(todayYmd) >= 0)
        .toList()
      ..sort((a, b) => a.offDate.compareTo(b.offDate));
    String rupiah(int v) {
      if (v <= 0) return 'belum diatur';
      final s = v.toString();
      final buf = StringBuffer();
      for (var i = 0; i < s.length; i++) {
        final pos = s.length - i;
        buf.write(s[i]);
        if (pos > 1 && pos % 3 == 1) buf.write('.');
      }
      return 'Rp ${buf.toString()}';
    }

    Widget price(String label, int value, {bool package = false}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style:
                      const TextStyle(fontSize: 12.5, color: Colors.black54))),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                  color: package
                      ? const Color(0xFFF2E6FB)
                      : const Color(0xFFF7F8FA),
                  borderRadius: BorderRadius.circular(4)),
              child: Text(rupiah(value),
                  style: const TextStyle(
                      fontSize: 12.5, fontWeight: FontWeight.w800))),
        ]));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Jam praktik mingguan',
          style: TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 12),
      if (byDay.isEmpty)
        const Text('Belum diatur — pasien tidak bisa booking.',
            style: TextStyle(color: MalvaColors.danger, fontSize: 12.5))
      else
        for (final day
            in (byDay.keys.toList()
              ..sort((a, b) => (a == 0 ? 7 : a).compareTo(b == 0 ? 7 : b))))
          Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                    width: 40,
                    child: Text('${_dayNames[day]}:',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800, fontSize: 12.5))),
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      for (final slot
                          in (byDay[day]!
                            ..sort(
                                (a, b) => a.startTime.compareTo(b.startTime))))
                        Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                                '${slot.startTime}–${slot.endTime} (${slot.slotDurationMinutes} mnt)',
                                style: const TextStyle(
                                    color: Colors.black54, fontSize: 12.5))),
                    ])),
              ])),
      const Divider(height: 24, color: Color(0xFFEDEFF2)),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Hari libur:',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
        const SizedBox(width: 12),
        Expanded(
            child: Text(
                upcomingOff.isEmpty
                    ? 'belum ada'
                    : upcomingOff
                        .map((day) => _formatYmdId(day.offDate))
                        .join('\n'),
                textAlign: TextAlign.right,
                style: const TextStyle(
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                    color: Colors.black54))),
      ]),
      const Divider(height: 24, color: Color(0xFFEDEFF2)),
      price('Chat:', pricing.quickChatPrice),
      price('Video:', pricing.quickVideoPrice),
      price('Paket 4 sesi / 6 minggu:', pricing.packagePrice, package: true),
    ]);
  }
}

String _formatYmdId(String ymd) {
  final d = DateTime.tryParse(ymd);
  if (d == null) return ymd;
  const days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
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
    'Des'
  ];
  return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
}
