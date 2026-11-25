import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../services/server_clock.dart';
import '../time/wib.dart';
import '../theme.dart';
import '../screens/professional_session_notes_screen.dart';
import '../screens/booking/booking_owner.dart';
import '../screens/chat_screen.dart';
import 'meet_join_button.dart';
import 'session_attendance_actions.dart';
import 'professional_avatar.dart';

/// Shared session presentation for Home and Jadwal. Actions retain their owning flows.
class CareSessionCard extends ConsumerWidget {
  const CareSessionCard(
      {super.key,
      required this.session,
      required this.role,
      required this.onOpenChat,
      required this.onChanged,
      this.accessToken,
      this.apiClient,
      this.onCancel,
      this.onReschedule,
      this.onProfile,
      this.onNotes,
      this.otherActions,
      this.onConfirmAttendance,
      this.subtitle,
      this.detailLabel = 'Lihat Detail Sesi',
      this.allowPreSessionChat = false});
  final BackendCareSession session;
  final UserRole role;
  final VoidCallback onOpenChat;
  final Future<void> Function() onChanged;
  final String? accessToken;
  final MalvaApiClient? apiClient;
  final VoidCallback? onCancel, onReschedule, onProfile, onNotes;
  final Widget? otherActions;
  final String? subtitle;
  final String detailLabel;
  final bool allowPreSessionChat;
  final Future<BackendCareSession?> Function()? onConfirmAttendance;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _SessionPresentation(
      card: this,
      token:
          accessToken ?? ref.watch(currentSessionProvider)?.accessToken ?? '');
}

class _SessionPresentation extends StatefulWidget {
  const _SessionPresentation(
      {required this.card, required this.token, this.detail = false});
  final CareSessionCard card;
  final String token;
  final bool detail;
  @override
  State<_SessionPresentation> createState() => _SessionPresentationState();
}

