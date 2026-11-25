import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../services/server_clock.dart';
import '../theme.dart';
import '../time/wib.dart';
import '../widgets/care_reference_widgets.dart';
import '../widgets/friendly_error.dart';
import '../widgets/malva_components.dart';
import '../widgets/professional_avatar.dart';
import '../widgets/professional_availability_summary.dart';
import 'booking/booking_owner.dart';
import 'care_package_screen.dart';

class SchedulePackageSessionsScreen extends ConsumerStatefulWidget {
  const SchedulePackageSessionsScreen({
    super.key,
    required this.package,
    required this.api,
    required this.session,
  });
  final BackendCarePackage package;
  final MalvaApiClient api;
  final AuthSession session;

  @override
  ConsumerState<SchedulePackageSessionsScreen> createState() =>
      _SchedulePackageSessionsScreenState();
}

class _SchedulePackageSessionsScreenState
    extends ConsumerState<SchedulePackageSessionsScreen> {
  final _selected = <int, String>{};
  final _scheduled = <int>{};
  List<BackendProfessionalSchedule> _practiceHours = const [];
  String _specialty = '';
  bool _saving = false;
  bool _changed = false;
  late final BookingOwner _owner;
  String? _error;

  BackendCarePackage get _package => widget.package;
  int get _remaining => _package.remainingSessions - _scheduled.length;
  bool get _expired =>
      !_package.isActive ||
      _package.expiresDateTime?.isAfter(ServerClock.now()) != true;
  String? get _token => _owner.session?.accessToken;

  @override
  void initState() {
    super.initState();
    _owner = BookingOwner(ref, widget.session);
    _loadHours();
  }

  Future<void> _loadHours() async {
    try {
      final profile = await widget.api.getDoctorProfile(
        accessToken: _token,
        userId: _package.professionalId,
      );
      if (mounted && _token != null) {
        final schedules = professionalServiceSchedules(
            profile.schedules, 'package',
            usePrimarySchedule: profile.usePrimarySchedule);
        setState(() {
          _practiceHours = schedules.where((s) => s.isActive).toList()
            ..sort((a, b) => a.dayOfWeek.compareTo(b.dayOfWeek));
          _specialty = profile.credential.specialization;
        });
      }
    } on Object {
      // Availability inside the picker is loaded from the slots API.
    }
  }

  Future<void> _pick(int number) async {
    final token = _token;
    if (_expired || token == null) return;
    final chosen = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      builder: (_) => CareSessionSchedulerSheet(
        apiClient: widget.api,
        accessToken: token,
        professionalId: _package.professionalId,
        sessionNumber: number,
        expiresAt: _package.expiresDateTime,
        excludedSlots: _selected.entries
            .where((entry) => entry.key != number)
            .map((entry) => entry.value)
            .toSet(),
      ),
    );
    if (!mounted || chosen == null || _token == null) return;
    setState(() {
      _selected[number] = chosen.split('|').first;
      _error = null;
    });
  }

  Future<void> _save() async {
    if (_saving || _selected.isEmpty || _expired || _token == null) return;
    final requested = _selected.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    setState(() {
      _error = null;
      _saving = true;
    });
    try {
      for (final entry in requested) {
        if (!mounted || _token == null) return;
        try {
          await widget.api.scheduleSession(
            accessToken: _token!,
            packageId: _package.id,
            scheduledAt: entry.value,
            sessionType: 'video',
          );
        } on Object {
          // If the response was lost after the write, reconcile the same slot
          // before offering a retry.
          final token = _token;
          if (token == null) return;
          final sessions =
              await widget.api.listCareSessions(accessToken: token);
          final start = parseWibStored(entry.value);
          if (!sessions.any((session) =>
              session.packageId == _package.id &&
              session.status == 'scheduled' &&
              parseWibStored(session.scheduledAt) == start)) {
            rethrow;
          }
        }
        if (!mounted || _token == null) return;
        setState(() {
          _selected.remove(entry.key);
          _scheduled.add(entry.key);
          _changed = true;
        });
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on Object catch (failure) {
      if (!mounted || _token == null) return;
      final prefix = _changed ? '${_scheduled.length} sesi tersimpan. ' : '';
      setState(() => _error = '$prefix${friendlyErrorMessage(failure)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _longDate(DateTime value) {
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
      'Desember',
    ];
    return '${d.day} ${months[d.month - 1]} ${d.year}';
  }

  String _clock(DateTime at) =>
      '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

  String _slotText(String value) {
    final start = parseWibStored(value)!;
    final startClock = _clock(start);
    final duration = _practiceHours
        .where((schedule) =>
            schedule.dayOfWeek == start.weekday % 7 &&
            schedule.startTime.compareTo(startClock) <= 0 &&
            schedule.endTime.compareTo(startClock) > 0)
        .firstOrNull
        ?.slotDurationMinutes;
    if (duration == null) {
      return '${wibWeekdayName(start)}, ${_longDate(start)} · $startClock';
    }
    final end = start.add(Duration(minutes: duration.clamp(60, 180)));
    return '${wibWeekdayName(start)}, ${_longDate(start)} · ${_clock(start)}–${_clock(end)}';
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(currentSessionProvider);
    final available = _token != null && !_expired;
    final total = _package.totalSessions;
    final name = _package.professionalName.trim();
    final expiry = _package.expiresDateTime;
    const title = TextStyle(
      fontSize: 20,
      color: Color(0xff182330),
      fontWeight: FontWeight.w900,
    );
    return PopScope(
      canPop: !_saving,
      child: Scaffold(
        backgroundColor: carePageColor,
        appBar: AppBar(
          title: const Text('Jadwalkan Sesi'),
          centerTitle: true,
          backgroundColor: MalvaColors.seed,
          foregroundColor: Colors.white,
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            SoftCard(
              radius: 26,
              color: Colors.white,
              outline: careCardBorder,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    ProfessionalAvatar(
                      displayName: name,
                      photoUrl: _package.photoIntroUrl,
                      radius: 25,
                      borderRadius: BorderRadius.circular(18),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(name.isEmpty ? 'Profesional' : name, style: title),
                        if (_specialty.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(_specialty,
                              style: const TextStyle(
                                  color: Color(0xff7d8891), fontSize: 13)),
                        ],
                      ],
                    )),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                          color: available
                              ? const Color(0xffe9faf3)
                              : const Color(0xfff7effa),
                          borderRadius: BorderRadius.circular(20)),
                      child: Text(available ? 'Paket aktif' : 'Paket berakhir',
                          style: TextStyle(
                              color: available
                                  ? const Color(0xff257d65)
                                  : MalvaColors.plum,
                              fontWeight: FontWeight.w700,
                              fontSize: 12)),
                    ),
                  ]),
                  const SizedBox(height: 20),
                  SoftCard(
                      color: const Color(0xfffaf5fd),
                      radius: 18,
                      outline: const BorderSide(color: Color(0xfff0e7f5)),
                      child: Column(children: [
                        Row(children: [
                          const Icon(Icons.event_available_outlined,
                              size: 36, color: MalvaColors.seed),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Kuota Konsultasi',
                                    style: TextStyle(color: MalvaColors.seed)),
                                Text('$_remaining dari $total sesi tersisa',
                                    style: title.copyWith(
                                        color: MalvaColors.plum, fontSize: 16)),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                              '${total > 0 ? (_remaining / total * 100).round() : 0}%',
                              style: title.copyWith(
                                  color: MalvaColors.seed, fontSize: 17)),
                        ]),
                        const SizedBox(height: 14),
                        LinearProgressIndicator(
                          value: total > 0
                              ? (_remaining / total).clamp(0.0, 1.0)
                              : 0,
                          borderRadius: BorderRadius.circular(8),
                          minHeight: 8,
                          backgroundColor: const Color(0xffe7d2ef),
                          color: MalvaColors.seed,
                        ),
                      ])),
                  const Divider(height: 24),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    runSpacing: 5,
                    spacing: 12,
                    children: [
                      Text(
                          'DETAIL PAKET\n${total ~/ 4} paket · $total sesi\n${_package.validityDays ~/ 7} minggu masa aktif'),
                      if (expiry != null)
                        Text(
                            'BERLAKU HINGGA\n${_longDate(expiry)}\n${_expired ? 'Paket berakhir' : '${expiry.difference(ServerClock.now()).inDays.clamp(0, 99999)} hari lagi'}'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const SoftCard(
                    color: Color(0xfff7f9fb),
                    padding: EdgeInsets.all(14),
                    child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.info, color: MalvaColors.seed, size: 18),
                          SizedBox(width: 10),
                          Expanded(
                              child: Text(
                                  'Setiap pembelian paket menambah 4 sesi dan 6 minggu masa aktif. Sisa sesi mengikuti tanggal berakhir terbaru.',
                                  style: TextStyle(
                                      color: Color(0xff66717e), height: 1.5))),
                        ]),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Row(children: [
              Expanded(child: Text('Pilih Jadwal', style: title)),
              StatusPill(label: 'WIB', color: MalvaColors.seed),
            ]),
            Text('Pilih hingga $_remaining sesi sesuai jam praktik dokter',
                style: const TextStyle(color: Color(0xff7d8891))),
            const SizedBox(height: 12),
            for (var number = _package.usedSessions + 1;
                number <= total;
                number++) ...[
              SoftCard(
                  padding:
                      const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                  color: Colors.white,
                  radius: 20,
                  child: ListTile(
                    leading: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          color: const Color(0xfff8f0fc),
                          borderRadius: BorderRadius.circular(16)),
                      child: Icon(
                          _scheduled.contains(number) ||
                                  _selected.containsKey(number)
                              ? Icons.check_rounded
                              : Icons.event_outlined,
                          color: MalvaColors.seed,
                          size: 22),
                    ),
                    title: Text('Sesi $number',
                        style: const TextStyle(fontWeight: FontWeight.w800)),
                    subtitle: Text(_scheduled.contains(number)
                        ? 'Terjadwal'
                        : _selected[number] == null
                            ? 'Belum dijadwalkan'
                            : _slotText(_selected[number]!)),
                    trailing: TextButton(
                      style: TextButton.styleFrom(
                          backgroundColor: const Color(0xfff8f0fc),
                          foregroundColor: MalvaColors.seed),
                      onPressed:
                          !available || _saving || _scheduled.contains(number)
                              ? null
                              : () => _pick(number),
                      child: Text(_selected.containsKey(number)
                          ? 'Ubah'
                          : 'Pilih jadwal'),
                    ),
                  )),
              const SizedBox(height: 12),
            ],
            if (_practiceHours.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Row(children: [
                Expanded(child: Text('Jam Praktik', style: title)),
                Text('Jadwal rutin mingguan',
                    style: TextStyle(color: Color(0xffa0a8b1), fontSize: 11))
              ]),
              const SizedBox(height: 12),
              SoftCard(
                  color: Colors.white,
                  radius: 20,
                  child: Column(children: [
                    for (final schedule in _practiceHours)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(children: [
                            const Icon(Icons.circle,
                                size: 8, color: MalvaColors.seed),
                            const SizedBox(width: 10),
                            Expanded(
                                child: Text(_dayNames[schedule.dayOfWeek % 7],
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700))),
                            Container(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 6, horizontal: 12),
                                decoration: BoxDecoration(
                                    color: const Color(0xfff1f4f8),
                                    borderRadius: BorderRadius.circular(10)),
                                child: Text(
                                    '${schedule.startTime} – ${schedule.endTime}')),
                          ])),
                  ])),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(_error!, style: const TextStyle(color: MalvaColors.danger)),
            ],
          ],
        ),
        bottomNavigationBar: Material(
            color: Colors.white,
            child: SafeArea(
              minimum: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(children: [
                    const Expanded(
                        child: Text('Total jadwal dipilih',
                            style: TextStyle(color: Color(0xff7d8891)))),
                    Text('${_selected.length} sesi dipilih',
                        style: const TextStyle(fontWeight: FontWeight.w800))
                  ]),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _saving || !available || _selected.isEmpty
                        ? null
                        : _save,
                    icon: const Icon(Icons.event_available_outlined),
                    label: Text(_saving
                        ? 'Menjadwalkan…'
                        : 'Jadwalkan ${_selected.length} sesi'),
                  ),
                ],
              ),
            )),
      ),
    );
  }

  static const _dayNames = [
    'Minggu',
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
  ];
}
