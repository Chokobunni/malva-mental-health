import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../services/care_session_refresh.dart';
import '../services/server_clock.dart';
import '../widgets/doctor_review_actions.dart';
import '../services/medication_reminder_service.dart';
import '../theme.dart';
import '../widgets/care_reference_widgets.dart';
import 'notifications_screen.dart';
import '../widgets/crisis_hotline.dart';
import '../widgets/daily_checkin_flow.dart';
import '../widgets/malva_components.dart';
import '../widgets/care_session_card.dart';
import '../widgets/friendly_error.dart';

import '../widgets/sync_status.dart';
import '../widgets/therapy_library.dart';
import 'booking/doctor_discovery_screen.dart';
import 'booking/doctor_profile_screen.dart';
import 'my_care_screen.dart';
import 'chat_screen.dart';
import 'diary_history_screen.dart';
import 'goals_screen.dart';
import 'history_log_screen.dart';
import 'mood_medication_checkin_screen.dart';
import 'record_screen.dart';

// ============================================================
// HOME — layout final:
//   [Sesi booking aktif]      (bila ada, Join/Cancel)
//   Daily Check-in interaktif (emoji -> obat -> tidur -> energi -> streak)
//   Self Care:                Goals & Habits / Diary History /
//                             Psychological Therapy / Health Record
//   Professional Care:        tombol Find Professionals
//                             Assessment / History Log
//   Mood Medication Check-in  (banner -> screen Mood+Medication)
// ============================================================

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({
    super.key,
    required this.onOpenMood,
    required this.onOpenMedication,
    required this.onOpenDiary,
    required this.onOpenChat,
    required this.onOpenMore,
    required this.onOpenAssessment,
    this.medicationReminderService,
    this.session,
    this.apiClient,
  });

  final VoidCallback onOpenMood;
  final VoidCallback onOpenMedication;
  final VoidCallback onOpenDiary;
  final VoidCallback onOpenChat;
  final VoidCallback onOpenMore;
  final VoidCallback onOpenAssessment;
  final MedicationReminderService? medicationReminderService;
  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with WidgetsBindingObserver {
  late final CareSessionRefresh _sessionRefresh;
  bool _isInitialLoading = true;
  List<BackendCareSession> _upcomingSessions = const [];
  bool _ongoingLoadFailed = false;
  bool _upcomingLoadFailed = false;
  bool _showAllUpcomingVideos = false;
  bool _showAllUpcomingChats = false;
  String? _sessionsOwnerToken;
  int _sessionsRequest = 0;

  AuthSession? get _session =>
      widget.session ?? ref.read(currentSessionProvider);
  MalvaApiClient get _api => widget.apiClient ?? ref.read(apiClientProvider);

  /// Sesi scheduled dalam jendela waktu; konfirmasi hadir tidak menutup akses.
  List<BackendCareSession> _ongoingSessions = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionRefresh = CareSessionRefresh(() {
      if (!mounted) return;
      setState(() {});
      unawaited(_loadUpcomingSession());
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_loadUpcomingSession());
      Future<void>.delayed(const Duration(milliseconds: 400)).then((_) {
        if (mounted) setState(() => _isInitialLoading = false);
      });
    });
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session?.accessToken != widget.session?.accessToken ||
        oldWidget.apiClient != widget.apiClient) {
      unawaited(_loadUpcomingSession());
    }
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
      unawaited(_loadUpcomingSession());
    }
  }

  Future<void> _refreshAll() async {
    await _loadUpcomingSession();
    // Segarkan riwayat check-in dan obat dari server saat pull-to-refresh.
    final notifier = ref.read(malvaStoreProvider.notifier);
    await Future.wait([
      notifier.loadCheckinHistory().catchError((_) {}),
      notifier.loadMedications().catchError((_) {}),
    ]);
  }

  Future<void> _loadUpcomingSession() async {
    final request = ++_sessionsRequest;
    final apiClient = _api;
    final rawToken = _session?.accessToken;
    final accessToken =
        (rawToken == null || rawToken.isEmpty) ? null : rawToken;
    if (mounted && _sessionsOwnerToken != accessToken) {
      _sessionsOwnerToken = accessToken;
      setState(() {
        _showAllUpcomingVideos = false;
        _showAllUpcomingChats = false;
        _upcomingSessions = const [];
        _ongoingSessions = const [];
        _upcomingLoadFailed = false;
        _ongoingLoadFailed = false;
      });
      _sessionRefresh.update(const []);
    }
    if (accessToken == null) {
      if (mounted) {
        setState(() {
          _upcomingSessions = const [];
          _ongoingSessions = const [];
          _ongoingLoadFailed = false;
          _upcomingLoadFailed = false;
        });
      }
      return;
    }
    bool upcomingFailed = false;
    bool ongoingFailed = false;
    Future<List<BackendCareSession>> load(String scope) async {
      try {
        return await apiClient.listCareSessions(
            accessToken: accessToken, scope: scope);
      } on Object {
        if (scope == 'ongoing') {
          ongoingFailed = true;
        } else {
          upcomingFailed = true;
        }
        return [];
      }
    }

    final results = await Future.wait([load('upcoming'), load('ongoing')]);
    if (!mounted ||
        request != _sessionsRequest ||
        _session?.accessToken != accessToken) return;
    final upcoming = results[0]
      ..sort((a, b) => (a.scheduledAt ?? '').compareTo(b.scheduledAt ?? ''));
    final ongoing = results[1]
      ..sort((a, b) => (a.scheduledAt ?? '').compareTo(b.scheduledAt ?? ''));
    setState(() {
      _upcomingSessions = upcoming;
      _ongoingSessions = ongoing;
      _upcomingLoadFailed = upcomingFailed;
      _ongoingLoadFailed = ongoingFailed;
    });
    _sessionRefresh.update([...upcoming, ...ongoing]);
    ref.read(reviewEntitlementsRevisionProvider.notifier).state++;
  }

  @override
  Widget build(BuildContext context) {
    // Foto/nama profesional bisa berubah kapan saja (event realtime
    // `professional.profile.updated`). Muat ulang data sesi yang menampilkan
    // identitas profesional tanpa perlu refresh manual (bug 28 Okt 2026:
    // foto profil baru tidak muncul di sisi pasien).
    ref.listen<int>(professionalProfileRevisionProvider, (previous, next) {
      unawaited(_loadUpcomingSession());
    });
    ref.listen<AuthSession?>(currentSessionProvider, (before, after) {
      if (widget.session == null && before?.accessToken != after?.accessToken) {
        unawaited(_loadUpcomingSession());
      }
    });
    final auth = _session;
    final liveSessions = {
      for (final s in [..._upcomingSessions, ..._ongoingSessions])
        if (s.canJoinNow) s.id: s,
    };
    final ongoingChats = liveSessions.values.where((s) => !s.isVideo);
    final ongoingVideos = liveSessions.values.where((s) => s.isVideo);
    final upcomingVideos = _upcomingSessions.where((s) =>
        s.isScheduled &&
        !s.isAfterJoinWindow &&
        s.isVideo &&
        !liveSessions.containsKey(s.id));
    final upcomingChats = _upcomingSessions.where((s) =>
        s.isScheduled &&
        !s.isAfterJoinWindow &&
        !s.isVideo &&
        !liveSessions.containsKey(s.id));
    return Scaffold(
      backgroundColor: carePageColor,
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            if (_isInitialLoading) const LinearProgressIndicator(),
            DailyCheckInFlow(
              onSaved: () => setState(() {}),
              onProfile: widget.onOpenMore,
              trailing: CareHeaderNotification(
                  onPressed: () => _push(NotificationsScreen(
                      session: auth, apiClient: widget.apiClient))),
            ),
            const CrisisHotlineBanner(),
            const OfflineBanner(),
            Padding(
              padding: const EdgeInsets.all(23),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _HomeSectionLabel('Sesi berjalan',
                      icon: Icons.play_circle_rounded),
                  if (_ongoingLoadFailed)
                    const Text('Sesi berjalan belum dapat dimuat.')
                  else if (liveSessions.isEmpty)
                    const _HomeSessionEmpty(
                        asset: 'home-ongoing',
                        text: 'Tidak ada sesi berjalan saat ini.')
                  else
                    for (final s in [...ongoingVideos, ...ongoingChats])
                      Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _OngoingSessionCard(
                            session: s,
                            onChat: () => _joinSession(context, s),
                            onChanged: _loadUpcomingSession,
                            accessToken: auth?.accessToken ?? '',
                            onConfirmAttendance: () async {
                              final token = auth?.accessToken;
                              if (token == null ||
                                  token.isEmpty ||
                                  _session?.accessToken != token) return null;
                              final updated = await _api.updateCareSession(
                                  accessToken: token,
                                  sessionId: s.id,
                                  status: 'attended');
                              return mounted && _session?.accessToken == token
                                  ? updated
                                  : null;
                            },
                          )),
                  const SizedBox(height: 23),
                  for (final (video, sessions, expanded) in [
                    (true, upcomingVideos, _showAllUpcomingVideos),
                    (false, upcomingChats, _showAllUpcomingChats),
                  ]) ...[
                    _HomeSectionLabel(
                      video ? 'Panggilan video mendatang' : 'Chat mendatang',
                      icon: video
                          ? Icons.videocam_rounded
                          : Icons.chat_bubble_rounded,
                      action: sessions.length > 1
                          ? IconButton(
                              tooltip: expanded
                                  ? 'Tampilkan lebih sedikit sesi ${video ? 'video' : 'chat'}'
                                  : 'Tampilkan semua sesi ${video ? 'video' : 'chat'}',
                              onPressed: () => setState(() {
                                if (video) {
                                  _showAllUpcomingVideos = !expanded;
                                } else {
                                  _showAllUpcomingChats = !expanded;
                                }
                              }),
                              icon: Icon(expanded
                                  ? Icons.expand_less_rounded
                                  : Icons.expand_more_rounded),
                            )
                          : null,
                    ),
                    if (_upcomingLoadFailed)
                      Text(video
                          ? 'Panggilan video mendatang belum dapat dimuat.'
                          : 'Chat mendatang belum dapat dimuat.')
                    else if (sessions.isEmpty &&
                        (!video || ongoingVideos.isEmpty))
                      _HomeSessionEmpty(
                        asset: video ? 'home-video' : 'home-chat',
                        text: video
                            ? 'Tidak ada panggilan video mendatang.'
                            : 'Tidak ada chat mendatang.',
                      )
                    else
                      for (final session
                          in expanded ? sessions : sessions.take(1))
                        _upcomingCard(session, auth),
                    const SizedBox(height: 23),
                  ],
                  if (_ongoingLoadFailed || _upcomingLoadFailed)
                    TextButton(
                        onPressed: _loadUpcomingSession,
                        child: const Text('Coba lagi')),
                  const _HomeSectionLabel('Pengelolaan Diri', center: true),
                  _MoodMedicationBanner(
                      onTap: () => _push(MoodMedicationCheckinScreen(
                          session: widget.session,
                          apiClient: widget.apiClient,
                          medicationReminderService:
                              widget.medicationReminderService))),
                  const SizedBox(height: 20),
                  _HomeSectionGrid(
                    items: [
                      _GridItem(
                        icon: Icons.flag_rounded,
                        label: 'Target & Kebiasaan',
                        color: const Color(0xff5985c6),
                        onTap: () => _push(const GoalsScreen()),
                      ),
                      _GridItem(
                        icon: Icons.menu_book_rounded,
                        label: 'Riwayat Jurnal',
                        color: const Color(0xffd49949),
                        onTap: () => _push(DiaryHistoryScreen(
                          session: widget.session,
                          apiClient: widget.apiClient,
                        )),
                      ),
                      _GridItem(
                        icon: Icons.psychology_rounded,
                        label: 'Terapi Psikologis',
                        color: const Color(0xff46a68e),
                        onTap: () => _push(const TherapyCatalogScreen()),
                      ),
                      _GridItem(
                        icon: Icons.note_add_rounded,
                        label: 'Rekam Medis',
                        color: const Color(0xff469dcd),
                        onTap: () => _push(RecordScreen(
                          session: widget.session,
                          apiClient: widget.apiClient,
                        )),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // === 4. PROFESSIONAL CARE ===
                  const _HomeSectionLabel('Layanan Profesional', center: true),
                  _FindProfessionalsButton(
                    onTap: () => _openDoctorDiscovery(context),
                  ),
                  const SizedBox(height: 12),
                  _HomeSectionGrid(
                    compact: true,
                    items: [
                      _GridItem(
                        icon: Icons.fact_check_rounded,
                        label: 'Asesmen',
                        color: const Color(0xffcf7c68),
                        onTap: widget.onOpenAssessment,
                      ),
                      _GridItem(
                        icon: Icons.show_chart_rounded,
                        label: 'Riwayat Aktivitas',
                        color: const Color(0xff46a68e),
                        onTap: () => _push(HistoryLogScreen(
                          session: widget.session,
                          apiClient: widget.apiClient,
                        )),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  const SizedBox(height: 24),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _push(Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => screen),
    );
  }

  Widget _upcomingCard(BackendCareSession session, AuthSession? auth) =>
      Padding(
        key: ValueKey(session.id),
        padding: const EdgeInsets.only(bottom: 12),
        child: _UpcomingSessionCard(
          session: session,
          accessToken: auth?.accessToken ?? '',
          onJoin: () => _joinSession(context, session),
          onCancel: () => _cancelSession(context, session),
          onProfile: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => DoctorProfileScreen(
                      doctorUserId: session.professionalId,
                      doctorName: session.professionalName,
                      session: auth,
                      apiClient: _api))),
          onReschedule: session.scheduledDateTime != null &&
                  session.scheduledDateTime!.difference(ServerClock.now()) >=
                      const Duration(hours: 24)
              ? () async {
                  final token = auth?.accessToken ?? '';
                  if (token.isEmpty) return;
                  final changed = await reschedulePatientCareSession(context,
                      api: _api, token: token, session: session);
                  if (changed && mounted) await _loadUpcomingSession();
                }
              : null,
          onChanged: _loadUpcomingSession,
          onConfirmAttendance: () async {
            final token = auth?.accessToken;
            if (token == null ||
                token.isEmpty ||
                _session?.accessToken != token) {
              return null;
            }
            final updated = await _api.updateCareSession(
                accessToken: token, sessionId: session.id, status: 'attended');
            return mounted && _session?.accessToken == token ? updated : null;
          },
        ),
      );

  void _joinSession(BuildContext context, BackendCareSession session) {
    if (session.professionalId.isEmpty) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUserName: session.professionalName.isEmpty
              ? 'Profesional'
              : session.professionalName,
          otherUserId: session.professionalId,
        ),
      ),
    );
  }

  Future<void> _cancelSession(
    BuildContext context,
    BackendCareSession session,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan sesi?'),
        content: const Text(
            'Pembatalan minimal 24 jam sebelum sesi. Kurang dari itu sesi hangus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Kembali'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: compactFilledButtonStyle.copyWith(
              backgroundColor: const WidgetStatePropertyAll(MalvaColors.danger),
            ),
            child: const Text('Batalkan'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final apiClient = _api;
    final token = _session?.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      await apiClient.updateCareSession(
        accessToken: token,
        sessionId: session.id,
        status: 'cancelled_by_patient',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesi dibatalkan.')),
      );
      await _loadUpcomingSession();
      setState(() {});
    } on Object catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }

  void _openDoctorDiscovery(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DoctorDiscoveryScreen(
          session: widget.session,
          apiClient: widget.apiClient,
        ),
      ),
    );
  }
}

