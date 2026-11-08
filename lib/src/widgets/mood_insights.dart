import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models.dart';
import '../services/mood_insights.dart';
import '../theme.dart';
import '../time/wib.dart';
import 'malva_components.dart';

const _months = [
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
String moodCalendarDate(DateTime date) {
  final d = toWib(date);
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

class MoodInsights extends StatefulWidget {
  const MoodInsights(
      {super.key, required this.entries, this.now, this.ownerKey});
  final List<MoodEntry> entries;
  final DateTime? now;
  final String? ownerKey;
  @override
  State<MoodInsights> createState() => _MoodInsightsState();
}

class _MoodInsightsState extends State<MoodInsights> {
  late DateTime _month;
  ModalRoute<dynamic>? _detailsRoute;

  void _closeDetails() {
    final route = _detailsRoute;
    _detailsRoute = null;
    if (route == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final navigator = route.navigator;
      if (navigator != null && navigator.mounted && route.isActive)
        navigator.removeRoute(route);
    });
  }

  @override
  void didUpdateWidget(covariant MoodInsights oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.ownerKey != oldWidget.ownerKey ||
        !identical(widget.entries, oldWidget.entries)) _closeDetails();
  }

  @override
  void dispose() {
    _closeDetails();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final now = toWib(widget.now ?? wibNow());
    _month = wibFromParts(now.year, now.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final stats = MoodStatistics.fromEntries(widget.entries, now: widget.now);
    final recent = [...widget.entries]
      ..sort((a, b) => b.date.compareTo(a.date));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        for (final metric in [
          ('✅ Longest Streak', stats.longestStreak),
          ('🔥 Current Streak', stats.currentStreak),
          ('🗓️ Total Days', stats.totalDays)
        ])
          Expanded(
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: SoftCard(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 14),
                      child: Column(children: [
                        Text('${metric.$2}',
                            style: const TextStyle(
                                fontSize: 25, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 4),
                        Text(metric.$1,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w700)),
                      ])))),
      ]),
      const SizedBox(height: 18),
      SoftCard(
          child: Column(children: [
        Row(children: [
          IconButton(
              tooltip: 'Bulan sebelumnya',
              onPressed: () => setState(() =>
                  _month = wibFromParts(_month.year, _month.month - 1, 1)),
              icon: const Icon(Icons.chevron_left)),
          Expanded(
              child: Text('${_months[_month.month - 1]} ${_month.year}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w800))),
          IconButton(
              tooltip: 'Bulan berikutnya',
              onPressed: () => setState(() =>
                  _month = wibFromParts(_month.year, _month.month + 1, 1)),
              icon: const Icon(Icons.chevron_right)),
        ]),
        _calendar(),
        const SizedBox(height: 8),
        const Text('Tanggal berwarna = check-in tercatat (WIB)',
            style: TextStyle(fontSize: 11)),
      ])),
      const SizedBox(height: 18),
      MoodTrendChart(entries: widget.entries, now: widget.now),
      const SizedBox(height: 18),
      SymptomsBalanceChart(entries: widget.entries, now: widget.now),
      const SizedBox(height: 18),
      const SectionLabel('Recent Mood Entries'),
      if (recent.isEmpty)
        const SoftCard(
            child: Text('Belum ada check-in. Tambahkan mood pertamamu.')),
      for (final entry in recent.take(3))
        Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _RecentMood(entry: entry)),
    ]);
  }

  Widget _calendar() {
    final firstOffset = _month.weekday % 7;
    final count = wibFromParts(_month.year, _month.month + 1, 0).day;
    return Column(children: [
      Row(children: [
        for (final name in ['Min', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab'])
          Expanded(
              child: Center(
                  child: Text(name, style: const TextStyle(fontSize: 11))))
      ]),
      const SizedBox(height: 8),
      for (var row = 0; row < (firstOffset + count + 6) ~/ 7; row++)
        Row(children: [
          for (var col = 0; col < 7; col++)
            Expanded(
                child: _calendarCell(row * 7 + col - firstOffset + 1, count)),
        ]),
    ]);
  }

  Widget _calendarCell(int day, int count) {
    if (day < 1 || day > count) return const SizedBox(height: 42);
    final date = wibFromParts(_month.year, _month.month, day);
    final matches = widget.entries
        .where((e) => wibDateKey(e.date) == wibDateKey(date))
        .toList();
    return Semantics(
        label: '${moodCalendarDate(date)}, ${matches.length} check-in',
        button: matches.isNotEmpty,
        child: ExcludeSemantics(
            child: InkWell(
          onTap: matches.isEmpty
              ? null
              : () => showModalBottomSheet<void>(
                  context: context,
                  showDragHandle: true,
                  isScrollControlled: true,
                  builder: (sheetContext) {
                    _detailsRoute = ModalRoute.of(sheetContext);
                    return SafeArea(
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.all(18),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  for (final e in matches) _RecentMood(entry: e)
                                ])));
                  }),
          child: Container(
              height: 38,
              margin: const EdgeInsets.all(2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: matches.isEmpty
                      ? Colors.transparent
                      : MalvaColors.mint.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(10)),
              child: Text('$day',
                  style: TextStyle(
                      fontWeight: matches.isEmpty
                          ? FontWeight.normal
                          : FontWeight.w900))),
        )));
  }
}

