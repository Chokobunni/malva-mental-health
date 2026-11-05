import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../contracts/ports.dart';

/// [FileExporter] web: unduhan nyata lewat `Blob` + `<a download>`.
///
/// Ekspor CSV/JSON/teks BISA berjalan di browser — jadi di web fitur ini
/// berfungsi, bukan disembunyikan. Tidak melempar untuk kasus normal.
class BrowserFileExporter implements FileExporter {
  const BrowserFileExporter();

  @override
  Future<void> saveText({
    required String filename,
    required String content,
    required String mimeType,
    String? subject,
  }) async {
    final bytes = Uint8List.fromList(utf8.encode(content));
    await saveBytes(
        filename: filename, bytes: bytes, mimeType: mimeType, subject: subject);
  }

  @override
  Future<void> saveBytes(
      {required String filename,
      required Uint8List bytes,
      required String mimeType,
      String? subject}) async {
    final blob = web.Blob(
      <JSAny>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = filename
      ..style.display = 'none';
    // Lampirkan sementara agar click() dihormati semua browser, lalu bersihkan.
    web.document.body?.append(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
  }
}
