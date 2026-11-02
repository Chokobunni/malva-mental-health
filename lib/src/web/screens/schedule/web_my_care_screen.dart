import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/providers.dart';
import '../../../screens/chat_screen.dart';
import '../../../services/malva_api_client.dart';
import '../../../services/meeting_launcher.dart';
import '../../../theme.dart';
import '../../../time/wib.dart';
import '../../../widgets/friendly_error.dart';
import '../../services/web_care_service.dart';
import '../../web_format.dart';
import '../../web_theme.dart';
import '../../widgets/web_admin_widgets.dart';
import '../../widgets/web_page_header.dart';

/// MyCare pasien (`/jadwal`): tab Paket, Jadwal, dan Riwayat.
class WebMyCareScreen extends ConsumerStatefulWidget {
  const WebMyCareScreen({super.key});

  @override
  ConsumerState<WebMyCareScreen> createState() => _WebMyCareScreenState();
}

class _WebMyCareScreenState extends ConsumerState<WebMyCareScreen> {
  int _tab = 0;
  List<BackendCarePackage> _packages = const <BackendCarePackage>[];
  List<BackendCareSession> _sessions = const <BackendCareSession>[];
  bool _loading = true;
  Object? _error;
  final Set<String> _busySessions = <String>{};

  String get _token => ref.read(authStateProvider).session?.accessToken ?? '';

  String get _patientId =>
      ref.read(authStateProvider).session?.backendUserId ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final results = await Future.wait(<Future<Object>>[
        api.listCarePackages(
          accessToken: _token,
          patientId: _patientId.isEmpty ? null : _patientId,
        ),
        api.listCareSessions(
          accessToken: _token,
          scope: 'all',
          patientId: _patientId.isEmpty ? null : _patientId,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _packages = results[0] as List<BackendCarePackage>;
        _sessions = results[1] as List<BackendCareSession>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  List<BackendCareSession> get _upcoming => _sessions
      .where((BackendCareSession s) =>
          s.isScheduled && (s.scheduledDateTime?.isAfter(wibNow()) ?? false))
      .toList(growable: false)
    ..sort((BackendCareSession a, BackendCareSession b) =>
        (a.scheduledDateTime ?? wibNow())
            .compareTo(b.scheduledDateTime ?? wibNow()));

  List<BackendCareSession> get _history => _sessions
      .where((BackendCareSession s) => !s.isScheduled)
      .toList(growable: false);

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _joinSession(BackendCareSession session) async {
    if (_busySessions.contains(session.id)) return;
    setState(() => _busySessions.add(session.id));
    try {
      var url = session.meetingUrl;
      if (url.isEmpty) {
        final updated = await ref.read(apiClientProvider).ensureMeetLink(
              accessToken: _token,
              sessionId: session.id,
            );
        url = updated.meetingUrl;
      }
      if (!mounted) return;
      if (url.isEmpty) {
        _showMessage(
            'Link video belum tersedia. Coba lagi beberapa saat lagi.');
        return;
      }
      final result = await openMeetLink(url);
      if (!mounted) return;
      if (result == MeetLaunchResult.invalid) {
        _showMessage('Link video tidak valid. Hubungi profesional lewat chat.');
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage('Gagal membuka sesi. ${friendlyErrorMessage(error)}');
    } finally {
      if (mounted) setState(() => _busySessions.remove(session.id));
    }
  }

  Future<void> _copyMeetLink(BackendCareSession session) async {
    if (session.meetingUrl.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: session.meetingUrl));
    if (!mounted) return;
    _showMessage('Tautan video disalin.');
  }

  void _openChat(BackendCareSession session) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(
          otherUserName: session.professionalName,
          otherUserId: session.professionalId,
          otherUserPhotoUrl: session.photoIntroUrl,
        ),
      ),
    );
  }

