import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models.dart';
import '../../providers/providers.dart';
import '../../services/malva_api_client.dart';
import '../../time/wib.dart';
import '../../widgets/friendly_error.dart';
import 'prescription_widgets.dart';

class EPrescriptionEditorScreen extends ConsumerStatefulWidget {
  const EPrescriptionEditorScreen(
      {super.key,
      this.session,
      this.apiClient,
      required this.prescription,
      this.patientName = 'Pasien terhubung'});
  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final BackendEPrescription prescription;
  final String patientName;
  @override
  ConsumerState<EPrescriptionEditorScreen> createState() =>
      _PrescriptionEditorState();
}

class _DrugDraft {
  _DrugDraft([BackendEPrescriptionItem? item])
      : original = item,
        routineEnabled = item == null || item.schedule != null,
        name = TextEditingController(text: item?.name ?? ''),
        dosage = TextEditingController(text: item?.dosage ?? ''),
        frequency = TextEditingController(text: item?.frequency ?? '1x sehari'),
        quantity =
            TextEditingController(text: (item?.currentStock ?? 30).toString()),
        unit = TextEditingController(text: item?.unit ?? 'mg'),
        instructions =
            TextEditingController(text: item?.schedule?.instructions ?? ''),
        meal = item?.schedule?.relationToMeal ?? 'Sesudah makan',
        form = item?.form ?? 'Tablet',
        routine = item?.schedule?.toJson() ??
            {
              'times': ['08:00'],
              'weekdays': [1, 2, 3, 4, 5, 6, 7],
              'start_at': wibIso(wibNow()),
              'interval_hours': 0,
              'interval_days': 0,
              'units_per_dose': 1,
              'refill_enabled': true
            },
        threshold =
            TextEditingController(text: (item?.alertBelow ?? 3).toString());
  final BackendEPrescriptionItem? original;
  final TextEditingController name,
      dosage,
      frequency,
      quantity,
      unit,
      instructions,
      threshold;
  String meal, form;
  bool routineEnabled;
  Map<String, dynamic> routine;
  void dispose() {
    for (final c in [
      name,
      dosage,
      frequency,
      quantity,
      unit,
      instructions,
      threshold
    ]) {
      c.dispose();
    }
  }

  BackendEPrescriptionItem item() => BackendEPrescriptionItem(
      id: original?.id ?? '',
      medicationId: original?.medicationId,
      name: name.text.trim(),
      dosage: dosage.text.trim(),
      frequency: frequency.text.trim(),
      currentStock: int.parse(quantity.text),
      alertBelow: int.parse(threshold.text),
      unit: unit.text.trim(),
      form: form,
      days: original?.days ?? 30,
      unitsPerDay: routineEnabled
          ? (routine['times'] as List).length *
              (routine['units_per_dose'] as num).toInt()
          : original?.unitsPerDay ?? 1,
      schedule: !routineEnabled
          ? null
          : MedicationSchedule.fromJson({
              ...routine,
              'relation_to_meal': meal,
              'instructions': instructions.text.trim()
            }));
}

