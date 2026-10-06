import 'package:flutter/material.dart';

import '../models.dart';
import '../services/malva_api_client.dart';
import '../theme.dart';
import '../widgets/malva_components.dart';

enum AuthMode { login, register }

/// Validasi password mode daftar, SELARAS dengan policy server
/// (backend/internal/security/password_policy.go).
/// Mengembalikan null bila valid, pesan Bahasa Indonesia bila tidak.
String? validatePasswordForRegister(String password) {
  if (password.length < 8) return 'Password minimal 8 karakter.';
  if (!RegExp(r'[A-Z]').hasMatch(password)) {
    return 'Password harus mengandung minimal 1 huruf besar (A-Z).';
  }
  if (!RegExp(r'[a-z]').hasMatch(password)) {
    return 'Password harus mengandung minimal 1 huruf kecil (a-z).';
  }
  if (!RegExp(r'[0-9]').hasMatch(password)) {
    return 'Password harus mengandung minimal 1 angka (0-9).';
  }
  if (!RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
    return 'Password harus mengandung minimal 1 simbol (mis. #?!@\$).';
  }
  return null;
}

/// Petunjuk syarat password yang ditampilkan di bawah field.
const passwordRequirementHint =
    'Min. 8 karakter: huruf besar + kecil + angka + simbol.';

/// Menampilkan error apapun dari proses autentikasi sebagai dialog ramah.
void showAuthFailure(BuildContext context, Object error) {
  if (error is AuthFailure) {
    showAuthError(context, error.message);
    return;
  }
  if (error is MalvaApiException) {
    showAuthError(context, error.message);
    return;
  }
  showAuthError(context, 'Terjadi kesalahan tak terduga. Silakan coba lagi.');
}

/// Halaman gerbang peran — langkah pertama setelah splash.
/// Memisahkan alur login pasien dan profesional ke halaman berbeda.
class RoleGateScreen extends StatelessWidget {
  const RoleGateScreen({
    super.key,
    required this.onSelectPatient,
    required this.onSelectProfessional,
  });

  final VoidCallback onSelectPatient;
  final VoidCallback onSelectProfessional;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF3F205B), Color(0xFFB75ECB), Color(0xFFEFA0EC)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.local_florist_rounded,
                        color: Colors.white, size: 76),
                    const SizedBox(height: 18),
                    Text(
                      'Malva',
                      style:
                          Theme.of(context).textTheme.displayMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Are you',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'a Patient or a Mental Health Professional?',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: onSelectPatient,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: MalvaColors.seed,
                        ),
                        icon: const Icon(Icons.person_rounded),
                        label: const Text('Patient'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: onSelectProfessional,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white, width: 2),
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.medical_information_rounded),
                        label: const Text(
                          'Professional',
                          style: TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'By continuing, you agree to our Terms & Privacy Policy',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Kerangka latar gradien yang dipakai kedua halaman login.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.children,
    this.onBack,
  });

  final List<Widget> children;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF3F205B), Color(0xFFB75ECB), Color(0xFFEFA0EC)],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                if (onBack != null)
                                  IconButton(
                                    tooltip: 'Kembali pilih peran',
                                    onPressed: onBack,
                                    icon: const Icon(
                                      Icons.arrow_back_rounded,
                                      color: Colors.white,
                                    ),
                                  ),
                                const Icon(Icons.local_florist_rounded,
                                    color: Colors.white, size: 40),
                                const SizedBox(width: 10),
                                Text(
                                  'Malva',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                      ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 24),
                            ...children,
                            const SizedBox(height: 14),
                            Text(
                              'By continuing, you agree to our Terms & Privacy Policy',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.85),
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Toggle Masuk/Daftar bersama.
class AuthModeToggle extends StatelessWidget {
  const AuthModeToggle({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final AuthMode mode;
  final ValueChanged<AuthMode> onChanged;

  bool get isLogin => mode == AuthMode.login;

  @override
  Widget build(BuildContext context) {
    return _ToggleGroup<AuthMode>(
      value: mode,
      options: const [
        _ToggleOption(
            value: AuthMode.login, icon: Icons.login_rounded, label: 'Masuk'),
        _ToggleOption(
            value: AuthMode.register,
            icon: Icons.person_add_rounded,
            label: 'Daftar'),
      ],
      onChanged: onChanged,
    );
  }
}

/// Baris Remember me + Forgot Password.
class RememberForgotRow extends StatelessWidget {
  const RememberForgotRow({
    super.key,
    required this.rememberMe,
    required this.onRememberMeChanged,
    required this.onForgotPassword,
  });

  final bool rememberMe;
  final ValueChanged<bool> onRememberMeChanged;
  final VoidCallback onForgotPassword;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: rememberMe,
                onChanged: (v) => onRememberMeChanged(v ?? false),
              ),
              const Flexible(
                child: Text('Remember me',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: onForgotPassword,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
          ),
          child: const Text(
            'Forgot Password?',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

/// Tombol Google SSO (stub jujur sampai kredensial tersedia).
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({
    super.key,
    required this.isLogin,
    required this.onPressed,
  });

  final bool isLogin;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 6),
        const Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 10),
              child: Text('Or', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
            Expanded(child: Divider()),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          onPressed: onPressed,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          icon: const Icon(Icons.g_mobiledata_rounded, size: 28),
          label: Text(
            isLogin ? 'Continue with Google' : 'Sign up with Google',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
      ],
    );
  }
}

/// Dialog lupa password bersama.
Future<void> showForgotPasswordDialog(BuildContext context) async {
  final controller = TextEditingController();
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Forgot Password?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Masukkan email akunmu. Kami akan mengirim tautan reset password.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.email_rounded),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: compactFilledButtonStyle,
          child: const Text('Kirim'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (result == true && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content:
            Text('Tautan reset dikirim jika email terdaftar. Cek inbox kamu.'),
      ),
    );
  }
}

/// Dialog error autentikasi bersama.
void showAuthError(BuildContext context, String message) {
  showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.error_rounded, color: MalvaColors.danger),
      title: const Text('Autentikasi gagal'),
      content: Text(message),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup')),
      ],
    ),
  );
}

/// Toggle generik (dipakai mode Masuk/Daftar).
class _ToggleGroup<T> extends StatelessWidget {
  const _ToggleGroup({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<_ToggleOption<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: MalvaColors.seed.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(option.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: value == option.value
                        ? MalvaColors.seed
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        option.icon,
                        size: 18,
                        color: value == option.value
                            ? Colors.white
                            : Colors.black54,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        option.label,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: value == option.value
                              ? Colors.white
                              : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ToggleOption<T> {
  const _ToggleOption({
    required this.value,
    required this.icon,
    required this.label,
  });

  final T value;
  final IconData icon;
  final String label;
}
