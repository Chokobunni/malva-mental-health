import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../platform/platform_providers.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../services/medication_reminder_service.dart';
import '../theme.dart';
import '../time/wib.dart';
import '../services/medication_adherence.dart';
import '../services/server_clock.dart';
import '../widgets/malva_components.dart';
import 'medication_history_screen.dart';
import 'portal/prescription_wizard_screen.dart';

class MedicationScreen extends ConsumerStatefulWidget {
  const MedicationScreen({
    super.key,
    this.session,
    this.apiClient,
    this.medicationReminderService,
    this.embedded = false,
  });

  /// true = tampil tanpa Scaffold sendiri (di dalam tab Mood/Med Check-in).
  final bool embedded;

  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final MedicationReminderService? medicationReminderService;

  /// Format waktu log untuk riwayat: `dd/MM/yyyy HH:mm` dalam WIB.
  ///
  /// `takenAt` dari server berupa instant; tanpa `toWib()` riwayat
  /// menampilkan jam instant mentah (mundur 7 jam / tanggal sebelumnya).
  static String formatLogTime(DateTime dt) => formatWibDateTime(dt);

  @override
  ConsumerState<MedicationScreen> createState() => _MedicationScreenState();
}

class _MedicationScreenState extends ConsumerState<MedicationScreen>
    with WidgetsBindingObserver {
  /// Status izin notifikasi: null = belum selesai diperiksa.
  bool? _notificationsEnabled;
  bool _historyAccountInvalid = false;
  bool _showStreak = false;

  /// Sedang memeriksa/meminta izin (tombol dinonaktifkan sementara).
  bool _isCheckingPermission = false;

  /// Guard agar satu dosis tidak tercatat dua kali karena tap ganda.
  final Set<String> _pendingLogs = {};
  final Map<String, DateTime> _lastLogAt = {};
  final Map<String, MedicationLog> _unsavedLogs = {};
  Timer? _cooldownTimer;

  String? _owner(AuthSession? session) => session == null
      ? null
      : '${session.role.name}|${session.backendUserId ?? session.identifier}';
  AuthSession? get _session {
    if (_historyAccountInvalid) return null;
    final active = ref.read(authStateProvider).session;
    if (active == null) return widget.session;
    if (widget.session != null && _owner(active) != _owner(widget.session))
      return null;
    return active;
  }

  MalvaApiClient? get _apiClient => widget.apiClient;
  MedicationReminderService? get _reminderService =>
      widget.medicationReminderService;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _cooldownTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
    // Ditunda ke post-frame: jangan menyentuh platform channel saat build
    // pertama (dan aman untuk widget test).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_refreshPermissionStatus());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _session == null) return;
    unawaited(_refreshPermissionStatus());
    unawaited(_refreshMedications());
  }

  Future<void> _refreshMedications() async {
    final session = _session;
    final token = session?.accessToken;
    final api = _apiClient;
    if (api == null || token == null || token.isEmpty) return;
    final store = ref.read(malvaStoreProvider.notifier);
    await Future.wait([
      store.loadMedications(api, token),
      store.loadMedicationLogs(api, token)
    ]);
  }

  void _openHistory() {
    if (_historyAccountInvalid || _session == null) return;
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => MedicationHistoryScreen(
                session: _session, apiClient: _apiClient)));
  }

  /// Periksa izin notifikasi dan minta bila belum aktif, lalu simpan statusnya.
  Future<void> _refreshPermissionStatus() async {
    final service = _reminderService;
    if (service == null) {
      if (mounted) setState(() => _notificationsEnabled = false);
      return;
    }
    if (mounted) setState(() => _isCheckingPermission = true);
    var enabled = false;
    try {
      enabled = await service.ensurePermissions();
    } on Object {
      enabled = false;
    }
    if (!mounted) return;
    setState(() {
      _notificationsEnabled = enabled;
      _isCheckingPermission = false;
    });
  }

  /// Kirim notifikasi uji agar pasien bisa memverifikasi pengingat berfungsi.
  Future<void> _sendTestNotification(BuildContext context) async {
    final service = _reminderService;
    if (service == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Layanan pengingat belum siap.')),
      );
      return;
    }
    try {
      await service.showTestNotification();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Notifikasi uji dikirim. Bila tidak muncul, aktifkan izin '
                  'notifikasi untuk Malva di Pengaturan perangkat.'),
          backgroundColor: MalvaColors.mint,
        ),
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal mengirim notifikasi uji: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateProvider, (previous, next) {
      if (previous?.session != null &&
          _owner(previous?.session) != _owner(next.session)) {
        setState(() => _historyAccountInvalid = true);
      }
    });
    final storeState = ref.watch(malvaStoreProvider);
    final store = ref.read(malvaStoreProvider.notifier);
    final now = ServerClock.now();
    final today = medicationDay(now);
    final weekStart = today.subtract(const Duration(days: 6));
    final lastTaken = <String, DateTime>{};
    var historyStart = weekStart;
    for (final log in storeState.medicationLogs) {
      if (log.takenAt.isAfter(now)) continue;
      if (log.takenAt.isBefore(historyStart))
        historyStart = medicationDay(log.takenAt);
      final last = lastTaken[log.medicationId];
      if (normalizedMedicationStatus(log.status) == 'taken' &&
          (last == null || log.takenAt.isAfter(last))) {
        lastTaken[log.medicationId] = log.takenAt;
      }
    }
    final weekly = MedicationAdherence.calculate(
        medications: storeState.medications,
        logs: storeState.medicationLogs,
        start: weekStart,
        end: now);
    final longTerm = historyStart == weekStart
        ? weekly
        : MedicationAdherence.calculate(
            medications: storeState.medications,
            logs: storeState.medicationLogs,
            start: historyStart,
            end: now);
    final takenToday = storeState.medications
        .where((med) => storeState.medicationLogs.any((log) =>
            log.medicationId == med.id &&
            medicationDay(log.takenAt) == today &&
            !log.takenAt.isAfter(now) &&
            normalizedMedicationStatus(log.status) == 'taken'))
        .length;
    final content = RefreshIndicator(
      onRefresh: () async {
        final startedOwner = _owner(_session);
        final startedAuthOwner = _owner(ref.read(authStateProvider).session);
        final accessToken = _session?.accessToken;
        final api = _apiClient;
        if (api == null || accessToken == null || accessToken.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          return;
        }
        if (_owner(_session) != startedOwner ||
            _owner(ref.read(authStateProvider).session) != startedAuthOwner) {
          return;
        }
        await Future.wait([
          store.loadMedications(api, accessToken),
          store.loadMedicationLogs(api, accessToken),
        ]);
      },
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (!widget.embedded)
            const GradientHeader(
              title: 'Obat',
              subtitle: 'Pengingat, stok, dan kepatuhan',
              leading:
                  Icon(Icons.medication_rounded, color: Colors.white, size: 34),
            ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [Color(0xff53236c), Color(0xff783298)]),
                      borderRadius: BorderRadius.circular(22)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('TARGET HARIAN',
                          style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                              letterSpacing: .4)),
                      const SizedBox(height: 12),
                      Row(children: [
                        const Expanded(
                            child: Text('Kepatuhan hari ini',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w900))),
                        Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(18)),
                            child: Column(children: [
                              Text('${storeState.adherencePercent}%',
                                  style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white)),
                              Text(
                                  '$takenToday/${storeState.medications.length} obat',
                                  style: const TextStyle(color: Colors.white70))
                            ])),
                      ]),
                      const SizedBox(height: 6),
                      const Text('Ketuk Minum Sekarang setelah obat diminum.',
                          style: TextStyle(color: Colors.white70)),
                      const SizedBox(height: 18),
                      LinearProgressIndicator(
                          value: storeState.adherencePercent / 100,
                          color: const Color(0xffd19de5),
                          backgroundColor: const Color(0xff48205e),
                          borderRadius: BorderRadius.circular(8),
                          minHeight: 8),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _MedicationConsistencyCard(
                  summary: weekly,
                  longTerm: longTerm,
                  medicationCount: storeState.medications.length,
                  logCount: storeState.medicationLogs
                      .where((log) =>
                          !log.takenAt.isBefore(weekStart) &&
                          !log.takenAt.isAfter(now))
                      .length,
                  lastTaken: lastTaken,
                  showStreak: _showStreak,
                  onChanged: (value) => setState(() => _showStreak = value),
                  onHistory: _historyAccountInvalid || _session == null
                      ? null
                      : _openHistory,
                ),
                const SizedBox(height: 14),
                _buildReminderStatusCard(context),
                const SizedBox(height: 22),
                if (storeState.medications.isNotEmpty) ...[
                  DecoratedBox(
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xff76229f), Color(0xff9729e7)]),
                          borderRadius: BorderRadius.circular(16)),
                      child: FilledButton.icon(
                        onPressed: () => _openMedicationForm(context),
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            minimumSize: const Size.fromHeight(50)),
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Tambah Obat'),
                      )),
                  const SizedBox(height: 14),
                ],
                const SectionLabel('Jadwal hari ini'),
                if (storeState.medications.isEmpty)
                  SoftCard(
                    child: Column(
                      children: [
                        const Image(
                            image: AssetImage(
                                'assets/reference/medication-empty.png'),
                            height: 96,
                            excludeFromSemantics: true),
                        const SizedBox(height: 12),
                        const Text(
                          'Belum ada obat',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Anda atau profesional yang terhubung dapat menambahkan obat.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () => _openMedicationForm(context),
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Tambah Obat Pertama'),
                        ),
                      ],
                    ),
                  )
                else
                  for (final med in storeState.medications) ...[
                    _MedicationCard(
                      medication: med,
                      serverReady: _looksLikeServerId(med.id),
                      busy: _pendingLogs.contains(med.id),
                      retry: _unsavedLogs.containsKey(med.id),
                      cooldown: !ref
                          .read(malvaStoreProvider.notifier)
                          .canTakeMedication(med.id),
                      onTake: _pendingLogs.contains(med.id) ||
                              (!_unsavedLogs.containsKey(med.id) &&
                                  !ref
                                      .read(malvaStoreProvider.notifier)
                                      .canTakeMedication(med.id)) ||
                              !_looksLikeServerId(med.id)
                          ? null
                          : _unsavedLogs.containsKey(med.id)
                              ? () => unawaited(_logMedication(
                                  context, med, _unsavedLogs[med.id]!.status))
                              : () => _takeMedication(context, med),
                      onEdit: () => _openMedicationForm(context, med),
                    ),
                    const SizedBox(height: 12),
                  ],
              ],
            ),
          ),
        ],
      ),
    );
    // Di web tidak ada penjadwal notifikasi OS. Tampilkan banner jujur bahwa
    // pengingat hanya berjalan di aplikasi Android — bukan tombol mati.
    final withBanner = ref.watch(capabilitiesProvider).canScheduleOsReminders
        ? content
        : Column(
            children: [
              _webReminderBanner(context),
              Expanded(child: content),
            ],
          );
    if (widget.embedded) return withBanner;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'medication_add_fab',
        onPressed: () => _openMedicationForm(context),
        child: const Icon(Icons.add_rounded),
      ),
      body: withBanner,
    );
  }

  /// Banner "pengingat hanya di aplikasi Android" (tampil di web).
  Widget _webReminderBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MalvaColors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.alarm_off_rounded, color: MalvaColors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Pengingat obat hanya berjalan di aplikasi Android Malva. '
              'Di versi web, jadwal obat tetap tersimpan namun tanpa alarm.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  /// Kartu status pengingat obat: izin aktif/tidak + uji notifikasi.
  Widget _buildReminderStatusCard(BuildContext context) {
    final enabled = _notificationsEnabled;
    final active = enabled ?? false;
    final color = enabled == null
        ? MalvaColors.seed
        : active
            ? MalvaColors.mint
            : MalvaColors.amber;
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    final compact = MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(12) > 15;
    final description = enabled == null
        ? 'Memeriksa izin notifikasi…'
        : active
            ? 'Izin notifikasi aktif — pengingat berbunyi sesuai jam minum obat.'
            : 'Izin notifikasi belum aktif — pengingat tidak akan berbunyi. Aktifkan agar tidak ada dosis yang terlewat.';
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(Icons.notifications_active_rounded, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pengingat obat',
                      style:
                          TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                    ),
                    if (!compact) ...[
                      const SizedBox(height: 2),
                      Text(
                        enabled == null
                            ? 'Memeriksa izin notifikasi…'
                            : active
                                ? 'Izin notifikasi aktif — pengingat berbunyi '
                                    'sesuai jam minum obat.'
                                : 'Izin notifikasi belum aktif — pengingat tidak '
                                    'akan berbunyi. Aktifkan agar tidak ada dosis '
                                    'yang terlewat.',
                        style: TextStyle(fontSize: 12, color: onSurfaceVariant),
                      )
                    ],
                  ],
                ),
              ),
              if (!compact) ...[
                const SizedBox(width: 8),
                StatusPill(
                  label: enabled == null
                      ? 'Memeriksa'
                      : active
                          ? 'Aktif'
                          : 'Tidak aktif',
                  color: color,
                )
              ],
            ],
          ),
          if (compact) ...[
            const SizedBox(height: 10),
            StatusPill(
                label: enabled == null
                    ? 'Memeriksa'
                    : active
                        ? 'Aktif'
                        : 'Tidak aktif',
                color: color),
            const SizedBox(height: 8),
            Text(description,
                style: TextStyle(fontSize: 12, color: onSurfaceVariant)),
          ],
          const SizedBox(height: 12),
          const Text('Pastikan volume perangkat aktif',
              style: TextStyle(color: Color(0xff8c97a3), fontSize: 12)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _isCheckingPermission
                    ? null
                    : () => _sendTestNotification(context),
                icon: const Icon(Icons.notifications_rounded, size: 18),
                label: const Text('Tes pengingat'),
              ),
              if (!active)
                FilledButton.icon(
                  onPressed:
                      _isCheckingPermission ? null : _refreshPermissionStatus,
                  icon: _isCheckingPermission
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.lock_open_rounded, size: 18),
                  label: const Text('Aktifkan izin'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _openMedicationForm(BuildContext context,
      [Medication? medication]) async {
    final session = _session;
    final value = await Navigator.of(context).push<Medication>(
      MaterialPageRoute(
        builder: (_) => EPrescriptionFormScreen(
          personal: true,
          session: session,
          initialMedication: medication,
          onDelete: medication == null
              ? null
              : () {
                  if (mounted &&
                      context.mounted &&
                      !_historyAccountInvalid &&
                      _owner(session) == _owner(_session)) {
                    _deleteMedication(context, medication);
                  }
                },
        ),
      ),
    );
    if (!mounted ||
        !context.mounted ||
        value == null ||
        _historyAccountInvalid ||
        _owner(session) != _owner(_session)) return;
    ref.read(malvaStoreProvider.notifier).upsertMedication(value);
    unawaited(_reminderService?.scheduleMedicationReminder(value));
    unawaited(_syncMedication(context, value, isNew: medication == null));
  }

  void _deleteMedication(BuildContext context, Medication medication) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Hapus ${medication.name}?'),
        content: const Text('Obat dan reminder akan dihapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              ref
                  .read(malvaStoreProvider.notifier)
                  .deleteMedication(medication.id);
              unawaited(_reminderService?.cancelReminder(medication.id));
              unawaited(_syncMedicationDeletion(context, medication));
            },
            style: compactFilledButtonStyle.copyWith(
              backgroundColor: const WidgetStatePropertyAll(MalvaColors.danger),
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  void _takeMedication(BuildContext context, Medication medication) {
    if (_pendingLogs.contains(medication.id) ||
        !_looksLikeServerId(medication.id)) return;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Colors.white,
      barrierColor: Colors.black54,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (sheet) => SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(17, 0, 17, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 3, top: 7),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Log minum obat',
                              style: TextStyle(
                                  fontSize: 25, fontWeight: FontWeight.w900)),
                          Text(medication.name,
                              style: const TextStyle(
                                  fontSize: 20,
                                  color: MalvaColors.seed,
                                  fontWeight: FontWeight.w800)),
                        ],
                      ),
                    ),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Tutup',
                    onPressed: () => Navigator.pop(sheet),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFF1E5F7),
                      foregroundColor: MalvaColors.seed,
                    ),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              for (final (status, label, description, icon, color, tint)
                  in const [
                (
                  'taken',
                  'Sudah diminum',
                  'Seluruh dosis diminum',
                  Icons.check_circle_rounded,
                  MalvaColors.mint,
                  Color(0xFFEAF9F5)
                ),
                (
                  'skipped',
                  'Dilewati',
                  'Sengaja tidak diminum',
                  Icons.skip_next_rounded,
                  MalvaColors.amber,
                  Color(0xFFFFF3E1)
                ),
                (
                  'missed',
                  'Terlewat',
                  'Terlewat tanpa sengaja',
                  Icons.access_time_rounded,
                  MalvaColors.danger,
                  Color(0xFFFCE6E6)
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    shape: RoundedRectangleBorder(
                      side: const BorderSide(color: Color(0xFFC5B1CD)),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundColor: tint,
                      foregroundColor: color,
                      child: Icon(icon, size: 29),
                    ),
                    title: Text(label,
                        style: const TextStyle(fontWeight: FontWeight.w900)),
                    subtitle: Text(description),
                    onTap: () {
                      Navigator.pop(sheet);
                      unawaited(_logMedication(context, medication, status));
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Catat dosis: potong stok lokal, kirim log ke server, lalu rekonsiliasi.
  ///
  /// Urutan ini penting. Stok lokal dipotong lebih dulu agar UI langsung
  /// benar, lalu penanda "pending" menjaga angka itu tidak ditimpa stok server
  /// yang belum terpotong. Setelah server menerima (dan memotong), penanda
  /// dihapus dan daftar obat dimuat ulang dari server sebagai sumber final.
  Future<void> _logMedication(
    BuildContext context,
    Medication medication,
    String status,
  ) async {
    if (_session == null) return;
    if (_pendingLogs.contains(medication.id)) return;
    final retry = _unsavedLogs[medication.id];
    // Debounce per obat + status: tap ganda dalam 3 detik diabaikan.
    final key = '${medication.id}|$status';
    final now = wibNow();
    final last = _lastLogAt[key];
    if (retry == null &&
        last != null &&
        now.difference(last) < const Duration(seconds: 3)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Dosis ini baru saja dicatat.')));
      return;
    }
    _lastLogAt[key] = now;
    final startedAuthOwner = _owner(ref.read(authStateProvider).session);
    final startedOwner = _owner(_session);
    setState(() => _pendingLogs.add(medication.id));

    final store = ref.read(malvaStoreProvider.notifier);
    final consumed = status == 'taken' || status == 'partial';
    if (retry == null && !store.takeMedication(medication.id, status: status)) {
      setState(() => _pendingLogs.remove(medication.id));
      return;
    }
    final local = retry ?? ref.read(malvaStoreProvider).medicationLogs.first;
    final takenAt = local.takenAt;
    final accepted =
        await _syncMedicationLog(context, medication, status, takenAt);
    if (!mounted) return;
    setState(() => _pendingLogs.remove(medication.id));
    if (_owner(ref.read(authStateProvider).session) != startedAuthOwner ||
        _owner(_session) != startedOwner) return;

    if (accepted) {
      setState(() => _unsavedLogs.remove(medication.id));
      unawaited(_reloadMedications());
      // Muat ulang log dari server agar entri optimistis digantikan versi
      // server (id/timestamp otoritatif) dan riwayat tidak dobel.
      final accessToken = _session?.accessToken;
      if (accessToken != null && accessToken.isNotEmpty) {
        unawaited(store.loadMedicationLogs(_apiClient, accessToken));
      }
    } else {
      // Gagal kirim: MASUKKAN ke antrean offline. Sebelumnya hanya SnackBar
      // ditampilkan, sehingga log hilang permanen saat app ditutup.
      //
      // `medicationId` hanya dikirim bila sudah berupa id server: backend
      // menerima id kosong (hanya tidak memotong stok), dan lebih baik log
      // tercatat tanpa pemotongan stok daripada hilang sama sekali.
      try {
        await ref.read(offlineSyncServiceProvider).enqueueMedicationLog(
              medicationId:
                  _looksLikeServerId(medication.id) ? medication.id : '',
              medicationName: medication.name,
              status: status,
              takenAt: takenAt,
            );
      } on Object {
        if (context.mounted && _owner(_session) == startedOwner) {
          setState(() => _unsavedLogs[medication.id] = local);
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content:
                  Text('Antrean obat belum tersimpan. Coba sinkronkan lagi.')));
        }
        return;
      }
      if (!context.mounted ||
          _owner(ref.read(authStateProvider).session) != startedAuthOwner ||
          _owner(_session) != startedOwner) return;
      setState(() => _unsavedLogs.remove(medication.id));
      // Penanda pending DIBIARKAN (tidak confirmDose) supaya stok di layar
      // tetap terpotong dan tidak naik kembali saat refresh.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Log obat masuk antrean offline dan akan dikirim otomatis saat '
              'koneksi kembali.'),
          backgroundColor: MalvaColors.amber,
        ),
      );
    }

    final updated = ref
        .read(malvaStoreProvider)
        .medications
        .where((m) => m.id == medication.id)
        .firstOrNull;
    if (updated != null && updated.needsRefill && consumed) {
      await _reminderService?.showLowStockNotification(updated);
    }
  }

  /// Muat ulang daftar obat dari server (best effort, tanpa menggagalkan UI).
  Future<void> _reloadMedications() async {
    final accessToken = _session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) return;
    await ref
        .read(malvaStoreProvider.notifier)
        .loadMedications(_apiClient, accessToken);
  }

  /// Id dari server adalah UUID (36 karakter). Obat yang ditambahkan sebelum
  /// sempat sync memakai id sementara `med_<timestamp>`, sehingga tidak boleh
  /// dikirim ke endpoint PUT/DELETE.
  static bool _looksLikeServerId(String id) =>
      id.length == 36 && RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id);

  Future<void> _syncMedication(
    BuildContext context,
    Medication medication, {
    required bool isNew,
  }) async {
    final owner = _session;
    final accessToken = owner?.accessToken;
    final api = _apiClient;
    if (api == null || accessToken == null || accessToken.isEmpty) {
      return;
    }
    try {
      final reminder = medication.reminders.firstOrNull;
      if (!isNew && _looksLikeServerId(medication.id)) {
        // Jalur ubah: PUT ke id yang sudah dikenal server. Sebelumnya "edit"
        // selalu dikirim sebagai POST, dan UpsertMedication di server adalah
        // INSERT murni, sehingga obat yang sama menjadi baris duplikat.
        await api.updateMedication(
          accessToken: accessToken,
          medicationId: medication.id,
          name: medication.name,
          dosage: medication.dosage,
          form: medication.form,
          reminderTime: reminder?.label ?? '',
          relationToMeal: reminder?.relationToMeal ?? '',
          currentStock: medication.currentStock,
          alertBelow: medication.alertBelow,
          source: medication.source,
          schedule: medication.schedule,
        );
        return;
      }
      final created = await api.createMedication(
        accessToken: accessToken,
        name: medication.name,
        dosage: medication.dosage,
        form: medication.form,
        reminderTime: reminder?.label ?? '',
        relationToMeal: reminder?.relationToMeal ?? '',
        currentStock: medication.currentStock,
        alertBelow: medication.alertBelow,
        source: medication.source,
        schedule: medication.schedule,
      );
      // Simpan id dari server agar edit berikutnya memakai PUT, bukan POST
      // yang akan melahirkan baris baru lagi.
      if (!mounted || _owner(owner) != _owner(_session)) return;
      ref
          .read(malvaStoreProvider.notifier)
          .rebindMedication(medication.id, medication.copyWith(id: created.id));
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Obat tersimpan lokal, sync backend gagal: $error'),
        ),
      );
    }
  }

  /// Hapus obat di server.
  ///
  /// Sebelumnya penghapusan hanya terjadi di state lokal, sehingga obat
  /// muncul kembali begitu daftar dimuat ulang dari backend.
  Future<void> _syncMedicationDeletion(
    BuildContext context,
    Medication medication,
  ) async {
    final accessToken = _session?.accessToken;
    final api = _apiClient;
    if (api == null || accessToken == null || accessToken.isEmpty) {
      return;
    }
    if (!_looksLikeServerId(medication.id)) return;
    try {
      await api.deleteMedication(
        accessToken: accessToken,
        medicationId: medication.id,
      );
    } on Object catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Obat terhapus lokal, sync backend gagal: $error'),
        ),
      );
    }
  }

  /// Kirim log minum obat ke server.
  ///
  /// Penerimaan server adalah final, termasuk obat lokal tanpa id server;
  /// jangan antrekan lagi log yang sudah diterima karena akan menduplikasi dosis.
  Future<bool> _syncMedicationLog(
    BuildContext context,
    Medication medication,
    String status,
    DateTime takenAt,
  ) async {
    final accessToken = _session?.accessToken;
    final api = _apiClient;
    if (api == null || accessToken == null || accessToken.isEmpty) return false;
    final serverId = _looksLikeServerId(medication.id) ? medication.id : null;
    try {
      final startedOwner = _owner(_session);
      final startedAuthOwner = _owner(ref.read(authStateProvider).session);
      final accepted = await api.createMedicationLog(
        accessToken: accessToken,
        medicationId: serverId,
        medicationName: medication.name,
        status: status,
        // Waktu minum memakai acuan server (bukan jam perangkat) agar dosis
        // tidak tercatat di hari yang salah bila jam perangkat meleset.
        takenAt: takenAt,
      );
      if (mounted &&
          _owner(_session) == startedOwner &&
          _owner(ref.read(authStateProvider).session) == startedAuthOwner) {
        ref
            .read(malvaStoreProvider.notifier)
            .confirmMedicationLog(medication.id, takenAt, accepted);
      }
      return true;
    } on Object {
      return false;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cooldownTimer?.cancel();
    super.dispose();
  }
}

