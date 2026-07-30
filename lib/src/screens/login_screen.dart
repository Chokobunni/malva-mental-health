import 'package:flutter/material.dart';

import '../models.dart';
import '../store/malva_store.dart';
import '../theme.dart';

enum _AuthMode { login, register }

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    super.key,
    required this.store,
    required this.onAuthenticated,
  });

  final MalvaStore store;
  final ValueChanged<AuthSession> onAuthenticated;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController(text: 'pasien@malva.app');
  final _patientNameController = TextEditingController(text: 'Emelie R.');
  final _professionalIdController =
      TextEditingController(text: '1234567890123456');
  final _professionalNameController =
      TextEditingController(text: 'dr. Hafid Algistian, Sp.KJ.');
  final _passwordController = TextEditingController(text: 'Malva1234');
  final _confirmPasswordController = TextEditingController(text: 'Malva1234');
  UserRole _role = UserRole.patient;
  _AuthMode _mode = _AuthMode.login;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _emailController.dispose();
    _patientNameController.dispose();
    _professionalIdController.dispose();
    _professionalNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

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
                            const Icon(Icons.local_florist_rounded,
                                color: Colors.white, size: 76),
                            const SizedBox(height: 18),
                            Text(
                              'Malva',
                              style: Theme.of(context)
                                  .textTheme
                                  .displayMedium
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Mental health check-in untuk pasien dan profesional',
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.9),
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 36),
                            _LoginCard(
                              mode: _mode,
                              role: _role,
                              emailController: _emailController,
                              patientNameController: _patientNameController,
                              professionalIdController:
                                  _professionalIdController,
                              professionalNameController:
                                  _professionalNameController,
                              passwordController: _passwordController,
                              confirmPasswordController:
                                  _confirmPasswordController,
                              onRoleChanged: _setRole,
                              onModeChanged: (value) =>
                                  setState(() => _mode = value),
                              onSubmit: _submit,
                              isSubmitting: _isSubmitting,
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

  void _setRole(UserRole value) {
    setState(() {
      _role = value;
      _passwordController.text =
          _role == UserRole.patient ? 'Malva1234' : 'Dokter1234';
      _confirmPasswordController.text = _passwordController.text;
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting) return;
    try {
      setState(() => _isSubmitting = true);
      _validateFields();
      final session = await switch ((_role, _mode)) {
        (UserRole.patient, _AuthMode.login) => widget.store.loginPatientOnline(
            email: _emailController.text,
            password: _passwordController.text,
          ),
        (UserRole.patient, _AuthMode.register) =>
          widget.store.registerPatientOnline(
            email: _emailController.text,
            password: _passwordController.text,
            displayName: _patientNameController.text,
          ),
        (UserRole.professional, _AuthMode.login) =>
          widget.store.loginProfessionalOnline(
            professionalId: _professionalIdController.text,
            password: _passwordController.text,
          ),
        (UserRole.professional, _AuthMode.register) =>
          widget.store.registerProfessionalOnline(
            professionalId: _professionalIdController.text,
            password: _passwordController.text,
            displayName: _professionalNameController.text,
          ),
      };
      if (!mounted) return;
      widget.onAuthenticated(session);
    } on AuthFailure catch (error) {
      if (!mounted) return;
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  void _validateFields() {
    final password = _passwordController.text;
    if (_role == UserRole.patient) {
      final email = _emailController.text.trim();
      final validEmail = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);
      if (!validEmail) {
        throw const AuthFailure('Format email pasien tidak valid.');
      }
    } else {
      final professionalId = _professionalIdController.text.trim();
      final validProfessionalId = RegExp(r'^\d{16}$').hasMatch(professionalId);
      if (!validProfessionalId) {
        throw const AuthFailure('ID profesi harus berisi tepat 16 angka.');
      }
    }
    if (password.length < 8) {
      throw const AuthFailure('Password minimal 8 karakter.');
    }
    if (_mode == _AuthMode.register &&
        password != _confirmPasswordController.text) {
      throw const AuthFailure('Konfirmasi password tidak sama.');
    }
  }

  void _showError(String message) {
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
}

class _LoginCard extends StatelessWidget {
  const _LoginCard({
    required this.mode,
    required this.role,
    required this.emailController,
    required this.patientNameController,
    required this.professionalIdController,
    required this.professionalNameController,
    required this.passwordController,
    required this.confirmPasswordController,
    required this.onRoleChanged,
    required this.onModeChanged,
    required this.onSubmit,
    required this.isSubmitting,
  });

  final _AuthMode mode;
  final UserRole role;
  final TextEditingController emailController;
  final TextEditingController patientNameController;
  final TextEditingController professionalIdController;
  final TextEditingController professionalNameController;
  final TextEditingController passwordController;
  final TextEditingController confirmPasswordController;
  final ValueChanged<UserRole> onRoleChanged;
  final ValueChanged<_AuthMode> onModeChanged;
  final VoidCallback onSubmit;
  final bool isSubmitting;

  @override
  Widget build(BuildContext context) {
    final isLogin = mode == _AuthMode.login;
    final isPatient = role == UserRole.patient;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isLogin ? 'Masuk ke Malva' : 'Daftar Akun',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            _ToggleGroup<UserRole>(
              value: role,
              options: const [
                _ToggleOption(
                    value: UserRole.patient,
                    icon: Icons.person_rounded,
                    label: 'Pasien'),
                _ToggleOption(
                  value: UserRole.professional,
                  icon: Icons.medical_information_rounded,
                  label: 'Profesional',
                ),
              ],
              onChanged: onRoleChanged,
            ),
            const SizedBox(height: 12),
            _ToggleGroup<_AuthMode>(
              value: mode,
              options: const [
                _ToggleOption(
                    value: _AuthMode.login,
                    icon: Icons.login_rounded,
                    label: 'Masuk'),
                _ToggleOption(
                    value: _AuthMode.register,
                    icon: Icons.person_add_rounded,
                    label: 'Daftar'),
              ],
              onChanged: onModeChanged,
            ),
            const SizedBox(height: 14),
            if (isPatient) ...[
              if (!isLogin) ...[
                TextField(
                  controller: patientNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nama pasien',
                    prefixIcon: Icon(Icons.badge_rounded),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(
                  labelText: 'Email pasien',
                  prefixIcon: Icon(Icons.email_rounded),
                ),
              ),
            ] else ...[
              if (!isLogin) ...[
                TextField(
                  controller: professionalNameController,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Nama profesional',
                    prefixIcon: Icon(Icons.badge_rounded),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              TextField(
                controller: professionalIdController,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                maxLength: MalvaStore.professionalIdDigitCount,
                decoration: const InputDecoration(
                  labelText: 'ID profesi',
                  prefixIcon: Icon(Icons.verified_user_rounded),
                  counterText: '',
                ),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: passwordController,
              obscureText: true,
              textInputAction:
                  isLogin ? TextInputAction.done : TextInputAction.next,
              onSubmitted: (_) {
                if (isLogin) onSubmit();
              },
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock_rounded),
              ),
            ),
            if (!isLogin) ...[
              const SizedBox(height: 10),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onSubmit(),
                decoration: const InputDecoration(
                  labelText: 'Konfirmasi password',
                  prefixIcon: Icon(Icons.lock_reset_rounded),
                ),
              ),
            ],
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: isSubmitting ? null : onSubmit,
              icon: isSubmitting
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      isLogin ? Icons.login_rounded : Icons.person_add_rounded),
              label: Text(isSubmitting
                  ? 'Menghubungkan...'
                  : isLogin
                      ? 'Masuk'
                      : 'Daftar'),
            ),
            const SizedBox(height: 14),
            Text(
              isPatient
                  ? 'Demo pasien: pasien@malva.app / Malva1234'
                  : 'Demo profesional: 1234567890123456 / Dokter1234',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.black54),
            ),
          ],
        ),
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
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MalvaColors.seed.withValues(alpha: 0.28)),
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onChanged(option.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding:
                      const EdgeInsets.symmetric(vertical: 11, horizontal: 8),
                  decoration: BoxDecoration(
                    color: value == option.value
                        ? Colors.white
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: value == option.value
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        option.icon,
                        size: 18,
                        color: value == option.value
                            ? MalvaColors.plum
                            : Colors.black54,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          option.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: value == option.value
                                ? MalvaColors.plum
                                : Colors.black54,
                            fontWeight: FontWeight.w900,
                          ),
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
