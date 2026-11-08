import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models.dart';
import '../time/wib.dart';
import 'mood_insights.dart';

class ScreeningPdfScore {
  const ScreeningPdfScore(
      {required this.instrument,
      required this.total,
      required this.interpretation,
      required this.rank});
  final String instrument;
  final String total;
  final String interpretation;
  final int rank;
}

class ScreeningPdfRow {
  const ScreeningPdfRow(
      {this.date,
      required this.title,
      required this.scores,
      this.crisis = false});
  final DateTime? date;
  final String title;
  final List<ScreeningPdfScore> scores;
  final bool crisis;
}

const _ink = PdfColor.fromInt(0xFF24334A);
const _teal = PdfColor.fromInt(0xFF087E78);
const _border = PdfColor.fromInt(0xFFCBD5E1);
const _stripe = PdfColor.fromInt(0xFFF6F8FB);
const _colors = [
  PdfColors.green800,
  PdfColors.blue800,
  PdfColors.orange800,
  PdfColors.deepOrange800,
  PdfColors.red800
];
const _backgrounds = [
  PdfColors.green50,
  PdfColors.blue50,
  PdfColors.yellow100,
  PdfColors.orange50,
  PdfColors.red50
];

Future<Uint8List> buildHealthReportPdf({
  required String title,
  List<MoodEntry>? moods,
  List<MedicationLog>? medicationLogs,
  List<ScreeningPdfRow>? screenings,
  List<DiaryEntry>? diaries,
  String? patientName,
  DateTime? now,
}) async {
  final at = now ?? wibNow();
  final font =
      pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-regular.ttf'));
  final bold =
      pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-bold.ttf'));
  final emoji = <MoodValue, pw.MemoryImage>{};
  if (moods != null) {
    for (final mood in MoodValue.values) {
      emoji[mood] = pw.MemoryImage(
          (await rootBundle.load('assets/mood_emojis/${mood.name}.png'))
              .buffer
              .asUint8List());
    }
  }
  final document = pw.Document(title: title, author: 'MALVA');
  document.addPage(pw.MultiPage(
    pageFormat: PdfPageFormat.a4,
    margin: const pw.EdgeInsets.fromLTRB(36, 40, 36, 36),
    maxPages: 10000,
    theme: pw.ThemeData.withFont(base: font, bold: bold),
    header: (_) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 16),
        child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(title,
                  style: pw.TextStyle(
                      fontSize: 19,
                      fontWeight: pw.FontWeight.bold,
                      color: moods != null ? _teal : _ink)),
              pw.SizedBox(height: 6),
              pw.Text('Diekspor: ${formatWibDateTime(at)} WIB',
                  style: const pw.TextStyle(
                      fontSize: 9, color: PdfColors.blueGrey700)),
              if (patientName != null)
                pw.Text('Nama: $patientName',
                    style: const pw.TextStyle(fontSize: 9)),
              pw.SizedBox(height: 8),
              pw.Divider(color: _border),
            ])),
    footer: (context) =>
        pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
      pw.Text('Pribadi - MALVA',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey700)),
      pw.Text('Halaman ${context.pageNumber} dari ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 8, color: PdfColors.blueGrey700))
    ]),
    build: (_) => [
      if (moods != null) ..._moodSection(moods, emoji, at),
      if (screenings != null) ..._screeningSection(screenings),
      if (medicationLogs != null) ..._medicationSection(medicationLogs),
      if (diaries != null) ..._diarySection(diaries),
    ],
  ));
  return document.save();
}

pw.Widget _heading(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 10, bottom: 10),
    child: pw.Text(text,
        style: const pw.TextStyle(
            fontSize: 13, fontWeight: pw.FontWeight.bold, color: _teal)));
pw.Widget _text(String text, {bool bold = false, PdfColor? color}) =>
    pw.Text(text.replaceAll('–', '-').replaceAll('—', '-'),
        style: pw.TextStyle(
            fontSize: 9,
            lineSpacing: 2,
            fontWeight: bold ? pw.FontWeight.bold : null,
            color: color ?? _ink));
pw.Widget _cell(pw.Widget child) =>
    pw.Padding(padding: const pw.EdgeInsets.all(8), child: child);
pw.Widget _badge(String label, int rank) {
  final index = rank.clamp(0, 4);
  return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: pw.BoxDecoration(
          color: _backgrounds[index],
          borderRadius: pw.BorderRadius.circular(9),
          border: pw.Border.all(color: _colors[index], width: .3)),
      child: _text(label, bold: true, color: _colors[index]));
}