class _SessionPresentationState extends State<_SessionPresentation> {
  Timer? _ticker;
  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.card, s = c.session;
    final professional = c.role == UserRole.professional;
    final name = professional
        ? (s.patientName.isEmpty ? 'Pasien' : s.patientName)
        : (s.professionalName.isEmpty ? 'Profesional' : s.professionalName);
    final at = s.scheduledDateTime;
    final now = ServerClock.now();
    final live = s.isScheduled &&
        at != null &&
        !now.isBefore(at) &&
        !s.isAfterJoinWindow;
    final upcoming = s.isScheduled && !s.isAfterJoinWindow;
    final duration = at == null
        ? Duration.zero
        : (live
            ? at.add(Duration(minutes: s.durationMinutes)).difference(now)
            : at.difference(now));
    final minutes = duration.inMinutes.clamp(0, 999999);
    final countdown =
        '${minutes ~/ 60 > 0 ? '${minutes ~/ 60} jam ' : ''}${minutes % 60} mnt';
    final status = live
        ? 'Aktif'
        : switch (s.status) {
            'scheduled' => s.isAfterJoinWindow ? 'Waktu berakhir' : 'Terjadwal',
            'completed' => 'Selesai',
            'no_show' => 'Tidak hadir',
            'pending_payment' => 'Menunggu pembayaran',
            'cancelled_by_patient' ||
            'cancelled_by_professional' =>
              'Dibatalkan',
            _ => s.status
          };
    final color = live || s.status == 'completed'
        ? const Color(0xff099b78)
        : MalvaColors.seed;
    final date = at == null
        ? 'Jadwal belum tersedia'
        : '${wibWeekdayDate(at)} • ${formatWibBubbleTime(at)}${live ? ' – ${formatWibBubbleTime(at.add(Duration(minutes: s.durationMinutes)))}' : ''} WIB';
    final initials = name
        .split(RegExp(r'\s+'))
        .where((v) => v.isNotEmpty)
        .take(2)
        .map((v) => v.characters.first)
        .join()
        .toUpperCase();
    Widget strip(String text, IconData icon, {Color? tint}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
            color: tint ?? const Color(0xfff5f3f8),
            borderRadius: BorderRadius.circular(13)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 19, color: MalvaColors.seed),
          const SizedBox(width: 8),
          Flexible(
              child: Text(text,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13)))
        ]));
    Widget chip(String text, IconData icon) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
            color: const Color(0xfffaf8fc),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xffeee8f1))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: MalvaColors.seed),
          const SizedBox(width: 5),
          Text(text, style: const TextStyle(fontSize: 12))
        ]));
    final content =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 340;
        final badge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
                color: color.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(20)),
            child: Text(status,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w700, fontSize: 11)));
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (!professional && s.photoIntroUrl.isNotEmpty)
              ProfessionalAvatar(
                  displayName: name, photoUrl: s.photoIntroUrl, radius: 24)
            else
              Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: const Color(0xfff4eaf9),
                      borderRadius: BorderRadius.circular(16)),
                  child: Text(initials,
                      style: const TextStyle(
                          color: MalvaColors.seed,
                          fontWeight: FontWeight.w800))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(name,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 3),
                  Text(c.subtitle ?? (professional ? 'Pasien' : 'Profesional'),
                      style:
                          const TextStyle(color: Colors.black54, fontSize: 13))
                ])),
            if (!narrow) ...[const SizedBox(width: 5), badge],
          ]),
          if (narrow) ...[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerRight, child: badge)
          ]
        ]);
      }),
      const SizedBox(height: 14),
      Wrap(spacing: 7, runSpacing: 7, children: [
        chip(s.isVideo ? 'Video' : 'Chat',
            s.isVideo ? Icons.videocam_outlined : Icons.chat_bubble_outline),
        chip('${s.durationMinutes} mnt', Icons.hourglass_bottom),
        chip(
            live
                ? 'Sisa $countdown'
                : s.packageId == null
                    ? 'Sekali sesi'
                    : 'Paket',
            live ? Icons.timer_outlined : Icons.auto_awesome_outlined)
      ]),
      const SizedBox(height: 14),
      strip(date, Icons.calendar_today_outlined),
      if (upcoming && !live) ...[
        const SizedBox(height: 9),
        strip('Mulai dalam $countdown', Icons.schedule,
            tint: const Color(0xfff8eefb))
      ],
      if (s.canJoinNow) ...[
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: s.isVideo
                ? MeetJoinButton(
                    session: s,
                    accessToken: widget.token,
                    canCreateLink: professional,
                    expanded: true,
                    onConfirmAttendance: c.onConfirmAttendance,
                    onSessionChanged: (_) => c.onChanged())
                : FilledButton.icon(
                    onPressed: c.onOpenChat,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xff078b69),
                      padding: const EdgeInsets.symmetric(horizontal: 7),
                    ),
                    icon: const Icon(Icons.chat_rounded, size: 17),
                    label: const Text('Gabung'),
                  ),
          ),
          const SizedBox(width: 8),
          Expanded(
              child: OutlinedButton.icon(
                  onPressed: c.onOpenChat,
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xffeafaf4),
                    foregroundColor: const Color(0xff08765a),
                    side: const BorderSide(color: Color(0xffc4eddf)),
                    minimumSize: const Size(0, 48),
                  ),
                  icon: const Icon(Icons.chat_bubble_outline, size: 17),
                  label: const Text('Chat'))),
        ]),
      ],
      if (c.allowPreSessionChat && upcoming && !s.canJoinNow) ...[
        const SizedBox(height: 10),
        SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
                onPressed: c.onOpenChat,
                icon: const Icon(Icons.chat_bubble_outline, size: 17),
                label: const Text('Buka Riwayat Chat'))),
      ],
      if (!widget.detail) ...[
        const SizedBox(height: 14),
        _DetailButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => CareSessionDetailScreen(card: c))),
            label: c.detailLabel)
      ],
      if (upcoming && s.isBeforeJoinWindow) ...[
        const SizedBox(height: 12),
        const Row(children: [
          Icon(Icons.info_outline_rounded, size: 15, color: MalvaColors.seed),
          SizedBox(width: 6),
          Expanded(
              child: Text('Check-in dibuka 10 menit sebelum sesi.',
                  style: TextStyle(color: Colors.black54, fontSize: 12))),
        ]),
      ],
      if (upcoming &&
          (c.otherActions != null ||
              c.onCancel != null ||
              c.onReschedule != null ||
              c.onProfile != null)) ...[
        const SizedBox(height: 14),
        if (c.otherActions != null)
          c.otherActions!
        else
          Theme(
              data:
                  Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                  childrenPadding: const EdgeInsets.all(10),
                  backgroundColor: const Color(0xfff8f5fb),
                  collapsedBackgroundColor: const Color(0xfff8f5fb),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                  collapsedShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15)),
                  title: const Text('AKSI LAIN',
                      style:
                          TextStyle(fontSize: 12, fontWeight: FontWeight.w800)),
                  children: [
                    if (!s.isVideo && c.onReschedule != null)
                      SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                              onPressed: c.onReschedule,
                              icon: const Icon(Icons.event_repeat),
                              label: const Text('Reschedule'))),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (c.onProfile != null)
                        OutlinedButton.icon(
                            onPressed: c.onProfile,
                            icon: const Icon(Icons.person_outline),
                            label: const Text('Profil')),
                      if (c.onCancel != null)
                        OutlinedButton.icon(
                            onPressed: c.onCancel,
                            icon: const Icon(Icons.cancel_outlined),
                            label: const Text('Batal')),
                      if (s.isVideo && c.onReschedule != null)
                        OutlinedButton.icon(
                            onPressed: c.onReschedule,
                            icon: const Icon(Icons.event_repeat),
                            label: const Text('Reschedule'))
                    ])
                  ]))
      ],
      if (!s.isScheduled && s.summaryForPatient.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('Ringkasan: ${s.summaryForPatient}')
      ],
      if (s.cancelReason.isNotEmpty) ...[
        const SizedBox(height: 10),
        Text('Alasan: ${s.cancelReason}')
      ],
    ]);
    if (widget.detail) {
      Widget block(Widget child) => Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(22)),
          child: child);
      Widget info(IconData icon, String label) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: const Color(0xfff5eafa),
                    borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, color: MalvaColors.seed)),
            const SizedBox(width: 14),
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)))
          ]));
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xff863399), Color(0xffa33bb6)]),
                borderRadius: BorderRadius.circular(24)),
            child: Row(children: [
              CircleAvatar(
                  backgroundColor: Colors.white,
                  radius: 27,
                  child: Text(initials,
                      style: const TextStyle(
                          color: MalvaColors.seed,
                          fontWeight: FontWeight.w800))),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(name,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 17)),
                    Text(
                        c.subtitle ?? (professional ? 'Pasien' : 'Profesional'),
                        style: const TextStyle(color: Colors.white70))
                  ]))
            ])),
        block(Column(children: [
          info(s.isVideo ? Icons.videocam_outlined : Icons.forum_outlined,
              '${s.isVideo ? 'Video Call' : 'Chat'} • $status'),
          const Divider(height: 1),
          info(Icons.calendar_today_outlined,
              at == null ? 'Jadwal belum tersedia' : wibWeekdayDate(at)),
          const Divider(height: 1),
          info(
              Icons.schedule,
              at == null
                  ? '—'
                  : '${formatWibBubbleTime(at)} – ${formatWibBubbleTime(at.add(Duration(minutes: s.durationMinutes)))} WIB'),
          const Divider(height: 1),
          Row(children: [
            Expanded(child: info(Icons.tag, 'ID Sesi: ${s.id}')),
            IconButton(
                tooltip: 'Salin ID Sesi',
                onPressed: () => Clipboard.setData(ClipboardData(text: s.id)),
                icon: const Icon(Icons.copy_outlined, color: MalvaColors.seed))
          ])
        ])),
        if (upcoming)
          block(Column(children: [
            Text(live ? 'Sisa Waktu Sesi' : 'Sesi dimulai dalam',
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
            const SizedBox(height: 10),
            Text(
                live
                    ? '${duration.inMinutes.clamp(0, 9999).toString().padLeft(2, '0')}:${(duration.inSeconds.clamp(0, 999999) % 60).toString().padLeft(2, '0')}'
                    : countdown,
                style: const TextStyle(
                    color: MalvaColors.seed,
                    fontWeight: FontWeight.w800,
                    fontSize: 36)),
            const SizedBox(height: 8),
            Text(
                live
                    ? 'Waktu sesi mengikuti jadwal konsultasi.'
                    : 'Check-in dibuka 10 menit sebelum sesi.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: MalvaColors.seed))
          ])),
        if (s.status == 'completed')
          block(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Ringkasan Sesi',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            Text(s.summaryForPatient.isEmpty
                ? 'Ringkasan sesi belum tersedia.'
                : s.summaryForPatient)
          ]))
        else if (upcoming && !live)
          block(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Persiapan Sesi',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            Text(s.isVideo
                ? 'Siapkan koneksi internet yang stabil dan tempat yang nyaman.'
                : 'Siapkan hal yang ingin Anda ceritakan. Percakapan dibuka sesuai jadwal sesi.')
          ])),
        if (professional && (s.isScheduled || s.status == 'completed'))
          block(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Catatan Klinis',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(s.summaryForPatient.isEmpty
                ? 'Ringkasan belum dibagikan.'
                : 'Ringkasan tersimpan dan dibagikan kepada pasien.'),
            TextButton.icon(
                onPressed: c.onNotes ??
                    () async {
                      await Navigator.push(
                          context,
                          MaterialPageRoute<BackendCareSession>(
                              builder: (_) => ProfessionalSessionNotesScreen(
                                  session: s,
                                  accessToken: widget.token,
                                  apiClient: c.apiClient)));
                      await c.onChanged();
                    },
                icon: const Icon(Icons.edit_note),
                label: Text(s.summaryForPatient.isEmpty
                    ? 'Isi Catatan Sesi'
                    : 'Buka Catatan Sesi'))
          ])),
        if (s.isScheduled && !s.isBeforeJoinWindow)
          block(SessionAttendanceActions(
              session: s,
              role: c.role,
              onChanged: c.onChanged,
              accessToken: widget.token,
              apiClient: c.apiClient)),
        if (c.otherActions != null && upcoming) c.otherActions!,
        if (upcoming &&
            c.otherActions == null &&
            (c.onProfile != null ||
                c.onReschedule != null ||
                c.onCancel != null))
          block(Wrap(spacing: 8, runSpacing: 8, children: [
            if (c.onProfile != null)
              OutlinedButton.icon(
                  onPressed: c.onProfile,
                  icon: const Icon(Icons.person_outline),
                  label: const Text('Profil')),
            if (c.onReschedule != null)
              OutlinedButton.icon(
                  onPressed: c.onReschedule,
                  icon: const Icon(Icons.event_repeat),
                  label: const Text('Reschedule')),
            if (c.onCancel != null)
              OutlinedButton.icon(
                  onPressed: c.onCancel,
                  icon: const Icon(Icons.cancel_outlined),
                  label: const Text('Batal')),
            if (s.isVideo)
              OutlinedButton.icon(
                  onPressed: s.meetingUrl.isEmpty
                      ? null
                      : () =>
                          Clipboard.setData(ClipboardData(text: s.meetingUrl)),
                  icon: const Icon(Icons.link),
                  label: const Text('Link'))
          ])),
        if (s.cancelReason.isNotEmpty) block(Text('Alasan: ${s.cancelReason}')),
      ]);
    }
    return Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(23),
            border: Border.all(color: const Color(0xfff1eaf5))),
        child: content);
  }
}

