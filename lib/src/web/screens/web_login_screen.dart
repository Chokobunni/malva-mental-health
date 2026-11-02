import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models.dart';
import '../../providers/providers.dart';
import '../../theme.dart';
import '../../widgets/friendly_error.dart';
import '../web_routes.dart';
import '../web_theme.dart';
import '../widgets/web_brand_panel.dart';
import '../widgets/web_form_field.dart';

/// Mode formulir autentikasi web.
enum WebAuthMode { login, register }

/// Halaman masuk/daftar web untuk **pasien** dan **profesional**.
///
/// Logika autentikasi TIDAK diduplikasi: seluruh pemanggilan server memakai
/// metode [MalvaStoreNotifier] yang sama dengan aplikasi mobile
/// (`loginPatientOnline`, `registerPatientOnline`, `loginProfessionalOnline`,
/// `registerProfessionalOnline`), sehingga perilaku kedua klien identik.
///
/// Perbedaan dengan mobile hanya pada penyajian (tata letak dua kolom, checklist
/// password langsung, tanpa tombol Google di fase ini).
class WebLoginScreen extends ConsumerStatefulWidget {
  const WebLoginScreen({
    super.key,
    required this.onAuthenticated,
    required this.onNavigate,
    this.initialMode = WebAuthMode.login,
  });

  /// Dipanggil setelah sesi berhasil dibuat (login maupun daftar).
  final ValueChanged<AuthSession> onAuthenticated;

  /// Dipanggil saat mode berubah agar URL browser ikut menyesuaikan.
  final ValueChanged<String> onNavigate;

  /// Mode awal, diturunkan dari path URL (`/masuk` atau `/daftar`).
  final WebAuthMode initialMode;

  @override
  ConsumerState<WebLoginScreen> createState() => _WebLoginScreenState();
}

