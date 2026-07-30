import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'src/malva_app.dart';
import 'src/services/medication_reminder_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  try {
    await Firebase.initializeApp();
  } on Object {
    // Firebase not configured — app continues without FCM
  }

  final medicationReminderService = MedicationReminderService();
  await medicationReminderService.initialize();

  runApp(MalvaApp(
    medicationReminderService: medicationReminderService,
  ));
}
