import 'package:flutter/material.dart';

import '../screens/safety/emergency_dashboard_screen.dart';
import '../theme.dart';

// ============================================================
// SOS FLOATING ACTION BUTTON (persistent, all patient routes)
// ============================================================

class SosFab extends StatelessWidget {
  const SosFab({super.key, this.heroTag = 'sos_fab'});

  final Object heroTag;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 64,
      height: 64,
      child: FloatingActionButton(
        heroTag: heroTag,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const EmergencyDashboardScreen(),
            ),
          );
        },
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
        shape: const CircleBorder(),
        tooltip: 'SOS Darurat',
        child: const Text(
          'SOS',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
      ),
    );
  }
}
