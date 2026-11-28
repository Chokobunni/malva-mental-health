import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';

/// Patient secondary actions shared by Home, Jadwal, and web.
class PatientSessionActions extends StatelessWidget {
  const PatientSessionActions(
      {super.key,
      required this.session,
      this.onProfile,
      this.onCancel,
      this.onReschedule,
      this.initiallyExpanded = false});
  final BackendCareSession session;
  final VoidCallback? onProfile, onCancel, onReschedule;
  final bool initiallyExpanded;
  @override
  Widget build(BuildContext context) => Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 13),
          childrenPadding: const EdgeInsets.all(12),
          backgroundColor: const Color(0xfff7f4fa),
          collapsedBackgroundColor: const Color(0xfff7f4fa),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
          collapsedShape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
          title: const Text('Aksi lain',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.black54)),
          children: [
            LayoutBuilder(builder: (context, constraints) {
              final half = constraints.maxWidth >=
                      MediaQuery.textScalerOf(context).scale(250)
                  ? (constraints.maxWidth - 8) / 2
                  : constraints.maxWidth;
              Widget action(IconData icon, String label, VoidCallback? callback,
                      {bool full = false, bool danger = false}) =>
                  SizedBox(
                      width: full ? constraints.maxWidth : half,
                      child: OutlinedButton.icon(
                          onPressed: callback,
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 40),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 5, vertical: 9),
                              backgroundColor: danger
                                  ? const Color(0xfffff6f7)
                                  : Colors.white,
                              foregroundColor: danger
                                  ? MalvaColors.danger
                                  : MalvaColors.seed,
                              side: BorderSide(
                                  color: danger
                                      ? const Color(0xfff2dadd)
                                      : const Color(0xffece6f1)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      initiallyExpanded ? 24 : 12)),
                              textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          icon: Icon(icon, size: 17),
                          label: Text(label, textAlign: TextAlign.center)));
              return Wrap(spacing: 8, runSpacing: 8, children: [
                if (!session.isVideo && onReschedule != null)
                  action(Icons.event_repeat, 'Reschedule', onReschedule,
                      full: true),
                if (onProfile != null)
                  action(Icons.person_outline, 'Profil', onProfile),
                if (onCancel != null)
                  action(Icons.cancel_outlined, 'Batal', onCancel,
                      danger: true),
                if (session.isVideo) ...[
                  if (onReschedule != null)
                    action(Icons.event_repeat, 'Reschedule', onReschedule),
                  Tooltip(
                      message: session.meetingUrl.trim().isEmpty
                          ? 'Menunggu link video dari profesional.'
                          : 'Salin link sesi',
                      child: action(
                          Icons.link,
                          'Link',
                          session.meetingUrl.trim().isEmpty
                              ? null
                              : () async {
                                  await Clipboard.setData(
                                      ClipboardData(text: session.meetingUrl));
                                  if (context.mounted)
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                            content:
                                                Text('Link sesi disalin.')));
                                },
                          full: initiallyExpanded)),
                ],
              ]);
            })
          ],
        ),
      );
}
