import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/care_session_refresh.dart';
import '../widgets/session_attendance_actions.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/care_reference_widgets.dart';
import '../widgets/malva_components.dart';
import '../widgets/meet_join_button.dart';
import '../widgets/professional_availability_summary.dart';
import 'chat_screen.dart';
import 'pro_patient_detail_screen.dart';
import '../time/wib.dart';

// ============================================================
// PRO SCHEDULE — tab "Jadwal" dashboard profesional:
//   - Sesi hari ini & mendatang: join chat, tandai hadir/tidak,
//     batal (kredit kembali), reschedule, meeting URL, ringkasan.
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
    // Parallel scope requests may straddle completion; terminal state wins.
    final sessionsById = <String, BackendCareSession>{};
    for (final s in [..._today, ..._upcoming, ..._past]) {
      if (sessionsById[s.id]?.isScheduled ?? true) sessionsById[s.id] = s;
    }
    final needsCompletion = sessionsById.values
        .where((s) => s.isScheduled && s.isAfterJoinWindow)
        .toList()
      ..sort((a, b) => (a.scheduledAt ?? '').compareTo(b.scheduledAt ?? ''));
    final today = _today
        .map((s) => sessionsById[s.id]!)
        .where((s) => s.isScheduled && !s.isAfterJoinWindow)
        .toList();
    final todayIds = today.map((s) => s.id).toSet();
    final upcoming = _upcoming
        .map((s) => sessionsById[s.id]!)
        .where((s) =>
            s.isScheduled && !s.isAfterJoinWindow && !todayIds.contains(s.id))
        .toList();
    final completionIds = needsCompletion.map((s) => s.id).toSet();
    final past = _past
        .map((s) => sessionsById[s.id]!)
        .where((s) => !completionIds.contains(s.id))
        .toList();
    return Theme(
        data: Theme.of(context).copyWith(
            cardTheme: Theme.of(context).cardTheme.copyWith(elevation: .35)),
        child: RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              if (widget.header != null) ...[
                widget.header!,
                const SizedBox(height: 14),
              ],
              if (needsCompletion.isNotEmpty) ...[
                const SectionLabel('Perlu diselesaikan',
                    icon: Icons.task_alt_rounded),
                for (final s in needsCompletion) ...[
                  _ProSessionCard(
                      key: ValueKey('complete-${s.id}'),
                      session: s,
                      onChanged: _load),
                  const SizedBox(height: 10),
                ],
              ],
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else if (_error != null)
                SoftCard(
                  bordered: false,
                  child: Column(
                    children: [
                      Text(_error!,
                          style: const TextStyle(
                              color: MalvaColors.danger,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                        label: const Text('Coba Lagi'),
                      ),
                    ],
                  ),
                )
              else ...[
                if (today.isEmpty)
                  const CareIllustratedCard(
                    horizontal: true,
                    imageHeight: 85,
                    asset: 'pro-today',
                    title: 'Sesi hari ini',
                    subtitle: 'Tidak ada sesi hari ini',
                  )
                else ...[
                  const SectionLabel('Sesi hari ini'),
                  for (final s in today) ...[
                    _ProSessionCard(
                        key: ValueKey('today-${s.id}'),
                        session: s,
                        onChanged: _load),
                    const SizedBox(height: 10),
                  ],
                ],
                const SizedBox(height: 14),
                if (upcoming.isEmpty)
                  const CareIllustratedCard(
                    horizontal: true,
                    imageHeight: 85,
                    asset: 'pro-upcoming',
                    title: 'Mendatang',
                    subtitle: 'Belum ada sesi mendatang',
                  )
                else ...[
                  const SectionLabel('Mendatang'),
                  for (final s in upcoming) ...[
                    _ProSessionCard(
                        key: ValueKey('upcoming-${s.id}'),
                        session: s,
                        onChanged: _load),
                    const SizedBox(height: 10),
                  ],
                ],
                const SizedBox(height: 14),
                SoftCard(
                    radius: 14,
                    padding: EdgeInsets.zero,
                    child: ListTile(
                      key: const ValueKey('session-history-toggle'),
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 13),
                      leading: const Icon(Icons.history_rounded),
                      title: const Text('Riwayat sesi',
                          style: TextStyle(fontWeight: FontWeight.w700)),
                      subtitle: Text('${past.length} sesi'),
                      trailing: Icon(_historyExpanded
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded),
                      onTap: () =>
                          setState(() => _historyExpanded = !_historyExpanded),
                    )),
                if (_historyExpanded && past.isEmpty)
                  const EmptyState(
                    icon: Icons.history_rounded,
                    title: 'Belum ada riwayat',
                    subtitle: 'Sesi selesai / batal tercatat di sini.',
                  )
                else if (_historyExpanded)
                  for (final s in past) ...[
                    _ProSessionCard(
                        key: ValueKey('past-${s.id}'),
                        session: s,
                        onChanged: _load),
                    const SizedBox(height: 10),
                  ],
              ],
            ],
          ),
        ));
  }
}