  Future<void> _cancelSession(BackendCareSession session) async {
    final reason = await showWebReasonDialog(
      context,
      title: 'Batalkan sesi',
      message: 'Sesi dengan ${session.professionalName} pada '
          '${formatWibDateTimeOrDash(session.scheduledDateTime)} WIB akan '
          'dibatalkan. Pembatalan kurang dari 24 jam dapat dikenakan aturan '
          'server.',
      confirmLabel: 'Batalkan sesi',
      destructive: true,
    );
    if (reason == null || !mounted) return;
    try {
      await ref.read(apiClientProvider).updateCareSession(
            accessToken: _token,
            sessionId: session.id,
            status: 'cancelled_by_patient',
            cancelReason: reason,
          );
      if (!mounted) return;
      _showMessage('Sesi dibatalkan.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Gagal membatalkan sesi. ${friendlyErrorMessage(error)}');
    }
  }

  Future<void> _rescheduleSession(BackendCareSession session) async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (BuildContext dialogContext) => _WebRescheduleDialog(
        professionalId: session.professionalId,
      ),
    );
    if (picked == null || !mounted) return;
    try {
      final result = await ref.read(apiClientProvider).rescheduleCareSession(
            accessToken: _token,
            sessionId: session.id,
            scheduledAt: wibApiDateTime(picked),
          );
      if (!mounted) return;
      final warnings = result.warnings;
      _showMessage(warnings.isEmpty
          ? 'Jadwal dipindahkan.'
          : 'Jadwal tersimpan, tetapi kalender profesional perlu diperbarui: '
              '${warnings.join('; ')}');
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Gagal memindahkan jadwal. ${friendlyErrorMessage(error)}');
    }
  }

  Future<void> _cancelPackage(BackendCarePackage carePackage) async {
    final confirmed = await showWebConfirmDialog(
      context,
      title: 'Batalkan paket',
      message: 'Paket ${carePackage.totalSessions} sesi dengan '
          '${carePackage.professionalName} yang belum dibayar akan '
          'dibatalkan.',
      confirmLabel: 'Batalkan paket',
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    try {
      await ref.read(apiClientProvider).cancelPendingCarePackage(
          accessToken: _token, packageId: carePackage.id);
      if (!mounted) return;
      _showMessage('Paket dibatalkan.');
      await _load();
    } catch (error) {
      if (!mounted) return;
      _showMessage('Gagal membatalkan paket. ${friendlyErrorMessage(error)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final nextSession = _upcoming.isEmpty ? null : _upcoming.first;
    final activePackage = _packages.where((BackendCarePackage p) => p.isActive);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WebPageHeader(
          title: 'Jadwal & Paket',
          subtitle: 'Sesi terapi, paket perawatan, dan riwayat konsultasi Anda '
              'dalam WIB.',
          trailing: OutlinedButton.icon(
            onPressed: _loading ? null : () => unawaited(_load()),
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Muat ulang'),
          ),
        ),
        const SizedBox(height: WebSpacing.section),
        WebAdminCard(
          child: Row(
            children: <Widget>[
              const Icon(Icons.event_note_rounded,
                  size: 20, color: MalvaColors.seed),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  nextSession == null
                      ? 'Belum ada sesi terjadwal berikutnya.'
                      : 'Sesi berikutnya: ${nextSession.professionalName} · '
                          '${formatWibDateTimeOrDash(nextSession.scheduledDateTime)} WIB',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${activePackage.length} paket aktif',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B6377)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SegmentedButton<int>(
          segments: const <ButtonSegment<int>>[
            ButtonSegment<int>(value: 0, label: Text('Paket')),
            ButtonSegment<int>(value: 1, label: Text('Jadwal')),
            ButtonSegment<int>(value: 2, label: Text('Riwayat')),
          ],
          selected: <int>{_tab},
          onSelectionChanged: (Set<int> value) =>
              setState(() => _tab = value.first),
        ),
        const SizedBox(height: 14),
        if (_loading)
          const WebAdminCard(child: WebAdminLoading(label: 'Memuat data...'))
        else if (_error != null)
          WebAdminCard(
            child: WebAdminError(
                error: _error!, onRetry: () => unawaited(_load())),
          )
        else
          switch (_tab) {
            0 => _buildPackages(),
            1 => _buildSessions(_upcoming,
                emptyMessage: 'Belum ada sesi terjadwal.'),
            _ =>
              _buildSessions(_history, emptyMessage: 'Belum ada riwayat sesi.'),
          },
      ],
    );
  }

  Widget _buildPackages() {
    if (_packages.isEmpty) {
      return const WebAdminCard(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 26),
          child: Text(
            'Belum ada paket perawatan.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Color(0xFF8B8194)),
          ),
        ),
      );
    }
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final columns = constraints.maxWidth >= 1000 ? 2 : 1;
        final width =
            (constraints.maxWidth - WebSpacing.cardGap * (columns - 1)) /
                columns;
        return Wrap(
          spacing: WebSpacing.cardGap,
          runSpacing: WebSpacing.cardGap,
          children: _packages.map((BackendCarePackage carePackage) {
            final canCancel = carePackage.status == 'pending_payment';
            return SizedBox(
              width: width,
              child: WebAdminCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            carePackage.professionalName.isEmpty
                                ? 'Paket perawatan'
                                : carePackage.professionalName,
                            style: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        WebStatusPill(
                          label: webCarePackageStatusLabel(carePackage.status),
                          color: carePackage.isActive
                              ? MalvaColors.mint
                              : MalvaColors.amber,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Sisa ${carePackage.remainingSessions} dari '
                      '${carePackage.totalSessions} sesi',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      carePackage.expiresDateTime == null
                          ? 'Masa berlaku ${carePackage.validityDays} hari'
                          : 'Berlaku sampai '
                              '${formatWibDate(carePackage.expiresDateTime!)}',
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: Color(0xFF6B6377),
                      ),
                    ),
                    if (carePackage.price > 0) ...<Widget>[
                      const SizedBox(height: 4),
                      Text(
                        formatRupiah(carePackage.price),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                    if (canCancel) ...<Widget>[
                      const SizedBox(height: 10),
                      OutlinedButton(
                        key: Key('web-package-cancel-${carePackage.id}'),
                        onPressed: () => unawaited(_cancelPackage(carePackage)),
                        child: const Text('Batalkan paket'),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(growable: false),
        );
      },
    );
  }

  Widget _buildSessions(
    List<BackendCareSession> sessions, {
    required String emptyMessage,
  }) {
    if (sessions.isEmpty) {
      return WebAdminCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 26),
          child: Text(
            emptyMessage,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 13, color: Color(0xFF8B8194)),
          ),
        ),
      );
    }
    return Column(
      children: sessions
          .map((BackendCareSession session) => _WebSessionCard(
                session: session,
                busy: _busySessions.contains(session.id),
                onJoin: () => unawaited(_joinSession(session)),
                onCopyLink: () => unawaited(_copyMeetLink(session)),
                onChat: () => _openChat(session),
                onReschedule: () => unawaited(_rescheduleSession(session)),
                onCancel: () => unawaited(_cancelSession(session)),
              ))
          .toList(growable: false),
    );
  }
}

