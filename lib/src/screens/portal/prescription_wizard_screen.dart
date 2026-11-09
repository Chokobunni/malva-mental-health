import 'package:flutter/material.dart';

import '../../models.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../time/wib.dart';
import '../../widgets/friendly_error.dart';

/// One medicine, three steps: clinical detail, routine, and patient reminders.
class EPrescriptionFormScreen extends StatefulWidget {
  const EPrescriptionFormScreen(
      {super.key,
      this.session,
      this.apiClient,
      this.links = const [],
      this.preselectedPatientId = '',
      this.preselectedPatientName = '',
      this.onCreated});
  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final List<BackendPatientProfessionalLink> links;
  final String preselectedPatientId;
  final String preselectedPatientName;
  final VoidCallback? onCreated;
  @override
  State<EPrescriptionFormScreen> createState() => _PrescriptionWizardState();
}

class _PrescriptionWizardState extends State<EPrescriptionFormScreen> {
  static const _purple = Color(0xff9346a4);
  final _name = TextEditingController();
  final _dose = TextEditingController();
  final _notes = TextEditingController();
  final _stock = TextEditingController(text: '30');
  final _units = TextEditingController(text: '1');
  final _threshold = TextEditingController(text: '3');
  final _interval = TextEditingController(text: '8');
  final _scroll = ScrollController();
  int _step = 0;
  String? _patientId;
  String _form = 'Tablet';
  String _unit = 'mg';
  String _frequency = '1x sehari';
  String _intervalUnit = 'jam';
  bool _periodic = false;
  bool _refill = true;
  bool _saving = false;
  String? _error;
  DateTime _start = wibNow();
  TimeOfDay _startTime = const TimeOfDay(hour: 8, minute: 0);
  final List<TimeOfDay> _times = [const TimeOfDay(hour: 8, minute: 0)];
  final Set<int> _weekdays = {1, 2, 3, 4, 5, 6, 7};
  @override
  void initState() {
    super.initState();
    if (widget.preselectedPatientId.isNotEmpty)
      _patientId = widget.preselectedPatientId;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _dose,
      _notes,
      _stock,
      _units,
      _threshold,
      _interval
    ]) {
      c.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  void _go(int step) {
    setState(() {
      _step = step;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  String _timeLabel(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  Widget _label(String s) => Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 10),
      child: Text(s,
          style: const TextStyle(
              fontWeight: FontWeight.w700,
              color: Color(0xff56616d),
              fontSize: 15)));
  InputDecoration _decoration(String label, {String? hint}) => InputDecoration(
      labelText: label,
      hintText: hint,
      filled: true,
      fillColor: const Color(0xfff8f9fb),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xffe4e5e8))),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xffe4e5e8))),
      contentPadding: const EdgeInsets.all(18));
  Widget _number(TextEditingController controller, String label,
          {bool decimal = false}) =>
      TextField(
          controller: controller,
          keyboardType: TextInputType.numberWithOptions(decimal: decimal),
          decoration: _decoration(label));
  Widget _choice(String label, bool selected, VoidCallback onTap,
          {IconData? icon}) =>
      OutlinedButton.icon(
          onPressed: onTap,
          icon: Icon(
              icon ??
                  (selected
                      ? Icons.check_circle_outline
                      : Icons.circle_outlined),
              size: 20),
          label: Text(label),
          style: OutlinedButton.styleFrom(
              foregroundColor: selected ? _purple : const Color(0xff697480),
              backgroundColor:
                  selected ? const Color(0xfffcf5ff) : const Color(0xfff8f9fb),
              side: BorderSide(
                  color: selected ? _purple : const Color(0xffe9eaed),
                  width: selected ? 2 : 1),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15))));
  Widget _summary() => Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
          color: const Color(0xfffcf5ff),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _purple.withValues(alpha: .25))),
      child: Row(children: [
        const Icon(Icons.medication_rounded, color: _purple, size: 32),
        const SizedBox(width: 14),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_name.text,
              style:
                  const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          Text('${_dose.text} ${_unit.toUpperCase()} • $_form'),
          if (_notes.text.isNotEmpty) Text(_notes.text)
        ])),
        IconButton(
            onPressed: () => _go(0),
            tooltip: 'Edit detail obat',
            icon: const Icon(Icons.edit_outlined, color: _purple))
      ]));
  @override
  Widget build(BuildContext context) {
    final titles = ['Detail Obat', 'Atur Rutinitas', 'Atur Pengingat'];
    return PopScope(
        canPop: _step == 0 && !_saving,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && !_saving && _step > 0) _go(_step - 1);
        },
        child: Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
                title: Text(titles[_step],
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontFamily: 'Roboto')),
                centerTitle: true,
                toolbarHeight: 88,
                backgroundColor: _purple,
                foregroundColor: Colors.white,
                shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(bottom: Radius.circular(30))),
                leading: IconButton(
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: _saving
                        ? null
                        : () {
                            if (_step > 0) {
                              _go(_step - 1);
                            } else {
                              Navigator.maybePop(context);
                            }
                          })),
            body: SafeArea(
                child: ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(24, 24, 24, 30),
                    children: [
                  Row(children: [
                    for (var i = 0; i < 3; i++)
                      Expanded(
                          child: Container(
                              height: 4,
                              margin: const EdgeInsets.symmetric(horizontal: 3),
                              decoration: BoxDecoration(
                                  color: i <= _step
                                      ? _purple
                                      : const Color(0xffece8ef),
                                  borderRadius: BorderRadius.circular(4))))
                  ]),
                  const SizedBox(height: 24),
                  Text(
                      [
                        'Obat apa yang ingin kamu resepkan?',
                        'Kapan pasien perlu minum obat?',
                        'Siapkan pengingat untuk pasien'
                      ][_step],
                      style: const TextStyle(
                          fontSize: 26,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: Color(0xff242f39))),
                  if (_step == 0)
                    ..._details()
                  else if (_step == 1)
                    ..._routine()
                  else
                    ..._reminders(),
                  if (_error != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 18),
                        child: Text(_error!,
                            style: const TextStyle(
                                color: MalvaColors.danger,
                                fontWeight: FontWeight.w700))),
                  const SizedBox(height: 32),
                  FilledButton(
                      onPressed: _saving ? null : _next,
                      style: FilledButton.styleFrom(
                          backgroundColor: _purple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 20),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16))),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_saving)
                              const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                            else
                              Flexible(
                                  child: Text(
                                      [
                                        'Atur Jadwal Minum Obat Pasien',
                                        'Lanjut Atur Pengingat',
                                        'Simpan dan Kirim Resep'
                                      ][_step],
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          fontSize: 16,
                                          fontFamily: 'Roboto'))),
                            if (!_saving) ...[
                              const SizedBox(width: 8),
                              const Icon(Icons.arrow_forward_rounded)
                            ]
                          ])),
                ]))));
  }

  List<Widget> _details() {
    final patients = {
      for (final link in widget.links)
        link.patientId: link.patientDisplayName.isEmpty
            ? 'Pasien terhubung'
            : link.patientDisplayName
    };
    if (widget.preselectedPatientId.isNotEmpty)
      patients.putIfAbsent(
          widget.preselectedPatientId,
          () => widget.preselectedPatientName.isEmpty
              ? 'Pasien terpilih'
              : widget.preselectedPatientName);
    return [
      _label('Pasien'),
      DropdownButtonFormField<String>(
          initialValue: _patientId,
          decoration: _decoration('Pilih pasien'),
          items: [
            for (final p in patients.entries)
              DropdownMenuItem(
                  value: p.key,
                  child: Text(p.value, overflow: TextOverflow.ellipsis))
          ],
          onChanged: _saving ? null : (v) => setState(() => _patientId = v)),
      if (patients.isEmpty) const Text('Belum ada pasien terhubung.'),
      _label('Nama Obat'),
      TextField(
          controller: _name,
          decoration: _decoration('Nama obat',
              hint: 'Contoh: Aripiprazole, Paracetamol')),
      _label('Bentuk Obat'),
      LayoutBuilder(
          builder: (context, c) => Wrap(spacing: 10, runSpacing: 10, children: [
                for (final form in [
                  ('Tablet', Icons.medication_rounded),
                  ('Kapsul', Icons.medication_outlined),
                  ('Sirup', Icons.medication_liquid_outlined),
                  ('Injeksi', Icons.vaccines_outlined)
                ])
                  SizedBox(
                      width: (c.maxWidth - 10) / 2,
                      child: _choice(form.$1, _form == form.$1,
                          () => setState(() => _form = form.$1),
                          icon: form.$2))
              ])),
      _label('Dosis per minum'),
      Row(children: [
        Expanded(
            flex: 2, child: _number(_dose, 'Dosis per minum', decimal: true)),
        const SizedBox(width: 12),
        Expanded(
            child: DropdownButtonFormField<String>(
                initialValue: _unit,
                decoration: _decoration('Satuan'),
                items: [
                  for (final u in ['mg', 'mcg', 'g', 'ml', 'IU'])
                    DropdownMenuItem(value: u, child: Text(u.toUpperCase()))
                ],
                onChanged: (v) => setState(() => _unit = v!)))
      ]),
      _label('Stok obat yang diberikan'),
      _number(_stock, 'Jumlah stok'),
      _label('Catatan (opsional)'),
      TextField(
          controller: _notes,
          maxLines: 3,
          decoration:
              _decoration('Catatan', hint: 'Contoh: Diminum sesudah makan...')),
    ];
  }

  void _setCount(int count) {
    final first = _times.first;
    setState(() {
      _times.clear();
      for (var i = 0; i < count; i++)
        _times.add(TimeOfDay(
            hour: (first.hour +
                    (count == 1 ? 0 : (i * 12 / (count - 1)).round())) %
                24,
            minute: first.minute));
    });
  }

  List<Widget> _routine() => [
        const SizedBox(height: 22),
        _summary(),
        _label('Frekuensi minum obat'),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final f in ['1x sehari', '2x sehari', '3x sehari', 'Fleksibel'])
            _choice(f, _frequency == f, () {
              setState(() => _frequency = f);
              if (f != 'Fleksibel') _setCount(int.parse(f.substring(0, 1)));
            })
        ]),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeTrackColor: _purple,
            title: const Text('Jadwal berkala khusus',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Setiap beberapa jam atau hari'),
            value: _periodic,
            onChanged: (v) => setState(() => _periodic = v)),
        if (_periodic) ...[
          Row(children: [
            Expanded(child: _number(_interval, 'Setiap')),
            const SizedBox(width: 12),
            Expanded(
                child: DropdownButtonFormField<String>(
                    initialValue: _intervalUnit,
                    decoration: _decoration('Interval'),
                    items: [
                      for (final u in ['jam', 'hari'])
                        DropdownMenuItem(value: u, child: Text(u))
                    ],
                    onChanged: (v) => setState(() => _intervalUnit = v!)))
          ]),
          const SizedBox(height: 12),
          const Text(
              'Interval dihitung dari tanggal dan jam mulai. Hari yang tidak dipilih dilewati.')
        ],
        if (_frequency == 'Fleksibel' &&
            !(_periodic && _intervalUnit == 'jam')) ...[
          _label('Jumlah waktu minum per hari'),
          DropdownButtonFormField<int>(
              initialValue: _times.length,
              decoration: _decoration('Jumlah waktu'),
              items: [
                for (var i = 1; i <= 10; i++)
                  DropdownMenuItem(value: i, child: Text('$i kali'))
              ],
              onChanged: (v) => _setCount(v!))
        ],
        _label(_periodic && _intervalUnit == 'jam'
            ? 'Jam pertama diatur pada langkah berikutnya'
            : 'Jam minum obat (WIB)'),
        if (!(_periodic && _intervalUnit == 'jam'))
          for (var i = 0; i < _times.length; i++)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: OutlinedButton.icon(
                    icon: const Icon(Icons.access_time),
                    label:
                        Text('Minum ${i + 1} • ${_timeLabel(_times[i])} WIB'),
                    onPressed: () async {
                      final t = await showTimePicker(
                          context: context,
                          initialTime: _times[i],
                          builder: (context, child) => MediaQuery(
                              data: MediaQuery.of(context)
                                  .copyWith(alwaysUse24HourFormat: true),
                              child: child!));
                      if (t != null && mounted) setState(() => _times[i] = t);
                    })),
        _label('Hari minum obat'),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var d = 1; d <= 7; d++)
            FilterChip(
                label: Text(const [
                  'Sen',
                  'Sel',
                  'Rab',
                  'Kam',
                  'Jum',
                  'Sab',
                  'Min'
                ][d - 1]),
                selected: _weekdays.contains(d),
                selectedColor: _purple.withValues(alpha: .15),
                onSelected: (v) => setState(() {
                      if (v) {
                        _weekdays.add(d);
                      } else {
                        _weekdays.remove(d);
                      }
                    }))
        ]),
      ];
  List<Widget> _reminders() => [
        const SizedBox(height: 22),
        _summary(),
        _label('Mulai pengingat'),
        OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(formatWibDate(_start)),
            onPressed: () async {
              final now = wibNow();
              final date = await showDatePicker(
                  context: context,
                  initialDate: _start,
                  firstDate: wibFromParts(now.year, now.month, now.day),
                  lastDate: wibFromParts(now.year + 5, 12, 31));
              if (date != null && mounted)
                setState(() =>
                    _start = wibFromParts(date.year, date.month, date.day));
            }),
        OutlinedButton.icon(
            icon: const Icon(Icons.access_time),
            label: Text('${_timeLabel(_startTime)} WIB'),
            onPressed: () async {
              final time = await showTimePicker(
                  context: context,
                  initialTime: _startTime,
                  builder: (context, child) => MediaQuery(
                      data: MediaQuery.of(context)
                          .copyWith(alwaysUse24HourFormat: true),
                      child: child!));
              if (time != null && mounted) setState(() => _startTime = time);
            }),
        _label('Jumlah yang diminum setiap dosis'),
        _number(_units, 'Unit per dosis'),
        const SizedBox(height: 6),
        Text(
            'Dalam satuan ${_form == 'Sirup' ? 'ml' : _form.toLowerCase()}. Dosis klinis: ${_dose.text} ${_unit.toUpperCase()}.'),
        SwitchListTile(
            contentPadding: EdgeInsets.zero,
            activeTrackColor: _purple,
            title: const Text('Pengingat isi ulang',
                style: TextStyle(fontWeight: FontWeight.w700)),
            subtitle: const Text('Notifikasi ketika sisa stok mencapai batas'),
            value: _refill,
            onChanged: (v) => setState(() => _refill = v)),
        if (_refill) ...[
          _label('Stok dan batas pengingat'),
          _number(_stock, 'Jumlah stok'),
          const SizedBox(height: 12),
          _number(_threshold, 'Ingatkan jika sisa stok ≤'),
          const SizedBox(height: 8),
          const Text(
              'Batas awal: 3 unit. Stok berkurang saat pasien mencatat obat diminum.')
        ],
        if (_periodic)
          const Padding(
              padding: EdgeInsets.only(top: 16),
              child: Text(
                  'Pengingat berkala menyiapkan 60 waktu berikutnya dan diperbarui otomatis ketika Malva dibuka.')),
        const SizedBox(height: 18),
        const Text(
            'Resep dan rutinitas tersimpan pada akun pasien. Pengingat perangkat memerlukan izin notifikasi pasien.'),
      ];
  void _next() {
    if (_step == 0) {
      final dose = double.tryParse(_dose.text.replaceAll(',', '.'));
      String? error;
      if (_patientId == null || _patientId!.isEmpty) {
        error = 'Pilih pasien terlebih dahulu.';
      } else if (_name.text.trim().isEmpty) {
        error = 'Nama obat tidak boleh kosong.';
      } else if (dose == null || !dose.isFinite || dose <= 0) {
        error = 'Dosis harus lebih dari 0.';
      } else if ((int.tryParse(_stock.text) ?? -1) <= 0) {
        error = 'Stok yang diberikan harus lebih dari 0.';
      }
      if (error != null) {
        setState(() => _error = error);
        return;
      }
      _go(1);
      return;
    }
    if (_step == 1) {
      if (_weekdays.isEmpty) {
        setState(() => _error = 'Pilih minimal satu hari.');
        return;
      }
      if (_periodic) {
        final n = int.tryParse(_interval.text) ?? 0;
        if (n < 1 || n > (_intervalUnit == 'jam' ? 168 : 365)) {
          setState(() => _error =
              'Interval harus 1–${_intervalUnit == 'jam' ? 168 : 365} $_intervalUnit.');
          return;
        }
      }
      if (_times.map(_timeLabel).toSet().length != _times.length) {
        setState(() => _error = 'Jam minum obat tidak boleh sama.');
        return;
      }
      _startTime = _times.first;
      _go(2);
      return;
    }
    _submit();
  }

  Future<void> _submit() async {
    final units = int.tryParse(_units.text) ?? 0;
    final stock = int.tryParse(_stock.text) ?? -1;
    final threshold = int.tryParse(_threshold.text) ?? -1;
    if (units < 1 || units > 1000 || stock <= 0 || threshold < 0) {
      setState(() =>
          _error = 'Jumlah per dosis, stok, dan batas pengingat harus valid.');
      return;
    }
    final api = widget.apiClient;
    final token = widget.session?.accessToken;
    if (api == null || token == null || token.isEmpty) {
      setState(() => _error = 'Hubungkan ke server untuk menerbitkan resep.');
      return;
    }
    final times = (_periodic && _intervalUnit == 'jam'
        ? [_timeLabel(_startTime)]
        : _times.map(_timeLabel).toList())
      ..sort();
    final schedule = MedicationSchedule(
        times: times,
        weekdays: _weekdays.toList()..sort(),
        startAt: wibFromParts(_start.year, _start.month, _start.day,
            _startTime.hour, _startTime.minute),
        intervalHours:
            _periodic && _intervalUnit == 'jam' ? int.parse(_interval.text) : 0,
        intervalDays: _periodic && _intervalUnit == 'hari'
            ? int.parse(_interval.text)
            : 0,
        unitsPerDose: units,
        refillEnabled: _refill);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await api.createEPrescription(
          accessToken: token,
          patientId: _patientId!,
          instructions: _notes.text.trim(),
          notes: _notes.text.trim(),
          items: [
            BackendEPrescriptionItem(
                name: _name.text.trim(),
                dosage: '${_dose.text.trim()} $_unit',
                form: _form,
                unit: _unit,
                frequency: _periodic
                    ? 'Setiap ${_interval.text} $_intervalUnit'
                    : _frequency,
                unitsPerDay: units * times.length,
                currentStock: stock,
                alertBelow: threshold,
                schedule: schedule)
          ]);
      widget.onCreated?.call();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Resep dan rutinitas obat dikirim ke pasien.')));
      Navigator.pop(context);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
