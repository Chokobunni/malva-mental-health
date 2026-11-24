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
    final capacity = pricing.patientCapacity ?? 2;
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
      for (var i = 0; i < prices.length; i++) ...[
        _serviceSummary(context, i, prices[i]),
        const SizedBox(height: 12),
      ],
      Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: const Color(0xFFFAF5FD),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFF0E9F5))),
          child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.people_outline, color: MalvaColors.seed),
                  SizedBox(width: 8),
                  Text('Slot pasien',
                      style: TextStyle(fontWeight: FontWeight.w800))
                ]),
                Text(
                    capacity == 0
                        ? 'Ditutup untuk pasien baru'
                        : 'Maks. $capacity pasien aktif',
                    style: const TextStyle(
                        color: MalvaColors.seed, fontWeight: FontWeight.w800)),
              ])),
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
    final durations = slots
        .map((s) => s.slotDurationMinutes < 60 ? 60 : s.slotDurationMinutes)
        .toSet()
        .toList()
      ..sort();
    return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: index == 2 ? Colors.white : const Color(0xFFFAFBFD),
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
          const Divider(height: 25, color: Color(0xFFEFF0F3)),
          if (slots.isEmpty)
            const Text('Belum ada jadwal.',
                style: TextStyle(color: Color(0xFF98A2AD)))
          else
            for (final slot in slots)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
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
                    Text(slot.isActive ? 'Aktif' : 'Nonaktif',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: slot.isActive
                                ? const Color(0xFF268C75)
                                : const Color(0xFF87939E))),
                  ])),
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
  });

  final TextEditingController chat;
  final TextEditingController video;
  final TextEditingController package;
  final VoidCallback onSave;
  final bool isSaving;

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
    final color = index == 2 ? const Color(0xFF168369) : MalvaColors.seed;
    final label = Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: .09),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(professionalServiceIcons[_serviceCategories[index]],
                color: color, size: 20),
          ),
        ),
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
