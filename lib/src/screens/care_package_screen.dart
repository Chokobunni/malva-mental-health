import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';
import 'chat_screen.dart';

// ============================================================
// CARE PACKAGE — status paket 4 sesi / 6 minggu + daftar sesi.
// Pasien: jadwalkan sesi dari sisa, reschedule/cancel (>=24 jam),
// buka chat sesi. Aturan hangus & refund dijelaskan di kartu.
// ============================================================

/// Format angka rupiah sederhana: 125000 → "Rp 125.000".
String _rupiah(int value) {
  if (value <= 0) return 'Rp 0';
  final s = value.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final pos = s.length - i;
    buf.write(s[i]);
    if (pos > 1 && pos % 3 == 1) buf.write('.');
  }
  return 'Rp $buf';
}

class CarePackageScreen extends ConsumerStatefulWidget {
  const CarePackageScreen({
    super.key,
    required this.package,
    this.session,
    this.apiClient,
  });

  final BackendCarePackage package;
  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<CarePackageScreen> createState() => _CarePackageScreenState();
}

class _CarePackageScreenState extends ConsumerState<CarePackageScreen> {
  late BackendCarePackage _package;
  List<BackendCareSession> _sessions = const [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _package = widget.package;
    _load();
  }

  Future<void> _load() async {
    final MalvaApiClient apiClient =
        widget.apiClient ?? ref.read(apiClientProvider);
    final token = widget.session?.accessToken;
    if (token == null || token.isEmpty) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = 'Mode offline aktif.';
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
        apiClient.listCarePackages(accessToken: token),
        apiClient.listCareSessions(accessToken: token, scope: 'all'),
      ]);
      if (!mounted) return;
      final pkgs = results[0] as List<BackendCarePackage>;
      final sessions = results[1] as List<BackendCareSession>;
      BackendCarePackage? mine;
      for (final p in pkgs) {
        if (p.id == _package.id) {
          mine = p;
          break;
        }
      }
      setState(() {
        if (mine != null) _package = mine;
        _sessions = sessions
            .where((s) => s.packageId == _package.id)
            .toList(growable: false)
          ..sort(
              (a, b) => (a.scheduledAt ?? '').compareTo(b.scheduledAt ?? ''));
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

  List<BackendCareSession> get _upcoming =>
      _sessions.where((s) => s.isScheduled).toList(growable: false);

  List<BackendCareSession> get _past =>
      _sessions.where((s) => !s.isScheduled).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final expires = _package.expiresDateTime?.toLocal();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paket Saya'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Muat ulang',
            onPressed: _isLoading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            SoftCard(
              color: MalvaColors.mint.withValues(alpha: 0.10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _package.professionalName.isEmpty
                              ? 'Paket Continuous'
                              : _package.professionalName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 16),
                        ),
                      ),
                      StatusPill(
                        label: _package.status,
                        color: _package.isActive
                            ? MalvaColors.mint
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ProgressStrip(
                    value: _package.totalSessions == 0
                        ? 0
                        : _package.usedSessions / _package.totalSessions,
                    color: MalvaColors.seed,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_package.remainingSessions}/${_package.totalSessions} sesi tersisa',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  if (expires != null)
                    Text(
                      'Berlaku s/d ${expires.day}/${expires.month}/${expires.year} — sisa hangus setelah itu.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  if (_package.refundedAmount > 0)
                    Text(
                      'Total refund uang: ${_rupiah(_package.refundedAmount)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w700, color: MalvaColors.mint),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const SoftCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Aturan paket',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 13)),
                  SizedBox(height: 6),
                  Text(
                    '• Tidak hadir = sesi hangus.\n'
                    '• Profesional batal = kredit kembali, bisa dijadwalkan ulang.\n'
                    '• Batal/reschedule olehmu minimal 24 jam sebelum sesi.\n'
                    '• Chat teks aktif saat sesi berjalan; kiriman data dibahas saat sesi.',
                    style: TextStyle(fontSize: 12.5),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
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
              if (_package.isActive && _package.remainingSessions > 0) ...[
                FilledButton.icon(
                  onPressed: () => _openScheduler(context),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Jadwalkan Sesi'),
                ),
                const SizedBox(height: 14),
              ],
              const SectionLabel('Sesi Mendatang'),
              if (_upcoming.isEmpty)
                const EmptyState(
                  icon: Icons.event_available_outlined,
                  title: 'Belum ada sesi terjadwal',
                  subtitle:
                      'Jadwalkan sesi dari sisa paketmu sebelum kedaluwarsa.',
                )
              else
                for (final s in _upcoming) ...[
                  _PackageSessionCard(
                    session: s,
                    onOpenChat: () => _openChat(s),
                    onReschedule: () => _openScheduler(context, existing: s),
                    onCancel: () => _cancelSession(s),
                  ),
                  const SizedBox(height: 10),
                ],
              const SizedBox(height: 8),
              const SectionLabel('Riwayat Sesi'),
              if (_past.isEmpty)
                const EmptyState(
                  icon: Icons.history_rounded,
                  title: 'Belum ada riwayat',
                  subtitle: 'Sesi yang selesai tercatat di sini.',
                )
              else
                for (final s in _past) ...[
                  _PackageSessionCard(
                    session: s,
                    past: true,
                    // Sesi yang dibatalkan profesional: boleh reschedule
                    // (pakai kredit) atau minta refund uang.
                    onReschedule: s.cancelledByProfessional
                        ? () => _openScheduler(context, existing: s)
                        : null,
                    onRequestRefund: s.cancelledByProfessional
                        ? () => _requestRefund(s)
                        : null,
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openScheduler(BuildContext context,
      {BackendCareSession? existing}) async {
    final token = widget.session?.accessToken;
    final MalvaApiClient apiClient =
        widget.apiClient ?? ref.read(apiClientProvider);
    if (token == null || token.isEmpty) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _SessionSchedulerSheet(
        apiClient: apiClient,
        accessToken: token,
        professionalId: _package.professionalId,
        expiresAt: _package.expiresDateTime,
        initialType: existing?.sessionType ?? 'chat',
      ),
    );
    if (picked == null || !mounted) return;
    try {
      if (existing != null) {
        await apiClient.rescheduleCareSession(
          accessToken: token,
          sessionId: existing.id,
          scheduledAt: picked,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sesi berhasil di-reschedule.')),
        );
      } else {
        final parts = picked.split('|');
        await apiClient.scheduleSession(
          accessToken: token,
          packageId: _package.id,
          scheduledAt: parts[0],
          sessionType: parts.length > 1 ? parts[1] : 'chat',
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sesi berhasil dijadwalkan.')),
        );
      }
      await _load();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }

  Future<void> _cancelSession(BackendCareSession s) async {
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
    if (confirmed != true) return;
    final MalvaApiClient apiClient =
        widget.apiClient ?? ref.read(apiClientProvider);
    final token = widget.session?.accessToken;
    if (token == null || token.isEmpty) return;
    try {
      await apiClient.updateCareSession(
        accessToken: token,
        sessionId: s.id,
        status: 'cancelled_by_patient',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sesi dibatalkan.')),
      );
      await _load();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }

  /// Minta refund uang untuk sesi yang dibatalkan profesional
  /// (POST /v1/care-sessions/{id}/refund). Idempoten di sisi server.
  Future<void> _requestRefund(BackendCareSession s) async {
    final token = widget.session?.accessToken;
    final MalvaApiClient apiClient =
        widget.apiClient ?? ref.read(apiClientProvider);
    if (token == null || token.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Minta refund?'),
        content: const Text(
            'Profesional membatalkan sesi ini. Kamu bisa meminta refund uang '
            '(diproses admin) atau tetap jadwalkan ulang memakai kredit sesi.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Minta refund'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      final result = await apiClient.requestCareRefund(
        accessToken: token,
        sessionId: s.id,
        kind: 'refund',
        reason: 'Profesional membatalkan; sesi tak bisa dijadwalkan ulang',
      );
      if (!mounted) return;
      if (result.package != null) {
        setState(() => _package = result.package!);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permintaan refund tercatat. Admin akan memproses.'),
          backgroundColor: MalvaColors.mint,
        ),
      );
      await _load();
    } on Object catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(friendlyErrorMessage(e)),
            backgroundColor: MalvaColors.danger),
      );
    }
  }

  void _openChat(BackendCareSession s) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          otherUserName: _package.professionalName.isEmpty
              ? 'Profesional'
              : _package.professionalName,
          otherUserId: _package.professionalId,
        ),
      ),
    );
  }
}

