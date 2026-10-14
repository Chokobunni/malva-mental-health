import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';
import 'chat_screen.dart';
import 'pro_patient_detail_screen.dart';

// ============================================================
// PRO SCHEDULE — tab "Jadwal" dashboard profesional:
//   - Sesi hari ini & mendatang: join chat, tandai hadir/tidak,
//     batal (kredit kembali), reschedule, meeting URL, ringkasan.
//   - Ketersediaan: jadwal mingguan (hari available) — bisa
//     diaktifkan/nonaktifkan per baris.
//   - Harga layanan: quick chat / quick video / paket 4 sesi.
// Semua dari server — tanpa data demo.
// ============================================================

class ProScheduleScreen extends ConsumerStatefulWidget {
  const ProScheduleScreen({super.key, this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<ProScheduleScreen> createState() => _ProScheduleScreenState();
}

class _ProScheduleScreenState extends ConsumerState<ProScheduleScreen> {
  List<BackendCareSession> _today = const [];
  List<BackendCareSession> _upcoming = const [];
  List<BackendCareSession> _past = const [];
  List<BackendProfessionalSchedule> _schedules = const [];
  BackendProfessionalPricing _pricing = const BackendProfessionalPricing();
  bool _isLoading = true;
  String? _error;

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

  Future<void> _load() async {
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
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.listCareSessions(accessToken: token, scope: 'today'),
        _api.listCareSessions(accessToken: token, scope: 'upcoming'),
        _api.listCareSessions(accessToken: token, scope: 'past'),
        _api.listMySchedules(accessToken: token),
        _api.getPricing(accessToken: token),
      ]);
      if (!mounted) return;
      setState(() {
        _today = (results[0] as List<BackendCareSession>);
        _upcoming = (results[1] as List<BackendCareSession>)
          ..sort((a, b) =>
              (a.scheduledAt ?? '').compareTo(b.scheduledAt ?? ''));
        _past = (results[2] as List<BackendCareSession>);
        _schedules = (results[3] as List<BackendProfessionalSchedule>);
        _pricing = (results[4] as BackendProfessionalPricing);
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

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const SectionLabel('Sesi hari ini'),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            SoftCard(
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
            if (_today.isEmpty)
              const EmptyState(
                icon: Icons.event_available_outlined,
                title: 'Tidak ada sesi hari ini',
                subtitle: 'Sesi terjadwal hari ini muncul di sini.',
              )
            else
              for (final s in _today) ...[
                _ProSessionCard(session: s, onChanged: _load),
                const SizedBox(height: 10),
              ],
            const SizedBox(height: 10),
            const SectionLabel('Mendatang'),
            if (_upcoming.isEmpty)
              const EmptyState(
                icon: Icons.calendar_month_outlined,
                title: 'Belum ada sesi mendatang',
                subtitle: 'Pasien menjadwalkan sesi dari paket / quick consult.',
              )
            else
              for (final s in _upcoming.take(10)) ...[
                _ProSessionCard(session: s, onChanged: _load),
                const SizedBox(height: 10),
              ],
            const SizedBox(height: 10),
            // Info referensi (jam praktik + harga) dilipat agar tidak setara
            // bobotnya dengan daftar sesi. Tombol "Atur" tetap di area header
            // (selalu terlihat) sehingga aksinya tidak tersembunyi.
            CollapsibleCard(
              header: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Ketersediaan & harga',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () => _openAvailability(context),
                    icon: const Icon(Icons.edit_calendar_rounded, size: 18),
                    label: const Text('Atur'),
                  ),
                ],
              ),
              child: _AvailabilitySummary(
                schedules: _schedules,
                pricing: _pricing,
              ),
            ),
            const SizedBox(height: 10),
            const SectionLabel('Riwayat sesi'),
            if (_past.isEmpty)
              const EmptyState(
                icon: Icons.history_rounded,
                title: 'Belum ada riwayat',
                subtitle: 'Sesi selesai / batal tercatat di sini.',
              )
            else
              for (final s in _past.take(10)) ...[
                _ProSessionCard(session: s, onChanged: _load, past: true),
                const SizedBox(height: 10),
              ],
          ],
        ],
      ),
    );
  }

  Future<void> _openAvailability(BuildContext context) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProAvailabilityScreen(
          session: widget.session,
          apiClient: widget.apiClient,
        ),
      ),
    );
    await _load();
  }
}

class _ProSessionCard extends ConsumerWidget {
  const _ProSessionCard(
      {required this.session, required this.onChanged, this.past = false});

