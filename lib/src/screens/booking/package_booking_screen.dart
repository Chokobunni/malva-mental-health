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
    return Scaffold(
      backgroundColor: const Color(0xFFFDFBFD),
      appBar: AppBar(
        centerTitle: true,
        title: const Text('Booking Detail'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          SoftCard(
            color: Colors.white,
            child: Row(
              children: [
                ProfessionalAvatar(
                    displayName: widget.doctorName,
                    radius: 27,
                    photoUrl: widget.doctorPhotoUrl),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(widget.doctorName,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 18))),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SoftCard(
            color: Colors.white,
            child: Row(
              children: [
                const Icon(Icons.calendar_month_outlined,
                    color: MalvaColors.seed, size: 38),
                const SizedBox(width: 12),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Continuous Package',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w900)),
                    const Text('4 sesi video • 6 minggu'),
                    if (widget.remainingPatientSlots case final remaining?)
                      StatusPill(
                          label: '$remaining slot tersisa',
                          color: MalvaColors.seed),
                  ],
                )),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(child: SectionLabel('Jadwal 4 sesi')),
              StatusPill(label: 'WIB', color: MalvaColors.seed),
            ],
          ),
          Text(widget.canResumePackage
              ? 'Lanjutkan pembayaran untuk jadwal yang sudah dipilih.'
              : 'Sesi 1 wajib dipilih. Sesi 2–4 opsional dan juga dapat dijadwalkan dari Terhubung selama paket aktif.'),
          const SizedBox(height: 10),
          SoftCard(
            color: Colors.white,
            child: Column(
              children: [
                for (var index = 1; index <= 4; index++) ...[
                  if (index > 1) const Divider(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text('Sesi $index',
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 16)),
                                StatusPill(
                                    label: index == 1 ? 'Wajib' : 'Opsional',
                                    color: index == 1
                                        ? MalvaColors.seed
                                        : Colors.black54),
                              ],
                            ),
                            if (_sessions[index] case (final date, final time))
                              Text('${_displayDate(date)} • $time')
                            else
                              const Text('Belum dijadwalkan'),
                          ],
                        ),
                      ),
                      if (index > 1 && _sessions.containsKey(index))
                        IconButton(
                          tooltip: 'Hapus jadwal sesi $index',
                          onPressed: _isSubmitting
                              ? null
                              : () => setState(() => _sessions.remove(index)),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      TextButton(
                        key: ValueKey('package-session-$index'),
                        onPressed: _isSubmitting ||
                                !_hasCapacity ||
                                widget.canResumePackage ||
                                (index > 1 && !_sessions.containsKey(1))
                            ? null
                            : () => _pickSession(index),
                        child: Text(_sessions.containsKey(index)
                            ? 'Ubah'
                            : 'Pilih jadwal'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (widget.scheduleLines.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(widget.scheduleLines.join(' • ')),
          ],
          const SizedBox(height: 12),
          SoftCard(
            color: Colors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionLabel('Aturan paket'),
                _PackageRule(
                    Icons.event_available_outlined,
                    widget.durationLabel == null
                        ? '4 sesi video per paket.'
                        : '4 sesi video per paket, masing-masing ${widget.durationLabel}.'),
                const _PackageRule(Icons.send_outlined,
                    'Selama paket aktif, kirim diary, goals, assessment, dan worksheet. Termasuk monitoring data.'),
                const _PackageRule(Icons.chat_bubble_outline_rounded,
                    'Profesional membahas kiriman saat sesi, tanpa kewajiban membalas di luar sesi.'),
                const _PackageRule(Icons.info_outline_rounded,
                    'Tidak hadir: sesi hangus. Jika profesional membatalkan, kredit sesi kembali atau jadwal ulang.'),
                const _PackageRule(Icons.event_outlined,
                    'Setiap pembelian paket menambah 4 sesi dan 6 minggu masa aktif.'),
                const _PackageRule(Icons.event_busy_outlined,
                    'Sisa sesi hangus saat masa aktif berakhir. Tanpa perpanjangan otomatis.'),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SoftCard(
            color: Colors.white,
            child: Row(
              children: [
                const Expanded(
                    child: Text('Total paket',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 18))),
                Text('Rp ${_formatRupiah(widget.price)}',
                    style: const TextStyle(
                        color: MalvaColors.seed,
                        fontWeight: FontWeight.w900,
                        fontSize: 20)),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!,
                style: const TextStyle(
                    color: MalvaColors.danger, fontWeight: FontWeight.w700)),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _isSubmitting ||
                    !_hasCapacity ||
                    (!_sessions.containsKey(1) && !widget.canResumePackage)
                ? null
                : _submit,
            icon: const Icon(Icons.arrow_forward_rounded),
            label: Text(_isSubmitting
                ? 'Memproses...'
                : widget.canResumePackage
                    ? 'Lanjutkan pembayaran'
                    : 'Lanjut ke pembayaran'),
          ),
        ],
      ),
    );
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
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: MalvaColors.seed, size: 21),
            const SizedBox(width: 10),
            Expanded(child: Text(text)),
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

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Text('Pilih jadwal sesi ${widget.index}'),
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
                  const SectionLabel('Pilih tanggal'),
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
                                label: Text(_displayDate(day.date, short: true),
                                    textAlign: TextAlign.center),
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
                                  child: const Text('Batal')),
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
