import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../services/malva_api_client.dart';
import '../services/medication_reminder_service.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';
import 'medication_screen.dart';
import 'mood_screen.dart';

// ============================================================
// MOOD MEDICATION CHECK-IN — screen gabungan (tab Mood / Medication).
// Dibuka dari banner "Mood Medication Check-in" di Home.
// ============================================================

class MoodMedicationCheckinScreen extends ConsumerStatefulWidget {
  const MoodMedicationCheckinScreen({
    super.key,
    this.session,
    this.apiClient,
    this.medicationReminderService,
  });

  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final MedicationReminderService? medicationReminderService;

  @override
  ConsumerState<MoodMedicationCheckinScreen> createState() =>
      _MoodMedicationCheckinScreenState();
}

class _MoodMedicationCheckinScreenState
    extends ConsumerState<MoodMedicationCheckinScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          const GradientHeader(
            title: 'Check-in Mood & Obat',
            subtitle: 'Pantau mood harian & kepatuhan obat',
            leading: Icon(Icons.monitor_heart_rounded,
                color: Colors.white, size: 34),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 268),
              child: DecoratedBox(
                decoration: const ShapeDecoration(
                  color: Color(0xffe9eaee),
                  shape: StadiumBorder(),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      for (final (index, label, icon) in const [
                        (0, 'Mood', Icons.sentiment_satisfied_alt_outlined),
                        (1, 'Obat', Icons.medication_outlined),
                      ])
                        Expanded(
                          child: Semantics(
                            selected: _tab == index,
                            child: TextButton.icon(
                              onPressed: () => setState(() => _tab = index),
                              style: TextButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                backgroundColor: _tab == index
                                    ? MalvaColors.seed
                                    : Colors.transparent,
                                foregroundColor: _tab == index
                                    ? Colors.white
                                    : const Color(0xff4b5563),
                                textStyle: const TextStyle(
                                    fontSize: 15, fontWeight: FontWeight.w700),
                              ),
                              icon: index == 0
                                  ? Icon(icon, size: 19)
                                  : const ImageIcon(
                                      AssetImage(
                                          'assets/prescription/capsule.png'),
                                      size: 19,
                                    ),
                              label: Text(label),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: _tab == 0
                ? MoodScreen(
                    session: widget.session,
                    apiClient: widget.apiClient,
                    embedded: true,
                  )
                : MedicationScreen(
                    session: widget.session,
                    apiClient: widget.apiClient,
                    medicationReminderService: widget.medicationReminderService,
                    embedded: true,
                  ),
          ),
        ],
      ),
    );
  }
}
