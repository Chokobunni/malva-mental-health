import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/services/malva_api_client.dart';

class _DiaryMediaClient extends http.BaseClient {
  _DiaryMediaClient(this.status, this.body);
  final int status;
  final String body;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    expect(request.url.toString(), 'https://api.example.test/v1/diary-media');
    expect(request.headers['Authorization'], 'Bearer private-token');
    final upload = request as http.MultipartRequest;
    expect(upload.files.single.field, 'file');
    expect(upload.files.single.filename, 'drawing.png');
    expect(upload.files.single.contentType.toString(), 'image/png');
    expect(await upload.files.single.finalize().toBytes(), [1, 2, 3]);
    return http.StreamedResponse(Stream.value(utf8.encode(body)), status);
  }
}

void main() {
  test('private diary upload uses auth and resolves server path', () async {
    final api = MalvaApiClient(
        baseUrl: 'https://api.example.test',
        httpClient: _DiaryMediaClient(
            201, '{"url":"/v1/diary-media/owner/random.png"}'));
    expect(
        await api.uploadDiaryImage(
            accessToken: 'private-token',
            fileName: 'drawing.png',
            bytes: Uint8List.fromList([1, 2, 3]),
            mimeType: 'image/png'),
        'https://api.example.test/v1/diary-media/owner/random.png');
  });
  test('private diary upload preserves server validation errors', () async {
    final api = MalvaApiClient(
        baseUrl: 'https://api.example.test',
        httpClient:
            _DiaryMediaClient(413, '{"error":"Gambar maksimal 5 MiB."}'));
    await expectLater(
        api.uploadDiaryImage(
            accessToken: 'private-token',
            fileName: 'drawing.png',
            bytes: Uint8List.fromList([1, 2, 3]),
            mimeType: 'image/png'),
        throwsA(isA<MalvaApiException>()
            .having((e) => e.message, 'message', 'Gambar maksimal 5 MiB.')));
  });
}
