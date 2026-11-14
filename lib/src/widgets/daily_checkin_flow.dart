import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/offline_sync_service.dart';
import '../services/server_clock.dart';
import '../time/wib.dart';

// Five-step daily check-in with account-scoped persistence.

const _dailyCheckInNote = 'Daily check-in';

/// Check-in lengkap memakai marker alur; data lama dikenali dari durasi tidur.
///
/// `MoodEntry.date` berasal dari server saat riwayat dimuat ulang,
/// jadi perbandingan WAJIB lewat hari kalender WIB — kalau tidak, check-in
/// pukul 22:00 WIB terbaca sebagai kemarin dan pasien diminta check-in lagi.
bool hasCheckedInToday(List<MoodEntry> moods) {
  final now = ServerClock.now();
  return moods.any((m) =>
      isSameLocalDay(m.date, now) &&
      (m.sleepHours > 0 || m.note == _dailyCheckInNote));
}

/// Streak hari beruntun check-in (mood tersimpan > 0 hari berturut-turut).
int checkInStreak(List<MoodEntry> moods) =>
    _checkInDateStreak(moods.map((m) => m.date));

int _checkInDateStreak(Iterable<DateTime> dates) {
  // Hari kalender WIB, dibekukan sebagai WIB tengah malam supaya selisih hari
  // dihitung bersih. Dibangun lewat `wibFromParts` (zona WIB), BUKAN
  // `DateTime(...)` yang memakai zona perangkat: selain bergeser di perangkat
  // non-WIB, hari yang punya DST bisa membuat `difference().inDays` meleset.
  DateTime dayOnly(DateTime value) {
    final wib = toWib(value);
    return wibFromParts(wib.year, wib.month, wib.day);
  }

  final days = dates.map(dayOnly).toSet().toList()
    ..sort((a, b) => b.compareTo(a));
  var streak = 0;
  var cursor = dayOnly(ServerClock.now());
  for (final day in days) {
    final diff = cursor.difference(day).inDays;
    if (diff == 0 || diff == 1) {
      streak++;
      cursor = day;
    } else {
      break;
    }
  }
  return streak;
}

class DailyCheckInFlow extends ConsumerStatefulWidget {
  const DailyCheckInFlow(
      {super.key, required this.onSaved, this.onProfile, this.trailing});
  final VoidCallback onSaved;
  final VoidCallback? onProfile;
  final Widget? trailing;
  @override
  ConsumerState<DailyCheckInFlow> createState() => _DailyCheckInFlowState();
}

class _DailyCheckInFlowState extends ConsumerState<DailyCheckInFlow> {
  static const purple = Color(0xff9755ad);
  MoodValue? _mood;
  int _step = 0,
      _hours = 7,
      _minutes = 30,
      _energy = 5,
      _anxiety = 3,
      _irritability = 2;
  bool _saving = false, _done = false;
  String _day = wibDateKey(ServerClock.now());
  int _generation = 0;
  MoodEntry? _savedMood;
  final Set<String> _startedDoses = {}, _finishedDoses = {};
  final Map<String, DateTime> _doseTakenAt = {};
  bool _pending = false;
  final Map<String, String> _doses = {};
  String? _error;
  String? _owner(AuthSession? s) =>
      s == null ? null : '${s.role.name}|${s.backendUserId ?? s.identifier}';
  void _reset() {
    _generation++;
    _day = wibDateKey(ServerClock.now());
    _savedMood = null;
    _startedDoses.clear();
    _doseTakenAt.clear();
    _finishedDoses.clear();
    _pending = false;
    _step = 0;
    _mood = null;
    _hours = 7;
    _minutes = 30;
    _energy = 5;
    _anxiety = 3;
    _irritability = 2;
    _doses.clear();
    _saving = false;
    _done = false;
    _error = null;
  }

