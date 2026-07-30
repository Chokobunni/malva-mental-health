import 'package:flutter/material.dart';

import 'src/malva_app.dart';
import 'src/services/medication_reminder_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final medicationReminderService = MedicationReminderService();
  await medicationReminderService.initialize();

  runApp(MalvaApp(
    medicationReminderService: medicationReminderService,
  ));
}
