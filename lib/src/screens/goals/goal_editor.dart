import 'package:flutter/material.dart';

import '../../models/goal_details.dart';
import '../../services/malva_api_client.dart';
import '../../time/wib.dart';
import '../../widgets/friendly_error.dart';
import 'goal_reference_widgets.dart';

class GoalEditorResult {
  const GoalEditorResult(this.title, this.details);
  final String title;
  final GoalDetails details;
}

class GoalEditor extends StatefulWidget {
  const GoalEditor({super.key, this.goal, required this.onSave});
  final BackendGoal? goal;
  final Future<bool> Function(GoalEditorResult result) onSave;
  @override
  State<GoalEditor> createState() => _GoalEditorState();
}

class _GoalEditorState extends State<GoalEditor> {
  final _title = TextEditingController();
  final _note = TextEditingController();
  final _step = TextEditingController();
  final _unit = TextEditingController();
  final _target = TextEditingController();
  late String _method, _date, _time, _recurrence;
  late int _interval;
  late List<GoalStep> _steps;
  late List<int> _weekdays, _reminders;
  late bool _autoFail, _lockPast;
  bool _busy = false;
  String? _error, _titleError;
  bool get _editing => widget.goal != null;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  @override
  void dispose() {
    for (final c in [_title, _note, _step, _unit, _target]) {
      c.dispose();
    }
    super.dispose();
  }

  void _restore() {
    final now = wibNow();
    final d = widget.goal?.details ??
        GoalDetails(
            recurrence: widget.goal == null ? 'weekly' : 'daily',
            reminders: widget.goal == null ? const [30] : const [],
            startDate: wibDateKey(widget.goal?.createdAt ?? now),
            time:
                '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}');
    _title.text = widget.goal?.title ?? '';
    _note.text = d.note;
    _unit.text = d.unit;
    _target.text = '${d.target}';
    _step.clear();
    _method = d.method;
    _date = d.startDate;
    _time = d.time;
    _recurrence = d.recurrence;
    _interval = d.interval;
    _steps = [...d.steps];
    _weekdays = [...d.weekdays];
    _reminders = [...d.reminders];
    _autoFail = d.autoFail;
    _lockPast = d.lockPast;
    _error = null;
    _titleError = null;
  }

  GoalDetails get _details => GoalDetails(
      note: _note.text.trim(),
      method: _method,
      target: int.tryParse(_target.text) ?? 0,
      unit: _unit.text.trim(),
      steps: [..._steps],
      startDate: _date,
      time: _time,
      recurrence: _recurrence,
      interval: _interval,
      weekdays: [..._weekdays]..sort(),
      reminders: [..._reminders]..sort(),
      autoFail: _autoFail,
      lockPast: _lockPast);

