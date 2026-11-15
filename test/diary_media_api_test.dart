import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
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
  test('private drawing read uses authorization and does not follow redirects',
      () async {
    final api = MalvaApiClient(
        baseUrl: 'https://api.example.test',
        httpClient: MockClient((request) async {
          expect(request.url.toString(),
              'https://api.example.test/v1/diary-media/owner/drawing.png');
          expect(request.headers['Authorization'], 'Bearer private-token');
          expect(request.followRedirects, isFalse);
          return http.Response.bytes([1, 2, 3], 200);
        }));
    expect(
        await api.fetchDiaryImage(
            accessToken: 'private-token',
            url: '/v1/diary-media/owner/drawing.png'),
        [1, 2, 3]);
  });

  for (final url in [
    'https://external.test/v1/diary-media/owner/drawing.png',
    '//external.test/v1/diary-media/owner/drawing.png',
    '/v1/messages',
    '/v1/diary-media/owner/drawing.png?secret=1',
    '/v1/diary-media/owner/drawing.png#fragment',
  ]) {
    test('private drawing rejects a URL outside its endpoint: $url', () async {
      var requests = 0;
      final api = MalvaApiClient(
          baseUrl: 'https://api.example.test',
          httpClient: MockClient((request) async {
            requests++;
            return http.Response('', 200);
          }));
      await expectLater(
          api.fetchDiaryImage(accessToken: 'private-token', url: url),
          throwsA(isA<MalvaApiException>()));
      expect(requests, 0);
    });
  }

  for (final status in [302, 403, 404]) {
    test(
        'private drawing rejects HTTP $status instead of returning error bytes',
        () async {
      final api = MalvaApiClient(
          baseUrl: 'https://api.example.test',
          httpClient: MockClient((request) async => http.Response('', status,
              headers: {'location': 'https://external.test/image.png'})));
      await expectLater(
          api.fetchDiaryImage(
              accessToken: 'private-token',
              url: '/v1/diary-media/owner/drawing.png'),
          throwsA(isA<MalvaApiException>()));
    });
  }

  test('private drawing response from an old account is rejected', () async {
    final response = Completer<http.Response>();
    final api = MalvaApiClient(
        baseUrl: 'https://api.example.test',
        httpClient: MockClient((_) => response.future));
    final reading = api.fetchDiaryImage(
        accessToken: 'private-token', url: '/v1/diary-media/owner/drawing.png');
    api.setRefreshToken('other-account');
    response.complete(http.Response.bytes([1, 2, 3], 200));
    await expectLater(reading, throwsA(isA<MalvaApiException>()));
  });

  test('private drawing rejects a response larger than the upload limit',
      () async {
    final api = MalvaApiClient(
        baseUrl: 'https://api.example.test',
        httpClient: MockClient((_) async =>
            http.Response.bytes(Uint8List(5 * 1024 * 1024 + 1), 200)));
    await expectLater(
        api.fetchDiaryImage(
            accessToken: 'private-token',
            url: '/v1/diary-media/owner/drawing.png'),
        throwsA(isA<MalvaApiException>()));
  });

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
