import 'dart:convert';
import 'package:flutter/material.dart';
import 'diary_catalog.dart';

/// Optional presentation data lives in the existing note; legacy writing stays plain.
class DiaryContent {
  const DiaryContent(
      {required this.text,
      this.font = 'roboto',
      this.size = 18,
      this.color = 0xff201b24,
      this.align = TextAlign.left,
      this.height = 1.6,
      this.palette,
      this.promptId,
      this.selfNote = '',
      this.tags = const [],
      this.appreciations = const [],
      this.brushColors = const [],
      this.inVault = false,
      this.media = const []});
  static const marker = '<!--malva-diary-v1:';
  final String text, font;
  final double size, height;
  final int color;
  final TextAlign align;
  final List<DiaryMedia> media;
  final String? palette;
  final int? promptId;
  final String selfNote;
  final List<String> tags;
  final List<int> appreciations, brushColors;
  final bool inVault;
  DiaryPrompt? get prompt =>
      promptId != null && promptId! >= 1 && promptId! <= 100
          ? diaryPrompts[promptId! - 1]
          : null;

  DiaryContent copyWith(
          {String? text, bool? inVault, List<int>? appreciations}) =>
      DiaryContent(
          text: text ?? this.text,
          font: font,
          size: size,
          color: color,
          align: align,
          height: height,
          media: media,
          palette: palette,
          promptId: promptId,
          selfNote: selfNote,
          tags: tags,
          appreciations: appreciations ?? this.appreciations,
          brushColors: brushColors,
          inVault: inVault ?? this.inVault);

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
          palette: const ['cerah', 'teduh', 'netral', 'redup', 'sendu']
                  .contains(data['palette'])
              ? data['palette'] as String
              : null,
          promptId:
              data['promptId'] is int && data['promptId'] >= 1 && data['promptId'] <= 100
                  ? data['promptId'] as int
                  : null,
          selfNote:
              data['selfNote'] is String ? data['selfNote'] as String : '',
          tags: data['tags'] is List
              ? (data['tags'] as List).whereType<String>().take(20).toList()
              : const [],
          appreciations: data['appreciations'] is List
              ? (data['appreciations'] as List)
                  .whereType<int>()
                  .where((id) => id >= 1 && id <= 100)
                  .toSet()
                  .toList()
              : const [],
          brushColors: data['brushColors'] is List
              ? (data['brushColors'] as List).whereType<int>().take(32).toList()
              : const [],
          inVault: data['inVault'] == true,
          media: (data['media'] as List)
              .whereType<Map>()
              .take(6)
              .map((m) => DiaryMedia(
                  url: m['url'].toString(),
                  colors: m['colors'] is List
                      ? (m['colors'] as List).whereType<int>().take(32).toList()
                      : const [],
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
        if (prompt != null) 'Pertanyaan: ${prompt!.question}',
        if (text.isNotEmpty) text,
        if (selfNote.isNotEmpty) 'Pesan penguat diri: $selfNote',
        if (tags.isNotEmpty) tags.map((tag) => '#$tag').join(' '),
        if (media.isNotEmpty) '[${media.length} gambar terlampir]'
      ].join('\n');
  String encode() {
    if (font == 'roboto' &&
        size == 18 &&
        color == 0xff201b24 &&
        align == TextAlign.left &&
        height == 1.6 &&
        media.isEmpty &&
        palette == null &&
        promptId == null &&
        selfNote.isEmpty &&
        tags.isEmpty &&
        appreciations.isEmpty &&
        brushColors.isEmpty &&
        !inVault) return text;
    final data = {
      'font': font,
      'size': size,
      'color': color,
      'align': align.name,
      'height': height,
      if (palette != null) 'palette': palette,
      if (promptId != null) 'promptId': promptId,
      if (selfNote.isNotEmpty) 'selfNote': selfNote,
      if (tags.isNotEmpty) 'tags': tags,
      if (appreciations.isNotEmpty) 'appreciations': appreciations,
      if (brushColors.isNotEmpty) 'brushColors': brushColors,
      if (inVault) 'inVault': true,
      'media': media
          .map((m) => {
                'url': m.url,
                'kind': m.kind,
                if (m.colors.isNotEmpty) 'colors': m.colors
              })
          .toList()
    };
    return '$text${text.isEmpty ? '' : '\n\n'}$marker${base64Url.encode(utf8.encode(jsonEncode(data)))}-->';
  }
}

class DiaryMedia {
  const DiaryMedia(
      {required this.url, this.kind = 'photo', this.colors = const []});
  final String url, kind;
  final List<int> colors;
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