class _DetailButton extends StatelessWidget {
  const _DetailButton({required this.onPressed, required this.label});
  final VoidCallback onPressed;
  final String label;
  @override
  Widget build(BuildContext context) => Container(
      decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xff893492), Color(0xffa744b3)]),
          borderRadius: BorderRadius.circular(13)),
      child: Material(
          color: Colors.transparent,
          child: InkWell(
              borderRadius: BorderRadius.circular(13),
              onTap: onPressed,
              child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Row(children: [
                    const Icon(Icons.description_outlined,
                        color: Colors.white, size: 19),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(label,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700))),
                    const Icon(Icons.chevron_right, color: Colors.white)
                  ])))));
}

class CareSessionDetailScreen extends ConsumerStatefulWidget {
  const CareSessionDetailScreen({super.key, required this.card});
  final CareSessionCard card;
  @override
  ConsumerState<CareSessionDetailScreen> createState() =>
      _CareSessionDetailScreenState();
}

class _CareSessionDetailScreenState
    extends ConsumerState<CareSessionDetailScreen> {
  late BackendCareSession _session;
  late final BookingOwner _owner;
  late final bool _providerOwned;
  Timer? _poll;
  bool _refreshing = false;
  @override
  void initState() {
    super.initState();
    _session = widget.card.session;
    final viewer = ref.read(currentSessionProvider);
    _owner = BookingOwner(ref, viewer);
    _providerOwned = viewer != null;
    _poll = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) setState(() {});
      if (timer.tick % 30 == 0) _refresh();
    });
    Future.microtask(_refresh);
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted || _refreshing || _providerOwned && _owner.session == null) {
      return;
    }
    final token = _providerOwned
        ? _owner.session?.accessToken ?? ''
        : widget.card.accessToken ?? '';
    final api = widget.card.apiClient ?? ref.read(apiClientProvider);
    if (token.isEmpty || api == null) return;
    _refreshing = true;
    try {
      final sessions = await api.listCareSessions(accessToken: token);
      if (!mounted || _providerOwned && _owner.session == null) return;
      for (final s in sessions) {
        if (s.id == _session.id) {
          setState(() => _session = s);
          break;
        }
      }
    } catch (_) {
      /* Existing snapshot stays readable when a refresh is unavailable. */
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    ref.watch(currentSessionProvider);
    if (_providerOwned && _owner.session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Detail Sesi')),
        body: const Center(
            child: Text('Buka kembali detail sesi dari akun aktif.')),
      );
    }
    final token = _providerOwned
        ? _owner.session?.accessToken ?? ''
        : c.accessToken ?? '';
    final live = _session.canJoinNow;
    final completed = _session.status == 'completed';
    final professional = c.role == UserRole.professional;
    final summary = completed && !professional;
    final status = completed
        ? 'Selesai'
        : live
            ? 'Live'
            : 'Terjadwal';
    final subtitle = summary
        ? 'Rekam Medis & Evaluasi dari Profesional'
        : completed
            ? 'Ringkasan Sesi Selesai'
            : live
                ? 'Sesi Konsultasi Aktif'
                : _session.isScheduled
                    ? 'Sesi Terjadwal'
                    : 'Riwayat Konsultasi';
    void openChat() {
      if (!_session.canJoinNow) return;
      Navigator.push<void>(
          context,
          MaterialPageRoute(
              builder: (_) => ChatScreen(
                    otherUserId: professional
                        ? _session.patientId
                        : _session.professionalId,
                    otherUserName: professional
                        ? _session.patientName
                        : _session.professionalName,
                  )));
    }

    final card = CareSessionCard(
        session: _session,
        role: c.role,
        onOpenChat: openChat,
        onChanged: () async {
          await c.onChanged();
          await _refresh();
        },
        accessToken: token,
        apiClient: c.apiClient,
        onNotes: c.onNotes,
        onConfirmAttendance: c.onConfirmAttendance,
        subtitle: c.subtitle);
    return Scaffold(
        backgroundColor: const Color(0xfff8f5fb),
        appBar: AppBar(
          centerTitle: false,
          toolbarHeight: 73,
          backgroundColor: MalvaColors.plum,
          foregroundColor: Colors.white,
          flexibleSpace: const DecoratedBox(
              decoration: BoxDecoration(
            gradient: LinearGradient(
                colors: [MalvaColors.plum, MalvaColors.orchid],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter),
          )),
          title:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(summary ? 'Ringkasan Catatan Sesi' : 'Detail Sesi',
                maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(subtitle,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ]),
          actions: [
            if (_session.isScheduled || completed)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Chip(
                  label:
                      Text(status, style: const TextStyle(color: Colors.white)),
                  backgroundColor: const Color(0x397fffff),
                  side: BorderSide.none,
                ),
              ),
          ],
        ),
        body: RefreshIndicator(
            onRefresh: _refresh,
            child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: _SessionPresentation(
                    card: card, token: token, detail: true))),
        bottomNavigationBar: live
            ? SafeArea(
                child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (_session.isVideo)
                        MeetJoinButton(
                            session: _session,
                            accessToken: token,
                            expanded: true,
                            canCreateLink: c.role == UserRole.professional,
                            onConfirmAttendance: c.onConfirmAttendance,
                            onSessionChanged: (_) async {
                              await c.onChanged();
                              await _refresh();
                            }),
                      if (_session.isVideo) const SizedBox(height: 7),
                      SizedBox(
                          width: double.infinity,
                          child: FilledButton.icon(
                              onPressed: openChat,
                              icon: const Icon(Icons.forum_outlined),
                              label: const Text('Buka Percakapan')))
                    ])))
            : _session.isBeforeJoinWindow || summary
                ? SafeArea(
                    minimum: const EdgeInsets.all(12),
                    child: FilledButton.icon(
                      onPressed: summary ? () => Navigator.pop(context) : null,
                      icon: Icon(summary
                          ? Icons.arrow_back_rounded
                          : _session.isVideo
                              ? Icons.videocam_outlined
                              : Icons.forum_outlined),
                      label: Text(summary
                          ? 'Kembali'
                          : _session.isVideo
                              ? 'Masuk Video Call (Belum Dibuka)'
                              : 'Masuk Ruang Chat (Belum Dibuka)'),
                    ),
                  )
                : null);
  }
}
