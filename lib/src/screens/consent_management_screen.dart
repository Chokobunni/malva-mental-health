import 'dart:async';

import 'package:flutter/material.dart';

import '../models.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';

class ConsentManagementScreen extends StatefulWidget {
  const ConsentManagementScreen({
    super.key,
    this.apiClient,
    this.session,
  });

  final MalvaApiClient? apiClient;
  final AuthSession? session;

  @override
  State<ConsentManagementScreen> createState() =>
      _ConsentManagementScreenState();
}

class _ConsentManagementScreenState extends State<ConsentManagementScreen> {
  bool _shareScreenings = true;
  bool _shareMoodDiary = true;
  bool _shareMedications = true;
  bool _shareTimeline = true;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConsent();
  }

  Future<void> _loadConsent() async {
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final consent = await apiClient.getPrivacyConsent(
        accessToken: accessToken,
        professionalId: widget.session?.identifier ?? '',
      );
      if (mounted) {
        setState(() {
          _shareScreenings = consent.shareScreenings;
          _shareMoodDiary = consent.shareMoodDiary;
          _shareMedications = consent.shareMedications;
          _shareTimeline = consent.shareTimeline;
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
    final apiClient = widget.apiClient;
    final accessToken = widget.session?.accessToken;
    if (apiClient == null || accessToken == null || accessToken.isEmpty) {
      return;
    }

    setState(() => _isLoading = true);

    try {
      await apiClient.updatePrivacyConsent(
        accessToken: accessToken,
        professionalId: widget.session?.identifier ?? '',
        shareScreenings: _shareScreenings,
        shareMoodDiary: _shareMoodDiary,
        shareMedications: _shareMedications,
        shareTimeline: _shareTimeline,
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
            leading: Icon(Icons.security_rounded,
                color: Colors.white, size: 34),
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
                  'Pilih data yang ingin Anda bagikan dengan profesional:',
                  style: TextStyle(fontWeight: FontWeight.w700),
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
