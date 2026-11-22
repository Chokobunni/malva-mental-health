import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../ai/assessment_scoring.dart';
import '../services/health_pdf_report.dart';
import '../services/mood_insights.dart';
import '../platform/platform_providers.dart';
import '../providers/providers.dart';
import 'assessment_history_screen.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';
import '../widgets/care_reference_widgets.dart';
import 'consent_management_screen.dart';
import 'admin/admin_panel_screen.dart';
import 'safety/emergency_contacts_screen.dart';
import 'settings_screens.dart';
import 'notifications_screen.dart';

class MoreScreen extends ConsumerStatefulWidget {
  const MoreScreen({
    super.key,
    required this.onLogout,
    this.apiClient,
    this.session,
    this.professionalUserId = '',
    this.professionalName = 'Profesional',
  });

  final VoidCallback onLogout;
  final MalvaApiClient? apiClient;
  final AuthSession? session;
  final String professionalUserId;
  final String professionalName;

  @override
  ConsumerState<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends ConsumerState<MoreScreen> {
  @override
  Widget build(BuildContext context) {
    final session = widget.session ?? ref.watch(currentSessionProvider);
    final name = session?.displayName.trim().isNotEmpty == true
        ? session!.displayName
        : ref.watch(malvaStoreProvider).patient.name;
    void open(Widget page) =>
        Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    void openProfile() => open(const ProfileScreen());
    void openNotifications() => open(
        NotificationsScreen(session: session, apiClient: widget.apiClient));
    return Scaffold(
      backgroundColor: carePageColor,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          CarePageHeader(
            title: 'Lainnya',
            subtitle: 'Kelola profil, pengaturan, dan data.',
            name: name,
            onNotifications: openNotifications,
            onProfile: openProfile,
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                _MoreCard(
                    child: Row(children: [
                  InitialAvatar(
                      name: name, color: MalvaColors.seed, radius: 20),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text(name,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w900))),
                ])),
                const SizedBox(height: 8),
                const SectionLabel('Pengaturan'),
                _MoreCard(
                    child: Column(children: [
                  _ExportTile(
                      icon: Icons.edit_rounded,
                      title: 'Edit Profil',
                      subtitle: 'Foto dan informasi pribadi',
                      color: MalvaColors.seed,
                      onTap: openProfile),
                  const Divider(height: 12),
                  _ExportTile(
                      icon: Icons.notifications_rounded,
                      title: 'Notifikasi',
                      subtitle: 'Lihat notifikasi Malva',
                      color: MalvaColors.seed,
                      onTap: openNotifications),
                  const Divider(height: 12),
                  _ExportTile(
                      icon: Icons.contact_emergency_rounded,
                      title: 'Kontak Darurat',
                      subtitle: 'Kelola kontak untuk Silent SOS',
                      color: MalvaColors.amber,
                      onTap: () => open(const EmergencyContactsScreen())),
                  const Divider(height: 12),
                  _ExportTile(
                      icon: Icons.settings_rounded,
                      title: 'Settings',
                      subtitle: 'Akun, notifikasi, dan keamanan',
                      color: MalvaColors.seed,
                      onTap: () => open(SettingsScreen(
                          onLogout: widget.onLogout, session: widget.session))),
                  const Divider(height: 12),
                  _ExportTile(
                      icon: Icons.security_rounded,
                      title: 'Consent Management',
                      subtitle: 'Kelola berbagi data dengan profesional',
                      color: MalvaColors.orchid,
                      onTap: () => open(const ConsentManagementScreen())),
                ])),
                if (widget.session?.role == UserRole.admin) ...[
                  const SizedBox(height: 10),
                  ActionTile(
                    icon: Icons.admin_panel_settings_rounded,
                    title: 'Panel Admin',
                    subtitle: 'Kelola pengguna, dokter & verifikasi',
                    color: MalvaColors.danger,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => AdminPanelScreen(
                                apiClient: widget.apiClient,
                                session: widget.session,
                              )),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                const SectionLabel('Export Data'),
                _ExportSection(),
                const SizedBox(height: 20),
                SoftCard(
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Catatan klinis',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                      const SizedBox(height: 8),
                      Text(
                        'Skor assessment di app ini hanya untuk screening dan triase. Diagnosis dan perubahan terapi tetap harus dibuat profesional.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _MoreCard(
                    child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                      backgroundColor: Color(0xfffae7ef),
                      child:
                          Icon(Icons.logout_rounded, color: Color(0xffa62c60))),
                  title: const Text('Keluar',
                      style: TextStyle(
                          color: Color(0xffa62c60),
                          fontWeight: FontWeight.w800)),
                  onTap: widget.onLogout,
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// EXPORT SECTION WIDGET
// ============================================================

class _MoreCard extends StatelessWidget {
  const _MoreCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: careSoftShadow),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: BorderRadius.circular(18),
          child: Padding(padding: const EdgeInsets.all(14), child: child),
        ),
      );
}

class _ExportSection extends ConsumerStatefulWidget {
  @override
  ConsumerState<_ExportSection> createState() => _ExportSectionState();
}

class _ExportSectionState extends ConsumerState<_ExportSection> {
  bool _exporting = false;
  int _accountGeneration = 0;

  String _identity(AuthSession? session) => session == null
      ? ''
      : '${session.role.name}:${session.backendUserId ?? session.identifier}';

  Future<void> _export(String category) async {
    if (_exporting) return;
    final generation = _accountGeneration;
    final session = ref.read(currentSessionProvider);
    final store = ref.read(malvaStoreProvider);
    bool isCurrent() => mounted && generation == _accountGeneration;
    setState(() => _exporting = true);
    try {
      final all = category == 'full_export';
      List<MoodEntry>? moods =
          all || category == 'mood_history' ? store.moodEntries : null;
      List<MedicationLog>? medications =
          all || category == 'medication_log' ? store.medicationLogs : null;
      List<DiaryEntry>? diaries =
          all || category == 'diary' ? store.diaryEntries : null;
      List<ScreeningPdfRow>? screenings;
      final api = ref.read(apiClientProvider);
      final token = session?.accessToken;
      final remote = token != null && token.isNotEmpty;
      final loads = <Future<void>>[];
      if (remote && moods != null) {
        loads.add(
            api.listMoodCheckins(accessToken: token, limit: 0).then((rows) {
          if (rows.any((e) => e.occurredAt == null))
            throw const FormatException('Waktu mood tidak valid.');
          moods = rows.map(moodEntryFromBackend).toList();
        }));
      }
      if (remote && medications != null) {
        loads.add(
            api.listMedicationLogs(accessToken: token, limit: 0).then((rows) {
          medications = rows
              .map((e) => MedicationLog(
                  medicationId: e.medicationId,
                  medicationName: e.medicationName,
                  takenAt: e.takenAt ??
                      e.createdAt ??
                      (throw const FormatException('Waktu obat tidak valid.')),
                  status: e.status))
              .toList();
        }));
      }
      if (remote && diaries != null) {
        loads.add(
            api.listDiaryEntries(accessToken: token, limit: 0).then((rows) {
          diaries = rows
              .map((e) => DiaryEntry(
                  id: e.id,
                  createdAt: e.occurredAt ??
                      (throw const FormatException('Waktu diary tidak valid.')),
                  mood: MoodValue.okay,
                  title: e.title,
                  note: e.note,
                  professionalFeedback: e.professionalFeedback))
              .toList();
        }));
      }
      if (category == 'screenings' || all) {
        if (remote) {
          if (session?.backendUserId?.isNotEmpty != true)
            throw StateError('Identitas pasien belum tersedia.');
          loads.add(loadAssessmentHistory(
                  api: api,
                  accessToken: token,
                  patientId: session?.backendUserId,
                  requireAllSources: true)
              .then((entries) {
            screenings = entries.map(assessmentPdfRow).toList();
          }));
        } else {
          screenings = [
            for (final b in store.screeningBundles)
              ScreeningPdfRow(
                  date: b.createdAt,
                  title: 'PHQ-9 + GAD-7',
                  crisis: b.crisisFlag,
                  scores: [
                    for (final score in [b.phq9, b.gad7])
                      ScreeningPdfScore(
                          instrument: score.type.name.toUpperCase(),
                          total: '${score.score}/${score.maxScore}',
                          interpretation: score.level.label,
                          rank: _screeningRank(score.level.name))
                  ])
          ];
        }
      }
      await Future.wait(loads);
      if (!isCurrent()) return;
      final title = switch (category) {
        'mood_history' => 'Laporan Riwayat Mood: MALVA',
        'screenings' => 'Hasil Screening Psikologis: MALVA',
        'medication_log' => 'Riwayat Konsumsi Obat: MALVA',
        'diary' => 'Catatan Harian: MALVA',
        _ => 'Ringkasan Data Pasien: MALVA',
      };
      await ref.read(exportServiceProvider).shareHealthReport(
          title: title,
          filename: 'malva_$category.pdf',
          moods: moods,
          medicationLogs: medications,
          diaryEntries: diaries,
          screenings: screenings,
          patientName: session?.displayName ?? store.patient.name,
          canShare: isCurrent);
    } catch (_) {
      if (isCurrent()) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDF belum dapat dibuat.')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthSession?>(currentSessionProvider, (previous, next) {
      if (_identity(previous) != _identity(next)) _accountGeneration++;
    });
    if (!ref.watch(capabilitiesProvider).canExportFiles) {
      return const SoftCard(
        child: Text('Ekspor PDF belum tersedia pada perangkat ini.'),
      );
    }
    return _MoreCard(
      child: AbsorbPointer(
        absorbing: _exporting,
        child: Column(
          children: [
            if (_exporting) const LinearProgressIndicator(),
            _ExportTile(
              icon: Icons.mood_rounded,
              title: 'Export Mood History',
              subtitle: 'PDF riwayat mood',
              color: MalvaColors.seed,
              onTap: () => _export('mood_history'),
            ),
            const SizedBox(height: 8),
            _ExportTile(
              icon: Icons.fact_check_rounded,
              title: 'Export Screening Results',
              subtitle: 'PDF WHO-5, GAD-7, PHQ-9, dan DASS-21',
              color: MalvaColors.amber,
              onTap: () => _export('screenings'),
            ),
            const SizedBox(height: 8),
            _ExportTile(
              icon: Icons.medication_rounded,
              title: 'Export Medication Log',
              subtitle: 'PDF riwayat konsumsi obat',
              color: MalvaColors.mint,
              onTap: () => _export('medication_log'),
            ),
            const SizedBox(height: 8),
            _ExportTile(
              icon: Icons.note_rounded,
              title: 'Export Diary Entries',
              subtitle: 'PDF catatan harian',
              color: MalvaColors.orchid,
              onTap: () => _export('diary'),
            ),
            const Divider(height: 24),
            _ExportTile(
              icon: Icons.file_download_rounded,
              title: 'Export All Data (PDF)',
              subtitle: 'Ringkasan data yang tersedia untuk konsultasi',
              color: MalvaColors.plum,
              onTap: () => _export('full_export'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportTile extends StatelessWidget {
  const _ExportTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700)),
                  Text(
                    subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Colors.black54),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.black26),
          ],
        ),
      ),
    );
  }
}

ScreeningPdfRow assessmentPdfRow(AssessmentHistoryEntry entry) {
  final screening = entry.screening;
  if (screening != null) {
    return ScreeningPdfRow(
        date: entry.date,
        title: entry.title,
        crisis: screening.crisisFlag,
        scores: [
          for (final (name, score) in [
            ('PHQ-9', screening.phq9),
            ('GAD-7', screening.gad7)
          ])
            ScreeningPdfScore(
                instrument: name,
                total: '${score.score}/${score.maxScore}',
                interpretation: _screeningLabel(score.level),
                rank: _screeningRank(score.level))
        ]);
  }
  if (entry.moduleId == 'who5') {
    final score = scoreWho5(entry.answers);
    return ScreeningPdfRow(date: entry.date, title: entry.title, scores: [
      ScreeningPdfScore(
          instrument: 'WHO-5',
          total: '${score.raw}/25 (${score.percent}%)',
          interpretation: who5Summary(entry.answers),
          rank: score.possibleDepression
              ? 4
              : score.lowWellbeing
                  ? 3
                  : hasStandardizedWho5LowItem(entry.answers)
                      ? 2
                      : 0)
    ]);
  }
  final score = scoreDass21(entry.answers);
  return ScreeningPdfRow(date: entry.date, title: entry.title, scores: [
    for (final (name, total, level) in [
      ('DASS-21 Depresi', score.depression, score.depressionLevel),
      ('DASS-21 Kecemasan', score.anxiety, score.anxietyLevel),
      ('DASS-21 Stres', score.stress, score.stressLevel)
    ])
      ScreeningPdfScore(
          instrument: name,
          total: '$total/42',
          interpretation: level,
          rank: dassLevelRank(level))
  ]);
}

int _screeningRank(String level) => switch (level.toLowerCase()) {
      'mild' => 1,
      'moderate' => 2,
      'moderately_severe' || 'moderatelysevere' => 3,
      'severe' || 'crisis' => 4,
      _ => 0,
    };
String _screeningLabel(String level) => switch (level.toLowerCase()) {
      'minimal' => 'Minimal',
      'mild' => 'Ringan',
      'moderate' => 'Sedang',
      'moderately_severe' || 'moderatelysevere' => 'Cukup berat',
      'severe' => 'Berat',
      'crisis' => 'Krisis',
      _ => level,
    };
