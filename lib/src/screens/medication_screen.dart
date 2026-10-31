import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../services/medication_reminder_service.dart';
import '../services/server_clock.dart';
import '../theme.dart';
import '../time/wib.dart';
import '../widgets/home_personalization.dart';
import '../widgets/malva_components.dart';

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

class _MedicationScreenState extends ConsumerState<MedicationScreen> {
  /// Status izin notifikasi: null = belum selesai diperiksa.
  bool? _notificationsEnabled;

  /// Sedang memeriksa/meminta izin (tombol dinonaktifkan sementara).
  bool _isCheckingPermission = false;

  /// Guard agar satu dosis tidak tercatat dua kali karena tap ganda.
  bool _isLogging = false;

  /// Kunci debounce terakhir ("<id>|<status>") dan waktunya.
  String? _lastLogKey;
  DateTime? _lastLogAt;

  AuthSession? get _session => widget.session;
  MalvaApiClient? get _apiClient => widget.apiClient;
  MedicationReminderService? get _reminderService =>
      widget.medicationReminderService;

  @override
  void initState() {
    super.initState();
    // Ditunda ke post-frame: jangan menyentuh platform channel saat build
    // pertama (dan aman untuk widget test).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_refreshPermissionStatus());
    });
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
    final storeState = ref.watch(malvaStoreProvider);
    final store = ref.read(malvaStoreProvider.notifier);
    final content = RefreshIndicator(
      onRefresh: () async {
        final accessToken = _session?.accessToken;
        final api = _apiClient;
        if (api == null || accessToken == null || accessToken.isEmpty) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
          return;
        }
        try {
          final backendMeds = await api.listMedications(
            accessToken: accessToken,
          );
          final meds = backendMeds
              .map(
                (b) => Medication(
                  id: b.id,
                  name: b.name,
                  dosage: b.dosage,
                  form: b.form,
                  reminders: [
                    MedicationReminder(
                      time: _parseReminderTime(b.reminderTime),
                      relationToMeal: 'Setelah makan',
                    ),
                  ],
                  currentStock: b.currentStock,
                  alertBelow: b.alertBelow,
                  // Pakai sumber asli dari server ('Pasien'/'Profesional')
                  // agar badge tidak salah label untuk obat yang ditambahkan
                  // pasien sendiri. Fallback ke 'Profesional' bila kosong.
                  source: b.source.isEmpty ? 'Profesional' : b.source,
                ),
              )
              .toList();
          // replaceMedications() ikut mengurangkan dosis yang masih pending,
          // sehingga stok yang belum terpotong di server tidak menaikkan
          // angka di layar.
          store.replaceMedications(meds);
        } on Object catch (_) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      },
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          if (!widget.embedded)
            const GradientHeader(
              title: 'Medication',
              subtitle: 'Reminder, stok, dan adherence',
              leading:
                  Icon(Icons.medication_rounded, color: Colors.white, size: 34),
            ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SoftCard(
                  color: MalvaColors.plum,
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Kepatuhan Hari Ini',
                              style: TextStyle(
                                  color: Colors.white70,
                                  fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '${storeState.adherencePercent}% hari ini',
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineSmall
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            const Text('Tap Take Now setelah obat diminum.',
                                style: TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ),
                      CircleAvatar(
                        radius: 34,
                        backgroundColor: Colors.white,
                        child: Text(
                          '${storeState.adherencePercent}%',
                          style: const TextStyle(
                              color: MalvaColors.plum,
                              fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                SoftCard(
                  child: Row(
                    children: [
                      StreakRing(percent: storeState.adherencePercent),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              storeState.adherencePercent >= 100
                                  ? 'Perfect! Adherence 100%'
                                  : 'Adherence streak',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${storeState.medications.length} obat dipantau • ${storeState.medicationLogs.length} log tercatat',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _buildReminderStatusCard(context),
                const SizedBox(height: 22),
                const SectionLabel('Jadwal hari ini'),
                if (storeState.medications.isEmpty)
                  SoftCard(
                    child: Column(
                      children: [
                        const Icon(Icons.medication_rounded,
                            size: 48, color: MalvaColors.seed),
                        const SizedBox(height: 12),
                        const Text(
                          'Belum ada obat',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Tambahkan obat pertama Anda untuk mulai melacak.',
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
                      onTake: () => _takeMedication(context, med),
                      onEdit: () => _openMedicationForm(context, med),
                    ),
                    const SizedBox(height: 12),
                  ],
                const SizedBox(height: 70),
                const SizedBox(height: 22),
                const SectionLabel('Riwayat Minum Obat'),
                if (storeState.medicationLogs.isEmpty)
                  const SoftCard(
                    child: Text('Belum ada riwayat minum obat.'),
                  )
                else
                  for (final log in storeState.medicationLogs.take(10))
                    SoftCard(
                      child: Row(
                        children: [
                          Icon(
                            _logIcon(log.status),
                            color: _logColor(log.status),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  log.medicationName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  '${log.status.toUpperCase()} — ${MedicationScreen.formatLogTime(log.takenAt)}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
    if (widget.embedded) return content;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        heroTag: 'medication_add_fab',
        onPressed: () => _openMedicationForm(context),
        child: const Icon(Icons.add_rounded),
      ),
      body: content,
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
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(
                label: enabled == null
                    ? 'Memeriksa'
                    : active
                        ? 'Aktif'
                        : 'Tidak aktif',
                color: color,
              ),
            ],
          ),
          const SizedBox(height: 12),
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

  /// Ikon status log obat. 'partial' (sebagian diminum) punya ikon sendiri;
  /// sebelumnya status ini jatuh ke ikon "dibatalkan" seperti missed.
  static IconData _logIcon(String status) => switch (status) {
        'taken' => Icons.check_circle_rounded,
        'partial' => Icons.hourglass_bottom_rounded,
        'skipped' => Icons.skip_next_rounded,
        _ => Icons.cancel_rounded,
      };

  static Color _logColor(String status) => switch (status) {
        'taken' => MalvaColors.mint,
        'partial' => MalvaColors.orchid,
        'skipped' => MalvaColors.amber,
        _ => MalvaColors.danger,
      };

  void _openMedicationForm(BuildContext context, [Medication? medication]) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => MedicationFormSheet(
        initial: medication,
        onSave: (value) {
          ref.read(malvaStoreProvider.notifier).upsertMedication(value);
          unawaited(_syncMedication(context, value, isNew: medication == null));
          unawaited(_reminderService?.scheduleMedicationReminder(value));
          Navigator.pop(context);
        },
        onDelete: medication != null
            ? () {
                Navigator.pop(context);
                _deleteMedication(context, medication);
              }
            : null,
      ),
    );
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
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Log ${medication.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle_rounded,
                  color: MalvaColors.mint),
              title: const Text('Taken'),
              subtitle: const Text('Obat sudah diminum'),
              onTap: () {
                Navigator.pop(context);
                unawaited(_logMedication(context, medication, 'taken'));
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.skip_next_rounded, color: MalvaColors.amber),
              title: const Text('Skipped'),
              subtitle: const Text('Dilewati dengan sengaja'),
              onTap: () {
                Navigator.pop(context);
                unawaited(_logMedication(context, medication, 'skipped'));
              },
            ),
            ListTile(
              leading:
                  const Icon(Icons.cancel_rounded, color: MalvaColors.danger),
              title: const Text('Missed'),
              subtitle: const Text('Terlewat tanpa sengaja'),
              onTap: () {
                Navigator.pop(context);
                unawaited(_logMedication(context, medication, 'missed'));
              },
            ),
            ListTile(
              leading: const Icon(Icons.hourglass_bottom_rounded,
                  color: MalvaColors.orchid),
              title: const Text('Partial'),
              subtitle: const Text('Sebagian diminum'),
              onTap: () {
                Navigator.pop(context);
                unawaited(_logMedication(context, medication, 'partial'));
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
        ],
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
    if (_isLogging) return;
    // Debounce per obat + status: tap ganda dalam 3 detik diabaikan.
    final key = '${medication.id}|$status';
    final now = wibNow();
    final last = _lastLogAt;
    if (_lastLogKey == key &&
        last != null &&
        now.difference(last) < const Duration(seconds: 3)) {
      return;
    }
    _lastLogKey = key;
    _lastLogAt = now;
    setState(() => _isLogging = true);

    final store = ref.read(malvaStoreProvider.notifier);
    final consumed = status == 'taken' || status == 'partial';
    store.takeMedication(medication.id, status: status);
    final accepted = await _syncMedicationLog(context, medication, status);
    if (!mounted) return;
    setState(() => _isLogging = false);

    if (accepted) {
      if (consumed) store.confirmDose(medication.id);
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
      unawaited(
        ref.read(offlineSyncServiceProvider).enqueueMedicationLog(
              medicationId:
                  _looksLikeServerId(medication.id) ? medication.id : '',
              medicationName: medication.name,
              status: status,
            ),
      );
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

    if (medication.needsRefill) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              '${medication.name} stok rendah (${medication.currentStock}). Segera refill!'),
          backgroundColor: MalvaColors.amber,
          duration: const Duration(seconds: 4),
        ),
      );
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
    final accessToken = _session?.accessToken;
    final api = _apiClient;
    if (api == null || accessToken == null || accessToken.isEmpty) {
      return;
    }
    try {
      final reminder = medication.reminders.first;
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
          reminderTime: reminder.label,
          relationToMeal: reminder.relationToMeal,
          currentStock: medication.currentStock,
          alertBelow: medication.alertBelow,
          source: medication.source,
        );
        return;
      }
      final created = await api.createMedication(
        accessToken: accessToken,
        name: medication.name,
        dosage: medication.dosage,
        form: medication.form,
        reminderTime: reminder.label,
        relationToMeal: reminder.relationToMeal,
        currentStock: medication.currentStock,
        alertBelow: medication.alertBelow,
        source: medication.source,
      );
      // Simpan id dari server agar edit berikutnya memakai PUT, bukan POST
      // yang akan melahirkan baris baru lagi.
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
  /// Mengembalikan `true` HANYA bila server menerima log SEKALIGUS memotong
  /// stok — yaitu saat `medication_id` benar-benar dikirim. Tanpa
  /// `medication_id`, backend tidak memotong stok (lihat
  /// `backend/internal/store/store.go` pada CreateMedicationLog), sehingga
  /// refresh berikutnya mengembalikan stok lama: inilah akar bug "stok 2
  /// kembali jadi 3".
  Future<bool> _syncMedicationLog(
    BuildContext context,
    Medication medication,
    String status,
  ) async {
    final accessToken = _session?.accessToken;
    final api = _apiClient;
    if (api == null || accessToken == null || accessToken.isEmpty) return false;
    final serverId = _looksLikeServerId(medication.id) ? medication.id : null;
    try {
      await api.createMedicationLog(
        accessToken: accessToken,
        medicationId: serverId,
        medicationName: medication.name,
        status: status,
        // Waktu minum memakai acuan server (bukan jam perangkat) agar dosis
        // tidak tercatat di hari yang salah bila jam perangkat meleset.
        takenAt: ServerClock.now(),
      );
      return serverId != null;
    } on Object catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text('Log obat tersimpan lokal, sync backend gagal: $error'),
          ),
        );
      }
      return false;
    }
  }
}

TimeOfDay _parseReminderTime(String reminderTime) {
  final parts = reminderTime.split(':');
  return TimeOfDay(
    hour: int.tryParse(parts[0]) ?? 8,
    minute: parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0,
  );
}

class _MedicationCard extends StatelessWidget {
  const _MedicationCard({
    required this.medication,
    required this.onTake,
    required this.onEdit,
  });

  final Medication medication;
  final VoidCallback onTake;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final firstReminder = medication.reminders.first;
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
                        '${medication.dosage} - ${medication.form} - ${firstReminder.relationToMeal}'),
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
                label: firstReminder.label,
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  medication.lastTakenLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              FilledButton.icon(
                onPressed: onTake,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                ),
                icon: const Icon(Icons.check_rounded),
                label: const Text('Take Now'),
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
  late TimeOfDay _time;
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
        TextEditingController(text: (med?.alertBelow ?? 5).toString());
    _time = med?.reminders.first.time ?? const TimeOfDay(hour: 8, minute: 0);
    _relation = med?.reminders.first.relationToMeal ?? 'Setelah makan';
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
              widget.initial == null ? 'Tambah Medication' : 'Edit Medication',
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
              onPressed: _pickTime,
              icon: const Icon(Icons.schedule_rounded),
              label: Text(
                  'Reminder ${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}'),
            ),
            DropdownButtonFormField<String>(
              initialValue: _relation,
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
                        const InputDecoration(labelText: 'Current stock'),
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
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  void _save() {
    final id = widget.initial?.id ?? 'med_${wibNow().millisecondsSinceEpoch}';
    widget.onSave(
      Medication(
        id: id,
        name: _name.text.trim().isEmpty ? 'Medication' : _name.text.trim(),
        dosage: _dosage.text.trim().isEmpty ? '0 mg' : _dosage.text.trim(),
        form: _form.text.trim().isEmpty ? 'Tablet' : _form.text.trim(),
        reminders: [
          MedicationReminder(time: _time, relationToMeal: _relation),
        ],
        currentStock: int.tryParse(_stock.text.trim()) ?? 0,
        alertBelow: int.tryParse(_alertBelow.text.trim()) ?? 5,
        source: widget.initial?.source ?? 'Pasien',
      ),
    );
  }
}