class _PrescriptionEditorState
    extends ConsumerState<EPrescriptionEditorScreen> {
  final _form = GlobalKey<FormState>();
  final _diagnosis = TextEditingController();
  final _notes = TextEditingController();
  final _instructions = TextEditingController();
  late final PrescriptionAccountGuard _account;
  List<_DrugDraft> _drugs = [];
  BackendEPrescription? _rx;
  String _status = 'issued';
  bool _loading = true, _saving = false;
  String? _error;
  AuthSession? get _session =>
      _account.session(ref.read(authStateProvider).session);
  @override
  void initState() {
    super.initState();
    _account = PrescriptionAccountGuard(
        widget.session, ref.read(authStateProvider).session);
    _load();
  }

  @override
  void dispose() {
    for (final c in [_diagnosis, _notes, _instructions]) {
      c.dispose();
    }
    for (final d in _drugs) {
      d.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final token = _session?.accessToken;
    final api = widget.apiClient;
    if (token == null || api == null) {
      setState(() {
        _loading = false;
        _error = 'Hubungkan ke server untuk mengubah resep.';
      });
      return;
    }
    try {
      final rx = await api.getEPrescription(
          accessToken: token, prescriptionId: widget.prescription.id);
      if (!mounted || _session == null) return;
      setState(() {
        _rx = rx;
        _diagnosis.text = rx.diagnosis;
        _notes.text = rx.notes;
        _instructions.text = rx.instructions;
        _status = rx.status == 'draft' ? 'draft' : 'issued';
        _drugs = rx.items.map(_DrugDraft.new).toList();
        if (_drugs.isEmpty) _drugs.add(_DrugDraft());
        _loading = false;
      });
    } on Object catch (e) {
      if (mounted && _session != null)
        setState(() {
          _loading = false;
          _error = friendlyErrorMessage(e);
        });
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final session = _session;
    final api = widget.apiClient;
    final rx = _rx;
    if (session?.accessToken == null || api == null || rx == null) return;
    if (_drugs.any(
        (d) => d.routineEnabled && (d.routine['weekdays'] as List).isEmpty)) {
      setState(() => _error = 'Pilih minimal satu hari pada setiap obat.');
      return;
    }
    if (_drugs.any((d) =>
        d.routineEnabled &&
        (d.routine['times'] as List).toSet().length !=
            (d.routine['times'] as List).length)) {
      setState(() => _error = 'Waktu minum setiap obat harus berbeda.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await api.updateEPrescription(
          accessToken: session!.accessToken!,
          prescriptionId: rx.id,
          patientId: rx.patientId,
          items: _drugs.map((d) => d.item()).toList(),
          notes: _notes.text.trim(),
          instructions: _instructions.text.trim(),
          diagnosis: _diagnosis.text.trim(),
          status: _status);
      if (mounted && _session != null) Navigator.pop(context, true);
    } on Object catch (e) {
      if (mounted && _session != null)
        setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  InputDecoration _dec(String text) => InputDecoration(
      labelText: text,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xffdedfe6))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xffdedfe6))));
  @override
  Widget build(BuildContext context) {
    final valid = _account.current(ref.watch(authStateProvider).session);
    return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
            title: const Text('Edit E-Prescription',
                style: TextStyle(
                    fontFamily: 'Roboto', fontWeight: FontWeight.w800)),
            toolbarHeight: 76,
            backgroundColor: prescriptionPurple,
            foregroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.vertical(bottom: Radius.circular(24)))),
        bottomNavigationBar: valid && !_loading && _rx != null
            ? SafeArea(
                child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          OutlinedButton(
                              onPressed:
                                  _saving ? null : () => Navigator.pop(context),
                              child: const Text('Batal')),
                          FilledButton.icon(
                              onPressed: _saving ? null : _save,
                              icon: _saving
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2, color: Colors.white))
                                  : const Icon(Icons.check),
                              label: Text(_saving
                                  ? 'Menyimpan...'
                                  : 'Simpan Perubahan'),
                              style: FilledButton.styleFrom(
                                  backgroundColor: prescriptionPurple,
                                  minimumSize: const Size(0, 50),
                                  textStyle: const TextStyle(
                                      fontFamily: 'Roboto',
                                      fontWeight: FontWeight.w700)))
                        ])))
            : null,
        body: !valid
            ? const Center(
                child: Text('Sesi akun berubah. Buka kembali halaman resep.'))
            : _loading
                ? const Center(child: CircularProgressIndicator())
                : _rx == null
                    ? Center(child: Text(_error ?? 'Resep tidak ditemukan.'))
                    : Form(
                        key: _form,
                        child: ListView(
                            padding: const EdgeInsets.fromLTRB(18, 24, 18, 35),
                            children: [
                              PrescriptionPanel(
                                  color: const Color(0xfff8f9fb),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        TextFormField(
                                            initialValue: widget.patientName,
                                            readOnly: true,
                                            decoration: _dec('Nama Pasien')),
                                        const SizedBox(height: 18),
                                        DropdownButtonFormField<String>(
                                            initialValue: _status,
                                            isExpanded: true,
                                            decoration:
                                                _dec('Status Penerbitan'),
                                            items: const [
                                              DropdownMenuItem(
                                                  value: 'issued',
                                                  child: Text(
                                                      'Issued • QR + signature')),
                                              DropdownMenuItem(
                                                  value: 'draft',
                                                  child: Text(
                                                      'Draft • belum dikirim'))
                                            ],
                                            onChanged: _saving
                                                ? null
                                                : (v) => setState(
                                                    () => _status = v!)),
                                        const SizedBox(height: 18),
                                        TextFormField(
                                            controller: _diagnosis,
                                            decoration: _dec(
                                                'Diagnosis ICD-10 / Indikasi'),
                                            maxLines: 2)
                                      ])),
                              const SizedBox(height: 24),
                              Row(children: [
                                Expanded(
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                      Text(
                                          'Daftar Obat (${_drugs.length} item)',
                                          style: const TextStyle(
                                              fontSize: 18,
                                              fontWeight: FontWeight.w800)),
                                      const SizedBox(height: 5),
                                      const Text(
                                          'Semua obat digabung dalam satu kartu resep.',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: Color(0xff7c8794)))
                                    ])),
                                const SizedBox(width: 10),
                                FilledButton.tonalIcon(
                                    style: FilledButton.styleFrom(
                                        minimumSize: const Size(0, 48),
                                        textStyle: const TextStyle(
                                            fontFamily: 'Roboto',
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700)),
                                    onPressed: _saving
                                        ? null
                                        : () => setState(
                                            () => _drugs.add(_DrugDraft())),
                                    icon: const Icon(Icons.add),
                                    label: const Text('Tambah Obat'))
                              ]),
                              const SizedBox(height: 16),
                              for (var i = 0; i < _drugs.length; i++) ...[
                                _DrugEditor(
                                    key: ObjectKey(_drugs[i]),
                                    draft: _drugs[i],
                                    index: i + 1,
                                    decoration: _dec,
                                    canDelete: _drugs.length > 1,
                                    onDelete: _saving
                                        ? null
                                        : () {
                                            final removed = _drugs[i];
                                            setState(() => _drugs.removeAt(i));
                                            WidgetsBinding.instance
                                                .addPostFrameCallback((_) {
                                              removed.dispose();
                                            });
                                          }),
                                const SizedBox(height: 16)
                              ],
                              TextFormField(
                                  controller: _instructions,
                                  decoration:
                                      _dec('Instruksi umum resep (opsional)'),
                                  maxLines: 2),
                              const SizedBox(height: 16),
                              TextFormField(
                                  controller: _notes,
                                  decoration: _dec(
                                      'Catatan Klinis Tambahan (opsional)'),
                                  maxLines: 3),
                              if (_error != null)
                                Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Text(_error!,
                                        style: TextStyle(
                                            color: Colors.red.shade700))),
                              const SizedBox(height: 24),
                            ])));
  }
}

