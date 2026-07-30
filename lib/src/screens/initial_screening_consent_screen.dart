import 'package:flutter/material.dart';

import '../store/malva_store.dart';
import '../theme.dart';

class InitialScreeningConsentScreen extends StatelessWidget {
  const InitialScreeningConsentScreen({
    super.key,
    required this.store,
    required this.onAgree,
    required this.onSkip,
  });

  final MalvaStore store;
  final VoidCallback onAgree;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF4A2667), Color(0xFFB85FD0), Color(0xFFE99AE9)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Spacer(),
                const Icon(Icons.local_florist_rounded,
                    color: Colors.white, size: 54),
                const SizedBox(height: 20),
                Text(
                  'Symptoms Assessment',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'PHQ-9 dan GAD-7 untuk screening awal',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 26),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      children: [
                        const Text(
                          'Apakah kamu bersedia menjawab pertanyaan agar profesional bisa memahami kebutuhan awalmu?',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 17),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Ini adalah screening, bukan diagnosis. Hasilnya akan tersimpan sebagai pertimbangan tambahan profesional.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.black54),
                        ),
                        const SizedBox(height: 18),
                        FilledButton.icon(
                          onPressed: onAgree,
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Saya setuju'),
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton(
                          onPressed: () {
                            store.skipInitialScreening();
                            onSkip();
                          },
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(50),
                            foregroundColor: MalvaColors.plum,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: const Text('Skip'),
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
