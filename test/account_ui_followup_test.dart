import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/screens/consent_management_screen.dart';
import 'package:malva_mental_health/src/screens/messages_list_screen.dart';
import 'package:malva_mental_health/src/screens/safety/emergency_contacts_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

const _patient = AuthSession(
  role: UserRole.patient,
  identifier: 'patient-a',
  displayName: 'Pasien A',
  backendUserId: 'patient-a',
  accessToken: 'token-a',
);
const _otherPatient = AuthSession(
  role: UserRole.patient,
  identifier: 'patient-b',
  displayName: 'Pasien B',
  backendUserId: 'patient-b',
  accessToken: 'token-b',
);
const _professional = AuthSession(
  role: UserRole.professional,
  identifier: 'professional',
  displayName: 'Profesional',
  accessToken: 'token-pro',
);

http.Response _json(Object body) => http.Response(jsonEncode(body), 200,
    headers: {'content-type': 'application/json'});

Map<String, Object> _link(String id) => {
      'patient_id': 'patient',
      'professional_user_id': id,
      'professional_id': 'profile-$id',
      'patient_display_name': 'Pasien',
      'professional_display_name': 'Profesional $id',
      'status': 'active',
    };

Map<String, Object> _consent(String id, bool therapy) => {
      'professional_id': id,
      'share_screenings': true,
      'share_mood_diary': false,
      'share_medications': true,
      'share_timeline': false,
      'share_health_record': true,
      'share_goals': false,
      'share_therapy_records': therapy,
    };

ProviderContainer _container(MalvaApiClient api) {
  final container = ProviderContainer(overrides: [
    apiClientProvider.overrideWithValue(api),
    authStateProvider
        .overrideWith((ref) => AuthNotifier()..setSession(_patient)),
    capabilitiesProvider.overrideWithValue(const PlatformCapabilities(
      canScheduleOsReminders: false,
      canRegisterPush: false,
      canExportFiles: false,
      canDialTel: false,
      canPickFiles: false,
      canGeolocate: false,
      canBindGoogleCalendar: false,
      isWebBuild: true,
    )),
  ]);
  addTearDown(container.dispose);
  return container;
}

Widget _wrap(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: buildMalvaTheme(), home: child),
    );

Finder _therapySwitch() => find.descendant(
      of: find.ancestor(
        of: find.text('Therapy Record (Psikologis)'),
        matching: find.byType(Row),
      ),
      matching: find.byType(Switch),
    );

Future<void> _save(WidgetTester tester) async {
  final save = find.widgetWithText(FilledButton, 'Simpan Pengaturan');
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pumpAndSettle();
}

