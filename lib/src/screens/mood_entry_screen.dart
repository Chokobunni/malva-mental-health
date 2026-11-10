import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../services/server_clock.dart';
import '../time/wib.dart';

/// Standalone mood entry; returns true only after the server saves this account.
class MoodEntryScreen extends ConsumerStatefulWidget {
  const MoodEntryScreen({super.key, this.session, this.apiClient});
  final AuthSession? session;
  final MalvaApiClient? apiClient;
  @override
  ConsumerState<MoodEntryScreen> createState() => _MoodEntryScreenState();
}

class _MoodEntryScreenState extends ConsumerState<MoodEntryScreen> {
  static const purple = Color(0xff9c48ad);
  late final String? _owner;
  late final DateTime _occurredAt;
  bool _bound = false, _invalid = false, _saving = false;
  int _generation = 0;
  String? _error;
  MoodValue _mood = MoodValue.okay;
  double _anxiety = 5, _irritability = 5, _energy = 5;
  int _sleepHours = 7, _sleepMinutes = 0;
  String? _key(AuthSession? s) =>
      s == null ? null : '${s.role.name}|${s.backendUserId ?? s.identifier}';
  AuthSession? get _session {
    final active = ref.read(authStateProvider).session;
    if (_invalid ||
        (_bound && _key(active) != _owner) ||
        (active != null && _key(active) != _owner)) return null;
    return active ?? widget.session;
  }

  @override
  void initState() {
    super.initState();
    final active = ref.read(authStateProvider).session;
    _owner = _key(widget.session ?? active);
    _bound = active != null;
    _occurredAt = ServerClock.now();
  }