/// Kartu satu sesi perawatan.
class _WebSessionCard extends StatelessWidget {
  const _WebSessionCard({
    required this.session,
    required this.busy,
    required this.onJoin,
    required this.onCopyLink,
    required this.onChat,
    required this.onReschedule,
    required this.onCancel,
  });

  final BackendCareSession session;
  final bool busy;
  final VoidCallback onJoin;
  final VoidCallback onCopyLink;
  final VoidCallback onChat;
  final VoidCallback onReschedule;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final scheduled = session.scheduledDateTime;
    final isVideo = session.isVideo;
    return WebAdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  session.professionalName.isEmpty
                      ? 'Sesi'
                      : session.professionalName,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              WebStatusPill(
                label: webSessionStatusLabel(session.status),
                color:
                    session.isScheduled ? MalvaColors.mint : MalvaColors.amber,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${formatWibDateTimeOrDash(scheduled)} WIB · '
            '${webSessionTypeLabel(session.sessionType)} · '
            '${session.durationMinutes} menit',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B6377)),
          ),
          if (isVideo &&
              session.meetingUrl.isEmpty &&
              session.isScheduled) ...<Widget>[
            const SizedBox(height: 6),
            const Text(
              'Menunggu link video dari profesional.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF8A5A00)),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              if (isVideo)
                FilledButton.icon(
                  key: Key('web-session-join-${session.id}'),
                  onPressed: busy ? null : onJoin,
                  icon: const Icon(Icons.videocam_rounded, size: 17),
                  label: const Text('Gabung'),
                ),
              if (isVideo && session.meetingUrl.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: onCopyLink,
                  icon: const Icon(Icons.link_rounded, size: 17),
                  label: const Text('Salin tautan'),
                ),
              OutlinedButton.icon(
                key: Key('web-session-chat-${session.id}'),
                onPressed: onChat,
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                label: const Text('Chat'),
              ),
              if (session.isScheduled) ...<Widget>[
                TextButton(
                  key: Key('web-session-reschedule-${session.id}'),
                  onPressed: onReschedule,
                  child: const Text('Pindahkan'),
                ),
                TextButton(
                  key: Key('web-session-cancel-${session.id}'),
                  onPressed: onCancel,
                  child: const Text('Batalkan'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Dialog pindah jadwal: pilih tanggal (7 hari) + slot tersedia.
class _WebRescheduleDialog extends ConsumerStatefulWidget {
  const _WebRescheduleDialog({required this.professionalId});

  final String professionalId;

  @override
  ConsumerState<_WebRescheduleDialog> createState() =>
      _WebRescheduleDialogState();
}

class _WebRescheduleDialogState extends ConsumerState<_WebRescheduleDialog> {
  final List<String> _days = webNextSevenDayKeys();
  late String _date = _days.first;
  List<BackendDoctorSlot> _slots = const <BackendDoctorSlot>[];
  bool _loading = true;
  String? _slot;

  String get _token => ref.read(authStateProvider).session?.accessToken ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadSlots());
  }

  Future<void> _loadSlots() async {
    setState(() {
      _loading = true;
      _slot = null;
    });
    try {
      final slots = await ref.read(apiClientProvider).getDoctorAvailableSlots(
            accessToken: _token.isEmpty ? null : _token,
            userId: widget.professionalId,
            date: _date,
          );
      if (!mounted) return;
      setState(() {
        _slots = slots.where((BackendDoctorSlot s) => s.available).toList();
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _slots = const <BackendDoctorSlot>[];
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Pindahkan jadwal',
          style: TextStyle(fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _days.map((String day) {
                final selected = day == _date;
                return InkWell(
                  key: Key('web-reschedule-date-$day'),
                  borderRadius: BorderRadius.circular(9),
                  onTap: () {
                    setState(() => _date = day);
                    unawaited(_loadSlots());
                  },
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color:
                          selected ? MalvaColors.seed : const Color(0xFFF7F3FA),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      webShortDateLabel(day),
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : MalvaColors.ink,
                      ),
                    ),
                  ),
                );
              }).toList(growable: false),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Text('Memuat slot...',
                  style: TextStyle(fontSize: 12, color: Color(0xFF8B8194)))
            else if (_slots.isEmpty)
              const Text('Tidak ada slot pada tanggal ini.',
                  style: TextStyle(fontSize: 12, color: Color(0xFF8B8194)))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _slots.map((BackendDoctorSlot slot) {
                  final selected = _slot == slot.time;
                  return InkWell(
                    key: Key('web-reschedule-slot-${slot.time}'),
                    borderRadius: BorderRadius.circular(9),
                    onTap: () => setState(() => _slot = slot.time),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected
                            ? MalvaColors.seed
                            : const Color(0xFFF7F3FA),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        slot.time.length >= 5
                            ? slot.time.substring(0, 5)
                            : slot.time,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: selected ? Colors.white : MalvaColors.ink,
                        ),
                      ),
                    ),
                  );
                }).toList(growable: false),
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
          key: const Key('web-reschedule-confirm'),
          onPressed: _slot == null
              ? null
              : () {
                  final parts = _slot!.split(':');
                  final date = DateTime.tryParse(_date);
                  if (date == null) return;
                  Navigator.of(context).pop(
                    DateTime(
                      date.year,
                      date.month,
                      date.day,
                      int.tryParse(parts.first) ?? 0,
                      parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0,
                    ),
                  );
                },
          child: const Text('Pindahkan'),
        ),
      ],
    );
  }
}
