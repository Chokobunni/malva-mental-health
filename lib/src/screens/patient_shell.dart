import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../services/medication_reminder_service.dart';
import '../services/realtime_service.dart';
import 'assessment_list_screen.dart';
import 'home_screen.dart';
import 'messages_list_screen.dart';
import 'more_screen.dart';
import 'my_care_screen.dart';
import '../widgets/sos_fab.dart';
import '../widgets/doctor_review_actions.dart';

// ============================================================
// PATIENT SHELL — Navbar bawah baru (4 ikon, tanpa label):
//   Home  |  My Care  |  Messages  |  Lainnya (smile)
// MyCare = jadwal profesional; Messages = chat dengan profesional
// (tersedia bila terhubung Continuous Support); Smile = sidebar.
// ============================================================

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

class _PatientShellState extends ConsumerState<PatientShell>
    with WidgetsBindingObserver {
  int _index = 0;
  String _professionalUserId = '';
  String _professionalName = 'Profesional';

  /// Koneksi realtime untuk menerima perubahan profil profesional
  /// (foto/video intro) tanpa perlu refresh manual.
  RealtimeService? _realtime;
  StreamSubscription<RealtimeEvent>? _realtimeSub;
  int _realtimeGeneration = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connectRealtime();
    _fetchLinkedProfessional();
  }

  @override
  void didUpdateWidget(covariant PatientShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Token berubah (login ulang / akun berbeda) → sambungkan ulang.
    if (oldWidget.session?.accessToken != widget.session?.accessToken) {
      _connectRealtime();
      _fetchLinkedProfessional();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _realtimeGeneration++;
    _realtimeSub?.cancel();
    _realtime?.dispose();
    super.dispose();
  }

  /// Menyambungkan klien realtime dan meneruskan event perubahan profil
  /// profesional ke provider revisi agar layar pasien memuat ulang data.
  void _connectRealtime() {
    final generation = ++_realtimeGeneration;
    final apiClient = widget.apiClient;
    final token = widget.session?.accessToken;
    _realtimeSub?.cancel();
    _realtime?.dispose();
    _realtime = null;
    _realtimeSub = null;
    if (apiClient == null || token == null || token.isEmpty) return;

    final service = RealtimeService(
      accessToken: token,
      baseUrl: apiClient.baseUri.toString(),
    );
    _realtime = service;
    _realtimeSub = service.events.listen((event) {
      if (!mounted || generation != _realtimeGeneration) return;
      switch (event.type) {
        case 'realtime.connected':
          _refreshClinicalData();
        case 'clinical_data_changed':
          final owner =
              widget.session?.backendUserId ?? widget.session?.identifier;
          if (event.stringValue('patient_id') == owner &&
              const ['medications', 'goals', 'health_record']
                  .contains(event.stringValue('resource'))) {
            _refreshClinicalData();
          }
        case 'professional.profile.updated':
          final updatedId = event.stringValue('professional_user_id');
          ref.read(professionalProfileUpdatedIdProvider.notifier).state =
              updatedId;
          ref.read(professionalProfileRevisionProvider.notifier).state++;
          // Nama profesional bisa ikut berubah — segarkan data tautan.
          _fetchLinkedProfessional();
        default:
          break;
      }
    });
    service.connect();
  }

  void _refreshClinicalData() {
    final session = widget.session;
    final api = widget.apiClient;
    final token = session?.accessToken;
    if (!mounted ||
        session?.role != UserRole.patient ||
        api == null ||
        token == null ||
        token.isEmpty) return;
    // The store rejects responses belonging to an earlier account or an older
    // hydration request. Its update also reschedules existing local reminders.
    unawaited(
        ref.read(malvaStoreProvider.notifier).loadMedications(api, token));
    ref.read(clinicalDataRevisionProvider.notifier).state++;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshClinicalData();
      _connectRealtime();
    }
  }

  Future<void> _fetchLinkedProfessional() async {
    final generation = _realtimeGeneration;
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      return;
    }
    try {
      final links = await apiClient.listPatientProfessionalLinks(
        accessToken: accessToken,
      );
      if (links.isNotEmpty && mounted && generation == _realtimeGeneration) {
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
      // 0. HOME
      HomeScreen(
        session: widget.session,
        apiClient: widget.apiClient,
        medicationReminderService: widget.medicationReminderService,
        onOpenMood: () => setState(() => _index = 0),
        onOpenMedication: () => setState(() => _index = 0),
        onOpenDiary: () => setState(() => _index = 0),
        onOpenChat: () => setState(() => _index = 2),
        onOpenMore: () => setState(() => _index = 3),
        onOpenAssessment: () {
          // Ke halaman LIST asesmen — bukan langsung PHQ-9/GAD-7.
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AssessmentListScreen(
                session: widget.session,
                apiClient: widget.apiClient,
              ),
            ),
          );
        },
      ),
      // 1. MY CARE (jadwal profesional)
      MyCareScreen(
        session: widget.session,
        apiClient: widget.apiClient,
      ),
      // 2. MESSAGES (chat dengan profesional)
      MessagesListScreen(
        session: widget.session,
        apiClient: widget.apiClient,
      ),
      // 3. LAINNYA (sidebar)
      MoreScreen(
        onLogout: widget.onLogout,
        apiClient: widget.apiClient,
        session: widget.session,
        professionalUserId: _professionalUserId,
        professionalName: _professionalName,
      ),
    ];

    final scaffold = Scaffold(
      body: IndexedStack(index: _index, children: pages),
      // SOS hanya di Home.
      floatingActionButton: _index == 0 ? const SosFab() : null,
      bottomNavigationBar: ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          child: NavigationBarTheme(
              data: NavigationBarThemeData(
                  iconTheme: WidgetStateProperty.resolveWith((states) =>
                      IconThemeData(
                          color: states.contains(WidgetState.selected)
                              ? const Color(0xff9755ad)
                              : const Color(0xff9ca3af)))),
              child: NavigationBar(
                backgroundColor: Colors.white,
                indicatorColor: const Color(0xfff8f1fc),
                indicatorShape: const CircleBorder(),
                height: 64,
                labelBehavior: NavigationDestinationLabelBehavior.alwaysHide,
                selectedIndex: _index,
                onDestinationSelected: (value) =>
                    setState(() => _index = value),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'Home',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.event_note_outlined),
                    selectedIcon: Icon(Icons.event_note_rounded),
                    label: 'MyCare',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.chat_bubble_outline_rounded),
                    selectedIcon: Icon(Icons.chat_bubble_rounded),
                    label: 'Messages',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.sentiment_satisfied_alt_outlined),
                    selectedIcon: Icon(Icons.sentiment_satisfied_alt_rounded),
                    label: 'Lainnya',
                  ),
                ],
              ))),
    );
    return ReviewCompletionPrompt(
        apiClient: widget.apiClient ?? ref.read(apiClientProvider),
        child: scaffold);
  }
}
