import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';
import '../widgets/therapy_library.dart';
import 'assessment_screen.dart';

// ============================================================
// ASSESSMENT LIST — daftar pilihan asesmen dari Home.
// Menampilkan: PHQ-9 + GAD-7 (screening utama) serta asesmen lanjutan
// (DASS-21, WHO-5) yang tersimpan di database sebagai worksheet.
// ============================================================

class AssessmentListScreen extends ConsumerWidget {
  const AssessmentListScreen({super.key, this.session, this.apiClient});

  final AuthSession? session;
  final MalvaApiClient? apiClient;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store = ref.watch(malvaStoreProvider);
    final latest = store.latestScreeningBundle;
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          GradientHeader(
            title: 'Assessment',
            subtitle: 'Pilih asesmen sesuai kebutuhanmu',
            leading: IconButton(
              onPressed: () => Navigator.maybePop(context),
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (latest != null) ...[
                  SoftCard(
                    color: latest.overallLevel.color.withValues(alpha: 0.10),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor:
                              latest.overallLevel.color.withValues(alpha: 0.18),
                          child: Icon(Icons.history_rounded,
                              color: latest.overallLevel.color),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Screening terakhir',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14)),
                              Text(
                                'PHQ-9 ${latest.phq9.score}/${latest.phq9.maxScore} '
                                '(${latest.phq9.level.label}) • '
                                'GAD-7 ${latest.gad7.score}/${latest.gad7.maxScore} '
                                '(${latest.gad7.level.label})',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        StatusPill(
                          label: latest.overallLevel.label,
                          color: latest.overallLevel.color,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                ],
                const SectionLabel('Screening Utama'),
                _AssessmentTile(
                  icon: Icons.fact_check_rounded,
                  color: MalvaColors.seed,
                  title: 'PHQ-9 + GAD-7',
                  subtitle:
                      'Screening depresi & kecemasan (16 pertanyaan, 2 minggu terakhir).',
                  badge: 'Wajib',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AssessmentScreen(
                        session: session,
                        apiClient: apiClient,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const SectionLabel('Assessment Lanjutan'),
                _AssessmentTile(
                  icon: dass21Module.icon ?? Icons.assignment_rounded,
                  color: dass21Module.color ?? MalvaColors.seed,
                  title: dass21Module.title,
                  subtitle:
                      '21 pertanyaan: depresi, kecemasan, dan stres (skala 0-3).',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const TherapyDetailScreen(module: dass21Module),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _AssessmentTile(
                  icon: who5Module.icon ?? Icons.favorite_rounded,
                  color: who5Module.color ?? MalvaColors.mint,
                  title: who5Module.title,
                  subtitle:
                      '5 pertanyaan kesejahteraan psikologis (skala 0-5).',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) =>
                          const TherapyDetailScreen(module: who5Module),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SoftCard(
                  color: MalvaColors.amber.withValues(alpha: 0.10),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded,
                          color: MalvaColors.amber),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Hasil asesmen adalah alat bantu screening, bukan '
                          'diagnosis. Diagnosis hanya dapat diberikan oleh '
                          'profesional terverifikasi setelah sesi konsultasi.',
                          style: TextStyle(
                              fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                OutlinedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const TherapyCatalogScreen(),
                    ),
                  ),
                  icon: const Icon(Icons.psychology_rounded),
                  label: const Text('Lihat Semua Therapy & Worksheet'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssessmentTile extends StatelessWidget {
  const _AssessmentTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: color.withValues(alpha: 0.14),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900, fontSize: 14.5)),
                    ),
                    if (badge != null) StatusPill(label: badge!, color: color),
                  ],
                ),
                const SizedBox(height: 3),
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
          const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}