/// Sheet pilih tanggal (hari praktik) + jam + tipe sesi.
/// Mengembalikan "YYYY-MM-DDTHH:MM|chat|video".
class _SessionSchedulerSheet extends StatefulWidget {
  const _SessionSchedulerSheet({
    required this.apiClient,
    required this.accessToken,
    required this.professionalId,
    this.expiresAt,
    this.initialType = 'chat',
  });

  final MalvaApiClient apiClient;
  final String accessToken;
  final String professionalId;
  final DateTime? expiresAt;
  final String initialType;

  @override
  State<_SessionSchedulerSheet> createState() => _SessionSchedulerSheetState();
}

class _SessionSchedulerSheetState extends State<_SessionSchedulerSheet> {
  List<BackendAvailabilityDay> _days = const [];
  String? _date;
  String? _slot;
  String _type = 'chat';
  bool _loadingDays = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType == 'video' ? 'video' : 'chat';
    _loadDays();
  }

  Future<void> _loadDays() async {
    try {
      final days = await widget.apiClient.getDoctorAvailability(
        accessToken: widget.accessToken,
        userId: widget.professionalId,
      );
      if (!mounted) return;
      final exp = widget.expiresAt;
      final filtered = days.where((d) {
        if (!d.bookable) return false;
        if (exp == null) return true;
        final dt = DateTime.tryParse(d.date);
        if (dt == null) return true;
        return dt.isBefore(exp.add(const Duration(days: 1)));
      }).toList(growable: false);
      setState(() {
        _days = filtered;
        _loadingDays = false;
        _date = filtered.isEmpty ? null : filtered.first.date;
        _slot = null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDays = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Jadwalkan sesi',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 4),
            Text(
              'Hanya hari praktik profesional & sebelum paket kedaluwarsa.',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Chat'),
                  selected: _type == 'chat',
                  onSelected: (_) => setState(() => _type = 'chat'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Video'),
                  selected: _type == 'video',
                  onSelected: (_) => setState(() => _type = 'video'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingDays)
              const Center(child: CircularProgressIndicator())
            else if (_days.isEmpty)
              const Text('Tidak ada hari tersedia sebelum paket kedaluwarsa.')
            else
              SizedBox(
                height: 78,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final d in _days)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(_shortDay(d.date)),
                          selected: _date == d.date,
                          onSelected: (_) => setState(() {
                            _date = d.date;
                            _slot = null;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            if (_date != null)
              _FirstSessionSlots(
                apiClient: widget.apiClient,
                accessToken: widget.accessToken,
                professionalId: widget.professionalId,
                date: _date!,
                selected: _slot,
                onSelect: (t) => setState(() => _slot = t),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(
                      color: MalvaColors.danger, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: (_date == null || _slot == null)
                  ? null
                  : () => Navigator.pop(context, '${_date}T$_slot|$_type'),
              child: const Text('Pilih Jadwal'),
            ),
          ],
        ),
      ),
    );
  }

  static String _shortDay(String yyyyMmDd) {
    final d = DateTime.tryParse(yyyyMmDd);
    if (d == null) return yyyyMmDd;
    const days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    return '${days[d.weekday - 1]} ${d.day}/${d.month}';
  }
}

/// Sheet pilih slot sesi PERTAMA paket (dipakai saat pembayaran paket).
/// Sama seperti _SessionSchedulerSheet tapi tanpa batas kedaluwarsa paket
/// (paket baru aktif setelah bayar; expiry dihitung dari aktivasi).
class PackageFirstSessionSheet extends StatefulWidget {
  const PackageFirstSessionSheet({
    super.key,
    required this.apiClient,
    required this.accessToken,
    required this.professionalId,
  });

  final MalvaApiClient apiClient;
  final String accessToken;
  final String professionalId;

  @override
  State<PackageFirstSessionSheet> createState() =>
      _PackageFirstSessionSheetState();
}

class _PackageFirstSessionSheetState extends State<PackageFirstSessionSheet> {
  List<BackendAvailabilityDay> _days = const [];
  String? _date;
  String? _slot;
  String _type = 'chat';
  bool _loadingDays = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDays();
  }

  Future<void> _loadDays() async {
    try {
      final days = await widget.apiClient.getDoctorAvailability(
        accessToken: widget.accessToken,
        userId: widget.professionalId,
      );
      if (!mounted) return;
      final filtered = days.where((d) => d.bookable).toList(growable: false);
      setState(() {
        _days = filtered;
        _loadingDays = false;
        _date = filtered.isEmpty ? null : filtered.first.date;
        _slot = null;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDays = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 12,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Pilih sesi pertama',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 17)),
            const SizedBox(height: 4),
            Text(
              'Sesi ini langsung terjadwal setelah pembayaran berhasil. Sisa 3 sesi dijadwalkan dari My Care.',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                ChoiceChip(
                  label: const Text('Chat'),
                  selected: _type == 'chat',
                  onSelected: (_) => setState(() => _type = 'chat'),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Video'),
                  selected: _type == 'video',
                  onSelected: (_) => setState(() => _type = 'video'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loadingDays)
              const Center(child: CircularProgressIndicator())
            else if (_days.isEmpty)
              const Text(
                  'Profesional belum membuka slot. Minta profesional mengatur jadwal dulu.')
            else
              SizedBox(
                height: 78,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: <Widget>[
                    for (final d in _days)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(_shortDay(d.date)),
                          selected: _date == d.date,
                          onSelected: (_) => setState(() {
                            _date = d.date;
                            _slot = null;
                          }),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            if (_date != null)
              _FirstSessionSlots(
                apiClient: widget.apiClient,
                accessToken: widget.accessToken,
                professionalId: widget.professionalId,
                date: _date!,
                selected: _slot,
                onSelect: (t) => setState(() => _slot = t),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: const TextStyle(
                      color: MalvaColors.danger, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 14),
            FilledButton(
              onPressed: (_date == null || _slot == null)
                  ? null
                  : () => Navigator.pop(context, '${_date}T$_slot|$_type'),
              child: const Text('Lanjut ke Pembayaran'),
            ),
          ],
        ),
      ),
    );
  }

  static String _shortDay(String yyyyMmDd) {
    final d = DateTime.tryParse(yyyyMmDd);
    if (d == null) return yyyyMmDd;
    const days = ['Sen', 'Sel', 'Rab', 'Kam', 'Jum', 'Sab', 'Min'];
    return '${days[d.weekday - 1]} ${d.day}/${d.month}';
  }
}

/// Item slot bebas pada hari terpilih (dipakai ulang di sheet ini).
class _FirstSessionSlots extends StatefulWidget {
  const _FirstSessionSlots({
    required this.apiClient,
    required this.accessToken,
    required this.professionalId,
    required this.date,
    required this.selected,
    required this.onSelect,
  });

  final MalvaApiClient apiClient;
  final String accessToken;
  final String professionalId;
  final String date;
  final String? selected;
  final ValueChanged<String> onSelect;

  @override
  State<_FirstSessionSlots> createState() => _FirstSessionSlotsState();
}

class _FirstSessionSlotsState extends State<_FirstSessionSlots> {
  List<BackendDoctorSlot> _slots = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _FirstSessionSlots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.date != widget.date) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final slots = await widget.apiClient.getDoctorAvailableSlots(
        accessToken: widget.accessToken,
        userId: widget.professionalId,
        date: widget.date,
      );
      if (!mounted) return;
      setState(() {
        _slots = slots;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Text(_error!,
          style: const TextStyle(
              color: MalvaColors.danger, fontWeight: FontWeight.w700));
    }
    final free = _slots.where((s) => s.available).toList(growable: false);
    if (free.isEmpty) {
      return Text('Slot hari ini penuh. Pilih hari lain.',
          style:
              TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant));
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final slot in free)
          ChoiceChip(
            label: Text(slot.time),
            selected: widget.selected == slot.time,
            onSelected: (_) => widget.onSelect(slot.time),
          ),
      ],
    );
  }
}

/// Kartu sesi dalam layar paket (upcoming + riwayat).
class _PackageSessionCard extends StatelessWidget {
  const _PackageSessionCard({
    required this.session,
    this.past = false,
    this.onOpenChat,
    this.onReschedule,
    this.onCancel,
    this.onRequestRefund,
  });

  final BackendCareSession session;
  final bool past;
  final VoidCallback? onOpenChat;
  final VoidCallback? onReschedule;
  final VoidCallback? onCancel;
  final VoidCallback? onRequestRefund;

  @override
  Widget build(BuildContext context) {
    final at = session.scheduledDateTime?.toLocal();
    final dateLabel = at == null
        ? '-'
        : '${at.day}/${at.month}/${at.year} ${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final statusColor = switch (session.status) {
      'scheduled' => MalvaColors.seed,
      'completed' => MalvaColors.mint,
      'no_show' => MalvaColors.danger,
      'cancelled_by_professional' => MalvaColors.amber,
      _ => Theme.of(context).colorScheme.onSurfaceVariant,
    };
    final statusLabel = switch (session.status) {
      'scheduled' => 'Terjadwal',
      'completed' => 'Selesai',
      'no_show' => 'Tidak hadir (hangus)',
      'cancelled_by_professional' => 'Dibatalkan profesional (kredit kembali)',
      'cancelled_by_patient' => 'Dibatalkan',
      _ => session.status,
    };
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: MalvaColors.seed.withValues(alpha: 0.12),
                child: Icon(
                    session.isVideo
                        ? Icons.videocam_rounded
                        : Icons.chat_bubble_rounded,
                    color: MalvaColors.seed),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${session.isVideo ? 'Video' : 'Chat'} • ${session.durationMinutes} mnt',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    Text(
                      dateLabel,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              StatusPill(label: statusLabel, color: statusColor),
            ],
          ),
          if (!past) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onOpenChat,
                    style: compactFilledButtonStyle,
                    icon: const Icon(Icons.chat_bubble_rounded, size: 16),
                    label: const Text('Chat'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onReschedule,
                    child: const Text('Reschedule'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: onCancel,
                    child: const Text('Batal'),
                  ),
                ),
              ],
            ),
          ],
          if (past && session.cancelledByProfessional) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onReschedule,
                    icon: const Icon(Icons.edit_calendar_rounded, size: 16),
                    label: const Text('Reschedule'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onRequestRefund,
                    style: compactFilledButtonStyle,
                    icon: const Icon(Icons.currency_exchange_rounded, size: 16),
                    label: const Text('Minta refund'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
