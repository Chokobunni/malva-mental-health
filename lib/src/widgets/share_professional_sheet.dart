import 'package:flutter/material.dart';

import '../services/malva_api_client.dart';
import '../services/server_clock.dart';
import 'professional_avatar.dart';

typedef ShareRecipient = ({String id, String name, String photoUrl});

List<ShareRecipient> eligibleShareRecipients({
  required List<BackendCarePackage> packages,
  required List<BackendPatientProfessionalLink> links,
  required List<BackendCareSession> sessions,
  required DateTime now,
}) {
  final packageIds = {
    for (final package in packages)
      if (package.isActive && (package.expiresDateTime?.isAfter(now) ?? true))
        package.professionalId,
  };
  final recipients = <String, ShareRecipient>{};
  for (final link in links) {
    final id = link.professionalUserId;
    if (id.isNotEmpty && link.status == 'active' && packageIds.contains(id)) {
      recipients[id] = (
        id: id,
        name: link.professionalDisplayName,
        photoUrl: link.professionalPhotoUrl,
      );
    }
  }
  for (final session in sessions) {
    final id = session.professionalId;
    final start = session.scheduledDateTime;
    if (id.isEmpty ||
        session.packageId?.isNotEmpty == true ||
        !session.isScheduled ||
        (session.sessionType != 'chat' && !session.isVideo) ||
        start == null ||
        now.isBefore(start) ||
        !now.isBefore(start.add(Duration(minutes: session.durationMinutes)))) {
      continue;
    }
    recipients.putIfAbsent(
        id,
        () => (
              id: id,
              name: session.professionalName,
              photoUrl: session.photoIntroUrl,
            ));
  }
  return recipients.values.toList(growable: false);
}

Future<String?> pickShareProfessional({
  required BuildContext context,
  required MalvaApiClient api,
  required String token,
  required bool Function() isCurrent,
  VoidCallback? onEmpty,
}) async {
  final (packages, links, sessions) = await (
    api.listCarePackages(accessToken: token),
    api.listPatientProfessionalLinks(accessToken: token),
    api.listCareSessions(accessToken: token, scope: 'ongoing'),
  ).wait;
  if (!context.mounted || !isCurrent()) return null;
  final recipients = eligibleShareRecipients(
    packages: packages,
    links: links,
    sessions: sessions,
    now: ServerClock.now(),
  );
  if (recipients.isEmpty) {
    if (onEmpty != null) {
      onEmpty();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Belum ada profesional dengan paket terhubung atau sesi aktif.'),
      ));
    }
    return null;
  }
  return showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: const Color(0xfff8f8fb),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
    ),
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(sheetContext).height * .76,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 16),
              child: Row(children: [
                const Expanded(
                  child: Text('Bagikan ke profesional',
                      style: TextStyle(
                        color: Color(0xff171d2e),
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      )),
                ),
                IconButton.filledTonal(
                  tooltip: 'Tutup',
                  onPressed: () => Navigator.pop(sheetContext),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xff8792a1),
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
              ]),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 22),
                itemCount: recipients.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final recipient = recipients[index];
                  return _RecipientCard(
                    recipient: recipient,
                    api: api,
                    token: token,
                    onSend: () => Navigator.pop(sheetContext, recipient.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RecipientCard extends StatefulWidget {
  const _RecipientCard({
    required this.recipient,
    required this.api,
    required this.token,
    required this.onSend,
  });
  final ShareRecipient recipient;
  final MalvaApiClient api;
  final String token;
  final VoidCallback onSend;

  @override
  State<_RecipientCard> createState() => _RecipientCardState();
}

class _RecipientCardState extends State<_RecipientCard> {
  late final Future<BackendDoctorProfile> _profile =
      widget.api.getDoctorProfile(
    accessToken: widget.token,
    userId: widget.recipient.id,
  );

  @override
  Widget build(BuildContext context) {
    final recipient = widget.recipient;
    final name = recipient.name.trim().isEmpty ? 'Profesional' : recipient.name;
    return FutureBuilder(
      future: _profile,
      builder: (context, snapshot) {
        final credential = snapshot.data?.credential;
        final specialization = credential?.specialization.trim() ?? '';
        final photo = recipient.photoUrl.isEmpty
            ? credential?.photoIntroUrl
            : recipient.photoUrl;
        return Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xffe8e9ee)),
          ),
          child: Row(children: [
            ProfessionalAvatar(
              displayName: name,
              photoUrl: photo,
              radius: 22,
              borderRadius: BorderRadius.circular(14),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: const TextStyle(
                          color: Color(0xff171d2e),
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(specialization.isEmpty ? 'Profesional' : specialization,
                      style: const TextStyle(color: Color(0xff748093))),
                ],
              ),
            ),
            IconButton.filledTonal(
              tooltip: 'Kirim ke $name',
              onPressed: widget.onSend,
              style: IconButton.styleFrom(
                backgroundColor: const Color(0xfff6f7fa),
                foregroundColor: const Color(0xff69778b),
              ),
              icon: const Icon(Icons.send_outlined),
            ),
          ]),
        );
      },
    );
  }
}
