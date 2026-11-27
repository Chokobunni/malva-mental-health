import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/care_session_refresh.dart';
import '../widgets/session_attendance_actions.dart';
import '../services/malva_api_client.dart';
import '../services/server_clock.dart';
import '../theme.dart';
import '../time/wib.dart';
import '../widgets/friendly_error.dart';
import '../widgets/session_cancellation_sheet.dart';
import '../widgets/care_reference_widgets.dart';
import '../widgets/malva_components.dart';
import '../widgets/professional_schedule_calendar.dart';
import '../widgets/care_session_card.dart';
import '../widgets/professional_availability_summary.dart';
import 'chat_screen.dart';
import 'pro_patient_detail_screen.dart';

// ============================================================
// PRO SCHEDULE — tab "Jadwal" dashboard profesional:
//   - Sesi hari ini & mendatang: join chat, tandai hadir/tidak,
//     batal (kredit kembali), penjadwalan ulang, dan tautan video.
// Pengaturan ketersediaan/harga dibuka dari Home profesional.
// Semua dari server — tanpa data demo.
// ============================================================

class ProScheduleScreen extends ConsumerStatefulWidget {
  const ProScheduleScreen(
      {super.key, this.session, this.apiClient, this.header});

  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final Widget? header;

  @override
  ConsumerState<ProScheduleScreen> createState() => _ProScheduleScreenState();
}

