import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models.dart';
import '../../providers/providers.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../time/wib.dart';
import '../../widgets/friendly_error.dart';
import 'prescription_widgets.dart';

/// Clinical detail, routine, dose reminders and refill reminders share one draft.
class EPrescriptionFormScreen extends ConsumerStatefulWidget {
  const EPrescriptionFormScreen(
      {super.key,
      this.session,
      this.apiClient,
      this.links = const [],
      this.preselectedPatientId = '',
      this.preselectedPatientName = '',
      this.onCreated,
      this.onIssued,
      this.lockPatient = false,
      this.initialMedication,
      this.prescription,
      this.itemIndex = 0,
      this.onSaveMedication,
      this.sessionDraft = false,
      this.personal = false});
  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final List<BackendPatientProfessionalLink> links;
  final String preselectedPatientId, preselectedPatientName;
  final VoidCallback? onCreated;
  final ValueChanged<BackendEPrescription>? onIssued;
  final bool lockPatient;
  final Medication? initialMedication;
  final BackendEPrescription? prescription;
  final int itemIndex;
  final Future<void> Function(Medication)? onSaveMedication;
  final bool sessionDraft;
  final bool personal;
  @override
  ConsumerState<EPrescriptionFormScreen> createState() =>
      _PrescriptionWizardState();
}

enum _Routine { daily, flexible, periodic, precision, weekdays }

class _PrescriptionWizardState extends ConsumerState<EPrescriptionFormScreen> {
  static const _purple = Color(0xff91479e);
  static const _teal = Color(0xff39b49e);
  static const _ink = Color(0xff222e3a);
  static const _muted = Color(0xff8190a0);
  static const _line = Color(0xffe6eaf0);
  static const _pale = Color(0xfff8f9fc);
  late final PrescriptionAccountGuard _account;
  final _name = TextEditingController();
  final _dose = TextEditingController();
  final _notes = TextEditingController();
  final _scroll = ScrollController();
  AuthSession? get _session =>
      _account.session(ref.read(authStateProvider).session);
  String? _patientId, _error;
  String _form = 'Tablet', _unit = 'mg', _intervalUnit = 'jam';
  _Routine _mode = _Routine.daily;
  int _step = 0, _dailyCount = 1, _precisionCount = 4, _interval = 8;
  int _stock = 30, _threshold = 3, _units = 1;
  bool _refill = true, _saving = false;
  DateTime _start = wibNow();
  final _times = <TimeOfDay>[const TimeOfDay(hour: 8, minute: 0)];
  final _weekdays = <int>{1, 2, 3, 4, 5, 6, 7};
  static const _doseUnits = ['mg', 'mcg', 'g', 'ml', 'IU'];
  bool get _editing =>
      widget.initialMedication != null || widget.prescription != null;
  BackendEPrescriptionItem? get _item =>
      widget.prescription?.items[widget.itemIndex];
  int get _stockOffset {
    final item = _item;
    // Prescription updates apply the supply difference to the patient's stock.
    return item == null
        ? 0
        : item.currentStock - (item.remainingStock ?? item.currentStock);
  }

  MedicationSchedule? get _initialSchedule =>
      widget.initialMedication?.schedule ?? _item?.schedule;
  String get _meal =>
      _initialSchedule?.relationToMeal ??
      widget.initialMedication?.reminders.firstOrNull?.relationToMeal ??
      '';
  String? _initialDose;
  String? _initialUnit;
  bool _routineChanged = false;
  bool _timingChanged = false;
  String get _stockUnit => switch (_form) {
        'Sirup' => 'ml',
        'Injeksi' => 'ampul',
        'Tablet' when widget.personal => 'tablet',
        'Kapsul' when widget.personal => 'kapsul',
        _ => 'pil'
      };
  String get _frequency => switch (_mode) {
        _Routine.flexible => 'Fleksibel',
        _Routine.periodic => 'Setiap $_interval $_intervalUnit',
        _Routine.precision => '$_precisionCount kali sehari',
        _Routine.weekdays => 'Hari tertentu',
        _Routine.daily => '${_dailyCount}x sehari'
      };
  String get _badge => switch (_mode) {
        _Routine.periodic => 'Minum setiap $_interval $_intervalUnit',
        _Routine.precision => 'Minum $_precisionCount kali sehari',
        _Routine.weekdays => 'Minum di hari tertentu',
        _Routine.daily when widget.personal => '$_dailyCount kali sehari',
        _ => _frequency
      };

