import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers/providers.dart';
import '../theme.dart';
import 'auth_widgets.dart';

/// Halaman login/daftar KHUSUS PASIEN.
/// Email + nama + password. Tidak ada field profesional di sini.
class PatientLoginScreen extends ConsumerStatefulWidget {
  const PatientLoginScreen({
    super.key,
    required this.onAuthenticated,
    this.onBackToRole,
  });

  final ValueChanged<AuthSession> onAuthenticated;
  final VoidCallback? onBackToRole;

  @override
  ConsumerState<PatientLoginScreen> createState() => _PatientLoginScreenState();
}

class _PatientLoginScreenState extends ConsumerState<PatientLoginScreen> {
  final _emailController = TextEditingController(text: '');
  final _nameController = TextEditingController(text: '');
  final _passwordController = TextEditingController(text: '');
  final _confirmPasswordController = TextEditingController(text: '');
  AuthMode _mode = AuthMode.login;
  bool _isSubmitting = false;
  bool _rememberMe = false;

  @override
  void dispose() {
    _emailController.dispose();
    _nameController.dispose();
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
          ? await store.loginPatientOnline(
              email: _emailController.text,
              password: _passwordController.text,
            )
          : await store.registerPatientOnline(
              email: _emailController.text,
              password: _passwordController.text,
              displayName: _nameController.text,
            );
      if (!mounted) return;
      widget.onAuthenticated(session);
    } on AuthFailure catch (error) {
      if (!mounted) return;
      showAuthError(context, error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _validateFields() {
    final email = _emailController.text.trim();
    final validEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
    if (!validEmail) {
      throw const AuthFailure('Format email pasien tidak valid.');
    }
    if (!_isLogin && _nameController.text.trim().isEmpty) {
      throw const AuthFailure('Nama pasien harus diisi.');
    }
    if (_passwordController.text.length < 8) {
      throw const AuthFailure('Password minimal 8 karakter.');
    }
    if (!_isLogin &&
        _passwordController.text != _confirmPasswordController.text) {
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
                    const Icon(Icons.person_rounded, color: MalvaColors.seed),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isLogin
                            ? 'Masuk sebagai Pasien'
                            : 'Daftar sebagai Pasien',
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
                      labelText: 'Nama pasien',
                      prefixIcon: Icon(Icons.badge_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Email pasien',
                    prefixIcon: Icon(Icons.email_rounded),
                  ),
                ),
                const SizedBox(height: 10),
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
                GoogleSignInButton(
                  isLogin: _isLogin,
                  onPressed: () => showGoogleComingSoon(context),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
