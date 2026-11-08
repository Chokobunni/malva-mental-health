import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/services/export_service.dart';

class _Exporter implements FileExporter {
  Uint8List? bytes;
  String? filename;
  String? mime;
  @override
  Future<void> saveBytes(
      {required String filename,
      required Uint8List bytes,
      required String mimeType,
      String? subject}) async {
    this.filename = filename;
    this.bytes = bytes;
    mime = mimeType;
  }

  @override
  Future<void> saveText(
          {required String filename,
          required String content,
          required String mimeType,
          String? subject}) async =>
      fail('PDF must be binary');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('does not share a PDF after the owner changed during generation',
      () async {
    final port = _Exporter();
    var allowed = true;
    final pending = ExportService(port).sharePdf(
      title: 'Data pribadi',
      filename: 'private.pdf',
      lines: ['Catatan'],
      canShare: () => allowed,
    );
    allowed = false;
    await pending;
    expect(port.bytes, isNull);
  });
  test('exports a real paginated PDF with long notes through binary port',
      () async {
    final port = _Exporter();
    await ExportService(port).sharePdf(
      title: 'Riwayat screening',
      filename: 'screening.pdf',
      lines: [
        'WHO-5: 13/25 (52%) - Kesejahteraan baik',
        'PHQ-9: 12/27 - Sedang; GAD-7: 11/21 - Sedang',
        ...List.generate(
            120, (i) => 'Catatan $i: ${'Pengalaman dan perasaan. ' * 35}'),
        List.generate(150, (i) => 'Baris $i').join('\n'),
        'AKHIR LAPORAN',
      ],
    );
    expect(port.filename, 'screening.pdf');
    expect(port.mime, 'application/pdf');
    final source = latin1.decode(port.bytes!);
    expect(source.startsWith('%PDF-'), isTrue);
    expect(source.trimRight().endsWith('%%EOF'), isTrue);
    expect(
        RegExp(r'/Type\s*/Page\b').allMatches(source).length, greaterThan(2));
    final output = Platform.environment['MALVA_PDF_QA_OUTPUT'];
    if (output != null) await File(output).writeAsBytes(port.bytes!);
  });
}
