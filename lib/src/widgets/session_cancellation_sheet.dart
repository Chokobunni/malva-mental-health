import 'package:flutter/material.dart';
import '../services/malva_api_client.dart';
import '../services/server_clock.dart';
import '../time/wib.dart';

/// Null means dismissed; an empty reason is a confirmed optional reason.
Future<String?> showSessionCancellationSheet(
  BuildContext context, {
  required BackendCareSession session,
  bool professional = false,
  DateTime? now,
}) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      useSafeArea: true,
      constraints: const BoxConstraints(maxWidth: 580),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) => _CancellationSheet(
          session: session, professional: professional, now: now),
    );

class _CancellationSheet extends StatefulWidget {
  const _CancellationSheet(
      {required this.session, required this.professional, this.now});
  final BackendCareSession session;
  final bool professional;
  final DateTime? now;
  @override
  State<_CancellationSheet> createState() => _CancellationSheetState();
}

class _CancellationSheetState extends State<_CancellationSheet> {
  final _reason = TextEditingController();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final package = session.packageId?.trim().isNotEmpty == true;
    final start = session.scheduledDateTime;
    final refundable = widget.professional ||
        (start != null &&
            start.difference(widget.now ?? ServerClock.now()) >=
                const Duration(hours: 1));
    final person =
        widget.professional ? session.patientName : session.professionalName;
    final title = refundable
        ? (package
            ? (widget.professional
                ? 'Kredit Sesi Otomatis Dikembalikan'
                : 'Kebijakan Pembatalan 1 Jam • Kredit Direfund')
            : (widget.professional
                ? 'Dana Otomatis Direfund ke Pasien'
                : 'Dana Otomatis Direfund'))
        : (package
            ? 'Perhatian: Kredit Tidak Dapat Direfund'
            : 'Perhatian: Dana Tidak Dapat Direfund');
    final message = refundable
        ? (package
            ? (widget.professional
                ? 'Karena pembatalan dilakukan oleh profesional, 1 kredit sesi akan otomatis kembali ke akun pasien dan dapat dijadwalkan ulang.'
                : 'Pembatalan dilakukan minimal 1 jam sebelum sesi. Sebanyak 1 kredit sesi akan otomatis dikembalikan ke akun Anda. Kurang dari 1 jam, sesi hangus.')
            : (widget.professional
                ? 'Karena pembatalan dilakukan oleh profesional, proses pengembalian seluruh biaya sesi ke metode pembayaran pasien akan dimulai otomatis jika didukung. Metode lain diproses manual oleh admin.'
                : 'Pembatalan dilakukan minimal 1 jam sebelum sesi. Proses pengembalian seluruh biaya sesi ke metode pembayaran Anda akan dimulai otomatis jika didukung. Metode lain diproses manual oleh admin.'))
        : (package
            ? 'Pembatalan kurang dari 1 jam sebelum sesi. Sesi dianggap hangus dan 1 kredit sesi tidak dikembalikan.'
            : 'Pembatalan kurang dari 1 jam sebelum sesi. Sesi dianggap hangus dan biaya sesi tidak dapat dikembalikan.');
    final tone = refundable ? const Color(0xff087f65) : const Color(0xffbd3037);
    return SingleChildScrollView(
        child: Padding(
      padding: EdgeInsets.fromLTRB(
          24, 0, 24, 24 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  padding: const EdgeInsets.all(13),
                  decoration: BoxDecoration(
                      color: const Color(0xfffff1f2),
                      borderRadius: BorderRadius.circular(17)),
                  child: const Icon(Icons.event_busy_outlined,
                      color: Color(0xffc62828), size: 28)),
              const SizedBox(width: 14),
              const Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text('Batalkan Sesi Ini?',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800)),
                    SizedBox(height: 7),
                    Text(
                        'Tindakan ini tidak dapat dibatalkan setelah dikonfirmasi.',
                        style: TextStyle(color: Color(0xff687483), height: 1.5))
                  ])),
              IconButton(
                  tooltip: 'Tutup',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Color(0xff98a3b1))),
            ]),
            const SizedBox(height: 22),
            Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                    color: const Color(0xfff8f9fb),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xffe5e7eb))),
                child: Row(children: [
                  CircleAvatar(
                      backgroundColor: Colors.white,
                      child: Text(person.trim().isEmpty
                          ? '?'
                          : person.trim().characters.first.toUpperCase())),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(
                            person.trim().isEmpty
                                ? (widget.professional
                                    ? 'Pasien'
                                    : 'Profesional')
                                : person,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 16)),
                        const SizedBox(height: 5),
                        Text(
                            package
                                ? 'Sesi Paket'
                                : 'Sekali Sesi (${session.isVideo ? 'Video' : 'Chat'})',
                            style: TextStyle(
                                color: package
                                    ? const Color(0xff7e46b3)
                                    : const Color(0xff336dc0),
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 5),
                        Text(
                            start == null
                                ? 'Belum dijadwalkan'
                                : '${formatWibDateTime(start)} WIB',
                            style: const TextStyle(color: Color(0xff687483)))
                      ])),
                  if (package)
                    const Padding(
                        padding: EdgeInsets.only(left: 8),
                        child: Text('1 Sesi')),
                ])),
            const SizedBox(height: 18),
            Container(
                padding: const EdgeInsets.all(17),
                decoration: BoxDecoration(
                    color: refundable
                        ? const Color(0xffeffcf6)
                        : const Color(0xfffff3f3),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: refundable
                            ? const Color(0xffbcebd9)
                            : const Color(0xfff0d4d6))),
                child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                          refundable
                              ? Icons.history_rounded
                              : Icons.error_outline,
                          color: tone),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(title,
                                style: TextStyle(
                                    color: refundable
                                        ? const Color(0xff123c31)
                                        : const Color(0xff481c20),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 8),
                            Text(message,
                                style: TextStyle(color: tone, height: 1.6))
                          ]))
                    ])),
            const SizedBox(height: 22),
            Row(children: [
              Image.asset('assets/care/cancellation_reason.png',
                  width: 22, height: 22),
              const SizedBox(width: 8),
              const Flexible(
                  child: Text('Alasan Pembatalan',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16))),
              const SizedBox(width: 8),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                      color: const Color(0xfff1f4f9),
                      borderRadius: BorderRadius.circular(8)),
                  child: const Text('Opsional',
                      style: TextStyle(color: Color(0xff687483))))
            ]),
            const SizedBox(height: 10),
            TextField(
                controller: _reason,
                maxLength: 200,
                minLines: 3,
                maxLines: 4,
                decoration: InputDecoration(
                    hintText:
                        'Tuliskan catatan singkat untuk ${widget.professional ? 'pasien' : 'profesional'}...',
                    hintStyle: const TextStyle(color: Color(0xff98a3b1)),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: const BorderSide(color: Color(0xffdfe3e8))),
                    filled: true,
                    fillColor: Colors.white)),
            const SizedBox(height: 22),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 50),
                          foregroundColor: const Color(0xff34404d),
                          side: const BorderSide(color: Color(0xffdfe3e8)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16))),
                      child: const Text('Kembali'))),
              const SizedBox(width: 12),
              Expanded(
                  child: FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, _reason.text.trim()),
                      style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xffdf2026),
                          minimumSize: const Size(0, 50),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16))),
                      child: const Text('Ya, Batalkan')))
            ]),
          ]),
    ));
  }
}
