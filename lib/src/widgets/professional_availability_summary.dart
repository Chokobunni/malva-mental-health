import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/malva_api_client.dart';
import '../theme.dart';
import 'malva_components.dart';

const professionalServiceNames = {
  'quick_chat': 'Quick Session (Chat)',
  'quick_video': 'Quick Session (Video)',
  'package': 'Continuous Package',
  'shared': 'Jadwal praktik utama',
};

const professionalServiceIcons = {
  'quick_chat': Icons.chat_bubble_outline,
  'quick_video': Icons.videocam_outlined,
  'package': Icons.event_repeat_outlined,
  'shared': Icons.calendar_month_outlined,
};

Widget professionalServiceArtwork(String category, {double size = 44}) =>
    Image.asset(
        'assets/reference/operations_${switch (category) {
          'shared' => 'primary',
          'quick_chat' => 'chat',
          'quick_video' => 'video',
          'package' => 'package',
          _ => 'availability',
        }}.png',
        width: size,
        height: size);

const _serviceCategories = ['quick_chat', 'quick_video', 'package'];

List<BackendProfessionalSchedule> professionalServiceSchedules(
  Iterable<BackendProfessionalSchedule> schedules,
  String category, {
  Map<String, bool> usePrimarySchedule = const {},
}) {
  final configured =
      schedules.where((slot) => slot.serviceCategory == category).toList();
  if (!(usePrimarySchedule[category] ?? configured.isEmpty)) return configured;
  return schedules.where((slot) => slot.serviceCategory == 'shared').toList();
}

const _days = ['Minggu', 'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu'];

class ProfessionalAvailabilitySummary extends StatelessWidget {
  const ProfessionalAvailabilitySummary(
      {super.key,
      required this.schedules,
      this.usePrimarySchedule = const {},
      required this.pricing,
      this.onConfigure});

  final List<BackendProfessionalSchedule> schedules;
  final Map<String, bool> usePrimarySchedule;
  final BackendProfessionalPricing pricing;
  final VoidCallback? onConfigure;

  @override
  Widget build(BuildContext context) {
    final prices = [
      pricing.quickChatPrice,
      pricing.quickVideoPrice,
      pricing.packagePrice
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        const Expanded(
            child: Text('Jadwal & tarif',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800))),
        if (onConfigure != null)
          TextButton.icon(
              onPressed: onConfigure,
              style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFFFAF5FD),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              icon: const Icon(Icons.edit_calendar_outlined, size: 18),
              label: const Text('Atur')),
      ]),
      const SizedBox(height: 3),
      const Row(children: [
        Icon(Icons.circle, size: 6, color: Color(0xFF36C998)),
        SizedBox(width: 5),
        Expanded(
            child: Text('Zona Waktu: WIB  •  Durasi fleksibel',
                style: TextStyle(fontSize: 12, color: Color(0xFF98A2AD)))),
      ]),
      const SizedBox(height: 16),
      Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: const Color(0xFFFFFCF0),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFF6EDC5))),
          child: Row(children: [
            professionalServiceArtwork('shared'),
            const SizedBox(width: 12),
            const Expanded(
                child: Text('Jadwal praktik utama',
                    style: TextStyle(fontWeight: FontWeight.w700))),
            Text(
                '${schedules.where((s) => s.serviceCategory == 'shared' && s.isActive).length} aktif',
                style: const TextStyle(
                    color: Color(0xFF986019), fontWeight: FontWeight.w700))
          ])),
      const SizedBox(height: 16),
      for (var i = 0; i < prices.length; i++) ...[
        _serviceSummary(context, i, prices[i]),
        const SizedBox(height: 12),
      ],
    ]);
  }

  Widget _serviceSummary(BuildContext context, int index, int price) {
    final slots = professionalServiceSchedules(
        schedules, _serviceCategories[index],
        usePrimarySchedule: usePrimarySchedule)
      ..sort((a, b) {
        final day = ((a.dayOfWeek + 6) % 7).compareTo((b.dayOfWeek + 6) % 7);
        return day == 0 ? a.startTime.compareTo(b.startTime) : day;
      });
    final capacity = pricing.patientCapacity ?? 2;
    final durations = slots
        .map((s) => s.slotDurationMinutes < 60 ? 60 : s.slotDurationMinutes)
        .toSet()
        .toList()
      ..sort();
    return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
                color: index == 2
                    ? const Color(0xFFF0E5F5)
                    : const Color(0xFFF0F2F5))),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _ServicePriceRow(
              index: index,
              subtitle: durations.isEmpty
                  ? 'Durasi belum diatur'
                  : '${durations.join(' / ')} mnt/sesi',
              trailing: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                  decoration: BoxDecoration(
                      color: const Color(0xFFFAF5FD),
                      borderRadius: BorderRadius.circular(15)),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                            price <= 0
                                ? 'Belum diatur'
                                : 'Rp${_groupDigits(price.toString())}',
                            style: const TextStyle(
                                color: Color(0xFF49176F),
                                fontWeight: FontWeight.w800,
                                fontSize: 16)),
                        Text(index == 2 ? '4 sesi · 6 minggu' : 'per sesi',
                            style: const TextStyle(
                                color: MalvaColors.seed, fontSize: 12)),
                      ]))),
          if (index != 2) ...[
            const SizedBox(height: 6),
            Align(
                alignment: Alignment.centerLeft,
                child: StatusPill(
                    label: (usePrimarySchedule[_serviceCategories[index]] ??
                            !schedules.any((s) =>
                                s.serviceCategory == _serviceCategories[index]))
                        ? 'Jadwal utama'
                        : 'Jadwal khusus',
                    color: index == 0
                        ? const Color(0xFF1386AD)
                        : const Color(0xFF5A49CD))),
          ],
          const Divider(height: 25, color: Color(0xFFEFF0F3)),
          if (slots.isEmpty)
            const Text('Belum ada jadwal aktif.',
                style: TextStyle(color: Color(0xFF98A2AD)))
          else
            for (final slot in slots)
              Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding:
                      const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                  decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14)),
                  child: Row(children: [
                    Expanded(
                        flex: 2,
                        child: Text(_days[slot.dayOfWeek],
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: slot.isActive
                                    ? const Color(0xFF384450)
                                    : const Color(0xFF98A2AD)))),
                    Expanded(
                        flex: 3,
                        child: Text('${slot.startTime}–${slot.endTime}',
                            style: TextStyle(
                                fontSize: 12,
                                color: slot.isActive
                                    ? const Color(0xFF52606C)
                                    : const Color(0xFF98A2AD),
                                decoration: slot.isActive
                                    ? null
                                    : TextDecoration.lineThrough))),
                    StatusPill(
                        label: slot.isActive ? 'Aktif' : 'Nonaktif',
                        color: slot.isActive
                            ? const Color(0xFF268C75)
                            : const Color(0xFF87939E)),
                  ])),
          if (index == 2) ...[
            const SizedBox(height: 14),
            Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: const Color(0xFFF0FAF7),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFBCEEE2))),
                child: Row(children: [
                  const Icon(Icons.people_outline, color: Color(0xFF23826D)),
                  const SizedBox(width: 10),
                  const Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('Slot pasien paket',
                            style: TextStyle(fontWeight: FontWeight.w800)),
                        Text('Khusus layanan Continuous Package',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF7B8791)))
                      ])),
                  Flexible(
                      child: Text(
                          capacity == 0
                              ? 'Ditutup untuk pasien baru'
                              : 'Maks. $capacity pasien aktif',
                          style: const TextStyle(
                              color: Color(0xFF23826D),
                              fontWeight: FontWeight.w800)))
                ])),
          ],
        ]));
  }
}

