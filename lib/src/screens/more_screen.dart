import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../platform/platform_providers.dart';
import '../providers/providers.dart';
import '../time/wib.dart';
import 'assessment_history_screen.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';
import 'consent_management_screen.dart';
import 'admin/admin_panel_screen.dart';
import 'safety/emergency_contacts_screen.dart';
import 'settings_screens.dart';

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
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientHeader(
            title: 'Lainnya',
            subtitle: 'Assessment, goals, record, dan pengaturan',
            trailing: IconButton(
              tooltip: 'Keluar',
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout_rounded, color: Colors.white),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                ActionTile(
                  icon: Icons.contact_emergency_rounded,
                  title: 'Kontak Darurat',
                  subtitle: 'Kelola kontak untuk Silent SOS',
                  color: MalvaColors.amber,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const EmergencyContactsScreen()),
                  ),
                ),
                const SizedBox(height: 10),
                ActionTile(
                  icon: Icons.settings_rounded,
                  title: 'Settings',
                  subtitle: 'Akun, notifikasi, dan keamanan',
                  color: MalvaColors.seed,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => SettingsScreen(
                            onLogout: widget.onLogout,
                            session: widget.session)),
                  ),
                ),
                const SizedBox(height: 10),
                ActionTile(
                  icon: Icons.security_rounded,
                  title: 'Consent Management',
                  subtitle: 'Kelola berbagi data dengan profesional',
                  color: MalvaColors.orchid,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const ConsentManagementScreen()),
                  ),
                ),
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
    final mood = ref.read(moodReportProvider);
    final medications = ref.read(medicationReportProvider);
    final diary = ref.read(diaryReportProvider);
    bool isCurrent() => mounted && generation == _accountGeneration;
    setState(() => _exporting = true);
    try {
      final screeningLines = <String>[];
      if (category == 'screenings' || category == 'full_export') {
        final token = session?.accessToken;
        if (token != null && token.isNotEmpty) {
          final entries = await loadAssessmentHistory(
            api: ref.read(apiClientProvider),
            accessToken: token,
            patientId: session?.backendUserId,
            requireAllSources: true,
          );
          screeningLines.addAll([
            'RIWAYAT SCREENING',
            'Hasil yang tersedia di Assessment Record (hingga 50 sesi PHQ-9/GAD-7 terbaru).',
            if (entries.isEmpty) 'Belum ada hasil screening lengkap.',
            for (final entry in entries)
              '${entry.title} | ${formatAssessmentDate(entry.date)}\n${entry.subtitle}',
          ]);
        } else {
          screeningLines.addAll([
            'RIWAYAT SCREENING LOKAL',
            'Hanya data yang tersimpan pada perangkat ini.',
            if (store.screeningBundles.isEmpty)
              'Belum ada hasil screening lokal.',
            for (final bundle in store.screeningBundles)
              '${formatWibDateTime(bundle.createdAt)} | '
                  'PHQ-9 ${bundle.phq9.score}/27 (${bundle.phq9.level}); '
                  'GAD-7 ${bundle.gad7.score}/21 (${bundle.gad7.level})',
          ]);
        }
      }
      if (!isCurrent()) return;
      final (title, lines) = switch (category) {
        'mood_history' => ('Riwayat Mood', mood),
        'screenings' => ('Hasil Screening', screeningLines),
        'medication_log' => ('Riwayat Konsumsi Obat', medications),
        'diary' => ('Catatan Harian', diary),
        _ => (
            'Ringkasan Data Pasien',
            [
              'Nama: ${session?.displayName ?? store.patient.name}',
              'Ringkasan untuk konsultasi: mood, screening, konsumsi obat, dan catatan harian yang tersedia pada akun/perangkat ini.',
              ...mood,
              ...screeningLines,
              ...medications,
              ...diary,
            ]
          ),
      };
      await ref.read(exportServiceProvider).sharePdf(
            title: title,
            lines: lines,
            filename: 'malva_$category.pdf',
            canShare: isCurrent,
          );
    } catch (_) {
      if (isCurrent()) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'PDF belum dapat dibuat. Periksa koneksi lalu coba lagi.')));
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
    return SoftCard(
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