class _WebLoginScreenState extends ConsumerState<WebLoginScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _identifierController = TextEditingController();
  final TextEditingController _strController = TextEditingController();
  final TextEditingController _sipController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController =
      TextEditingController();

  UserRole _role = UserRole.patient;
  late WebAuthMode _mode = widget.initialMode;
  String _specialization = 'Sp.KJ';
  bool _submitting = false;
  String? _error;

  bool get _isLogin => _mode == WebAuthMode.login;

  bool get _isPatient => _role == UserRole.patient;

  @override
  void didUpdateWidget(WebLoginScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // URL berubah (mis. tombol back browser) → form mengikuti tanpa membuang
    // isian yang sudah diketik. Cukup ditugaskan langsung: build akan mengikuti.
    if (widget.initialMode != oldWidget.initialMode &&
        widget.initialMode != _mode) {
      _mode = widget.initialMode;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _identifierController.dispose();
    _strController.dispose();
    _sipController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _changeRole(UserRole role) {
    if (role == _role) return;
    setState(() {
      _role = role;
      _error = null;
    });
  }

  void _changeMode(WebAuthMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _error = null;
    });
    widget.onNavigate(
      mode == WebAuthMode.login ? WebRoutes.login : WebRoutes.register,
    );
  }

  void _handleFieldChanged(String _) {
    // Checklist password bergantung pada isi password & email → bangun ulang.
    if (_error != null) {
      setState(() => _error = null);
    } else {
      setState(() {});
    }
  }

  void _validateEmail(String raw, String message) {
    final email = raw.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      throw AuthFailure(message);
    }
  }

  void _validateIdentifier(String raw) {
    if (raw.trim().isEmpty) {
      throw const AuthFailure('Nomor STR / SIP harus diisi.');
    }
  }

  void _validateSixteenDigits(String raw, String label) {
    if (!RegExp(r'^\d{16}$').hasMatch(raw.trim())) {
      throw AuthFailure('$label harus 16 digit angka.');
    }
  }

  void _validatePassword(String email) {
    final error = webPasswordError(_passwordController.text, email: email);
    if (error != null) throw AuthFailure(error);
    if (_passwordController.text != _confirmPasswordController.text) {
      throw const AuthFailure('Konfirmasi password tidak sama.');
    }
  }

  /// Menjalankan autentikasi sesuai kombinasi peran + mode.
  Future<AuthSession> _performAuth() {
    final store = ref.read(malvaStoreProvider.notifier);

    if (_isPatient) {
      if (_isLogin) {
        _validateEmail(
          _emailController.text,
          'Format email pasien tidak valid.',
        );
        if (_passwordController.text.isEmpty) {
          throw const AuthFailure('Password harus diisi.');
        }
        return store.loginPatientOnline(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }
      if (_nameController.text.trim().isEmpty) {
        throw const AuthFailure('Nama lengkap harus diisi.');
      }
      _validateEmail(
        _emailController.text,
        'Format email pasien tidak valid.',
      );
      _validatePassword(_emailController.text);
      return store.registerPatientOnline(
        email: _emailController.text,
        password: _passwordController.text,
        displayName: _nameController.text.trim(),
      );
    }

    if (_isLogin) {
      _validateIdentifier(_identifierController.text);
      if (_passwordController.text.isEmpty) {
        throw const AuthFailure('Password harus diisi.');
      }
      return store.loginProfessionalOnline(
        professionalId: _identifierController.text,
        password: _passwordController.text,
      );
    }

    if (_nameController.text.trim().isEmpty) {
      throw const AuthFailure('Nama lengkap harus diisi.');
    }
    _validateSixteenDigits(_strController.text, 'Nomor STR');
    _validateSixteenDigits(_sipController.text, 'Nomor SIP');
    _validateEmail(
      _emailController.text,
      'Format email profesional tidak valid.',
    );
    _validatePassword(_emailController.text);
    return store.registerProfessionalOnline(
      professionalId: _strController.text,
      password: _passwordController.text,
      displayName: _nameController.text.trim(),
      strNumber: _strController.text,
      sipNumber: _sipController.text,
      specialization: _specialization,
      email: _emailController.text,
    );
  }

  Future<void> _submit() async {
    if (_submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final session = await _performAuth();
      if (!mounted) return;
      widget.onAuthenticated(session);
    } catch (error) {
      if (!mounted) return;
      // Tidak pernah menampilkan exception mentah: semua pesan dilewatkan
      // melalui satu sumber pesan ramah (sama seperti mobile).
      setState(() => _error = friendlyErrorMessage(error));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MalvaColors.paper,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final showBrand = constraints.maxWidth >= WebBreakpoints.splitPanel;
            final formCard = _buildFormCard(context);
            if (!showBrand) {
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: WebSpacing.gutterCompact,
                  vertical: WebSpacing.section,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 480),
                    child: formCard,
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: <Widget>[
                  const Expanded(flex: 11, child: WebBrandPanel()),
                  const SizedBox(width: 32),
                  Expanded(
                    flex: 10,
                    child: SingleChildScrollView(
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 520),
                          child: formCard,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildFormCard(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFEDE6F1)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: <Color>[MalvaColors.plum, MalvaColors.orchid],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.spa_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'Malva',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: MalvaColors.plum,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text(
            _isLogin ? 'Masuk ke akun Anda' : 'Buat akun Malva',
            style: textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            _isLogin
                ? 'Gunakan akun yang sudah terdaftar untuk melanjutkan.'
                : 'Isi data di bawah ini. Butuh waktu kurang dari dua menit.',
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: 20),
          _WebSegmentedToggle<UserRole>(
            selected: _role,
            enabled: !_submitting,
            onChanged: _changeRole,
            options: const <_WebSegmentOption<UserRole>>[
              _WebSegmentOption<UserRole>(
                value: UserRole.patient,
                label: 'Pasien',
                key: Key('web-role-patient'),
              ),
              _WebSegmentOption<UserRole>(
                value: UserRole.professional,
                label: 'Profesional',
                key: Key('web-role-professional'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _WebSegmentedToggle<WebAuthMode>(
            selected: _mode,
            enabled: !_submitting,
            onChanged: _changeMode,
            options: const <_WebSegmentOption<WebAuthMode>>[
              _WebSegmentOption<WebAuthMode>(
                value: WebAuthMode.login,
                label: 'Masuk',
                key: Key('web-mode-login'),
              ),
              _WebSegmentOption<WebAuthMode>(
                value: WebAuthMode.register,
                label: 'Daftar',
                key: Key('web-mode-register'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ..._buildFields(),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 14),
            _ErrorBanner(message: _error!),
          ],
          const SizedBox(height: 20),
          _buildSubmitButton(),
          const SizedBox(height: 14),
          _buildModeFooter(context),
        ],
      ),
    );
  }

  List<Widget> _buildFields() {
    final fields = <Widget>[];
    void gap() => fields.add(const SizedBox(height: 12));

    if (_isPatient) {
      if (!_isLogin) {
        fields.add(
          WebFormField(
            key: const Key('web-field-name'),
            controller: _nameController,
            label: 'Nama lengkap',
            icon: Icons.badge_outlined,
            textInputAction: TextInputAction.next,
            textCapitalization: TextCapitalization.words,
            enabled: !_submitting,
            autofillHints: const <String>[AutofillHints.name],
            onChanged: _handleFieldChanged,
          ),
        );
        gap();
      }
      fields.add(
        WebFormField(
          key: const Key('web-field-email'),
          controller: _emailController,
          label: 'Email',
          hint: 'nama@contoh.com',
          icon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          enabled: !_submitting,
          autofillHints: const <String>[AutofillHints.email],
          onChanged: _handleFieldChanged,
        ),
      );
      gap();
      fields.add(
        WebPasswordField(
          key: const Key('web-field-password'),
          controller: _passwordController,
          label: 'Password',
          enabled: !_submitting,
          textInputAction:
              _isLogin ? TextInputAction.done : TextInputAction.next,
          autofillHints: <String>[
            _isLogin ? AutofillHints.password : AutofillHints.newPassword,
          ],
          onChanged: _handleFieldChanged,
          onSubmitted: _isLogin ? (_) => _submit() : null,
        ),
      );
      if (!_isLogin) {
        gap();
        fields.add(
          WebPasswordChecklist(
            password: _passwordController.text,
            email: _emailController.text,
          ),
        );
        gap();
        fields.add(
          WebPasswordField(
            key: const Key('web-field-confirm'),
            controller: _confirmPasswordController,
            label: 'Konfirmasi password',
            icon: Icons.lock_reset_outlined,
            enabled: !_submitting,
            textInputAction: TextInputAction.done,
            autofillHints: const <String>[AutofillHints.newPassword],
            onChanged: _handleFieldChanged,
            onSubmitted: (_) => _submit(),
          ),
        );
      }
      return fields;
    }

    // ── Profesional ──
    if (_isLogin) {
      fields.add(
        WebFormField(
          key: const Key('web-field-identifier'),
          controller: _identifierController,
          label: 'Nomor STR / SIP',
          hint: '16 digit angka pada STR atau SIP Anda',
          icon: Icons.badge_outlined,
          textInputAction: TextInputAction.next,
          enabled: !_submitting,
          onChanged: _handleFieldChanged,
        ),
      );
      gap();
      fields.add(
        WebPasswordField(
          controller: _passwordController,
          label: 'Password',
          enabled: !_submitting,
          textInputAction: TextInputAction.done,
          autofillHints: const <String>[AutofillHints.password],
          onChanged: _handleFieldChanged,
          onSubmitted: (_) => _submit(),
        ),
      );
      return fields;
    }

    fields.add(
      WebFormField(
        key: const Key('web-field-name'),
        controller: _nameController,
        label: 'Nama lengkap',
        icon: Icons.badge_outlined,
        textInputAction: TextInputAction.next,
        textCapitalization: TextCapitalization.words,
        enabled: !_submitting,
        autofillHints: const <String>[AutofillHints.name],
        onChanged: _handleFieldChanged,
      ),
    );
    gap();
    fields.add(
      WebFormField(
        key: const Key('web-field-str'),
        controller: _strController,
        label: 'Nomor STR',
        hint: '16 digit angka',
        icon: Icons.verified_user_outlined,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        enabled: !_submitting,
        onChanged: _handleFieldChanged,
      ),
    );
    gap();
    fields.add(
      WebFormField(
        key: const Key('web-field-sip'),
        controller: _sipController,
        label: 'Nomor SIP',
        hint: '16 digit angka',
        icon: Icons.assignment_ind_outlined,
        keyboardType: TextInputType.number,
        textInputAction: TextInputAction.next,
        enabled: !_submitting,
        onChanged: _handleFieldChanged,
      ),
    );
    gap();
    fields.add(
      DropdownButtonFormField<String>(
        initialValue: _specialization,
        isExpanded: true,
        decoration: const InputDecoration(
          labelText: 'Spesialisasi',
          prefixIcon: Icon(Icons.school_outlined, size: 20),
        ),
        items: const <DropdownMenuItem<String>>[
          DropdownMenuItem<String>(
            value: 'Sp.KJ',
            child: Text('Sp.KJ — Psikiater'),
          ),
          DropdownMenuItem<String>(
            value: 'M.Psi',
            child: Text('M.Psi — Psikolog'),
          ),
        ],
        onChanged: _submitting
            ? null
            : (String? value) {
                if (value == null) return;
                setState(() => _specialization = value);
              },
      ),
    );
    gap();
    fields.add(
      WebFormField(
        key: const Key('web-field-email'),
        controller: _emailController,
        label: 'Email',
        hint: 'nama@contoh.com',
        icon: Icons.email_outlined,
        keyboardType: TextInputType.emailAddress,
        textInputAction: TextInputAction.next,
        enabled: !_submitting,
        autofillHints: const <String>[AutofillHints.email],
        onChanged: _handleFieldChanged,
      ),
    );
    gap();
    fields.add(
      WebPasswordField(
        key: const Key('web-field-password'),
        controller: _passwordController,
        label: 'Password',
        enabled: !_submitting,
        textInputAction: TextInputAction.next,
        autofillHints: const <String>[AutofillHints.newPassword],
        onChanged: _handleFieldChanged,
      ),
    );
    gap();
    fields.add(
      WebPasswordChecklist(
        password: _passwordController.text,
        email: _emailController.text,
      ),
    );
    gap();
    fields.add(
      WebPasswordField(
        key: const Key('web-field-confirm'),
        controller: _confirmPasswordController,
        label: 'Konfirmasi password',
        icon: Icons.lock_reset_outlined,
        enabled: !_submitting,
        textInputAction: TextInputAction.done,
        autofillHints: const <String>[AutofillHints.newPassword],
        onChanged: _handleFieldChanged,
        onSubmitted: (_) => _submit(),
      ),
    );
    return fields;
  }

  Widget _buildSubmitButton() {
    final label = _isLogin ? 'Masuk' : 'Daftar';
    return FilledButton(
      key: const Key('web-submit'),
      onPressed: _submitting ? null : _submit,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (_submitting)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
          else
            Icon(
              _isLogin ? Icons.login_rounded : Icons.person_add_alt_1_rounded,
              size: 19,
            ),
          const SizedBox(width: 8),
          Text(_submitting ? 'Memproses...' : label),
        ],
      ),
    );
  }

  Widget _buildModeFooter(BuildContext context) {
    final question = _isLogin ? 'Belum punya akun?' : 'Sudah punya akun?';
    final action = _isLogin ? 'Daftar sekarang' : 'Masuk di sini';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Flexible(
          child: Text(
            question,
            style: const TextStyle(fontSize: 13, color: Color(0xFF6B6377)),
          ),
        ),
        TextButton(
          key: const Key('web-mode-footer-toggle'),
          onPressed: _submitting
              ? null
              : () => _changeMode(
                    _isLogin ? WebAuthMode.register : WebAuthMode.login,
                  ),
          child: Text(action),
        ),
      ],
    );
  }
}

/// Satu pilihan pada [_WebSegmentedToggle].
class _WebSegmentOption<T> {
  const _WebSegmentOption({
    required this.value,
    required this.label,
    required this.key,
  });

  final T value;
  final String label;
  final Key key;
}

/// Kontrol pilihan bersegmen (pill) khas desktop.
///
/// Memakai [Key] per opsi agar dapat diuji tanpa bergantung pada teks (teks
/// "Masuk" juga dipakai tombol submit).
class _WebSegmentedToggle<T> extends StatelessWidget {
  const _WebSegmentedToggle({
    required this.options,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final List<_WebSegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF3EDF8),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: options
            .map(
              (_WebSegmentOption<T> option) => Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    key: option.key,
                    borderRadius: BorderRadius.circular(9),
                    onTap: enabled ? () => onChanged(option.value) : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 140),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: option.value == selected
                            ? Colors.white
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(9),
                        boxShadow: option.value == selected
                            ? const <BoxShadow>[
                                BoxShadow(
                                  color: Color(0x12000000),
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          option.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: option.value == selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: option.value == selected
                                ? MalvaColors.plum
                                : const Color(0xFF6B6377),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            )
            .toList(growable: false),
      ),
    );
  }
}

/// Banner error ramah di dalam kartu formulir.
class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('web-auth-error'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: MalvaColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MalvaColors.danger.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(
            Icons.error_outline_rounded,
            size: 18,
            color: MalvaColors.danger,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                fontWeight: FontWeight.w600,
                color: MalvaColors.danger,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
