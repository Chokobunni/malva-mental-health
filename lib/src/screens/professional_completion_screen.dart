import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../services/google_auth_service.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';
import '../widgets/password_field.dart';

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

  /// Password akun LAMA. Hanya ditampilkan bila server menyatakan nomor STR
  /// sudah terdaftar di akun lain (`str_terdaftar_perlu_verifikasi`) — bukti
  /// kepemilikan sebelum akun Google ditautkan. Jalur normal tidak pernah
  /// melihat kolom ini.
  final _existingPasswordController = TextEditingController();
  bool _needsExistingPassword = false;
  String? _existingPasswordError;

  @override
  void initState() {
    super.initState();
    // Pre-fill nama dari sesi Google.
    _nameController = TextEditingController(text: widget.session.displayName);
    // Hapus galat inline kolom password akun lama begitu pengguna mengetik.
    _existingPasswordController.addListener(_clearExistingPasswordError);
  }

  /// Menghapus galat inline pada kolom password akun lama saat pengguna mulai
  /// memperbaiki isiannya.
  void _clearExistingPasswordError() {
    if (!mounted) return;
    if (_existingPasswordError != null &&
        _existingPasswordController.text.isNotEmpty) {
      setState(() => _existingPasswordError = null);
    }
  }

  @override
  void dispose() {
    _existingPasswordController.removeListener(_clearExistingPasswordError);
    _nameController.dispose();
    _strController.dispose();
    _sipController.dispose();
    _existingPasswordController.dispose();
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
    // Setelah server meminta bukti kepemilikan, password akun lama wajib diisi.
    if (_needsExistingPassword && _existingPasswordController.text.isEmpty) {
      setState(() => _existingPasswordError =
          'Password akun lama wajib diisi untuk menautkan akun Google ini.');
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
        existingPassword: _existingPasswordController.text,
      );
      if (!mounted) return;
      widget.onCompleted(updatedSession);
    } on MalvaApiException catch (error) {
      if (!mounted) return;
      if (error.code == professionalMergeVerificationRequiredCode) {
        // Nomor STR milik akun lain. Tampilkan kolom password akun lama
        // TANPA menghapus isian STR/SIP/spesialisasi/nama yang sudah diketik.
        // Bila password sudah pernah diisi (berarti server menolaknya), beri
        // galat inline yang spesifik agar pengguna tahu passwordnya salah.
        final passwordRejected = _needsExistingPassword &&
            _existingPasswordController.text.isNotEmpty;
        setState(() {
          _needsExistingPassword = true;
          _existingPasswordError =
              passwordRejected ? 'Password akun lama salah.' : null;
        });
        _showSnack(
          passwordRejected
              ? 'Password akun lama salah. Periksa lalu coba lagi.'
              : 'Nomor STR ini sudah terdaftar pada akun profesional lain. '
                  'Masukkan password akun lama Anda untuk menautkan akun '
                  'Google ini.',
        );
        return;
      }
      if (error.code == professionalMergeTooManyAttemptsCode) {
        // Lockout per-akun aktif (terlalu banyak percobaan verifikasi).
        // Tampilkan pesan server APA ADANYA dan jangan sentuh form: jangan buka
        // kolom password lagi dan jangan reset isian yang sudah diketik.
        // SENGAJA terpisah dari cabang 409 di atas.
        _showSnack(error.message);
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
            // Bukti kepemilikan: hanya muncul bila nomor STR sudah terdaftar
            // di akun lain. Jalur normal (profesional baru / email sama) tidak
            // pernah menampilkan kolom ini.
            if (_needsExistingPassword) ...[
              const SizedBox(height: 14),
              SoftCard(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.lock_person_rounded,
                        color: MalvaColors.amber, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Nomor STR ini sudah terdaftar pada akun profesional '
                        'lain. Masukkan password akun lama Anda untuk '
                        'menautkan akun Google ini — isian lain tidak hilang.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              PasswordField(
                controller: _existingPasswordController,
                labelText: 'Password akun lama',
                helperText:
                    'Diperlukan untuk menautkan akun Google ke akun profesional '
                    'yang sudah terdaftar',
                prefixIcon: const Icon(Icons.lock_rounded),
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                errorText: _existingPasswordError,
              ),
            ],
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
