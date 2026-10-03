import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets/malva_components.dart';

// ============================================================
// PSYCHOLOGICAL TESTS MARKETPLACE
// ============================================================

class _PsychTest {
  const _PsychTest({
    required this.title,
    required this.description,
    required this.icon,
    required this.price,
  });

  final String title;
  final String description;
  final IconData icon;
  final int price;
}

class TestsMarketplaceScreen extends StatelessWidget {
  const TestsMarketplaceScreen({super.key});

  static const _tests = [
    _PsychTest(
      title: 'Tes Kepribadian',
      description: 'Kenali pola kepribadian dominanmu.',
      icon: Icons.people_alt_rounded,
      price: 25000,
    ),
    _PsychTest(
      title: '5 Bahasa Cinta',
      description: 'Temukan bahasa cintamu dan pasangan.',
      icon: Icons.favorite_rounded,
      price: 15000,
    ),
    _PsychTest(
      title: 'Happiness',
      description: 'Ukur tingkat kebahagiaan saat ini.',
      icon: Icons.sentiment_satisfied_alt_rounded,
      price: 15000,
    ),
    _PsychTest(
      title: 'Purpose of Life',
      description: 'Refleksi tujuan dan makna hidup.',
      icon: Icons.explore_rounded,
      price: 20000,
    ),
    _PsychTest(
      title: 'Self Efficacy',
      description: 'Seberapa yakin kamu pada kemampuanmu.',
      icon: Icons.fitness_center_rounded,
      price: 15000,
    ),
    _PsychTest(
      title: 'Mental Health',
      description: 'Screening kesehatan mental umum.',
      icon: Icons.psychology_rounded,
      price: 0,
    ),
    _PsychTest(
      title: 'Loneliness',
      description: 'Kenali pola kesepian dan solusinya.',
      icon: Icons.person_off_outlined,
      price: 15000,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Tes Psikologi'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SoftCard(
            color: MalvaColors.plum,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Apakah kamu baik-baik saja hari ini?',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Kenali kondisimu dengan mengikuti tes psikologi dari Malva.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.82,
            children: [
              for (final test in _tests)
                _TestCard(
                  test: test,
                  onStart: () => _showStartDialog(context, test),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showStartDialog(BuildContext context, _PsychTest test) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(test.title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(test.description),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: MalvaColors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Tes ini TIDAK ditujukan untuk mendiagnosis gangguan psikologis, namun untuk membantu mengenali kondisi diri.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            if (test.price > 0) ...[
              const SizedBox(height: 8),
              Text(
                'Rp ${_rupiah(test.price)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: MalvaColors.seed,
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Nanti'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                      '${test.title} segera hadir. Ikuti screening PHQ-9/GAD-7 dulu ya.'),
                ),
              );
            },
            style: compactFilledButtonStyle,
            child: const Text('Mulai Tes'),
          ),
        ],
      ),
    );
  }

  static String _rupiah(int value) {
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

class _TestCard extends StatelessWidget {
  const _TestCard({required this.test, required this.onStart});

  final _PsychTest test;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: MalvaColors.seed.withValues(alpha: 0.1),
            child: Icon(test.icon, color: MalvaColors.seed, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            test.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: Text(
              test.description,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: onStart,
              style: FilledButton.styleFrom(
                backgroundColor: MalvaColors.amber,
                foregroundColor: MalvaColors.ink,
                minimumSize: const Size.fromHeight(38),
                padding: EdgeInsets.zero,
              ),
              child: const Text('Mulai Tes',
                  style: TextStyle(fontWeight: FontWeight.w800)),
            ),
          ),
        ],
      ),
    );
  }
}
