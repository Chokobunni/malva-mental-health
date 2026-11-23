import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../providers/providers.dart';
import '../../services/malva_api_client.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';
import '../../widgets/malva_components.dart';
import '../../widgets/professional_avatar.dart';
import 'consent_request_sheet.dart';
import 'booking_owner.dart';
import 'payment_screen.dart';

// ============================================================
// PACKAGE BOOKING — beli paket Continuous 4 sesi / 6 minggu.
// Alur: ringkasan aturan -> consent sharing -> buat paket
// (pending_payment) -> payment -> paket aktif -> jadwalkan sesi.
// ============================================================

class PackageBookingScreen extends ConsumerStatefulWidget {
  const PackageBookingScreen({
    super.key,
    required this.doctorUserId,
    required this.doctorName,
    required this.price,
    required this.doctorPhotoUrl,
    this.doctorSpecialization = '',
    this.doctorVerified = false,
    this.scheduleLines = const [],
    this.remainingPatientSlots,
    this.canRenewPackage = false,
    this.canResumePackage = false,
    this.durationLabel,
    this.session,
    this.apiClient,
  });

  final String doctorUserId;
  final String doctorName;
  final String doctorSpecialization;
  final bool doctorVerified;
  final int price;
  final List<String> scheduleLines;
  final int? remainingPatientSlots;
  final bool canRenewPackage;
  final bool canResumePackage;
  final String? durationLabel;

  /// URL foto profil profesional. Kosong = pakai avatar gradien + inisial.
  final String doctorPhotoUrl;
  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<PackageBookingScreen> createState() =>
      _PackageBookingScreenState();
}

class _PackageBookingScreenState extends ConsumerState<PackageBookingScreen> {
  late final BookingOwner _owner;
  bool _isSubmitting = false;
  String? _error;
  final _sessions = <int, (String, String)>{};

  bool get _hasCapacity =>
      widget.remainingPatientSlots != 0 ||
      widget.canRenewPackage ||
      widget.canResumePackage;

  @override
  void initState() {
    super.initState();
    _owner = BookingOwner(ref, widget.session);
  }

