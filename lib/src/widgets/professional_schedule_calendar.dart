import 'package:flutter/material.dart';

import '../services/malva_api_client.dart';
import '../theme.dart';
import '../time/wib.dart';
import 'malva_components.dart';

const _monthNames = [
  'Januari',
  'Februari',
  'Maret',
  'April',
  'Mei',
  'Juni',
  'Juli',
  'Agustus',
  'September',
  'Oktober',
  'November',
  'Desember',
];
const _shortMonthNames = [
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

String professionalScheduleDateLabel(DateTime date) =>
    '${date.day} ${_shortMonthNames[date.month - 1]} ${date.year}';

class ProfessionalScheduleCalendar extends StatelessWidget {
  const ProfessionalScheduleCalendar({
    required this.month,
    required this.today,
    required this.sessionsByDate,
    required this.selectedDate,
    required this.onMonthChanged,
    required this.onDateTapped,
    required this.onClear,
  });

  final DateTime month, today;
  final Map<String, List<BackendCareSession>> sessionsByDate;
  final DateTime? selectedDate;
  final ValueChanged<int> onMonthChanged;
  final ValueChanged<DateTime> onDateTapped;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final offset = month.weekday % 7;
    final dayCount = wibFromParts(month.year, month.month + 1, 0).day;
    final selected = selectedDate;
    final todayKey = wibDateKey(today);
    final selectedKey = selected == null ? null : wibDateKey(selected);
    final sessions =
        sessionsByDate[selectedKey] ?? const <BackendCareSession>[];
    final textTheme = Theme.of(context).textTheme;
    return SoftCard(
      color: Colors.white,
      radius: 22,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
              child: Text('${_monthNames[month.month - 1]} ${month.year}',
                  style: const TextStyle(
                      color: MalvaColors.plum,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
            ),
            IconButton(
              onPressed: () => onMonthChanged(-1),
              tooltip: 'Bulan sebelumnya',
              color: MalvaColors.seed,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              onPressed: () => onMonthChanged(1),
              tooltip: 'Bulan berikutnya',
              color: MalvaColors.seed,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            for (final day in const [
              'Min',
              'Sen',
              'Sel',
              'Rab',
              'Kam',
              'Jum',
              'Sab'
            ])
              Expanded(
                child: Text(day,
                    textAlign: TextAlign.center, style: textTheme.bodySmall),
              ),
          ]),
          const SizedBox(height: 5),
          for (var week = 0; week * 7 < dayCount + offset; week++)
            Row(children: [
              for (var weekday = 0; weekday < 7; weekday++)
                Expanded(child: Builder(builder: (context) {
                  final day = week * 7 + weekday + 1 - offset;
                  if (day < 1 || day > dayCount)
                    return const SizedBox(height: 49);
                  final date = wibFromParts(month.year, month.month, day);
                  final key = wibDateKey(date);
                  final isToday = key == todayKey;
                  final isSelected = key == selectedKey;
                  final hasSessions = sessionsByDate.containsKey(key);
                  return Semantics(
                    button: true,
                    selected: isSelected,
                    label:
                        '${wibWeekdayName(date)}, ${professionalScheduleDateLabel(date)}'
                        '${isToday ? ', hari ini' : ''}'
                        '${hasSessions ? ', ada sesi' : ''}',
                    excludeSemantics: true,
                    child: InkWell(
                      key: ValueKey('jadwal-$key'),
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => onDateTapped(date),
                      child: SizedBox(
                        height: 49,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 33,
                              height: 33,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isToday
                                    ? MalvaColors.plum
                                    : isSelected
                                        ? MalvaColors.seed
                                        : null,
                              ),
                              child: Text('$day',
                                  style: TextStyle(
                                      color: isToday || isSelected
                                          ? Colors.white
                                          : null,
                                      fontWeight:
                                          isToday || isSelected || hasSessions
                                              ? FontWeight.w800
                                              : FontWeight.w500)),
                            ),
                            const SizedBox(height: 3),
                            Icon(Icons.circle,
                                size: 5,
                                color: hasSessions
                                    ? MalvaColors.seed
                                    : Colors.transparent),
                          ],
                        ),
                      ),
                    ),
                  );
                })),
            ]),
          const Divider(),
          if (selected != null && sessions.isNotEmpty) ...[
            Row(children: [
              Expanded(
                child: Text(
                    'Daftar Pasien • ${professionalScheduleDateLabel(selected)}',
                    style: const TextStyle(
                        color: MalvaColors.plum, fontWeight: FontWeight.w800)),
              ),
              StatusPill(
                  label:
                      '${sessions.map((s) => s.patientId).toSet().length} pasien',
                  color: MalvaColors.seed),
            ]),
            for (final session in sessions)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  tileColor: const Color(0xFFF7F3FA),
                  dense: true,
                  leading: InitialAvatar(
                    name: session.patientName,
                    radius: 15,
                    color: MalvaColors.seed,
                  ),
                  title: Text(
                      session.patientName.isEmpty
                          ? 'Pasien'
                          : session.patientName,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(
                      '${formatWibBubbleTime(session.scheduledDateTime!)} WIB'
                      ' • ${session.isVideo ? 'Video' : 'Chat'} (${session.durationMinutes} mnt)'),
                ),
              ),
            const Divider(),
          ],
          Row(children: [
            const Icon(Icons.circle, color: MalvaColors.seed, size: 8),
            const SizedBox(width: 7),
            Expanded(child: Text('Ada sesi', style: textTheme.bodySmall)),
            if (selected != null)
              TextButton(
                  onPressed: onClear, child: const Text('Tampilkan semua')),
          ]),
        ],
      ),
    );
  }
}
