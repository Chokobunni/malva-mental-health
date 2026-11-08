import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/screens/patient_login_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

/// Port Google palsu: meniru perilaku web (tombol) atau mobile (imperatif).
class _FakeGooglePort implements GoogleSignInPort {
  _FakeGooglePort({
    required this.usesButtonWidget,
    this.mobileToken,
    this.webToken,
  });

  @override
  final bool usesButtonWidget;
  final String? mobileToken;
  final String? webToken;

  int signInCalls = 0;

  @override
  Future<String?> signInIdToken() async {
    signInCalls++;
    return mobileToken;
  }

  @override
  Widget? buildButton({
    required ValueChanged<String> onIdToken,
    required ValueChanged<Object> onError,
  }) {
    if (!usesButtonWidget) return null;
    return ElevatedButton(
      onPressed: () => onIdToken(webToken ?? ''),
      child: const Text('GWEB'),
    );
  }
}

class _FakeApi extends MalvaApiClient {
  _FakeApi() : super(baseUrl: 'http://backend.test');

  final googleTokens = <String>[];

  @override
  Future<BackendAuthResult> googleLogin({
    required String idToken,
    UserRole role = UserRole.patient,
    void Function()? onAccountCreated,
  }) async {
    googleTokens.add(idToken);
    return const BackendAuthResult(
      userId: 'u1',
      email: 'pasien@malva.app',
      role: UserRole.patient,
      displayName: 'Pasien',
      accessToken: 'access',
      refreshToken: 'refresh',
    );
  }
}

Future<_FakeApi> _pumpLogin(
  WidgetTester tester,
  _FakeGooglePort port,
) async {
  tester.view.physicalSize = const Size(1000, 3000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final api = _FakeApi();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      googleSignInProvider.overrideWithValue(port),
      apiClientProvider.overrideWithValue(api),
    ],
    child: MaterialApp(
      home: PatientLoginScreen(onAuthenticated: (_) {}),
    ),
  ));
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets(
      'WEB: memakai tombol Google (bukan authenticate), token → googleLogin',
      (tester) async {
    final port =
        _FakeGooglePort(usesButtonWidget: true, webToken: 'WEB_ID_TOKEN');
    final api = await _pumpLogin(tester, port);

    // Tombol web dari port dirender.
    expect(find.text('GWEB'), findsOneWidget);
    await tester.tap(find.text('GWEB'));
    await tester.pumpAndSettle();

    // ID token dari tombol web diteruskan ke googleLogin.
    expect(api.googleTokens, ['WEB_ID_TOKEN']);
    // Jalur imperatif (authenticate) TIDAK dipakai di web.
    expect(port.signInCalls, 0);
  });

  testWidgets('MOBILE: memakai jalur imperatif lama (signInIdToken)',
      (tester) async {
    final port =
        _FakeGooglePort(usesButtonWidget: false, mobileToken: 'MOB_ID_TOKEN');
    final api = await _pumpLogin(tester, port);

    // Mobile: tombol Flutter biasa dengan label lama.
    expect(find.text('Continue with Google'), findsOneWidget);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(port.signInCalls, 1);
    expect(api.googleTokens, ['MOB_ID_TOKEN']);
  });
}