class _ProScheduleScreenState extends ConsumerState<ProScheduleScreen>
    with WidgetsBindingObserver {
  late final CareSessionRefresh _sessionRefresh;
  List<BackendCareSession> _today = const [];
  List<BackendCareSession> _upcoming = const [];
  List<BackendCareSession> _past = const [];
  bool _isLoading = true;
  bool _loadInProgress = false;
  bool _historyExpanded = false;
  String _historyFilter = 'completed';

  static const _historyFilters = [
    ('completed', 'Selesai'),
    ('cancelled', 'Dibatalkan'),
    ('no_show', 'Tidak Hadir'),
    ('all', 'Semua'),
  ];

  bool _matchesHistory(BackendCareSession session, String filter) =>
      switch (filter) {
        'all' => true,
        'cancelled' => isCareSessionCancelled(session),
        _ => session.status == filter,
      };

  DateTime? _calendarMonth;
  DateTime? _selectedDate;
  String? _error;

  MalvaApiClient get _api => widget.apiClient ?? ref.read(apiClientProvider);
  String? get _token {
    final t = widget.session?.accessToken;
    return (t == null || t.isEmpty) ? null : t;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionRefresh = CareSessionRefresh(() {
      if (!mounted) return;
      setState(() {});
      unawaited(_load(silent: true));
    });
    _load();
  }

  @override
  void dispose() {
    _sessionRefresh.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      setState(() {});
      unawaited(_load(silent: true));
    }
  }

  Future<void> _load({bool silent = false}) async {
    if (_loadInProgress) return;
    final token = _token;
    if (token == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Login dulu untuk melihat jadwal.';
        });
      }
      return;
    }
    if (!silent) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }
    _loadInProgress = true;
    try {
      final results = await Future.wait([
        _api.listCareSessions(accessToken: token, scope: 'today'),
        _api.listCareSessions(accessToken: token, scope: 'upcoming'),
        _api.listCareSessions(accessToken: token, scope: 'past'),
      ]);
      if (!mounted) return;
      setState(() {
        _error = null;
        _today = results[0];
        _upcoming = results[1]
          ..sort(
              (a, b) => (a.scheduledAt ?? '').compareTo(b.scheduledAt ?? ''));
        _past = results[2];
        _isLoading = false;
      });
      _sessionRefresh.update([..._today, ..._upcoming, ..._past]);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorMessage(e);
        _isLoading = false;
      });
    } finally {
      _loadInProgress = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final sessionsById = <String, BackendCareSession>{};
    for (final s in [..._today, ..._upcoming, ..._past]) {
      if (sessionsById[s.id]?.isScheduled ?? true) sessionsById[s.id] = s;
    }
    final all = sessionsById.values.toList()
      ..sort((a, b) => (a.scheduledAt ?? '').compareTo(b.scheduledAt ?? ''));
    final needsCompletion =
        all.where((s) => s.isScheduled && s.isAfterJoinWindow).toList();
    final past = all
        .where((s) =>
            s.status == 'completed' ||
            s.status == 'no_show' ||
            isCareSessionCancelled(s))
        .toList()
        .reversed
        .toList();
    final active =
        all.where((s) => s.isScheduled && !s.isAfterJoinWindow).toList();
    final now = ServerClock.now();
    final todayKey = wibDateKey(now);
    final month = _calendarMonth ?? wibFromParts(now.year, now.month, 1);
    final byDate = <String, List<BackendCareSession>>{};
    for (final s in (_historyExpanded ? past : active)) {
      final at = s.scheduledDateTime;
      if (at != null) (byDate[wibDateKey(at)] ??= []).add(s);
    }
    final selectedKey =
        _selectedDate == null ? null : wibDateKey(_selectedDate!);
    bool selected(BackendCareSession s) =>
        selectedKey == null ||
        (s.scheduledDateTime != null &&
            wibDateKey(s.scheduledDateTime!) == selectedKey);
    final today = active
        .where((s) =>
            s.scheduledDateTime != null &&
            wibDateKey(s.scheduledDateTime!) == todayKey &&
            selected(s))
        .toList();
    final upcoming = active
        .where((s) =>
            s.scheduledDateTime == null ||
            wibDateKey(s.scheduledDateTime!) != todayKey)
        .where(selected)
        .toList();
    final history = past.where(selected).toList();
    final filteredHistory =
        history.where((s) => _matchesHistory(s, _historyFilter)).toList();
    Widget cards(List<BackendCareSession> sessions, String prefix) =>
        Column(children: [
          for (final s in sessions)
            Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _ProSessionCard(
                    key: ValueKey('$prefix-${s.id}'),
                    session: s,
                    onChanged: _load,
                    accessToken: _token,
                    apiClient: _api))
        ]);
    Widget tab(String title, bool history) => Expanded(
        child: InkWell(
            key: history ? const ValueKey('session-history-toggle') : null,
            onTap: () => setState(() {
                  _historyExpanded = history;
                  _selectedDate = null;
                }),
            child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
                decoration: BoxDecoration(
                    color: _historyExpanded == history
                        ? const Color(0xffead5f2)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(14)),
                child: Text(title,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: _historyExpanded == history
                            ? MalvaColors.seed
                            : Colors.black54)))));
    return Column(children: [
      if (widget.header != null)
        Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
            child: widget.header!),
      Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xffe9dcef))),
          child: Row(children: [
            tab('List Sesi', false),
            tab('Riwayat Sesi (${past.length})', true)
          ])),
      Expanded(
          child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(18), children: [
                if (_isLoading)
                  const Center(child: CircularProgressIndicator())
                else if (_error != null)
                  SoftCard(
                      child: Column(children: [
                    Text(_error!,
                        style: const TextStyle(color: MalvaColors.danger)),
                    OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Coba Lagi'))
                  ]))
                else ...[
                  if (!_historyExpanded && needsCompletion.isNotEmpty) ...[
                    const SectionLabel('Perlu diselesaikan',
                        icon: Icons.task_alt_rounded),
                    cards(needsCompletion, 'complete')
                  ],
                  Container(
                      padding: const EdgeInsets.all(14),
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(15)),
                      child: Row(children: [
                        const Icon(Icons.calendar_today_outlined,
                            color: MalvaColors.seed),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text('Hari ini • ${wibWeekdayDate(now)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800))),
                        Text(
                            '${active.where((s) => s.scheduledDateTime != null && wibDateKey(s.scheduledDateTime!) == todayKey).length} sesi',
                            style: const TextStyle(
                                color: MalvaColors.seed,
                                fontWeight: FontWeight.w700))
                      ])),
                  if (!_historyExpanded) ...[
                    ProfessionalScheduleCalendar(
                        month: month,
                        today: now,
                        sessionsByDate: byDate,
                        selectedDate: _selectedDate,
                        onMonthChanged: (offset) => setState(() {
                              _calendarMonth = wibFromParts(
                                  month.year, month.month + offset, 1);
                              _selectedDate = null;
                            }),
                        onClear: () => setState(() => _selectedDate = null),
                        onDateTapped: (date) {
                          if (!byDate.containsKey(wibDateKey(date))) {
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(const SnackBar(
                                  content: Text(
                                      'Tidak ada sesi pada tanggal ini.')));
                            return;
                          }
                          setState(() => _selectedDate =
                              wibDateKey(date) == selectedKey ? null : date);
                        }),
                    const SizedBox(height: 14)
                  ],
                  Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        Text(_historyExpanded ? 'Riwayat Sesi' : 'Daftar Sesi',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 20)),
                        FilledButton(
                            onPressed: () async {
                              final date = await showDatePicker(
                                  context: context,
                                  initialDate: _selectedDate ?? now,
                                  firstDate: wibFromParts(2020, 1, 1),
                                  lastDate:
                                      wibFromParts(now.year + 10, 12, 31));
                              if (date != null && mounted)
                                setState(() => _selectedDate = wibFromParts(
                                    date.year, date.month, date.day));
                            },
                            style: FilledButton.styleFrom(
                                backgroundColor: MalvaColors.seed,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 13, vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(15))),
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              const Icon(Icons.calendar_today_outlined,
                                  size: 18),
                              const SizedBox(width: 8),
                              Text(_selectedDate == null
                                  ? 'Semua tanggal'
                                  : professionalScheduleDateLabel(
                                      _selectedDate!)),
                              const SizedBox(width: 7),
                              const Icon(Icons.keyboard_arrow_down, size: 20)
                            ]))
                      ]),
                  if (_selectedDate != null)
                    Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                            onPressed: () =>
                                setState(() => _selectedDate = null),
                            child: const Text('Tampilkan semua sesi'))),
                  const SizedBox(height: 14),
                  if (_historyExpanded) ...[
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final (filter, label) in _historyFilters)
                          ChoiceChip(
                            label: Text(
                                '$label ${history.where((s) => _matchesHistory(s, filter)).length}'),
                            selected: _historyFilter == filter,
                            onSelected: (_) =>
                                setState(() => _historyFilter = filter),
                            showCheckmark: false,
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (filteredHistory.isEmpty)
                      const EmptyState(
                          icon: Icons.history_rounded,
                          title: 'Belum ada riwayat',
                          subtitle: 'Sesi selesai / batal tercatat di sini.')
                    else
                      cards(filteredHistory, 'past')
                  ] else ...[
                    if (today.isEmpty)
                      const CareIllustratedCard(
                          horizontal: true,
                          imageHeight: 85,
                          asset: 'pro-today',
                          title: 'Sesi hari ini',
                          subtitle: 'Tidak ada sesi hari ini')
                    else ...[
                      const SectionLabel('Sesi hari ini'),
                      cards(today, 'today')
                    ],
                    const SizedBox(height: 14),
                    const SectionLabel('Mendatang'),
                    if (upcoming.isEmpty)
                      const CareIllustratedCard(
                          horizontal: true,
                          imageHeight: 85,
                          asset: 'pro-upcoming',
                          title: 'Belum ada sesi mendatang')
                    else
                      cards(upcoming, 'upcoming'),
                  ]
                ]
              ])))
    ]);
  }
}

class _ProSessionCard extends ConsumerWidget {
  const _ProSessionCard(
      {super.key,
      required this.session,
      required this.onChanged,
      this.apiClient,
      this.accessToken});

