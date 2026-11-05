import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../contracts/ports.dart';

/// [FileExporter] mobile/desktop: tulis ke berkas temp lalu buka lembar
/// bagikan Android (perilaku identik dengan `ExportService.shareCsv`).
class ShareFileExporter implements FileExporter {
  const ShareFileExporter();

  @override
  Future<void> saveBytes(
      {required String filename,
      required Uint8List bytes,
      required String mimeType,
      String? subject}) async {
    final tempDir = await getTemporaryDirectory();
    final safeName = filename.replaceAll(RegExp(r'[^a-zA-Z0-9._ -]'), '_');
    final directory = await Directory('${tempDir.path}/malva-chat').create();
    final file = File('${directory.path}/$safeName');
    await file.writeAsBytes(bytes, flush: true);
    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path, mimeType: mimeType)],
      subject: subject ?? safeName,
    ));
  }

  @override
  Future<void> saveText({
    required String filename,
    required String content,
    required String mimeType,
    String? subject,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/$filename');
    await file.writeAsString(content);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: subject ?? filename,
      ),
    );
  }
}
