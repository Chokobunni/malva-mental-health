import 'dart:async';

import 'package:flutter/widgets.dart' show Widget, ValueChanged;
import 'package:google_sign_in/google_sign_in.dart' show GoogleSignIn;
import 'package:google_sign_in_platform_interface/google_sign_in_platform_interface.dart'
    show
        GoogleSignInPlatform,
        AuthenticationEvent,
        AuthenticationEventSignIn,
        AuthenticationEventException,
        AuthenticationEventSignOut;
import 'package:google_sign_in_web/google_sign_in_web.dart'
    show
        GoogleSignInPlugin,
        GSIButtonConfiguration,
        GSIButtonShape,
        GSIButtonSize,
        GSIButtonText,
        GSIButtonTheme;

import '../contracts/ports.dart';

/// Login Google web: WAJIB lewat tombol resmi Google (`renderButton`).
///
/// `authenticate()` TIDAK didukung di web (plugin melempar UnimplementedError),
/// jadi [signInIdToken] sengaja tidak dipakai di web. ID token diterima dari
/// `authenticationEvents` setelah pengguna menekan tombol Google, lalu
/// diteruskan ke [onIdToken] untuk dikirim ke `POST /v1/auth/google`.
///
/// `initialize()` di web HANYA mengirim `clientId` (bukan `serverClientId`) —
/// plugin meng-assert `serverClientId == null` di web.
class GoogleSignInWeb implements GoogleSignInPort {
  GoogleSignInWeb(this._config);

  final GoogleClientConfig _config;

  StreamSubscription<AuthenticationEvent>? _sub;
  ValueChanged<String>? _onIdToken;
  ValueChanged<Object>? _onError;
  Future<void>? _initFuture;

  @override
  bool get usesButtonWidget => true;

  @override
  Future<String?> signInIdToken() async {
    throw UnsupportedError(
      'Di web, login Google memakai tombol renderButton — bukan authenticate().',
    );
  }

  @override
  Widget? buildButton({
    required ValueChanged<String> onIdToken,
    required ValueChanged<Object> onError,
  }) {
    _onIdToken = onIdToken;
    _onError = onError;
    // Satu langganan saja; event masuk setelah pengguna menekan tombol Google.
    _sub ??=
        GoogleSignInPlatform.instance.authenticationEvents!.listen(_handle);
    // Inisialisasi sekali (clientId saja). renderButton menunggu init selesai.
    _initFuture ??= GoogleSignIn.instance
        .initialize(clientId: _config.clientId)
        .catchError((Object e) => _onError?.call(e));

    final plugin = GoogleSignInPlatform.instance as GoogleSignInPlugin;
    return plugin.renderButton(
      configuration: GSIButtonConfiguration(
        theme: GSIButtonTheme.outline,
        size: GSIButtonSize.large,
        text: GSIButtonText.continueWith,
        shape: GSIButtonShape.rectangular,
        minimumWidth: 280,
      ),
    );
  }

  void _handle(AuthenticationEvent event) {
    switch (event) {
      case AuthenticationEventSignIn():
        final token = event.authenticationTokens.idToken;
        if (token != null && token.isNotEmpty) {
          _onIdToken?.call(token);
        } else {
          _onError?.call(StateError('id_token_kosong'));
        }
      case AuthenticationEventException():
        _onError?.call(event.exception);
      case AuthenticationEventSignOut():
        break;
    }
  }

  /// Lepas langganan (dipanggil saat provider di-dispose bila perlu).
  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