  final BackendCareSession session;
  final Future<void> Function() onChanged;
  final bool past;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final at = session.scheduledDateTime?.toLocal();
    final dateLabel = at == null
        ? '-'
        : '${at.day}/${at.month}/${at.year} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final statusColor = switch (session.status) {
      'scheduled' => MalvaColors.seed,
      'completed' => MalvaColors.mint,
      'no_show' => MalvaColors.danger,
      'cancelled_by_professional' => MalvaColors.amber,
      'cancelled_by_patient' => Theme.of(context).colorScheme.onSurfaceVariant,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: MalvaColors.seed.withValues(alpha: 0.12),
                child: Text(
                  session.patientName.isEmpty
                      ? '?'
                      : session.patientName.characters.first.toUpperCase(),
                  style: const TextStyle(
                      color: MalvaColors.seed, fontWeight: FontWeight.w900),
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
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      '$dateLabel • ${session.isVideo ? 'Video' : 'Chat'} • ${session.durationMinutes} mnt'
                      '${session.packageId == null ? ' • sekali sesi' : ''}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              StatusPill(label: session.status, color: statusColor),
            ],
          ),
          if (session.summaryForPatient.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Ringkasan: ${session.summaryForPatient}',
                style: Theme.of(context).textTheme.bodySmall),
          ],
          if (session.summaryForPatient.isNotEmpty && past) ...[
            const SizedBox(height: 6),
            OutlinedButton.icon(
              onPressed: () => _openPatientDetail(context),
              icon: const Icon(Icons.person_rounded, size: 16),
              label: const Text('Buka detail pasien'),
            ),
          ],
          if (!past && session.isScheduled) ...[
            const SizedBox(height: 10),
            // Lapis 2 — aksi primer (paling sering dipakai saat sesi berjalan).
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => _openChat(context),
                  style: compactFilledButtonStyle,
                  icon: const Icon(Icons.chat_bubble_rounded, size: 16),
                  label: const Text('Join / Chat'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _mark(context, ref, 'completed'),
                  icon: const Icon(Icons.check_rounded, size: 16),
                  label: const Text('Hadir'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _mark(context, ref, 'no_show'),
                  icon: const Icon(Icons.person_off_rounded, size: 16),
                  label: const Text('Tidak hadir'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Lapis 3 — aksi sekunder dilipat agar kartu tidak penuh tombol.
            // Semua handler tetap terpasang dan tetap bisa ditekan.
            CollapsibleCard(
              header: const Text(
                'Aksi lain',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: () => _openPatientDetail(context),
                    icon: const Icon(Icons.person_rounded, size: 16),
                    label: const Text('Detail pasien'),
                  ),
                  if (session.isVideo && session.meetingUrl.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () => _openMeeting(context),
                      icon: const Icon(Icons.videocam_rounded, size: 16),
                      label: const Text('Meeting'),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _cancel(context, ref),
                    icon: const Icon(Icons.cancel_rounded, size: 16),
                    label: const Text('Batal'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _reschedule(context, ref),
                    icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                    label: const Text('Reschedule'),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _editDetail(context, ref),
                    icon: const Icon(Icons.edit_note_rounded, size: 16),
                    label: const Text('Link & ringkasan'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _openChat(BuildContext context) {
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

  void _openPatientDetail(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProPatientDetailScreen(
          patientId: session.patientId,
          patientName:
              session.patientName.isEmpty ? 'Pasien' : session.patientName,
        ),
      ),
    );
  }

  Future<void> _openMeeting(BuildContext context) async {
    final uri = Uri.tryParse(session.meetingUrl.trim());
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _mark(
      BuildContext context, WidgetRef ref, String status) async {
    final api = ref.read(apiClientProvider);
    final token = ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      await api.updateCareSession(
        accessToken: token,
        sessionId: session.id,
        status: status,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(status == 'completed'
                ? 'Sesi ditandai selesai.'
                : 'Pasien ditandai tidak hadir (sesi hangus).')),
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
              decoration: const InputDecoration(
                  labelText: 'Alasan (opsional)'),
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
              backgroundColor:
                  const WidgetStatePropertyAll(MalvaColors.danger),
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
    final dateController = TextEditingController();
    final timeController = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reschedule sesi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: dateController,
              decoration: const InputDecoration(
                  labelText: 'Tanggal (YYYY-MM-DD)',
                  hintText: '2026-10-20'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: timeController,
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
    final scheduledAt =
        '${dateController.text.trim()}T${timeController.text.trim()}';
    dateController.dispose();
    timeController.dispose();
    if (confirmed != true || !context.mounted) return;
    final api = ref.read(apiClientProvider);
    final token = ref.read(currentSessionProvider)?.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      await api.rescheduleCareSession(
        accessToken: token,
        sessionId: session.id,
        scheduledAt: scheduledAt,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesi berhasil di-reschedule.')),
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

  Future<void> _editDetail(BuildContext context, WidgetRef ref) async {
    final meetingController =
        TextEditingController(text: session.meetingUrl);
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

class _AvailabilitySummary extends StatelessWidget {
  const _AvailabilitySummary({
    required this.schedules,
    required this.pricing,
  });

  final List<BackendProfessionalSchedule> schedules;
  final BackendProfessionalPricing pricing;

  static const _dayNames = [
    'Min',
    'Sen',
    'Sel',
    'Rab',
    'Kam',
    'Jum',
    'Sab',
  ];

  @override
  Widget build(BuildContext context) {
    final byDay = <int, List<BackendProfessionalSchedule>>{};
    for (final s in schedules) {
      (byDay[s.dayOfWeek] ??= []).add(s);
    }
    String rupiah(int v) {
      if (v <= 0) return 'belum diatur';
      final s = v.toString();
      final buf = StringBuffer();
      for (var i = 0; i < s.length; i++) {
        final pos = s.length - i;
        buf.write(s[i]);
        if (pos > 1 && pos % 3 == 1) buf.write('.');
      }
      return 'Rp ${buf.toString()}';
    }

    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Jam praktik mingguan',
              style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          if (byDay.isEmpty)
            const Text('Belum diatur — pasien tidak bisa booking.',
                style: TextStyle(color: MalvaColors.danger, fontSize: 12.5))
          else
            for (final d in (byDay.keys.toList()..sort())) ...[
              Text(
                '${_dayNames[d]}: ${byDay[d]!.map((s) => '${s.startTime}–${s.endTime} (${s.slotDurationMinutes} mnt)').join(', ')}',
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 2),
            ],
          const Divider(height: 18),
          Text('Chat: ${rupiah(pricing.quickChatPrice)}',
              style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 2),
          Text('Video: ${rupiah(pricing.quickVideoPrice)}',
              style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 2),
          Text('Paket 4 sesi / 6 minggu: ${rupiah(pricing.packagePrice)}',
              style: const TextStyle(fontSize: 12.5)),
        ],
      ),
    );
  }
}

/// Layar ketersediaan & harga: jadwal mingguan + tarif.
class ProAvailabilityScreen extends ConsumerStatefulWidget {
  const ProAvailabilityScreen({super.key, this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<ProAvailabilityScreen> createState() =>
      _ProAvailabilityScreenState();
}

class _ProAvailabilityScreenState
    extends ConsumerState<ProAvailabilityScreen> {
  List<BackendProfessionalSchedule> _schedules = const [];
  bool _isLoading = true;
  String? _error;

  final _chatPrice = TextEditingController();
  final _videoPrice = TextEditingController();
  final _packagePrice = TextEditingController();
  int _newDay = 1;
  final _newStart = TextEditingController(text: '09:00');
  final _newEnd = TextEditingController(text: '16:00');
  final _newDuration = TextEditingController(text: '30');

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
      ]);
      if (!mounted) return;
      final pricing = results[1] as BackendProfessionalPricing;
      setState(() {
        _schedules = results[0] as List<BackendProfessionalSchedule>;
        _chatPrice.text =
            pricing.quickChatPrice > 0 ? '${pricing.quickChatPrice}' : '';
        _videoPrice.text =
            pricing.quickVideoPrice > 0 ? '${pricing.quickVideoPrice}' : '';
        _packagePrice.text =
            pricing.packagePrice > 0 ? '${pricing.packagePrice}' : '';
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

  static const _dayNames = ['Min', 'Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      const SectionLabel(
                          'Hari praktik (yang muncul di sisi pasien)'),
                      if (_schedules.isEmpty)
                        const EmptyState(
                          icon: Icons.event_busy_rounded,
                          title: 'Belum ada jadwal',
                          subtitle:
                              'Tambahkan hari praktik agar pasien bisa booking.',
                        )
                      else
                        for (final s in _schedules) ...[
                          SoftCard(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Opacity(
                                        opacity: s.isActive ? 1.0 : 0.5,
                                        child: Text(
                                          '${_dayNames[s.dayOfWeek]} • ${s.startTime}–${s.endTime} • ${s.slotDurationMinutes} mnt/slot',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                    ),
                                    if (!s.isActive)
                                      const StatusPill(
                                        label: 'Nonaktif',
                                        color: MalvaColors.amber,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    OutlinedButton.icon(
                                      onPressed: () => _toggleSchedule(s),
                                      icon: Icon(
                                        s.isActive
                                            ? Icons.pause_circle_outline_rounded
                                            : Icons.play_circle_outline_rounded,
                                        size: 16,
                                      ),
                                      label: Text(
                                          s.isActive ? 'Nonaktifkan' : 'Aktifkan'),
                                    ),
                                    OutlinedButton(
                                      onPressed: () => _removeSchedule(s),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: MalvaColors.danger,
                                      ),
                                      child: const Text('Hapus'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 8),
                        ],
                      SoftCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Text('Tambah jadwal',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900)),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<int>(
                              initialValue: _newDay,
                              decoration: const InputDecoration(
                                  labelText: 'Hari'),
                              items: [
                                for (var d = 0; d < 7; d++)
                                  DropdownMenuItem(
                                      value: d,
                                      child: Text(_dayNames[d])),
                              ],
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _newDay = v);
                                }
                              },
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _newStart,
                                    decoration: const InputDecoration(
                                        labelText: 'Mulai (HH:MM)'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _newEnd,
                                    decoration: const InputDecoration(
                                        labelText: 'Selesai (HH:MM)'),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _newDuration,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                        labelText: 'Slot (mnt)'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: _addSchedule,
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Tambah & Simpan'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),
                      const SectionLabel('Harga layanan'),
                      SoftCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _chatPrice,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Quick chat 1 sesi (Rp)',
                                  hintText: '150000'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _videoPrice,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Quick video 1 sesi (Rp)',
                                  hintText: '250000'),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _packagePrice,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'Paket 4 sesi / 6 minggu (Rp)',
                                  hintText: '799000'),
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: _savePricing,
                              icon: const Icon(Icons.save_rounded),
                              label: const Text('Simpan harga'),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Jumlah sesi paket tetap 4 & masa berlaku 6 minggu; yang kamu atur hanya harga.',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
  }

  /// Payload satu baris jadwal untuk PUT /v1/professional/schedules.
  /// `is_active` selalu dikirim eksplisit; bila null pakai status baris.
  Map<String, Object?> _scheduleToPayload(
    BackendProfessionalSchedule s, {
    bool? isActive,
  }) =>
      {
        'day_of_week': s.dayOfWeek,
        'start_time': s.startTime,
        'end_time': s.endTime,
        'slot_duration_minutes': s.slotDurationMinutes,
        'is_active': isActive ?? s.isActive,
      };

  Future<void> _addSchedule() async {
    final token = _token;
    if (token == null) return;
    final duration = int.tryParse(_newDuration.text.trim()) ?? 30;
    final next = [
      ..._schedules.map(_scheduleToPayload),
      {
        'day_of_week': _newDay,
        'start_time': _newStart.text.trim(),
        'end_time': _newEnd.text.trim(),
        'slot_duration_minutes': duration,
        'is_active': true,
      },
    ];
    try {
      final updated = await _api.updateMySchedules(
        accessToken: token,
        schedules: next,
      );
      if (!mounted) return;
      setState(() => _schedules = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jadwal tersimpan.')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }

  Future<void> _removeSchedule(BackendProfessionalSchedule s) async {
    final token = _token;
    if (token == null) return;
    final next = _schedules
        .where((e) =>
            e.dayOfWeek != s.dayOfWeek ||
            e.startTime != s.startTime ||
            e.endTime != s.endTime)
        .map(_scheduleToPayload)
        .toList();
    try {
      final updated = await _api.updateMySchedules(
        accessToken: token,
        schedules: next,
      );
      if (!mounted) return;
      setState(() => _schedules = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Jadwal dihapus.')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }

  /// Aktifkan/nonaktifkan satu baris jadwal (toggle) tanpa menghapusnya,
  /// sehingga baris tetap tampil dan bisa diaktifkan kembali.
  Future<void> _toggleSchedule(BackendProfessionalSchedule s) async {
    final token = _token;
    if (token == null) return;
    final next = [
      for (final e in _schedules)
        _scheduleToPayload(
          e,
          isActive: (e.dayOfWeek == s.dayOfWeek &&
                  e.startTime == s.startTime &&
                  e.endTime == s.endTime)
              ? !e.isActive
              : e.isActive,
        ),
    ];
    try {
      final updated = await _api.updateMySchedules(
        accessToken: token,
        schedules: next,
      );
      if (!mounted) return;
      setState(() => _schedules = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(
                s.isActive ? 'Jadwal dinonaktifkan.' : 'Jadwal diaktifkan.')),
      );
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }

  Future<void> _savePricing() async {
    final token = _token;
    if (token == null) return;
    try {
      await _api.updatePricing(
        accessToken: token,
        quickChatPrice: int.tryParse(_chatPrice.text.trim()) ?? 0,
        quickVideoPrice: int.tryParse(_videoPrice.text.trim()) ?? 0,
        packagePrice: int.tryParse(_packagePrice.text.trim()) ?? 0,
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
    }
  }
}