  @override
  Widget build(BuildContext context) {
    final needsFirst = !_sessions.containsKey(1) && !widget.canResumePackage;
    return Scaffold(
      backgroundColor: const Color(0xFFFAF9FC),
      appBar: AppBar(
          centerTitle: true,
          title: const Text('Booking Detail',
              style: TextStyle(fontFamily: 'Roboto')),
          backgroundColor: MalvaColors.seed,
          foregroundColor: Colors.white),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        SoftCard(
            radius: 24,
            padding: EdgeInsets.zero,
            color: Colors.white,
            child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: Column(children: [
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(children: [
                        ProfessionalAvatar(
                            displayName: widget.doctorName,
                            radius: 27,
                            borderRadius: BorderRadius.circular(16),
                            photoUrl: widget.doctorPhotoUrl),
                        const SizedBox(width: 12),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 5,
                                  children: [
                                    Text(widget.doctorName,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 17)),
                                    if (widget.doctorVerified)
                                      const Icon(Icons.verified_outlined,
                                          size: 19, color: MalvaColors.seed),
                                  ]),
                              if (widget.doctorSpecialization.isNotEmpty)
                                Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(widget.doctorSpecialization,
                                        style: const TextStyle(
                                            color: Color(0xFF8E99A5),
                                            fontSize: 12))),
                            ])),
                      ])),
                  Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                          color: Color(0xFFFCF7FF),
                          border: Border(
                              top: BorderSide(color: Color(0xFFF2EBF7)))),
                      child: Row(children: [
                        Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border:
                                    Border.all(color: const Color(0xFFF0E8F5))),
                            child: const Icon(Icons.calendar_month_outlined,
                                size: 25, color: MalvaColors.seed)),
                        const SizedBox(width: 10),
                        const Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text('Continuous Package',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16)),
                              SizedBox(height: 3),
                              Text('4 sesi video • Masa aktif 6 minggu',
                                  style: TextStyle(
                                      color: MalvaColors.seed, fontSize: 12)),
                            ])),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 85),
                            child: Text(
                                widget.durationLabel == null
                                    ? 'Durasi sesuai jadwal'
                                    : '${widget.durationLabel}/sesi',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: MalvaColors.seed,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11))),
                      ])),
                ]))),
        const SizedBox(height: 16),
        SoftCard(
            radius: 24,
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Row(children: [
                    Expanded(
                        child: Text('Jadwal 4 sesi',
                            style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w800))),
                    StatusPill(label: 'WIB', color: MalvaColors.seed)
                  ]),
                  const SizedBox(height: 10),
                  Text(
                      widget.canResumePackage
                          ? 'Lanjutkan pembayaran untuk jadwal yang sudah dipilih.'
                          : 'Sesi 1 wajib dipilih. Sesi 2–4 opsional sekarang dan dapat dijadwalkan kapan saja dari menu Terhubung selama paket aktif.',
                      style: const TextStyle(
                          color: Color(0xFF788490), height: 1.6, fontSize: 13)),
                  const SizedBox(height: 18),
                  for (var index = 1; index <= 4; index++) ...[
                    _sessionRow(index),
                    const SizedBox(height: 10),
                  ],
                  if (widget.scheduleLines.isNotEmpty)
                    Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: const Color(0xFFF8F9FC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFF0F1F4))),
                        child: Row(children: [
                          const Icon(Icons.schedule_outlined,
                              color: MalvaColors.seed, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                              child: Text(
                                  'Jam praktik: ${widget.scheduleLines.join(' • ')}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: Color(0xFF788490),
                                      height: 1.5)))
                        ])),
                ])),
        const SizedBox(height: 16),
        SoftCard(
            radius: 24,
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Row(children: [
                Icon(Icons.task_outlined, color: MalvaColors.seed),
                SizedBox(width: 9),
                Text('Aturan paket',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800))
              ]),
              const SizedBox(height: 8),
              _PackageRule(
                  Icons.videocam_outlined,
                  widget.durationLabel == null
                      ? '4 sesi video per paket.'
                      : '4 sesi video per paket, masing-masing berdurasi ${widget.durationLabel}.'),
              const _PackageRule(Icons.send_outlined,
                  'Selama paket aktif, kirim diary, goals, assessment, dan worksheet. Termasuk monitoring data.'),
              const _PackageRule(Icons.chat_bubble_outline_rounded,
                  'Profesional membahas kiriman saat sesi berlangsung, tanpa kewajiban membalas di luar sesi.'),
              const _PackageRule(Icons.info_outline_rounded,
                  'Tidak hadir: sesi hangus. Jika profesional membatalkan, kredit sesi kembali atau jadwal ulang.'),
              const _PackageRule(Icons.event_outlined,
                  'Setiap pembelian paket menambah 4 sesi dan 6 minggu masa aktif.'),
              const _PackageRule(Icons.event_busy_outlined,
                  'Sisa sesi hangus saat masa aktif berakhir. Tanpa perpanjangan otomatis.'),
            ])),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style: const TextStyle(
                      color: MalvaColors.danger, fontWeight: FontWeight.w700))),
      ]),
      bottomNavigationBar: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: Color(0xFFF1F2F4)))),
          child: SafeArea(
              top: false,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 5,
                        children: [
                          Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Total paket (4 Sesi)',
                                    style: TextStyle(
                                        color: Color(0xFF98A2AD),
                                        fontSize: 12)),
                                Text('Rp ${_formatRupiah(widget.price)}',
                                    style: const TextStyle(
                                        color: MalvaColors.seed,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 22)),
                              ]),
                          if (!_hasCapacity)
                            const StatusPill(
                                label: 'Slot pasien penuh',
                                color: MalvaColors.amber)
                          else if (needsFirst)
                            const StatusPill(
                                label: 'Pilih Sesi 1 dulu',
                                icon: Icons.schedule_outlined,
                                color: MalvaColors.amber)
                          else if (widget.remainingPatientSlots
                              case final remaining?)
                            StatusPill(
                                label: '$remaining slot tersisa',
                                color: MalvaColors.seed),
                        ]),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                        onPressed: _isSubmitting || !_hasCapacity || needsFirst
                            ? null
                            : _submit,
                        icon: const Icon(Icons.arrow_forward_rounded, size: 19),
                        label: Text(
                            style: const TextStyle(fontFamily: 'Roboto'),
                            _isSubmitting
                                ? 'Memproses...'
                                : widget.canResumePackage
                                    ? 'Lanjutkan pembayaran'
                                    : 'Lanjut ke pembayaran')),
                  ]))),
    );
  }

  Widget _sessionRow(int index) {
    final first = index == 1;
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
            color: const Color(0xFFFDFDFE),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color:
                    first ? const Color(0xFFE9D7F4) : const Color(0xFFEDF0F3),
                width: first ? 1.7 : 1)),
        child: Row(children: [
          Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: first ? MalvaColors.seed : const Color(0xFFE9EDF3),
                  borderRadius: BorderRadius.circular(12)),
              child: Text('$index',
                  style: TextStyle(
                      color: first ? Colors.white : const Color(0xFF52606C),
                      fontWeight: FontWeight.w800))),
          const SizedBox(width: 10),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Wrap(
                    spacing: 6,
                    runSpacing: 3,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('Sesi $index',
                          style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 15)),
                      StatusPill(
                          label: first ? 'Wajib' : 'Opsional',
                          color: first
                              ? MalvaColors.seed
                              : const Color(0xFF87939E)),
                    ]),
                const SizedBox(height: 4),
                if (_sessions[index] case (final date, final time))
                  Text('${_displayDate(date)} • $time',
                      style: const TextStyle(
                          color: Color(0xFF788490), fontSize: 12))
                else
                  const Text('Belum dijadwalkan',
                      style: TextStyle(color: Color(0xFF98A2AD), fontSize: 12)),
              ])),
          if (index > 1 && _sessions.containsKey(index))
            IconButton(
                tooltip: 'Hapus jadwal sesi $index',
                onPressed: _isSubmitting
                    ? null
                    : () => setState(() => _sessions.remove(index)),
                icon: const Icon(Icons.close_rounded, size: 17),
                constraints: const BoxConstraints(minWidth: 32, minHeight: 40),
                padding: EdgeInsets.zero),
          const SizedBox(width: 5),
          TextButton(
              key: ValueKey('package-session-$index'),
              style: TextButton.styleFrom(
                  backgroundColor: first ? MalvaColors.seed : Colors.white,
                  foregroundColor:
                      first ? Colors.white : const Color(0xFF384450),
                  disabledBackgroundColor:
                      first ? const Color(0xFFDBC9E7) : Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
                  minimumSize: const Size(0, 38),
                  side: BorderSide(
                      color:
                          first ? Colors.transparent : const Color(0xFFE5E8ED)),
                  textStyle: const TextStyle(
                      fontFamily: 'Roboto',
                      fontSize: 12,
                      fontWeight: FontWeight.w700),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              onPressed: _isSubmitting ||
                      !_hasCapacity ||
                      widget.canResumePackage ||
                      (index > 1 && !_sessions.containsKey(1))
                  ? null
                  : () => _pickSession(index),
              child:
                  Text(_sessions.containsKey(index) ? 'Ubah' : 'Pilih jadwal')),
        ]));
  }

  Future<void> _pickSession(int index) async {
    final MalvaApiClient api = widget.apiClient ?? ref.read(apiClientProvider);
    final session = _owner.session;
    final choice = await showDialog<(String, String)>(
      context: context,
      barrierColor: MalvaColors.plum.withValues(alpha: .65),
      builder: (_) => _PackageSessionDialog(
        api: api,
        accessToken: session?.accessToken,
        professionalId: widget.doctorUserId,
        index: index,
        initial: _sessions[index],
        first: index > 1 ? _sessions[1] : null,
        excluded: _sessions.entries
            .where((entry) => entry.key != index)
            .map((entry) => entry.value)
            .toSet(),
      ),
    );
    if (mounted && choice != null) {
      setState(() {
        _sessions[index] = choice;
        if (index == 1 &&
            _sessions.entries.any((entry) =>
                entry.key > 1 && _compareSlots(entry.value, choice) <= 0)) {
          _error =
              'Sesi opsional harus setelah sesi pertama. Ubah jadwal sesi opsional sebelum melanjutkan.';
        } else {
          _error = null;
        }
      });
    }
  }

  Future<void> _submit() async {
    // Fallback ke provider agar pembelian paket tetap jalan bila apiClient
    // tidak dioper eksplisit (deep-link), konsisten dengan layar lain.
    final MalvaApiClient apiClient =
        widget.apiClient ?? ref.read(apiClientProvider);
    final accessToken = _owner.session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      setState(() => _error = 'Mode offline aktif. '
          'Hubungkan ke server untuk membeli paket.');
      return;
    }
    final firstSession = _sessions[1];
    if (_isSubmitting ||
        !_hasCapacity ||
        (firstSession == null && !widget.canResumePackage)) return;
    if (firstSession != null &&
        _sessions.entries.any((entry) =>
            entry.key > 1 && _compareSlots(entry.value, firstSession) <= 0)) {
      setState(() => _error =
          'Sesi opsional harus setelah sesi pertama. Ubah jadwal sesi opsional sebelum melanjutkan.');
      return;
    }
    final additional = _sessions.entries
        .where((entry) => entry.key > 1)
        .map((entry) => '${entry.value.$1}T${entry.value.$2}')
        .toList()
      ..sort();
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    try {
      final granted = widget.canResumePackage ||
          await showConsentRequestSheet(
            context: context,
            professionalId: widget.doctorUserId,
            ownerSession: () => mounted ? _owner.session : null,
          );
      if (!granted || !mounted) return;
      final purchaseToken = _owner.session?.accessToken;
      if (purchaseToken == null || purchaseToken.isEmpty) return;
      final BackendCarePackage pkg;
      if (widget.canResumePackage) {
        final pending =
            (await apiClient.listCarePackages(accessToken: purchaseToken))
                .where((p) =>
                    p.professionalId == widget.doctorUserId &&
                    p.status == 'pending_payment' &&
                    p.bookingId != null)
                .firstOrNull;
        if (pending == null)
          throw const MalvaApiException(
              'Pesanan menunggu pembayaran sudah berubah. Buka kembali profil untuk memperbarui informasi.');
        pkg = pending;
      } else {
        pkg = await apiClient.createCarePackage(
            accessToken: purchaseToken, professionalId: widget.doctorUserId);
      }
      if (!mounted || _owner.session == null) return;
      BackendBooking? booking;
      if (pkg.bookingId == null && firstSession != null) {
        final bookingToken = _owner.session?.accessToken;
        if (bookingToken == null || bookingToken.isEmpty) return;
        booking = await apiClient.createPackageSessionBooking(
          accessToken: bookingToken,
          packageId: pkg.id,
          bookingDate: firstSession.$1,
          slotTime: firstSession.$2,
          additionalSessions: additional,
        );
        if (!mounted || _owner.session == null) return;
      }
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PaymentScreen(
            package: pkg,
            booking: booking,
            packageScheduleSummary: booking == null
                ? const []
                : [
                    for (final stamp in [
                      '${firstSession!.$1}T${firstSession.$2}',
                      ...additional
                    ])
                      '${_displayDate(stamp.split('T').first)} • ${stamp.split('T').last}',
                  ],
            doctorName: widget.doctorName,
            session: _owner.session,
            apiClient: widget.apiClient,
          ),
        ),
      );
    } on MalvaApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } on Object catch (e) {
      if (mounted) setState(() => _error = friendlyErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  static String _formatRupiah(int value) {
    final s = value.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final pos = s.length - i;
      buf.write(s[i]);
      if (pos > 1 && pos % 3 == 1) buf.write('.');
    }
    return buf.toString();
  }
}

