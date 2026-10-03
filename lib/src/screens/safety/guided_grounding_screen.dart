import 'package:flutter/material.dart';

import '../../theme.dart';
import '../../widgets/malva_components.dart';
import 'emergency_dashboard_screen.dart' show BreathingCircle;

// ============================================================
// GUIDED GROUNDING (NO TALKING) - 4-7-8 breathing + 5-4-3-2-1
// ============================================================

class GuidedGroundingScreen extends StatefulWidget {
  const GuidedGroundingScreen({super.key});

  @override
  State<GuidedGroundingScreen> createState() => _GuidedGroundingScreenState();
}

class _GuidedGroundingScreenState extends State<GuidedGroundingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathController;
  int _checkedCount = 0;
  final Set<int> _checked = {};

  static const _senses = [
    ('Lihat 5 hal di sekitarmu', Icons.visibility_rounded),
    ('Sentuh 4 benda di dekatmu', Icons.touch_app_rounded),
    ('Dengar 3 suara', Icons.hearing_rounded),
    ('Cium 2 aroma', Icons.air_rounded),
    ('Rasakan 1 hal di mulutmu', Icons.restaurant_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _breathController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 19),
    )..repeat();
  }

  @override
  void dispose() {
    _breathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Silent Grounding'),
        backgroundColor: MalvaColors.mint,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          const Text(
            'Ikuti lingkaran napas. Tidak perlu bicara atau mengetik.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          BreathingCircle(controller: _breathController),
          const SizedBox(height: 22),
          const SectionLabel('Grounding 5-4-3-2-1'),
          for (var i = 0; i < _senses.length; i++) ...[
            _SenseRow(
              label: _senses[i].$1,
              icon: _senses[i].$2,
              checked: _checked.contains(i),
              onTap: () {
                setState(() {
                  if (_checked.contains(i)) {
                    _checked.remove(i);
                  } else {
                    _checked.add(i);
                  }
                  _checkedCount = _checked.length;
                });
              },
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 14),
          LinearProgressIndicator(
            value: _checkedCount / _senses.length,
            minHeight: 10,
            color: MalvaColors.mint,
            backgroundColor: MalvaColors.mint.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(999),
          ),
          const SizedBox(height: 8),
          Text(
            '$_checkedCount dari ${_senses.length} selesai',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (_checkedCount == _senses.length) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: MalvaColors.mint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: MalvaColors.mint),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Bagus sekali. Tubuhmu mulai tenang. Jika masih butuh bantuan, tekan SOS kapan saja.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 76),
        ],
      ),
    );
  }
}

class _SenseRow extends StatelessWidget {
  const _SenseRow({
    required this.label,
    required this.icon,
    required this.checked,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool checked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      color: checked ? MalvaColors.mint.withValues(alpha: 0.12) : null,
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: checked
                ? MalvaColors.mint
                : MalvaColors.seed.withValues(alpha: 0.12),
            child: Icon(
              checked ? Icons.check_rounded : icon,
              color: checked ? Colors.white : MalvaColors.seed,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                decoration:
                    checked ? TextDecoration.lineThrough : TextDecoration.none,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