class MoodTrendChart extends StatelessWidget {
  const MoodTrendChart({super.key, required this.entries, this.now});
  final List<MoodEntry> entries;
  final DateTime? now;
  @override
  Widget build(BuildContext context) {
    final days = moodWeek(entries, now: now);
    final balance = moodBalance(entries, now: now);
    return SoftCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Mood Trend',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      const Text('7 hari terakhir • rata-rata harian • WIB',
          style: TextStyle(fontSize: 12)),
      const SizedBox(height: 14),
      const Wrap(spacing: 12, children: [
        Text('🟢 Baik'),
        Text('🟡 Cukup'),
        Text('🔴 Rendah'),
        Text('🟦 Tidur')
      ]),
      const SizedBox(height: 10),
      Semantics(
          label: days
              .map((d) =>
                  '${formatWibDate(d.date)}: ${d.mood == null ? 'belum ada data' : 'mood ${d.mood!.toStringAsFixed(1)}/5, tidur ${d.sleep!.toStringAsFixed(1)} jam'}')
              .join('. '),
          child: SizedBox(
              height: 210,
              child: CustomPaint(
                  painter: _TrendPainter(days),
                  child: const SizedBox.expand()))),
      if (balance == null)
        const Text(
            'Belum ada data minggu ini. Hari tanpa check-in dibiarkan kosong.'),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        _symptomTag('Anxiety', balance?[4], MalvaColors.amber),
        _symptomTag('Energy', balance?[1], MalvaColors.mint),
        _symptomTag('Irritability', balance?[3], MalvaColors.pink),
      ]),
    ]));
  }

  Widget _symptomTag(String label, double? value, Color color) => StatusPill(
      label:
          '$label: ${value == null ? '—' : value < 4 ? 'Low' : value < 7 ? 'Med' : 'High'}',
      color: color);
}

Color _moodColor(double score) => score >= 3.5
    ? const Color(0xFF39A856)
    : score >= 2.5
        ? const Color(0xFFE3B51C)
        : const Color(0xFFD94742);

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.days);
  final List<MoodDay> days;
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(22, 12, size.width - 28, size.height - 35);
    final step = rect.width / 7;
    final grid = Paint()
      ..color = Colors.black12
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = rect.top + i * rect.height / 4;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
      _text(canvas, '${5 - i}', Offset(0, y - 6));
      _text(canvas, '${12 - i * 3}', Offset(rect.right + 4, y - 6));
    }
    Offset? previous;
    double? previousMood;
    for (var i = 0; i < days.length; i++) {
      final d = days[i];
      final x = rect.left + step * (i + 0.5);
      _text(canvas, '${d.date.day}/${d.date.month}',
          Offset(x - 12, rect.bottom + 10));
      if (d.mood == null) {
        previous = null;
        previousMood = null;
        continue;
      }
      final barHeight = (d.sleep! / 12).clamp(0, 1) * rect.height;
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x - step * .24, rect.bottom - barHeight, step * .48,
                  barHeight),
              const Radius.circular(3)),
          Paint()..color = const Color(0xFFBFD7FA));
      final point = Offset(x, rect.bottom - ((d.mood! - 1) / 4) * rect.height);
      if (previous != null)
        canvas.drawLine(
            previous,
            point,
            Paint()
              ..strokeWidth = 3
              ..shader = LinearGradient(
                      colors: [_moodColor(previousMood!), _moodColor(d.mood!)])
                  .createShader(Rect.fromPoints(previous, point).inflate(1)));
      canvas.drawCircle(point, 4, Paint()..color = _moodColor(d.mood!));
      previous = point;
      previousMood = d.mood;
    }
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) => true;
}

class SymptomsBalanceChart extends StatefulWidget {
  const SymptomsBalanceChart({super.key, required this.entries, this.now});
  final List<MoodEntry> entries;
  final DateTime? now;
  @override
  State<SymptomsBalanceChart> createState() => _SymptomsBalanceChartState();
}