int _compareSlots((String, String) a, (String, String) b) =>
    '${a.$1}T${a.$2}'.compareTo('${b.$1}T${b.$2}');

String _displayDate(String date, {bool short = false}) {
  final parsed = DateTime.tryParse(date);
  if (parsed == null) return date;
  const weekdays = [
    'Senin',
    'Selasa',
    'Rabu',
    'Kamis',
    'Jumat',
    'Sabtu',
    'Minggu'
  ];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des'
  ];
  final day = weekdays[parsed.weekday - 1];
  final label = '${parsed.day} ${months[parsed.month - 1]}';
  return short
      ? '${day.substring(0, 3)}\n$label'
      : '$day, $label ${parsed.year}';
}

class _PackageRule extends StatelessWidget {
  const _PackageRule(this.icon, this.text);

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                    color: Color(0xFFFBF5FF), shape: BoxShape.circle),
                child: Icon(icon, color: MalvaColors.seed, size: 19)),
            const SizedBox(width: 10),
            Expanded(
                child: Text(text,
                    style: const TextStyle(
                        color: Color(0xFF788490), height: 1.6, fontSize: 13))),
          ],
        ),
      );
}

class _PackageSessionDialog extends StatefulWidget {
  const _PackageSessionDialog({
    required this.api,
    required this.accessToken,
    required this.professionalId,
    required this.initial,
    required this.index,
    required this.excluded,
    this.first,
  });