class _ProSessionCard extends ConsumerWidget {
  const _ProSessionCard(
      {super.key, required this.session, required this.onChanged});

  final BackendCareSession session;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final at = session.scheduledDateTime;
    final dateLabel = at == null
        ? '-'
        : '${at.day}/${at.month}/${at.year} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')} WIB';
    final statusColor = switch (session.status) {
      'scheduled' => MalvaColors.seed,
      'completed' => MalvaColors.mint,
      'no_show' => MalvaColors.danger,
      'cancelled_by_professional' => MalvaColors.amber,
      'cancelled_by_patient' => Theme.of(context).colorScheme.onSurfaceVariant,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    final statusLabel = switch (session.status) {
      'scheduled' =>
        session.isAfterJoinWindow ? 'Menunggu penyelesaian' : 'Terjadwal',
      'completed' => 'Selesai',
      'no_show' => 'Tidak hadir',
      'cancelled_by_professional' => 'Dibatalkan profesional',
      'cancelled_by_patient' => 'Dibatalkan pasien',
      'expired_unpaid' => 'Pembayaran kedaluwarsa',
      'pending_payment' => 'Menunggu pembayaran',
      _ => session.status,
    };
    // Aksi sesi hanya tersedia selama sesi scheduled berada dalam jendela.
    final live = session.canJoinNow;
    return SoftCard(
      padding: EdgeInsets.zero,
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              MalvaColors.seed.withValues(alpha: 0.12),
                          child: Text(
                            session.patientName.isEmpty
                                ? '?'
                                : session.patientName.characters.first
                                    .toUpperCase(),
                            style: const TextStyle(
                                color: MalvaColors.seed,
                                fontWeight: FontWeight.w900),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                session.patientName.isEmpty
                                    ? 'Pasien'
                                    : session.patientName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w900),
                              ),
                              Text(
                                dateLabel,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        if (!session.isScheduled) ...[
                          const SizedBox(width: 8),
                          ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 112),
                              child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 5),
                                  decoration: BoxDecoration(
                                      color: statusColor.withValues(alpha: .09),
                                      borderRadius: BorderRadius.circular(5)),
                                  child: Text(statusLabel,
                                      style: TextStyle(
                                          color: statusColor,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800)))),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          if (session.isScheduled)
                            StatusPill(label: statusLabel, color: statusColor),
                          Text(
                              '${session.isVideo ? 'Video' : 'Chat'} • ${session.durationMinutes} mnt • ${session.packageId == null ? 'Sekali sesi' : 'Paket'}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ]),
                    if (session.isScheduled && session.isBeforeJoinWindow) ...[
                      const SizedBox(height: 8),
                      const Text('Check-in dibuka 10 menit sebelum sesi.'),
                    ],
                    if (session.summaryForPatient.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('Ringkasan: ${session.summaryForPatient}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                    if (session.cancelReason.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('Alasan: ${session.cancelReason}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                    if (session.cancelledByProfessional ||
                        session.status == 'no_show') ...[
                      const SizedBox(height: 6),
                      Text(
                          session.cancelledByProfessional
                              ? 'Kuota sesi pasien dikembalikan.'
                              : 'Kuota sesi pasien terpakai.',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                    if (!session.isScheduled) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => _openPatientDetail(context, ref),
                            style: OutlinedButton.styleFrom(
                                side:
                                    const BorderSide(color: Color(0xFFE5E7EB)),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                                minimumSize: const Size(0, 36)),
                            child: const Text('Buka detail pasien'),
                          )),
                    ],
                    // Konfirmasi hadir tidak menutup sesi; batas akhir tetap menutup akses.
                    if (live) ...[
                      const SizedBox(height: 10),
                      // Sesi video: tombol gabung Google Meet dengan jendela waktu.
                      // Bila link belum ada, tombol berubah menjadi "Siapkan link Meet".
                      if (session.isVideo) ...[
                        MeetJoinButton(
                          session: session,
                          accessToken:
                              ref.read(currentSessionProvider)?.accessToken ??
                                  '',
                          expanded: true,
                          onSessionChanged: (_) {
                            onChanged();
                          },
                        ),
                        const SizedBox(height: 10),
                      ],
                      // Lapis 2 — aksi primer selama jendela sesi terbuka.
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.icon(
                            onPressed: () => _openChat(context),
                            style: compactFilledButtonStyle,
                            icon:
                                const Icon(Icons.chat_bubble_rounded, size: 16),
                            label: const Text('Join / Chat'),
                          ),
                        ],
                      ),
                    ],
                  ])),
          // Lapis 3 — aksi sekunder (batal/pindah/detail) hanya relevan
          // untuk sesi yang masih scheduled.
          if (session.isScheduled && !session.isAfterJoinWindow) ...[
            CollapsibleCard(
              key: ValueKey('aksi-lain-${session.id}'),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              header: const Text(
                'AKSI LAIN',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: Colors.black54),
              ),
              color: const Color(0xFFF7F8FA),
              child: LayoutBuilder(builder: (context, constraints) {
                Widget action(
                        IconData icon, String title, VoidCallback onPressed) =>
                    SizedBox(
                        width: (constraints.maxWidth - 8) / 2,
                        child: OutlinedButton.icon(
                            onPressed: onPressed,
                            style: OutlinedButton.styleFrom(
                                backgroundColor: Colors.white,
                                side:
                                    const BorderSide(color: Color(0xFFE5E7EB)),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(11)),
                                minimumSize: const Size(0, 34),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 8),
                                textStyle: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700)),
                            icon: Icon(icon, size: 15),
                            label: Text(title, textAlign: TextAlign.center)));
                return Wrap(spacing: 8, runSpacing: 8, children: [
                  action(Icons.person_outline_rounded, 'Detail pasien',
                      () => _openPatientDetail(context, ref)),
                  action(Icons.cancel_outlined, 'Batal',
                      () => _cancel(context, ref)),
                  action(Icons.edit_calendar_rounded, 'Reschedule',
                      () => _reschedule(context, ref)),
                  action(Icons.link_rounded, 'Link & ringkasan',
                      () => _editDetail(context, ref)),
                ]);
              }),
            ),
          ],
          if (session.isScheduled && !session.isBeforeJoinWindow)
            Padding(
                padding: const EdgeInsets.all(16),
                child: SessionAttendanceActions(
                    session: session,
                    role: UserRole.professional,
                    onChanged: onChanged)),
        ],
      ),
    );
  }

  void _openChat(BuildContext context) {
    if (!session.canJoinNow) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUserName:
              session.patientName.isEmpty ? 'Pasien' : session.patientName,
          otherUserId: session.patientId,
        ),
      ),
    );
  }

  void _openPatientDetail(BuildContext context, WidgetRef ref) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProPatientDetailScreen(
          patientId: session.patientId,
          patientName:
              session.patientName.isEmpty ? 'Pasien' : session.patientName,
          session: ref.read(currentSessionProvider),
          apiClient: ref.read(apiClientProvider),
        ),
      ),
    );
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    final reasonController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Batalkan sesi?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'Kredit sesi pasien otomatis kembali dan bisa dijadwalkan ulang.'),
            const SizedBox(height: 10),
            TextField(
              controller: reasonController,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Alasan (opsional)'),
            ),
          ],
        ),
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
    reasonController.dispose();
    if (confirmed != true || !context.mounted) return;
    final api = ref.read(apiClientProvider);
    final token = ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      await api.updateCareSession(
        accessToken: token,
        sessionId: session.id,
        status: 'cancelled_by_professional',
        cancelReason: reasonController.text.trim(),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Sesi dibatalkan. Kredit pasien dikembalikan.')),
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
        title: const Text('Reschedule sesi'),
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
              'Pilih slot dalam jam praktikmu. Reschedule profesional boleh melewati kedaluwarsa paket.',
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
    final api = ref.read(apiClientProvider);
    final token = ref.read(currentSessionProvider)?.accessToken;
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
          const SnackBar(content: Text('Sesi berhasil di-reschedule.')),
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

  Future<void> _editDetail(BuildContext context, WidgetRef ref) async {
    final meetingController = TextEditingController(text: session.meetingUrl);
    final summaryController =
        TextEditingController(text: session.summaryForPatient);
    final noteController = TextEditingController(text: session.privateNote);
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link & ringkasan sesi'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: meetingController,
                decoration: const InputDecoration(
                    labelText: 'Meeting URL (video)',
                    hintText: 'https://meet.google.com/...'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: summaryController,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Ringkasan untuk pasien',
                    hintText:
                        'Dibagikan ke pasien setelah sesi — ganti follow-up.'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: const InputDecoration(
                    labelText: 'Catatan privat (hanya kamu)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: compactFilledButtonStyle,
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    final meeting = meetingController.text.trim();
    final summary = summaryController.text.trim();
    final note = noteController.text.trim();
    meetingController.dispose();
    summaryController.dispose();
    noteController.dispose();
    if (saved != true || !context.mounted) return;
    final api = ref.read(apiClientProvider);
    final token = ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      await api.updateCareSession(
        accessToken: token,
        sessionId: session.id,
        meetingUrl: meeting,
        summaryForPatient: summary,
        privateNote: note,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Detail sesi tersimpan.')),
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

// ============================================================
// Helper tanggal untuk hari libur. YYYY-MM-DD dipakai karena itu
// format yang diminta/dikembalikan API (kolom DATE) sekaligus
// urut secara leksikografis sehingga perbandingan string aman.
// ============================================================

const _monthShort = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'Mei',
  'Jun',
  'Jul',
  'Agu',
  'Sep',
  'Okt',
  'Nov',
  'Des',
];

/// `yyyy-MM-dd` dari instant apa pun, selalu dalam kalender WIB
/// (hari libur adalah tanggal kalender di zona waktu profesional).
String _ymdFrom(DateTime d) => wibDateKey(d);

/// "2026-11-03" -> "Sen, 3 Nov 2026".
String _formatYmdId(String ymd) {
  final d = DateTime.tryParse(ymd);
  if (d == null) return ymd;
  const days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
  return '${days[d.weekday - 1]}, ${d.day} ${_monthShort[d.month - 1]} ${d.year}';
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
  List<BackendTimeOff> _timeOff = const [];
  bool _isLoading = true;
  String? _error;

  final _chatPrice = TextEditingController();
  final _videoPrice = TextEditingController();
  final _packagePrice = TextEditingController();
  int _newDay = 1;
  String _newCategory = 'quick_chat';
  int? _patientCapacity;
  int? _savedPatientCapacity;
  bool _savingCapacity = false;
  final _newStart = TextEditingController(text: '09:00');
  final _newEnd = TextEditingController(text: '16:00');
  final _newDuration = TextEditingController(text: '60');
  final _offReason = TextEditingController();
  DateTime? _offDate;
  bool _savingOff = false;
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
    _newStart.dispose();
    _newEnd.dispose();
    _newDuration.dispose();
    _offReason.dispose();
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
        _api.listMySchedules(accessToken: token),
        _api.getPricing(accessToken: token),
        _api.listTimeOff(accessToken: token),
      ]);
      if (!mounted) return;
      final pricing = results[1] as BackendProfessionalPricing;
      setState(() {
        _schedules = results[0] as List<BackendProfessionalSchedule>;
        _timeOff = results[2] as List<BackendTimeOff>;
        _savedPatientCapacity = pricing.patientCapacity;
        _patientCapacity = pricing.patientCapacity;
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
          ? const Color(0xFFF5EFF9)
          : null,
      appBar: AppBar(
        title: const Text('Ketersediaan & Harga'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
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
                        !_savingOff &&
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
                      const Text('Jadwal aktif tampil di sisi pasien.'),
                      const SizedBox(height: 12),
                      for (final category in professionalServiceNames.keys)
                        if (category != 'shared' ||
                            _schedules.any((slot) =>
                                slot.serviceCategory == 'shared')) ...[
                          _categoryCard(category),
                          const SizedBox(height: 12),
                        ],
                      SoftCard(
                        bordered: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Tambah jadwal',
                                style: TextStyle(fontWeight: FontWeight.w900)),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _categoryDropdown(
                                      _newCategory,
                                      (value) =>
                                          setState(() => _newCategory = value)),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonFormField<int>(
                                    initialValue: _newDay,
                                    isExpanded: true,
                                    decoration: _scheduleField(context, 'Hari'),
                                    items: [
                                      for (final d in [1, 2, 3, 4, 5, 6, 0])
                                        DropdownMenuItem(
                                            value: d,
                                            child: Text(_dayNames[d])),
                                    ],
                                    onChanged: (v) {
                                      if (v != null)
                                        setState(() => _newDay = v);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _newStart,
                                    decoration:
                                        _scheduleField(context, 'Mulai'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _newEnd,
                                    decoration:
                                        _scheduleField(context, 'Selesai'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _newDuration,
                                    keyboardType: TextInputType.number,
                                    decoration:
                                        _scheduleField(context, 'Slot (mnt)'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: _savingSchedules ? null : _addSchedule,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Tambah & Simpan'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const Text('Harga layanan',
                          style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 10),
                      ProfessionalPriceCard(
                        chat: _chatPrice,
                        video: _videoPrice,
                        package: _packagePrice,
                        onSave: _savePricing,
                        isSaving: _savingPricing || _savingCapacity,
                      ),
                      const SizedBox(height: 14),
                      const SectionLabel('Hari libur'),
                      SoftCard(
                        bordered: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Tanggal libur tidak bisa dipilih pasien saat '
                              'booking. Sesi yang sudah terlanjur terjadwal '
                              'pada tanggal itu TIDAK otomatis dibatalkan — '
                              'batalkan atau reschedule dari tab Jadwal.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 12),
                            if (_upcomingTimeOff.isEmpty)
                              const EmptyState(
                                icon: Icons.beach_access_outlined,
                                title: 'Belum ada hari libur',
                                subtitle:
                                    'Tambahkan tanggal saat kamu tidak praktik.',
                              )
                            else
                              for (final t in _upcomingTimeOff) ...[
                                Row(
                                  children: [
                                    const Icon(Icons.event_busy_rounded,
                                        size: 18, color: MalvaColors.amber),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _formatYmdId(t.offDate),
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w800),
                                          ),
                                          if (t.reason.isNotEmpty)
                                            Text(
                                              t.reason,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Hapus hari libur',
                                      onPressed: () => _removeTimeOff(t),
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                        color: MalvaColors.danger,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: _pickOffDate,
                              icon: const Icon(Icons.calendar_month_rounded,
                                  size: 18),
                              label: Text(
                                _offDate == null
                                    ? 'Pilih tanggal libur'
                                    : _formatYmdId(_ymdFrom(_offDate!)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _offReason,
                              decoration: const InputDecoration(
                                labelText: 'Alasan (opsional)',
                                hintText: 'Cuti, seminar, hari besar',
                              ),
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: _savingOff ? null : _addTimeOff,
                              icon: const Icon(Icons.add_rounded),
                              label: Text(_savingOff
                                  ? 'Menyimpan…'
                                  : 'Tambah hari libur'),
                            ),
                          ],
                        ),
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
      borderRadius: BorderRadius.circular(8),
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

  Widget _categoryDropdown(String selected, ValueChanged<String> onChanged) {
    return DropdownButtonFormField<String>(
      initialValue: selected,
      isExpanded: true,
      decoration: _scheduleField(context, 'Kategori'),
      items: [
        for (final option in professionalServiceNames.entries)
          DropdownMenuItem(
              value: option.key,
              child: Text(option.value, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }

  Widget _categoryCard(String category) {
    final rows = _schedules
        .where((slot) => slot.serviceCategory == category)
        .toList()
      ..sort((a, b) {
        final day = ((a.dayOfWeek + 6) % 7).compareTo((b.dayOfWeek + 6) % 7);
        return day == 0 ? a.startTime.compareTo(b.startTime) : day;
      });
    final shared = category != 'shared' &&
        rows.isEmpty &&
        _schedules.any((slot) => slot.serviceCategory == 'shared');
    return SoftCard(
      radius: 14,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: MalvaColors.seed.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(professionalServiceIcons[category],
                      color: MalvaColors.seed, size: 19),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(professionalServiceNames[category]!,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900))),
            ],
          ),
          if (rows.isEmpty)
            Text(shared ? 'Mengikuti jadwal bersama.' : 'Belum ada jadwal.')
          else
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) const Divider(height: 1),
              _scheduleRow(rows[i]),
            ],
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
            const Text('Slot pasien',
                style: TextStyle(fontWeight: FontWeight.w800)),
            Text(capacity == null
                ? 'Tanpa batas pasien aktif'
                : capacity == 0
                    ? 'Ditutup untuk pasien baru'
                    : 'Maks. $capacity pasien aktif'),
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                IconButton(
                  tooltip: 'Kurangi kapasitas',
                  onPressed: _savingCapacity ||
                          capacity == null ||
                          capacity == 0
                      ? null
                      : () => setState(() => _patientCapacity = capacity - 1),
                  icon: const Icon(Icons.remove),
                ),
                Text(capacity?.toString() ?? '∞'),
                IconButton(
                  tooltip: 'Tambah kapasitas',
                  onPressed: _savingCapacity || (capacity ?? 0) >= 2147483647
                      ? null
                      : () => setState(
                          () => _patientCapacity = (capacity ?? 0) + 1),
                  icon: const Icon(Icons.add),
                ),
                if (capacity != null)
                  TextButton(
                    onPressed: _savingCapacity
                        ? null
                        : () => setState(() => _patientCapacity = null),
                    child: const Text('Tanpa batas'),
                  ),
              ],
            ),
            if (_savingCapacity || capacity != _savedPatientCapacity)
              FilledButton(
                onPressed:
                    _savingCapacity || _savingPricing ? null : _saveCapacity,
                child:
                    Text(_savingCapacity ? 'Menyimpan...' : 'Simpan kapasitas'),
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
        clearPatientCapacity: capacity == null,
      );
      if (!mounted) return;
      setState(() {
        _savedPatientCapacity = updated.patientCapacity;
        _patientCapacity = updated.patientCapacity;
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

  Widget _scheduleRow(BackendProfessionalSchedule schedule) {
    final day = _dayNames[schedule.dayOfWeek];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
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
                        style: const TextStyle(fontWeight: FontWeight.w800)),
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
                onChanged:
                    _savingSchedules ? null : (_) => _toggleSchedule(schedule),
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
                _editSchedule(schedule);
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

  Future<void> _editSchedule(BackendProfessionalSchedule schedule) async {
    var day = schedule.dayOfWeek;
    var category = schedule.serviceCategory;
    var start = schedule.startTime;
    var end = schedule.endTime;
    var durationText = '${schedule.slotDurationMinutes}';
    final edited = await showDialog<Map<String, Object?>>(
      context: context,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: const Text('Edit jadwal',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
            contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            scrollable: true,
            content: SizedBox(
              width: 430,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _categoryDropdown(category,
                      (value) => setDialogState(() => category = value)),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<int>(
                    initialValue: day,
                    decoration: _scheduleField(context, 'Hari'),
                    items: [
                      for (final i in [1, 2, 3, 4, 5, 6, 0])
                        DropdownMenuItem(value: i, child: Text(_dayNames[i])),
                    ],
                    onChanged: (value) {
                      if (value != null) day = value;
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                          child: TextFormField(
                        initialValue: start,
                        onChanged: (value) => start = value,
                        decoration: _scheduleField(context, 'Mulai'),
                      )),
                      const SizedBox(width: 8),
                      Expanded(
                          child: TextFormField(
                        initialValue: end,
                        onChanged: (value) => end = value,
                        decoration: _scheduleField(context, 'Selesai'),
                      )),
                      const SizedBox(width: 8),
                      Expanded(
                          child: TextFormField(
                        initialValue: durationText,
                        onChanged: (value) => durationText = value,
                        keyboardType: TextInputType.number,
                        decoration: _scheduleField(context, 'Slot (mnt)'),
                      )),
                    ],
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
                    Text(error!,
                        style: const TextStyle(color: MalvaColors.danger)),
                  ],
                ],
              ),
            ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Batal'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      child: const Text('Simpan perubahan',
                          textAlign: TextAlign.center),
                      onPressed: () {
                        final duration = int.tryParse(durationText.trim()) ?? 0;
                        final times =
                            RegExp(r'^(?:[01][0-9]|2[0-3]):[0-5][0-9]$');
                        final from = start.trim();
                        final to = end.trim();
                        if (!times.hasMatch(from) ||
                            !times.hasMatch(to) ||
                            from.compareTo(to) >= 0) {
                          setDialogState(() => error =
                              'Isi jam mulai dan selesai dalam urutan yang benar (HH:MM).');
                          return;
                        }
                        if (duration < 60 || duration > 180) {
                          setDialogState(() => error =
                              'Slot minimal 60 menit dan maksimal 180 menit.');
                          return;
                        }
                        if (_schedules.any((other) =>
                            other.id != schedule.id &&
                            other.serviceCategory == category &&
                            other.dayOfWeek == day &&
                            other.startTime == from &&
                            other.endTime == to)) {
                          setDialogState(() => error =
                              'Jadwal dengan hari dan jam tersebut sudah ada.');
                          return;
                        }
                        Navigator.pop(context, {
                          'id': schedule.id,
                          'service_category': category,
                          'day_of_week': day,
                          'start_time': from,
                          'end_time': to,
                          'slot_duration_minutes': duration,
                          'is_active': schedule.isActive,
                        });
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
    if (!mounted || edited == null) return;
    await _writeSchedules([
      for (final row in _schedules)
        if (row.id == schedule.id) edited else _scheduleToPayload(row),
    ], 'Perubahan jadwal disimpan.');
  }

  // ==========================================================
  // Hari libur (professional_time_off)
  // Sisi server sudah lama mendukung GET/POST/DELETE time-off dan
  // memakainya saat menghitung slot, tetapi belum ada layar untuk
  // mengisinya — sehingga profesional hanya bisa "menutup" hari
  // dengan menghapus jadwal mingguan (yang menghapus polanya juga).
  // ==========================================================

  /// Hari libur hari ini dan yang akan datang, urut terdekat.
  /// Tanggal lampau tidak ditampilkan karena tidak lagi berguna
  /// (tidak memblokir slot apa pun).
  List<BackendTimeOff> get _upcomingTimeOff {
    final today = _ymdFrom(wibNow());
    return _timeOff.where((t) => t.offDate.compareTo(today) >= 0).toList()
      ..sort((a, b) => a.offDate.compareTo(b.offDate));
  }

  Future<void> _pickOffDate() async {
    final now = wibNow();
    final picked = await showDatePicker(
      context: context,
      initialDate: _offDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 1, now.month, now.day),
      helpText: 'Pilih tanggal libur',
    );
    if (picked != null && mounted) setState(() => _offDate = picked);
  }

  Future<void> _addTimeOff() async {
    final token = _token;
    if (token == null) return;
    final date = _offDate;
    if (date == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih tanggal libur dulu.'),
          backgroundColor: MalvaColors.amber,
        ),
      );
      return;
    }
    setState(() => _savingOff = true);
    try {
      final created = await _api.addTimeOff(
        accessToken: token,
        offDate: _ymdFrom(date),
        reason: _offReason.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        // Server memakai ON CONFLICT (professional_id, off_date), jadi tanggal
        // yang sama menimpa baris lama: buang entri lama agar tidak dobel.
        final next = [
          ..._timeOff.where((e) => e.offDate != created.offDate),
          created,
        ]..sort((a, b) => a.offDate.compareTo(b.offDate));
        _timeOff = next;
        _offDate = null;
        _offReason.clear();
        _savingOff = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hari libur disimpan.')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      setState(() => _savingOff = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(e)),
          backgroundColor: MalvaColors.danger,
        ),
      );
    }
  }

  Future<void> _removeTimeOff(BackendTimeOff item) async {
    final token = _token;
    if (token == null) return;
    try {
      await _api.deleteTimeOff(accessToken: token, id: item.id);
      if (!mounted) return;
      setState(() {
        _timeOff =
            _timeOff.where((e) => e.id != item.id).toList(growable: false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hari libur dihapus.')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(friendlyErrorMessage(e)),
          backgroundColor: MalvaColors.danger,
        ),
      );
    }
  }

  /// Payload satu baris jadwal untuk PUT /v1/professional/schedules.
  /// `is_active` selalu dikirim eksplisit; bila null pakai status baris.
  Map<String, Object?> _scheduleToPayload(
    BackendProfessionalSchedule s, {
    bool? isActive,
  }) =>
      {
        'service_category': s.serviceCategory,
        'day_of_week': s.dayOfWeek,
        'start_time': s.startTime,
        'end_time': s.endTime,
        'slot_duration_minutes': s.slotDurationMinutes,
        'is_active': isActive ?? s.isActive,
      };

  Future<void> _addSchedule() async {
    final duration = int.tryParse(_newDuration.text.trim()) ?? 0;
    if (duration < 60 || duration > 180) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Slot minimal 60 menit dan maksimal 180 menit.')));
      return;
    }
    final next = [
      ..._schedules.map(_scheduleToPayload),
      {
        'service_category': _newCategory,
        'day_of_week': _newDay,
        'start_time': _newStart.text.trim(),
        'end_time': _newEnd.text.trim(),
        'slot_duration_minutes': duration,
        'is_active': true,
      },
    ];
    await _writeSchedules(next, 'Jadwal tersimpan.');
  }

  Future<void> _writeSchedules(
      List<Map<String, Object?>> schedules, String message) async {
    final token = _token;
    if (token == null || _savingSchedules) return;
    setState(() => _savingSchedules = true);
    try {
      final updated = await _api.updateMySchedules(
          accessToken: token, schedules: schedules);
      if (!mounted) return;
      setState(() => _schedules = updated);
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
        content: const Text(
            'Jadwal ini akan dihapus permanen dan tidak bisa dikembalikan. '
            'Bila hanya ingin menyembunyikan sementara, gunakan '
            '"Nonaktifkan" — jadwal tetap tersimpan dan bisa diaktifkan lagi.'),
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
  Future<void> _toggleSchedule(BackendProfessionalSchedule s) =>
      _writeSchedules([
        for (final row in _schedules)
          _scheduleToPayload(row,
              isActive: row.id == s.id ? !row.isActive : null),
      ], s.isActive ? 'Jadwal dinonaktifkan.' : 'Jadwal diaktifkan.');

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
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Harga tersimpan.')),
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
