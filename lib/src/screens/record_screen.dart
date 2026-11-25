import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/friendly_error.dart';
import '../widgets/clinical_allergy_section.dart';
import '../widgets/clinical_profile_cards.dart';
import '../widgets/malva_components.dart';
import 'assessment_history_screen.dart';
import '../time/wib.dart';

/// Tanggal "Diperbarui" pada kartu diagnosis (`d/M/yyyy`) dalam waktu WIB.
///
/// `updatedAt` health record berasal dari server (UTC), jadi WAJIB
/// `toWib()` lebih dulu — tanpa itu pembaruan dini hari WIB tampil sebagai
/// tanggal kemarin. Pola keluaran dipertahankan seperti sebelumnya (tanggal
/// TANPA padding, mis. `1/11/2026`) agar tampilan tidak berubah selain
/// kebenaran tanggalnya.
String formatHealthRecordUpdatedDate(DateTime? value) {
  if (value == null) return '';
  return formatWibDateShort(value);
}

class RecordScreen extends ConsumerStatefulWidget {
  const RecordScreen({super.key, this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<RecordScreen> createState() => _RecordScreenState();
}

class _RecordScreenState extends ConsumerState<RecordScreen> {
  String? _selectedFileName;
  String _searchQuery = '';
  String _typeFilter = 'Semua';
  int _visibleCount = 4;
  List<BackendHealthRecordAllergy> _allergies = const [];
  String? _allergyError;
  int? _adherence;

  /// Filter jenis entri Record (dokumen / assessment / therapy).
  String _kindFilter = _RecordEntry.kindAll;

  BackendHealthRecord? _healthRecord;
  List<BackendMedication> _medications = const [];
  List<BackendTherapySubmission> _therapySubmissions = const [];
  List<BackendScreeningSession> _screenings = const [];
  bool _isLoading = true;
  String? _loadError;
  int _loadRequest = 0;
  late final String _screenOwner;

  String _ownerKey(AuthSession? session) =>
      '${session?.role.name}:${session?.backendUserId ?? session?.identifier ?? ''}';

  /// True selama assessment & therapy record masih dimuat.
  ///
  /// Dipisah dari [_isLoading] supaya diagnosis/obat/dokumen tampil segera
  /// setelah data inti siap — daftar Record hanya menambah baris indikator
  /// ringkas selama sumber tambahan belum selesai.
  bool _extrasLoading = true;

  /// Kegagalan sumber tambahan (therapy record / assessment record) — ditampilkan
  /// sebagai keterangan kecil, tidak mengosongkan seluruh layar.
  String? _therapyError;
  String? _screeningError;

  List<String> get _typeOptions =>
      const ['Semua', 'PDF', 'IMAGE', 'DOC', 'OTHER'];

  List<String> get _kindOptions => const [
        _RecordEntry.kindAll,
        _RecordEntry.kindDocument,
        _RecordEntry.kindAssessment,
        _RecordEntry.kindTherapy,
      ];

  @override
  void initState() {
    super.initState();
    _screenOwner = _ownerKey(ref.read(currentSessionProvider));
    _loadFromServer();
  }

  Future<void> _loadFromServer() async {
    final request = ++_loadRequest;
    bool isCurrent() =>
        mounted &&
        request == _loadRequest &&
        _screenOwner == _ownerKey(ref.read(currentSessionProvider));
    final apiClient = widget.apiClient;
    final accessToken =
        (ref.read(currentSessionProvider) ?? widget.session)?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      // Tanpa sesi tidak ada yang dimuat: matikan kedua indikator agar tidak
      // ada spinner yang berputar selamanya.
      if (isCurrent()) {
        setState(() {
          _isLoading = false;
          _extrasLoading = false;
        });
      }
      return;
    }
    if (isCurrent()) {
      setState(() {
        _isLoading = true;
        _extrasLoading = true;
        _loadError = null;
        _therapyError = null;
        _screeningError = null;
        _allergyError = null;
        _adherence = null;
      });
    }
    // Data inti (diagnosis + obat) dimuat lebih dulu; kegagalannya tetap jadi
    // error utama layar seperti sebelumnya.
    try {
      final results = await Future.wait([
        apiClient.getHealthRecord(accessToken: accessToken),
        apiClient.listMedications(accessToken: accessToken),
      ]);
      if (!isCurrent()) return;
      final record = results[0] as BackendHealthRecord;
      // Tampilkan SEMUA obat aktif apa pun sumbernya ('Pasien' maupun
      // 'Profesional'). Dulu obat yang ditambahkan pasien sendiri difilter
      // keluar (source != 'pasien') sehingga tidak muncul di Health Record
      // (mis. Lamictal dengan source 'Pasien').
      final meds = results[1] as List<BackendMedication>;
      setState(() {
        _healthRecord = record;
        _medications = meds;
      });
      ref
          .read(malvaStoreProvider.notifier)
          .setPatientDiagnosis(record.diagnosisSummary);
    } on Object catch (e) {
      if (!isCurrent()) return;
      setState(() {
        _loadError = e is MalvaApiException ? e.message : null;
      });
    }
    // Data inti selesai (sukses maupun gagal) → layar langsung tampil, tidak
    // ikut menunggu dua request tambahan di bawah.
    if (!isCurrent()) return;
    setState(() => _isLoading = false);

    final additionalClinical = Future.wait([
      apiClient
          .listHealthRecordAllergies(accessToken: accessToken)
          .then((records) {
        if (isCurrent()) setState(() => _allergies = records);
      }).catchError((Object error) {
        if (isCurrent())
          setState(() => _allergyError = friendlyErrorMessage(error));
      }),
      apiClient
          .listMedicationLogs(accessToken: accessToken, limit: 0)
          .then((logs) {
        if (isCurrent() && _loadError == null) {
          setState(() =>
              _adherence = clinicalMedicationAdherence(_medications, logs));
        }
      }).catchError((Object _) {}),
    ]);
    // Sumber tambahan dimuat TERPISAH: satu endpoint gagal tidak boleh
    // mengosongkan dokumen/diagnosis/obat yang sudah tampil.
    try {
      final submissions =
          await apiClient.listTherapySubmissions(accessToken: accessToken);
      if (!isCurrent()) return;
      setState(() => _therapySubmissions = submissions);
    } on Object catch (e) {
      if (!isCurrent()) return;
      setState(() => _therapyError = friendlyErrorMessage(e));
    }

    // `patient_id` kosong membuat server menolak permintaan (400), jadi
    // riwayat screening hanya dimuat bila id pasien backend tersedia.
    final patientId = (widget.session?.backendUserId ?? '').trim();
    if (patientId.isNotEmpty) {
      try {
        final screenings = await apiClient.listScreenings(
          accessToken: accessToken,
          patientId: patientId,
          limit: 0,
        );
        if (!isCurrent()) return;
        setState(() => _screenings = screenings);
      } on Object catch (e) {
        if (!isCurrent()) return;
        setState(() => _screeningError = friendlyErrorMessage(e));
      }
    }

    await additionalClinical;
    if (isCurrent()) setState(() => _extrasLoading = false);
  }

  /// Gabungkan dokumen unggahan + assessment record + therapy record menjadi
  /// satu daftar kronologis (terbaru dulu, entri tanpa tanggal paling akhir).
  List<_RecordEntry> _buildEntries(
    BuildContext context,
    List<HealthRecord> documents,
  ) {
    final entries = <_RecordEntry>[];

    // 1. Dokumen unggahan — perilaku lama dipertahankan (tanpa aksi tap).
    for (final document in documents) {
      entries.add(
        _RecordEntry(
          kind: _RecordEntry.kindDocument,
          title: document.title,
          date: document.date,
          fileType: document.type,
          icon: _getRecordIcon(document.type),
          color: MalvaColors.seed,
          locked: document.lockedByProfessional,
          onDelete: document.lockedByProfessional
              ? null
              : () => _deleteDocument(document),
        ),
      );
    }

    // 2. Assessment record & 3. therapy record dari submission worksheet server.
    for (final submission in _therapySubmissions) {
      final history = assessmentEntryFromSubmission(submission);
      entries.add(
        _RecordEntry(
          kind: history.isAssessmentResult
              ? _RecordEntry.kindAssessment
              : _RecordEntry.kindTherapy,
          title: history.title,
          detail: history.subtitle,
          date: history.date,
          icon: history.icon,
          color: history.color,
          isShared: history.isShared,
          onTap: () => showAssessmentHistoryDetail(context, history),
        ),
      );
    }

    // Screening PHQ-9 + GAD-7 termasuk assessment record.
    for (final screening in _screenings) {
      final history = assessmentEntryFromScreening(screening);
      entries.add(
        _RecordEntry(
          kind: _RecordEntry.kindAssessment,
          title: history.title,
          detail: history.subtitle,
          date: history.date,
          icon: history.icon,
          color: screening.crisisFlag ? MalvaColors.danger : history.color,
          crisis: screening.crisisFlag,
          scores: history.subtitle.split(' • '),
          onTap: () => showAssessmentHistoryDetail(context, history),
        ),
      );
    }

    entries.sort((a, b) {
      final dateA = a.date;
      final dateB = b.date;
      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return 1;
      if (dateB == null) return -1;
      return dateB.compareTo(dateA);
    });
    return entries;
  }

  /// Filter jenis + tipe file + pencarian judul (lintas jenis).
  bool _matchesFilter(_RecordEntry entry) {
    if (_kindFilter != _RecordEntry.kindAll && entry.kind != _kindFilter) {
      return false;
    }
    // Tipe file hanya bermakna untuk dokumen unggahan.
    if (_kindFilter == _RecordEntry.kindDocument &&
        _typeFilter != 'Semua' &&
        entry.fileType.toUpperCase() != _typeFilter) {
      return false;
    }
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return true;
    return '${entry.title} ${entry.detail} ${entry.fileType}'
        .toLowerCase()
        .contains(query);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentSessionProvider);
    if (_screenOwner != _ownerKey(ref.read(currentSessionProvider))) {
      return const Scaffold(
          body: Center(
              child: Text('Sesi akun telah berubah. Buka kembali Record.')));
    }
    ref.listen<int>(clinicalDataRevisionProvider, (_, __) => _loadFromServer());
    final storeState = ref.watch(malvaStoreProvider);
    // Record = gabungan kronologis dokumen unggahan + assessment record +
    // therapy record agar riwayat klinis pasien terbaca dalam satu daftar.
    final entries = _buildEntries(context, storeState.records);
    final visibleEntries =
        entries.where(_matchesFilter).toList(growable: false);
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadFromServer,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            GradientHeader(
              title: 'Profil Klinis',
              subtitle: 'Ringkasan kesehatan & catatan siap dibagikan',
              leading: IconButton(
                onPressed: () => Navigator.maybePop(context),
                icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SectionLabel('Diagnosis Klinis',
                      action: StatusPill(
                          label: 'Hanya Baca',
                          color: MalvaColors.seed,
                          icon: Icons.lock_outline)),
                  if (_isLoading)
                    const SoftCard(
                      child: Center(
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    )
                  else if (_healthRecord?.hasDiagnosis == true)
                    ClinicalDiagnosisCard(record: _healthRecord!)
                  else
                    const _NoDiagnosisCard(),
                  if (_loadError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _loadError!,
                      style: const TextStyle(
                          color: MalvaColors.danger,
                          fontWeight: FontWeight.w700),
                    ),
                  ],
                  const SizedBox(height: 22),
                  ClinicalAllergySection(
                    records: _allergies,
                    onAdd: widget.apiClient != null &&
                            (ref.read(currentSessionProvider) ?? widget.session)
                                    ?.role ==
                                UserRole.patient
                        ? _addAllergy
                        : null,
                    status: _allergyError == null
                        ? null
                        : SoftCard(child: Text(_allergyError!)),
                  ),
                  const SizedBox(height: 22),
                  SectionLabel(
                    'Obat Aktif (${_medications.length})',
                    action: _adherence == null
                        ? null
                        : StatusPill(
                            label: 'Kepatuhan $_adherence% (7 hr)',
                            color: MalvaColors.seed),
                  ),
                  if (_isLoading)
                    const SizedBox.shrink()
                  else if (_medications.isEmpty)
                    const SoftCard(
                      child: Column(
                        children: [
                          Icon(Icons.medication_outlined,
                              size: 42, color: MalvaColors.seed),
                          SizedBox(height: 10),
                          Text(
                            'Belum ada obat',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Tambahkan obat dari menu Obat agar '
                            'muncul di sini.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    for (final med in _medications) ...[
                      ClinicalMedicationCard(med: med),
                      const SizedBox(height: 12),
                    ],
                  const SizedBox(height: 22),
                  SectionLabel(
                    'Arsip Klinis',
                    action: OutlinedButton.icon(
                      onPressed: () => _showAddRecordDialog(context),
                      icon: const Icon(Icons.upload_file_rounded),
                      label: const Text('Tambah Berkas'),
                    ),
                  ),
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Cari',
                      hintText: 'Cari dokumen, asesmen, atau terapi...',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (v) => setState(() {
                      _searchQuery = v;
                      _visibleCount = 4;
                    }),
                  ),
                  const SizedBox(height: 10),
                  // Sumber tambahan masih dimuat: indikator ringkas saja,
                  // bukan spinner besar yang menahan seluruh layar.
                  if (_extrasLoading) ...[
                    Row(
                      children: [
                        const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Memuat asesmen & riwayat Terapi…',
                          style: TextStyle(
                            fontSize: 12.5,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],
                  // Filter jenis entri (primer).
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final option in _kindOptions)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: FilterChip(
                              label: Text(option),
                              selected: _kindFilter == option,
                              onSelected: (_) => setState(() {
                                _kindFilter = option;
                                _visibleCount = 4;
                                // Filter tipe file hanya berlaku untuk dokumen;
                                // direset agar daftar tidak kosong tanpa sebab.
                                if (option != _RecordEntry.kindDocument) {
                                  _typeFilter = 'Semua';
                                }
                              }),
                              selectedColor:
                                  MalvaColors.seed.withValues(alpha: 0.15),
                              checkmarkColor: MalvaColors.seed,
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Filter tipe file hanya tampil saat melihat dokumen.
                  if (_kindFilter == _RecordEntry.kindDocument) ...[
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final option in _typeOptions)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                label: Text(option),
                                selected: _typeFilter == option,
                                onSelected: (_) => setState(() {
                                  _typeFilter = option;
                                  _visibleCount = 4;
                                }),
                                selectedColor:
                                    MalvaColors.seed.withValues(alpha: 0.15),
                                checkmarkColor: MalvaColors.seed,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  if (_therapyError != null || _screeningError != null) ...[
                    const SizedBox(height: 8),
                    // Kegagalan satu sumber hanya jadi keterangan kecil:
                    // dokumen, diagnosis, dan obat tetap tampil.
                    Text(
                      [
                        if (_therapyError != null)
                          'Riwayat Terapi belum termuat: $_therapyError',
                        if (_screeningError != null)
                          'Riwayat Asesmen belum termuat: $_screeningError',
                      ].join(' • '),
                      style: const TextStyle(
                          fontSize: 11.5, color: MalvaColors.danger),
                    ),
                  ],
                  const SizedBox(height: 10),
                  // Empty state ditahan selama sumber tambahan dimuat: kalau
                  // tidak, filter "Assessment"/"Therapy" sempat menampilkan
                  // "Tidak ada yang cocok" padahal datanya belum tiba.
                  if (visibleEntries.isEmpty && !_extrasLoading)
                    SoftCard(
                      child: Column(
                        children: [
                          const Icon(Icons.folder_open_rounded,
                              size: 48, color: MalvaColors.seed),
                          const SizedBox(height: 12),
                          Text(
                            entries.isEmpty
                                ? 'Belum ada record'
                                : 'Tidak ada yang cocok',
                            style: const TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Upload dokumen, isi asesmen, atau simpan '
                            'lembar kerja terapi — semuanya tampil di sini.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    )
                  else
                    for (final entry in visibleEntries.take(_visibleCount)) ...[
                      _RecordEntryCard(entry: entry),
                      const SizedBox(height: 12),
                    ],
                  if (visibleEntries.length > _visibleCount)
                    OutlinedButton(
                      onPressed: () => setState(() => _visibleCount += 5),
                      child: Text(
                          'Tunjukkan Lebih (${visibleEntries.length - _visibleCount} lagi)'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteDocument(HealthRecord document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Hapus berkas?'),
        content: Text(document.title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        _screenOwner != _ownerKey(ref.read(currentSessionProvider))) return;
    ref.read(malvaStoreProvider.notifier).deleteRecord(document.id);
  }

  Future<void> _addAllergy() async {
    final api = widget.apiClient!;
    final record = await showModalBottomSheet<BackendHealthRecordAllergy>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      isDismissible: false,
      enableDrag: false,
      showDragHandle: true,
      builder: (_) => AddClinicalAllergySheet(
        onSave: (id, reaction, substance, symptoms, severity, occurredWhen) {
          final session = ref.read(currentSessionProvider) ?? widget.session;
          final token = session?.accessToken;
          if (!mounted ||
              _screenOwner != _ownerKey(ref.read(currentSessionProvider)) ||
              session?.role != UserRole.patient ||
              token == null ||
              token.isEmpty) {
            return Future.error(StateError('Sesi akun telah berubah.'));
          }
          return api.createHealthRecordAllergy(
            accessToken: token,
            clientId: id,
            reactionType: reaction,
            substance: substance,
            symptoms: symptoms,
            severity: severity,
            occurredWhen: occurredWhen,
          );
        },
      ),
    );
    if (!mounted ||
        record == null ||
        _screenOwner != _ownerKey(ref.read(currentSessionProvider))) return;
    await _loadFromServer();
  }

  IconData _getRecordIcon(String type) {
    switch (type.toUpperCase()) {
      case 'PDF':
        return Icons.picture_as_pdf_rounded;
      case 'IMAGE':
      case 'JPG':
      case 'PNG':
        return Icons.image_rounded;
      case 'DOC':
      case 'DOCX':
        return Icons.description_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  void _showAddRecordDialog(BuildContext context) {
    final titleController = TextEditingController();
    String selectedType = 'PDF';

    showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Tambah Record'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Nama file',
                    hintText: 'contoh: Hasil_Tes_MMPI',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Tipe file:',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: ['PDF', 'IMAGE', 'DOC', 'OTHER'].map((type) {
                    return ChoiceChip(
                      label: Text(type),
                      selected: selectedType == type,
                      onSelected: (_) =>
                          setDialogState(() => selectedType = type),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () async {
                    final result = await FilePicker.platform.pickFiles();
                    if (result != null && result.files.isNotEmpty) {
                      _selectedFileName = result.files.single.name;
                      setDialogState(() {});
                    }
                  },
                  icon: const Icon(Icons.attach_file_rounded),
                  label: Text(_selectedFileName ?? 'Pilih File'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isEmpty) return;
                ref.read(malvaStoreProvider.notifier).addRecord(
                      HealthRecord(
                        id: 'record_${wibNow().millisecondsSinceEpoch}',
                        date: wibNow(),
                        title: title,
                        type: selectedType,
                        lockedByProfessional: false,
                      ),
                    );
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Record "${title}" berhasil ditambahkan.'),
                  ),
                );
              },
              style: compactFilledButtonStyle,
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Satu baris gabungan di bagian Record: dokumen unggahan, assessment record,
/// atau therapy record. [kind] dipakai filter primer di atas daftar.
class _RecordEntry {
  const _RecordEntry({
    required this.kind,
    required this.title,
    required this.icon,
    required this.color,
    this.detail = '',
    this.date,
    this.fileType = '',
    this.locked = false,
    this.isShared = false,
    this.onTap,
    this.onDelete,
    this.scores = const [],
    this.crisis = false,
  });

  static const String kindAll = 'Semua';
  static const String kindDocument = 'Dokumen';
  static const String kindAssessment = 'Asesmen';
  static const String kindTherapy = 'Terapi';

  final String kind;
  final String title;
  final IconData icon;
  final Color color;

  /// Ringkasan skor/isi; kosong untuk dokumen biasa.
  final String detail;
  final DateTime? date;

  /// Tipe file dokumen (PDF/IMAGE/DOC/OTHER); kosong untuk non-dokumen.
  final String fileType;

  /// Dokumen terkunci oleh profesional (read-only).
  final bool locked;

  /// Hasil yang sudah dibagikan ke profesional.
  final bool isShared;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final List<String> scores;
  final bool crisis;

  /// Baris keterangan kartu: jenis • tipe file • ringkasan • tanggal.
  String get description {
    final parts = <String>[kind];
    // Tipe file hanya ada pada dokumen; tanpa ini info PDF/IMAGE hilang dari
    // kartu dan hanya tersisa di ikon.
    if (fileType.isNotEmpty) parts.add(fileType);
    if (detail.isNotEmpty && scores.isEmpty) parts.add(detail);
    if (date != null) parts.add(formatAssessmentDate(date));
    return parts.join(' • ');
  }
}

/// Kartu satu entri Record (dokumen / assessment / therapy).
class _RecordEntryCard extends StatelessWidget {
  const _RecordEntryCard({required this.entry});

  final _RecordEntry entry;

  @override
  Widget build(BuildContext context) {
    final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
    return SoftCard(
      onTap: entry.onTap,
      color: Colors.white,
      outline: BorderSide(
        color: entry.crisis
            ? entry.color.withValues(alpha: 0.25)
            : const Color(0xFFEDE8F1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClinicalIconTile(icon: entry.icon, color: entry.color),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                if (entry.crisis || entry.scores.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 5),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        if (entry.crisis)
                          const StatusPill(
                              label: 'CRISIS',
                              color: MalvaColors.danger,
                              icon: Icons.warning_amber_rounded),
                        for (final score in entry.scores)
                          StatusPill(label: score, color: entry.color),
                      ],
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  entry.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: onSurfaceVariant),
                ),
                if (entry.isShared)
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: StatusPill(
                        label: 'Dibagikan',
                        color: MalvaColors.mint,
                        icon: Icons.send_rounded),
                  ),
              ],
            ),
          ),
          if (entry.onDelete case final remove?)
            IconButton(
                tooltip: 'Hapus berkas',
                onPressed: remove,
                icon: const Icon(Icons.delete_outline)),
          if (entry.locked)
            const Icon(Icons.lock_rounded, color: Colors.black45),
        ],
      ),
    );
  }
}

/// Empty state diagnosis: belum ada diagnosis profesional.
class _NoDiagnosisCard extends StatelessWidget {
  const _NoDiagnosisCard();

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.medical_information_outlined,
                  color: MalvaColors.amber),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Belum ada diagnosis',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Diagnosis hanya dapat diberikan oleh psikolog/psikiater '
            'terverifikasi setelah sesi konsultasi (meeting). Silakan booking '
            'dan ikuti sesi dengan profesional terlebih dahulu.',
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.lock_rounded, size: 18, color: Colors.black45),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Pasien read-only — data ini terisi otomatis setelah '
                  'profesional menyimpan diagnosis.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.black54),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