  final int index;
  final (String, String)? first;
  final Set<(String, String)> excluded;
  final MalvaApiClient api;
  final String? accessToken;
  final String professionalId;
  final (String, String)? initial;

  @override
  State<_PackageSessionDialog> createState() => _PackageSessionDialogState();
}

class _PackageSessionDialogState extends State<_PackageSessionDialog> {
  late Future<List<BackendAvailabilityDay>> _availability;
  Future<List<BackendDoctorSlot>>? _slots;
  String? _date;
  String? _time;

  @override
  void initState() {
    super.initState();
    _availability = _loadDays();
  }

  Future<List<BackendAvailabilityDay>> _loadDays() async {
    final days = (await widget.api.getDoctorAvailability(
      accessToken: widget.accessToken,
      userId: widget.professionalId,
      serviceCategory: 'package',
    ))
        .where((day) =>
            day.bookable &&
            (widget.first == null || day.date.compareTo(widget.first!.$1) >= 0))
        .toList(growable: false);
    if (mounted && days.isNotEmpty) {
      final previous = widget.initial;
      final canRestore =
          previous != null && days.any((day) => day.date == previous.$1);
      _selectDate(canRestore ? previous.$1 : days.first.date,
          initialTime: canRestore ? previous.$2 : null);
    }
    return days;
  }

