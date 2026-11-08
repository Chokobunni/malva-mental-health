import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../assessment_engine.dart';
import '../models.dart';
import '../platform/contracts/ports.dart';
import '../time/wib.dart';
import 'health_pdf_report.dart';

// ============================================================
// EXPORT SERVICE
// ============================================================
//
// Pembentuk CSV/JSON tetap murni (tanpa I/O). Penyimpanan/pembagian berkas
// didelegasikan ke [FileExporter] (port platform): mobile memakai temp file +
// share sheet, web memakai unduhan browser. Berkas ini TIDAK menyentuh
// I/O native/`path_provider`/`share_plus` sehingga aman dikompilasi ke web.
// ============================================================

class ExportService {
  ExportService(this._exporter);

  final FileExporter _exporter;

  Future<void> shareHealthReport({
    required String title,
    required String filename,
    List<MoodEntry>? moods,
    List<MedicationLog>? medicationLogs,
    List<ScreeningPdfRow>? screenings,
    List<DiaryEntry>? diaryEntries,
    String? patientName,
    bool Function()? canShare,
  }) async {
    final bytes = await buildHealthReportPdf(
        title: title,
        moods: moods,
        medicationLogs: medicationLogs,
        screenings: screenings,
        diaries: diaryEntries,
        patientName: patientName);
    if (canShare != null && !canShare()) return;
    await _exporter.saveBytes(
        filename: filename,
        bytes: bytes,
        mimeType: 'application/pdf',
        subject: title);
  }

  Future<void> sharePdf(
      {required String title,
      required List<String> lines,
      required String filename,
      bool Function()? canShare}) async {
    final bytes = await buildPdf(title: title, lines: lines);
    if (canShare != null && !canShare()) return;
    await _exporter.saveBytes(
        filename: filename,
        bytes: bytes,
        mimeType: 'application/pdf',
        subject: title);
  }

