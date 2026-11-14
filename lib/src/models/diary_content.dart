import 'dart:convert';
import 'package:flutter/material.dart';

/// Optional presentation data lives in the existing note; legacy writing stays plain.
class DiaryContent {
  const DiaryContent(
      {required this.text,
      this.font = 'roboto',
      this.size = 18,
      this.color = 0xff201b24,
      this.align = TextAlign.left,
      this.height = 1.6,
      this.media = const []});
  static const marker = '<!--malva-diary-v1:';
  final String text, font;
  final double size, height;
  final int color;
  final TextAlign align;
  final List<DiaryMedia> media;

  factory DiaryContent.parse(String note) {
    final start = note.lastIndexOf(marker);
    if (start < 0 ||
        !note.endsWith('-->') ||
        (start > 0 && !note.substring(0, start).endsWith('\n\n')))
      return DiaryContent(text: note);
    try {
      final encoded = note.substring(start + marker.length, note.length - 3);
      final data = jsonDecode(
          utf8.decode(base64Url.decode(base64Url.normalize(encoded)))) as Map;
      if (data['font'] is! String || data['media'] is! List) {
        return DiaryContent(text: note);
      }
      return DiaryContent(
          text: start == 0 ? '' : note.substring(0, start - 2),
          font: data['font'] == 'jakarta' ? 'jakarta' : 'roboto',
          size: (data['size'] as num).toDouble().clamp(14, 32),
          color: (data['color'] as num).toInt() | 0xff000000,
          align: switch (data['align']) {
            'center' => TextAlign.center,
            'right' => TextAlign.right,
            _ => TextAlign.left
          },
          height: (data['height'] as num).toDouble().clamp(1.2, 2.2),
          media: (data['media'] as List)
              .whereType<Map>()
              .take(6)
              .map((m) => DiaryMedia(
                  url: m['url'].toString(),
                  kind: m['kind'] == 'drawing' ? 'drawing' : 'photo'))
              .toList());
    } on Object {
      return DiaryContent(text: note);
    }
  }

  TextStyle get style => TextStyle(
      fontFamily: font == 'jakarta' ? 'PlusJakartaSans' : 'Roboto',
      fontSize: size,
      color: Color(color),
      height: height);
  String get plainText => [
        if (text.isNotEmpty) text,
        if (media.isNotEmpty) '[${media.length} gambar terlampir]'
      ].join('\n');
  String encode() {
    if (font == 'roboto' &&
        size == 18 &&
        color == 0xff201b24 &&
        align == TextAlign.left &&
        height == 1.6 &&
        media.isEmpty) return text;
    final data = {
      'font': font,
      'size': size,
      'color': color,
      'align': align.name,
      'height': height,
      'media': media.map((m) => {'url': m.url, 'kind': m.kind}).toList()
    };
    return '$text${text.isEmpty ? '' : '\n\n'}$marker${base64Url.encode(utf8.encode(jsonEncode(data)))}-->';
  }
}

class DiaryMedia {
  const DiaryMedia({required this.url, this.kind = 'photo'});
  final String url, kind;
  Uri? resolve(Uri api) {
    final resolved = api.resolve(url);
    if (resolved.origin != api.origin ||
        resolved.hasQuery ||
        resolved.hasFragment ||
        !RegExp(r'^/v1/diary-media/[a-zA-Z0-9_-]+/[a-zA-Z0-9_.-]+$')
            .hasMatch(resolved.path)) return null;
    return resolved;
  }
}
