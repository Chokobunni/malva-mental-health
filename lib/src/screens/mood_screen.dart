import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';

class MoodScreen extends ConsumerStatefulWidget {
  const MoodScreen({
    super.key,
    this.session,
    this.apiClient,
  });

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  ConsumerState<MoodScreen> createState() => _MoodScreenState();
}

class _MoodScreenState extends ConsumerState<MoodScreen> {
  MoodValue _mood = MoodValue.okay;
  double _sleep = 7;
  double _energy = 5;
  double _anxiety = 4;
  double _irritability = 2;
  final _noteController = TextEditingController();
  bool _isInitialLoading = true;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 500)).then((_) {
      if (mounted) setState(() => _isInitialLoading = false);
    });
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
      return;
    }
    try {
      final backendEntries = await apiClient.listMoodCheckins(
        accessToken: accessToken,
      );
      final entries = backendEntries
          .map(
            (b) => MoodEntry(
              date: b.occurredAt ?? DateTime.now(),
              mood: MoodValue.values.firstWhere(
                (m) => m.name == b.mood,
                orElse: () => MoodValue.okay,
              ),
              sleepHours: b.sleepHours,
              energy: b.energy,
              anxiety: b.anxiety,
              irritability: b.irritability,
              note: b.note,
            ),
          )
          .toList();
      ref.read(malvaStoreProvider.notifier).replaceMoodEntries(entries);
      if (mounted) setState(() {});
    } on Object catch (_) {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeState = ref.watch(malvaStoreProvider);
    final entries = storeState.moodEntries;
    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refreshData,
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            if (_isInitialLoading) const LinearProgressIndicator(),
            const GradientHeader(
              title: 'Mood Tracker',
              subtitle: 'Mood, tidur, energi, kecemasan',
              leading: Icon(Icons.mood_rounded, color: Colors.white, size: 34),
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: MetricTile(
                          icon: Icons.check_circle_rounded,
                          value: '${entries.length}',
                          label: 'Total check-in',
                          color: MalvaColors.mint,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MetricTile(
                          icon: Icons.local_fire_department_rounded,
                          value: '${entries.take(7).length}',
                          label: 'Streak hari',
                          color: MalvaColors.amber,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  const SectionLabel('Check-in hari ini'),
                  SoftCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Bagaimana perasaanmu?',
                            style: TextStyle(fontWeight: FontWeight.w900)),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: MoodValue.values.map((mood) {
                            return ChoiceChip(
                              avatar: Icon(mood.icon, size: 18),
                              label: Text(mood.label),
                              selected: _mood == mood,
                              onSelected: (_) => setState(() => _mood = mood),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 18),
                        _SliderField(
                          label: 'Tidur',
                          value: _sleep,
                          min: 0,
                          max: 12,
                          divisions: 24,
                          suffix: '${_sleep.toStringAsFixed(1)} jam',
                          onChanged: (value) => setState(() => _sleep = value),
                        ),
                        _SliderField(
                          label: 'Energi',
                          value: _energy,
                          min: 0,
                          max: 10,
                          divisions: 10,
                          suffix: _energy.round().toString(),
                          onChanged: (value) => setState(() => _energy = value),
                        ),
                        _SliderField(
                          label: 'Kecemasan',
                          value: _anxiety,
                          min: 0,
                          max: 10,
                          divisions: 10,
                          suffix: _anxiety.round().toString(),
                          onChanged: (value) =>
                              setState(() => _anxiety = value),
                        ),
                        _SliderField(
                          label: 'Iritabilitas',
                          value: _irritability,
                          min: 0,
                          max: 10,
                          divisions: 10,
                          suffix: _irritability.round().toString(),
                          onChanged: (value) =>
                              setState(() => _irritability = value),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _noteController,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Catatan singkat',
                            hintText:
                                'Trigger, pikiran, atau hal yang membantu hari ini',
                          ),
                        ),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _saveEntry,
                          icon: const Icon(Icons.save_rounded),
                          label: const Text('Simpan Mood Entry'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  const SectionLabel('Combo chart'),
                  SoftCard(
                    child: SizedBox(
                      height: 210,
                      child: entries.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.mood_rounded,
                                      size: 48, color: MalvaColors.seed),
                                  SizedBox(height: 12),
                                  Text(
                                    'Belum ada data mood',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'Data mood akan muncul setelah Anda melakukan check-in.',
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            )
                          : GestureDetector(
                              onTapUp: (details) {
                                final chartEntries =
                                    entries.take(7).toList().reversed.toList();
                                if (chartEntries.isEmpty) return;
                                final RenderBox box =
                                    context.findRenderObject() as RenderBox;
                                final localPosition =
                                    box.globalToLocal(details.globalPosition);
                                final step =
                                    box.size.width / chartEntries.length;
                                final index = (localPosition.dx / step).floor();
                                if (index >= 0 && index < chartEntries.length) {
                                  _showMoodDetail(context, chartEntries[index]);
                                }
                              },
                              child: CustomPaint(
                                painter: _MoodChartPainter(
                                    entries.take(7).toList().reversed.toList()),
                                child: const SizedBox.expand(),
                              ),
                            ),
                    ),
                  ),
                  if (entries.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _ChartLegend(color: MalvaColors.mint, label: 'Mood'),
                          const SizedBox(width: 16),
                          _ChartLegend(
                              color: MalvaColors.amber, label: 'Kecemasan'),
                          const SizedBox(width: 16),
                          _ChartLegend(color: MalvaColors.pink, label: 'Tidur'),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _saveEntry() {
    final entry = MoodEntry(
      date: DateTime.now(),
      mood: _mood,
      sleepHours: _sleep,
      energy: _energy.round(),
      anxiety: _anxiety.round(),
      irritability: _irritability.round(),
      note: _noteController.text.trim().isEmpty
          ? 'Tidak ada catatan.'
          : _noteController.text.trim(),
    );
    ref.read(malvaStoreProvider.notifier).addMood(entry);

    // Offline-first: always save locally, queue for sync if offline
    final isOnline = ref.read(isOnlineProvider);
    if (isOnline) {
      unawaited(_syncEntry(entry));
    } else {
      unawaited(ref.read(offlineSyncServiceProvider).enqueueMood(entry));
    }

    _noteController.clear();
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Mood entry tersimpan.')));
  }

  Future<void> _syncEntry(MoodEntry entry) async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      // Queue for later sync
      unawaited(ref.read(offlineSyncServiceProvider).enqueueMood(entry));
      return;
    }
    try {
      await apiClient.createMoodCheckin(
        accessToken: accessToken,
        mood: entry.mood.name,
        sleepHours: entry.sleepHours,
        energy: entry.energy,
        anxiety: entry.anxiety,
        irritability: entry.irritability,
        note: entry.note,
        occurredAt: entry.date,
      );
    } on Object catch (error) {
      // Queue for offline sync on failure
      unawaited(ref.read(offlineSyncServiceProvider).enqueueMood(entry));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Tersimpan lokal, akan sync saat online: $error'),
        ),
      );
    }
  }

  void _showMoodDetail(BuildContext context, MoodEntry entry) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(entry.mood.icon, color: MalvaColors.seed, size: 42),
        title: Text(entry.mood.label),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _DetailRow(
                  icon: Icons.bed_rounded,
                  label: 'Tidur',
                  value: '${entry.sleepHours.toStringAsFixed(1)} jam'),
              const SizedBox(height: 8),
              _DetailRow(
                  icon: Icons.battery_full_rounded,
                  label: 'Energi',
                  value: '${entry.energy}/10'),
              const SizedBox(height: 8),
              _DetailRow(
                  icon: Icons.psychology_rounded,
                  label: 'Kecemasan',
                  value: '${entry.anxiety}/10'),
              const SizedBox(height: 8),
              _DetailRow(
                  icon: Icons.mood_bad_rounded,
                  label: 'Iritabilitas',
                  value: '${entry.irritability}/10'),
              if (entry.note.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Catatan:',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 4),
                Text(entry.note),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: MalvaColors.seed),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _ChartLegend extends StatelessWidget {
  const _ChartLegend({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

class _SliderField extends StatelessWidget {
  const _SliderField({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.suffix,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final String suffix;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
                child: Text(label,
                    style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(suffix,
                style: const TextStyle(
                    fontWeight: FontWeight.w900, color: MalvaColors.seed)),
          ],
        ),
        Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged),
      ],
    );
  }
}

class _MoodChartPainter extends CustomPainter {
  const _MoodChartPainter(this.entries);

  final List<MoodEntry> entries;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.08)
      ..strokeWidth = 1;
    final barPaint = Paint()..color = MalvaColors.pink.withValues(alpha: 0.55);
    final moodPaint = Paint()
      ..color = MalvaColors.mint
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final anxietyPaint = Paint()
      ..color = MalvaColors.amber
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    for (var i = 0; i <= 4; i++) {
      final y = size.height - (size.height * i / 4);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    if (entries.isEmpty) return;
    final step = size.width / entries.length;
    final moodPath = Path();
    final anxietyPath = Path();

    for (var i = 0; i < entries.length; i++) {
      final entry = entries[i];
      final x = step * i + step / 2;
      final sleepRatio = (entry.sleepHours / 12).clamp(0.0, 1.0).toDouble();
      final sleepHeight = sleepRatio * size.height;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - step * 0.22, size.height - sleepHeight, step * 0.44,
              sleepHeight),
          const Radius.circular(6),
        ),
        barPaint,
      );

      final moodY = size.height - (entry.mood.score / 5) * size.height;
      final anxietyY = size.height - (entry.anxiety / 10) * size.height;
      if (i == 0) {
        moodPath.moveTo(x, moodY);
        anxietyPath.moveTo(x, anxietyY);
      } else {
        moodPath.lineTo(x, moodY);
        anxietyPath.lineTo(x, anxietyY);
      }
    }

    canvas.drawPath(moodPath, moodPaint);
    canvas.drawPath(anxietyPath, anxietyPaint);
  }

  @override
  bool shouldRepaint(covariant _MoodChartPainter oldDelegate) =>
      oldDelegate.entries != entries;
}
