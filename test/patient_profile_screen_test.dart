import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/settings_screens.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

const _ami = AuthSession(
    role: UserRole.patient,
    identifier: 'ami',
    displayName: 'Ami',
    backendUserId: 'ami',
    accessToken: 'ami-token',
    refreshToken: 'ami-refresh');
const _other = AuthSession(
    role: UserRole.patient,
    identifier: 'other',
    displayName: 'Other',
    backendUserId: 'other',
    accessToken: 'other-token');

http.Response _profile(String id, String name, {String? dob}) => http.Response(
    jsonEncode({
      'user': {
        'id': id,
        'email': '$id@example.test',
        'role': 'patient',
        'display_name': name,
        'date_of_birth': dob
      }
    }),
    200);

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  Future<ProviderContainer> mount(
      WidgetTester tester, Future<http.Response> Function(http.Request) respond,
      {bool settle = true}) async {
    final container = ProviderContainer(overrides: [
      apiClientProvider.overrideWithValue(MalvaApiClient(
          baseUrl: 'https://synthetic.test', httpClient: MockClient(respond)))
    ]);
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(_ami);
    container.read(malvaStoreProvider.notifier).applySession(_ami);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Builder(
                builder: (context) => Scaffold(
                    body: TextButton(
                        onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) => const ProfileScreen())),
                        child: const Text('Open profile')))))));
    await tester.tap(find.text('Open profile'));
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump(const Duration(milliseconds: 400));
    }
    return container;
  }

  TextField field(WidgetTester tester, String label) =>
      tester.widget<TextField>(find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == label));

  testWidgets('shows the active profile and leaves unknown DOB empty',
      (tester) async {
    await mount(tester, (_) async => _profile('ami', 'Ami Google'));
    expect(field(tester, 'Name').controller!.text, 'Ami Google');
    expect(field(tester, 'Date of Birth').controller!.text, isEmpty);
  });

  testWidgets('saves real profile via PATCH and updates active identity',
      (tester) async {
    Map<String, dynamic>? sent;
    final container = await mount(tester, (request) async {
      if (request.method == 'PATCH') {
        expect(request.headers['authorization'], 'Bearer ami-token');
        sent = jsonDecode(request.body) as Map<String, dynamic>;
        return _profile('ami', 'Ami Updated', dob: '2000-12-31');
      }
      return _profile('ami', 'Ami Google', dob: '2001-01-02');
    });
    expect(field(tester, 'Date of Birth').controller!.text, '02/01/2001');
    await tester.enterText(
        find.widgetWithText(TextField, 'Name'), 'Ami Updated');
    await tester.enterText(
        find.widgetWithText(TextField, 'Date of Birth'), '31/12/2000');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(
        sent, {'display_name': 'Ami Updated', 'date_of_birth': '2000-12-31'});
    expect(container.read(currentSessionProvider)!.displayName, 'Ami Updated');
    expect(container.read(malvaStoreProvider).patient.name, 'Ami Updated');
    expect(find.text('Perubahan profil tersimpan.'), findsOneWidget);
    expect(
        (await container.read(malvaStoreProvider.notifier).restoreSession())!
            .displayName,
        'Ami Updated');
  });

  testWidgets('invalid DOB prevents request and failure never claims saved',
      (tester) async {
    var patches = 0;
    await mount(tester, (request) async {
      if (request.method == 'PATCH') {
        patches++;
        return http.Response('{"error":"Tidak tersimpan"}', 500);
      }
      return _profile('ami', 'Ami');
    });
    await tester.enterText(
        find.widgetWithText(TextField, 'Date of Birth'), '31/02/2000');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(patches, 0);
    await tester.enterText(find.widgetWithText(TextField, 'Date of Birth'), '');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(patches, 1);
    expect(find.text('Tidak tersimpan'), findsOneWidget);
    expect(find.text('Perubahan profil tersimpan.'), findsNothing);
  });

  testWidgets('late profile save cannot overwrite a different active account',
      (tester) async {
    final response = Completer<http.Response>();
    final container = await mount(
        tester,
        (request) async => request.method == 'PATCH'
            ? response.future
            : _profile(
                request.headers['authorization'] == 'Bearer other-token'
                    ? 'other'
                    : 'ami',
                request.headers['authorization'] == 'Bearer other-token'
                    ? 'Other'
                    : 'Ami'));
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Old save');
    await tester.tap(find.text('Save changes'));
    await tester.pump();
    container.read(authStateProvider.notifier).setSession(_other);
    container.read(malvaStoreProvider.notifier).applySession(_other);
    await tester.pumpAndSettle();
    response.complete(_profile('ami', 'Old save'));
    await tester.pumpAndSettle();
    expect(container.read(currentSessionProvider)!.displayName, 'Other');
    expect(container.read(malvaStoreProvider).patient.name, 'Other');
    expect(field(tester, 'Name').controller!.text, 'Other');
    expect(find.text('Perubahan profil tersimpan.'), findsNothing);
  });

  testWidgets('late profile load cannot fill another account form',
      (tester) async {
    final oldResponse = Completer<http.Response>();
    final container = await mount(tester, (request) async {
      if (request.url.path != '/v1/me') return http.Response('{}', 200);
      return request.headers['authorization'] == 'Bearer ami-token'
          ? oldResponse.future
          : _profile('other', 'Other');
    }, settle: false);
    container.read(authStateProvider.notifier).setSession(_other);
    container.read(malvaStoreProvider.notifier).applySession(_other);
    await tester.pumpAndSettle();
    oldResponse
        .complete(_profile('ami', 'Old private name', dob: '2001-02-03'));
    await tester.pumpAndSettle();
    expect(field(tester, 'Name').controller!.text, 'Other');
    expect(field(tester, 'Date of Birth').controller!.text, isEmpty);
  });

  testWidgets(
      'save uses rotated token and preserves rotated session credentials',
      (tester) async {
    String? sentToken;
    final container = await mount(tester, (request) async {
      if (request.method == 'PATCH')
        sentToken = request.headers['authorization'];
      return _profile('ami', request.method == 'PATCH' ? 'Updated' : 'Ami');
    });
    container
        .read(authStateProvider.notifier)
        .updateTokens('rotated-access', 'rotated-refresh');
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Updated');
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(sentToken, 'Bearer rotated-access');
    expect(
        container.read(currentSessionProvider)!.accessToken, 'rotated-access');
    expect(container.read(currentSessionProvider)!.refreshToken,
        'rotated-refresh');
    expect(container.read(currentSessionProvider)!.displayName, 'Updated');
  });
}