class ProfessionalPriceCard extends StatelessWidget {
  const ProfessionalPriceCard({
    super.key,
    required this.chat,
    required this.video,
    required this.package,
    required this.onSave,
    required this.isSaving,
    this.showSaveButton = true,
  });

  final TextEditingController chat;
  final TextEditingController video;
  final TextEditingController package;
  final VoidCallback onSave;
  final bool isSaving;
  final bool showSaveButton;

  @override
  Widget build(BuildContext context) {
    final controllers = [chat, video, package];
    return SoftCard(
      radius: 24,
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < controllers.length; i++) ...[
            if (i > 0) const Divider(height: 16),
            _ServicePriceRow(
              index: i,
              subtitle: i == 2 ? '4 sesi · berlaku 6 minggu' : '1 sesi',
              trailing: Semantics(
                label:
                    'Harga ${professionalServiceNames[_serviceCategories[i]]}',
                child: TextField(
                  controller: controllers[i],
                  enabled: !isSaving,
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                  ],
                  decoration: InputDecoration(
                    prefixText: 'Rp',
                    filled: true,
                    fillColor: const Color(0xFFF8F9FC),
                    hintText: '0',
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(18),
                      borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant),
                    ),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18)),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (showSaveButton)
            FilledButton.icon(
              onPressed: isSaving ? null : onSave,
              icon: const Icon(Icons.save_outlined),
              label: Text(isSaving ? 'Menyimpan...' : 'Simpan harga',
                  style: const TextStyle(fontFamily: 'Roboto')),
            ),
        ],
      ),
    );
  }
}

class _ServicePriceRow extends StatelessWidget {
  const _ServicePriceRow({
    required this.index,
    required this.trailing,
    this.subtitle,
  });

  final int index;
  final Widget trailing;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final label = Row(
      children: [
        professionalServiceArtwork(_serviceCategories[index]),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(professionalServiceNames[_serviceCategories[index]]!,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              if (subtitle != null)
                Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
    return LayoutBuilder(builder: (context, constraints) {
      final largeText = MediaQuery.textScalerOf(context).scale(14) > 16;
      if (constraints.maxWidth < (largeText ? 280 : 215)) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            label,
            const SizedBox(height: 6),
            Align(
                alignment: Alignment.centerRight,
                child: SizedBox(width: 128, child: trailing)),
          ],
        );
      }
      return Row(children: [
        Expanded(flex: 3, child: label),
        const SizedBox(width: 8),
        Flexible(flex: 2, child: trailing),
      ]);
    });
  }
}

String _groupDigits(String digits) => digits.replaceAllMapped(
    RegExp(r'([0-9])(?=(?:[0-9]{3})+$)'), (m) => '${m[1]}.');

String formatProfessionalPrice(int value) =>
    value > 0 ? _groupDigits(value.toString()) : '';

int parseProfessionalPrice(String value) =>
    int.tryParse(value.replaceAll('.', '').trim()) ?? 0;