  @override
  void initState() {
    super.initState();
    _account = PrescriptionAccountGuard(
        widget.session, ref.read(authStateProvider).session);
    if (widget.preselectedPatientId.isNotEmpty)
      _patientId = widget.preselectedPatientId;
    if (!_editing) return;
    final medication = widget.initialMedication;
    final item = _item;
    final dosage = medication?.dosage ?? item!.dosage;
    final parts =
        RegExp(r'^([0-9]+(?:[.,][0-9]+)?)\s*(.*)$').firstMatch(dosage.trim());
    _name.text = medication?.name ?? item!.name;
    _dose.text = _initialDose = parts?.group(1) ?? dosage;
    final suffix = parts?.group(2);
    _unit = _initialUnit = item != null && item.unit.isNotEmpty
        ? item.unit
        : suffix != null && suffix.isNotEmpty
            ? suffix
            : 'mg';
    _form = medication?.form ?? item!.form;
    _stock =
        medication?.currentStock ?? (item!.remainingStock ?? item.currentStock);
    _threshold = medication?.alertBelow ?? item!.alertBelow;
    final schedule = _initialSchedule;
    final reminders = schedule?.reminders(_meal) ?? medication?.reminders;
    _times
      ..clear()
      ..addAll(reminders?.map((r) => r.time) ?? const []);
    if (schedule != null) {
      _start = toWib(schedule.startAt);
      _weekdays
        ..clear()
        ..addAll(schedule.weekdays);
      _units = schedule.unitsPerDose;
      _refill = schedule.refillEnabled;
      _notes.text = schedule.instructions;
      if (schedule.intervalHours > 0) {
        _interval = schedule.intervalHours;
      } else if (schedule.intervalDays > 0) {
        _interval = schedule.intervalDays;
        _intervalUnit = 'hari';
      } else if (schedule.intervalMonths > 0) {
        _interval = schedule.intervalMonths;
        _intervalUnit = 'bulan';
      }
    }
    _mode = switch (schedule) {
      _ when _times.isEmpty => _Routine.flexible,
      MedicationSchedule(
        :final intervalHours,
        :final intervalDays,
        :final intervalMonths
      )
          when intervalHours > 0 || intervalDays > 0 || intervalMonths > 0 =>
        _Routine.periodic,
      _ when _weekdays.length < 7 || item?.frequency == 'Hari tertentu' =>
        _Routine.weekdays,
      _
          when _times.length > 3 ||
              (item?.frequency.contains(' kali sehari') ?? false) =>
        _Routine.precision,
      _ => _Routine.daily,
    };
    if (_mode == _Routine.daily) _dailyCount = _times.length;
    if (_mode == _Routine.precision) _precisionCount = _times.length;
  }