pw.Widget _table(List<String> headers, List<List<pw.Widget>> rows,
        Map<int, pw.TableColumnWidth> widths) =>
    pw.Table(
      columnWidths: widths,
      border: pw.TableBorder.all(color: _border, width: .5),
      children: [
        pw.TableRow(
            repeat: true,
            decoration: const pw.BoxDecoration(color: _stripe),
            children: [
              for (final header in headers) _cell(_text(header, bold: true))
            ]),
        for (var i = 0; i < rows.length; i++)
          pw.TableRow(
              decoration:
                  pw.BoxDecoration(color: i.isOdd ? _stripe : PdfColors.white),
              verticalAlignment: pw.TableCellVerticalAlignment.middle,
              children: [for (final child in rows[i]) _cell(child)]),
      ],
    );

Iterable<pw.Widget> _medicationSection(List<MedicationLog> logs) sync* {
  yield _heading('Riwayat Konsumsi Obat');
  yield pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: _text(
          'Catatan harian kepatuhan konsumsi obat. Hijau: taken, kuning: partial, jingga: skipped, merah: missed.'));
  final sorted = [...logs]..sort((a, b) => b.takenAt.compareTo(a.takenAt));
  if (sorted.isEmpty) {
    yield _text('Belum ada log obat.');
    return;
  }
  yield _table([
    'TANGGAL',
    'WAKTU (WIB)',
    'NAMA OBAT',
    'STATUS'
  ], [
    for (final log in sorted)
      [
        _text(_date(log.takenAt), bold: true),
        _text(_time(log.takenAt)),
        _text(log.medicationName, bold: true, color: _teal),
        _badge(
            log.status.toUpperCase(),
            switch (log.status) {
              'taken' => 0,
              'partial' => 2,
              'skipped' => 3,
              _ => 4
            }),
      ]
  ], {
    0: const pw.FlexColumnWidth(1.4),
    1: const pw.FlexColumnWidth(1),
    2: const pw.FlexColumnWidth(1.8),
    3: const pw.FlexColumnWidth(1)
  });
}

Iterable<pw.Widget> _screeningSection(List<ScreeningPdfRow> rows) sync* {
  yield _heading('Hasil Screening Psikologis');
  yield pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: _text(
          'Hasil lengkap yang tersedia di Assessment Record. Skor screening adalah alat bantu, bukan diagnosis.'));
  if (rows.isEmpty) {
    yield _text('Belum ada hasil screening lengkap.');
    return;
  }
  yield _table([
    'WAKTU (WIB)',
    'JENIS SCREENING',
    'HASIL & INTERPRETASI'
  ], [
    for (final row in rows)
      [
        _text(
            row.date == null ? 'Tidak tercatat' : formatWibDateTime(row.date!)),
        _text(row.title),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          for (final score in row.scores) ...[
            _text('${score.instrument} - Total Score: ${score.total}',
                bold: true),
            pw.SizedBox(height: 4),
            _badge(score.interpretation, score.rank),
            pw.SizedBox(height: 5),
          ],
          if (row.crisis)
            _badge('Indikator risiko krisis - hubungi bantuan/profesional.', 4)
        ]),
      ]
  ], {
    0: const pw.FlexColumnWidth(1.1),
    1: const pw.FlexColumnWidth(1.6),
    2: const pw.FlexColumnWidth(2.8)
  });
}

