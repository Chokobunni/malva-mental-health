import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/providers.dart';
import '../../../services/malva_api_client.dart';
import '../../../services/meeting_launcher.dart';
import '../../../theme.dart';
import '../../../time/wib.dart';
import '../../../widgets/friendly_error.dart';
import '../../../widgets/professional_schedule_calendar.dart';
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
  Map<String, List<BackendCareSession>> _sessions = const {};
  DateTime? _calendarMonth;
  DateTime? _selectedDate;
  bool _loading = true;
  Object? _error;

  String get _token => ref.read(authStateProvider).session?.accessToken ?? '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final scope = _scope;
    final token = _token;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(apiClientProvider);
      final scopes = {'today', 'upcoming', scope};
      final sessions = await Future.wait(scopes.map((scope) async => MapEntry(
          scope,
          await api.listCareSessions(accessToken: token, scope: scope))));
      if (!mounted || scope != _scope || token != _token) return;
      setState(() {
        _sessions = Map.fromEntries(sessions);
        _loading = false;
      });
    } catch (error) {
      if (!mounted || scope != _scope || token != _token) return;
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
    final now = wibNow();
    final month = _calendarMonth ?? wibFromParts(now.year, now.month, 1);
    final byDate = <String, List<BackendCareSession>>{};
    final ids = <String>{};
    for (final scope in ['today', 'upcoming']) {
      for (final session in _sessions[scope] ?? const <BackendCareSession>[]) {
        final at = session.scheduledDateTime;
        if (at != null &&
            session.isScheduled &&
            !session.isAfterJoinWindow &&
            ids.add(session.id)) {
          (byDate[wibDateKey(at)] ??= []).add(session);
        }
      }
    }
    final selectedDate = _selectedDate;
    final selectedKey = selectedDate == null ? null : wibDateKey(selectedDate);
    final filtered = selectedKey != null && byDate.containsKey(selectedKey);
    final rows = _sessions[_scope] ?? const <BackendCareSession>[];
    final visibleRows = _scope == 'upcoming' && filtered
        ? rows.where((session) {
            final at = session.scheduledDateTime;
            return at != null && wibDateKey(at) == selectedKey;
          }).toList()
        : rows;
    void clearSelection() => setState(() => _selectedDate = null);
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
        if (!_loading && _error == null) ...[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: ProfessionalScheduleCalendar(
              month: month,
              today: now,
              sessionsByDate: byDate,
              selectedDate: filtered ? selectedDate : null,
              onClear: clearSelection,
              onMonthChanged: (offset) => setState(() {
                _calendarMonth =
                    wibFromParts(month.year, month.month + offset, 1);
                _selectedDate = null;
              }),
              onDateTapped: (date) {
                final key = wibDateKey(date);
                if (key == selectedKey) {
                  clearSelection();
                } else if (byDate.containsKey(key)) {
                  setState(() => _selectedDate = date);
                } else {
                  ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
                  _showMessage('Tidak ada sesi pada tanggal ini.');
                }
              },
            ),
          ),
          const SizedBox(height: 14),
        ],
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: <Widget>[
            for (final (String scope, String label) in const <(String, String)>[
              ('today', 'Hari ini'),
              ('upcoming', 'Mendatang'),
              ('all', 'Semua'),
            ])
              ChoiceChip(
                key: Key('web-pro-schedule-$scope'),
                label: Text(label),
                selected: _scope == scope,
                onSelected: _loading
                    ? null
                    : (bool selected) {
                        if (!selected) return;
                        setState(() => _scope = scope);
                        unawaited(_load());
                      },
              ),
          ],
        ),
        const SizedBox(height: 14),
        if (_scope == 'upcoming' && !_loading && _error == null) ...[
          Text('${visibleRows.length} sesi • '
              '${filtered ? professionalScheduleDateLabel(selectedDate!) : 'Semua tanggal'}'),
          const SizedBox(height: 8),
        ],
        WebAdminCard(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
          child: _buildBody(visibleRows),
        ),
        if (_scope == 'upcoming' && filtered) ...[
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: clearSelection,
              icon: const Icon(Icons.layers_outlined),
              label: Text('Tampilkan semua sesi (${rows.length})')),
        ],
      ],
    );
  }

  Widget _buildBody(List<BackendCareSession> sessions) {
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
      rowKeyBuilder: (int index) => Key('pro-session-${sessions[index].id}'),
      rows: sessions.map((BackendCareSession session) {
        final isVideo = session.isVideo;
        final at = session.scheduledDateTime;
        return <Widget>[
          Text(
            formatWibDateTimeOrDash(session.scheduledDateTime),
            style: const TextStyle(fontSize: 12),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                session.patientName.isEmpty ? 'Pasien' : session.patientName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
              if (at != null)
                Text(wibWeekdayName(at), style: const TextStyle(fontSize: 11)),
            ],
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