  Future<void> _save() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (_title.text.trim().isEmpty) {
      setState(() => _titleError = 'Judul goal wajib diisi.');
      return;
    }
    // The pending step is explicit input and must not disappear on Save.
    if (_step.text.trim().isNotEmpty) _addStep();
    final target = int.tryParse(_target.text);
    if (_method == 'numeric' &&
        (target == null || target < 1 || target > 1000000)) {
      setState(() => _error = 'Target harus berupa angka 1–1.000.000.');
      return;
    }
    if (_method == 'checklist' && _steps.isEmpty) {
      setState(
          () => _error = 'Tambahkan minimal satu langkah untuk sub-tugas.');
      return;
    }
    if (_recurrence == 'weekly' && _weekdays.isEmpty) {
      setState(() => _error = 'Pilih minimal satu hari untuk jadwal mingguan.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
      _titleError = null;
    });
    try {
      final saved =
          await widget.onSave(GoalEditorResult(_title.text.trim(), _details));
      if (mounted && saved) Navigator.of(context).pop();
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _addStep() {
    final text = _step.text.trim();
    if (text.isEmpty || _steps.length >= 100) return;
    setState(() {
      _steps.add(GoalStep(
          id: 'step_${wibNow().microsecondsSinceEpoch}_${_steps.length}',
          label: text));
      _step.clear();
    });
  }

  Widget _section(String title, String tag) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Expanded(
            child: Text(title,
                style: const TextStyle(
                    fontFamily: 'PlusJakartaSans',
                    fontSize: 15,
                    fontWeight: FontWeight.w700))),
        const SizedBox(width: 6),
        GoalPill(tag)
      ]));

  Widget _field(String label, TextEditingController controller, String hint,
          {Key? key, bool note = false}) =>
      GoalSurface(
          padding:
              EdgeInsets.symmetric(horizontal: 14, vertical: note ? 12 : 15),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label,
                style: TextStyle(
                    fontFamily: 'PlusJakartaSans',
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .2,
                    color: note ? const Color(0xFF687582) : goalPurple)),
            const SizedBox(height: 9),
            TextField(
                key: key,
                controller: controller,
                enabled: !_busy,
                maxLength: note ? 5000 : 200,
                minLines: note ? 2 : 1,
                maxLines: note ? 5 : 3,
                style: TextStyle(
                    fontFamily: 'PlusJakartaSans',
                    fontSize: note ? 12 : 14,
                    height: 1.4,
                    color: goalInk),
                decoration: InputDecoration.collapsed(
                        hintText: hint,
                        hintMaxLines: note ? 2 : 1,
                        hintStyle: TextStyle(
                            fontFamily: 'PlusJakartaSans',
                            fontSize: note ? 12 : 14,
                            color: goalMuted))
                    .copyWith(
                        filled: false,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        counterText: '',
                        errorText: note ? null : _titleError)),
          ]));

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_busy,
      child: Theme(
          data: Theme.of(context).copyWith(
            textTheme: Theme.of(context)
                .textTheme
                .apply(bodyColor: goalInk, displayColor: goalInk),
          ),
          child: Scaffold(
              backgroundColor: const Color(0xFF602274),
              body: Container(
                decoration: const BoxDecoration(gradient: goalGradient),
                child: SafeArea(
                    child: Align(
                        alignment: Alignment.topCenter,
                        child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: SingleChildScrollView(
                              key: const Key('goal-editor-scroll'),
                              padding: EdgeInsets.only(
                                  bottom: 10 +
                                      MediaQuery.viewInsetsOf(context).bottom),
                              child: AbsorbPointer(
                                  absorbing: _busy,
                                  child: Column(
                                      key: const Key('goal-editor-content'),
                                      children: [
                                        Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                20, 18, 20, 10),
                                            child: Row(children: [
                                              IconButton(
                                                  tooltip: 'Kembali',
                                                  onPressed: () =>
                                                      Navigator.maybePop(
                                                          context),
                                                  icon: const Icon(
                                                      Icons.chevron_left,
                                                      color: Colors.white,
                                                      size: 28)),
                                              Expanded(
                                                  child: Center(
                                                      child: Image.asset(
                                                          'assets/goals/flower-white.png',
                                                          width: 36,
                                                          height: 36))),
                                              TextButton.icon(
                                                  onPressed: () =>
                                                      setState(_restore),
                                                  style: TextButton.styleFrom(
                                                      backgroundColor:
                                                          Colors.white.withValues(
                                                              alpha: .18),
                                                      foregroundColor:
                                                          Colors.white,
                                                      padding: const EdgeInsets.symmetric(
                                                          horizontal: 12),
                                                      minimumSize:
                                                          const Size(0, 34)),
                                                  icon: const Icon(
                                                      Icons.restart_alt_rounded,
                                                      size: 17),
                                                  label: Text(_editing ? 'Pulihkan' : 'Reset',
                                                      style: const TextStyle(
                                                          fontFamily:
                                                              'PlusJakartaSans',
                                                          fontSize: 13))),
                                            ])),
                                        Padding(
                                            padding: const EdgeInsets.fromLTRB(
                                                28, 0, 28, 20),
                                            child: Text(
                                                _editing
                                                    ? 'Perbarui target atau\nkebiasaanmu'
                                                    : 'Target atau kebiasaan apa\nyang ingin dibangun?',
                                                textAlign: TextAlign.center,
                                                style: const TextStyle(
                                                    fontFamily:
                                                        'PlusJakartaSans',
                                                    color: Colors.white,
                                                    fontSize: 24,
                                                    height: 1.35,
                                                    fontWeight: FontWeight.w700,
                                                    letterSpacing: -.6))),
                                        Container(
                                            margin: const EdgeInsets.symmetric(
                                                horizontal: 10),
                                            padding: EdgeInsets.fromLTRB(
                                                20, _editing ? 24 : 30, 20, 24),
                                            decoration: BoxDecoration(
                                                color: goalPaper,
                                                borderRadius:
                                                    BorderRadius.circular(32)),
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.stretch,
                                                children: [
                                                  if (_editing) ...[
                                                    const Center(
                                                        child: GoalPill(
                                                            'Mode Edit Habit',
                                                            fontSize: 11,
                                                            verticalPadding: 2,
                                                            icon: Icons.edit,
                                                            color: Color(
                                                                0xFFA55B1B),
                                                            background: Color(
                                                                0xFFFFF3C8))),
                                                    const SizedBox(height: 10),
                                                  ],
                                                  Text(
                                                      _editing
                                                          ? 'Edit Rincian Target'
                                                          : 'Rincian Target Utama',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                          fontFamily:
                                                              'PlusJakartaSans',
                                                          fontSize: 20,
                                                          fontWeight:
                                                              FontWeight.w700)),
                                                  const SizedBox(height: 10),
                                                  Text(
                                                      _editing
                                                          ? 'Sesuaikan kembali target, jadwal, atau langkah kebiasaan ini'
                                                          : 'Pilih metode pencatatan yang paling sesuai dengan dirimu',
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                          fontFamily:
                                                              'PlusJakartaSans',
                                                          color: goalMuted,
                                                          fontSize: 15,
                                                          height: 1.4)),
                                                  const SizedBox(height: 12),
                                                  Center(
                                                      child: GoalPill(
                                                          '${goalDateLabel(_date)}${_time.isEmpty ? '' : ', ${_time.replaceAll(':', '.')}'}',
                                                          icon: Icons
                                                              .calendar_today_outlined,
                                                          fontSize: 13)),
                                                  const SizedBox(height: 22),
                                                  _field(
                                                      'NAMA TARGET / KEBIASAAN *',
                                                      _title,
                                                      'Misal: Baca 20 halaman, Minum air putih...',
                                                      key: const Key(
                                                          'goal-title')),
                                                  const SizedBox(height: 12),
                                                  _field(
                                                      'CATATAN / MOTIVASI',
                                                      _note,
                                                      'Tambahkan deskripsi, aturan, atau alasan mengapa ini penting...',
                                                      note: true,
                                                      key: const Key(
                                                          'goal-note')),
                                                  const SizedBox(height: 20),
                                                  Row(children: [
                                                    const Expanded(
                                                        child: Text(
                                                            'Metode Pencatatan',
                                                            style: TextStyle(
                                                                fontFamily:
                                                                    'PlusJakartaSans',
                                                                fontSize: 15,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700))),
                                                    GoalPill(
                                                        switch (_method) {
                                                          'numeric' =>
                                                            'Terukur',
                                                          'checklist' =>
                                                            'Bertahap',
                                                          _ => 'Sederhana'
                                                        },
                                                        color: const Color(
                                                            0xFFA55B1B),
                                                        background: const Color(
                                                            0xFFFFF3C8))
                                                  ]),
                                                  const SizedBox(height: 12),
                                                  Row(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .start,
                                                      children: [
                                                        for (final method in [
                                                          'yes_no',
                                                          'numeric',
                                                          'checklist'
                                                        ]) ...[
                                                          if (method !=
                                                              'yes_no')
                                                            const SizedBox(
                                                                width: 10),
                                                          Expanded(
                                                              child:
                                                                  _methodTile(
                                                                      method)),
                                                        ]
                                                      ]),
                                                  if (_method == 'numeric') ...[
                                                    const SizedBox(height: 24),
                                                    _numericTarget()
                                                  ],
                                                  const SizedBox(height: 26),
                                                  _section(
                                                      'Daftar Langkah (Checklist)',
                                                      '${_steps.length} langkah'),
                                                  for (final step
                                                      in _steps) ...[
                                                    GoalSurface(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                                left: 14,
                                                                top: 5,
                                                                bottom: 5,
                                                                right: 5),
                                                        radius: 12,
                                                        child: Row(children: [
                                                          const Icon(
                                                              Icons
                                                                  .check_circle,
                                                              color: goalPurple,
                                                              size: 14),
                                                          const SizedBox(
                                                              width: 12),
                                                          Expanded(
                                                              child: Text(
                                                                  step.label,
                                                                  maxLines:
                                                                      _editing
                                                                          ? null
                                                                          : 1,
                                                                  overflow: _editing
                                                                      ? null
                                                                      : TextOverflow
                                                                          .ellipsis,
                                                                  style: const TextStyle(
                                                                      fontFamily:
                                                                          'PlusJakartaSans',
                                                                      fontSize:
                                                                          12,
                                                                      height:
                                                                          1.4))),
                                                          IconButton(
                                                              constraints:
                                                                  const BoxConstraints(
                                                                      minWidth:
                                                                          28,
                                                                      minHeight:
                                                                          34,
                                                                      maxWidth:
                                                                          28,
                                                                      maxHeight:
                                                                          34),
                                                              padding:
                                                                  EdgeInsets
                                                                      .zero,
                                                              visualDensity:
                                                                  VisualDensity
                                                                      .compact,
                                                              tooltip:
                                                                  'Hapus langkah ${step.label}',
                                                              icon: const Icon(
                                                                  Icons.close,
                                                                  size: 18,
                                                                  color:
                                                                      goalMuted),
                                                              onPressed: () =>
                                                                  setState(() =>
                                                                      _steps.remove(
                                                                          step))),
                                                        ])),
                                                    const SizedBox(height: 8),
                                                  ],
                                                  GoalSurface(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                          horizontal: 14,
                                                          vertical: 6),
                                                      child: Row(children: [
                                                        const Icon(
                                                            Icons.playlist_add,
                                                            color: goalPurple,
                                                            size: 20),
                                                        const SizedBox(
                                                            width: 12),
                                                        Expanded(
                                                            child: TextField(
                                                                key: const Key(
                                                                    'goal-new-step'),
                                                                controller:
                                                                    _step,
                                                                maxLength: 500,
                                                                maxLines: 1,
                                                                minLines: 1,
                                                                style: const TextStyle(
                                                                    fontFamily:
                                                                        'PlusJakartaSans',
                                                                    fontSize:
                                                                        13),
                                                                onSubmitted: (_) =>
                                                                    _addStep(),
                                                                decoration: const InputDecoration(
                                                                    isDense:
                                                                        true,
                                                                    hintMaxLines:
                                                                        1,
                                                                    hintText:
                                                                        'Tulis langkah kecil yang ingin dilakukan...',
                                                                    hintStyle: TextStyle(
                                                                        fontFamily:
                                                                            'PlusJakartaSans',
                                                                        color:
                                                                            goalMuted),
                                                                    border:
                                                                        InputBorder
                                                                            .none,
                                                                    enabledBorder:
                                                                        InputBorder
                                                                            .none,
                                                                    focusedBorder:
                                                                        InputBorder
                                                                            .none,
                                                                    filled:
                                                                        false,
                                                                    counterText:
                                                                        '',
                                                                    contentPadding:
                                                                        EdgeInsets.symmetric(
                                                                            vertical:
                                                                                8)))),
                                                      ])),
                                                  const SizedBox(height: 8),
                                                  GoalButton('Tambah Langkah',
                                                      onPressed:
                                                          _steps.length >= 100
                                                              ? null
                                                              : _addStep),
                                                  const SizedBox(height: 24),
                                                  _schedule(),
                                                  const SizedBox(height: 26),
                                                  _section('Pengingat',
                                                      'Notifikasi'),
                                                  for (final reminder
                                                      in _reminders) ...[
                                                    GoalSurface(
                                                        radius: 12,
                                                        padding:
                                                            const EdgeInsets
                                                                .only(
                                                                left: 14,
                                                                right: 5,
                                                                top: 2,
                                                                bottom: 2),
                                                        child: Row(children: [
                                                          const Icon(
                                                              Icons
                                                                  .notifications_active,
                                                              color: goalPurple,
                                                              size: 17),
                                                          const SizedBox(
                                                              width: 12),
                                                          Expanded(
                                                              child: Text(
                                                                  reminder == 0
                                                                      ? 'Saat waktunya'
                                                                      : '$reminder menit sebelumnya',
                                                                  style: const TextStyle(
                                                                      fontFamily:
                                                                          'PlusJakartaSans',
                                                                      fontSize:
                                                                          13))),
                                                          IconButton(
                                                              constraints: const BoxConstraints(
                                                                  minWidth: 34,
                                                                  minHeight:
                                                                      34),
                                                              visualDensity:
                                                                  VisualDensity
                                                                      .compact,
                                                              tooltip:
                                                                  'Hapus pengingat $reminder menit',
                                                              onPressed: () =>
                                                                  setState(() =>
                                                                      _reminders
                                                                          .remove(
                                                                              reminder)),
                                                              icon: const Icon(
                                                                  Icons.close,
                                                                  size: 18,
                                                                  color:
                                                                      goalMuted)),
                                                        ])),
                                                    const SizedBox(height: 8),
                                                  ],
                                                  GoalButton('Tambah Pengingat',
                                                      onPressed:
                                                          _reminders.length >=
                                                                  10
                                                              ? null
                                                              : _addReminder),
                                                  const SizedBox(height: 28),
                                                  _section('Aturan Pelacakan',
                                                      'Disiplin'),
                                                  _rule(
                                                      'Otomatis tandai gagal jika terlewat',
                                                      'Menjaga konsistensi beruntun (streak) saat tengah malam',
                                                      _autoFail,
                                                      (v) => setState(
                                                          () => _autoFail = v),
                                                      const Key(
                                                          'goal-auto-fail')),
                                                  const SizedBox(height: 10),
                                                  _rule(
                                                      'Kunci perubahan untuk tanggal lampau',
                                                      'Cegah pengeditan riwayat setelah lewat 24 jam',
                                                      _lockPast,
                                                      (v) => setState(
                                                          () => _lockPast = v),
                                                      const Key(
                                                          'goal-lock-past')),
                                                  if (_error != null)
                                                    Padding(
                                                        padding:
                                                            const EdgeInsets
                                                                .only(top: 18),
                                                        child: Text(_error!,
                                                            style: TextStyle(
                                                                fontFamily:
                                                                    'PlusJakartaSans',
                                                                color: Theme.of(
                                                                        context)
                                                                    .colorScheme
                                                                    .error))),
                                                  const SizedBox(height: 32),
                                                  GoalButton(
                                                      _busy
                                                          ? 'Menyimpan...'
                                                          : _editing
                                                              ? 'Simpan Perubahan'
                                                              : 'Simpan Target',
                                                      icon: Icons.check,
                                                      primary: true,
                                                      onPressed:
                                                          _busy ? null : _save),
                                                  if (_editing) ...[
                                                    const SizedBox(height: 10),
                                                    FilledButton.icon(
                                                        onPressed: () =>
                                                            Navigator.maybePop(
                                                                context),
                                                        style: FilledButton.styleFrom(
                                                            backgroundColor:
                                                                const Color(
                                                                    0xFFF0F3F7),
                                                            foregroundColor:
                                                                const Color(
                                                                    0xFF53606D),
                                                            minimumSize:
                                                                const Size.fromHeight(
                                                                    42),
                                                            textStyle: const TextStyle(
                                                                fontFamily:
                                                                    'PlusJakartaSans',
                                                                fontSize: 13,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w700)),
                                                        icon: const Icon(Icons.close,
                                                            size: 16),
                                                        label: const Text(
                                                            'Batal & Kembali ke Daftar')),
                                                  ],
                                                ])),
                                      ])),
                            )))),
              ))));

  Widget _methodTile(String method) {
    final selected = _method == method;
    final iconColor = method == 'numeric'
        ? const Color(0xFFC18A25)
        : method == 'checklist'
            ? const Color(0xFFC13D82)
            : goalPurple;
    final circle = method == 'numeric'
        ? const Color(0xFFFFF3C8)
        : method == 'checklist'
            ? const Color(0xFFFBE7F1)
            : const Color(0xFFF6EEF8);
    return Semantics(
        selected: selected,
        button: true,
        child: InkWell(
            key: Key('goal-method-$method'),
            onTap: () => setState(() => _method = method),
            borderRadius: BorderRadius.circular(15),
            child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 14),
                constraints: const BoxConstraints(minHeight: 91),
                decoration: BoxDecoration(
                    color: selected ? const Color(0xFFFAF5FC) : Colors.white,
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(
                        color: selected ? goalPurple : const Color(0xFFF0F0F4),
                        width: 2),
                    boxShadow: selected
                        ? const [
                            BoxShadow(
                                color: Color(0x149853A4),
                                blurRadius: 8,
                                offset: Offset(0, 4))
                          ]
                        : []),
                child: Column(children: [
                  Container(
                      width: 40,
                      height: 40,
                      decoration:
                          BoxDecoration(color: circle, shape: BoxShape.circle),
                      child: Icon(goalMethodIcon(method),
                          color: iconColor,
                          size: method == 'yes_no' ? 17 : 23)),
                  const SizedBox(height: 10),
                  Text(goalMethodLabel(method),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color:
                              selected ? goalPurple : const Color(0xFF53606D))),
                ]))));
  }

  Widget _numericTarget() => GoalSurface(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Target Capaian Harian',
            style: TextStyle(
                fontFamily: 'PlusJakartaSans',
                fontSize: 15,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        const Text('Atur jumlah angka dan satuan target setiap sesi',
            style: TextStyle(
                fontFamily: 'PlusJakartaSans',
                fontSize: 14,
                height: 1.4,
                color: goalMuted)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
              child: GoalSurface(
                  color: goalTint,
                  radius: 11,
                  padding: EdgeInsets.zero,
                  child: Row(children: [
                    IconButton(
                        tooltip: 'Kurangi target',
                        onPressed: () => setState(() => _target.text =
                            '${((int.tryParse(_target.text) ?? 1) - 1).clamp(1, 1000000)}'),
                        icon: const Icon(Icons.remove,
                            size: 16, color: goalPurple)),
                    Expanded(
                        child: TextField(
                            key: const Key('goal-target'),
                            controller: _target,
                            textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            style: const TextStyle(
                                fontFamily: 'PlusJakartaSans',
                                fontSize: 15,
                                fontWeight: FontWeight.w700),
                            decoration: const InputDecoration.collapsed(
                                hintText: '1'))),
                    IconButton(
                        tooltip: 'Tambah target',
                        onPressed: () => setState(() => _target.text =
                            '${((int.tryParse(_target.text) ?? 1) + 1).clamp(1, 1000000)}'),
                        icon:
                            const Icon(Icons.add, size: 16, color: goalPurple)),
                  ]))),
          const SizedBox(width: 10),
          Expanded(
              child: GoalSurface(
                  color: goalTint,
                  radius: 11,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
                  child: TextField(
                      key: const Key('goal-unit'),
                      controller: _unit,
                      maxLength: 80,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: 'PlusJakartaSans',
                          fontSize: 13,
                          color: goalPurple),
                      decoration:
                          const InputDecoration.collapsed(hintText: 'satuan')
                              .copyWith(counterText: '')))),
        ]),
      ]));

  Widget _schedule() => GoalSurface(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Jadwal & Frekuensi',
                    style: TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Text('Atur tanggal mulai, waktu, dan pengulangan',
                    style: TextStyle(
                        fontFamily: 'PlusJakartaSans',
                        fontSize: 12,
                        color: goalMuted,
                        height: 1.4)),
              ])),
          SizedBox(width: 8),
          GoalPill('Rutin')
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: _scheduleCell(
                  'TANGGAL MULAI',
                  InkWell(
                      onTap: _pickDate,
                      child: Row(children: [
                        Expanded(
                            child: Text(_date.split('-').reversed.join(' / '),
                                style: const TextStyle(
                                    fontFamily: 'PlusJakartaSans',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700))),
                        const Icon(Icons.calendar_today_outlined,
                            size: 15, color: Color(0xFF7F8792))
                      ])))),
          const SizedBox(width: 10),
          Expanded(
              child: _scheduleCell(
                  'WAKTU',
                  InkWell(
                      onTap: _pickTime,
                      child: Row(children: [
                        Expanded(
                            child: Text(_clockLabel,
                                style: const TextStyle(
                                    fontFamily: 'PlusJakartaSans',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700))),
                        const Icon(Icons.schedule,
                            size: 15, color: Color(0xFF7F8792))
                      ])))),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(
              child: _scheduleCell(
                  'PENGULANGAN',
                  DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                          value: _recurrence,
                          isExpanded: true,
                          isDense: true,
                          icon: const Icon(Icons.expand_more,
                              size: 16, color: goalPurple),
                          style: const TextStyle(
                              fontFamily: 'PlusJakartaSans',
                              color: goalPurple,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                          items: const [
                            DropdownMenuItem(
                                value: 'daily', child: Text('Harian')),
                            DropdownMenuItem(
                                value: 'weekly', child: Text('Mingguan'))
                          ],
                          onChanged: (v) => setState(() {
                                _recurrence = v!;
                                _interval = 1;
                              }))))),
          const SizedBox(width: 10),
          Expanded(
              child: _scheduleCell(
                  'SETIAP',
                  Row(children: [
                    _intervalButton(false),
                    Expanded(
                        child: Text(
                            '$_interval ${_recurrence == 'daily' ? 'Hari' : 'Minggu'}',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontFamily: 'PlusJakartaSans',
                                fontSize: 12,
                                color: goalPurple,
                                fontWeight: FontWeight.w600))),
                    _intervalButton(true),
                  ]))),
        ]),
        if (_recurrence == 'weekly') ...[
          const SizedBox(height: 20),
          Row(children: [
            for (final day in [7, 1, 2, 3, 4, 5, 6])
              Expanded(
                  child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: Semantics(
                          selected: _weekdays.contains(day),
                          button: true,
                          label: const [
                            'Senin',
                            'Selasa',
                            'Rabu',
                            'Kamis',
                            'Jumat',
                            'Sabtu',
                            'Minggu'
                          ][day - 1],
                          child: InkWell(
                              key: Key('goal-weekday-$day'),
                              borderRadius: BorderRadius.circular(99),
                              onTap: () => setState(() => _weekdays.contains(day)
                                  ? _weekdays.remove(day)
                                  : _weekdays.add(day)),
                              child: Container(
                                  constraints:
                                      const BoxConstraints(minHeight: 36),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: _weekdays.contains(day)
                                          ? goalPurple
                                          : goalTint,
                                      boxShadow: _weekdays.contains(day)
                                          ? const [
                                              BoxShadow(
                                                  color: Color(0x269853A4),
                                                  blurRadius: 6,
                                                  offset: Offset(0, 4))
                                            ]
                                          : []),
                                  child: Text(const ['S', 'S', 'R', 'K', 'J', 'S', 'M'][day - 1], style: TextStyle(fontFamily: 'PlusJakartaSans', fontSize: 13, fontWeight: FontWeight.w700, color: _weekdays.contains(day) ? Colors.white : goalPurple))))))),
          ]),
          const SizedBox(height: 12),
          Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                  color: const Color(0xFFF6F7F9),
                  borderRadius: BorderRadius.circular(8)),
              child: Text.rich(
                  TextSpan(children: [
                    const TextSpan(text: 'Berulang setiap '),
                    TextSpan(
                        text: _interval == 1 ? 'minggu' : '$_interval minggu',
                        style: const TextStyle(
                            color: goalPurple, fontWeight: FontWeight.w700)),
                    const TextSpan(text: ' pada '),
                    TextSpan(
                        text: _weekdays.length == 7
                            ? 'setiap hari.'
                            : '${(_weekdays.toList()..sort()).map((d) => const [
                                  'Sen',
                                  'Sel',
                                  'Rab',
                                  'Kam',
                                  'Jum',
                                  'Sab',
                                  'Min'
                                ][d - 1]).join(', ')}.',
                        style: const TextStyle(
                            color: goalPurple, fontWeight: FontWeight.w700)),
                  ]),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'PlusJakartaSans',
                      fontSize: 14,
                      height: 1.4,
                      color: Color(0xFF6F7C88)))),
        ],
      ]));

  Widget _scheduleCell(String label, Widget child) => Container(
      constraints: const BoxConstraints(minHeight: 62),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
          color: const Color(0xFFF9F5FC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFF0EAF5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(
                fontFamily: 'PlusJakartaSans',
                fontSize: 10,
                color: goalMuted,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        child,
      ]));

  Widget _intervalButton(bool add) => SizedBox(
      width: 25,
      height: 25,
      child: IconButton(
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6))),
          tooltip: add ? 'Tambah interval' : 'Kurangi interval',
          onPressed: () => setState(() => _interval =
              (_interval + (add ? 1 : -1))
                  .clamp(1, _recurrence == 'daily' ? 365 : 52)),
          icon: Icon(add ? Icons.add : Icons.remove,
              size: 13, color: goalPurple)));

  Widget _rule(String title, String subtitle, bool value,
          ValueChanged<bool> change, Key key) =>
      GoalSurface(
          padding: const EdgeInsets.fromLTRB(14, 14, 6, 14),
          child: InkWell(
              onTap: () => change(!value),
              child: Row(children: [
                Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text(title,
                          style: const TextStyle(
                              fontFamily: 'PlusJakartaSans',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 3),
                      Text(subtitle,
                          style: const TextStyle(
                              fontFamily: 'PlusJakartaSans',
                              fontSize: 11,
                              height: 1.4,
                              color: goalMuted)),
                    ])),
                Checkbox(
                    key: key,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    value: value,
                    activeColor: goalPurple,
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4)),
                    onChanged: (v) => change(v!)),
              ])));

  String get _clockLabel {
    if (_time.isEmpty) return 'Tanpa waktu';
    final parts = _time.split(':');
    final h = int.parse(parts[0]);
    return '${(h % 12 == 0 ? 12 : h % 12).toString().padLeft(2, '0')} : ${parts[1]}  ${h < 12 ? 'AM' : 'PM'}';
  }

  Future<void> _pickDate() async {
    final date = DateTime.tryParse(_date) ?? wibNow();
    final selected = await showDatePicker(
        context: context,
        initialDate: date,
        firstDate: DateTime(2000),
        lastDate: DateTime(2100),
        helpText: 'Tanggal mulai (WIB)');
    if (selected != null && mounted)
      setState(() => _date = wibDateKey(
          wibFromParts(selected.year, selected.month, selected.day)));
  }

  Future<void> _pickTime() async {
    final parts = _time.split(':');
    final time = await showTimePicker(
        context: context,
        initialTime: parts.length == 2
            ? TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]))
            : TimeOfDay.fromDateTime(wibNow()),
        helpText: 'Waktu target (WIB)');
    if (time != null && mounted)
      setState(() => _time =
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}');
  }

  Future<void> _addReminder() async {
    final controller = TextEditingController(text: '30');
    final value = await showDialog<int>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Tambah Pengingat'),
                content: TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                        labelText: 'Menit sebelum jadwal',
                        helperText: '0–10080 menit (0 = saat waktunya)')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Batal')),
                  FilledButton(
                      onPressed: () {
                        final n = int.tryParse(controller.text);
                        if (n != null && n >= 0 && n <= 10080)
                          Navigator.pop(ctx, n);
                      },
                      child: const Text('Tambah'))
                ]));
    // Dialog route keeps its TextField alive through the reverse transition.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    controller.dispose();
    if (value != null && mounted && !_reminders.contains(value)) {
      setState(() => _reminders.add(value));
    }
  }
}