Iterable<pw.Widget> _moodSection(List<MoodEntry> entries,
    Map<MoodValue, pw.MemoryImage> emoji, DateTime at) sync* {
  yield _heading('Riwayat Mood');
  yield pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 10),
      child: _text(
          'Emoji menunjukkan mood yang dicatat. Metrik lain ditampilkan sesuai data tersimpan. Waktu menggunakan WIB.'));
  final sorted = [...entries]..sort((a, b) => b.date.compareTo(a.date));
  if (sorted.isEmpty) {
    yield _text('Belum ada check-in mood.');
    return;
  }
  yield _table([
    'WAKTU',
    'MOOD',
    'TIDUR',
    'ENERGI',
    'CEMAS',
    'IRITABILITAS',
    'CATATAN'
  ], [
    for (final entry in sorted)
      for (final note in _chunks(entry.note))
        [
          _text(formatWibDateTime(entry.date)),
          pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
            pw.Image(emoji[entry.mood]!, width: 19, height: 19),
            pw.SizedBox(height: 3),
            _text(entry.mood.label)
          ]),
          _text('${entry.sleepHours.toStringAsFixed(1)} jam'),
          _text('${entry.energy}'),
          _text('${entry.anxiety}'),
          _text('${entry.irritability}'),
          _text(note.isEmpty ? '-' : note),
        ]
  ], {
    0: const pw.FlexColumnWidth(1.25),
    1: const pw.FlexColumnWidth(1),
    2: const pw.FlexColumnWidth(.85),
    3: const pw.FlexColumnWidth(.7),
    4: const pw.FlexColumnWidth(.7),
    5: const pw.FlexColumnWidth(1.15),
    6: const pw.FlexColumnWidth(1.4)
  });
  yield pw.NewPage();
  yield _heading('Mood Trend (Weekly)');
  yield _text(
      '7 hari terakhir. Mood: skala 1-5; tidur: 0-12 jam. Rata-rata per tanggal; tanggal tanpa check-in dibiarkan kosong.');
  yield pw.SizedBox(height: 12);
  yield _combo(entries, emoji, at);
  yield pw.SizedBox(height: 18);
  yield _heading('Symptoms Balance Map (Weekly)');
  yield _radar(entries, at);
  yield _text(
      'Rata-rata 7 hari. Mood dinormalisasi dari 1-5; energi, kecemasan, iritabilitas dari 0-10; tidur dari 0-12 jam. Kecemasan/iritabilitas lebih tinggi berarti gejala lebih kuat.');
}

Iterable<pw.Widget> _diarySection(List<DiaryEntry> entries) sync* {
  yield _heading('Catatan Harian');
  final sorted = [...entries]
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  if (sorted.isEmpty) {
    yield _text('Belum ada catatan diary.');
    return;
  }
  yield _table([
    'WAKTU (WIB)',
    'JUDUL',
    'CATATAN / TANGGAPAN'
  ], [
    for (final entry in sorted)
      for (final chunk in _chunks(
          '${entry.note}\nTanggapan profesional: ${entry.professionalFeedback ?? "Belum ada"}'))
        [
          _text(formatWibDateTime(entry.createdAt)),
          _text(entry.title, bold: true),
          _text(chunk),
        ]
  ], {
    0: const pw.FlexColumnWidth(1.1),
    1: const pw.FlexColumnWidth(1.2),
    2: const pw.FlexColumnWidth(3)
  });
}

Iterable<String> _chunks(String text) sync* {
  if (text.isEmpty) {
    yield '';
    return;
  }
  var buffer = <int>[];
  var breaks = 0;
  for (final rune in text.runes) {
    buffer.add(rune);
    if (rune == 10) breaks++;
    if (buffer.length >= 350 || breaks >= 8) {
      yield String.fromCharCodes(buffer);
      buffer = [];
      breaks = 0;
    }
  }
  if (buffer.isNotEmpty) yield String.fromCharCodes(buffer);
}

String _date(DateTime time) {
  final d = toWib(time);
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
  return '${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]} ${d.year}';
}

