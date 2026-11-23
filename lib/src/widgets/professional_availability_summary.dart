import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/malva_api_client.dart';
import '../theme.dart';
import '../time/wib.dart';
import 'malva_components.dart';

const _services = [
  (Icons.chat_bubble_outline, 'Quick Session (Chat)', '1 sesi', 'per sesi'),
  (Icons.videocam_outlined, 'Quick Session (Video)', '1 sesi', 'per sesi'),
  (
    Icons.event_repeat_outlined,
    'Continuous Package',
    '4 sesi · berlaku 6 minggu',
    '4 sesi · 6 minggu'
  ),
];

const _days = ['Min:', 'Sen:', 'Sel:', 'Rab:', 'Kam:', 'Jum:', 'Sab:'];

class ProfessionalAvailabilitySummary extends StatelessWidget {
  const ProfessionalAvailabilitySummary({
    super.key,
    required this.schedules,
    required this.pricing,
    this.timeOff = const [],
  });

  final List<BackendProfessionalSchedule> schedules;
  final BackendProfessionalPricing pricing;
  final List<BackendTimeOff> timeOff;

  @override
  Widget build(BuildContext context) {
    final active = schedules.where((slot) => slot.isActive).toList()
      ..sort((a, b) {
        final day = ((a.dayOfWeek + 6) % 7).compareTo((b.dayOfWeek + 6) % 7);
        return day == 0 ? a.startTime.compareTo(b.startTime) : day;
      });
    final today = wibDateKey(wibNow());
    final upcomingOff = timeOff
        .where((t) => t.offDate.compareTo(today) >= 0)
        .toList()
      ..sort((a, b) => a.offDate.compareTo(b.offDate));
    final prices = [
      pricing.quickChatPrice,
      pricing.quickVideoPrice,
      pricing.packagePrice
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const Row(children: [
        Expanded(
            child: Text('Jam praktik mingguan',
                style: TextStyle(fontWeight: FontWeight.w800))),
        Text('WIB'),
      ]),
      const SizedBox(height: 8),
      if (active.isEmpty)
        const Text('Belum ada jadwal aktif.',
            style: TextStyle(color: MalvaColors.danger))
      else
        for (final slot in active)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 49,
                  child: Text(_days[slot.dayOfWeek],
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                ),
                Expanded(
                    child: Text(
                        '${slot.startTime}–${slot.endTime} (${slot.slotDurationMinutes} mnt)')),
              ],
            ),
          ),
      const SizedBox(height: 8),
      Text(upcomingOff.isEmpty
          ? 'Hari libur: belum ada'
          : 'Hari libur: ${upcomingOff.map((day) {
              final date = parseWibStored(day.offDate);
              return date == null ? day.offDate : formatWibDate(date);
            }).join(', ')}'),
      const Divider(height: 24),
      for (var i = 0; i < prices.length; i++) ...[
        if (i > 0) const Divider(height: 18),
        _ServicePriceRow(
          index: i,
          trailing: DecoratedBox(
            decoration: BoxDecoration(
              color: MalvaColors.seed.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                      prices[i] <= 0
                          ? 'belum diatur'
                          : 'Rp ${_groupDigits(prices[i].toString())}',
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  Text(_services[i].$4,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        ),
      ],
    ]);
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
      radius: 18,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < controllers.length; i++) ...[
            if (i > 0) const Divider(height: 16),
            _ServicePriceRow(
              index: i,
              subtitle: _services[i].$3,
              trailing: Semantics(
                label: 'Harga ${_services[i].$2}',
                child: TextField(
                  controller: controllers[i],
                  enabled: !isSaving,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    prefixText: 'Rp',
                    hintText: '0',
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9)),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: isSaving ? null : onSave,
            icon: const Icon(Icons.save_outlined),
            label: Text(isSaving ? 'Menyimpan...' : 'Simpan harga'),
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
        DecoratedBox(
          decoration: BoxDecoration(
            color: MalvaColors.seed.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(_services[index].$1,
                color: Theme.of(context).colorScheme.primary, size: 20),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_services[index].$2,
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