  Future<void> _save() async {
    if (_saving || _session == null) return;
    final token = _session?.accessToken;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Masuk ke akun untuk menyimpan mood.');
      return;
    }
    final generation = ++_generation;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final api = widget.apiClient ?? ref.read(apiClientProvider);
      if (api == null) throw StateError('Api unavailable');
      await api.createMoodCheckin(
          accessToken: token,
          mood: _mood.name,
          sleepHours: _sleepHours + _sleepMinutes / 60,
          energy: _energy.round(),
          anxiety: _anxiety.round(),
          irritability: _irritability.round(),
          note: '',
          occurredAt: _occurredAt);
      if (!mounted || generation != _generation || _session == null) return;
      Navigator.pop(context, true);
    } on Object {
      if (!mounted || generation != _generation || _session == null) return;
      setState(() {
        _saving = false;
        _error = 'Mood belum tersimpan. Periksa koneksi lalu coba lagi.';
      });
    }
  }

  String _dateLabel(DateTime value) {
    final d = toWib(value);
    const months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember'
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}, ${d.hour.toString().padLeft(2, '0')}.${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authStateProvider, (previous, next) {
      if (next.session != null) _bound = true;
      if (_key(next.session) != _owner &&
          (previous?.session != null || next.session != null)) {
        _generation++;
        setState(() {
          _invalid = true;
          _saving = false;
        });
      }
    });
    final active = _session != null;
    return PopScope(
        canPop: !_saving || !active,
        child: Scaffold(
            body: Container(
                decoration: const BoxDecoration(
                    gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                      Color(0xff662c83),
                      Color(0xffaa5dbd),
                      Color(0xffd484db),
                      Color(0xffeda3ee),
                      Color(0xfff9b7f7)
                    ],
                        stops: [
                      0,
                      .24,
                      .47,
                      .70,
                      1
                    ])),
                child: SafeArea(
                    child: ListView(
                        padding: const EdgeInsets.fromLTRB(13, 6, 13, 14),
                        children: [
                      SizedBox(
                          height: 50,
                          child: Stack(alignment: Alignment.center, children: [
                            Align(
                                alignment: Alignment.centerLeft,
                                child: Transform.translate(
                                    offset: const Offset(21, -4),
                                    child: IconButton(
                                        tooltip: 'Kembali',
                                        onPressed: _saving
                                            ? null
                                            : () => Navigator.maybePop(context),
                                        icon: const Icon(
                                            Icons.arrow_back_ios_new_rounded,
                                            color: Colors.white,
                                            size: 26)))),
                            Image.asset('assets/checkin/flower-white.png',
                                width: 40, height: 46),
                          ])),
                      const Padding(
                          padding: EdgeInsets.fromLTRB(25, 9, 25, 10),
                          child: Text('Bagaimana perasaan\nAnda?',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontSize: 27,
                                  height: 1.25,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white))),
                      if (!active)
                        const Padding(
                            padding: EdgeInsets.all(24),
                            child: Text(
                                'Akun berubah. Buka kembali check-in dari akun aktif.',
                                style: TextStyle(color: Colors.white)))
                      else
                        Container(
                            key: const Key('mood-entry-form'),
                            padding: const EdgeInsets.fromLTRB(22, 21, 22, 20),
                            decoration: BoxDecoration(
                                color: const Color(0xfffffdff),
                                borderRadius: BorderRadius.circular(38)),
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text('Suasana Hati Keseluruhan',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 18,
                                          height: 1.2,
                                          fontWeight: FontWeight.w700,
                                          color: Color(0xff465260))),
                                  const SizedBox(height: 2),
                                  const Text(
                                      'Pilih yang paling sesuai dengan dirimu',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          fontSize: 13,
                                          height: 1.2,
                                          color: Color(0xff9aa4b4))),
                                  const SizedBox(height: 6),
                                  Center(
                                      child: Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 11, vertical: 4),
                                          decoration: BoxDecoration(
                                              color: const Color(0xfffcf2ff),
                                              borderRadius:
                                                  BorderRadius.circular(30)),
                                          child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                    Icons
                                                        .calendar_today_outlined,
                                                    color: Color(0xff8018a5),
                                                    size: 13),
                                                const SizedBox(width: 8),
                                                Flexible(
                                                    child: Text(
                                                        _dateLabel(_occurredAt),
                                                        style: const TextStyle(
                                                            color: Color(
                                                                0xff8018a5),
                                                            fontWeight:
                                                                FontWeight.w700,
                                                            fontSize: 14))),
                                              ]))),
                                  const SizedBox(height: 13),
                                  Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (final mood in MoodValue.values)
                                          Expanded(
                                              child: Padding(
                                                  padding: const EdgeInsets
                                                      .symmetric(horizontal: 3),
                                                  child: Semantics(
                                                      selected: _mood == mood,
                                                      button: true,
                                                      label: mood.label,
                                                      child: InkWell(
                                                        key: ValueKey(
                                                            'mood-${mood.name}'),
                                                        onTap: _saving
                                                            ? null
                                                            : () => setState(
                                                                () => _mood =
                                                                    mood),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(18),
                                                        child: Container(
                                                            constraints:
                                                                const BoxConstraints(
                                                                    minHeight:
                                                                        96),
                                                            padding: const EdgeInsets.symmetric(
                                                                vertical: 13,
                                                                horizontal: 2),
                                                            decoration: BoxDecoration(
                                                                color: _mood == mood
                                                                    ? const Color(
                                                                        0xfff9ecfc)
                                                                    : Colors
                                                                        .white,
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                        18),
                                                                border: Border.all(
                                                                    color: _mood ==
                                                                            mood
                                                                        ? const Color(
                                                                            0xffc36bc8)
                                                                        : const Color(
                                                                            0xfff2eff5),
                                                                    width: _mood == mood
                                                                        ? 2.5
                                                                        : 1)),
                                                            child: Column(
                                                                children: [
                                                                  Image.asset(
                                                                      'assets/checkin/entry-${mood.name}.png',
                                                                      width: 36,
                                                                      height:
                                                                          36),
                                                                  const SizedBox(
                                                                      height:
                                                                          6),
                                                                  Text(
                                                                      mood
                                                                          .label,
                                                                      textAlign:
                                                                          TextAlign
                                                                              .center,
                                                                      style: TextStyle(
                                                                          fontSize:
                                                                              12.5,
                                                                          height:
                                                                              1.1,
                                                                          fontWeight: _mood == mood
                                                                              ? FontWeight
                                                                                  .w700
                                                                              : FontWeight
                                                                                  .w500,
                                                                          color: _mood == mood
                                                                              ? const Color(0xff8617a5)
                                                                              : const Color(0xff465260)))
                                                                ])),
                                                      ))))
                                      ]),
                                  const SizedBox(height: 18),
                                  const Text('Rincian Gejala',
                                      style: TextStyle(
                                          fontSize: 17,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xff465260))),
                                  const SizedBox(height: 7),
                                  _metric('Kecemasan', 'anxiety', _anxiety,
                                      (v) => setState(() => _anxiety = v),
                                      zero: 'Tidak Ada'),
                                  _metric(
                                      'Iritabilitas',
                                      'irritability',
                                      _irritability,
                                      (v) => setState(() => _irritability = v),
                                      zero: 'Rendah'),
                                  _metric('Energi', 'energy', _energy,
                                      (v) => setState(() => _energy = v),
                                      zero: 'Habis', energy: true),
                                  const SizedBox(height: 1),
                                  Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 18, vertical: 10),
                                      decoration: BoxDecoration(
                                          color: Colors.white,
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          boxShadow: const [
                                            BoxShadow(
                                                color: Color(0x08772d88),
                                                blurRadius: 12,
                                                offset: Offset(0, 4))
                                          ]),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            const Text('Durasi Tidur',
                                                style: TextStyle(
                                                    fontSize: 17,
                                                    height: 1.2,
                                                    fontWeight: FontWeight.w600,
                                                    color: Color(0xff465260))),
                                            const Text(
                                                'Atur jam dan menit tidur',
                                                style: TextStyle(
                                                    fontSize: 14,
                                                    height: 1.2,
                                                    color: Color(0xff9aa4b4))),
                                            const SizedBox(height: 6),
                                            Row(children: [
                                              Expanded(
                                                  child: _stepper('sleep-hours',
                                                      _sleepHours, 'j', () {
                                                if (_sleepHours > 0)
                                                  setState(() => _sleepHours--);
                                              }, () {
                                                if (_sleepHours < 24)
                                                  setState(() {
                                                    _sleepHours++;
                                                    if (_sleepHours == 24)
                                                      _sleepMinutes = 0;
                                                  });
                                              })),
                                              const SizedBox(width: 28),
                                              Expanded(
                                                  child: _stepper(
                                                      'sleep-minutes',
                                                      _sleepMinutes,
                                                      'm', () {
                                                if (_sleepMinutes > 0)
                                                  setState(
                                                      () => _sleepMinutes--);
                                              }, () {
                                                if (_sleepHours < 24 &&
                                                    _sleepMinutes < 59)
                                                  setState(
                                                      () => _sleepMinutes++);
                                              }))
                                            ]),
                                          ])),
                                  if (_error != null)
                                    Padding(
                                        padding: const EdgeInsets.only(top: 12),
                                        child: Text(_error!,
                                            style: TextStyle(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .error))),
                                  const SizedBox(height: 18),
                                  Container(
                                      decoration: BoxDecoration(
                                          gradient: const LinearGradient(colors: [Color(0xff85439a), Color(0xffc06aca)]),
                                          borderRadius: BorderRadius.circular(17),
                                          boxShadow: const [
                                            BoxShadow(
                                                color: Color(0x207d328c),
                                                blurRadius: 10,
                                                offset: Offset(0, 5))
                                          ]),
                                      child: FilledButton.icon(
                                          key: const Key('save-mood-entry'),
                                          onPressed: _saving ? null : _save,
                                          style: FilledButton.styleFrom(
                                              backgroundColor:
                                                  Colors.transparent,
                                              disabledBackgroundColor:
                                                  Colors.transparent,
                                              shadowColor: Colors.transparent,
                                              minimumSize: const Size(0, 46),
                                              shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                          17))),
                                          icon: _saving
                                              ? const SizedBox.square(
                                                  dimension: 18,
                                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                              : const Icon(Icons.check_rounded, size: 26),
                                          label: Text(_saving ? 'Menyimpan...' : 'Simpan', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 18, fontWeight: FontWeight.w500, color: Colors.white)))),
                                ])),
                    ])))));
  }

  Widget _metric(
      String label, String id, double value, ValueChanged<double> changed,
      {required String zero, bool energy = false}) {
    final level = value == 0
        ? (energy ? 'Habis' : 'Rendah')
        : value < 5
            ? 'Rendah'
            : value == 5
                ? 'Sedang'
                : value < 10
                    ? 'Tinggi'
                    : 'Sangat Tinggi';
    return Padding(
        padding: EdgeInsets.only(bottom: energy ? 14 : 22),
        child: Column(children: [
          Row(children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                        color: Color(0xff465260)))),
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                decoration: BoxDecoration(
                    color: level == 'Sedang'
                        ? const Color(0xfffff7e7)
                        : const Color(0xfffbf0ff),
                    borderRadius: BorderRadius.circular(30)),
                child: Text(level,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: level == 'Sedang'
                            ? const Color(0xffb47122)
                            : const Color(0xff8617a5)))),
            const SizedBox(width: 7),
            Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                    color: const Color(0xfffcf4ff),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: const Color(0xfff4e8f8))),
                child: Text('${value.round()}/10',
                    style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xffa254bc)))),
          ]),
          SliderTheme(
              data: SliderTheme.of(context).copyWith(
                  trackHeight: 7,
                  activeTrackColor: const Color(0xffefe2f3),
                  inactiveTrackColor: const Color(0xffefe2f3),
                  thumbColor: purple,
                  overlayColor: purple.withValues(alpha: .1),
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 11),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 16),
                  trackShape: const RoundedRectSliderTrackShape(),
                  tickMarkShape: SliderTickMarkShape.noTickMark),
              child: Slider(
                  key: ValueKey('metric-$id'),
                  value: value,
                  min: 0,
                  max: 10,
                  divisions: 10,
                  label: '${value.round()}/10',
                  padding: EdgeInsets.zero,
                  onChanged: _saving ? null : changed)),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final (anchor, alignment) in [
              ('0 ($zero)', TextAlign.start),
              ('5 (Sedang)', TextAlign.center),
              ('10 (Sangat Tinggi)', TextAlign.end)
            ])
              Expanded(
                  child: Text(anchor,
                      textAlign: alignment,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xff9aa4b4), fontSize: 10.5))),
          ]),
        ]));
  }

  Widget _stepper(String id, int value, String unit, VoidCallback minus,
          VoidCallback plus) =>
      Container(
          decoration: BoxDecoration(
              color: const Color(0xfffcf5ff),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: const Color(0xfff5eafa))),
          child: Row(children: [
            Expanded(
                child: IconButton(
                    style: IconButton.styleFrom(
                        minimumSize: const Size(40, 41),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                    padding: EdgeInsets.zero,
                    key: ValueKey('$id-minus'),
                    onPressed: _saving ? null : minus,
                    icon: const Icon(Icons.remove,
                        color: Color(0xff8118a6), size: 17))),
            Text.rich(TextSpan(children: [
              TextSpan(
                  text: '$value',
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Color(0xff465260))),
              TextSpan(
                  text: unit,
                  style:
                      const TextStyle(fontSize: 12, color: Color(0xffb76dc4)))
            ])),
            Expanded(
                child: IconButton(
                    style: IconButton.styleFrom(
                        minimumSize: const Size(40, 41),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                    padding: EdgeInsets.zero,
                    key: ValueKey('$id-plus'),
                    onPressed: _saving ? null : plus,
                    icon: const Icon(Icons.add,
                        color: Color(0xff8118a6), size: 17)))
          ]));
}