String _time(DateTime time) {
  final d = toWib(time);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

pw.Widget _combo(List<MoodEntry> entries, Map<MoodValue, pw.MemoryImage> emoji,
    DateTime at) {
  final days = moodWeek(entries, now: at);
  return pw.Column(children: [
    pw.Row(mainAxisAlignment: pw.MainAxisAlignment.center, children: [
      _text('Mood (1-5)', color: PdfColors.green700),
      pw.SizedBox(width: 22),
      _text('Tidur (0-12 jam)', color: PdfColors.blue700)
    ]),
    pw.SizedBox(height: 8),
    pw.SizedBox(
        height: 200,
        child: pw.Stack(children: [
          pw.Positioned(
              left: 24,
              top: 10,
              child: pw.CustomPaint(
                  size: const PdfPoint(440, 170),
                  painter: (canvas, size) {
                    const step = 440 / 7;
                    canvas.setLineWidth(.5);
                    canvas.setColor(_border);
                    for (var i = 0; i < 5; i++) {
                      canvas.drawLine(0, 5 + i * 40, 440, 5 + i * 40);
                      canvas.strokePath();
                    }
                    PdfPoint? previous;
                    for (var i = 0; i < days.length; i++) {
                      final day = days[i];
                      if (day.mood == null) {
                        previous = null;
                        continue;
                      }
                      final x = step * (i + .5);
                      final y = 5 + (day.mood! - 1) / 4 * 160;
                      canvas.setColor(PdfColors.blue100);
                      canvas.drawRect(
                          x - 12, 5, 24, (day.sleep! / 12).clamp(0, 1) * 160);
                      canvas.fillPath();
                      canvas.setColor(day.mood! >= 3.5
                          ? PdfColors.green600
                          : day.mood! >= 2.5
                              ? PdfColors.yellow700
                              : PdfColors.red700);
                      canvas.setLineWidth(2.5);
                      if (previous != null) {
                        canvas.drawLine(previous.x, previous.y, x, y);
                        canvas.strokePath();
                      }
                      canvas.drawEllipse(x, y, 3, 3);
                      canvas.fillPath();
                      previous = PdfPoint(x, y);
                    }
                  })),
          for (var i = 0; i < 5; i++)
            pw.Positioned(left: 0, top: 170 - i * 40, child: _text('${i + 1}')),
          for (var i = 0; i < 5; i++)
            pw.Positioned(
                right: 0,
                top: 164 - i * 40,
                child: pw.Image(emoji[MoodValue.values[4 - i]]!,
                    width: 18, height: 18)),
          for (var i = 0; i < 7; i++)
            pw.Positioned(
                left: 28 + i * 62,
                top: 186,
                child: _text('${days[i].date.day}/${days[i].date.month}')),
        ])),
  ]);
}

pw.Widget _radar(List<MoodEntry> entries, DateTime at) {
  final values = moodBalance(entries, now: at);
  if (values == null)
    return pw.Padding(
        padding: const pw.EdgeInsets.all(24),
        child: _text('Belum ada data pada 7 hari terakhir.'));
  final scaled = [
    values[0] / 10,
    values[1] / 10,
    values[2] / 12,
    values[3] / 10,
    values[4] / 10
  ];
  return pw.Column(children: [
    pw.SizedBox(
        height: 240,
        child: pw.Stack(children: [
          pw.Center(
              child: pw.CustomPaint(
                  size: const PdfPoint(300, 220),
                  painter: (canvas, size) {
                    PdfPoint point(int i, double scale) => PdfPoint(
                        150 +
                            math.cos(math.pi / 2 - i * math.pi * 2 / 5) *
                                85 *
                                scale,
                        110 +
                            math.sin(math.pi / 2 - i * math.pi * 2 / 5) *
                                85 *
                                scale);
                    void polygon(List<double> scales) {
                      for (var i = 0; i < 5; i++) {
                        final p = point(i, scales[i]);
                        if (i == 0) {
                          canvas.moveTo(p.x, p.y);
                        } else {
                          canvas.lineTo(p.x, p.y);
                        }
                      }
                      canvas.closePath();
                    }

                    canvas.setLineWidth(.6);
                    canvas.setColor(PdfColors.purple200);
                    for (var n = 1; n <= 5; n++) {
                      polygon(List.filled(5, n / 5));
                      canvas.strokePath();
                    }
                    for (var i = 0; i < 5; i++) {
                      final p = point(i, 1);
                      canvas.drawLine(150, 110, p.x, p.y);
                      canvas.strokePath();
                    }
                    canvas.setColor(PdfColors.purple100);
                    polygon(
                        scaled.map((v) => v.clamp(0, 1).toDouble()).toList());
                    canvas.fillPath();
                    canvas.setColor(PdfColors.purple700);
                    canvas.setLineWidth(1.8);
                    polygon(
                        scaled.map((v) => v.clamp(0, 1).toDouble()).toList());
                    canvas.strokePath();
                  })),
          pw.Positioned(left: 230, top: 0, child: _text('Mood', bold: true)),
          pw.Positioned(right: 80, top: 85, child: _text('Energy', bold: true)),
          pw.Positioned(
              right: 130, bottom: 7, child: _text('Sleep', bold: true)),
          pw.Positioned(
              left: 110, bottom: 7, child: _text('Irritability', bold: true)),
          pw.Positioned(left: 65, top: 85, child: _text('Anxiety', bold: true)),
        ])),
    _text(
        'Mood ${(values[0] / 2).toStringAsFixed(1)}/5 | Energy ${values[1].toStringAsFixed(1)}/10 | Sleep ${values[2].toStringAsFixed(1)} jam | Irritability ${values[3].toStringAsFixed(1)}/10 | Anxiety ${values[4].toStringAsFixed(1)}/10'),
  ]);
}
