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
      this.compactMedia = false,
      this.mediaGrid = false});
  final String note;
  final MalvaApiClient api;
  final String? token;
  final bool compactMedia;
  final bool mediaGrid;
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
      if (mediaGrid && content.media.isNotEmpty)
        LayoutBuilder(builder: (context, constraints) {
          final size = ((constraints.maxWidth - 10) / 2).clamp(0.0, 180.0);
          return Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Wrap(spacing: 10, runSpacing: 10, children: [
                for (final kind in ['drawing', 'photo'])
                  for (final item in content.media.where((m) => m.kind == kind))
                    DiaryMediaTile(
                        media: item, api: api, token: token, size: size),
              ]));
        })
      else
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
            child: DiaryTags(tags: content.tags)),
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

class DiaryTags extends StatelessWidget {
  const DiaryTags({super.key, required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) =>
      Wrap(spacing: 6, runSpacing: 6, children: [
        for (final tag in tags)
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
              decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xffddd0e5)),
                  borderRadius: BorderRadius.circular(8)),
              child: Text('#$tag', style: const TextStyle(fontSize: 11))),
      ]);
}

class DiaryMediaTile extends StatelessWidget {
  const DiaryMediaTile(
      {super.key,
      required this.media,
      required this.api,
      this.token,
      required this.size});

  final DiaryMedia media;
  final MalvaApiClient api;
  final String? token;
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(
      width: size,
      child: Column(children: [
        SizedBox.square(
            dimension: size,
            child: DiaryImage(
                media: media,
                api: api,
                token: token,
                preview: true,
                showLabel: false)),
        const SizedBox(height: 5),
        Text(media.kind == 'drawing' ? 'Sketsa' : 'Foto',
            style: const TextStyle(color: Color(0xff625a6b), fontSize: 11)),
      ]));
}

class DiaryImage extends StatelessWidget {
  const DiaryImage(
      {super.key,
      required this.media,
      required this.api,
      this.token,
      this.onEdit,
      this.onRemove,
      this.preview = false,
      this.showLabel = true});
  final DiaryMedia media;
  final MalvaApiClient api;
  final String? token;
  final VoidCallback? onEdit;
  final VoidCallback? onRemove;
  final bool preview;
  final bool showLabel;
  @override
  Widget build(BuildContext context) {
    final url = media.resolve(api.baseUri);
    final radius = BorderRadius.circular(showLabel ? 18 : 14);
    final image = ClipRRect(
        borderRadius: radius,
        child: url == null || token == null || token!.isEmpty
            ? !showLabel
                ? const Center(
                    child: Icon(Icons.lock_outline,
                        semanticLabel: 'Masuk untuk melihat gambar'))
                : const SizedBox(
                    height: 100,
                    child: Center(child: Text('Masuk untuk melihat gambar.')))
            : Image.network(url.toString(),
                headers: {'Authorization': 'Bearer $token'},
                cacheWidth: preview ? 720 : null,
                fit: BoxFit.contain,
                semanticLabel:
                    media.kind == 'drawing' ? 'Gambar jurnal' : 'Foto jurnal',
                errorBuilder: (_, __, ___) => !showLabel
                    ? const Center(
                        child: Icon(Icons.broken_image_outlined,
                            semanticLabel: 'Gambar belum dapat dimuat'))
                    : const SizedBox(
                        height: 100,
                        child: Center(
                            child: Text(
                                'Gambar belum dapat dimuat. Buka kembali jurnal untuk mencoba lagi.')))));
    return Stack(fit: StackFit.passthrough, children: [
      Container(
          constraints: BoxConstraints(maxHeight: preview ? 180 : 360),
          width: double.infinity,
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: radius,
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
      if (showLabel)
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