class _MedicationConsistencyCard extends StatelessWidget {
  const _MedicationConsistencyCard({
    required this.summary,
    required this.longTerm,
    required this.medicationCount,
    required this.logCount,
    required this.lastTaken,
    required this.showStreak,
    required this.onChanged,
    this.onHistory,
  });

  final MedicationAdherence summary;
  final MedicationAdherence longTerm;
  final int medicationCount;
  final int logCount;
  final Map<String, DateTime> lastTaken;
  final bool showStreak;
  final ValueChanged<bool> onChanged;
  final VoidCallback? onHistory;

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xff14877e);
    final streak = longTerm.streak;
    final progress =
        showStreak ? (streak > 0 ? 1.0 : 0.0) : summary.percent / 100;
    final title = showStreak ? 'Runtutan kepatuhan' : 'Kepatuhan 7 Hari';
    final latestMiss = (showStreak ? longTerm : summary).misses.lastOrNull;
    final last = latestMiss == null ? null : lastTaken[latestMiss.medicationId];
    final firstMiss = latestMiss == null
        ? null
        : longTerm.misses.firstWhere(
            (miss) =>
                miss.medicationId == latestMiss.medicationId &&
                (last == null || miss.takenAt.isAfter(last)),
            orElse: () => latestMiss);
    final elapsed = last == null
        ? null
        : medicationDay(longTerm.end).difference(medicationDay(last)).inDays;
    final lapse = latestMiss == null || (showStreak && streak > 0)
        ? null
        : showStreak
            ? '${latestMiss.medicationName} terlewat sejak ${_shortDate(firstMiss!.takenAt)}'
            : last != null && latestMiss.takenAt.isAfter(last)
                ? '${latestMiss.medicationName} tidak tercatat diminum sejak ${_shortDate(last)} ($elapsed hari)'
                : '${latestMiss.medicationName} terlewat pada ${_shortDate(latestMiss.takenAt)}';
    return SoftCard(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                    color: const Color(0xffedf9f7),
                    borderRadius: BorderRadius.circular(20)),
                child: const Text('Ringkasan Konsistensi',
                    style: TextStyle(
                        color: teal,
                        fontWeight: FontWeight.w800,
                        fontSize: 12)),
              ),
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(
                  textStyle: WidgetStatePropertyAll(TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
                  visualDensity: VisualDensity.compact,
                  padding: WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
                segments: const [
                  ButtonSegment(value: false, label: Text('7 Hari')),
                  ButtonSegment(value: true, label: Text('Runtutan')),
                ],
                selected: {showStreak},
                onSelectionChanged: (value) => onChanged(value.single),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (showStreak)
            Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: const Color(0xfffffaf1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xfff5e8ce))),
                child: Row(children: [
                  Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xffffab00), Color(0xfff57e0b)]),
                          borderRadius: BorderRadius.circular(20)),
                      child: const Icon(Icons.local_fire_department_outlined,
                          color: Colors.white, size: 30)),
                  const SizedBox(width: 14),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('$streak Hari Berturut-turut',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 17)),
                        const SizedBox(height: 5),
                        Text('Rekor terlama: ${longTerm.longestStreak} hari',
                            style: const TextStyle(color: Color(0xff77518d))),
                        if (lapse != null)
                          Text(lapse,
                              style: const TextStyle(
                                  color: Color(0xff991f40), fontSize: 12))
                      ])),
                ]))
          else
            Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: const Color(0xfff8f9fc),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xfff0f1f4))),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 75,
                      height: 75,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                              child: CircularProgressIndicator(
                            value: progress,
                            color: showStreak ? teal : const Color(0xffea950c),
                            backgroundColor: const Color(0xffe6e8eb),
                            strokeWidth: 7,
                            strokeCap: StrokeCap.round,
                            semanticsLabel: title,
                          )),
                          Padding(
                            padding: const EdgeInsets.all(9),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                      showStreak
                                          ? '$streak hari'
                                          : '${summary.percent}%',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 17)),
                                  Text(showStreak ? 'berturut' : '7 hari',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 5,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16)),
                              Tooltip(
                                message: showStreak
                                    ? 'Jumlah hari terjadwal berturut-turut dengan seluruh dosis tercatat diminum.'
                                    : 'Dosis yang diminum dibandingkan dengan seluruh dosis yang sudah jatuh tempo dan catatan dalam tujuh hari WIB.',
                                child: const Icon(Icons.info_outline_rounded,
                                    size: 15),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Wrap(spacing: 8, runSpacing: 6, children: [
                            Text('$medicationCount obat dipantau',
                                style: Theme.of(context).textTheme.bodySmall),
                            Text('$logCount catatan',
                                style: Theme.of(context).textTheme.bodySmall),
                          ]),
                          if (lapse != null) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 6),
                              decoration: BoxDecoration(
                                  color: showStreak
                                      ? const Color(0xffffeff1)
                                      : const Color(0xfffff7e4),
                                  borderRadius: BorderRadius.circular(12)),
                              child: Text(lapse,
                                  style: TextStyle(
                                      color: showStreak
                                          ? const Color(0xff991f40)
                                          : const Color(0xff834413))),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                )),
          const Divider(height: 28, color: Color(0xfff0f1f4)),
          Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                const Text('Catatan konsumsi & kepatuhan',
                    style: TextStyle(color: Color(0xff8c97a3), fontSize: 12)),
                TextButton.icon(
                    key: const Key('open-medication-history'),
                    onPressed: onHistory,
                    icon: const Icon(Icons.history, size: 18),
                    label: const Text('Lihat riwayat obat')),
              ]),
        ],
      ),
    );
  }

  static String _shortDate(DateTime value) {
    final at = toWib(value);
    const months = [
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
      'Des'
    ];
    return '${at.day} ${months[at.month - 1]}';
  }
}

