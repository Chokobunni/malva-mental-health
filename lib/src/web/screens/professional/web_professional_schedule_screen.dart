import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/providers.dart';
import '../../../services/malva_api_client.dart';
import '../../../services/meeting_launcher.dart';
import '../../../theme.dart';
import '../../../widgets/friendly_error.dart';
import '../../services/web_care_service.dart';
import '../../web_format.dart';
import '../../web_theme.dart';
import '../../widgets/web_admin_widgets.dart';
import '../../widgets/web_page_header.dart';

/// Jadwal sesi profesional (`/jadwal` untuk peran profesional).
class WebProfessionalScheduleScreen extends ConsumerStatefulWidget {
  const WebProfessionalScheduleScreen({super.key});

  @override
  ConsumerState<WebProfessionalScheduleScreen> createState() =>
      _WebProfessionalScheduleScreenState();
}

class _WebProfessionalScheduleScreenState
    extends ConsumerState<WebProfessionalScheduleScreen> {
  String _scope = 'upcoming';
  List<BackendCareSession> _sessions = const <BackendCareSession>[];
  bool _loading = true;
  Object? _error;

  String get _token => ref.read(authStateProvider).session?.accessToken ?? '';

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
      final sessions = await ref.read(apiClientProvider).listCareSessions(
            accessToken: _token,
            scope: _scope,
          );
      if (!mounted) return;
      setState(() {
        _sessions = sessions;
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

  void _showMessage(String message) {
    ScaffoldMessenger.maybeOf(context)
        ?.showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _join(BackendCareSession session) async {
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
        _showMessage('Link video belum tersedia.');
        return;
      }
      final result = await openMeetLink(url);
      if (!mounted) return;
      if (result == MeetLaunchResult.invalid) {
        _showMessage('Link video tidak valid. Perbarui lewat aplikasi mobile.');
      }
    } catch (error) {
      if (!mounted) return;
      _showMessage('Gagal membuka sesi. ${friendlyErrorMessage(error)}');
    }
  }

  Future<void> _copyLink(BackendCareSession session) async {
    if (session.meetingUrl.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: session.meetingUrl));
    if (!mounted) return;
    _showMessage('Tautan video disalin.');
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        WebPageHeader(
          title: 'Jadwal',
          subtitle: 'Sesi pasien Anda dalam WIB. Gabung video langsung dari '
              'sini atau salin tautannya.',
          trailing: OutlinedButton.icon(
            onPressed: _loading ? null : () => unawaited(_load()),
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Muat ulang'),
          ),
        ),
        const SizedBox(height: WebSpacing.section),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final (String scope, String label) in const <(String, String)>[
              ('today', 'Hari ini'),
              ('upcoming', 'Akan datang'),
              ('all', 'Semua'),
            ])
              ChoiceChip(
                key: Key('web-pro-schedule-$scope'),
                label: Text(label),
                selected: _scope == scope,
                onSelected: (bool selected) {
                  if (!selected) return;
                  setState(() => _scope = scope);
                  unawaited(_load());
                },
              ),
          ],
        ),
        const SizedBox(height: 14),
        WebAdminCard(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: _buildBody(),
        ),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) return const WebAdminLoading(label: 'Memuat sesi...');
    if (_error != null) {
      return WebAdminError(error: _error!, onRetry: () => unawaited(_load()));
    }
    return WebAdminTable(
      minWidth: 1080,
      emptyMessage: 'Tidak ada sesi pada filter ini.',
      columns: const <WebAdminColumn>[
        WebAdminColumn('WAKTU (WIB)', 170),
        WebAdminColumn('PASIEN', 220),
        WebAdminColumn('TIPE', 100),
        WebAdminColumn('DURASI', 90),
        WebAdminColumn('STATUS', 160),
        WebAdminColumn('AKSI', 240, align: Alignment.centerRight),
      ],
      rowKeyBuilder: (int index) => Key('pro-session-${_sessions[index].id}'),
      rows: _sessions.map((BackendCareSession session) {
        final isVideo = session.isVideo;
        return <Widget>[
          Text(
            formatWibDateTimeOrDash(session.scheduledDateTime),
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            session.patientName.isEmpty
                ? session.patientId
                : session.patientName,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            webSessionTypeLabel(session.sessionType),
            style: const TextStyle(fontSize: 12),
          ),
          Text(
            '${session.durationMinutes} mnt',
            style: const TextStyle(fontSize: 12),
          ),
          WebStatusPill(
            label: webSessionStatusLabel(session.status),
            color: session.isScheduled ? MalvaColors.mint : MalvaColors.amber,
          ),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 6,
            children: <Widget>[
              if (isVideo)
                FilledButton(
                  key: Key('web-pro-join-${session.id}'),
                  onPressed: () => unawaited(_join(session)),
                  child: const Text('Gabung'),
                ),
              if (isVideo && session.meetingUrl.isNotEmpty)
                TextButton(
                  onPressed: () => unawaited(_copyLink(session)),
                  child: const Text('Salin'),
                ),
            ],
          ),
        ];
      }).toList(growable: false),
    );
  }
}