  @override
  void dispose() {
    _name.dispose();
    _dose.dispose();
    _notes.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _go(int step) {
    FocusScope.of(context).unfocus();
    setState(() {
      _step = step;
      _error = null;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _back() {
    if (_saving) return;
    if (_step == 0) {
      Navigator.maybePop(context);
      return;
    }
    _go(_step == 3 && _mode == _Routine.flexible ? 1 : _step - 1);
  }

  String _timeLabel(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  void _setCount(int count) {
    _times.clear();
    for (var i = 0; i < count; i++) {
      _times.add(TimeOfDay(
          hour: 8 + (count == 1 ? 0 : (i * 12 / (count - 1)).round()),
          minute: 0));
    }
  }

  void _select(_Routine mode, [int? count]) => setState(() {
        if (_editing &&
            mode == _mode &&
            (count == null || count == _dailyCount)) return;
        _routineChanged = true;
        _mode = mode;
        _error = null;
        if (count != null) _dailyCount = count;
        if (mode == _Routine.flexible) {
          _times.clear();
        } else {
          _setCount(mode == _Routine.daily
              ? _dailyCount
              : mode == _Routine.precision
                  ? _precisionCount
                  : 1);
        }
        if (mode != _Routine.weekdays) {
          _weekdays.clear();
          _weekdays.addAll([1, 2, 3, 4, 5, 6, 7]);
        }
      });

  @override
  Widget build(BuildContext context) {
    if (!_account.current(ref.watch(authStateProvider).session)) {
      return const Scaffold(
          body: Center(
              child: Text('Sesi akun berubah. Buka kembali halaman resep.')));
    }
    final clinical = _step < 2;
    final purpleHeader = clinical || _editing;
    return Theme(
        data: Theme.of(context).copyWith(
          textTheme: Theme.of(context)
              .textTheme
              .apply(bodyColor: _ink, displayColor: _ink),
          appBarTheme: const AppBarTheme(
              titleTextStyle: TextStyle(fontFamily: 'Roboto')),
          filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                  textStyle: const TextStyle(fontFamily: 'Roboto'))),
          outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                  textStyle: const TextStyle(fontFamily: 'Roboto'))),
          textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                  textStyle: const TextStyle(fontFamily: 'Roboto'))),
          dividerColor: _line,
        ),
        child: PopScope(
          canPop: _step == 0 && !_saving,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) _back();
          },
          child: Scaffold(
            backgroundColor: clinical ? Colors.white : _pale,
            appBar: AppBar(
              title: Text(
                  switch (_step) {
                    0 when _editing => 'Edit Obat',
                    1 when _editing => 'Edit Rutinitas',
                    2 when _editing && !widget.personal => 'Edit Pengingat',
                    2 when _editing => 'Edit Pengingat Obat',
                    3 when _editing => 'Edit Pengingat Stok',
                    0 => widget.personal ? 'Tambah Obat' : 'Detail Obat',
                    1 => 'Atur Rutinitas',
                    2 when widget.personal => 'Pengingat Obat',
                    3 when widget.personal => 'Pengingat Isi Ulang Obat',
                    _ => 'Atur Pengingat',
                  },
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: purpleHeader ? Colors.white : _ink)),
              centerTitle: true,
              toolbarHeight: _step == 0
                  ? 88
                  : _step == 1
                      ? 66
                      : 60,
              backgroundColor: purpleHeader ? _purple : Colors.white,
              foregroundColor: purpleHeader ? Colors.white : _muted,
              surfaceTintColor: Colors.transparent,
              elevation: purpleHeader ? 3 : 0,
              shadowColor: purpleHeader ? Colors.black26 : Colors.transparent,
              shape: purpleHeader
                  ? RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(
                          bottom: Radius.circular(_step == 0 ? 38 : 12)))
                  : const Border(bottom: BorderSide(color: _line)),
              leading: IconButton(
                  tooltip: 'Kembali',
                  onPressed: _saving ? null : _back,
                  icon: const Icon(Icons.arrow_back_rounded, size: 24)),
            ),
            body: SafeArea(
                bottom: false,
                child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                          controller: _scroll,
                          padding: EdgeInsets.fromLTRB(_step == 0 ? 24 : 16, 22,
                              _step == 0 ? 24 : 16, 24),
                          child: Align(
                              alignment: Alignment.topCenter,
                              child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 620),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: switch (_step) {
                                      0 => _details(),
                                      1 => _routine(),
                                      2 => _timing(),
                                      _ => _refillSettings()
                                    },
                                  ))),
                        ))),
            bottomNavigationBar: SafeArea(
                top: false,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                      _step == 0 ? 24 : 16,
                      8,
                      _step == 0 ? 24 : 16,
                      12 + MediaQuery.viewInsetsOf(context).bottom),
                  child: Align(
                      heightFactor: 1,
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 620),
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (_error != null)
                                  Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: Text(_error!,
                                          style: const TextStyle(
                                              color: MalvaColors.danger,
                                              fontWeight: FontWeight.w600))),
                                Container(
                                    decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(16),
                                        boxShadow: [
                                          BoxShadow(
                                              color: _purple.withValues(
                                                  alpha: .18),
                                              blurRadius: 12,
                                              offset: const Offset(0, 5))
                                        ]),
                                    child: FilledButton(
                                      key: const Key('rx-next'),
                                      onPressed: _saving ? null : _next,
                                      style: FilledButton.styleFrom(
                                          backgroundColor: _purple,
                                          foregroundColor: Colors.white,
                                          minimumSize:
                                              const Size.fromHeight(56),
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 18, horizontal: 12),
                                          shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16))),
                                      child: _saving
                                          ? const SizedBox(
                                              width: 20,
                                              height: 20,
                                              child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white))
                                          : Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                  Flexible(
                                                      child: Text(
                                                          switch (_step) {
                                                            3
                                                                when widget
                                                                        .sessionDraft &&
                                                                    widget.onSaveMedication !=
                                                                        null =>
                                                              'Simpan Obat',
                                                            3 when _editing =>
                                                              widget.personal
                                                                  ? 'Simpan perubahan'
                                                                  : 'Simpan dan Kirim Perubahan',
                                                            0
                                                                when widget
                                                                    .personal =>
                                                              'Lanjut atur jadwal',
                                                            2
                                                                when widget
                                                                    .personal =>
                                                              'Lanjut ke pengingat stok',
                                                            3
                                                                when widget
                                                                    .personal =>
                                                              'Simpan obat',
                                                            0
                                                                when _editing &&
                                                                    !widget
                                                                        .personal =>
                                                              'Lanjut Edit Rutinitas',
                                                            1
                                                                when _editing &&
                                                                    !widget
                                                                        .personal =>
                                                              'Lanjut Edit Pengingat',
                                                            2
                                                                when _editing &&
                                                                    !widget
                                                                        .personal =>
                                                              'Lanjut Edit Pengingat Stok',
                                                            0 =>
                                                              'Lanjut Atur Jadwal Resep',
                                                            1 =>
                                                              'Lanjutkan Kebiasaan',
                                                            2 =>
                                                              'Lanjut Atur Pengingat Stok',
                                                            _ =>
                                                              'Simpan dan Kirim Resep'
                                                          },
                                                          textAlign:
                                                              TextAlign.center,
                                                          style: const TextStyle(
                                                              fontSize: 16,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w700))),
                                                  const SizedBox(width: 8),
                                                  const Icon(
                                                      Icons
                                                          .arrow_forward_rounded,
                                                      size: 23)
                                                ]),
                                    )),
                              ]))),
                )),
          ),
        ));
  }

  Widget _heading(String text) => Text.rich(
      TextSpan(children: [
        TextSpan(text: '$text '),
        WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Image.asset('assets/prescription/pill.png',
                width: 27, height: 27))
      ]),
      style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          height: 1.15,
          letterSpacing: -.35));
  Widget _label(String text, {double top = 22}) => Padding(
      padding: EdgeInsets.only(top: top, bottom: 10),
      child: Text(text,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xff626e79))));
  InputDecoration _decoration(String hint, {Widget? prefix}) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xffa0a8b4), fontSize: 15),
        filled: true,
        fillColor: const Color(0xfff9fafc),
        prefixIcon: prefix,
        isDense: true,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(color: Color(0xffe6e7eb))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(color: Color(0xffe6e7eb))),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      );
  List<Widget> _details() {
    final patients = {
      for (final p in widget.links)
        p.patientId: p.patientDisplayName.isEmpty
            ? 'Pasien terhubung'
            : p.patientDisplayName
    };
    if (widget.preselectedPatientId.isNotEmpty)
      patients.putIfAbsent(
          widget.preselectedPatientId,
          () => widget.preselectedPatientName.isEmpty
              ? 'Pasien terpilih'
              : widget.preselectedPatientName);
    return [
      _heading(_editing
          ? 'Detail Obat'
          : widget.personal
              ? 'Obat apa yang ingin\nkamu catat?'
              : 'Obat apa yang ingin\nkamu resepkan?'),
      if (!widget.personal && !_editing) ...[
        _label('Pasien'),
        DropdownButtonFormField<String>(
            initialValue: _patientId,
            style: const TextStyle(
                fontFamily: 'Roboto', fontSize: 16, height: 1.25, color: _ink),
            isExpanded: true,
            decoration: _decoration('Pilih pasien'),
            icon: const Icon(Icons.arrow_drop_down_rounded,
                color: Color(0xff9ca5b2)),
            items: [
              for (final p in patients.entries)
                DropdownMenuItem(
                    value: p.key,
                    child: Text(p.value, overflow: TextOverflow.ellipsis))
            ],
            onChanged: widget.lockPatient
                ? null
                : (v) => setState(() => _patientId = v)),
        if (patients.isEmpty)
          const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text('Belum ada pasien terhubung.')),
      ],
      _label(widget.personal ? 'Nama obat' : 'Nama Obat'),
      TextField(
          key: const Key('rx-name'),
          controller: _name,
          style: const TextStyle(fontSize: 16, height: 1.25),
          decoration: _decoration(
              widget.personal
                  ? 'Masukkan nama obat'
                  : 'Contoh: Aripiprazole, Paracetamol',
              prefix: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Image.asset('assets/prescription/capsule.png',
                      width: 20, height: 20, color: const Color(0xffa0a8b4)))),
          textCapitalization: TextCapitalization.words),
      _label(widget.personal ? 'Bentuk obat' : 'Bentuk Obat'),
      LayoutBuilder(
          builder: (context, c) => Wrap(spacing: 12, runSpacing: 12, children: [
                for (final form in [
                  ('Tablet', 'tablet'),
                  ('Kapsul', 'capsule'),
                  ('Sirup', 'syrup'),
                  ('Injeksi', 'injection')
                ])
                  SizedBox(
                      width: (c.maxWidth - 12) / 2,
                      child: OutlinedButton.icon(
                          onPressed: () => setState(() => _form = form.$1),
                          icon: Image.asset(
                              'assets/prescription/${form.$2}.png',
                              width: 21,
                              height: 21,
                              fit: BoxFit.contain,
                              color: _form == form.$1
                                  ? _purple
                                  : const Color(0xff717d87)),
                          label: Text(form.$1),
                          style: OutlinedButton.styleFrom(
                              foregroundColor: _form == form.$1
                                  ? _purple
                                  : const Color(0xff717d87),
                              backgroundColor: _form == form.$1
                                  ? const Color(0xfffbf5ff)
                                  : const Color(0xfff9fafc),
                              minimumSize: const Size(0, 54),
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14, horizontal: 8),
                              side: BorderSide(
                                  color: _form == form.$1
                                      ? _purple
                                      : const Color(0xfff0f1f4),
                                  width: _form == form.$1 ? 1.8 : 1),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(13)),
                              textStyle: const TextStyle(
                                  fontFamily: 'Roboto',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600))))
              ])),
      _label(widget.personal ? 'Dosis per penggunaan' : 'Dosis per minum',
          top: 32),
      Row(children: [
        Expanded(
            flex: 2,
            child: TextField(
                key: const Key('rx-dose'),
                controller: _dose,
                style: const TextStyle(fontSize: 16, height: 1.25),
                textAlign: TextAlign.center,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: _decoration(widget.personal ? 'Jumlah' : '0'))),
        const SizedBox(width: 12),
        Expanded(
            child: DropdownButtonFormField<String>(
                initialValue: _unit,
                style: const TextStyle(
                    fontFamily: 'Roboto',
                    fontSize: 16,
                    height: 1.25,
                    color: _ink),
                isExpanded: true,
                decoration: _decoration('Satuan'),
                icon: const Icon(Icons.arrow_drop_down_rounded,
                    color: Color(0xff9ca5b2)),
                items: [
                  for (final u in {..._doseUnits, _unit})
                    DropdownMenuItem(
                        value: u,
                        child: Text(u.toUpperCase(),
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 14)))
                ],
                onChanged: (v) => setState(() => _unit = v!)))
      ]),
      _label(
          widget.personal
              ? 'Catatan penggunaan (opsional)'
              : 'Catatan (opsional)',
          top: 32),
      TextField(
          controller: _notes,
          style: const TextStyle(fontSize: 15, height: 1.3),
          maxLines: 3,
          decoration: _decoration('Contoh: Diminum sesudah makan...')),
    ];
  }

  Widget _summary() => Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
          gradient:
              const LinearGradient(colors: [Color(0xfff3ebf6), Colors.white]),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xffe8dfed)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x08000000), blurRadius: 3, offset: Offset(0, 2))
          ]),
      child: Row(children: [
        SizedBox(
            width: 48,
            height: 48,
            child: IconButton.filledTonal(
                onPressed: () => _go(0),
                style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(13))),
                tooltip: 'Ubah obat',
                icon: const Icon(Icons.keyboard_arrow_down_rounded,
                    color: _purple))),
        const SizedBox(width: 16),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_name.text,
              style:
                  const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 7),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                  color: const Color(0xffdceeea),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(
                  '${_form.toUpperCase()} • ${_dose.text}${_unit.toUpperCase()}',
                  style: const TextStyle(
                      color: Color(0xff3e9c91),
                      fontSize: 10,
                      height: 1.15,
                      fontWeight: FontWeight.w700)))
        ])),
        const SizedBox(width: 8),
        SizedBox(
            width: 34,
            height: 34,
            child: IconButton.outlined(
                onPressed: () => _go(0),
                tooltip: 'Edit detail obat',
                style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: _line),
                    padding: EdgeInsets.zero),
                icon: const Icon(Icons.edit_rounded,
                    size: 16, color: Color(0xff9aa9b8))))
      ]));
  Widget _frequencyRow(String label, bool selected, VoidCallback tap) =>
      Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Semantics(
              selected: selected,
              button: true,
              child: Material(
                  color: selected ? Colors.white : const Color(0xfff9f9ff),
                  borderRadius: BorderRadius.circular(40),
                  child: InkWell(
                      onTap: tap,
                      borderRadius: BorderRadius.circular(40),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 56),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
                        decoration: BoxDecoration(
                            border: Border.all(
                                color: selected ? _purple : _line,
                                width: selected ? 1.8 : 1.3),
                            borderRadius: BorderRadius.circular(40),
                            boxShadow: selected
                                ? const [
                                    BoxShadow(
                                        color: Color(0x0791479e),
                                        blurRadius: 7,
                                        offset: Offset(0, 3))
                                  ]
                                : null),
                        child: Row(children: [
                          Expanded(
                              child: Text(label,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15))),
                          const SizedBox(width: 12),
                          Icon(selected ? Icons.circle : Icons.circle_outlined,
                              color:
                                  selected ? _purple : const Color(0xffced7e3),
                              size: 21)
                        ]),
                      )))));
  Widget _pattern(_Routine mode, String title, String subtitle, IconData icon) {
    final selected = _mode == mode;
    return Expanded(
        child: Semantics(
            selected: selected,
            button: true,
            child: Material(
                color: selected ? const Color(0xffeaf8f4) : Colors.white,
                borderRadius: BorderRadius.circular(23),
                child: InkWell(
                    onTap: () => _select(mode),
                    borderRadius: BorderRadius.circular(23),
                    child: Container(
                        constraints: const BoxConstraints(minHeight: 108),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 14),
                        decoration: BoxDecoration(
                            border: Border.all(
                                color:
                                    selected ? _teal : const Color(0xffedf2f7),
                                width: selected ? 1.7 : 1.3),
                            borderRadius: BorderRadius.circular(23)),
                        child: Column(children: [
                          Container(
                              width: 38,
                              height: 38,
                              decoration: BoxDecoration(
                                  color: selected
                                      ? _teal
                                      : const Color(0xfff8fafc),
                                  borderRadius: BorderRadius.circular(14),
                                  boxShadow: selected
                                      ? [
                                          BoxShadow(
                                              color:
                                                  _teal.withValues(alpha: .2),
                                              blurRadius: 8,
                                              offset: const Offset(0, 4))
                                        ]
                                      : null),
                              child: Icon(icon,
                                  size: 20,
                                  color: selected
                                      ? Colors.white
                                      : const Color(0xffa7b7c9))),
                          const SizedBox(height: 10),
                          Text(title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? const Color(0xff3c9e8f)
                                      : _ink)),
                          const SizedBox(height: 3),
                          Text(subtitle,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 10, color: Color(0xff9baab8)))
                        ]))))));
  }

  List<Widget> _routine() => [
        _summary(),
        const SizedBox(height: 24),
        _heading(widget.personal
            ? 'Seberapa sering kamu menggunakan obat ini?'
            : 'Bagaimana rutinitas minum\nobat pasien?'),
        const SizedBox(height: 24),
        for (var n = 1; n <= 3; n++)
          _frequencyRow(
              '${n}x sehari',
              _mode == _Routine.daily && _dailyCount == n,
              () => _select(_Routine.daily, n)),
        _frequencyRow('Fleksibel', _mode == _Routine.flexible,
            () => _select(_Routine.flexible)),
        const Padding(
            padding: EdgeInsets.only(top: 18, bottom: 26),
            child: Row(children: [
              Expanded(child: Divider(color: _line)),
              Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Text('POLA KHUSUS',
                      style: TextStyle(
                          fontSize: 11,
                          color: Color(0xff93a3b8),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1))),
              Expanded(child: Divider(color: _line))
            ])),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _pattern(_Routine.periodic, 'Pola Berkala', 'Tiap X jam/hari',
              CupertinoIcons.hourglass),
          const SizedBox(width: 12),
          _pattern(_Routine.precision, 'Jam Presisi', 'Jam spesifik',
              CupertinoIcons.clock),
          const SizedBox(width: 12),
          _pattern(_Routine.weekdays, 'Pilih Hari', 'Hari tertentu',
              CupertinoIcons.calendar),
        ]),
        if (_mode == _Routine.periodic)
          _optionPanel(Column(children: [
            SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final unit in ['jam', 'hari', 'bulan']) ...[
                    SizedBox(
                        width: unit == 'jam'
                            ? 136
                            : unit == 'hari'
                                ? 118
                                : 148,
                        child: OutlinedButton(
                            onPressed: () => setState(() {
                                  _intervalUnit = unit;
                                  _interval = unit == 'jam'
                                      ? 8
                                      : unit == 'hari'
                                          ? 2
                                          : 1;
                                }),
                            style: OutlinedButton.styleFrom(
                                backgroundColor: _intervalUnit == unit
                                    ? const Color(0xffe2f4f1)
                                    : Colors.white,
                                foregroundColor: _intervalUnit == unit
                                    ? const Color(0xff3b9c90)
                                    : _muted,
                                side: BorderSide(
                                    color: _intervalUnit == unit
                                        ? const Color(0xffb8dfda)
                                        : _line),
                                padding: const EdgeInsets.symmetric(
                                    vertical: 12, horizontal: 4),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(13))),
                            child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (_intervalUnit == unit) ...[
                                    const Icon(Icons.check_rounded, size: 16),
                                    const SizedBox(width: 4)
                                  ],
                                  Flexible(
                                      child: Text('Tiap X $unit',
                                          style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600)))
                                ]))),
                    if (unit != 'bulan') const SizedBox(width: 8)
                  ]
                ])),
            const SizedBox(height: 14),
            _settingsCard([
              _setting('Ingatkan setiap', '$_interval $_intervalUnit',
                  () async {
                final n = await _pickNumber(
                    'Ingatkan setiap ($_intervalUnit)', _interval,
                    max: _intervalUnit == 'jam'
                        ? 168
                        : _intervalUnit == 'bulan'
                            ? 12
                            : 365);
                if (n != null && mounted) setState(() => _interval = n);
              })
            ])
          ])),
        if (_mode == _Routine.precision)
          _optionPanel(_settingsCard([
            _setting('Jumlah konsumsi', '$_precisionCount kali sehari',
                () async {
              final n = await _pickNumber(
                  'Jumlah konsumsi per hari', _precisionCount,
                  max: 10);
              if (n != null && mounted)
                setState(() {
                  _precisionCount = n;
                  _setCount(n);
                });
            })
          ])),
        if (_mode == _Routine.weekdays)
          _optionPanel(Row(children: [
            for (var day = 1; day <= 7; day++) ...[
              Expanded(
                  child: Semantics(
                      selected: _weekdays.contains(day),
                      button: true,
                      child: Material(
                          color: _weekdays.contains(day) ? _teal : Colors.white,
                          borderRadius: BorderRadius.circular(11),
                          child: InkWell(
                              onTap: () => setState(() {
                                    if (!_weekdays.add(day))
                                      _weekdays.remove(day);
                                  }),
                              borderRadius: BorderRadius.circular(11),
                              child: Container(
                                  constraints:
                                      const BoxConstraints(minHeight: 50),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                      border: Border.all(
                                          color: _weekdays.contains(day)
                                              ? _teal
                                              : _line),
                                      borderRadius: BorderRadius.circular(11)),
                                  child: Text(
                                      const [
                                        'Sen',
                                        'Sel',
                                        'Rab',
                                        'Kam',
                                        'Jum',
                                        'Sab',
                                        'Min'
                                      ][day - 1],
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: _weekdays.contains(day)
                                              ? Colors.white
                                              : _muted,
                                          fontWeight: FontWeight.w600))))))),
              if (day < 7) const SizedBox(width: 7)
            ]
          ])),
      ];

  Widget _optionPanel(Widget child) => Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: _pale,
          border: Border.all(color: _line),
          borderRadius: BorderRadius.circular(24)),
      child: child);
  Widget _settingsCard(List<Widget> children) => Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(color: _line),
          boxShadow: const [
            BoxShadow(
                color: Color(0x04000000), blurRadius: 2, offset: Offset(0, 1))
          ]),
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            const Divider(height: 1, thickness: 1, color: Color(0xfff1f3f6)),
          children[i]
        ]
      ]));
  Widget _value(String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Flexible(
            child: Text(text,
                style:
                    const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                textAlign: TextAlign.end)),
        const SizedBox(width: 4),
        const Icon(Icons.keyboard_arrow_down_rounded,
            size: 17, color: Color(0xffacb9c8))
      ]);
  Widget _setting(String label, String value, VoidCallback tap,
          {Key? key, bool enabled = true}) =>
      InkWell(
          key: key,
          onTap: enabled ? tap : null,
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(children: [
                Expanded(
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 14,
                            color:
                                enabled ? const Color(0xff526173) : _muted))),
                const SizedBox(width: 12),
                ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * .45),
                    child: _value(value))
              ])));
  List<Widget> _reminderHeading(String title) => [
        Text('${_name.text} $_form',
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13, color: _muted, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        Text(title,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 22,
                height: 1.2,
                fontWeight: FontWeight.w700,
                letterSpacing: -.25)),
      ];
  Future<void> _pickDate() async {
    final now = wibNow();
    final first = _start.isBefore(now) ? _start : now;
    final lastYear = _start.year > now.year + 5 ? _start.year : now.year + 5;
    final date = await showDatePicker(
        context: context,
        initialDate: _start,
        firstDate: wibFromParts(first.year, first.month, first.day),
        lastDate: wibFromParts(lastYear, 12, 31));
    if (date != null && mounted)
      setState(() {
        _start = wibFromParts(date.year, date.month, date.day);
        _timingChanged = true;
      });
  }

  Future<void> _pickTime(int index) async {
    final time = await showTimePicker(
        context: context,
        initialTime: _times[index],
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!));
    if (time != null && mounted)
      setState(() {
        _times[index] = time;
        _timingChanged = true;
      });
  }

  Future<void> _pickDose() async {
    final n = await _pickNumber('Dosis per konsumsi ($_stockUnit)', _units,
        max: 1000, help: 'Berlaku untuk setiap waktu minum obat ini.');
    if (n != null && mounted)
      setState(() {
        _units = n;
        _timingChanged = true;
      });
  }

  List<Widget> _timing() => [
        ..._reminderHeading(widget.personal
            ? 'Kapan kamu ingin diingatkan?'
            : 'Kapan pasien perlu diingatkan?'),
        const SizedBox(height: 12),
        Center(
            child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                    color: const Color(0xffe5f4f3),
                    border: Border.all(color: const Color(0xffc6e7e3)),
                    borderRadius: BorderRadius.circular(8)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(CupertinoIcons.clock,
                      size: 15, color: Color(0xff45a698)),
                  const SizedBox(width: 6),
                  Flexible(
                      child: Text(_badge,
                          style: const TextStyle(
                              color: Color(0xff45a698),
                              fontWeight: FontWeight.w600,
                              fontSize: 13)))
                ]))),
        const SizedBox(height: 24),
        _settingsCard([
          _setting(
              widget.personal ? 'Tanggal mulai' : 'Mulai tanggal',
              formatWibDate(_start) == formatWibDate(wibNow())
                  ? 'Hari ini'
                  : formatWibDate(_start),
              _pickDate),
          if (_times.length == 1 && _mode != _Routine.weekdays) ...[
            _setting(widget.personal ? 'Jam pengingat' : 'Dimulai pada',
                _timeLabel(_times.first), () => _pickTime(0),
                key: const Key('rx-time-0')),
            _setting(widget.personal ? 'Jumlah per penggunaan' : 'Dosis',
                '$_units $_stockUnit', _pickDose)
          ] else
            for (var i = 0; i < _times.length; i++)
              Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(children: [
                    Expanded(
                        child: InkWell(
                            key: Key('rx-time-$i'),
                            onTap: () => _pickTime(i),
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 14),
                                child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _value(_timeLabel(_times[i])))))),
                    Expanded(
                        child: InkWell(
                            onTap: _pickDose,
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 14),
                                child: Align(
                                    alignment: Alignment.centerRight,
                                    child: _value('$_units $_stockUnit'))))),
                    if (_mode == _Routine.weekdays && _times.length > 1)
                      IconButton(
                          tooltip: 'Hapus waktu ${i + 1}',
                          onPressed: () => setState(() => _times.removeAt(i)),
                          icon:
                              const Icon(Icons.close, size: 17, color: _muted))
                  ])),
          if (_mode == _Routine.weekdays && _times.length < 10)
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                    onPressed: () => setState(() {
                          var hour = _times.length == 1 ? 20 : 8;
                          while (_times
                              .any((t) => t.hour == hour && t.minute == 0)) {
                            hour = (hour + 1) % 24;
                          }
                          _times.add(TimeOfDay(hour: hour, minute: 0));
                        }),
                    style: TextButton.styleFrom(
                        foregroundColor: _purple,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14)),
                    child: const Text('+ Tambah waktu pengingat',
                        style: TextStyle(fontSize: 14))))
        ]),
      ];
  List<Widget> _refillSettings() => [
        ..._reminderHeading(widget.personal
            ? 'Mau diingatkan untuk isi ulang obatmu?'
            : 'Apakah perlu pengingat isi ulang obat untuk pasien?'),
        const SizedBox(height: 24),
        _settingsCard([
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 2, 12, 2),
              child: Row(children: [
                Expanded(
                    child: Text(
                        widget.personal ? 'Ingatkan saya' : 'Ingatkan pasien',
                        style: const TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700))),
                Transform.scale(
                    scale: .85,
                    child: Switch(
                        value: _refill,
                        activeThumbColor: Colors.white,
                        activeTrackColor: _teal,
                        inactiveTrackColor: const Color(0xffd8dfe8),
                        inactiveThumbColor: Colors.white,
                        trackOutlineColor:
                            const WidgetStatePropertyAll(Colors.transparent),
                        onChanged: (v) => setState(() => _refill = v)))
              ]))
        ]),
        Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 10),
            child: Text(
                widget.personal ? 'Stok obat saat ini' : 'Stok saat ini',
                style:
                    const TextStyle(fontSize: 13, height: 1.2, color: _muted))),
        _settingsCard([
          _setting(widget.personal ? 'Jumlah yang tersisa' : 'Jumlah',
              '$_stock $_stockUnit', () async {
            final n = await _pickNumber('Stok saat ini ($_stockUnit)', _stock,
                min: _stockOffset < 0 ? -_stockOffset : 0,
                max: _stockOffset > 0 ? 1000000000 - _stockOffset : 1000000000);
            if (n != null && mounted) setState(() => _stock = n);
          }, key: const Key('rx-stock'))
        ]),
        Padding(
            padding: const EdgeInsets.only(top: 18, bottom: 10),
            child: Text(
                widget.personal
                    ? 'Ingatkan saat stok tersisa'
                    : 'Ingatkan ketika:',
                style:
                    const TextStyle(fontSize: 13, height: 1.2, color: _muted))),
        _settingsCard([
          _setting('Batas minimum', '$_threshold $_stockUnit', () async {
            final n = await _pickNumber(
                'Batas minimum ($_stockUnit)', _threshold,
                min: 0, max: 1000000000);
            if (n != null && mounted) setState(() => _threshold = n);
          }, enabled: _refill)
        ]),
      ];
  Future<int?> _pickNumber(String title, int current,
      {int min = 1, int max = 1000, String? help}) async {
    final input = TextEditingController(text: '$current');
    final form = GlobalKey<FormState>();
    final result = await showDialog<int>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(title),
                content: Form(
                    key: form,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (help != null)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(help)),
                      TextFormField(
                          controller: input,
                          autofocus: true,
                          keyboardType: TextInputType.number,
                          decoration:
                              const InputDecoration(labelText: 'Jumlah'),
                          validator: (v) {
                            final n = int.tryParse(v ?? '');
                            return n == null || n < min || n > max
                                ? 'Masukkan angka $min–$max.'
                                : null;
                          },
                          onFieldSubmitted: (_) {
                            if (form.currentState!.validate())
                              Navigator.pop(context, int.parse(input.text));
                          })
                    ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Batal')),
                  FilledButton(
                      onPressed: () {
                        if (form.currentState!.validate())
                          Navigator.pop(context, int.parse(input.text));
                      },
                      child: const Text('Simpan'))
                ]));
    // The closing route animates with its text field after the result completes.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    return result;
  }

  void _next() {
    if (_step == 0) {
      final dose = double.tryParse(_dose.text.replaceAll(',', '.'));
      final error = !widget.personal &&
              !_editing &&
              (_patientId == null || _patientId!.isEmpty)
          ? 'Pilih pasien terlebih dahulu.'
          : _name.text.trim().isEmpty
              ? 'Nama obat tidak boleh kosong.'
              : !_doseUnchanged && (dose == null || !dose.isFinite || dose <= 0)
                  ? 'Dosis harus lebih dari 0.'
                  : null;
      if (error != null) {
        setState(() => _error = error);
        return;
      }
      _go(1);
      return;
    }
    if (_step == 1) {
      if (_mode == _Routine.weekdays && _weekdays.isEmpty) {
        setState(() => _error = 'Pilih minimal satu hari.');
        return;
      }
      _go(_mode == _Routine.flexible ? 3 : 2);
      return;
    }
    if (_step == 2) {
      if (_times.map(_timeLabel).toSet().length != _times.length) {
        setState(() => _error = 'Jam minum obat tidak boleh sama.');
        return;
      }
      _go(3);
      return;
    }
    _submit();
  }

  bool get _doseUnchanged =>
      _dose.text == _initialDose && _unit == _initialUnit;

  Future<void> _submit() async {
    if (!widget.personal && !_editing && _stock < 1) {
      setState(() => _error = 'Stok yang diberikan harus lebih dari 0.');
      return;
    }
    final times = _mode == _Routine.flexible
        ? <String>[]
        : (_times.map(_timeLabel).toList()..sort());
    final first = times.isEmpty ? null : times.first.split(':');
    final originalSchedule = _initialSchedule;
    final unchangedTiming = originalSchedule != null &&
        _start == toWib(originalSchedule.startAt) &&
        times.join(',') == originalSchedule.times.join(',');
    final schedule = MedicationSchedule(
      times: times,
      weekdays: _weekdays.toList()..sort(),
      startAt: unchangedTiming
          ? originalSchedule.startAt
          : wibFromParts(
              _start.year,
              _start.month,
              _start.day,
              first == null ? 0 : int.parse(first[0]),
              first == null ? 0 : int.parse(first[1])),
      intervalHours:
          _mode == _Routine.periodic && _intervalUnit == 'jam' ? _interval : 0,
      intervalDays:
          _mode == _Routine.periodic && _intervalUnit == 'hari' ? _interval : 0,
      intervalMonths: _mode == _Routine.periodic && _intervalUnit == 'bulan'
          ? _interval
          : 0,
      unitsPerDose: _units,
      refillEnabled: _refill,
      relationToMeal: _meal,
      instructions: _notes.text.trim(),
      additional: originalSchedule?.additional ?? const {},
    );
    final initialMedication = widget.initialMedication;
    final item = _item;
    final dosage = _doseUnchanged
        ? initialMedication?.dosage ?? item!.dosage
        : '${_dose.text.trim()} $_unit';
    if (initialMedication != null) {
      final keepLegacy = originalSchedule == null &&
          !_routineChanged &&
          !_timingChanged &&
          _refill &&
          _notes.text.trim().isEmpty;
      final medication = initialMedication.copyWith(
        name: _name.text.trim(),
        dosage: dosage,
        form: _form,
        reminders: keepLegacy
            ? initialMedication.reminders
            : schedule.reminders(_meal),
        currentStock: _stock,
        alertBelow: _threshold,
        schedule: keepLegacy ? null : schedule,
      );
      final save = widget.onSaveMedication;
      if (save == null) {
        Navigator.pop(context, medication);
        return;
      }
      setState(() {
        _saving = true;
        _error = null;
      });
      try {
        await save(medication);
        if (mounted && _session != null) Navigator.pop(context, true);
      } on Object catch (e) {
        if (mounted && _session != null)
          setState(() => _error = friendlyErrorMessage(e));
      } finally {
        if (mounted) setState(() => _saving = false);
      }
      return;
    }
    if (widget.personal) {
      Navigator.pop(
          context,
          Medication(
            id: 'med_${wibNow().microsecondsSinceEpoch}',
            name: _name.text.trim(),
            dosage: dosage,
            form: _form,
            reminders: schedule.reminders(''),
            currentStock: _stock,
            alertBelow: _threshold,
            source: 'Pasien',
            schedule: schedule,
          ));
      return;
    }
    final api = widget.apiClient;
    final token = _session?.accessToken;
    if (api == null || token == null || token.isEmpty) {
      setState(() => _error = 'Hubungkan ke server untuk menerbitkan resep.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final rx = widget.prescription;
      final legacy = item != null &&
          item.schedule == null &&
          !_routineChanged &&
          _refill &&
          _notes.text.trim().isEmpty;
      final updated = BackendEPrescriptionItem(
          id: item?.id ?? '',
          medicationId: item?.medicationId,
          name: _name.text.trim(),
          dosage: dosage,
          form: _form,
          unit: legacy && _doseUnchanged ? item.unit : _unit,
          frequency: legacy ? item.frequency : _frequency,
          days: item?.days ?? 30,
          unitsPerDay: legacy
              ? item.unitsPerDay
              : _units * (times.isEmpty ? 1 : times.length),
          currentStock: _stock + _stockOffset,
          alertBelow: _threshold,
          schedule: legacy ? null : schedule);
      if (widget.sessionDraft) {
        final save = widget.onSaveMedication;
        if (save != null) {
          await save(Medication(
            id: '',
            name: updated.name,
            dosage: updated.dosage,
            form: updated.form,
            reminders: schedule.reminders(_meal),
            currentStock: updated.currentStock,
            alertBelow: updated.alertBelow,
            source: 'Profesional',
            schedule: updated.schedule,
          ));
          if (mounted && _session != null) Navigator.pop(context, true);
          return;
        }
        Navigator.pop(context, updated);
        return;
      }
      if (rx != null) {
        await api.updateEPrescription(
            accessToken: token,
            prescriptionId: rx.id,
            patientId: rx.patientId,
            status: rx.status == 'draft' ? 'draft' : 'issued',
            notes: rx.notes,
            instructions: rx.instructions,
            diagnosis: rx.diagnosis,
            items: [...rx.items]..[widget.itemIndex] = updated);
        if (mounted && _session != null) Navigator.pop(context, true);
        return;
      }
      final issued = await api.createEPrescription(
          accessToken: token,
          patientId: _patientId!,
          status: 'issued',
          instructions: _notes.text.trim(),
          notes: _notes.text.trim(),
          items: [updated]);
      if (!mounted || _session == null) return;
      widget.onIssued?.call(issued);
      widget.onCreated?.call();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Resep dan rutinitas obat dikirim ke pasien.')));
      Navigator.pop(context);
    } on Object catch (e) {
      if (mounted && _session != null)
        setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
