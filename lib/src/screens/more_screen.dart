import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';
import 'assessment_screen.dart';
import 'chat_screen.dart';
import 'consent_management_screen.dart';
import 'goals_screen.dart';
import 'record_screen.dart';

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
  bool _privacyMode = false;
  bool _hideDiagnosis = false;
  bool _hideMedicationName = false;

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
                  icon: Icons.fact_check_rounded,
                  title: 'Self Assessments',
                  subtitle: 'PHQ-9, GAD-7, dan forward chaining result',
                  color: MalvaColors.amber,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const AssessmentScreen()),
                  ),
                ),
                const SizedBox(height: 10),
                ActionTile(
                  icon: Icons.flag_rounded,
                  title: 'Goals & Habits',
                  subtitle: 'Target harian, streak, reminder',
                  color: MalvaColors.seed,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const GoalsScreen()),
                  ),
                ),
                const SizedBox(height: 10),
                ActionTile(
                  icon: Icons.folder_shared_rounded,
                  title: 'Health Record',
                  subtitle: 'Diagnosis, obat, dan file klinis',
                  color: MalvaColors.mint,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const RecordScreen()),
                  ),
                ),
                const SizedBox(height: 10),
                ActionTile(
                  icon: Icons.chat_bubble_outline_rounded,
                  title: 'Chat dengan Profesional',
                  subtitle: 'Kirim pesan langsung ke profesional Anda',
                  color: MalvaColors.orchid,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ChatScreen(
                              otherUserName: widget.professionalName,
                              otherUserId: widget.professionalUserId,
                            )),
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
                        builder: (_) => ConsentManagementScreen()),
                  ),
                ),
                const SizedBox(height: 20),
                const SectionLabel('Pengaturan Privasi'),
                SoftCard(
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.lock_rounded,
                              color: MalvaColors.seed),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Privacy Mode',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  'Sembunyikan detail sensitif dari notifikasi lock screen',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _privacyMode,
                            onChanged: (value) {
                              setState(() => _privacyMode = value);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    value
                                        ? 'Privacy mode aktif. Notifikasi tidak akan menampilkan detail sensitif.'
                                        : 'Privacy mode nonaktif. Notifikasi menampilkan detail normal.',
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          const Icon(Icons.notifications_off_rounded,
                              color: MalvaColors.amber),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Sembunyikan Diagnosis',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  'Jangan tampilkan diagnosis di notifikasi',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _hideDiagnosis,
                            onChanged: (value) {
                              setState(() => _hideDiagnosis = value);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    value
                                        ? 'Diagnosis disembunyikan dari notifikasi.'
                                        : 'Diagnosis ditampilkan di notifikasi.',
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          const Icon(Icons.medication_rounded,
                              color: MalvaColors.mint),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Sembunyikan Nama Obat',
                                  style: TextStyle(fontWeight: FontWeight.w700),
                                ),
                                Text(
                                  'Jangan tampilkan nama obat di notifikasi',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: Colors.black54),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: _hideMedicationName,
                            onChanged: (value) {
                              setState(() => _hideMedicationName = value);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    value
                                        ? 'Nama obat disembunyikan dari notifikasi.'
                                        : 'Nama obat ditampilkan di notifikasi.',
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
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
                        'Hasil assessment di app ini hanya untuk screening dan triase. Diagnosis dan perubahan terapi tetap harus dibuat profesional.',
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