Future<void> _selectProfessional(WidgetTester tester, String id) async {
  final dropdown = find.byType(DropdownButtonFormField<String>);
  await tester.ensureVisible(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text('Profesional $id').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'same-account token refresh preserves selected consent while saving',
      (tester) async {
    final pending = Completer<http.Response>();
    var linkLoads = 0;
    final api = MalvaApiClient(
        baseUrl: 'https://synthetic.test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/patient-professional-links') {
            linkLoads++;
            return _json({
              'links': [_link('pro-1'), _link('pro-2')]
            });
          }
          if (request.method == 'PUT') return pending.future;
          return _json({
            'consent':
                _consent(request.url.queryParameters['professional_id']!, false)
          });
        }));
    final container = _container(api);
    await tester.pumpWidget(_wrap(container, const ConsentManagementScreen()));
    await tester.pumpAndSettle();
    await _selectProfessional(tester, 'pro-2');
    await tester.ensureVisible(_therapySwitch());
    await tester.pumpAndSettle();
    await tester.tap(_therapySwitch());
    await tester.pumpAndSettle();
    final loadsBeforeSave = linkLoads;
    final save = find.widgetWithText(FilledButton, 'Simpan Pengaturan');
    await tester.ensureVisible(save);
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pump();
    container
        .read(authStateProvider.notifier)
        .updateTokens('rotated', 'refresh');
    await tester.pump();
    pending.complete(_json({'consent': _consent('pro-2', true)}));
    await tester.pumpAndSettle();
    expect(linkLoads, loadsBeforeSave,
        reason: 'rotation is not an account change');
    expect(find.text('Pengaturan consent berhasil disimpan.'), findsOneWidget);
    await tester.ensureVisible(find.byType(DropdownButtonFormField<String>));
    expect(find.text('Profesional pro-2'), findsOneWidget);
    expect(tester.widget<Switch>(_therapySwitch()).value, isTrue);
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
  });

  testWidgets(
      'therapy consent roundtrip preserves other grants per professional',
      (tester) async {
    final stored = {
      'pro-1': _consent('pro-1', true),
      'pro-2': _consent('pro-2', false)
    };
    final writes = <Map<String, dynamic>>[];
    final api = MalvaApiClient(
      baseUrl: 'https://synthetic.test',
      httpClient: MockClient((request) async {
        if (request.url.path == '/v1/patient-professional-links') {
          return _json({
            'links': [_link('pro-1'), _link('pro-2')]
          });
        }
        if (request.method == 'PUT') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          writes.add(body);
          stored[body['professional_id'] as String] =
              body.cast<String, Object>();
          return _json({'consent': body});
        }
        return _json({
          'consent': stored[request.url.queryParameters['professional_id']]!
        });
      }),
    );
    final container = _container(api);
    await tester.pumpWidget(_wrap(container, const ConsentManagementScreen()));
    await tester.pumpAndSettle();
    expect(_therapySwitch(), findsOneWidget);
    expect(tester.widget<Switch>(_therapySwitch()).value, isTrue);
    await _save(tester);
    expect(writes.single, _consent('pro-1', true));

    await _selectProfessional(tester, 'pro-2');
    expect(tester.widget<Switch>(_therapySwitch()).value, isFalse);
    await tester.ensureVisible(_therapySwitch());
    await tester.pumpAndSettle();
    await tester.tap(_therapySwitch());
    await tester.pumpAndSettle();
    await _save(tester);
    expect(writes.last, _consent('pro-2', true));

    await _selectProfessional(tester, 'pro-1');
    await _selectProfessional(tester, 'pro-2');
    expect(tester.widget<Switch>(_therapySwitch()).value, isTrue);
    await tester.ensureVisible(_therapySwitch());
    await tester.pumpAndSettle();
    await tester.tap(_therapySwitch());
    await tester.pumpAndSettle();
    await _save(tester);
    expect(writes.last, _consent('pro-2', false));
    expect(stored['pro-1'], _consent('pro-1', true));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'account switch discards a delayed consent and selects current link',
      (tester) async {
    final delayed = Completer<http.Response>();
    final requests = <String>[];
    final api = MalvaApiClient(
      baseUrl: 'https://synthetic.test',
      httpClient: MockClient((request) async {
        final account =
            request.headers['authorization'] == 'Bearer token-a' ? 'a' : 'b';
        if (request.url.path == '/v1/patient-professional-links') {
          return _json({
            'links': [_link('pro-$account')]
          });
        }
        final id = request.url.queryParameters['professional_id'];
        requests.add('$account/$id');
        if (account == 'a') return delayed.future;
        return _json({'consent': _consent('pro-b', false)});
      }),
    );
    final container = _container(api);
    await tester.pumpWidget(_wrap(container, const ConsentManagementScreen()));
    await tester.pump();
    await tester.pump();
    expect(requests, ['a/pro-a']);
    container.read(authStateProvider.notifier).setSession(_otherPatient);
    await tester.pumpAndSettle();
    expect(requests, ['a/pro-a', 'b/pro-b']);
    expect(find.text('Profesional pro-b'), findsOneWidget);
    expect(tester.widget<Switch>(_therapySwitch()).value, isFalse);
    delayed.complete(_json({'consent': _consent('pro-a', true)}));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(_therapySwitch()).value, isFalse);
    expect(find.text('Profesional pro-b'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'embedded professional messages keeps title without second app bar',
      (tester) async {
    final api = MalvaApiClient(
        baseUrl: 'https://synthetic.test',
        httpClient: MockClient((_) async => _json({'links': []})));
    await tester.pumpWidget(_wrap(
        _container(api),
        Scaffold(
          body: MessagesListScreen(session: _professional, apiClient: api),
        )));
    await tester.pumpAndSettle();
    expect(find.text('Messages'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.text('Recent'), findsOneWidget);
  });

  testWidgets('fullscreen messages retains app bar and back navigation',
      (tester) async {
    final api = MalvaApiClient(
        baseUrl: 'https://synthetic.test',
        httpClient: MockClient((_) async => _json({'links': []})));
    await tester.pumpWidget(_wrap(_container(api), Builder(builder: (context) {
      return Scaffold(
          body: TextButton(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => MessagesListScreen(
                          session: _professional, apiClient: api))),
              child: const Text('Open')));
    })));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Messages'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets(
      'narrow contact identity is readable and all actions remain usable',
      (tester) async {
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const name = 'Ibu Rahayu Kusumaningrum Keluarga';
    var exists = true;
    final api = MalvaApiClient(
        baseUrl: 'https://synthetic.test',
        httpClient: MockClient((request) async {
          if (request.method == 'DELETE') {
            exists = false;
            return _json({'ok': true});
          }
          if (request.url.path == '/v1/emergency-contacts') {
            return _json({
              'contacts': [
                if (exists)
                  {
                    'id': 'contact-1',
                    'patient_id': 'patient-a',
                    'contact_name': name,
                    'contact_phone': '08123456789',
                    'relationship': 'Ibu',
                    'is_default': true,
                  }
              ]
            });
          }
          return _json({'incidents': []});
        }));
    await tester.pumpWidget(_wrap(
        _container(api),
        const MediaQuery(
          data: MediaQueryData(
              size: Size(320, 1000), textScaler: TextScaler.linear(1.3)),
          child: EmergencyContactsScreen(),
        )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.getSize(find.text(name)).width, greaterThan(180));
    expect(tester.getSize(find.text(name)).height, lessThan(120));
    expect(find.text('Utama'), findsOneWidget);
    for (final action in ['Edit', 'Panggil', 'SMS', 'Hapus']) {
      final button = find.byTooltip(action);
      expect(tester.getSize(button).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
    }
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextField, name), findsOneWidget);
    Navigator.of(tester.element(find.byType(TextField).first)).pop();
    await tester.pumpAndSettle();
    for (final action in ['Panggil', 'SMS']) {
      await tester.tap(find.byTooltip(action));
      await tester.pumpAndSettle();
      expect(find.text('Hubungi nomor'), findsOneWidget);
      expect(find.text('08123456789'), findsOneWidget);
      Navigator.of(tester.element(find.text('Hubungi nomor'))).pop();
      await tester.pumpAndSettle();
    }
    await tester.tap(find.byTooltip('Hapus'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Hapus'));
    await tester.pumpAndSettle();
    expect(find.text(name), findsNothing);
    expect(find.text('Belum ada kontak darurat'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
