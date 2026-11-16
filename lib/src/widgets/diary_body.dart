import 'package:flutter/material.dart';
import '../models/diary_content.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import 'diary_design.dart';

class DiaryBody extends StatelessWidget {
  const DiaryBody(
      {super.key,
      required this.note,
      required this.api,
      this.token,
      this.compactMedia = false});
  final String note;
  final MalvaApiClient api;
  final String? token;
  final bool compactMedia;
  @override
  Widget build(BuildContext context) {
    final content = DiaryContent.parse(note);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (content.prompt != null)
        Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: DiaryCard(
                padding: const EdgeInsets.all(14),
                color: const Color(0xfffaf5ff),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(content.prompt!.category.toUpperCase(),
                          style: const TextStyle(
                              fontSize: 10,
                              color: diaryPurple,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      SelectableText('“${content.prompt!.question}”',
                          style: const TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: diaryPlum,
                              height: 1.6))
                    ]))),
      if (content.text.isNotEmpty)
        SelectableText(content.text,
            textAlign: content.align, style: content.style),
      for (final item in content.media)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: compactMedia ? 240 : double.infinity),
                    child: DiaryImage(
                        media: item,
                        api: api,
                        token: token,
                        preview: compactMedia)))),
      if (content.tags.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              for (final tag in content.tags)
                Chip(label: Text('#$tag', style: const TextStyle(fontSize: 11)))
            ])),
      if (content.selfNote.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(top: 18),
            child: DiaryCard(
                padding: const EdgeInsets.all(16),
                color: const Color(0xfffaf5ff),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('PESAN PENGUAT DIRI',
                          style: TextStyle(
                              fontSize: 10,
                              color: diaryPurple,
                              fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      SelectableText(content.selfNote,
                          style: const TextStyle(
                              fontSize: 13, color: diaryPlum, height: 1.6))
                    ]))),
    ]);
  }
}

class DiaryImage extends StatelessWidget {
  const DiaryImage(
      {super.key,
      required this.media,
      required this.api,
      this.token,
      this.onEdit,
      this.onRemove,
      this.preview = false});
  final DiaryMedia media;
  final MalvaApiClient api;
  final String? token;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final bool preview;
  @override
  Widget build(BuildContext context) {
    final url = media.resolve(api.baseUri);
    final image = ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: url == null || token == null || token!.isEmpty
            ? const SizedBox(
                height: 100,
                child: Center(child: Text('Masuk untuk melihat gambar.')))
            : Image.network(url.toString(),
                headers: {'Authorization': 'Bearer $token'},
                cacheWidth: preview ? 720 : null,
                fit: BoxFit.contain,
                semanticLabel:
                    media.kind == 'drawing' ? 'Gambar diary' : 'Foto diary',
                errorBuilder: (_, __, ___) => const SizedBox(
                    height: 100,
                    child: Center(
                        child: Text(
                            'Gambar belum dapat dimuat. Buka kembali diary untuk mencoba lagi.')))));
    return Stack(children: [
      Container(
          constraints: BoxConstraints(maxHeight: preview ? 180 : 360),
          width: double.infinity,
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xffe8daef))),
          child: image),
      if (onRemove != null)
        Positioned(
            top: 4,
            right: 4,
            child: IconButton.filledTonal(
                tooltip: 'Hapus lampiran',
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 20))),
      if (onEdit != null)
        Positioned(
            top: 4,
            right: onRemove == null ? 4 : 52,
            child: IconButton.filledTonal(
                tooltip: media.kind == 'drawing' ? 'Edit gambar' : 'Ganti foto',
                onPressed: onEdit,
                icon: Icon(
                    media.kind == 'drawing'
                        ? Icons.edit_outlined
                        : Icons.photo_library_outlined,
                    size: 20))),
      Positioned(
          left: 10,
          bottom: 8,
          child: IgnorePointer(
              child: DecoratedBox(
                  decoration: BoxDecoration(
                      color: MalvaColors.paper.withValues(alpha: .92),
                      borderRadius: BorderRadius.circular(20)),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(
                            media.kind == 'drawing'
                                ? Icons.draw_outlined
                                : Icons.image_outlined,
                            size: 14,
                            color: MalvaColors.seed),
                        const SizedBox(width: 4),
                        Text(media.kind == 'drawing' ? 'Gambar' : 'Foto',
                            style: const TextStyle(
                                fontSize: 11, color: MalvaColors.plum))
                      ]))))),
    ]);
  }
}
