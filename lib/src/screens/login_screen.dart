import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import 'auth_widgets.dart';
import 'patient_login_screen.dart';
import 'professional_login_screen.dart';

/// Gerbang autentikasi Malva.
///
/// Alur: RoleGate (pilih Pasien/Profesional) → halaman login khusus peran.
/// File ini menggantikan kartu login gabungan lama agar kedua peran
/// punya halaman dan form yang terpisah penuh.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({
    super.key,
    required this.onAuthenticated,
  });

  final ValueChanged<AuthSession> onAuthenticated;

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  UserRole? _role;

  @override
  Widget build(BuildContext context) {
    final role = _role;
    if (role == null) {
      return RoleGateScreen(
        onSelectPatient: () => setState(() => _role = UserRole.patient),
        onSelectProfessional: () =>
            setState(() => _role = UserRole.professional),
      );
    }
    if (role == UserRole.patient) {
      return PatientLoginScreen(
        onAuthenticated: widget.onAuthenticated,
        onBackToRole: () => setState(() => _role = null),
      );
    }
    return ProfessionalLoginScreen(
      onAuthenticated: widget.onAuthenticated,
      onBackToRole: () => setState(() => _role = null),
    );
  }
}
