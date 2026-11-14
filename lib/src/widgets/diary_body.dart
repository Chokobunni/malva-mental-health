import 'package:flutter/material.dart';
import '../models/diary_content.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';

class DiaryBody extends StatelessWidget {
  const DiaryBody(
      {super.key, required this.note, required this.api, this.token});
  final String note;
  final MalvaApiClient api;
  final String? token;
  @override
  Widget build(BuildContext context) {
    final content = DiaryContent.parse(note);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (content.text.isNotEmpty)
        SelectableText(content.text,
            textAlign: content.align, style: content.style),
      for (final item in content.media)
        Padding(
            padding: const EdgeInsets.only(top: 12),
            child: DiaryImage(media: item, api: api, token: token)),
    ]);
  }
}

class DiaryImage extends StatelessWidget {
  const DiaryImage(
      {super.key,
      required this.media,
      required this.api,
      this.token,
      this.onRemove});
  final DiaryMedia media;
  final MalvaApiClient api;
  final String? token;
  final VoidCallback? onRemove;
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
          constraints: const BoxConstraints(maxHeight: 360),
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
