import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';

/// Form pelengkapan data profesional baru yang login via Google.
/// Ditampilkan saat `needs_completion` = true (STR/SIP belum ada).
class ProfessionalCompletionScreen extends ConsumerStatefulWidget {
  const ProfessionalCompletionScreen({
    super.key,
    required this.session,
    required this.apiClient,
    required this.onCompleted,
  });

  final AuthSession session;
  final MalvaApiClient apiClient;
  final void Function(AuthSession updatedSession) onCompleted;

  @override
  ConsumerState<ProfessionalCompletionScreen> createState() =>
      _ProfessionalCompletionScreenState();
}

class _ProfessionalCompletionScreenState
    extends ConsumerState<ProfessionalCompletionScreen> {
  late final TextEditingController _nameController;
  final _strController = TextEditingController();
  final _sipController = TextEditingController();
  String _specialization = 'Sp.KJ';
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill nama dari sesi Google.
    _nameController = TextEditingController(text: widget.session.displayName);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _strController.dispose();
    _sipController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    // Validasi field wajib.
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nama lengkap harus diisi.')),
      );
      return;
    }
    if (_strController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nomor STR wajib diisi.')),
      );
      return;
    }
    if (_sipController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nomor SIP wajib diisi.')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final accessToken = widget.session.accessToken;
      if (accessToken == null || accessToken.isEmpty) {
        throw const AuthFailure('Sesi tidak valid. Silakan login ulang.');
      }
      final store = ref.read(malvaStoreProvider.notifier);
      final updatedSession = await store.completeProfessionalOnboarding(
        accessToken: accessToken,
        strNumber: _strController.text,
        sipNumber: _sipController.text,
        specialization: _specialization,
        displayName: _nameController.text,
        currentRefreshToken: widget.session.refreshToken ?? '',
      );
      if (!mounted) return;
      widget.onCompleted(updatedSession);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(error.toString())),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lengkapi Profil'),
        backgroundColor: MalvaColors.seed,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          SoftCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded,
                    color: MalvaColors.seed, size: 28),
                const SizedBox(height: 8),
                Text(
                  'Selamat datang! Lengkapi data kredensial Anda untuk '
                  'mengaktifkan akun profesional.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: Colors.black54),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const SectionLabel('Identitas', icon: Icons.badge_rounded),
          TextField(
            controller: _nameController,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Nama lengkap (dengan gelar)',
              hintText: 'dr. Ayu Pratama, Sp.KJ',
              prefixIcon: Icon(Icons.badge_rounded),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _strController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Nomor STR',
              hintText: 'STR-1234567890',
              prefixIcon: Icon(Icons.verified_user_rounded),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _sipController,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Nomor SIP',
              hintText: 'SIP-1234567890',
              prefixIcon: Icon(Icons.assignment_ind_rounded),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _specialization,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Spesialisasi',
              prefixIcon: Icon(Icons.school_rounded),
            ),
            items: const [
              DropdownMenuItem(
                  value: 'Sp.KJ', child: Text('Sp.KJ — Psikiater')),
              DropdownMenuItem(
                  value: 'M.Psi', child: Text('M.Psi — Psikolog')),
            ],
            onChanged: (v) =>
                setState(() => _specialization = v ?? _specialization),
          ),
          const SizedBox(height: 22),
          FilledButton.icon(
            onPressed: _isSubmitting ? null : _submit,
            icon: _isSubmitting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline_rounded),
            label: Text(_isSubmitting ? 'Menyimpan...' : 'Simpan & Lanjutkan'),
          ),
        ],
      ),
    );
  }
}