// ============================================================
// WIDGET LOKAL
// ============================================================

/// Kartu sesi mendatang: nama profesional riil, tipe & durasi riil,
/// tanggal, tombol Join / Cancel.
class _HomeCard extends StatelessWidget {
  const _HomeCard(
      {required this.child, this.padding = const EdgeInsets.all(20)});
  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => Container(
      padding: padding,
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: careSoftShadow),
      child: child);
}

class _HomeSessionEmpty extends StatelessWidget {
  const _HomeSessionEmpty({required this.asset, required this.text});
  final String asset, text;

  @override
  Widget build(BuildContext context) => _HomeCard(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        child: Row(children: [
          Image.asset('assets/care/$asset.png',
              width: 43, height: 43, excludeFromSemantics: true),
          const SizedBox(width: 18),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      color: MalvaColors.ink, fontWeight: FontWeight.w500))),
        ]),
      );
}

class _UpcomingSessionCard extends StatelessWidget {
  const _UpcomingSessionCard({
    required this.session,
    required this.onJoin,
    required this.onCancel,
    required this.accessToken,
    required this.onChanged,
    required this.onConfirmAttendance,
    this.onProfile,
    this.onReschedule,
  });

  final BackendCareSession session;
  final VoidCallback onJoin;
  final VoidCallback onCancel;
  final VoidCallback? onProfile, onReschedule;
  final String accessToken;
  final Future<void> Function() onChanged;
  final Future<BackendCareSession?> Function() onConfirmAttendance;

