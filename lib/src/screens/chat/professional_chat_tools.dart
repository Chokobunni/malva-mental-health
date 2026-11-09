import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../platform/contracts/ports.dart';
import '../../platform/platform_providers.dart';
import '../../professional_role.dart';
import '../../providers/auth_providers.dart';
import '../../services/client_intent_id.dart';
import '../../services/malva_api_client.dart';
import '../../services/server_clock.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';

/// Professional actions remain scoped to the patient and live session supplied
/// by ChatScreen. The server rechecks session eligibility and consent on writes.
class ProfessionalChatTools extends ConsumerStatefulWidget {
  const ProfessionalChatTools({
    super.key,
    required this.apiClient,
    required this.session,
    required this.patientId,
    required this.sessionId,
    this.sessionEndsAt,
    required this.onMessage,
    this.openFiles = false,
  });

  final MalvaApiClient apiClient;
  final AuthSession session;
  final String patientId;
  final String sessionId;
  final DateTime? sessionEndsAt;
  final ValueChanged<BackendChatMessage> onMessage;
  final bool openFiles;

  @override
  ConsumerState<ProfessionalChatTools> createState() =>
      _ProfessionalChatToolsState();
}

class _ProfessionalChatToolsState extends ConsumerState<ProfessionalChatTools> {
  String? _section;
  bool _busy = false;
  Object? _error;
  Future<void> Function()? _retry;
  List<BackendGoal>? _goals;
  final _selectedGoals = <String>{};
  final _goalTitle = TextEditingController();
  final _goalTarget = TextEditingController(text: '3');
  final _insight = TextEditingController();
  final _diagnosis = TextEditingController();
  String _module = 'screening';
  String? _goalFingerprint, _goalIntent, _cardFingerprint, _cardIntent;
  BackendHealthRecord? _health;
  List<BackendMedication>? _medications;
  Object? _medicationError;
  Object? _healthError;
  Timer? _expiryTimer;
  bool _expired = false;
  String? _medicationFingerprint, _medicationIntent;
  bool _psychiatrist = false;
  bool _showMedicationEditor = false;
  BackendMedication? _editingMedication;
  final _medName = TextEditingController();
  final _medDosage = TextEditingController();
  final _medForm = TextEditingController(text: 'Tablet');
  final _medTime = TextEditingController(text: '08:00');
  final _medMeal = TextEditingController();
  final _medStock = TextEditingController(text: '0');
  final _medAlert = TextEditingController(text: '5');
  PickedFile? _file;
  String? _uploadIntent;

  bool _sameAccount(AuthSession? current) =>
      current != null &&
      current.role == widget.session.role &&
      current.identifier == widget.session.identifier &&
      current.backendUserId == widget.session.backendUserId;

  bool get _sessionOpen =>
      !_expired &&
      (widget.sessionEndsAt == null ||
          ServerClock.now().isBefore(widget.sessionEndsAt!));

  bool get _ownsAccount =>
      mounted && _sessionOpen && _sameAccount(ref.read(currentSessionProvider));

  @override
  void initState() {
    super.initState();
    if (widget.openFiles) _section = 'files';
    _scheduleExpiry();
  }

