import 'package:flutter/widgets.dart' show Widget, ValueChanged;

import '../../services/google_auth_service.dart';
import '../contracts/ports.dart';

/// Login Google mobile/desktop: alur imperatif `authenticate()` yang sudah ada
/// (GoogleAuthService.signInIdToken). Perilaku mobile TIDAK berubah.
class GoogleSignInIo implements GoogleSignInPort {
  const GoogleSignInIo();

  @override
  bool get usesButtonWidget => false;

  @override
  Future<String?> signInIdToken() => GoogleAuthService.signInIdToken();

  @override
  Widget? buildButton({
    required ValueChanged<String> onIdToken,
    required ValueChanged<Object> onError,
  }) =>
      null;
}