  @override
  Widget build(BuildContext context) => CareSessionCard(
      session: session,
      role: UserRole.patient,
      allowPreSessionChat: true,
      onOpenChat: onJoin,
      onChanged: onChanged,
      accessToken: accessToken,
      onCancel: onCancel,
      onProfile: onProfile,
      onReschedule: onReschedule,
      onConfirmAttendance: onConfirmAttendance);
}

/// Tombol "Find Professionals" di bawah label Professional Care.
class _FindProfessionalsButton extends StatelessWidget {
  const _FindProfessionalsButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(53),
        backgroundColor: const Color(0xff9755ad),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
      ),
      icon: const Icon(Icons.search_rounded),
      label: const Text('Cari Profesional',
          style: TextStyle(fontFamily: 'Roboto', fontWeight: FontWeight.w700)),
    );
  }
}

/// Banner Mood Medication Check-in (Mood + Medication Tracker).
class _MoodMedicationBanner extends StatelessWidget {
  const _MoodMedicationBanner({required this.onTap});
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(19),
      child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 19, vertical: 14),
          decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(19),
              gradient: const LinearGradient(
                  colors: [Color(0xff9755ad), Color(0xffae65bf)]),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x159755ad),
                    blurRadius: 12,
                    offset: Offset(0, 6))
              ]),
          child: Row(children: [
            Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.monitor_heart_rounded,
                    color: Colors.white)),
            const SizedBox(width: 13),
            const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Check-in Mood & Obat',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 14)),
                  Text('Pelacak Mood & Obat',
                      style: TextStyle(color: Color(0xfff0dff5), fontSize: 11))
                ])),
            const CircleAvatar(
                radius: 17,
                backgroundColor: Colors.white24,
                child: Icon(Icons.chevron_right_rounded, color: Colors.white))
          ])));
}

