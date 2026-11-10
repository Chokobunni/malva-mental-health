import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../services/malva_api_client.dart';
import '../../services/mood_insights.dart';
import '../../widgets/mood_insights.dart';
import '../../providers/providers.dart';
import '../../theme.dart';
import '../../time/wib.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';
import '../../widgets/therapy_library.dart';
import '../assessment_history_screen.dart';

// ============================================================
// DATA PASIEN DIBAGIKAN (professional) — SATU PINTU dari dashboard.
//
// Menampilkan data yang dibagikan pasien terhubung dalam 7 kategori:
// Mood, Diary, Obat, Health Record, Goals, Screening, Terapi. Semua READ-ONLY.
//
// PENTING:
// - Pemilih pasien HANYA berisi pasien dari link aktif. Data pasien di luar
//   daftar link tidak pernah diminta.
// - 403 per-kategori (consent) dipetakan menjadi "Pasien belum membagikan
//   data ini." untuk kategori itu saja — bukan kegagalan global.
// ============================================================

class SharedPatientDataScreen extends ConsumerStatefulWidget {
  const SharedPatientDataScreen({
    super.key,
    this.session,
    this.apiClient,
  });

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<SharedPatientDataScreen> createState() =>
      _SharedPatientDataScreenState();
}

class _SharedPatientDataScreenState
    extends ConsumerState<SharedPatientDataScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  List<BackendPatientProfessionalLink> _links = const [];
  String? _selectedPatientId;
  bool _isLoading = true;
  String? _error;
  late final AuthSession? _owner;

  static const List<_TabSpec> _tabs = [
    _TabSpec('Mood', Icons.mood_rounded),
    _TabSpec('Diary', Icons.menu_book_rounded),
    _TabSpec('Obat', Icons.medication_rounded),
    _TabSpec('Health Record', Icons.medical_information_rounded),
    _TabSpec('Goals', Icons.flag_rounded),
    _TabSpec('Screening', Icons.fact_check_rounded),
    _TabSpec('Terapi', Icons.psychology_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _owner = ref.read(currentSessionProvider);
    _tabController = TabController(length: _tabs.length, vsync: this);
    unawaited(_loadLinks());
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadLinks() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = 'Mode offline aktif. Hubungkan ke server untuk melihat '
            'data pasien.';
      });
      return;
    }
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final links = await apiClient.listPatientProfessionalLinks(
          accessToken: accessToken);
      if (!mounted) return;
      setState(() {
        _links = links.where((link) => link.status == 'active').toList();
        _selectedPatientId = _links.isEmpty ? null : _links.first.patientId;
        _isLoading = false;
      });
    } on MalvaApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyServerMessage(error.message);
        _isLoading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyErrorMessage(error);
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (ref.watch(currentSessionProvider) != _owner) {
      return const Scaffold(
          body: Center(child: Text('Sesi akun telah berubah.')));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Data Pasien Dibagikan'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: SoftCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: MalvaColors.danger, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _loadLinks,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Coba Lagi'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_links.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: EmptyState(
          icon: Icons.folder_shared_outlined,
          title: 'Belum ada pasien terhubung',
          subtitle:
              'Pasien terhubung setelah membeli paket atau booking sesi denganmu. '
              'Data yang mereka bagikan akan tampil di sini.',
        ),
      );
    }

    final patientId = _selectedPatientId!;
    return Column(
      children: [
        _PatientSelector(
          links: _links,
          selectedPatientId: patientId,
          onChanged: (value) => setState(() => _selectedPatientId = value),
        ),
        Material(
          color: Colors.transparent,
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            labelColor: MalvaColors.seed,
            unselectedLabelColor: Colors.black54,
            indicatorColor: MalvaColors.seed,
            tabs: [
              for (final tab in _tabs) Tab(text: tab.label),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              // Setiap tab memakai ValueKey(patientId) agar memuat ulang saat
              // pasien diganti — data lama tidak tertinggal di layar.
              _MoodTab(
                  key: ValueKey('mood_$patientId'),
                  session: widget.session,
                  apiClient: widget.apiClient,
                  patientId: patientId),
              _DiaryTab(
                  key: ValueKey('diary_$patientId'),
                  session: widget.session,
                  apiClient: widget.apiClient,
                  patientId: patientId),
              _MedicationTab(
                  key: ValueKey('med_$patientId'),
                  session: widget.session,
                  apiClient: widget.apiClient,
                  patientId: patientId),
              _HealthRecordTab(
                  key: ValueKey('hr_$patientId'),
                  session: widget.session,
                  apiClient: widget.apiClient,
                  patientId: patientId),
              _GoalTab(
                  key: ValueKey('goal_$patientId'),
                  session: widget.session,
                  apiClient: widget.apiClient,
                  patientId: patientId),
              _ScreeningTab(
                  key: ValueKey('screening_$patientId'),
                  session: widget.session,
                  apiClient: widget.apiClient,
                  patientId: patientId),
              _TherapyTab(
                  key: ValueKey('therapy_$patientId'),
                  session: widget.session,
                  apiClient: widget.apiClient,
                  patientId: patientId),
            ],
          ),
        ),
      ],
    );
  }
}