class _SymptomsBalanceChartState extends State<SymptomsBalanceChart> {
  MoodRange _range = MoodRange.weekly;
  @override
  Widget build(BuildContext context) {
    final values = moodBalance(widget.entries, range: _range, now: widget.now);
    return SoftCard(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Text('Symptoms Balance Map',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      const SizedBox(height: 10),
      Wrap(spacing: 6, runSpacing: 4, children: [
        for (final range in MoodRange.values)
          ChoiceChip(
              label: Text(
                  '${range.name[0].toUpperCase()}${range.name.substring(1)}'),
              selected: range == _range,
              onSelected: (_) => setState(() => _range = range))
      ]),
      if (values == null)
        const Padding(
            padding: EdgeInsets.all(20),
            child: Text('Belum ada data pada periode ini.',
                textAlign: TextAlign.center))
      else ...[
        SizedBox(
            height: 260,
            child: Semantics(
                label:
                    'Mood ${(values[0] / 2).toStringAsFixed(1)}/5, Energy ${values[1].toStringAsFixed(1)}/10, Sleep ${values[2].toStringAsFixed(1)} jam, Irritability ${values[3].toStringAsFixed(1)}/10, Anxiety ${values[4].toStringAsFixed(1)}/10',
                child: CustomPaint(
                    painter: _BalancePainter(values),
                    child: const SizedBox.expand()))),
        const Text(
            'Rata-rata check-in. Mood: 1–5 • Sleep: 0–12 jam • sumbu lain: 0–10. Angka kecemasan/iritabilitas lebih tinggi berarti gejala lebih kuat.',
            style: TextStyle(fontSize: 11)),
      ],
    ]));
  }
}

class _BalancePainter extends CustomPainter {
  _BalancePainter(this.values);
  final List<double> values;
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width / 2 - 55, 80.0);
    Offset point(int i, double fraction) =>
        center +
        Offset(math.cos(-math.pi / 2 + i * math.pi * 2 / 5),
                math.sin(-math.pi / 2 + i * math.pi * 2 / 5)) *
            radius *
            fraction;
    Path polygon(double scale) {
      final p = Path()..moveTo(point(0, scale).dx, point(0, scale).dy);
      for (var i = 1; i < 5; i++) {
        p.lineTo(point(i, scale).dx, point(i, scale).dy);
      }
      return p..close();
    }

    final grid = Paint()
      ..color = Colors.black12
      ..style = PaintingStyle.stroke;
    for (var ring = 1; ring <= 5; ring++) {
      canvas.drawPath(polygon(ring / 5), grid);
    }
    const names = ['Mood', 'Energy', 'Sleep', 'Irritability', 'Anxiety'];
    for (var i = 0; i < 5; i++) {
      canvas.drawLine(center, point(i, 1), grid);
      final label = point(i, 1.28);
      _text(canvas, names[i],
          Offset(label.dx - (names[i].length * 3), label.dy - 6));
    }
    final scaled = [
      values[0] / 10,
      values[1] / 10,
      values[2] / 12,
      values[3] / 10,
      values[4] / 10
    ];
    final data = Path();
    for (var i = 0; i < 5; i++) {
      final p = point(i, scaled[i].clamp(0, 1));
      if (i == 0) {
        data.moveTo(p.dx, p.dy);
      } else {
        data.lineTo(p.dx, p.dy);
      }
    }
    data.close();
    canvas.drawPath(
        data, Paint()..color = MalvaColors.orchid.withValues(alpha: .22));
    canvas.drawPath(
        data,
        Paint()
          ..color = MalvaColors.orchid
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant _BalancePainter oldDelegate) => true;
}

void _text(Canvas canvas, String text, Offset offset) {
  final painter = TextPainter(
      text: TextSpan(
          text: text,
          style: const TextStyle(
              color: Colors.black87, fontSize: 10, fontFamily: 'Roboto')),
      textDirection: TextDirection.ltr)
    ..layout();
  painter.paint(canvas, offset);
}

class _RecentMood extends StatelessWidget {
  const _RecentMood({required this.entry});
  final MoodEntry entry;
  @override
  Widget build(BuildContext context) => SoftCard(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(entry.mood.emoji, style: const TextStyle(fontSize: 32)),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(entry.mood.label,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                Text(moodCalendarDate(entry.date),
                    style: const TextStyle(fontSize: 12))
              ])),
          StatusPill(
              label: '🛏 ${entry.sleepHours.toStringAsFixed(1)}h',
              color: MalvaColors.orchid)
        ]),
        const SizedBox(height: 12),
        for (final value in [
          ('Energy', entry.energy, MalvaColors.mint),
          ('Anxiety', entry.anxiety, MalvaColors.amber),
          ('Irritability', entry.irritability, MalvaColors.pink)
        ])
          Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(children: [
                SizedBox(
                    width: 70,
                    child:
                        Text(value.$1, style: const TextStyle(fontSize: 11))),
                Expanded(
                    child: LinearProgressIndicator(
                        value: (value.$2 / 10).clamp(0, 1),
                        color: value.$3,
                        backgroundColor: value.$3.withValues(alpha: .12),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(5))),
                const SizedBox(width: 10),
                Text('${value.$2}/10', style: const TextStyle(fontSize: 11))
              ])),
      ]));
}