class _MedicationCard extends StatelessWidget {
  const _MedicationCard({
    required this.medication,
    required this.onTake,
    required this.onEdit,
    this.busy = false,
    this.serverReady = true,
    this.cooldown = false,
    this.retry = false,
  });

  final Medication medication;
  final VoidCallback? onTake;
  final VoidCallback onEdit;
  final bool busy;
  final bool serverReady;
  final bool cooldown;
  final bool retry;

  @override
  Widget build(BuildContext context) {
    final firstReminder = medication.reminders.firstOrNull;
    return SoftCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: medication.needsRefill
                    ? MalvaColors.danger.withValues(alpha: 0.1)
                    : MalvaColors.mint.withValues(alpha: 0.1),
                child: Icon(
                  medication.needsRefill
                      ? Icons.priority_high_rounded
                      : Icons.medication_liquid_rounded,
                  color: medication.needsRefill
                      ? MalvaColors.danger
                      : MalvaColors.mint,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(medication.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16)),
                    Text(
                        [
                          medication.dosage,
                          medication.form,
                          if (firstReminder?.relationToMeal.isNotEmpty ?? false)
                            firstReminder!.relationToMeal,
                        ].join(' • '),
                        style: const TextStyle(
                            color: Color(0xff788590), fontSize: 13)),
                  ],
                ),
              ),
              IconButton(
                  onPressed: onEdit, icon: const Icon(Icons.edit_rounded)),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatusPill(
                label: medication.schedule?.label ??
                    (firstReminder?.label ?? 'Belum diatur'),
                color: MalvaColors.seed,
                icon: Icons.schedule_rounded,
              ),
              StatusPill(
                label: '${medication.currentStock} stok',
                color: medication.needsRefill
                    ? MalvaColors.danger
                    : MalvaColors.mint,
                icon: Icons.inventory_2_rounded,
              ),
              StatusPill(
                label: medication.sourceLabel,
                color: MalvaColors.amber,
                icon: Icons.verified_user_rounded,
              ),
            ],
          ),
          const Divider(height: 28, color: Color(0xfff0f1f4)),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                medication.lastTakenLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              FilledButton.icon(
                onPressed: onTake,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                icon: busy
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.check_rounded),
                label: Text(busy
                    ? 'Menyimpan…'
                    : !serverReady
                        ? 'Menunggu sync'
                        : retry
                            ? 'Coba simpan'
                            : cooldown
                                ? 'Tunggu 24 jam'
                                : 'Minum Sekarang'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class MedicationFormSheet extends StatefulWidget {
  const MedicationFormSheet({
    super.key,
    required this.onSave,
    this.initial,
    this.onDelete,
  });

  final Medication? initial;
  final ValueChanged<Medication> onSave;
  final VoidCallback? onDelete;

  @override
  State<MedicationFormSheet> createState() => _MedicationFormSheetState();
}

class _MedicationFormSheetState extends State<MedicationFormSheet> {
  late final TextEditingController _name;
  late final TextEditingController _dosage;
  late final TextEditingController _form;
  late final TextEditingController _stock;
  late final TextEditingController _alertBelow;
  TimeOfDay? _time;
  String _relation = 'Setelah makan';

  @override
  void initState() {
    super.initState();
    final med = widget.initial;
    _name = TextEditingController(text: med?.name ?? '');
    _dosage = TextEditingController(text: med?.dosage ?? '');
    _form = TextEditingController(text: med?.form ?? 'Tablet');
    _stock = TextEditingController(text: (med?.currentStock ?? 30).toString());
    _alertBelow =
        TextEditingController(text: (med?.alertBelow ?? 3).toString());
    final reminder = med?.reminders.firstOrNull;
    _time = med == null ? const TimeOfDay(hour: 8, minute: 0) : reminder?.time;
    _relation = reminder?.relationToMeal ?? 'Setelah makan';
    if (!['Sebelum makan', 'Setelah makan', 'Sebelum tidur']
        .contains(_relation)) {
      _relation = 'Setelah makan';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _dosage.dispose();
    _form.dispose();
    _stock.dispose();
    _alertBelow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, bottomInset + 18),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.initial == null ? 'Tambah Obat' : 'Edit Obat',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 16),
            TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nama obat')),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                    child: TextField(
                        controller: _dosage,
                        decoration:
                            const InputDecoration(labelText: 'Dosage'))),
                const SizedBox(width: 10),
                Expanded(
                    child: TextField(
                        controller: _form,
                        decoration: const InputDecoration(labelText: 'Form'))),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: widget.initial?.schedule == null ? _pickTime : null,
              icon: const Icon(Icons.schedule_rounded),
              label: Text(widget.initial?.schedule?.label ??
                  (_time == null
                      ? 'Reminder belum diatur'
                      : 'Reminder ${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}')),
            ),
            DropdownButtonFormField<String>(
              initialValue: _relation,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Relasi makan'),
              items: const [
                DropdownMenuItem(
                    value: 'Sebelum makan', child: Text('Sebelum makan')),
                DropdownMenuItem(
                    value: 'Setelah makan', child: Text('Setelah makan')),
                DropdownMenuItem(
                    value: 'Sebelum tidur', child: Text('Sebelum tidur')),
              ],
              onChanged: (value) =>
                  setState(() => _relation = value ?? _relation),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _stock,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Saat Ini stock'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _alertBelow,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Alert below'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(onPressed: _save, child: const Text('Simpan')),
            if (widget.onDelete != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: widget.onDelete,
                icon:
                    const Icon(Icons.delete_rounded, color: MalvaColors.danger),
                label: const Text('Hapus Obat',
                    style: TextStyle(color: MalvaColors.danger)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
        context: context,
        initialTime: _time ?? const TimeOfDay(hour: 8, minute: 0));
    if (picked != null && mounted) setState(() => _time = picked);
  }

  void _save() {
    final id = widget.initial?.id ?? 'med_${wibNow().millisecondsSinceEpoch}';
    widget.onSave(
      Medication(
        id: id,
        name: _name.text.trim().isEmpty ? 'Obat' : _name.text.trim(),
        dosage: _dosage.text.trim().isEmpty ? '0 mg' : _dosage.text.trim(),
        form: _form.text.trim().isEmpty ? 'Tablet' : _form.text.trim(),
        reminders: widget.initial?.schedule?.reminders(_relation) ??
            [
              if (_time != null)
                MedicationReminder(time: _time!, relationToMeal: _relation),
            ],
        currentStock: int.tryParse(_stock.text.trim()) ?? 0,
        alertBelow: int.tryParse(_alertBelow.text.trim()) ?? 3,
        schedule: widget.initial?.schedule,
        source: widget.initial?.source ?? 'Pasien',
      ),
    );
  }
}
