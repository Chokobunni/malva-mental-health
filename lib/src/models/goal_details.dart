import '../time/wib.dart';

class GoalStep {
  const GoalStep({required this.id, required this.label});
  factory GoalStep.fromJson(Map<String, dynamic> json) => GoalStep(
      id: json['id'] as String? ?? '', label: json['label'] as String? ?? '');
  final String id;
  final String label;
  Map<String, dynamic> toJson() => {'id': id, 'label': label};
}

class GoalDetails {
  const GoalDetails({
    this.note = '',
    this.method = 'yes_no',
    this.target = 1,
    this.unit = '',
    this.steps = const [],
    required this.startDate,
    this.time = '',
    this.recurrence = 'daily',
    this.interval = 1,
    this.weeklyTarget,
    this.weekdays = const [1, 2, 3, 4, 5, 6, 7],
    this.reminders = const [],
    this.autoFail = true,
    this.lockPast = false,
  });

  factory GoalDetails.fromJson(Map<String, dynamic> json) => GoalDetails(
        note: json['note'] as String? ?? '',
        method: json['method'] as String? ?? 'yes_no',
        target: (json['target'] as num?)?.toInt() ?? 1,
        unit: json['unit'] as String? ?? '',
        steps: (json['steps'] as List? ?? [])
            .whereType<Map>()
            .map((s) => GoalStep.fromJson(s.cast<String, dynamic>()))
            .toList(growable: false),
        startDate: json['start_date'] as String? ?? '',
        time: json['time'] as String? ?? '',
        recurrence: json['recurrence'] as String? ?? 'daily',
        interval: (json['interval'] as num?)?.toInt() ?? 1,
        weeklyTarget: (json['weekly_target'] as num?)?.toInt(),
        weekdays: (json['weekdays'] as List? ?? [1, 2, 3, 4, 5, 6, 7])
            .whereType<num>()
            .map((n) => n.toInt())
            .toList(growable: false),
        reminders: (json['reminders'] as List? ?? [])
            .whereType<num>()
            .map((n) => n.toInt())
            .toList(growable: false),
        autoFail: json['auto_fail'] != false,
        lockPast: json['lock_past'] == true,
      );

  final String note, method, unit, startDate, time, recurrence;
  final int target, interval;
  final int? weeklyTarget;
  final List<GoalStep> steps;
  final List<int> weekdays, reminders;
  final bool autoFail, lockPast;

  Map<String, dynamic> toJson() => {
        'note': note,
        'method': method,
        'target': target,
        'unit': unit,
        'steps': steps.map((s) => s.toJson()).toList(),
        'start_date': startDate,
        'time': time,
        'recurrence': recurrence,
        'interval': interval,
        if (weeklyTarget != null) 'weekly_target': weeklyTarget,
        'weekdays': weekdays,
        'reminders': reminders,
        'auto_fail': autoFail,
        'lock_past': lockPast,
      };

  bool isDueOn(DateTime date) {
    final start = DateTime.tryParse(startDate);
    if (start == null || interval < 1) return false;
    final day = wibFromParts(date.year, date.month, date.day);
    final anchor = wibFromParts(start.year, start.month, start.day);
    final days = day.difference(anchor).inDays;
    if (days < 0) return false;
    if (recurrence == 'daily') return days % interval == 0;
    if (recurrence == 'monthly') {
      final months = (day.year - anchor.year) * 12 + day.month - anchor.month;
      final lastDay = wibFromParts(day.year, day.month + 1, 0).day;
      return months % interval == 0 &&
          day.day == (anchor.day > lastDay ? lastDay : anchor.day);
    }
    if (recurrence != 'weekly') return false;
    final monday = anchor.subtract(Duration(days: anchor.weekday - 1));
    return day.difference(monday).inDays ~/ 7 % interval == 0 &&
        (weeklyTarget != null || weekdays.contains(day.weekday));
  }

  String get scheduleLabel {
    final every = recurrence == 'weekly'
        ? (interval == 1 ? 'setiap minggu' : 'setiap $interval minggu')
        : recurrence == 'monthly'
            ? (interval == 1 ? 'setiap bulan' : 'setiap $interval bulan')
            : (interval == 1 ? 'setiap hari' : 'setiap $interval hari');
    final days = recurrence == 'weekly' && weeklyTarget == null
        ? ' pada ${weekdays.length == 7 ? 'setiap hari' : (weekdays.toList()..sort()).map((d) => const [
              'Sen',
              'Sel',
              'Rab',
              'Kam',
              'Jum',
              'Sab',
              'Min'
            ][d - 1]).join(', ')}'
        : recurrence == 'weekly' && weeklyTarget != null
            ? (weeklyTarget == 0
                ? ' tanpa target frekuensi khusus'
                : ' • target $weeklyTarget kali per minggu (hari fleksibel)')
            : recurrence == 'monthly'
                ? ' pada tanggal ${startDate.split('-').last} (akhir bulan bila lebih pendek)'
                : '';
    return 'Berulang $every$days${time.isEmpty ? '' : ' • Pukul ${time.replaceAll(':', '.')}'}';
  }
}

String goalDateLabel(String key) {
  final date = DateTime.tryParse(key);
  if (date == null) return key;
  const months = [
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
    'Desember'
  ];
  return '${date.day} ${months[date.month - 1]} ${date.year}';
}
