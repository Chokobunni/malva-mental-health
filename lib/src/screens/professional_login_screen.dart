import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../theme.dart';
import 'auth_widgets.dart';

/// Halaman login/daftar KHUSUS PROFESIONAL.
/// Login: nomor STR / SIP / kode profesi (16 digit) + password.
/// Daftar: nama, STR, SIP, spesialisasi, email, password (+ Google opsional).
class ProfessionalLoginScreen extends ConsumerStatefulWidget {
  const ProfessionalLoginScreen({
    super.key,
    required this.onAuthenticated,
    this.onBackToRole,
  });

  final ValueChanged<AuthSession> onAuthenticated;
  final VoidCallback? onBackToRole;

  @override
  ConsumerState<ProfessionalLoginScreen> createState() =>
      _ProfessionalLoginScreenState();
}

class _ProfessionalLoginScreenState
    extends ConsumerState<ProfessionalLoginScreen> {
  final _idController = TextEditingController(text: '');
  final _nameController = TextEditingController(text: '');
  final _strController = TextEditingController(text: '');
  final _sipController = TextEditingController(text: '');
  final _emailController = TextEditingController(text: '');
  final _phoneController = TextEditingController(text: '');
  final _passwordController = TextEditingController(text: '');
  final _confirmPasswordController = TextEditingController(text: '');
  AuthMode _mode = AuthMode.login;
  String _specialization = 'Sp.KJ';
  bool _isSubmitting = false;
  bool _rememberMe = false;

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _strController.dispose();
    _sipController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  bool get _isLogin => _mode == AuthMode.login;

  Future<void> _submit() async {
    if (_isSubmitting) return;
    try {
      setState(() => _isSubmitting = true);
      _validateFields();
      final store = ref.read(malvaStoreProvider.notifier);
      final session = _isLogin
          ? await store.loginProfessionalOnline(
              professionalId: _idController.text,
              password: _passwordController.text,
            )
          : await store.registerProfessionalOnline(
              professionalId: _strController.text,
              password: _passwordController.text,
              displayName: _nameController.text,
              strNumber: _strController.text,
              sipNumber: _sipController.text,
              specialization: _specialization,
              email: _emailController.text,
              phone: _phoneController.text,
            );
      if (!mounted) return;
      widget.onAuthenticated(session);
    } catch (error) {
      if (!mounted) return;
      showAuthFailure(context, error);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _validateFields() {
    if (_isLogin) {
      final identifier = _idController.text.trim();
      if (identifier.isEmpty) {
        throw const AuthFailure('Nomor STR/SIP atau kode profesi harus diisi.');
      }
      if (_passwordController.text.isEmpty) {
        throw const AuthFailure('Password harus diisi.');
      }
      return;
    }
    // Registrasi: STR & SIP wajib (sesuai ketentuan KKI).
    if (_nameController.text.trim().isEmpty) {
      throw const AuthFailure('Nama profesional harus diisi.');
    }
    if (_strController.text.trim().isEmpty) {
      throw const AuthFailure('Nomor STR wajib diisi.');
    }
    if (_sipController.text.trim().isEmpty) {
      throw const AuthFailure('Nomor SIP wajib diisi.');
    }
    final email = _emailController.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      throw const AuthFailure('Format email profesional tidak valid.');
    }
    final passwordError = validatePasswordForRegister(_passwordController.text);
    if (passwordError != null) {
      throw AuthFailure(passwordError);
    }
    if (_passwordController.text != _confirmPasswordController.text) {
      throw const AuthFailure('Konfirmasi password tidak sama.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      onBack: widget.onBackToRole,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.medical_information_rounded,
                        color: MalvaColors.seed),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isLogin
                            ? 'Masuk sebagai Profesional'
                            : 'Daftar sebagai Profesional',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                AuthModeToggle(
                  mode: _mode,
                  onChanged: (value) => setState(() => _mode = value),
                ),
                const SizedBox(height: 14),
                if (!_isLogin) ...[
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
                  const SizedBox(height: 10),
                  TextField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Email profesional',
                      hintText: 'ayu@malva.web.id',
                      prefixIcon: Icon(Icons.email_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nomor telepon (opsional)',
                      hintText: '08xxxxxxxxxx',
                      prefixIcon: Icon(Icons.phone_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                if (_isLogin) ...[
                  TextField(
                    controller: _idController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Nomor STR / SIP / ID profesi',
                      hintText: 'STR-1234567890',
                      prefixIcon: Icon(Icons.verified_user_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: _passwordController,
                  obscureText: true,
                  textInputAction:
                      _isLogin ? TextInputAction.done : TextInputAction.next,
                  onSubmitted: (_) {
                    if (_isLogin) _submit();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_rounded),
                  ),
                ),
                if (!_isLogin) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _submit(),
                    decoration: const InputDecoration(
                      labelText: 'Konfirmasi password',
                      prefixIcon: Icon(Icons.lock_reset_rounded),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    passwordRequirementHint,
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Kredensial STR/SIP akan diverifikasi admin sebelum profil '
                    'kamu tampil di direktori pasien.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: _isSubmitting ? null : _submit,
                  icon: _isSubmitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(_isLogin
                          ? Icons.login_rounded
                          : Icons.person_add_rounded),
                  label: Text(_isSubmitting
                      ? 'Menghubungkan...'
                      : _isLogin
                          ? 'Masuk'
                          : 'Daftar'),
                ),
                if (_isLogin) ...[
                  RememberForgotRow(
                    rememberMe: _rememberMe,
                    onRememberMeChanged: (v) => setState(() => _rememberMe = v),
                    onForgotPassword: () => showForgotPasswordDialog(context),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