class _TabSpec {
  const _TabSpec(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _PatientSelector extends StatelessWidget {
  const _PatientSelector({
    required this.links,
    required this.selectedPatientId,
    required this.onChanged,
  });

  final List<BackendPatientProfessionalLink> links;
  final String selectedPatientId;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: DropdownButtonFormField<String>(
        initialValue: selectedPatientId,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Pilih pasien',
          prefixIcon: Icon(Icons.person_rounded),
        ),
        items: [
          for (final link in links)
            DropdownMenuItem<String>(
              value: link.patientId,
              child: Text(
                link.patientDisplayName.trim().isEmpty
                    ? 'Pasien Malva'
                    : link.patientDisplayName,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

/// Status pemuatan generik untuk satu tab data pasien.
enum _LoadState { loading, ready, notShared, error }

/// Basis bersama untuk tab data read-only: memuat satu sumber data, memetakan
/// 403 menjadi "belum membagikan", dan menyediakan empty/error state yang
/// konsisten. Subclass mengisi [loadData] dan [buildContent].
abstract class _PatientDataTabState<T> extends ConsumerStatefulWidget {
  const _PatientDataTabState({
    super.key,
    required this.session,
    required this.apiClient,
    required this.patientId,
  });

  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final String patientId;
}

abstract class _PatientDataTabStateBase<T, W extends _PatientDataTabState<T>>
    extends ConsumerState<W> {
  _LoadState _state = _LoadState.loading;
  T? _data;
  String? _errorMessage;

  /// Muat data dari server untuk [W.patientId]. Boleh melempar
  /// [MalvaApiException] (403 ditangani otomatis).
  Future<T> loadData(MalvaApiClient apiClient, String accessToken);

  /// Nama kategori untuk pesan "belum membagikan data <kategori>".
  String get categoryLabel;

  /// Ikon empty state.
  IconData get emptyIcon;

  /// Pesan empty state (data kosong tetapi berhasil dimuat).
  String get emptyMessage;

  /// Bangun isi saat data tersedia.
  Widget buildContent(BuildContext context, T data);

  /// True bila [data] dianggap kosong (mis. list kosong).
  bool isEmpty(T data);

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      setState(() {
        _state = _LoadState.error;
        _errorMessage = 'Mode offline aktif.';
      });
      return;
    }
    setState(() {
      _state = _LoadState.loading;
      _errorMessage = null;
    });
    try {
      final data = await loadData(apiClient, accessToken);
      if (!mounted) return;
      setState(() {
        _data = data;
        _state = _LoadState.ready;
      });
    } on MalvaApiException catch (error) {
      if (!mounted) return;
      setState(() {
        if (error.statusCode == 403) {
          _state = _LoadState.notShared;
        } else {
          _state = _LoadState.error;
          _errorMessage = friendlyServerMessage(error.message);
        }
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _state = _LoadState.error;
        _errorMessage = friendlyErrorMessage(error);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (_state) {
      case _LoadState.loading:
        return const Center(child: CircularProgressIndicator());
      case _LoadState.notShared:
        return _DataNotice(
          icon: Icons.lock_outline_rounded,
          message: 'Pasien belum membagikan data $categoryLabel.',
        );
      case _LoadState.error:
        return _DataNotice(
          icon: Icons.cloud_off_rounded,
          message: _errorMessage ?? 'Terjadi kendala. Silakan coba lagi.',
          onRetry: _load,
        );
      case _LoadState.ready:
        final data = _data;
        if (data == null || isEmpty(data)) {
          return _DataNotice(icon: emptyIcon, message: emptyMessage);
        }
        return RefreshIndicator(
          onRefresh: _load,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [buildContent(context, data)],
          ),
        );
    }
  }
}

class _DataNotice extends StatelessWidget {
  const _DataNotice({
    required this.icon,
    required this.message,
    this.onRetry,
  });

  final IconData icon;
  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        SoftCard(
          child: Column(
            children: [
              Icon(icon, size: 40, color: Colors.black38),
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.black54, fontWeight: FontWeight.w600),
              ),
              if (onRetry != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Coba Lagi'),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------- MOOD ----------------

class _MoodTab extends _PatientDataTabState<List<BackendMoodCheckin>> {
  const _MoodTab({
    super.key,
    required super.session,
    required super.apiClient,
    required super.patientId,
  });

  @override
  ConsumerState<_MoodTab> createState() => _MoodTabState();
}

class _MoodTabState
    extends _PatientDataTabStateBase<List<BackendMoodCheckin>, _MoodTab> {
  @override
  String get categoryLabel => 'mood';

  @override
  IconData get emptyIcon => Icons.mood_outlined;

  @override
  String get emptyMessage => 'Belum ada catatan mood yang dibagikan.';

  @override
  bool isEmpty(List<BackendMoodCheckin> data) => data.isEmpty;

  @override
  Future<List<BackendMoodCheckin>> loadData(
      MalvaApiClient apiClient, String accessToken) {
    return apiClient.listMoodCheckins(
        accessToken: accessToken, patientId: widget.patientId, limit: 0);
  }

  @override
  Widget buildContent(BuildContext context, List<BackendMoodCheckin> data) {
    return MoodInsights(
        entries: data
            .where((m) => m.occurredAt != null)
            .map(moodEntryFromBackend)
            .toList());
  }
}

// ---------------- DIARY ----------------

class _DiaryTab extends _PatientDataTabState<List<BackendDiaryEntry>> {
  const _DiaryTab({
    super.key,
    required super.session,
    required super.apiClient,
    required super.patientId,
  });

  @override
  ConsumerState<_DiaryTab> createState() => _DiaryTabState();
}

class _DiaryTabState
    extends _PatientDataTabStateBase<List<BackendDiaryEntry>, _DiaryTab> {
  @override
  String get categoryLabel => 'diary';

  @override
  IconData get emptyIcon => Icons.menu_book_outlined;

  @override
  String get emptyMessage => 'Belum ada diary yang dibagikan.';

  @override
  bool isEmpty(List<BackendDiaryEntry> data) => data.isEmpty;

  @override
  Future<List<BackendDiaryEntry>> loadData(
      MalvaApiClient apiClient, String accessToken) {
    return apiClient.listDiaryEntries(
        accessToken: accessToken, patientId: widget.patientId);
  }

  @override
  Widget buildContent(BuildContext context, List<BackendDiaryEntry> data) {
    return Column(
      children: [
        for (final entry in data) ...[
          SoftCard(
            bordered: true,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.title.isEmpty ? 'Catatan diary' : entry.title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    Text(
                      _wibDate(entry.occurredAt),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                if (entry.note.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(entry.note,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

// ---------------- OBAT ----------------

class _MedicationTab extends _PatientDataTabState<List<BackendMedication>> {
  const _MedicationTab({
    super.key,
    required super.session,
    required super.apiClient,
    required super.patientId,
  });

  @override
  ConsumerState<_MedicationTab> createState() => _MedicationTabState();
}

class _MedicationTabState
    extends _PatientDataTabStateBase<List<BackendMedication>, _MedicationTab> {
  @override
  String get categoryLabel => 'obat';

  @override
  IconData get emptyIcon => Icons.medication_outlined;

  @override
  String get emptyMessage => 'Belum ada data obat yang dibagikan.';

  @override
  bool isEmpty(List<BackendMedication> data) => data.isEmpty;

  @override
  Future<List<BackendMedication>> loadData(
      MalvaApiClient apiClient, String accessToken) {
    return apiClient.listMedications(
        accessToken: accessToken, patientId: widget.patientId);
  }

  @override
  Widget buildContent(BuildContext context, List<BackendMedication> data) {
    return Column(
      children: [
        for (final med in data) ...[
          SoftCard(
            bordered: true,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0x1F36C7A6),
                  child:
                      Icon(Icons.medication_rounded, color: MalvaColors.mint),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        med.name.isEmpty ? 'Obat' : med.name,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        [
                          if (med.dosage.isNotEmpty) med.dosage,
                          if (med.form.isNotEmpty) med.form,
                          'stok ${med.currentStock}',
                        ].join(' • '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (med.needsRefill)
                  const StatusPill(
                      label: 'Perlu isi ulang', color: MalvaColors.amber),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

// ---------------- HEALTH RECORD ----------------

class _HealthRecordTab extends _PatientDataTabState<BackendHealthRecord> {
  const _HealthRecordTab({
    super.key,
    required super.session,
    required super.apiClient,
    required super.patientId,
  });

  @override
  ConsumerState<_HealthRecordTab> createState() => _HealthRecordTabState();
}

class _HealthRecordTabState
    extends _PatientDataTabStateBase<BackendHealthRecord, _HealthRecordTab> {
  @override
  String get categoryLabel => 'Health Record';

  @override
  IconData get emptyIcon => Icons.medical_information_outlined;

  @override
  String get emptyMessage => 'Health record belum diisi.';

  @override
  bool isEmpty(BackendHealthRecord data) =>
      !data.hasDiagnosis && data.diagnosisSummary.trim().isEmpty;

  @override
  Future<BackendHealthRecord> loadData(
      MalvaApiClient apiClient, String accessToken) {
    return apiClient.getHealthRecord(
        accessToken: accessToken, patientId: widget.patientId);
  }

  @override
  Widget buildContent(BuildContext context, BackendHealthRecord data) {
    return Column(
      children: [
        SoftCard(
          bordered: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Ringkasan diagnosis',
                  style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(
                data.diagnosisSummary.trim().isEmpty
                    ? 'Belum ada diagnosis.'
                    : data.diagnosisSummary,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Colors.black87),
              ),
              if (data.authorName.trim().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('Oleh: ${data.authorName}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
              if (data.updatedAt != null)
                Text('Diperbarui ${_wibDate(data.updatedAt)}',
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
        if (data.medications.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text('Obat aktif',
              style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          for (final med in data.medications) ...[
            SoftCard(
              bordered: true,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(med.name,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  Text(
                    [if (med.dosage.isNotEmpty) med.dosage, med.form]
                        .where((e) => e.isNotEmpty)
                        .join(' • '),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ],
    );
  }
}

// ---------------- GOALS ----------------

class _GoalTab extends _PatientDataTabState<List<BackendGoal>> {
  const _GoalTab({
    super.key,
    required super.session,
    required super.apiClient,
    required super.patientId,
  });

  @override
  ConsumerState<_GoalTab> createState() => _GoalTabState();
}

class _GoalTabState
    extends _PatientDataTabStateBase<List<BackendGoal>, _GoalTab> {
  @override
  String get categoryLabel => 'tujuan terapi';

  @override
  IconData get emptyIcon => Icons.flag_outlined;

  @override
  String get emptyMessage => 'Belum ada tujuan terapi yang dibagikan.';

  @override
  bool isEmpty(List<BackendGoal> data) => data.isEmpty;

  @override
  Future<List<BackendGoal>> loadData(
      MalvaApiClient apiClient, String accessToken) {
    return apiClient.listGoals(
        accessToken: accessToken, patientId: widget.patientId);
  }

  @override
  Widget buildContent(BuildContext context, List<BackendGoal> data) {
    return Column(
      children: [
        for (final goal in data) ...[
          SoftCard(
            bordered: true,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0x1F8E44AD),
                  child: Icon(Icons.flag_rounded, color: MalvaColors.seed),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goal.title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      Text(
                        '${goal.doneThisWeek}/${goal.targetPerWeek} kali minggu ini',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                StatusPill(
                  label: goal.isActive ? 'Aktif' : 'Nonaktif',
                  color: goal.isActive ? MalvaColors.mint : Colors.grey,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

// ---------------- SCREENING ----------------

class _ScreeningTab extends _PatientDataTabState<List<AssessmentHistoryEntry>> {
  const _ScreeningTab({
    super.key,
    required super.session,
    required super.apiClient,
    required super.patientId,
  });

  @override
  ConsumerState<_ScreeningTab> createState() => _ScreeningTabState();
}

class _ScreeningTabState extends _PatientDataTabStateBase<
    List<AssessmentHistoryEntry>, _ScreeningTab> {
  @override
  String get categoryLabel => 'screening';

  @override
  IconData get emptyIcon => Icons.fact_check_outlined;

  @override
  String get emptyMessage => 'Belum ada hasil screening yang dibagikan.';

  @override
  bool isEmpty(List<AssessmentHistoryEntry> data) => data.isEmpty;

  @override
  Future<List<AssessmentHistoryEntry>> loadData(
          MalvaApiClient apiClient, String accessToken) =>
      loadAssessmentHistory(
          api: apiClient,
          accessToken: accessToken,
          patientId: widget.patientId);

  @override
  Widget buildContent(
          BuildContext context, List<AssessmentHistoryEntry> data) =>
      Column(children: [
        for (final entry in data) ...[
          AssessmentHistoryCard(
              entry: entry,
              onTap: () => showAssessmentHistoryDetail(context, entry)),
          const SizedBox(height: 8),
        ],
      ]);
}

// ---------------- TERAPI ----------------

class _TherapyTab extends _PatientDataTabState<List<BackendTherapySubmission>> {
  const _TherapyTab({
    super.key,
    required super.session,
    required super.apiClient,
    required super.patientId,
  });

  @override
  ConsumerState<_TherapyTab> createState() => _TherapyTabState();
}

class _TherapyTabState extends _PatientDataTabStateBase<
    List<BackendTherapySubmission>, _TherapyTab> {
  @override
  String get categoryLabel => 'terapi';

  @override
  IconData get emptyIcon => Icons.psychology_outlined;

  @override
  String get emptyMessage => 'Belum ada worksheet terapi yang dibagikan.';

  @override
  bool isEmpty(List<BackendTherapySubmission> data) => data.isEmpty;

  @override
  Future<List<BackendTherapySubmission>> loadData(
      MalvaApiClient apiClient, String accessToken) async {
    final submissions = await apiClient.listTherapySubmissions(
        accessToken: accessToken, patientId: widget.patientId, limit: 0);
    return submissions.where(isTherapyRecordSubmission).toList();
  }

  @override
  Widget buildContent(
      BuildContext context, List<BackendTherapySubmission> data) {
    return Column(
      children: [
        for (final submission in data) ...[
          SoftCard(
            onTap: () => showTherapyRecordDetail(context, submission),
            bordered: true,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        submission.title.isEmpty
                            ? 'Worksheet terapi'
                            : submission.title,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                    if (submission.isShared)
                      const StatusPill(
                          label: 'Dibagikan', color: MalvaColors.mint),
                  ],
                ),
                if (submission.summary.trim().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(submission.summary,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.black54)),
                ],
                if (submission.createdDateTime != null) ...[
                  const SizedBox(height: 4),
                  Text(_wibDate(submission.createdDateTime),
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

/// Tanggal ringkas WIB `dd/MM/yyyy HH:mm` untuk kartu data pasien.
String _wibDate(DateTime? value) {
  if (value == null) return '';
  return formatWibDateTimeShort(value);
}