  final BackendCareSession session;
  final MalvaApiClient? apiClient;
  final String? accessToken;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        CareSessionCard(
            session: session,
            role: UserRole.professional,
            detailLabel: session.isScheduled
                ? 'Lihat Detail Sesi'
                : 'Lihat Detail & Catatan Sesi',
            onChanged: onChanged,
            accessToken: accessToken,
            apiClient: apiClient,
            onProfile: () =>
                _openPatientDetail(context, ref, session, apiClient),
            onOpenChat: () => _openChat(context),
            otherActions: session.isScheduled && !session.isAfterJoinWindow
                ? ProfessionalSessionActions(
                    session: session,
                    onChanged: onChanged,
                    accessToken: accessToken,
                    apiClient: apiClient)
                : null),
        if (session.isScheduled && !session.isBeforeJoinWindow)
          Padding(
              padding: const EdgeInsets.all(12),
              child: SessionAttendanceActions(
                  session: session,
                  role: UserRole.professional,
                  onChanged: onChanged,
                  accessToken: accessToken,
                  apiClient: apiClient)),
      ]);
  void _openChat(BuildContext context) {
    if (!session.canJoinNow) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ChatScreen(
                otherUserName: session.patientName.isEmpty
                    ? 'Pasien'
                    : session.patientName,
                otherUserId: session.patientId)));
  }
}

class ProfessionalSessionActions extends ConsumerWidget {
  const ProfessionalSessionActions(
      {super.key,
      required this.session,
      required this.onChanged,
      this.apiClient,
      this.accessToken,
      this.futureCancellationOnly = false});
  final BackendCareSession session;
  final Future<void> Function() onChanged;
  final MalvaApiClient? apiClient;
  final String? accessToken;
  final bool futureCancellationOnly;

  bool get _canCancel =>
      !futureCancellationOnly ||
      (session.scheduledDateTime?.isAfter(ServerClock.now()) ?? false);

  @override
  Widget build(BuildContext context, WidgetRef ref) => Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
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
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: Colors.black54)),
          children: [
            LayoutBuilder(builder: (context, constraints) {
              Widget action(IconData icon, String label, VoidCallback? callback,
                      {bool full = false, bool danger = false}) =>
                  SizedBox(
                      width: full
                          ? constraints.maxWidth
                          : (constraints.maxWidth - 8) / 2,
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
                                  borderRadius: BorderRadius.circular(12)),
                              textStyle:
                                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                          icon: Icon(icon, size: 17),
                          label: Text(label, textAlign: TextAlign.center)));
              return Wrap(spacing: 8, runSpacing: 8, children: [
                if (!session.isVideo)
                  action(Icons.event_repeat, 'Reschedule',
                      () => _reschedule(context, ref),
                      full: true),
                action(Icons.person_outline, 'Profil',
                    () => _openPatientDetail(context, ref, session, apiClient)),
                action(Icons.cancel_outlined, 'Batal',
                    _canCancel ? () => _cancel(context, ref) : null,
                    danger: true),
                if (session.isVideo) ...[
                  action(Icons.event_repeat, 'Reschedule',
                      () => _reschedule(context, ref)),
                  action(Icons.link, 'Link', () async {
                    if (session.meetingUrl.trim().isEmpty) {
                      await _editLink(context, ref);
                    } else {
                      await Clipboard.setData(
                          ClipboardData(text: session.meetingUrl));
                      if (context.mounted)
                        ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text('Link sesi disalin.')));
                    }
                  })
                ],
              ]);
            })
          ]));
  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final reason = await showSessionCancellationSheet(context,
        session: session, professional: true);
    if (reason == null || !context.mounted || !_canCancel) return;
    final MalvaApiClient api = apiClient ?? ref.read(apiClientProvider);
    final token = accessToken ?? ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      await api.updateCareSession(
        accessToken: token,
        sessionId: session.id,
        status: 'cancelled_by_professional',
        cancelReason: reason,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(session.packageId?.trim().isNotEmpty == true
                ? 'Sesi dibatalkan. Kredit pasien dikembalikan.'
                : 'Sesi dibatalkan. Pengembalian dana pasien diproses.')),
      );
      await onChanged();
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }

  Future<void> _reschedule(BuildContext context, WidgetRef ref) async {
    var date = '';
    var time = '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Jadwalkan ulang sesi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              onChanged: (value) => date = value,
              decoration: const InputDecoration(
                  labelText: 'Tanggal (YYYY-MM-DD)', hintText: '2026-10-20'),
            ),
            const SizedBox(height: 8),
            TextField(
              onChanged: (value) => time = value,
              decoration: const InputDecoration(
                  labelText: 'Jam (HH:MM)', hintText: '10:00'),
            ),
            const SizedBox(height: 6),
            Text(
              'Pilih slot dalam jam praktikmu. Jadwal baru boleh melewati kedaluwarsa paket.',
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: compactFilledButtonStyle,
            child: const Text('Pindahkan'),
          ),
        ],
      ),
    );
    final scheduledAt = '${date.trim()}T${time.trim()}';
    if (confirmed != true || !context.mounted) return;
    final MalvaApiClient api = apiClient ?? ref.read(apiClientProvider);
    final token = accessToken ?? ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      final result = await api.rescheduleCareSession(
        accessToken: token,
        sessionId: session.id,
        scheduledAt: scheduledAt,
      );
      if (!context.mounted) return;
      // Bila server mengirim peringatan non-fatal (mis. event Google Calendar
      // gagal diperbarui), tampilkan HANYA pesan bahaya — jangan "berhasil"
      // lebih dulu, karena itu bertentangan dan menyesatkan. Pesan peringatan
      // server sudah menyebut jadwal tersimpan.
      final messenger = ScaffoldMessenger.of(context);
      if (result.warnings.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Sesi berhasil dijadwalkan ulang.')),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(result.warnings.join(' ')),
            backgroundColor: MalvaColors.danger,
            duration: const Duration(seconds: 6),
          ),
        );
      }
      await onChanged();
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }

  Future<void> _editLink(BuildContext context, WidgetRef ref) async {
    var meeting = session.meetingUrl;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link sesi video'),
        content: TextFormField(
          initialValue: meeting,
          onChanged: (value) => meeting = value,
          decoration: const InputDecoration(
              labelText: 'Link Google Meet',
              hintText: 'https://meet.google.com/...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          if (session.meetingUrl.trim().isEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Buat link Meet'),
            ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: compactFilledButtonStyle,
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    if (saved == null || !context.mounted) return;
    final MalvaApiClient api = apiClient ?? ref.read(apiClientProvider);
    final token = accessToken ?? ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      if (saved) {
        await api.updateCareSession(
          accessToken: token,
          sessionId: session.id,
          meetingUrl: meeting.trim(),
        );
      } else {
        await api.ensureMeetLink(accessToken: token, sessionId: session.id);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link sesi tersimpan.')),
      );
      await onChanged();
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }
}

