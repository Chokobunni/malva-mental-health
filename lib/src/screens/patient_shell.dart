import 'package:flutter/material.dart';

import '../models.dart';
import '../services/malva_api_client.dart';
import '../services/medication_reminder_service.dart';
import '../store/malva_store.dart';
import 'chat_screen.dart';
import 'diary_screen.dart';
import 'home_screen.dart';
import 'medication_screen.dart';
import 'mood_screen.dart';
import 'assessment_screen.dart';
import 'more_screen.dart';

class PatientShell extends StatefulWidget {
  const PatientShell({
    super.key,
    required this.store,
    required this.onLogout,
    this.session,
    this.apiClient,
    this.medicationReminderService,
  });

  final MalvaStore store;
  final VoidCallback onLogout;
  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final MedicationReminderService? medicationReminderService;

  @override
  State<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends State<PatientShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
        store: widget.store,
        session: widget.session,
        apiClient: widget.apiClient,
        onOpenMood: () => setState(() => _index = 1),
        onOpenMedication: () => setState(() => _index = 2),
        onOpenDiary: () => setState(() => _index = 3),
        onOpenChat: () => setState(() => _index = 4),
        onOpenMore: () => setState(() => _index = 5),
        onOpenAssessment: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AssessmentScreen(
                store: widget.store,
                session: widget.session,
              ),
            ),
          );
        },
      ),
      MoodScreen(
        store: widget.store,
        session: widget.session,
        apiClient: widget.apiClient,
      ),
      MedicationScreen(
        store: widget.store,
        session: widget.session,
        apiClient: widget.apiClient,
        medicationReminderService: widget.medicationReminderService,
      ),
      DiaryScreen(
        store: widget.store,
        session: widget.session,
        apiClient: widget.apiClient,
      ),
      ChatScreen(
        session: widget.session,
        apiClient: widget.apiClient,
        otherUserName: 'Profesional',
      ),
      MoreScreen(store: widget.store, onLogout: widget.onLogout, apiClient: widget.apiClient, session: widget.session),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (value) => setState(() => _index = value),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.mood_outlined),
              selectedIcon: Icon(Icons.mood),
              label: 'Mood'),
          NavigationDestination(
              icon: Icon(Icons.medication_outlined),
              selectedIcon: Icon(Icons.medication),
              label: 'Obat'),
          NavigationDestination(
              icon: Icon(Icons.edit_note_outlined),
              selectedIcon: Icon(Icons.edit_note),
              label: 'Diary'),
          NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              selectedIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Chat'),
          NavigationDestination(
              icon: Icon(Icons.grid_view_outlined),
              selectedIcon: Icon(Icons.grid_view),
              label: 'Lainnya'),
        ],
      ),
    );
  }
}
