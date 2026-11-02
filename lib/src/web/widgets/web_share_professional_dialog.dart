import 'package:flutter/material.dart';

import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';

/// Pesan ramah untuk kegagalan berbagi hasil ke profesional.
///
/// 403/402 = belum ada paket sesi aktif (server menolak berbagi). Pesan ini
/// memberi langkah berikutnya, bukan error mentah.
String webShareErrorMessage(Object error) {
  if (error is MalvaApiException &&
      (error.statusCode == 403 || error.statusCode == 402)) {
    return 'Butuh paket sesi aktif untuk membagikan hasil ke profesional. '
        'Aktifkan paket lalu coba lagi.';
  }
  return friendlyErrorMessage(error);
}

/// Dialog memilih profesional tujuan berbagi (dipakai asesmen & worksheet).
///
/// Mengembalikan profesional yang dipilih, atau `null` bila dibatalkan.
Future<BackendPatientProfessionalLink?> showWebShareProfessionalDialog(
  BuildContext context, {
  required List<BackendPatientProfessionalLink> links,
  String title = 'Bagikan hasil',
  String description = 'Pilih profesional yang boleh melihat hasil ini.',
}) {
  return showDialog<BackendPatientProfessionalLink>(
    context: context,
    builder: (BuildContext dialogContext) => _WebShareDialog(
      links: links,
      title: title,
      description: description,
    ),
  );
}

class _WebShareDialog extends StatefulWidget {
  const _WebShareDialog({
    required this.links,
    required this.title,
    required this.description,
  });

  final List<BackendPatientProfessionalLink> links;
  final String title;
  final String description;

  @override
  State<_WebShareDialog> createState() => _WebShareDialogState();
}

class _WebShareDialogState extends State<_WebShareDialog> {
  late BackendPatientProfessionalLink _selected = widget.links.first;

  String _valueOf(BackendPatientProfessionalLink link) =>
      link.professionalUserId.isNotEmpty
          ? link.professionalUserId
          : link.professionalId;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title,
          style: const TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              widget.description,
              style: const TextStyle(fontSize: 12.5, height: 1.5),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              key: const Key('web-share-professional'),
              initialValue: _valueOf(_selected),
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Profesional'),
              items: widget.links
                  .map(
                    (BackendPatientProfessionalLink link) =>
                        DropdownMenuItem<String>(
                      value: _valueOf(link),
                      child: Text(
                        link.professionalDisplayName.isEmpty
                            ? link.professionalId
                            : link.professionalDisplayName,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (String? value) {
                if (value == null) return;
                setState(() {
                  _selected = widget.links.firstWhere(
                    (BackendPatientProfessionalLink link) =>
                        _valueOf(link) == value,
                    orElse: () => widget.links.first,
                  );
                });
              },
            ),
            const SizedBox(height: 10),
            const Text(
              'Profesional hanya bisa melihat hasil yang Anda bagikan, bukan '
              'seluruh riwayat Anda.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF8B8194)),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Batal'),
        ),
        FilledButton(
          key: const Key('web-share-confirm'),
          onPressed: () => Navigator.of(context).pop(_selected),
          child: const Text('Bagikan'),
        ),
      ],
    );
  }
}

/// Tombol unduh ringkasan (dipakai dialog sukses & detail riwayat).
class WebDownloadSummaryButton extends StatelessWidget {
  const WebDownloadSummaryButton({
    super.key,
    required this.onPressed,
    this.label = 'Unduh ringkasan',
  });

  final VoidCallback onPressed;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.download_rounded, size: 17),
      label: Text(label),
    );
  }
}

/// Ikon kecil berwarna untuk header dialog (konsisten dengan tema Malva).
class WebDialogBadge extends StatelessWidget {
  const WebDialogBadge({
    super.key,
    required this.icon,
    this.color = MalvaColors.seed,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(11),
      ),
      child: Icon(icon, color: color, size: 21),
    );
  }
}
