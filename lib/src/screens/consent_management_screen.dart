import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';

class ConsentManagementScreen extends ConsumerStatefulWidget {
  const ConsentManagementScreen({super.key});

  @override
  ConsumerState<ConsentManagementScreen> createState() =>
      _ConsentManagementScreenState();
}

class _ConsentManagementScreenState
    extends ConsumerState<ConsentManagementScreen> {
  bool _shareScreenings = false;
  bool _shareMoodDiary = false;
  bool _shareMedications = false;
  bool _shareTimeline = false;
  bool _shareHealthRecord = false;
  bool _shareGoals = false;
  bool _isLoading = false;
  String? _error;
  List<BackendPatientProfessionalLink> _links = const [];
  String? _selectedProfessionalId;

  @override
  void initState() {
    super.initState();
    _loadConsent();
  }

  Future<void> _loadConsent() async {
    final apiClient = ref.read(apiClientProvider);
    final session = ref.read(currentSessionProvider);
    final accessToken = session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Daftar profesional terhubung DULU — consent bersifat per profesional,
      // bukan ke ID sendiri (bug lama memakai session.identifier).
      final links = await apiClient.listPatientProfessionalLinks(
        accessToken: accessToken,
      );
      final active =
          links.where((l) => l.status == 'active').toList(growable: false);
      if (!mounted) return;
      setState(() => _links = active);
      if (active.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }
      _selectedProfessionalId ??= active.first.professionalUserId;
      final consent = await apiClient.getPrivacyConsent(
        accessToken: accessToken,
        professionalId: _selectedProfessionalId!,
      );
      if (mounted) {
        setState(() {
          _shareScreenings = consent.shareScreenings;
          _shareMoodDiary = consent.shareMoodDiary;
          _shareMedications = consent.shareMedications;
          _shareTimeline = consent.shareTimeline;
          _shareHealthRecord = consent.shareHealthRecord;
          _shareGoals = consent.shareGoals;
          _isLoading = false;
        });
      }
    } on MalvaApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _isLoading = false;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = 'Gagal memuat consent: $error';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateConsent() async {
    final apiClient = ref.read(apiClientProvider);
    final session = ref.read(currentSessionProvider);
    final accessToken = session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      return;
    }

    if (_selectedProfessionalId == null || _selectedProfessionalId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Belum ada profesional terhubung untuk diatur.')),
      );
      return;
    }
    setState(() => _isLoading = true);

    try {
      await apiClient.updatePrivacyConsent(
        accessToken: accessToken,
        professionalId: _selectedProfessionalId!,
        shareScreenings: _shareScreenings,
        shareMoodDiary: _shareMoodDiary,
        shareMedications: _shareMedications,
        shareTimeline: _shareTimeline,
        shareHealthRecord: _shareHealthRecord,
        shareGoals: _shareGoals,
      );
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pengaturan consent berhasil disimpan.'),
          ),
        );
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal menyimpan consent: $error'),
            backgroundColor: MalvaColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const GradientHeader(
            title: 'Consent Management',
            subtitle: 'Kelola berbagi data dengan profesional',
            leading:
                Icon(Icons.security_rounded, color: Colors.white, size: 34),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_isLoading) const LinearProgressIndicator(),
                if (_error != null)
                  SoftCard(
                    color: MalvaColors.danger.withValues(alpha: 0.08),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded,
                            color: MalvaColors.danger),
                        const SizedBox(width: 12),
                        Expanded(child: Text(_error!)),
                        TextButton(
                          onPressed: _loadConsent,
                          child: const Text('Coba lagi'),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                const Text(
                  'Pilih profesional, lalu atur data yang dibagikan (default mati — aktifkan yang kamu setujui):',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (_links.isEmpty && !_isLoading)
                  const SoftCard(
                    child: Text(
                        'Belum ada profesional terhubung. Beli paket / booking sesi dulu untuk mengatur sharing.'),
                  )
                else if (_links.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: _selectedProfessionalId,
                    decoration: const InputDecoration(
                      labelText: 'Profesional',
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: [
                      for (final l in _links)
                        DropdownMenuItem(
                          value: l.professionalUserId,
                          child: Text(l.professionalDisplayName.isEmpty
                              ? 'Profesional'
                              : l.professionalDisplayName),
                        ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _selectedProfessionalId = v);
                      _loadConsent();
                    },
                  ),
                const SizedBox(height: 16),
                _ConsentSwitch(
                  icon: Icons.fact_check_rounded,
                  title: 'Screening Results',
                  subtitle: 'Hasil PHQ-9 dan GAD-7',
                  value: _shareScreenings,
                  onChanged: (value) {
                    setState(() => _shareScreenings = value);
                  },
                ),
                const SizedBox(height: 12),
                _ConsentSwitch(
                  icon: Icons.mood_rounded,
                  title: 'Mood & Diary',
                  subtitle: 'Data mood check-in dan diary entries',
                  value: _shareMoodDiary,
                  onChanged: (value) {
                    setState(() => _shareMoodDiary = value);
                  },
                ),
                const SizedBox(height: 12),
                _ConsentSwitch(
                  icon: Icons.medication_rounded,
                  title: 'Medications',
                  subtitle: 'Daftar obat dan log konsumsi',
                  value: _shareMedications,
                  onChanged: (value) {
                    setState(() => _shareMedications = value);
                  },
                ),
                const SizedBox(height: 12),
                _ConsentSwitch(
                  icon: Icons.timeline_rounded,
                  title: 'Timeline',
                  subtitle: 'Riwayat aktivitas dan perubahan',
                  value: _shareTimeline,
                  onChanged: (value) {
                    setState(() => _shareTimeline = value);
                  },
                ),
                const SizedBox(height: 12),
                _ConsentSwitch(
                  icon: Icons.folder_shared_rounded,
                  title: 'Health Record',
                  subtitle: 'Diagnosis & catatan klinis',
                  value: _shareHealthRecord,
                  onChanged: (value) {
                    setState(() => _shareHealthRecord = value);
                  },
                ),
                const SizedBox(height: 12),
                _ConsentSwitch(
                  icon: Icons.flag_rounded,
                  title: 'Goals & Habits',
                  subtitle: 'Target harian & streak',
                  value: _shareGoals,
                  onChanged: (value) {
                    setState(() => _shareGoals = value);
                  },
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _isLoading ? null : _updateConsent,
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Simpan Pengaturan'),
                ),
                const SizedBox(height: 16),
                SoftCard(
                  color: MalvaColors.seed.withValues(alpha: 0.08),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tentang Consent Management',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Anda memiliki kendali penuh atas data yang dibagikan dengan profesional. '
                        'Saat Anda menonaktifkan suatu kategori, profesional tidak akan dapat melihat data tersebut '
                        'sampai Anda mengaktifkannya kembali.',
                        style: TextStyle(color: Colors.black54),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Perubahan akan berlaku segera setelah disimpan.',
                        style: TextStyle(color: Colors.black54),
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

class _ConsentSwitch extends StatelessWidget {
  const _ConsentSwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: value
                ? MalvaColors.seed.withValues(alpha: 0.12)
                : Colors.black.withValues(alpha: 0.06),
            child: Icon(icon, color: value ? MalvaColors.seed : Colors.black38),
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
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