  @override
  Widget build(BuildContext context) {
    if (_day != wibDateKey(ServerClock.now())) _reset();
    final session = ref.watch(currentSessionProvider);
    ref.listen<AuthSession?>(currentSessionProvider, (before, after) {
      if (_owner(before) != _owner(after)) setState(_reset);
    });
    final store = ref.watch(malvaStoreProvider);
    ref.watch(syncQueueProvider);
    final queuedDates = <DateTime>[];
    var queuedToday = false;
    for (final item in ref.watch(offlineSyncServiceProvider).queue) {
      if (item.operation != SyncOperation.moodEntry ||
          item.userId != session?.backendUserId) continue;
      final date = parseWibStored(item.payload['date']?.toString());
      if (date == null) continue;
      queuedDates.add(date);
      if (isSameLocalDay(date, ServerClock.now()) &&
          ((item.payload['sleepHours'] as num? ?? 0) > 0 ||
              item.payload['note'] == _dailyCheckInNote)) queuedToday = true;
    }
    final name = session?.displayName.trim().isNotEmpty == true
        ? session!.displayName
        : store.patient.name;
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p[0])
        .join()
        .toUpperCase();
    final done = _done ||
        (_step == 0 && (hasCheckedInToday(store.moodEntries) || queuedToday));
    final streak = _checkInDateStreak([
      ...store.moodEntries.map((m) => m.date),
      ...queuedDates,
    ]);
    return Container(
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xff4e266a),
                  Color(0xff86509f),
                  Color(0xffe4a0d5)
                ]),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                  color: Color(0x18000000),
                  blurRadius: 12,
                  offset: Offset(0, 6))
            ]),
        padding: const EdgeInsets.fromLTRB(23, 42, 23, 26),
        child: DefaultTextStyle(
            style: const TextStyle(fontFamily: 'Roboto', color: Colors.white),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    Image.asset('assets/checkin/flower-white.png',
                        width: 29, height: 34),
                    const Expanded(
                        child: Text('Home',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                                fontSize: 19, fontWeight: FontWeight.w500))),
                    if (widget.trailing != null) widget.trailing!,
                    InkWell(
                        onTap: widget.onProfile,
                        borderRadius: BorderRadius.circular(24),
                        child: Container(
                            width: 40,
                            height: 40,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xff810091),
                                border: Border.all(
                                    color: Colors.white54, width: 2)),
                            child: Text(initials,
                                style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700))))
                  ]),
                  const SizedBox(height: 24),
                  if (_step == 0 || done) ...[
                    Text('Selamat datang, $name!',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 23, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 12),
                    Text(
                        done
                            ? 'Check-in hari ini selesai. Streak $streak hari!'
                            : 'Bagaimana kabarmu hari ini?',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 16, color: Color(0xfff3e7f5))),
                    if (!done) ...[
                      const SizedBox(height: 32),
                      Row(children: [
                        for (final m in MoodValue.values)
                          Expanded(
                              child: InkWell(
                                  onTap: () => setState(() {
                                        _mood = m;
                                        _step = 1;
                                      }),
                                  child: Column(children: [
                                    Image.asset('assets/checkin/${m.name}.png',
                                        width: 40, height: 40),
                                    const SizedBox(height: 14),
                                    Text(m.label,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w500))
                                  ])))
                      ]),
                    ],
                  ] else ...[
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _pill(
                              child: InkWell(
                                  onTap: _saving || _savedMood != null
                                      ? null
                                      : () => setState(() => _step--),
                                  child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.arrow_back_rounded,
                                            size: 15, color: Colors.white),
                                        Text('Kembali',
                                            style: TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600))
                                      ]))),
                          _pill(
                              child: Text('Langkah ${_step + 1} dari 5',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600)))
                        ]),
                    SizedBox(height: _step >= 3 ? 8 : 17),
                    Text(
                        switch (_step) {
                          1 => 'Apakah kamu sudah minum obat\nhari ini?',
                          2 => 'Berapa lama kamu tidur?',
                          3 => 'Bagaimana tingkat energimu?',
                          _ => 'Bagaimana tingkat kecemasan & iritabilitasmu?'
                        },
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 20,
                            height: 1.3,
                            fontWeight: FontWeight.w700)),
                    if (_step == 2) ...[
                      const SizedBox(height: 3),
                      const Text('Catat durasi tidur malammu',
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(fontSize: 13, color: Color(0xfff3e7f5)))
                    ],
                    SizedBox(height: _step >= 3 ? 14 : 20),
                    if (_step == 1) ...[
                      if (store.medications.isEmpty)
                        _card(const Text('Tidak ada jadwal obat hari ini.',
                            style: TextStyle(color: Color(0xff6b7280)))),
                      for (final med in store.medications)
                        Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _medication(med)),
                      const SizedBox(height: 8),
                      _next(outlined: true),
                    ],
                    if (_step == 2)
                      _card(Column(children: [
                        Row(children: [
                          Expanded(
                              child: _counter('sleep-hours', _hours, 'jam', 0,
                                  23, (n) => setState(() => _hours = n))),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _counter(
                                  'sleep-minutes',
                                  _minutes,
                                  'menit',
                                  0,
                                  59,
                                  (n) => setState(() => _minutes = n)))
                        ]),
                        const SizedBox(height: 16),
                        _next()
                      ])),
                    if (_step == 3) ...[
                      Center(
                          child: Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(17),
                                  boxShadow: const [
                                    BoxShadow(
                                        color: Color(0x18000000),
                                        blurRadius: 12,
                                        offset: Offset(0, 8))
                                  ]),
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Image.asset(
                                        'assets/checkin/battery-${_energy == 0 ? 0 : _energy < 5 ? 1 : _energy == 5 ? 5 : _energy < 10 ? 6 : 10}.png',
                                        width: 34,
                                        height: 23),
                                    const SizedBox(height: 4),
                                    Text(
                                        _energy == 0
                                            ? 'Habis'
                                            : _energy < 5
                                                ? 'Rendah'
                                                : _energy == 5
                                                    ? 'Sedang'
                                                    : _energy < 10
                                                        ? 'Tinggi'
                                                        : 'Sangat Tinggi',
                                        style: const TextStyle(
                                            color: Color(0xff4b5563),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700))
                                  ]))),
                      const SizedBox(height: 16),
                      _card(Column(children: [
                        Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Flexible(
                                  child: Text('0 (Habis)',
                                      style: TextStyle(
                                          color: Color(0xff707780),
                                          fontSize: 12))),
                              Text('$_energy / 10',
                                  style: const TextStyle(
                                      color: purple,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800)),
                              const Flexible(
                                  child: Text('10 (Penuh)',
                                      style: TextStyle(
                                          color: Color(0xff707780),
                                          fontSize: 12)))
                            ]),
                        const SizedBox(height: 18),
                        GridView.count(
                            crossAxisCount: 6,
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6,
                            childAspectRatio: 1.35,
                            children: [
                              for (var n = 0; n <= 10; n++)
                                InkWell(
                                    key: ValueKey('energy-$n'),
                                    onTap: () => setState(() => _energy = n),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                            color: n == _energy
                                                ? purple
                                                : const Color(0xfff7f8fa),
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            border: Border.all(
                                                color:
                                                    const Color(0xfff1f1f3))),
                                        child: Text('$n',
                                            style: TextStyle(
                                                color: n == _energy
                                                    ? Colors.white
                                                    : const Color(0xff374151),
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15))))
                            ]),
                        const SizedBox(height: 12),
                        _next()
                      ])),
                    ],
                    if (_step == 4)
                      _card(Column(children: [
                        Row(children: [
                          Expanded(
                              child: _counter(
                                  'anxiety',
                                  _anxiety,
                                  'Skala 0 - 10',
                                  0,
                                  10,
                                  (n) => setState(() => _anxiety = n),
                                  title: 'Kecemasan')),
                          const SizedBox(width: 12),
                          Expanded(
                              child: _counter(
                                  'irritability',
                                  _irritability,
                                  'Skala 0 - 10',
                                  0,
                                  10,
                                  (n) => setState(() => _irritability = n),
                                  title: 'Iritabilitas'))
                        ]),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xff0eb689),
                                disabledBackgroundColor:
                                    const Color(0xff7dcbba),
                                minimumSize: const Size.fromHeight(47),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16))),
                            icon: _saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.check_circle, size: 17),
                            label: const Text('Selesai Check-in',
                                style: TextStyle(
                                    fontFamily: 'Roboto',
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700)))
                      ])),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_error!, textAlign: TextAlign.center)),
                  ]
                ])));
  }

  Widget _pill({required Widget child}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .19),
          borderRadius: BorderRadius.circular(30)),
      child: child);
  Widget _card(Widget child) => Container(
      padding: EdgeInsets.all(_step >= 3 ? 15 : 19),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(27),
          boxShadow: const [
            BoxShadow(
                color: Color(0x15000000), blurRadius: 10, offset: Offset(0, 6))
          ]),
      child: child);
  Widget _next({bool outlined = false}) => SizedBox(
      width: double.infinity,
      child: FilledButton(
          onPressed: () => setState(() => _step++),
          style: FilledButton.styleFrom(
              backgroundColor:
                  outlined ? Colors.white.withValues(alpha: .13) : purple,
              minimumSize: const Size.fromHeight(47),
              side: outlined
                  ? const BorderSide(color: Colors.white54)
                  : BorderSide.none,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16))),
          child: const Text('Lanjut',
              style: TextStyle(
                  fontFamily: 'Roboto',
                  fontSize: 15,
                  fontWeight: FontWeight.w700))));
  Widget _counter(String id, int value, String label, int min, int max,
          ValueChanged<int> change, {String? title}) =>
      Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          decoration: BoxDecoration(
              color: const Color(0xfff8f5fa),
              borderRadius: BorderRadius.circular(17)),
          child: Column(children: [
            if (title != null) ...[
              Text(title,
                  style: const TextStyle(
                      color: purple,
                      fontSize: 12,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 10)
            ],
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              _counterButton(
                  '$id-minus',
                  Icons.remove_rounded,
                  value > min && !_saving && _savedMood == null
                      ? () => change(value - 1)
                      : null),
              Flexible(
                  child: Text('$value',
                      style: const TextStyle(
                          fontSize: 24,
                          color: Color(0xff111827),
                          fontWeight: FontWeight.w700))),
              _counterButton(
                  '$id-plus',
                  Icons.add_rounded,
                  value < max && !_saving && _savedMood == null
                      ? () => change(value + 1)
                      : null)
            ]),
            const SizedBox(height: 7),
            Text(label,
                style: const TextStyle(fontSize: 12, color: Color(0xff8e949e)))
          ]));
  Widget _counterButton(
          String id, IconData icon, VoidCallback? action) =>
      SizedBox(
          width: 34,
          height: 34,
          child: IconButton(
              key: ValueKey(id),
              padding: EdgeInsets.zero,
              onPressed: action,
              style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: purple,
                  side: const BorderSide(color: Color(0xffeee8f3))),
              icon: Icon(icon, size: 21)));
  Widget _medication(Medication m) {
    final enabled = !isTemporaryMedicationId(m.id) &&
        ref.read(malvaStoreProvider.notifier).pendingDosesFor(m.id) == 0;
    return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(17)),
        child: Row(children: [
          Container(
              width: 6,
              height: 39,
              decoration: BoxDecoration(
                  color: const Color(0xff2ac7b5),
                  borderRadius: BorderRadius.circular(6))),
          const SizedBox(width: 11),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('${m.name} ${m.dosage}',
                    style: const TextStyle(
                        color: Color(0xff111827),
                        fontSize: 13,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(
                    '${m.reminders.isEmpty ? 'Fleksibel' : m.reminders.map((r) => r.label).join(', ')} • ${m.form} • ${m.sourceLabel}',
                    style:
                        const TextStyle(color: Color(0xff6b7280), fontSize: 11))
              ])),
          const SizedBox(width: 6),
          Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                  color: const Color(0xfff3ebf8),
                  borderRadius: BorderRadius.circular(16)),
              child: Text('${m.currentStock} tersisa',
                  style: const TextStyle(
                      color: purple,
                      fontSize: 10,
                      fontWeight: FontWeight.w700))),
          const SizedBox(width: 7),
          for (final status in ['taken', 'skipped'])
            Padding(
                padding: const EdgeInsets.only(left: 5),
                child: SizedBox(
                    width: 31,
                    height: 31,
                    child: IconButton(
                        key: ValueKey('${m.id}-$status'),
                        tooltip:
                            status == 'taken' ? 'Sudah diminum' : 'Dilewati',
                        onPressed: enabled &&
                                (status != 'taken' ||
                                    ref
                                        .read(malvaStoreProvider.notifier)
                                        .canTakeMedication(m.id))
                            ? () => setState(() {
                                  if (_doses[m.id] == status) {
                                    _doses.remove(m.id);
                                  } else {
                                    _doses[m.id] = status;
                                  }
                                })
                            : null,
                        style: IconButton.styleFrom(
                            padding: EdgeInsets.zero,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(7)),
                            backgroundColor: status == 'taken'
                                ? const Color(0xffd1fae5)
                                : const Color(0xfffce4e8),
                            foregroundColor: status == 'taken'
                                ? const Color(0xff159d80)
                                : const Color(0xffd32b51),
                            side: _doses[m.id] == status
                                ? BorderSide(
                                    color: status == 'taken'
                                        ? const Color(0xff159d80)
                                        : const Color(0xffd32b51),
                                    width: 2)
                                : BorderSide.none),
                        icon: Icon(
                            status == 'taken'
                                ? Icons.check_rounded
                                : Icons.close_rounded,
                            size: 22))))
        ]));
  }

  Future<void> _save() async {
    if (_saving) return;
    final session = ref.read(currentSessionProvider);
    final owner = _owner(session);
    final generation = _generation;
    final token = session?.accessToken;
    if (owner == null || token == null || token.isEmpty) {
      setState(() => _error = 'Masuk ke akun untuk menyimpan check-in.');
      return;
    }
    bool current() =>
        mounted &&
        generation == _generation &&
        _owner(ref.read(currentSessionProvider)) == owner;
    final entry = MoodEntry(
        date: ServerClock.now(),
        mood: _mood!,
        sleepHours: _hours + _minutes / 60,
        energy: _energy,
        anxiety: _anxiety,
        irritability: _irritability,
        note: _dailyCheckInNote);
    final api = ref.read(apiClientProvider);
    final queue = ref.read(offlineSyncServiceProvider);
    final notifier = ref.read(malvaStoreProvider.notifier);
    final meds = List<Medication>.of(ref.read(malvaStoreProvider).medications);
    final doses = Map<String, String>.of(_doses);
    setState(() {
      _saving = true;
      _error = null;
    });
    if (_savedMood == null) {
      try {
        await api.createMoodCheckin(
            accessToken: token,
            mood: entry.mood.name,
            sleepHours: entry.sleepHours,
            energy: entry.energy,
            anxiety: entry.anxiety,
            irritability: entry.irritability,
            note: entry.note,
            medicationTaken: doses.containsValue('taken'),
            occurredAt: entry.date);
      } on Object {
        if (!current()) return;
        try {
          await queue.enqueueMood(entry);
          _pending = true;
        } on Object {
          if (current())
            setState(() {
              _saving = false;
              _error = 'Check-in belum tersimpan. Coba lagi.';
            });
          return;
        }
      }
      if (!current()) return;
      _savedMood = entry;
      notifier.addMood(entry);
    }
    for (final med in meds) {
      final status = doses[med.id];
      if (status == null ||
          isTemporaryMedicationId(med.id) ||
          _finishedDoses.contains(med.id) ||
          (!_startedDoses.contains(med.id) &&
              notifier.pendingDosesFor(med.id) > 0)) continue;
      if (!current()) return;
      if (!_startedDoses.contains(med.id)) {
        if (!notifier.takeMedication(med.id, status: status)) continue;
        _startedDoses.add(med.id);
        _doseTakenAt[med.id] =
            ref.read(malvaStoreProvider).medicationLogs.first.takenAt;
      }
      try {
        final accepted = await api.createMedicationLog(
            accessToken: ref.read(currentSessionProvider)!.accessToken!,
            medicationId: med.id,
            medicationName: med.name,
            status: status,
            takenAt: _doseTakenAt[med.id]);
        if (!current()) return;
        notifier.confirmMedicationLog(med.id, _doseTakenAt[med.id]!, accepted);
        unawaited(notifier.loadMedications(
            api, ref.read(currentSessionProvider)!.accessToken!));
      } on Object {
        if (!current()) return;
        try {
          await queue.enqueueMedicationLog(
              medicationId: med.id,
              medicationName: med.name,
              status: status,
              takenAt: _doseTakenAt[med.id]);
          _pending = true;
        } on Object {
          if (current())
            setState(() {
              _saving = false;
              _error =
                  'Mood tersimpan. Log obat belum tersimpan; tekan Selesai Check-in untuk mencoba lagi.';
            });
          return;
        }
      }
      if (!current()) return;
      _finishedDoses.add(med.id);
    }
    if (!current()) return;
    setState(() {
      _done = true;
      _saving = false;
    });
    if (_pending)
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:
              Text('Check-in disimpan di perangkat, menunggu sinkronisasi.')));
    widget.onSaved();
  }
}
