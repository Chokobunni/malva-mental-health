import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models/diary_content.dart';

void main() {
  test('media-only content survives server whitespace normalization', () {
    const content = DiaryContent(
        text: '', media: [DiaryMedia(url: '/v1/diary-media/p/a.png')]);
    final decoded = DiaryContent.parse(content.encode().trim());
    expect(decoded.text, isEmpty);
    expect(decoded.media.single.url, '/v1/diary-media/p/a.png');
  });
  test('legacy diary text survives without metadata', () {
    final content = DiaryContent.parse('Cerita lama\nBaris kedua');
    expect(content.text, 'Cerita lama\nBaris kedua');
    expect(content.media, isEmpty);
    expect(content.encode(), content.text);
  });
  test('writing, media and typography round trip through existing note', () {
    const original = DiaryContent(
        text: 'Hari yang penuh warna',
        font: 'jakarta',
        size: 22,
        color: 0xff5d2e7e,
        align: TextAlign.center,
        height: 1.8,
        media: [
          DiaryMedia(url: '/v1/diary-media/p/photo.png', kind: 'drawing')
        ]);
    final decoded = DiaryContent.parse(original.encode());
    expect(decoded.text, original.text);
    expect(decoded.media.single.url, original.media.single.url);
    expect(decoded.media.single.kind, 'drawing');
    expect(decoded.font, 'jakarta');
    expect(decoded.align, TextAlign.center);
    expect(decoded.size, 22);
    expect(decoded.color, 0xff5d2e7e);
    expect(decoded.height, 1.8);
  });
  test('malformed and unrecognized metadata stays readable', () {
    for (final value in [
      'Cerita\n\n<!--malva-diary-v1:broken-->',
      'Cerita <!--other-->'
    ]) {
      expect(DiaryContent.parse(value).text, value);
    }
  });
  test('attachment fetch only sends credentials to the owning API', () {
    expect(
        const DiaryMedia(url: 'https://evil.test/v1/diary-media/p/a.png')
            .resolve(Uri.parse('https://api.malva.web.id')),
        isNull);
    expect(
        const DiaryMedia(url: '/uploads/public.png')
            .resolve(Uri.parse('https://api.malva.web.id')),
        isNull);
    expect(
        const DiaryMedia(url: '/v1/diary-media/p/a.png')
            .resolve(Uri.parse('https://api.malva.web.id'))
            .toString(),
        'https://api.malva.web.id/v1/diary-media/p/a.png');
  });
}