class _HomeSectionGrid extends StatelessWidget {
  const _HomeSectionGrid({required this.items, this.compact = false});
  final List<_GridItem> items;
  final bool compact;
  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < items.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 18),
          IntrinsicHeight(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                for (var j = i; j < items.length && j < i + 2; j++) ...[
                  if (j > i) const SizedBox(width: 18),
                  Expanded(
                      child: ConstrainedBox(
                          constraints:
                              BoxConstraints(minHeight: compact ? 74 : 116),
                          child:
                              _HomeGridTile(item: items[j], compact: compact)))
                ]
              ]))
        ]
      ]);
}

class _HomeSectionLabel extends StatelessWidget {
  const _HomeSectionLabel(this.text,
      {this.icon, this.action, this.center = false});
  final String text;
  final IconData? icon;
  final Widget? action;
  final bool center;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.fromLTRB(3, 8, 3, 17),
      child: Row(
          mainAxisAlignment:
              center ? MainAxisAlignment.center : MainAxisAlignment.start,
          children: [
            if (icon != null) ...[
              Container(
                  width: 4,
                  height: 16,
                  decoration: BoxDecoration(
                      color: const Color(0xff9755ad),
                      borderRadius: BorderRadius.circular(9))),
              const SizedBox(width: 8),
              Icon(icon, size: 18, color: const Color(0xff9755ad)),
              const SizedBox(width: 8)
            ],
            if (center)
              Flexible(
                  child: Text(text,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Color(0xff9755ad),
                          fontWeight: FontWeight.w700,
                          fontSize: 18)))
            else
              Expanded(
                  child: Text(text,
                      style: const TextStyle(
                          color: Color(0xff9755ad),
                          fontWeight: FontWeight.w700,
                          fontSize: 17))),
            if (action != null) action!
          ]));
}

