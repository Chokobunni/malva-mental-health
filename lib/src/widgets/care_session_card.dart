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
import 'friendly_error.dart';

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
  const _SessionPresentation({required this.card, required this.token});
  final CareSessionCard card;
  final String token;

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
          Flexible(child: Text(text, style: const TextStyle(fontSize: 12)))
        ]));
    final content =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 300 ||
            MediaQuery.textScalerOf(context).scale(11) > 15;
        final badge = Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
                color: color.withValues(alpha: .09),
                borderRadius: BorderRadius.circular(20)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.circle, size: 6, color: color),
              const SizedBox(width: 6),
              Flexible(
                  child: Text(status,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 11)))
            ]));
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
      if (!professional &&
          c.allowPreSessionChat &&
          upcoming &&
          !s.canJoinNow) ...[
        const SizedBox(height: 10),
        SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
                onPressed: c.onOpenChat,
                icon: const Icon(Icons.chat_bubble_outline, size: 17),
                label: const Text('Buka Riwayat Chat'))),
      ],
      ...[
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
                    Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .16),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.chevron_right,
                            color: Colors.white, size: 19))
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
  bool _refreshing = false, _finishing = false;
  int _revision = 0;
  BackendChatAccess? _chatAccess;
  List<BackendCareSession> _feed = const [];
  BackendCarePackage? _package;
  static const _purple = Color(0xff792b91);
  static const _ink = Color(0xff18212e);
  static const _gradient =
      LinearGradient(colors: [Color(0xff75248e), Color(0xff9d38b5)]);
  static final _primaryStyle = FilledButton.styleFrom(
          minimumSize: const Size(0, 48),
          backgroundColor: _purple,
          foregroundColor: Colors.white,
          disabledBackgroundColor: const Color(0xffe3e5e9),
          disabledForegroundColor: const Color(0xff626a77),
          textStyle: const TextStyle(
              fontFamily: 'Roboto', fontSize: 14, fontWeight: FontWeight.w700),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)))
      .copyWith(backgroundBuilder: (context, states, child) {
    if (states.contains(WidgetState.disabled)) return child!;
    return Ink(
        decoration: BoxDecoration(
            gradient: _gradient, borderRadius: BorderRadius.circular(15)),
        child: child);
  });

  bool get _owns => !_providerOwned || _owner.session?.role == widget.card.role;
  String get _token => _providerOwned
      ? _owner.session?.accessToken ?? ''
      : widget.card.accessToken ?? '';
  MalvaApiClient? get _api =>
      widget.card.apiClient ?? ref.read(apiClientProvider);
  bool get _professional => widget.card.role == UserRole.professional;
  bool _canShowSummary = false;
  bool get _completed => _session.status == 'completed' && _canShowSummary;
  bool get _live => _session.canJoinNow;
  bool get _packageChat =>
      _session.isScheduled &&
      !_session.isVideo &&
      _session.packageId != null &&
      _chatAccess?.canSendText == true &&
      _chatAccess?.hasActivePackage == true;
  bool get _canChat => _session.isScheduled && (_live || _packageChat);
  bool get _canFinish =>
      _professional &&
      _session.isScheduled &&
      !_session.isBeforeJoinWindow &&
      _session.patientAttendance == 'attended';

  @override
  void initState() {
    super.initState();
    _session = widget.card.session;
    _canShowSummary = _session.status == 'completed';
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
    if (!mounted || _refreshing || !_owns || _token.isEmpty || _api == null)
      return;
    _refreshing = true;
    final token = _token;
    final revision = _revision;
    final api = _api!;
    try {
      try {
        final sessions = await api.listCareSessions(accessToken: token);
        if (!mounted || !_owns || revision != _revision) return;
        setState(() {
          _feed = sessions;
          for (final s in sessions) {
            if (s.id == _session.id) {
              _session = s;
              break;
            }
          }
        });
      } catch (_) {
        /* Keep the authorized snapshot readable if refresh fails. */
      }
      if (!mounted || !_owns) return;
      if (_session.isScheduled &&
          !_session.isVideo &&
          _session.packageId != null) {
        try {
          final access = await api.chatPermission(
              accessToken: _token,
              patientId: _professional ? _session.patientId : null,
              professionalId: _professional ? null : _session.professionalId);
          if (!mounted || !_owns || revision != _revision) return;
          setState(() => _chatAccess = access);
        } catch (_) {
          if (mounted && _owns) setState(() => _chatAccess = null);
        }
      }
      if (_session.packageId != null) {
        try {
          final packages = await api.listCarePackages(
              accessToken: _token,
              patientId: _professional ? _session.patientId : null);
          if (!mounted || !_owns || revision != _revision) return;
          setState(() {
            _package = null;
            for (final p in packages) {
              if (p.id == _session.packageId) {
                _package = p;
                break;
              }
            }
          });
        } catch (_) {
          /* Package numbering stays unavailable without saved data. */
        }
      }
    } finally {
      _refreshing = false;
    }
  }

  String get _packageLabel {
    if (_session.packageId == null) return 'Sekali sesi';
    final total = _package?.totalSessions;
    final sessions = _feed
        .where((s) =>
            s.packageId == _session.packageId &&
            (s.isScheduled || s.status == 'completed' || s.status == 'no_show'))
        .toList();
    if (total == null ||
        total <= 0 ||
        sessions.length != total ||
        sessions.any((s) => s.scheduledDateTime == null) ||
        sessions.map((s) => s.scheduledAt).toSet().length != total ||
        sessions.map((s) => s.id).toSet().length != total) return 'Paket';
    sessions
        .sort((a, b) => a.scheduledDateTime!.compareTo(b.scheduledDateTime!));
    final ordinal = sessions.indexWhere((s) => s.id == _session.id);
    return ordinal < 0 ? 'Paket' : 'Sesi ${ordinal + 1} dari $total';
  }

  void _openChat() {
    if (!_owns || !_canChat) return;
    Navigator.push<void>(
        context,
        MaterialPageRoute(
            builder: (_) => ChatScreen(
                otherUserId: _professional
                    ? _session.patientId
                    : _session.professionalId,
                otherUserName: _professional
                    ? _session.patientName
                    : _session.professionalName)));
  }

  Future<void> _notes() async {
    if (!_owns || !_professional || !_completed) return;
    if (widget.card.onNotes != null) {
      widget.card.onNotes!();
      return;
    }
    await Navigator.push<BackendCareSession>(
        context,
        MaterialPageRoute(
            builder: (_) => ProfessionalSessionNotesScreen(
                session: _session, accessToken: _token, apiClient: _api)));
    if (!mounted || !_owns) return;
    await widget.card.onChanged();
    await _refresh();
  }

  Future<void> _finish() async {
    if (!_owns || !_canFinish || _finishing || _token.isEmpty || _api == null)
      return;
    setState(() => _finishing = true);
    try {
      final updated = await _api!.updateCareSession(
          accessToken: _token, sessionId: _session.id, status: 'completed');
      if (!mounted || !_owns) return;
      if (updated.id != _session.id || updated.status != 'completed') {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'Status sesi belum berubah. Muat ulang dan coba kembali.')));
        return;
      }
      setState(() {
        _session = updated;
        _canShowSummary = true;
        _revision++;
      });
      await widget.card.onChanged();
    } catch (error) {
      if (mounted && _owns)
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyErrorMessage(error))));
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  Widget _chip(String text, {bool light = false, Color? color}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
          color: light ? const Color(0xfff5eafa) : const Color(0xfff4eafa),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: const Color(0xffe5d3ee))),
      child: Text(text,
          textAlign: TextAlign.center,
          style: TextStyle(
              color: color ?? _purple,
              fontWeight: FontWeight.w800,
              fontSize: 12)));
  Widget _block(Widget child, {Color color = Colors.white}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      margin: const EdgeInsets.only(bottom: 16),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(24)),
      child: child);
  Widget _icon(IconData icon) => Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
          color: const Color(0xfff7edfc),
          borderRadius: BorderRadius.circular(13)),
      child: Icon(icon, color: _purple, size: 22));
  Widget _row(IconData icon, Widget child) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(children: [
        _icon(icon),
        const SizedBox(width: 12),
        Expanded(child: child)
      ]));
  Widget _text(String value, {double size = 15}) => Text(value,
      style:
          TextStyle(color: _ink, fontSize: size, fontWeight: FontWeight.w700));

  Widget _identity(String name, String initials, {bool white = false}) =>
      Container(
          padding: white ? EdgeInsets.zero : const EdgeInsets.all(18),
          margin: EdgeInsets.only(bottom: white ? 6 : 16),
          decoration: BoxDecoration(
              color: white ? Colors.white : null,
              gradient: white ? null : _gradient,
              borderRadius: BorderRadius.circular(24)),
          child: Row(children: [
            Container(
                width: 48,
                height: 48,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: white ? _purple : Colors.white,
                    borderRadius: BorderRadius.circular(15)),
                child: Text(initials,
                    style: TextStyle(
                        color: white ? Colors.white : _purple,
                        fontWeight: FontWeight.w800,
                        fontSize: 18))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(name,
                      style: TextStyle(
                          color: white ? _ink : Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text(
                      _completed
                          ? _method
                          : widget.card.subtitle ??
                              (_professional
                                  ? 'Konsultasi • Kesehatan Mental'
                                  : 'Profesional'),
                      style: TextStyle(
                          color: white ? const Color(0xff626a77) : Colors.white,
                          fontSize: 13)),
                  if (_completed && !_professional) ...[
                    const SizedBox(height: 6),
                    Text('$_scheduledDate\n$_scheduledRange',
                        style: const TextStyle(
                            color: Colors.white, fontSize: 12, height: 1.4)),
                  ]
                ])),
            const SizedBox(width: 8),
            ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 108),
                child: _chip(_packageLabel, light: true)),
          ]));

  String get _method => _session.isVideo ? 'Video Call' : 'Chat Konsultasi';
  IconData get _methodIcon =>
      _session.isVideo ? Icons.videocam_outlined : Icons.chat_bubble_outline;
  String get _scheduledDate {
    final at = _session.scheduledDateTime;
    return at == null ? 'Tanggal belum tersedia' : wibWeekdayDate(at);
  }

  String get _scheduledRange {
    final at = _session.scheduledDateTime;
    return at == null
        ? 'Jadwal belum tersedia'
        : '${formatWibBubbleTime(at)}–${formatWibBubbleTime(at.add(Duration(minutes: _session.durationMinutes)))} WIB';
  }

  Widget _information(String status, {Widget? completedIdentity}) {
    if (_completed && !_professional) return _block(_sessionIdRow());
    return _block(Column(children: [
      if (completedIdentity != null) completedIdentity,
      if (completedIdentity == null) ...[
        _row(
            _methodIcon,
            Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _text(_method),
                  _chip(status,
                      color: _live
                          ? _purple
                          : _session.isScheduled
                              ? const Color(0xff8b5800)
                              : _purple)
                ])),
        const Divider(height: 1, color: Color(0xfff0eef3)),
      ],
      _row(Icons.calendar_today_outlined, _text(_scheduledDate)),
      const Divider(height: 1, color: Color(0xfff0eef3)),
      _row(Icons.schedule, _text(_scheduledRange)),
      const Divider(height: 1, color: Color(0xfff0eef3)),
      _sessionIdRow(),
    ]));
  }

  Widget _sessionIdRow() => _row(
      Icons.tag,
      Row(children: [
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('ID Sesi Konsultasi',
              style: TextStyle(color: Color(0xff626a77), fontSize: 12)),
          const SizedBox(height: 5),
          _text(_session.id, size: 13)
        ])),
        TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _session.id));
              if (mounted)
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('ID sesi disalin.')));
            },
            icon: const Icon(Icons.copy_outlined, size: 17),
            label: const Text('Salin'))
      ]));

  Widget _timer() {
    final at = _session.scheduledDateTime;
    final end = at?.add(Duration(minutes: _session.durationMinutes));
    final difference = at == null
        ? Duration.zero
        : (_live
            ? end!.difference(ServerClock.now())
            : at.difference(ServerClock.now()));
    final seconds = difference.inSeconds.clamp(0, 99999999);
    final time = _live
        ? '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}'
        : '${seconds ~/ 3600} jam ${(seconds % 3600) ~/ 60} mnt';
    return _block(
        Column(children: [
          Text(_live ? 'Sisa Waktu Sesi' : 'Sesi Dimulai Dalam',
              style: const TextStyle(
                  color: _ink, fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 10),
          Text(time,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: _purple, fontSize: 34, fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          Text(
              _live
                  ? (_professional
                      ? 'Waktu berjalan otomatis'
                      : 'Waktu berjalan otomatis • Status selesai dikendalikan oleh profesional')
                  : 'Check-in dibuka 10 menit sebelum sesi',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _purple, fontSize: 13))
        ]),
        color: const Color(0xfff2e5fa));
  }

  List<Widget> _publishedSummary() {
    final text = _session.summaryForPatient.trim();
    if (text.isEmpty)
      return [
        _block(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _text('Ringkasan Sesi', size: 17),
          const SizedBox(height: 10),
          const Text('Ringkasan sesi belum tersedia.')
        ]))
      ];
    final structured = sessionNoteSections.any((heading) =>
        text.startsWith('$heading\n') || text.contains('\n\n$heading\n'));
    if (!structured)
      return [
        _block(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _text('Ringkasan Sesi', size: 17),
          const SizedBox(height: 12),
          Text(text)
        ]))
      ];
    final sections = parseSessionNotes(text);
    const icons = [
      Icons.description_outlined,
      Icons.psychology_outlined,
      Icons.check_circle_outline,
      Icons.event_note_outlined,
      Icons.flag_outlined
    ];
    return [
      for (var i = 0; i < sections.length; i++)
        if (sections[i].trim().isNotEmpty)
          _block(
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _icon(icons[i]),
              const SizedBox(width: 10),
              Expanded(child: _text(sessionNoteSections[i], size: 16))
            ]),
            const SizedBox(height: 14),
            Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: const Color(0xfff8f7fa),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xffefedf3))),
                child: Text(sections[i],
                    style: const TextStyle(
                        height: 1.55, color: Color(0xff414957))))
          ]))
    ];
  }

  Widget _cta(String label, IconData icon, VoidCallback? action,
          {bool outline = false}) =>
      SizedBox(
          width: double.infinity,
          child: outline
              ? OutlinedButton.icon(
                  onPressed: action,
                  icon: Icon(icon, size: 19),
                  label: Text(label, textAlign: TextAlign.center),
                  style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      foregroundColor: _purple,
                      side: const BorderSide(color: _purple),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15))))
              : FilledButton.icon(
                  onPressed: action,
                  icon: Icon(icon, size: 19),
                  label: Text(label, textAlign: TextAlign.center),
                  style: _primaryStyle));

  @override
  Widget build(BuildContext context) {
    ref.watch(currentSessionProvider);
    if (!_owns)
      return Scaffold(
          appBar: AppBar(title: const Text('Detail Sesi')),
          body: const Center(
              child: Text('Buka kembali detail sesi dari akun aktif.')));
    final professional = _professional;
    final name = professional
        ? (_session.patientName.isEmpty ? 'Pasien' : _session.patientName)
        : (_session.professionalName.isEmpty
            ? 'Profesional'
            : _session.professionalName);
    final initials = name
        .replaceFirst(
            RegExp(r'^(dr\.?|prof\.?|ns\.?)\s+', caseSensitive: false), '')
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first)
        .join()
        .toUpperCase();
    final status = _completed
        ? 'Selesai'
        : _live
            ? 'Live'
            : _session.isScheduled
                ? 'Terjadwal'
                : switch (_session.status) {
                    'completed' => 'Selesai',
                    'no_show' => 'Tidak hadir',
                    'pending_payment' => 'Menunggu pembayaran',
                    'expired_unpaid' => 'Pembayaran kedaluwarsa',
                    _ => 'Dibatalkan'
                  };
    final title =
        _completed && !professional ? 'Ringkasan Catatan Sesi' : 'Detail Sesi';
    final subtitle = _completed
        ? professional
            ? 'Ringkasan Sesi Selesai'
            : 'Rekam Medis & Evaluasi dari Profesional'
        : _live
            ? 'Sesi Konsultasi Aktif'
            : _session.isScheduled
                ? 'Sesi Terjadwal'
                : 'Riwayat Konsultasi';
    final notesSaved = _session.summaryForPatient.trim().isNotEmpty;
    final content = <Widget>[
      if (_completed && professional) ...[
        const SizedBox(height: 12),
        Center(
            child: Container(
                width: 95,
                height: 95,
                decoration: BoxDecoration(
                    color: const Color(0xffddf5e9),
                    shape: BoxShape.circle,
                    border:
                        Border.all(color: const Color(0xffeef9f3), width: 9)),
                child: const Icon(Icons.check_circle,
                    color: Color(0xff168147), size: 64))),
        const SizedBox(height: 12),
        Center(child: _text('Sesi Selesai', size: 25)),
        const SizedBox(height: 20),
      ],
      if (!_completed || !professional) _identity(name, initials),
      _information(
          _completed
              ? 'Selesai'
              : _live
                  ? 'Sedang Berlangsung'
                  : _session.isScheduled
                      ? 'Menunggu Jadwal'
                      : status,
          completedIdentity: _completed && professional
              ? _identity(name, initials, white: true)
              : null),
      if (_session.isScheduled && !_session.isAfterJoinWindow) _timer(),
      if (_completed && !professional) ..._publishedSummary(),
      if (_session.status == 'completed' && !_canShowSummary)
        _block(const Text(
            'Sesi telah selesai. Buka Riwayat untuk melihat ringkasannya.')),
      if (_completed &&
          professional &&
          (notesSaved || _session.privateNote.trim().isNotEmpty))
        _block(
            Row(children: [
              Icon(notesSaved ? Icons.task_alt : Icons.edit_note,
                  color: notesSaved ? const Color(0xff08765a) : _purple),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(
                      notesSaved
                          ? 'Catatan sesi sudah tersimpan'
                          : _session.privateNote.trim().isNotEmpty
                              ? 'Draf/catatan pribadi tersimpan'
                              : 'Catatan sesi belum tersedia',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, color: _ink)))
            ]),
            color: notesSaved ? const Color(0xffeafaf2) : Colors.white),
      if (_session.isScheduled && !_live) ...[
        if (!professional && !_session.isVideo)
          _block(
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              _icon(Icons.assignment_outlined),
              const SizedBox(width: 10),
              Expanded(child: _text('Instruksi Persiapan Sesi Chat', size: 16))
            ]),
            const SizedBox(height: 14),
            const Text(
                '• Pastikan koneksi internet stabil dan notifikasi aplikasi aktif agar pesan terkirim secara real-time.',
                style: TextStyle(height: 1.5)),
            const SizedBox(height: 10),
            Text(
                '• Catat poin keluhan utama atau pertanyaan penting agar sesi chat ${_session.durationMinutes} menit lebih efektif.',
                style: const TextStyle(height: 1.5))
          ]))
        else
          _block(Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _icon(Icons.info_outline),
            const SizedBox(width: 12),
            Expanded(
                child: Text(
                    _session.isVideo
                        ? 'Siapkan koneksi internet yang stabil dan tempat yang nyaman.'
                        : _packageChat
                            ? 'Ruang chat sudah tersedia. Check-in sesi dibuka 10 menit sebelum jadwal.'
                            : 'Ruang konsultasi dibuka 10 menit sebelum jadwal dimulai.',
                    style: const TextStyle(height: 1.5)))
          ])),
        if (_packageChat)
          _block(
              const Text(
                  'Paket aktif • Ruang chat tersedia selama masa layanan paket.',
                  style: TextStyle(
                      color: Color(0xff08765a), fontWeight: FontWeight.w700)),
              color: const Color(0xffeafaf2)),
      ],
      if (_session.isScheduled &&
          !_session.isBeforeJoinWindow &&
          (!professional || !_session.isAfterJoinWindow))
        _block(SessionAttendanceActions(
            session: _session,
            role: widget.card.role,
            accessToken: _token,
            apiClient: _api,
            onChanged: () async {
              await widget.card.onChanged();
              await _refresh();
            })),
      if (_session.cancelReason.isNotEmpty)
        _block(Text('Alasan: ${_session.cancelReason}')),
    ];
    final actions = <Widget>[];
    if (_completed) {
      if (professional) {
        actions.add(_cta(
            notesSaved ? 'Lihat / Edit Catatan Sesi' : 'Isi Catatan Sesi',
            Icons.edit_note,
            _notes));
        actions.add(const SizedBox(height: 8));
        actions.add(_cta(
            'Nanti', Icons.arrow_back, () => Navigator.pop(context),
            outline: true));
      } else
        actions.add(_cta('Kembali ke Riwayat', Icons.arrow_back,
            () => Navigator.pop(context)));
    } else if (_session.isScheduled) {
      if (_session.isVideo && _live) {
        actions.add(MeetJoinButton(
            session: _session,
            accessToken: _token,
            expanded: true,
            canCreateLink: professional,
            joinLabel: 'Masuk Video Call',
            joinStyle: _primaryStyle,
            onConfirmAttendance: widget.card.onConfirmAttendance,
            onSessionChanged: (s) async {
              if (mounted && _owns) setState(() => _session = s);
              await widget.card.onChanged();
            }));
      } else
        actions.add(_cta(
            _session.isVideo
                ? 'Masuk Video Call (Belum Dibuka)'
                : _canChat
                    ? 'Masuk Ruang Chat'
                    : 'Masuk Ruang Chat (Belum Dibuka)',
            _session.isVideo
                ? Icons.videocam_outlined
                : Icons.chat_bubble_outline,
            !_session.isVideo && _canChat ? _openChat : null));
      if (professional) {
        actions.add(const SizedBox(height: 8));
        actions.add(_cta(_finishing ? 'Menyelesaikan…' : 'Tandai Sesi Selesai',
            Icons.task_alt, _canFinish && !_finishing ? _finish : null,
            outline: true));
      }
    } else
      actions.add(_cta('Kembali ke Riwayat', Icons.arrow_back,
          () => Navigator.pop(context)));
    return Scaffold(
        backgroundColor: const Color(0xfff8f5fb),
        appBar: AppBar(
            centerTitle: false,
            toolbarHeight: 83,
            foregroundColor: Colors.white,
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            leading: Navigator.canPop(context)
                ? Padding(
                    padding: const EdgeInsets.only(left: 10),
                    child: Center(
                        child: IconButton(
                            tooltip: MaterialLocalizations.of(context)
                                .backButtonTooltip,
                            style: IconButton.styleFrom(
                                backgroundColor: Colors.white24,
                                foregroundColor: Colors.white),
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(Icons.arrow_back))))
                : null,
            shape: const RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(27))),
            flexibleSpace: const DecoratedBox(
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xff75248e), Color(0xffb572cb)]),
                    borderRadius:
                        BorderRadius.vertical(bottom: Radius.circular(27))),
                child: SizedBox.expand()),
            title:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  maxLines: 2,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              const SizedBox(height: 3),
              Text(subtitle,
                  maxLines: 2,
                  style: const TextStyle(fontSize: 11, color: Colors.white))
            ]),
            actions: [
              Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(child: _chip(status, light: true)))
            ]),
        body: RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: content)),
        bottomNavigationBar: SafeArea(
            top: false,
            child: Container(
                padding: const EdgeInsets.all(14),
                decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(top: BorderSide(color: Color(0xfff0eaf4)))),
                child: Column(mainAxisSize: MainAxisSize.min, children: actions))));
  }
}