  Future<Uint8List> buildPdf(
      {required String title, required List<String> lines}) async {
    final base =
        pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-regular.ttf'));
    final bold =
        pw.Font.ttf(await rootBundle.load('assets/fonts/roboto-bold.ttf'));
    final document = pw.Document(title: title, author: 'Malva');
    final stamp = formatWibDateTime(wibNow());
    document.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(40),
      maxPages: 1000,
      theme: pw.ThemeData.withFont(base: base, bold: bold),
      header: (_) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 18),
          child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('MALVA',
                    style: const pw.TextStyle(
                        color: PdfColors.purple,
                        fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 5),
                pw.Text(title,
                    style: const pw.TextStyle(
                        fontSize: 19, fontWeight: pw.FontWeight.bold)),
                pw.Text('Diekspor $stamp WIB',
                    style: const pw.TextStyle(
                        fontSize: 9, color: PdfColors.grey700)),
                pw.Divider(color: PdfColors.purple),
              ])),
      footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 10),
          child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Pribadi - dibagikan atas pilihan pemilik data',
                    style: const pw.TextStyle(fontSize: 8)),
                pw.Text('${context.pageNumber}/${context.pagesCount}',
                    style: const pw.TextStyle(fontSize: 8)),
              ])),
      build: (_) => [
        for (final line in lines.isEmpty ? ['Belum ada data.'] : lines)
          for (final chunk in _pdfChunks(line))
            pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 8),
                child: pw.Text(chunk,
                    style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 3))),
      ],
    ));
    return document.save();
  }

  // Bound characters and explicit lines so each block fits on a PDF page.
  Iterable<String> _pdfChunks(String text) sync* {
    if (text.isEmpty) {
      yield '';
      return;
    }
    var block = <int>[];
    var breaks = 0;
    for (final rune in text.runes) {
      block.add(rune);
      if (rune == 10) breaks++;
      if (block.length == 600 || breaks == 12) {
        yield String.fromCharCodes(block);
        block = <int>[];
        breaks = 0;
      }
    }
    if (block.isNotEmpty) yield String.fromCharCodes(block);
  }
  // ----------------------------------------------------------
  // CSV EXPORTS
  // ----------------------------------------------------------

  String exportMoodCsv(List<MoodEntry> entries) {
    final buffer = StringBuffer();
    buffer.writeln('Date,Mood,Sleep Hours,Energy,Anxiety,Irritability,Note');
    for (final e in entries) {
      buffer.writeln(
        '${wibIso(e.date)},'
        '${e.mood.name},'
        '${e.sleepHours},'
        '${e.energy},'
        '${e.anxiety},'
        '${e.irritability},'
        '"${e.note.replaceAll('"', '""')}"',
      );
    }
    return buffer.toString();
  }

  String exportScreeningCsv(List<ScreeningBundle> bundles) {
    final buffer = StringBuffer();
    buffer.writeln(
        'ID,Date,PHQ9 Score,PHQ9 Level,GAD7 Score,GAD7 Level,Crisis Flag,Source');
    for (final b in bundles) {
      buffer.writeln(
        '"${b.id}",'
        '${wibIso(b.createdAt)},'
        '${b.phq9.score},'
        '"${b.phq9.level}",'
        '${b.gad7.score},'
        '"${b.gad7.level}",'
        '${b.crisisFlag},'
        '"${b.source}"',
      );
    }
    return buffer.toString();
  }

  String exportMedicationLogCsv(List<MedicationLog> logs) {
    final buffer = StringBuffer();
    buffer.writeln('Medication ID,Medication Name,Taken At,Status');
    for (final log in logs) {
      buffer.writeln(
        '"${log.medicationId}",'
        '"${log.medicationName}",'
        '${wibIso(log.takenAt)},'
        '${log.status}',
      );
    }
    return buffer.toString();
  }

  String exportDiaryCsv(List<DiaryEntry> entries) {
    final buffer = StringBuffer();
    buffer.writeln('ID,Date,Title,Note,Professional Feedback');
    for (final e in entries) {
      buffer.writeln(
        '"${e.id}",'
        '${wibIso(e.createdAt)},'
        '"${e.title.replaceAll('"', '""')}",'
        '"${e.note.replaceAll('"', '""')}",'
        '"${(e.professionalFeedback ?? '').replaceAll('"', '""')}"',
      );
    }
    return buffer.toString();
  }

  // ----------------------------------------------------------
  // JSON EXPORT
  // ----------------------------------------------------------

  String exportAllJson({
    required PatientProfile patient,
    required List<MoodEntry> moods,
    required List<ScreeningBundle> screenings,
    required List<MedicationLog> medicationLogs,
    required List<DiaryEntry> diaryEntries,
  }) {
    final data = {
      'exportedAt': wibIso(wibNow()),
      'patient': {
        'id': patient.id,
        'name': patient.name,
        'age': patient.age,
        'diagnosis': patient.diagnosisSummary,
      },
      'moodEntries': moods
          .map((e) => {
                'date': wibIso(e.date),
                'mood': e.mood.name,
                'sleepHours': e.sleepHours,
                'energy': e.energy,
                'anxiety': e.anxiety,
                'irritability': e.irritability,
                'note': e.note,
              })
          .toList(),
      'screenings': screenings
          .map((b) => {
                'id': b.id,
                'createdAt': wibIso(b.createdAt),
                'phq9Score': b.phq9.score,
                'phq9Level': b.phq9.level,
                'gad7Score': b.gad7.score,
                'gad7Level': b.gad7.level,
                'crisisFlag': b.crisisFlag,
                'source': b.source,
              })
          .toList(),
      'medicationLogs': medicationLogs
          .map((l) => {
                'medicationId': l.medicationId,
                'medicationName': l.medicationName,
                'takenAt': wibIso(l.takenAt),
                'status': l.status,
              })
          .toList(),
      'diaryEntries': diaryEntries
          .map((e) => {
                'id': e.id,
                'createdAt': wibIso(e.createdAt),
                'title': e.title,
                'note': e.note,
              })
          .toList(),
    };
    return const JsonEncoder.withIndent('  ').convert(data);
  }

  // ----------------------------------------------------------
  // SHARE / SAVE
  // ----------------------------------------------------------

  Future<void> shareCsv(String csv, String filename) async {
    await _exporter.saveText(
      filename: filename,
      content: csv,
      mimeType: 'text/csv',
    );
  }

  Future<void> shareJson(String json, String filename) async {
    await _exporter.saveText(
      filename: filename,
      content: json,
      mimeType: 'application/json',
    );
  }
}