class _GridItem {
  const _GridItem({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
}

class _HomeGridTile extends StatelessWidget {
  const _HomeGridTile({required this.item, this.compact = false});
  final _GridItem item;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final icon = Container(
        padding: EdgeInsets.all(compact ? 10 : 11),
        decoration: BoxDecoration(
            color: item.color.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(16)),
        child: Icon(item.icon, color: item.color, size: 24));
    final label = Text(item.label,
        textAlign: compact ? TextAlign.start : TextAlign.center,
        style: const TextStyle(
            fontSize: 13,
            color: Color(0xff9755ad),
            fontWeight: FontWeight.w700));
    return Material(
        color: Colors.white,
        elevation: 3,
        shadowColor: const Color(0x3854206f),
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
            onTap: item.onTap,
            borderRadius: BorderRadius.circular(24),
            child: Padding(
                padding: const EdgeInsets.all(14),
                child: compact
                    ? Row(children: [
                        icon,
                        const SizedBox(width: 10),
                        Expanded(child: label)
                      ])
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [icon, const SizedBox(height: 13), label]))));
  }
}

/// Kartu "Sesi berjalan" di home pasien. Menampilkan nama profesional, jam
/// WIB, tipe sesi, tombol Gabung (video, via [MeetJoinButton]) dan Chat.
/// Ditampilkan selama sesi scheduled berada di dalam jendela waktu.
class _OngoingSessionCard extends StatelessWidget {
  const _OngoingSessionCard({
    required this.session,
    required this.onChat,
    required this.onChanged,
    required this.accessToken,
    required this.onConfirmAttendance,
  });

  final BackendCareSession session;
  final String accessToken;
  final Future<BackendCareSession?> Function() onConfirmAttendance;
  final VoidCallback onChat;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context) => CareSessionCard(
      session: session,
      role: UserRole.patient,
      allowPreSessionChat: true,
      onOpenChat: onChat,
      accessToken: accessToken,
      onConfirmAttendance: onConfirmAttendance,
      onChanged: onChanged);
}