class _DrugEditor extends StatefulWidget {
  const _DrugEditor(
      {super.key,
      required this.draft,
      required this.index,
      required this.decoration,
      required this.canDelete,
      this.onDelete});
  final _DrugDraft draft;
  final int index;
  final InputDecoration Function(String) decoration;
  final bool canDelete;
  final VoidCallback? onDelete;
  @override
  State<_DrugEditor> createState() => _DrugEditorState();
}

class _DrugEditorState extends State<_DrugEditor> {
  _DrugDraft get d => widget.draft;
  InputDecoration _dec(String s) => widget.decoration(s);
  List<String> get _times => (d.routine['times'] as List).cast<String>();
  List<int> get _days => (d.routine['weekdays'] as List).cast<int>();
  String? _required(String? value) =>
      value?.trim().isEmpty != false ? 'Wajib diisi' : null;
  String? _quantity(String? value) {
    final n = int.tryParse(value ?? '');
    return n == null || n < 0 || (d.original == null && n == 0)
        ? 'Jumlah tidak valid'
        : null;
  }

  Future<void> _pickTime(int index) async {
    final raw = _times[index].split(':');
    final t = await showTimePicker(
        context: context,
        initialTime:
            TimeOfDay(hour: int.parse(raw[0]), minute: int.parse(raw[1])),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!));
    if (t != null && mounted)
      setState(() {
        final times = [..._times];
        times[index] =
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
        d.routine['times'] = times;
      });
  }

  @override
  Widget build(BuildContext context) {
    final start = parseWibStored(d.routine['start_at']?.toString()) ?? wibNow();
    return PrescriptionPanel(
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
                color: prescriptionPurple,
                borderRadius: BorderRadius.circular(8)),
            child: Text('Obat #${widget.index}',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w700))),
        const Spacer(),
        if (widget.canDelete)
          IconButton(
              tooltip: 'Hapus obat ${widget.index}',
              onPressed: widget.onDelete,
              icon: const Icon(Icons.delete_outline))
      ]),
      const SizedBox(height: 20),
      TextFormField(
          controller: d.name,
          validator: _required,
          decoration: _dec('Nama Obat *')),
      const SizedBox(height: 14),
      TextFormField(
          controller: d.dosage,
          validator: (value) {
            if (!d.routineEnabled) return _required(value);
            final dose = double.tryParse(
                (value ?? '').trim().split(' ').first.replaceAll(',', '.'));
            return dose == null || !dose.isFinite || dose <= 0 || dose > 1e9
                ? 'Dosis harus lebih dari 0.'
                : null;
          },
          decoration: _dec('Dosis / Kekuatan')),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
            child: TextFormField(
                controller: d.frequency,
                validator: _required,
                decoration: _dec('Signa (Frekuensi)'))),
        const SizedBox(width: 10),
        Expanded(
            child: DropdownButtonFormField<String>(
                initialValue: d.form,
                isExpanded: true,
                decoration: _dec('Bentuk'),
                items: [
                  for (final f in {
                    'Tablet',
                    'Kapsul',
                    'Sirup',
                    'Injeksi',
                    d.form
                  })
                    DropdownMenuItem(value: f, child: Text(f))
                ],
                onChanged: (v) => setState(() => d.form = v!)))
      ]),
      const SizedBox(height: 14),
      DropdownButtonFormField<String>(
          initialValue: d.meal,
          isExpanded: true,
          decoration: _dec('Waktu Konsumsi'),
          items: [
            for (final m in {
              'Sesudah makan',
              'Sebelum makan',
              'Sebelum tidur',
              'Bersama makan',
              '',
              d.meal
            })
              DropdownMenuItem(
                  value: m, child: Text(m.isEmpty ? 'Tidak ditentukan' : m))
          ],
          onChanged:
              !d.routineEnabled ? null : (v) => setState(() => d.meal = v!)),
      const SizedBox(height: 14),
      Row(children: [
        Expanded(
            child: TextFormField(
                controller: d.quantity,
                validator: _quantity,
                keyboardType: TextInputType.number,
                decoration: _dec('Jumlah diberikan'))),
        const SizedBox(width: 10),
        Expanded(
            child: DropdownButtonFormField<String>(
                initialValue: d.unit.text,
                isExpanded: true,
                decoration: _dec('Satuan dosis'),
                items: [
                  for (final unit in {
                    'mg',
                    'mcg',
                    'g',
                    'ml',
                    'IU',
                    d.unit.text
                  })
                    DropdownMenuItem(value: unit, child: Text(unit))
                ],
                validator: (v) => d.routineEnabled &&
                        !{'mg', 'mcg', 'g', 'ml', 'IU'}.contains(v)
                    ? 'Pilih satuan dosis'
                    : null,
                onChanged: (v) => setState(() => d.unit.text = v!)))
      ]),
      const SizedBox(height: 7),
      if (d.original?.remainingStock != null)
        Text(
            'Sisa stok pasien: ${d.original!.remainingStock}. Jumlah diberikan tetap ${d.original!.currentStock}; dosis yang sudah diminum tetap dihitung.',
            style: const TextStyle(fontSize: 12, color: Color(0xff7c8794))),
      const SizedBox(height: 14),
      TextFormField(
          controller: d.instructions,
          enabled: d.routineEnabled,
          decoration: _dec('Instruksi Khusus Obat (opsional)'),
          maxLines: 2),
      const SizedBox(height: 10),
      if (!d.routineEnabled)
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Atur rutinitas & pengingat'),
            subtitle: const Text('Obat ini belum memiliki jadwal pengingat.'),
            value: false,
            onChanged: (v) => setState(() => d.routineEnabled = v)),
      if (d.routineEnabled)
        ExpansionTile(
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(top: 12),
            title: const Text('Rutinitas & Pengingat Pasien',
                style: TextStyle(
                    color: prescriptionPurple,
                    fontWeight: FontWeight.w700,
                    fontSize: 14)),
            subtitle: Text(MedicationSchedule.fromJson(d.routine).label,
                style: const TextStyle(fontSize: 12)),
            children: [
              DropdownButtonFormField<int>(
                  initialValue: _times.length,
                  isExpanded: true,
                  decoration: _dec('Jumlah waktu minum'),
                  items: [
                    for (var c = 1; c <= 10; c++)
                      DropdownMenuItem(value: c, child: Text('$c kali'))
                  ],
                  onChanged: (n) => setState(() {
                        final times = [..._times];
                        while (times.length > n!) {
                          times.removeLast();
                        }
                        while (times.length < n) {
                          var hour = (8 + times.length * 2) % 24;
                          while (times.contains(
                              '${hour.toString().padLeft(2, '0')}:00')) {
                            hour = (hour + 1) % 24;
                          }
                          times.add('${hour.toString().padLeft(2, '0')}:00');
                        }
                        d.routine['times'] = times;
                      })),
              const SizedBox(height: 12),
              for (var i = 0; i < _times.length; i++)
                Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: OutlinedButton.icon(
                        onPressed: () => _pickTime(i),
                        icon: const Icon(Icons.schedule),
                        label: Text('${_times[i]} WIB'))),
              Wrap(spacing: 5, children: [
                for (var day = 1; day <= 7; day++)
                  FilterChip(
                      label: Text(const [
                        'Sen',
                        'Sel',
                        'Rab',
                        'Kam',
                        'Jum',
                        'Sab',
                        'Min'
                      ][day - 1]),
                      selected: _days.contains(day),
                      onSelected: (v) => setState(() {
                            final days = [..._days];
                            if (v) {
                              days.add(day);
                            } else {
                              days.remove(day);
                            }
                            d.routine['weekdays'] = days..sort();
                          }))
              ]),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: (d.routine['interval_hours'] as num? ?? 0) > 0
                      ? 'hours'
                      : (d.routine['interval_days'] as num? ?? 0) > 1
                          ? 'days'
                          : 'daily',
                  decoration: _dec('Pola pengulangan'),
                  items: const [
                    DropdownMenuItem(
                        value: 'daily', child: Text('Hari terpilih')),
                    DropdownMenuItem(
                        value: 'hours', child: Text('Setiap beberapa jam')),
                    DropdownMenuItem(
                        value: 'days', child: Text('Setiap beberapa hari'))
                  ],
                  onChanged: (v) => setState(() {
                        d.routine['interval_hours'] = v == 'hours' ? 8 : 0;
                        d.routine['interval_days'] = v == 'days' ? 2 : 0;
                      })),
              if ((d.routine['interval_hours'] as num? ?? 0) > 0 ||
                  (d.routine['interval_days'] as num? ?? 0) > 1)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: TextFormField(
                        key: ValueKey(
                            'interval-${d.routine['interval_hours']}-${d.routine['interval_days']}'),
                        initialValue:
                            ((d.routine['interval_hours'] as num? ?? 0) > 0
                                    ? d.routine['interval_hours']
                                    : d.routine['interval_days'])
                                .toString(),
                        keyboardType: TextInputType.number,
                        decoration: _dec(
                            (d.routine['interval_hours'] as num? ?? 0) > 0
                                ? 'Interval jam'
                                : 'Interval hari'),
                        validator: (v) {
                          final n = int.tryParse(v ?? '') ?? 0;
                          return n < 1 ||
                                  n >
                                      ((d.routine['interval_hours'] as num? ??
                                                  0) >
                                              0
                                          ? 168
                                          : 365)
                              ? 'Interval tidak valid'
                              : null;
                        },
                        onChanged: (v) {
                          d.routine[
                              (d.routine['interval_hours'] as num? ?? 0) > 0
                                  ? 'interval_hours'
                                  : 'interval_days'] = int.tryParse(v) ?? 0;
                        })),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('Mulai ${formatWibDateTime(start)} WIB'),
                  onPressed: () async {
                    final now = wibNow();
                    final date = await showDatePicker(
                        context: context,
                        initialDate: start,
                        firstDate: wibFromParts(2000, 1, 1),
                        lastDate: wibFromParts(now.year + 5, 12, 31));
                    if (date == null || !context.mounted) return;
                    final time = await showTimePicker(
                        context: context,
                        initialTime:
                            TimeOfDay(hour: start.hour, minute: start.minute));
                    if (time != null && mounted)
                      setState(() => d.routine['start_at'] = wibIso(
                          wibFromParts(date.year, date.month, date.day,
                              time.hour, time.minute)));
                  }),
              const SizedBox(height: 12),
              TextFormField(
                  initialValue: (d.routine['units_per_dose'] ?? 1).toString(),
                  keyboardType: TextInputType.number,
                  decoration: _dec('Unit per dosis'),
                  validator: (v) {
                    final n = int.tryParse(v ?? '') ?? 0;
                    return n < 1 || n > 1000 ? 'Jumlah tidak valid' : null;
                  },
                  onChanged: (v) =>
                      d.routine['units_per_dose'] = int.tryParse(v) ?? 0),
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pengingat isi ulang'),
                  value: d.routine['refill_enabled'] != false,
                  onChanged: (v) =>
                      setState(() => d.routine['refill_enabled'] = v)),
              TextFormField(
                  controller: d.threshold,
                  keyboardType: TextInputType.number,
                  decoration: _dec('Ingatkan jika sisa stok ≤'),
                  validator: (v) => (int.tryParse(v ?? '') ?? -1) < 0
                      ? 'Batas tidak valid'
                      : null),
              const SizedBox(height: 12),
            ]),
    ]));
  }
}
