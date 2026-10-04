import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../services/malva_api_client.dart';
import '../services/medication_reminder_service.dart';
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
            title: 'Mood Medication Check-in',
            subtitle: 'Pantau mood harian & kepatuhan obat',
            leading: Icon(Icons.monitor_heart_rounded,
                color: Colors.white, size: 34),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Mood')),
                ButtonSegment(value: 1, label: Text('Medication')),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
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
