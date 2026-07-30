import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../services/malva_api_client.dart';
import '../services/medication_reminder_service.dart';
import 'chat_screen.dart';
import 'diary_screen.dart';
import 'home_screen.dart';
import 'medication_screen.dart';
import 'mood_screen.dart';
import 'assessment_screen.dart';
import 'more_screen.dart';

class PatientShell extends ConsumerStatefulWidget {
  const PatientShell({
    super.key,
    required this.onLogout,
    this.session,
    this.apiClient,
    this.medicationReminderService,
  });

  final VoidCallback onLogout;
  final AuthSession? session;
  final MalvaApiClient? apiClient;
  final MedicationReminderService? medicationReminderService;

  @override
  ConsumerState<PatientShell> createState() => _PatientShellState();
}

class _PatientShellState extends ConsumerState<PatientShell> {
  int _index = 0;
  String _professionalUserId = '';
  String _professionalName = 'Profesional';

  @override
  void initState() {
    super.initState();
    _fetchLinkedProfessional();
  }

  Future<void> _fetchLinkedProfessional() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) return;
    try {
      final links = await apiClient.listPatientProfessionalLinks(
        accessToken: accessToken,
      );
      if (links.isNotEmpty && mounted) {
        setState(() {
          _professionalUserId = links.first.professionalUserId;
          _professionalName = links.first.professionalDisplayName;
        });
      }
    } on Object catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeScreen(
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
                session: widget.session,
              ),
            ),
          );
        },
      ),
      MoodScreen(
        session: widget.session,
        apiClient: widget.apiClient,
      ),
      MedicationScreen(
        session: widget.session,
        apiClient: widget.apiClient,
        medicationReminderService: widget.medicationReminderService,
      ),
      DiaryScreen(
        session: widget.session,
        apiClient: widget.apiClient,
      ),
      ChatScreen(
        otherUserName: _professionalName,
        otherUserId: _professionalUserId,
      ),
      MoreScreen(
          onLogout: widget.onLogout,
          apiClient: widget.apiClient,
          session: widget.session,
          professionalUserId: _professionalUserId,
          professionalName: _professionalName),
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
