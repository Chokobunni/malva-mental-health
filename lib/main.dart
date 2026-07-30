import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';
import 'src/malva_app.dart';
import 'src/services/medication_reminder_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  final medicationReminderService = MedicationReminderService();
  await medicationReminderService.initialize();

  runApp(MalvaApp(
    medicationReminderService: medicationReminderService,
  ));
}