  void _selectDate(String date, {String? initialTime}) {
    setState(() {
      _date = date;
      _time = initialTime;
      _slots = widget.api.getDoctorAvailableSlots(
        accessToken: widget.accessToken,
        userId: widget.professionalId,
        date: date,
        serviceCategory: 'package',
      );
    });
  }

  Future<void> _openCalendar(List<BackendAvailabilityDay> days) async {
    final dates = {
      for (final day in days)
        if (DateTime.tryParse(day.date) case final date?) date: day.date
    };
    if (dates.isEmpty) return;
    final ordered = dates.keys.toList()..sort();
    final initial = DateTime.tryParse(_date ?? '');
    final selected = await showDatePicker(
      context: context,
      initialDate: dates.containsKey(initial) ? initial! : ordered.first,
      firstDate: ordered.first,
      lastDate: ordered.last,
      selectableDayPredicate: dates.containsKey,
    );
    if (mounted && selected != null) _selectDate(dates[selected]!);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        titlePadding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        title: Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Pilih jadwal sesi ${widget.index}',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
              StatusPill(
                  label: widget.index == 1 ? 'Wajib' : 'Opsional',
                  color: widget.index == 1 ? MalvaColors.seed : Colors.black54),
            ]),
        content: SingleChildScrollView(
          child: SizedBox(
            width: 420,
            child: FutureBuilder<List<BackendAvailabilityDay>>(
              future: _availability,
              builder: (context, days) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Sesi video • WIB'),
                  const SizedBox(height: 12),
                  Row(children: [
                    const Expanded(child: SectionLabel('Pilih tanggal')),
                    if (days.connectionState == ConnectionState.done &&
                        days.hasData &&
                        days.data!.isNotEmpty)
                      TextButton.icon(
                          onPressed: () => _openCalendar(days.data!),
                          icon: const Icon(Icons.calendar_today_outlined,
                              size: 16),
                          label: const Text('Kalender')),
                  ]),
                  if (days.connectionState != ConnectionState.done)
                    const Center(child: CircularProgressIndicator())
                  else if (days.hasError)
                    FriendlyErrorCard(
                        error: days.error!,
                        onRetry: () async =>
                            setState(() => _availability = _loadDays()))
                  else if (days.data!.isEmpty)
                    const Text('Belum ada jadwal tersedia.')
                  else ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final day in days.data!)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                showCheckmark: false,
                                label: Text(
                                    _displayDate(day.date, short: true)
                                        .replaceAll('\n', ' · '),
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                selected: day.date == _date,
                                onSelected: (_) => _selectDate(day.date),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    const SectionLabel('Pilih jam'),
                    if (_date != null) Text(_displayDate(_date!)),
                  ],
                  FutureBuilder<List<BackendDoctorSlot>>(
                    future: _slots,
                    builder: (context, slots) {
                      final available = slots.data
                              ?.where((slot) =>
                                  slot.available &&
                                  !widget.excluded
                                      .contains((_date!, slot.time)) &&
                                  (widget.first == null ||
                                      _compareSlots((_date!, slot.time),
                                              widget.first!) >
                                          0))
                              .toList() ??
                          const <BackendDoctorSlot>[];
                      final loaded =
                          slots.connectionState == ConnectionState.done;
                      final canSave =
                          loaded && available.any((slot) => slot.time == _time);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (slots.connectionState == ConnectionState.waiting)
                            const Center(child: CircularProgressIndicator())
                          else if (slots.hasError)
                            FriendlyErrorCard(
                                error: slots.error!,
                                onRetry: () async => _selectDate(_date!))
                          else if (loaded && available.isEmpty)
                            const Text('Tidak ada slot bebas pada tanggal ini.')
                          else if (loaded)
                            Wrap(
                              spacing: 8,
                              children: [
                                for (final slot in available)
                                  ChoiceChip(
                                    label: Text(slot.time),
                                    selected: slot.time == _time,
                                    onSelected: (_) =>
                                        setState(() => _time = slot.time),
                                  ),
                              ],
                            ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('Batal',
                                      style: TextStyle(
                                          fontWeight: FontWeight.w800))),
                              Expanded(
                                  child: FilledButton(
                                onPressed: canSave
                                    ? () =>
                                        Navigator.pop(context, (_date!, _time!))
                                    : null,
                                child: const Text('Simpan jadwal',
                                    textAlign: TextAlign.center),
                              )),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