class ProAvailabilityScreen extends ConsumerStatefulWidget {
  const ProAvailabilityScreen({super.key, this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<ProAvailabilityScreen> createState() =>
      _ProAvailabilityScreenState();
}

class _ProAvailabilityScreenState extends ConsumerState<ProAvailabilityScreen> {
  List<BackendProfessionalSchedule> _schedules = const [];
  Map<String, bool> _usePrimarySchedule = const {};
  bool _isLoading = true;
  String? _error;

  final _chatPrice = TextEditingController();
  final _videoPrice = TextEditingController();
  final _packagePrice = TextEditingController();
  int _patientCapacity = 2;
  int _savedPatientCapacity = 2;
  bool _savingCapacity = false;
  bool _savingSchedules = false;
  bool _savingPricing = false;

  MalvaApiClient get _api => widget.apiClient ?? ref.read(apiClientProvider);
  String? get _token {
    final t = widget.session?.accessToken;
    return (t == null || t.isEmpty) ? null : t;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _chatPrice.dispose();
    _videoPrice.dispose();
    _packagePrice.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = _token;
    if (token == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Login dulu.';
        });
      }
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getMyScheduleSettings(accessToken: token),
        _api.getPricing(accessToken: token),
      ]);
      if (!mounted) return;
      final settings = results[0] as BackendProfessionalScheduleSettings;
      final pricing = results[1] as BackendProfessionalPricing;
      setState(() {
        _schedules = settings.schedules;
        _usePrimarySchedule = settings.usePrimarySchedule;
        _savedPatientCapacity = pricing.patientCapacity ?? 2;
        _patientCapacity = pricing.patientCapacity ?? 2;
        _chatPrice.text = formatProfessionalPrice(pricing.quickChatPrice);
        _videoPrice.text = formatProfessionalPrice(pricing.quickVideoPrice);
        _packagePrice.text = formatProfessionalPrice(pricing.packagePrice);
        _isLoading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorMessage(e);
        _isLoading = false;
      });
    }
  }

  static const _dayNames = [
    'Minggu',
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu'
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).brightness == Brightness.light
          ? const Color(0xFFFAF9FC)
          : null,
      appBar: AppBar(
        title: const Text('Ketersediaan & Harga',
            style: TextStyle(fontFamily: 'Roboto')),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      bottomNavigationBar: _isLoading || _error != null
          ? null
          : SafeArea(
              child: Container(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                  decoration: const BoxDecoration(
                      color: Colors.white,
                      border:
                          Border(top: BorderSide(color: Color(0xFFEDE7F1)))),
                  child: FilledButton.icon(
                      onPressed:
                          _savingPricing || _savingCapacity || _savingSchedules
                              ? null
                              : _savePricing,
                      style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(22))),
                      icon: const Icon(Icons.save_outlined),
                      label: Text(_savingPricing
                          ? 'Menyimpan...'
                          : 'Simpan harga & jadwal')))),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Coba Lagi'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () async {
                    if (!_savingSchedules &&
                        !_savingPricing &&
                        !_savingCapacity) await _load();
                  },
                  child: ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      const Row(
                        children: [
                          Expanded(
                              child: Text('Hari praktik',
                                  style: TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900))),
                          StatusPill(label: 'WIB', color: MalvaColors.seed),
                        ],
                      ),
                      const Text(
                          'Jadwal aktif tampil otomatis di sisi pasien.'),
                      const SizedBox(height: 12),
                      for (final category in [
                        'shared',
                        'quick_chat',
                        'quick_video',
                        'package'
                      ]) ...[
                        if (category == 'quick_chat') ...[
                          const SizedBox(height: 10),
                          const Text('JADWAL PER LAYANAN',
                              style: TextStyle(
                                  color: Color(0xFFAA88B3),
                                  fontWeight: FontWeight.w700)),
                          const SizedBox(height: 18)
                        ],
                        _categoryCard(category),
                        const SizedBox(height: 18),
                      ],
                      const Text('Harga layanan',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w900)),
                      const Text(
                          'Tarif bersih yang akan ditampilkan kepada pasien.',
                          style: TextStyle(color: Color(0xFF7B8791))),
                      const SizedBox(height: 16),
                      ProfessionalPriceCard(
                        showSaveButton: false,
                        chat: _chatPrice,
                        video: _videoPrice,
                        package: _packagePrice,
                        onSave: _savePricing,
                        isSaving: _savingPricing || _savingCapacity,
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
    );
  }

  InputDecoration _scheduleField(BuildContext context, String label) {
    final colors = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: colors.outlineVariant),
    );
    return InputDecoration(
      labelText: label,
      floatingLabelBehavior: FloatingLabelBehavior.always,
      isDense: true,
      filled: true,
      fillColor: colors.surfaceContainerLowest,
      contentPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 11),
      border: border,
      enabledBorder: border,
    );
  }

  bool _usesPrimary(String category) =>
      _usePrimarySchedule[category] ??
      (category != 'package' &&
          !_schedules.any((row) => row.serviceCategory == category));

  List<BackendProfessionalSchedule> _storedRows(String category) =>
      _schedules.where((row) => row.serviceCategory == category).toList();

  List<BackendProfessionalSchedule> _effectiveRows(String category) =>
      _storedRows(_usesPrimary(category) ? 'shared' : category);

  bool _overlapsQuick(int day, String start, String end) {
    return [..._effectiveRows('quick_chat'), ..._effectiveRows('quick_video')]
        .any((quick) =>
            quick.isActive &&
            quick.dayOfWeek == day &&
            start.compareTo(quick.endTime) < 0 &&
            quick.startTime.compareTo(end) < 0);
  }

  Widget _scheduleWarning() => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Text(
          'Jam ini juga tersedia untuk Quick Session. Sebaiknya pilih jam lain '
          'agar lebih mudah menyediakan slot untuk 4 sesi dalam 6 minggu.',
          style:
              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );

  Widget _categoryCard(String category) {
    final primary = category == 'shared';
    final inherited = !primary && _usesPrimary(category);
    final rows = _effectiveRows(category)
      ..sort((a, b) {
        final day = ((a.dayOfWeek + 6) % 7).compareTo((b.dayOfWeek + 6) % 7);
        return day == 0 ? a.startTime.compareTo(b.startTime) : day;
      });
    final color = switch (category) {
      'package' => const Color(0xFF168369),
      'shared' => const Color(0xFFCC911F),
      'quick_chat' => const Color(0xFF1484AF),
      _ => const Color(0xFF5E4AD2)
    };
    return SoftCard(
      radius: 24,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              professionalServiceArtwork(category),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(professionalServiceNames[category]!,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w800)),
                    Text(
                        switch (category) {
                          'quick_chat' => 'Konsultasi via pesan singkat',
                          'quick_video' => 'Konsultasi tatap muka daring',
                          'package' => 'Paket pendampingan 4 sesi',
                          _ =>
                            'Atur jam praktik mingguan yang bisa digunakan oleh beberapa layanan.',
                        },
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF98A2AD))),
                  ])),
              const SizedBox(width: 6),
              StatusPill(
                  label: '${rows.where((row) => row.isActive).length} aktif',
                  color: color),
            ],
          ),
          const Divider(height: 28, color: Color(0xFFF1EEF4)),
          if (!primary)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Gunakan jadwal praktik utama'),
              value: inherited,
              onChanged: _savingSchedules
                  ? null
                  : (usePrimary) => _writeSchedules(
                        'Pilihan jadwal disimpan.',
                        usePrimarySchedule: {category: usePrimary},
                      ),
            ),
          if (!inherited) ...[
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(category == 'package'
                    ? 'Tambahkan jadwal khusus untuk membuka pemesanan paket.'
                    : 'Belum ada jadwal.'),
              )
            else
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const Divider(height: 1),
                _scheduleRow(rows[i], category),
              ],
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFE5DAEA)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16))),
                    onPressed:
                        _savingSchedules ? null : () => _editSchedule(category),
                    icon: const Icon(Icons.add_rounded),
                    label: Text(
                        primary ? 'Tambah jadwal' : 'Tambah jadwal khusus'),
                  )),
            ),
          ],
          if (category == 'package' &&
              rows.any((row) =>
                  row.isActive &&
                  _overlapsQuick(row.dayOfWeek, row.startTime, row.endTime)))
            _scheduleWarning(),
          if (category == 'package') ...[
            const SizedBox(height: 12),
            _capacityControls(),
          ],
        ],
      ),
    );
  }

  Widget _capacityControls() {
    final capacity = _patientCapacity;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: MalvaColors.seed.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    const Text('Slot pasien aktif',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    const Text('Khusus Paket',
                        style:
                            TextStyle(color: Color(0xFF23826D), fontSize: 11)),
                    Text(
                        capacity == 0
                            ? 'Ditutup untuk pasien baru'
                            : 'Maks. $capacity pasien aktif',
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF87939E))),
                  ])),
              const SizedBox(width: 8),
              Container(
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFEDE8F2))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      tooltip: 'Kurangi kapasitas',
                      onPressed: _savingCapacity || capacity == 0
                          ? null
                          : () =>
                              setState(() => _patientCapacity = capacity - 1),
                      icon: const Icon(Icons.remove),
                    ),
                    Text('$capacity',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    IconButton(
                      tooltip: 'Tambah kapasitas',
                      onPressed: _savingCapacity || capacity >= 2147483647
                          ? null
                          : () =>
                              setState(() => _patientCapacity = capacity + 1),
                      icon: const Icon(Icons.add),
                    ),
                  ])),
            ]),
            if (_savingCapacity || capacity != _savedPatientCapacity)
              FilledButton(
                onPressed:
                    _savingCapacity || _savingPricing ? null : _saveCapacity,
                child: Text(
                    _savingCapacity ? 'Menyimpan...' : 'Simpan kapasitas',
                    style: const TextStyle(fontFamily: 'Roboto')),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveCapacity() async {
    final token = _token;
    if (token == null || _savingCapacity || _savingPricing) return;
    final capacity = _patientCapacity;
    setState(() => _savingCapacity = true);
    try {
      final updated = await _api.updatePricing(
        accessToken: token,
        patientCapacity: capacity,
      );
      if (!mounted) return;
      setState(() {
        _savedPatientCapacity = updated.patientCapacity ?? 2;
        _patientCapacity = updated.patientCapacity ?? 2;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kapasitas tersimpan.')),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(error))),
      );
    } finally {
      if (mounted) setState(() => _savingCapacity = false);
    }
  }

  Widget _scheduleRow(BackendProfessionalSchedule schedule, String category) {
    final day = _dayNames[schedule.dayOfWeek];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  children: [
                    Text(day,
                        style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: schedule.isActive
                                ? null
                                : const Color(0xFF98A2AD))),
                    if (!schedule.isActive)
                      const StatusPill(label: 'Nonaktif', color: Colors.grey),
                  ],
                ),
                Text(
                    '${schedule.startTime}–${schedule.endTime} · ${schedule.slotDurationMinutes} mnt/slot'),
              ],
            ),
          ),
          Semantics(
            label: 'Jadwal $day',
            child: Transform.scale(
              scale: .80,
              child: Switch(
                value: schedule.isActive,
                activeTrackColor: MalvaColors.seed,
                inactiveThumbColor: Colors.white,
                inactiveTrackColor: const Color(0xFFDDDCE1),
                trackOutlineColor:
                    const WidgetStatePropertyAll(Colors.transparent),
                onChanged: _savingSchedules
                    ? null
                    : (_) => _toggleSchedule(schedule, category),
              ),
            ),
          ),
          PopupMenuButton<bool>(
            tooltip: 'Opsi jadwal',
            enabled: !_savingSchedules,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            color: Theme.of(context).colorScheme.surface,
            onSelected: (edit) {
              if (edit) {
                _editSchedule(category, schedule);
              } else {
                _removeSchedule(schedule);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                  value: true,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(Icons.edit_outlined, color: MalvaColors.seed),
                    title: Text('Edit jadwal'),
                  )),
              PopupMenuItem(
                  value: false,
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading:
                        Icon(Icons.delete_outline, color: MalvaColors.danger),
                    title: Text('Hapus permanen',
                        style: TextStyle(color: MalvaColors.danger)),
                  )),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editSchedule(String category,
      [BackendProfessionalSchedule? schedule]) async {
    var day = schedule?.dayOfWeek ?? 1;
    var start = schedule?.startTime ?? '09:00';
    var end = schedule?.endTime ?? '16:00';
    final currentDuration = schedule?.slotDurationMinutes ?? 60;
    var durationText = '${currentDuration < 60 ? 60 : currentDuration}';
    var isActive = schedule?.isActive ?? true;
    String? error;
    final isNew = schedule == null;
    const choices = [60, 90, 120];
    var custom = !choices.contains(int.tryParse(durationText));
    const accent = Color(0xff8d4897);
    const border = Color(0xffe0cce4);
    const ink = Color(0xff171d2e);
    const muted = Color(0xff637083);
    const lilac = Color(0xfff3e6f6);
    final cardShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: border),
    );
    final edited = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final duration = int.tryParse(durationText.trim()) ?? 0;
          final slots = duration > 0 && _validScheduleTimes(start, end)
              ? (_scheduleMinutes(end) - _scheduleMinutes(start)) ~/ duration
              : 0;
          void save() {
            final minutes = int.tryParse(durationText.trim()) ?? 0;
            final invalid = _scheduleValidation(start, end, minutes);
            if (invalid != null) {
              setSheetState(() => error = invalid);
              return;
            }
            if (_storedRows(category).any((other) =>
                other.id != schedule?.id &&
                other.dayOfWeek == day &&
                other.startTime == start &&
                other.endTime == end)) {
              setSheetState(() =>
                  error = 'Jadwal dengan hari dan jam tersebut sudah ada.');
              return;
            }
            Navigator.pop(sheetContext, {
              if (schedule != null) 'id': schedule.id,
              'service_category': category,
              'day_of_week': day,
              'start_time': start,
              'end_time': end,
              'slot_duration_minutes': minutes,
              'is_active': isActive,
            });
          }

          Widget timeField(
              String label, String time, ValueChanged<String> put) {
            final value = _scheduleMinutes(time);
            final hour = value ~/ 60;
            final display =
                '${(hour + 11) % 12 + 1}:${time.substring(3)} ${hour < 12 ? 'AM' : 'PM'}';
            return Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: ink,
                  side: const BorderSide(color: border),
                  shape: cardShape,
                  padding: const EdgeInsets.all(13),
                ),
                onPressed: () async {
                  final picked = await _pickScheduleTime(context, value, label);
                  if (picked == null || !context.mounted) return;
                  final hh = picked.hour.toString().padLeft(2, '0');
                  final mm = picked.minute.toString().padLeft(2, '0');
                  setSheetState(() {
                    put('$hh:$mm');
                    error = null;
                  });
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(label, style: const TextStyle(color: muted)),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Expanded(
                            child: Text(display,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16))),
                        const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }

          Widget summaryRow(String label, String value, Color color) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                      child: Text(label, style: const TextStyle(color: muted))),
                  const SizedBox(width: 8),
                  Flexible(
                      child: Text(value,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                              color: color, fontWeight: FontWeight.w800))),
                ],
              );

          return SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                  10, 10, 10, MediaQuery.viewInsetsOf(context).bottom + 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 510),
                child: Material(
                  color: const Color(0xfff8f3fa),
                  borderRadius: BorderRadius.circular(30),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ColoredBox(
                        color: lilac,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(children: [
                            IconButton.filledTonal(
                              tooltip: 'Kembali',
                              onPressed: () => Navigator.pop(sheetContext),
                              style: IconButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: accent),
                              icon: const Icon(Icons.chevron_left_rounded),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(isNew ? 'Tambah jadwal' : 'Edit jadwal',
                                    style: const TextStyle(
                                        color: ink,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900)),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 7,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Text(professionalServiceNames[category]!,
                                        style: const TextStyle(
                                            color: accent,
                                            fontWeight: FontWeight.w800)),
                                    const StatusPill(
                                        label: 'WIB', color: accent),
                                  ],
                                ),
                              ],
                            )),
                            if (isNew)
                              const StatusPill(label: 'Baru', color: accent),
                          ]),
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              DropdownButtonFormField<int>(
                                initialValue: day,
                                decoration:
                                    _scheduleField(context, 'Hari praktik'),
                                items: [
                                  for (final i in [1, 2, 3, 4, 5, 6, 0])
                                    DropdownMenuItem(
                                        value: i, child: Text(_dayNames[i])),
                                ],
                                onChanged: (value) {
                                  if (value != null)
                                    setSheetState(() {
                                      day = value;
                                      error = null;
                                    });
                                },
                              ),
                              const SizedBox(height: 16),
                              const Text('Jam operasional',
                                  style: TextStyle(
                                      color: ink,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w900)),
                              const SizedBox(height: 10),
                              Row(children: [
                                timeField(
                                    'Mulai', start, (value) => start = value),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 10),
                                  child: CircleAvatar(
                                      radius: 16,
                                      backgroundColor: lilac,
                                      child: Icon(Icons.arrow_forward_rounded,
                                          color: accent, size: 19)),
                                ),
                                timeField(
                                    'Selesai', end, (value) => end = value),
                              ]),
                              const SizedBox(height: 18),
                              const Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Flexible(
                                    child: Text('Durasi per slot',
                                        style: TextStyle(
                                            color: ink,
                                            fontSize: 17,
                                            fontWeight: FontWeight.w900)),
                                  ),
                                  SizedBox(width: 8),
                                  Flexible(
                                    child: Text('Min. 60 menit',
                                        textAlign: TextAlign.end,
                                        style: TextStyle(
                                            color: accent,
                                            fontWeight: FontWeight.w700)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 7,
                                runSpacing: 4,
                                children: [
                                  for (final minutes in [...choices, 0])
                                    ChoiceChip(
                                      label: Text(minutes == 0
                                          ? 'Custom'
                                          : '$minutes mnt'),
                                      selected: minutes == 0
                                          ? custom
                                          : !custom && duration == minutes,
                                      showCheckmark: false,
                                      backgroundColor: Colors.white,
                                      selectedColor: accent,
                                      labelStyle: TextStyle(
                                          color: (minutes == 0
                                                  ? custom
                                                  : !custom &&
                                                      duration == minutes)
                                              ? Colors.white
                                              : muted,
                                          fontWeight: FontWeight.w700),
                                      side: const BorderSide(color: border),
                                      onSelected: (_) => setSheetState(() {
                                        custom = minutes == 0;
                                        if (!custom) durationText = '$minutes';
                                        error = null;
                                      }),
                                    ),
                                ],
                              ),
                              if (custom) ...[
                                const SizedBox(height: 8),
                                TextFormField(
                                  initialValue: durationText,
                                  onChanged: (value) => setSheetState(() {
                                    durationText = value;
                                    error = null;
                                  }),
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly
                                  ],
                                  keyboardType: TextInputType.number,
                                  decoration:
                                      _scheduleField(context, 'Slot (mnt)'),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Card.outlined(
                                margin: EdgeInsets.zero,
                                color: Colors.white,
                                shape: cardShape,
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(children: [
                                    Row(children: [
                                      const Icon(Icons.circle,
                                          size: 9, color: accent),
                                      const SizedBox(width: 6),
                                      Expanded(
                                          child: Text(
                                              isNew
                                                  ? 'RINGKASAN JADWAL BARU'
                                                  : 'RINGKASAN JADWAL',
                                              style: const TextStyle(
                                                  color: accent,
                                                  fontWeight:
                                                      FontWeight.w900))),
                                      StatusPill(
                                          label: '$slots Sesi', color: accent),
                                    ]),
                                    const Divider(height: 20),
                                    summaryRow('Jam Operasional',
                                        '$start – $end WIB', ink),
                                    const SizedBox(height: 6),
                                    summaryRow(
                                        'Durasi & Kapasitas',
                                        '$duration mnt/slot ($slots sesi)',
                                        accent),
                                  ]),
                                ),
                              ),
                              const SizedBox(height: 14),
                              Card.outlined(
                                color: Colors.white,
                                margin: EdgeInsets.zero,
                                shape: cardShape,
                                child: CheckboxListTile(
                                  activeColor: accent,
                                  shape: cardShape,
                                  value: isActive,
                                  onChanged: (value) => setSheetState(
                                      () => isActive = value ?? false),
                                  title: Text(
                                      isNew
                                          ? 'Langsung aktifkan jadwal'
                                          : 'Status jadwal aktif',
                                      style: const TextStyle(
                                          color: ink,
                                          fontWeight: FontWeight.w900)),
                                  subtitle: Text(
                                      isNew
                                          ? 'Jadwal otomatis terbuka setelah disimpan'
                                          : 'Pasien dapat memesan sesi pada jam ini',
                                      style: const TextStyle(color: muted)),
                                ),
                              ),
                              if (category == 'package' &&
                                  isActive &&
                                  _validScheduleTimes(start, end) &&
                                  _overlapsQuick(day, start, end))
                                _scheduleWarning(),
                              if (error != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 10),
                                  child: Text(error!,
                                      style: const TextStyle(
                                          color: MalvaColors.danger)),
                                ),
                            ],
                          ),
                        ),
                      ),
                      ColoredBox(
                        color: lilac,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(children: [
                            Expanded(
                                child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                  backgroundColor: Colors.white,
                                  foregroundColor: muted,
                                  minimumSize: const Size(0, 48),
                                  shape: cardShape,
                                  side: const BorderSide(color: border)),
                              onPressed: () => Navigator.pop(sheetContext),
                              child: const Text('Batal'),
                            )),
                            const SizedBox(width: 10),
                            Expanded(
                                flex: 2,
                                child: FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                      backgroundColor: accent,
                                      foregroundColor: Colors.white,
                                      minimumSize: const Size(0, 48),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(18)),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10)),
                                  icon: Icon(
                                      isNew
                                          ? Icons.add_rounded
                                          : Icons.check_rounded,
                                      size: 18),
                                  label: Text(
                                      isNew
                                          ? 'Simpan Jadwal Baru'
                                          : 'Simpan Perubahan',
                                      textAlign: TextAlign.center),
                                  onPressed: save,
                                )),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
    if (!mounted || edited == null) return;
    await _writeSchedules(
      schedule == null ? 'Jadwal tersimpan.' : 'Perubahan jadwal disimpan.',
      schedules: _replaceScheduleRow(category, edited, schedule?.id),
    );
  }

  int _scheduleMinutes(String time) =>
      int.parse(time.substring(0, 2)) * 60 + int.parse(time.substring(3));

  Future<TimeOfDay?> _pickScheduleTime(
          BuildContext context, int minutes, String label) =>
      showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60),
        orientation: Orientation.portrait,
        helpText: 'Jam $label',
        cancelText: 'Batal',
        confirmText: 'Atur',
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
          child: Theme(
            data: ThemeData.dark(useMaterial3: false).copyWith(
              colorScheme: const ColorScheme.dark(primary: Color(0xffaccbfb)),
              timePickerTheme: const TimePickerThemeData(
                backgroundColor: Color(0xff1c1e1f),
                dialBackgroundColor: Color(0xff525454),
                dialHandColor: Color(0xffaccbfb),
                hourMinuteColor: Color(0xff525454),
                dayPeriodColor: Color(0xff525454),
              ),
            ),
            child: child!,
          ),
        ),
      );

  bool _validScheduleTimes(String from, String to) {
    final times = RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$');
    return times.hasMatch(from) && times.hasMatch(to) && from.compareTo(to) < 0;
  }

  String? _scheduleValidation(String from, String to, int duration) {
    if (duration < 60 || duration > 180)
      return 'Slot minimal 60 menit dan maksimal 180 menit.';
    if (!_validScheduleTimes(from, to)) {
      return 'Isi jam mulai dan selesai dalam urutan yang benar (HH:MM).';
    }
    if (_scheduleMinutes(to) - _scheduleMinutes(from) < duration)
      return 'Rentang jadwal harus memuat setidaknya satu slot sesi.';
    return null;
  }

  List<Map<String, Object?>> _replaceScheduleRow(
          String category, Map<String, Object?> replacement, String? id) =>
      [
        for (final row in _storedRows(category))
          if (row.id == id) replacement else _scheduleToPayload(row),
        if (id == null) replacement,
      ];

  /// Payload satu baris jadwal untuk PUT /v1/professional/schedules.
  /// `is_active` selalu dikirim eksplisit; bila null pakai status baris.
  Map<String, Object?> _scheduleToPayload(
    BackendProfessionalSchedule s, {
    bool? isActive,
  }) =>
      {
        'id': s.id,
        'service_category': s.serviceCategory,
        'day_of_week': s.dayOfWeek,
        'start_time': s.startTime,
        'end_time': s.endTime,
        'slot_duration_minutes': s.slotDurationMinutes,
        'is_active': isActive ?? s.isActive,
      };

  Future<void> _writeSchedules(
    String message, {
    List<Map<String, Object?>>? schedules,
    Map<String, bool>? usePrimarySchedule,
  }) async {
    final token = _token;
    if (token == null || _savingSchedules) return;
    setState(() => _savingSchedules = true);
    try {
      final updated = await _api.updateMyScheduleSettings(
          accessToken: token,
          schedules: schedules,
          usePrimarySchedule: usePrimarySchedule);
      if (!mounted) return;
      setState(() {
        _schedules = updated.schedules;
        _usePrimarySchedule = updated.usePrimarySchedule;
      });
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(friendlyErrorMessage(e)),
        backgroundColor: MalvaColors.danger,
      ));
    } finally {
      if (mounted) setState(() => _savingSchedules = false);
    }
  }

  Future<void> _removeSchedule(BackendProfessionalSchedule s) async {
    final token = _token;
    if (token == null) return;
    // Konfirmasi dulu: hapus permanen tidak bisa dibatalkan.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon:
            const Icon(Icons.delete_forever_rounded, color: MalvaColors.danger),
        title: const Text('Hapus jadwal permanen?'),
        content: const Text('Jadwal ini akan dihapus permanen.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: compactFilledButtonStyle.copyWith(
              backgroundColor: const WidgetStatePropertyAll(MalvaColors.danger),
            ),
            child: const Text('Hapus permanen'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _savingSchedules) return;
    setState(() => _savingSchedules = true);
    try {
      await _api.deleteMySchedule(accessToken: token, id: s.id);
      if (!mounted) return;
      setState(() {
        _schedules =
            _schedules.where((e) => e.id != s.id).toList(growable: false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jadwal dihapus permanen.')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    } finally {
      if (mounted) setState(() => _savingSchedules = false);
    }
  }

  /// Aktifkan/nonaktifkan satu baris jadwal (toggle) tanpa menghapusnya,
  /// sehingga baris tetap tampil dan bisa diaktifkan kembali.
  Future<void> _toggleSchedule(
          BackendProfessionalSchedule s, String category) =>
      _writeSchedules(
        s.isActive ? 'Jadwal dinonaktifkan.' : 'Jadwal diaktifkan.',
        schedules: _replaceScheduleRow(
            category, _scheduleToPayload(s, isActive: !s.isActive), s.id),
      );

  Future<void> _savePricing() async {
    final token = _token;
    if (token == null || _savingPricing || _savingCapacity) return;
    setState(() => _savingPricing = true);
    try {
      await _api.updatePricing(
        accessToken: token,
        quickChatPrice: parseProfessionalPrice(_chatPrice.text),
        quickVideoPrice: parseProfessionalPrice(_videoPrice.text),
        packagePrice: parseProfessionalPrice(_packagePrice.text),
        patientCapacity: _patientCapacity,
      );
      if (!mounted) return;
      setState(() => _savedPatientCapacity = _patientCapacity);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Harga & jadwal tersimpan.')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    } finally {
      if (mounted) setState(() => _savingPricing = false);
    }
  }
}

void _openPatientDetail(BuildContext context, WidgetRef ref,
    BackendCareSession session, MalvaApiClient? apiClient) {
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ProPatientDetailScreen(
        patientId: session.patientId,
        patientName:
            session.patientName.isEmpty ? 'Pasien' : session.patientName,
        session: ref.read(currentSessionProvider),
        apiClient: apiClient ?? ref.read(apiClientProvider),
      ),
    ),
  );
}