  @override
  void didUpdateWidget(covariant ProfessionalChatTools oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionEndsAt != widget.sessionEndsAt) _scheduleExpiry();
  }

  void _scheduleExpiry() {
    _expiryTimer?.cancel();
    final end = widget.sessionEndsAt;
    _expired = end != null && !ServerClock.now().isBefore(end);
    if (end == null || _expired) return;
    _expiryTimer = Timer(end.difference(ServerClock.now()), () {
      if (!mounted) return;
      setState(() {
        _expired = true;
        _busy = false;
        _error = null;
        _retry = null;
      });
    });
  }

  String get _token {
    if (!_sessionOpen) throw const AuthFailure('Sesi berakhir.');
    final current = ref.read(currentSessionProvider);
    if (!_sameAccount(current)) {
      throw const AuthFailure(
          'Sesi telah berubah. Buka kembali chat dari akun aktif.');
    }
    final token = current?.accessToken;
    if (token == null || token.isEmpty)
      throw const AuthFailure('Sesi login berakhir. Silakan masuk kembali.');
    return token;
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    for (final controller in [
      _goalTitle,
      _goalTarget,
      _insight,
      _diagnosis,
      _medName,
      _medDosage,
      _medForm,
      _medTime,
      _medMeal,
      _medStock,
      _medAlert
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy || !_ownsAccount) return;
    setState(() {
      _busy = true;
      _error = null;
      _retry = action;
    });
    try {
      await action();
    } on Object catch (error) {
      if (_ownsAccount) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _select(String section) {
    setState(() {
      _section = section;
      _error = null;
      _retry = null;
    });
    if (section == 'goals' || section == 'summary') {
      setState(() => _goals = null);
      _run(_loadGoals);
    } else if (section == 'health') {
      setState(() {
        _health = null;
        _medications = null;
        _medicationError = null;
        _psychiatrist = false;
      });
      _run(_loadHealth);
    }
  }

  Future<void> _loadGoals() async {
    final goals = await widget.apiClient
        .listGoals(accessToken: _token, patientId: widget.patientId);
    if (!_ownsAccount) return;
    setState(() {
      _goals = goals.where((goal) => goal.isActive).toList();
      _selectedGoals.removeWhere((id) => !_goals!.any((goal) => goal.id == id));
    });
  }

  Future<void> _loadHealth() async {
    await Future.wait([_loadDiagnosis(), _loadMedications()]);
  }

  Future<void> _loadDiagnosis() async {
    if (_ownsAccount)
      setState(() {
        _health = null;
        _healthError = null;
      });
    try {
      final record = await widget.apiClient
          .getHealthRecord(accessToken: _token, patientId: widget.patientId);
      if (!_ownsAccount) return;
      setState(() {
        _health = record;
        _diagnosis.text = record.diagnosisSummary;
      });
    } on Object catch (error) {
      if (_ownsAccount) setState(() => _healthError = error);
    }
  }

  Future<void> _loadMedications() async {
    if (_ownsAccount) setState(() => _medicationError = null);
    try {
      final credentials =
          await widget.apiClient.getMyCredentials(accessToken: _token);
      final medications = await widget.apiClient
          .listMedications(accessToken: _token, patientId: widget.patientId);
      if (!_ownsAccount) return;
      setState(() {
        _psychiatrist = credentials != null &&
            isPsychiatristSpecialization(credentials.specialization) &&
            credentials.verificationStatus.toUpperCase() == 'VERIFIED';
        _medications = medications;
      });
    } on Object catch (error) {
      if (_ownsAccount)
        setState(() {
          _medicationError = error;
          _medications = null;
          _psychiatrist = false;
        });
    }
  }

  void _saveGoal() {
    final title = _goalTitle.text.trim();
    final target = int.tryParse(_goalTarget.text.trim());
    if (title.isEmpty || target == null || target < 1 || target > 7) {
      _invalid('Isi judul goal dan target 1–7 kali per minggu.');
      return;
    }
    final fingerprint = jsonEncode([title, target]);
    if (_goalFingerprint != fingerprint) {
      _goalFingerprint = fingerprint;
      _goalIntent = newClientIntentId();
    }
    final intent = _goalIntent!;
    _run(() async {
      final goal = await widget.apiClient.createGoal(
          accessToken: _token,
          patientId: widget.patientId,
          title: title,
          targetPerWeek: target,
          idempotencyKey: intent);
      if (!_ownsAccount) return;
      setState(() {
        _goals = [...?_goals?.where((item) => item.id != goal.id), goal];
        if (_selectedGoals.length < 20) _selectedGoals.add(goal.id);
        _goalTitle.clear();
        _goalFingerprint = null;
        _goalIntent = null;
      });
    });
  }

  void _sendCard(String kind, String text, Map<String, dynamic> metadata) {
    final fingerprint = jsonEncode([kind, text, metadata]);
    if (_cardFingerprint != fingerprint) {
      _cardFingerprint = fingerprint;
      _cardIntent = newClientIntentId();
    }
    final intent = _cardIntent!;
    _run(() async {
      final message = await widget.apiClient.sendChatMessage(
          accessToken: _token,
          recipientId: widget.patientId,
          text: text,
          kind: kind,
          metadata: metadata,
          clientMessageId: intent);
      if (!_ownsAccount) return;
      widget.onMessage(message);
      _cardFingerprint = null;
      _cardIntent = null;
      _notice('Pesan tersimpan di chat.');
      Navigator.of(context).maybePop();
    });
  }

  void _sendSummary() {
    final insight = _insight.text.trim();
    if ((_selectedGoals.isEmpty && insight.isEmpty) ||
        utf8.encode(insight).length > 2000) {
      _invalid(
          'Pilih goal atau isi insight singkat untuk pasien. Ringkas teks jika terlalu panjang.');
      return;
    }
    _sendCard('session_summary', 'Rangkuman sesi', {
      'session_id': widget.sessionId,
      'goal_ids': _selectedGoals.toList()..sort(),
      'insight': insight,
    });
  }

  void _notice(String text) {
    if (_ownsAccount)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _invalid(String message) {
    setState(() {
      _error = AuthFailure(message);
      _retry = null;
    });
  }

  Future<void> _pickFile() async {
    await _run(() async {
      final file = await ref.read(filePickerProvider).pick('file');
      if (file == null || !_ownsAccount) return;
      final name = file.name.toLowerCase();
      const extensions = ['.jpg', '.jpeg', '.png', '.webp', '.pdf'];
      if (file.size == 0 ||
          file.size > 10 * 1024 * 1024 ||
          !extensions.any(name.endsWith)) {
        throw const AuthFailure(
            'Pilih gambar JPEG, PNG, WebP atau PDF, maksimal 10 MiB.');
      }
      setState(() {
        _file = file;
        _uploadIntent = newClientIntentId();
      });
    });
  }

  void _upload() {
    final file = _file;
    if (file == null) return;
    final intent = _uploadIntent!;
    _run(() async {
      final message = await widget.apiClient.uploadChatAttachment(
          accessToken: _token,
          recipientId: widget.patientId,
          file: file,
          clientMessageId: intent);
      if (!_ownsAccount) return;
      widget.onMessage(message);
      setState(() {
        _file = null;
        _uploadIntent = null;
      });
      _notice('Berkas tersimpan di chat.');
      Navigator.of(context).maybePop();
    });
  }

  void _editMedication([BackendMedication? medication]) {
    setState(() {
      _editingMedication = medication;
      _showMedicationEditor = true;
      _medName.text = medication?.name ?? '';
      _medDosage.text = medication?.dosage ?? '';
      _medForm.text = medication?.form ?? 'Tablet';
      _medTime.text = medication?.reminderTime ?? '08:00';
      _medMeal.text = medication?.relationToMeal ?? '';
      _medStock.text = '${medication?.currentStock ?? 0}';
      _medAlert.text = '${medication?.alertBelow ?? 5}';
    });
  }

  void _saveMedication() {
    final stock = int.tryParse(_medStock.text),
        alert = int.tryParse(_medAlert.text);
    if (_medName.text.trim().isEmpty ||
        stock == null ||
        alert == null ||
        stock < 0 ||
        alert < 0) {
      _invalid('Isi nama obat serta stok dan batas pengingat yang valid.');
      return;
    }
    final current = _editingMedication;
    final name = _medName.text.trim(),
        dosage = _medDosage.text.trim(),
        form = _medForm.text.trim();
    final reminder = _medTime.text.trim(), meal = _medMeal.text.trim();
    final fingerprint =
        jsonEncode([name, dosage, form, reminder, meal, stock, alert]);
    if (current == null && _medicationFingerprint != fingerprint) {
      _medicationFingerprint = fingerprint;
      _medicationIntent = newClientIntentId();
    }
    final intent = _medicationIntent;
    _run(() async {
      final medication = current == null
          ? await widget.apiClient.createMedication(
              accessToken: _token,
              patientId: widget.patientId,
              name: name,
              dosage: dosage,
              form: form,
              reminderTime: reminder,
              relationToMeal: meal,
              currentStock: stock,
              alertBelow: alert,
              source: 'Profesional',
              idempotencyKey: intent)
          : await widget.apiClient.updateMedication(
              accessToken: _token,
              patientId: widget.patientId,
              medicationId: current.id,
              name: name,
              dosage: dosage,
              form: form,
              reminderTime: reminder,
              relationToMeal: meal,
              currentStock: stock,
              alertBelow: alert,
              source: current.source);
      if (!_ownsAccount) return;
      setState(() {
        _medications = [
          ...?_medications?.where((item) => item.id != medication.id),
          medication
        ];
        _showMedicationEditor = false;
        _medicationFingerprint = null;
        _medicationIntent = null;
      });
      _notice('Obat tersimpan.');
    });
  }

  Future<void> _deleteMedication(BackendMedication medication) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Hapus obat?'),
              content: Text(medication.name),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Batal')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Hapus')),
              ],
            ));
    if (confirmed != true || !_ownsAccount) return;
    await _run(() async {
      await widget.apiClient.deleteMedication(
          accessToken: _token,
          patientId: widget.patientId,
          medicationId: medication.id);
      if (_ownsAccount)
        setState(() => _medications =
            _medications?.where((item) => item.id != medication.id).toList());
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(currentSessionProvider);
    final allowed = _sessionOpen &&
        _sameAccount(current) &&
        widget.session.role == UserRole.professional &&
        widget.sessionId.isNotEmpty &&
        widget.patientId.isNotEmpty;
    return PopScope(
        canPop: !_busy,
        child: Scaffold(
          appBar: AppBar(
              backgroundColor: MalvaColors.seed,
              title: Text(switch (_section) {
                'goals' => 'Goals / Habits',
                'assessment' => 'Assessment',
                'health' => 'Health Record',
                'files' => 'Berkas',
                'summary' => 'Rangkuman sesi',
                _ => 'Alat sesi',
              }),
              leading: _section == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                                _section = null;
                                _error = null;
                              }))),
          body: !allowed
              ? Center(
                  child: Text(_sessionOpen
                      ? 'Alat profesional hanya tersedia pada sesi aktif.'
                      : 'Sesi berakhir'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_busy)
                      const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: LinearProgressIndicator()),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: FriendlyErrorCard(
                              error: _error!,
                              onRetry: () {
                                if (_busy) return;
                                final retry = _retry;
                                if (retry != null) {
                                  _run(retry);
                                } else {
                                  setState(() => _error = null);
                                }
                              })),
                    ...switch (_section) {
                      'goals' => _goalsPanel(false),
                      'assessment' => _assessmentPanel(),
                      'health' => _healthPanel(),
                      'files' => _filesPanel(),
                      'summary' => _goalsPanel(true),
                      _ => _menu(),
                    },
                  ],
                ),
        ));
  }

  List<Widget> _menu() => [
        for (final item in const [
          (
            'goals',
            'Goals / Habits',
            'Lihat progres dan buat tujuan pasien',
            Icons.task_alt
          ),
          (
            'assessment',
            'Assessment',
            'Kirim permintaan skrining, DASS-21, atau WHO-5',
            Icons.assignment_outlined
          ),
          (
            'health',
            'Health Record',
            'Perbarui diagnosis dan kelola obat',
            Icons.medical_information_outlined
          ),
          (
            'files',
            'Berkas',
            'Kirim gambar atau PDF ke chat',
            Icons.attach_file
          ),
          (
            'summary',
            'Rangkuman sesi',
            'Bagikan goals dan insight untuk pasien',
            Icons.summarize_outlined
          ),
        ])
          Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                  key: Key('tool-${item.$1}'),
                  leading: Icon(item.$4, color: MalvaColors.seed),
                  title: Text(item.$2),
                  subtitle: Text(item.$3),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _select(item.$1))),
      ];

  List<Widget> _goalsPanel(bool summary) {
    if (_goals == null) return [];
    return [
      Text(summary ? 'Pilih goals untuk rangkuman' : 'Goals dan progres pasien',
          style: Theme.of(context).textTheme.titleMedium),
      if (_goals!.isEmpty)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Belum ada goal aktif.')),
      for (final goal in _goals!)
        CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            key: Key('select-goal-${goal.id}'),
            value: _selectedGoals.contains(goal.id),
            title: Text(goal.title),
            subtitle: Text(
                '${goal.doneThisWeek}/${goal.targetPerWeek} kali minggu ini'),
            onChanged: _busy
                ? null
                : (selected) => setState(() {
                      if (selected == true && _selectedGoals.length < 20) {
                        _selectedGoals.add(goal.id);
                      } else {
                        _selectedGoals.remove(goal.id);
                      }
                    })),
      const SizedBox(height: 12),
      TextField(
          key: const Key('new-goal-title'),
          controller: _goalTitle,
          enabled: !_busy,
          maxLength: 200,
          decoration: const InputDecoration(labelText: 'Goal baru')),
      const SizedBox(height: 8),
      TextField(
          key: const Key('new-goal-target'),
          controller: _goalTarget,
          enabled: !_busy,
          keyboardType: TextInputType.number,
          decoration:
              const InputDecoration(labelText: 'Target per minggu (1–7)')),
      const SizedBox(height: 8),
      OutlinedButton.icon(
          key: const Key('save-goal'),
          onPressed: _busy ? null : _saveGoal,
          icon: const Icon(Icons.add),
          label: const Text('Simpan goal')),
      if (summary) ...[
        const SizedBox(height: 16),
        TextField(
            key: const Key('summary-insight'),
            controller: _insight,
            enabled: !_busy,
            maxLines: 4,
            maxLength: 2000,
            decoration:
                const InputDecoration(labelText: 'Insight untuk pasien')),
        const SizedBox(height: 12),
        FilledButton(
            key: const Key('send-summary'),
            onPressed: _busy ? null : _sendSummary,
            child: const Text('Kirim rangkuman')),
      ] else ...[
        const SizedBox(height: 12),
        FilledButton(
            onPressed: _busy || _selectedGoals.isEmpty
                ? null
                : () => _sendCard('goals', 'Goals untuk pasien', {
                      'session_id': widget.sessionId,
                      'goal_ids': _selectedGoals.toList()..sort()
                    }),
            child: const Text('Bagikan goals')),
      ],
    ];
  }

  List<Widget> _assessmentPanel() => [
        const Text(
            'Pilih asesmen yang perlu diisi pasien. Hasil tetap diperiksa dan dibagikan oleh pasien.'),
        const SizedBox(height: 12),
        for (final entry in const {
          'screening': 'Skrining PHQ-9 / GAD-7',
          'dass21': 'DASS-21',
          'who5': 'WHO-5'
        }.entries)
          ListTile(
              title: Text(entry.value),
              leading: Icon(_module == entry.key
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off),
              selected: _module == entry.key,
              onTap: _busy ? null : () => setState(() => _module = entry.key)),
        const SizedBox(height: 12),
        FilledButton(
            key: const Key('send-assessment'),
            onPressed: _busy
                ? null
                : () => _sendCard('assessment_request', 'Permintaan asesmen',
                    {'session_id': widget.sessionId, 'module_id': _module}),
            child: const Text('Kirim permintaan asesmen')),
      ];

  List<Widget> _filesPanel() => [
        const Text('Gambar JPEG, PNG, WebP atau PDF, maksimal 10 MiB.'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
            key: const Key('pick-chat-file'),
            onPressed: _busy ? null : _pickFile,
            icon: const Icon(Icons.attach_file),
            label: const Text('Pilih berkas')),
        if (_file != null) ...[
          Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child:
                  Text('${_file!.name} • ${(_file!.size / 1024).ceil()} KiB')),
          FilledButton(
              key: const Key('upload-chat-file'),
              onPressed: _busy ? null : _upload,
              child: const Text('Kirim berkas')),
        ],
      ];

  List<Widget> _healthPanel() {
    return [
      if (_healthError != null)
        FriendlyErrorCard(
            error: _healthError!,
            onRetry: () {
              if (!_busy) _run(_loadDiagnosis);
            }),
      if (_health != null) ...[
        TextField(
            key: const Key('diagnosis-summary'),
            controller: _diagnosis,
            enabled: !_busy,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'Diagnosis pasien')),
        const SizedBox(height: 12),
        FilledButton(
            key: const Key('save-diagnosis'),
            onPressed: _busy
                ? null
                : () {
                    final diagnosis = _diagnosis.text.trim();
                    _run(() async {
                      final record = await widget.apiClient
                          .updateHealthRecordDiagnosis(
                              accessToken: _token,
                              patientId: widget.patientId,
                              diagnosisSummary: diagnosis);
                      if (_ownsAccount) {
                        setState(() => _health = record);
                        _notice('Diagnosis tersimpan.');
                      }
                    });
                  },
            child: const Text('Simpan diagnosis')),
      ],
      const SizedBox(height: 20),
      Text('Obat pasien', style: Theme.of(context).textTheme.titleMedium),
      if (_medicationError != null)
        FriendlyErrorCard(
            error: _medicationError!,
            onRetry: () {
              if (!_busy) _run(_loadMedications);
            }),
      if (!_psychiatrist)
        const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
                'Pengelolaan obat hanya tersedia untuk psikiater terverifikasi.')),
      for (final medication in _medications ?? <BackendMedication>[])
        Card(
            child: ListTile(
          title: Text(medication.name),
          subtitle: Text('${medication.dosage} • ${medication.reminderTime}'),
          trailing: !_psychiatrist
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                      key: Key('edit-medication-${medication.id}'),
                      tooltip: 'Ubah obat',
                      onPressed:
                          _busy ? null : () => _editMedication(medication),
                      icon: const Icon(Icons.edit_outlined)),
                  IconButton(
                      key: Key('delete-medication-${medication.id}'),
                      tooltip: 'Hapus obat',
                      onPressed:
                          _busy ? null : () => _deleteMedication(medication),
                      icon: const Icon(Icons.delete_outline)),
                ]),
        )),
      if (_psychiatrist)
        OutlinedButton.icon(
            key: const Key('add-medication'),
            onPressed: _busy ? null : () => _editMedication(),
            icon: const Icon(Icons.add),
            label: const Text('Tambah obat')),
      if (_psychiatrist && _showMedicationEditor) ...[
        for (final field in [
          ('medication-name', 'Nama obat', _medName),
          ('medication-dosage', 'Dosis', _medDosage),
          ('medication-form', 'Bentuk', _medForm),
          ('medication-time', 'Jam minum (WIB)', _medTime),
          ('medication-meal', 'Kaitan makan', _medMeal),
          ('medication-stock', 'Stok', _medStock),
          ('medication-alert', 'Batas pengingat stok', _medAlert),
        ])
          Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextField(
                  key: Key(field.$1),
                  controller: field.$3,
                  enabled: !_busy,
                  decoration: InputDecoration(labelText: field.$2))),
        const SizedBox(height: 12),
        FilledButton(
            key: const Key('save-medication'),
            onPressed: _busy ? null : _saveMedication,
            child: const Text('Simpan obat')),
        TextButton(
            onPressed: _busy
                ? null
                : () => setState(() => _showMedicationEditor = false),
            child: const Text('Batal')),
      ],
    ];
  }
}
