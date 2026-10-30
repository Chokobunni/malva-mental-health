import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/google_auth_service.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';

/// Kode mesin server saat nomor STR/SIP sudah dimiliki akun profesional lain.
/// Sama dengan `professionalIdentifierTakenCode` di backend
/// (backend/internal/server/professional_identifier_guard.go).
const _professionalIdentifierTakenCode = 'str_sip_sudah_terdaftar';

/// Form pelengkapan data profesional baru yang login via Google.
/// Ditampilkan saat `needs_completion` = true (STR/SIP belum ada).
///
/// Form ini WAJIB diselesaikan: pengguna tidak bisa menekan tombol back dan
/// keluar tanpa sesi. Menekan back memunculkan dialog konfirmasi; memilih
/// "Batalkan login" akan mengakhiri alur Google login dan kembali ke halaman
/// login tanpa sesi aktif (bug 28 Okt 2026: profesional bisa lolos tanpa
/// identitas medis).
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

  // Galat validasi inline (ditampilkan di bawah masing-masing kolom).
  String? _nameError;
  String? _strError;
  String? _sipError;

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

  /// Memvalidasi seluruh kolom wajib. Mengembalikan `true` bila lolos.
  /// Pesan galat dipasang inline (bukan hanya SnackBar) agar pengguna
  /// melihat kolom mana yang kurang.
  bool _validate() {
    final name = _nameController.text.trim();
    final str = _strController.text.trim();
    final sip = _sipController.text.trim();
    setState(() {
      _nameError = name.isEmpty ? 'Nama lengkap wajib diisi.' : null;
      _strError = str.isEmpty ? 'Nomor STR wajib diisi.' : null;
      _sipError = sip.isEmpty ? 'Nomor SIP wajib diisi.' : null;
    });
    return _nameError == null && _strError == null && _sipError == null;
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    if (!_validate()) return;

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
    } on MalvaApiException catch (error) {
      if (!mounted) return;
      if (error.code == _professionalIdentifierTakenCode) {
        // Nomor STR/SIP sudah dimiliki akun profesional lain. Tandai kedua
        // field inline agar pengguna tahu harus memakai nomor lain yang sah,
        // dan jelaskan aturannya lewat SnackBar.
        const message = 'Nomor STR/SIP ini sudah terdaftar pada akun '
            'profesional lain. Satu STR/SIP hanya boleh untuk satu akun — '
            'gunakan nomor lain yang sah, atau masuk ke akun lama lalu '
            'hubungkan Gmail di menu Akun Google.';
        setState(() {
          _strError = message;
          _sipError = message;
        });
        _showSnack(message);
        return;
      }
      _showSnack(error.message);
    } catch (error) {
      if (!mounted) return;
      _showSnack(error.toString());
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  /// Menampilkan pesan singkat di bawah layar.
  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  /// Dialog konfirmasi saat pengguna mencoba keluar tanpa melengkapi form.
  Future<bool> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.warning_amber_rounded, color: MalvaColors.amber),
        title: const Text('Identitas medis wajib dilengkapi'),
        content: const Text(
          'Identitas medis wajib dilengkapi untuk melanjutkan. '
          'Keluar akan membatalkan login.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Lanjutkan mengisi'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: MalvaColors.danger),
            child: const Text('Batalkan login'),
          ),
        ],
      ),
    );
    return leave == true;
  }

  /// Membatalkan alur login: keluar dari akun Google lalu kembali ke halaman
  /// login TANPA sesi aktif.
  Future<void> _cancelLogin() async {
    if (!await _confirmLeave()) return;
    if (!mounted) return;
    await GoogleAuthService.signOut();
    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Form tidak boleh dilewati dengan tombol back.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        unawaited(_cancelLogin());
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Lengkapi Profil'),
          backgroundColor: MalvaColors.seed,
          foregroundColor: Colors.white,
          // Tombol back eksplisit agar perilakunya sama dengan gesture back.
          leading: IconButton(
            tooltip: 'Batalkan login',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => unawaited(_cancelLogin()),
          ),
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
                    'mengaktifkan akun profesional. Data ini wajib diisi — '
                    'tanpa STR & SIP, akun belum bisa diverifikasi admin.',
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
              onChanged: (_) {
                if (_nameError != null) setState(() => _nameError = null);
              },
              decoration: InputDecoration(
                labelText: 'Nama lengkap (dengan gelar)',
                hintText: 'dr. Ayu Pratama, Sp.KJ',
                prefixIcon: const Icon(Icons.badge_rounded),
                errorText: _nameError,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _strController,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_strError != null) setState(() => _strError = null);
              },
              decoration: InputDecoration(
                labelText: 'Nomor STR',
                hintText: 'STR-1234567890',
                prefixIcon: const Icon(Icons.verified_user_rounded),
                errorText: _strError,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _sipController,
              textInputAction: TextInputAction.next,
              onChanged: (_) {
                if (_sipError != null) setState(() => _sipError = null);
              },
              decoration: InputDecoration(
                labelText: 'Nomor SIP',
                hintText: 'SIP-1234567890',
                prefixIcon: const Icon(Icons.assignment_ind_rounded),
                errorText: _sipError,
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
              label:
                  Text(_isSubmitting ? 'Menyimpan...' : 'Simpan & Lanjutkan'),
            ),
          ],
        ),
      ),
    );
  }
}
