import 'dart:convert';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/screens/booking/doctor_discovery_screen.dart';
import 'package:malva_mental_health/src/screens/booking/doctor_profile_screen.dart';
import 'package:malva_mental_health/src/screens/my_care_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/widgets/doctor_review_actions.dart';

const _session = AuthSession(
    role: UserRole.patient,
    identifier: 'test',
    displayName: 'Pasien Uji',
    accessToken: 'test',
    backendUserId: 'patient');

class _Client extends http.BaseClient {
  final requests = <http.BaseRequest>[];
  bool reviewed = false;
  bool excludeLinkedFromDirectory = false;
  Completer<void>? delayedNoLocationSearch;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    Object body = <String, dynamic>{};
    if (request.url.path == '/v1/doctors/search') {
      final delayed = delayedNoLocationSearch != null &&
          request.url.queryParameters['sort_by'] == 'distance' &&
          !request.url.queryParameters.containsKey('patient_lat');
      if (delayed) await delayedNoLocationSearch!.future;
      body = {
        'doctors': [
          if (!excludeLinkedFromDirectory)
            {
              'user_id': 'doctor',
              'display_name': 'Dokter Uji',
              'review_count': 2,
              'average_stars': 4.5,
              'helpfulness_count': 1,
              'hospital_lat': -7.3,
              'hospital_lng': 112.7,
              'distance_km': 999
            },
          {'user_id': 'unknown', 'display_name': 'Dokter Tanpa Koordinat'}
        ]
      };
      if (delayed) {
        final result = body as Map<String, dynamic>;
        result['doctors'] = (result['doctors'] as List).reversed.toList();
      }
    } else if (request.url.path == '/v1/review-entitlements') {
      body = {
        'entitlements': reviewed
            ? []
            : [
                {'session_id': 'session', 'professional_id': 'doctor'}
              ]
      };
    } else if (request.method == 'POST') {
      reviewed = true;
    } else if (request.url.path == '/v1/doctors/doctor') {
      body = {
        'credential': {
          'user_id': 'doctor',
          'hospital_lat': -7.3,
          'hospital_lng': 112.7
        },
        'rating': {
          'average_stars': reviewed ? 4 : 4.5,
          'review_count': reviewed ? 1 : 2
        },
        'reviews': reviewed
            ? [
                {
                  'patient_name': 'Pa***',
                  'stars': 4,
                  'review_text': 'Penjelasan jelas',
                  'helpful': false
                }
              ]
            : []
      };
    } else if (request.url.path == '/v1/care-sessions') {
      body = {
        'sessions': [
          {
            'id': 'session',
            'professional_id': 'doctor',
            'status': 'completed',
            'session_type': 'chat'
          }
        ]
      };
    } else if (request.url.path == '/v1/care-packages') {
      body = {'packages': []};
    } else if (request.url.path == '/v1/patient-professional-links') {
      body = {
        'links': [
          {
            'professional_user_id': 'doctor',
            'professional_display_name': 'Dokter Uji',
            'status': 'active'
          }
        ]
      };
    } else if (request.url.path.endsWith('/availability')) {
      body = {'days': []};
    }
    return http.StreamedResponse(Stream.value(utf8.encode(jsonEncode(body))),
        request.method == 'POST' ? 201 : 200,
        headers: {'content-type': 'application/json'});
  }
}

void main() {
  setUpAll(initializeWib);
  testWidgets('late response without GPS cannot overwrite nearest ordering',
      (tester) async {
    final client = _Client();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: DoctorDiscoveryScreen(
                apiClient: MalvaApiClient(
                    baseUrl: 'http://test', httpClient: client)))));
    await tester.pumpAndSettle();
    client.delayedNoLocationSearch = Completer<void>();
    await tester.tap(find.text('Nama A-Z'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Terdekat').last);
    await tester.pump();
    container.read(patientLocationProvider.notifier).state =
        PatientLocationState(
            position: Position(
                latitude: -7.3,
                longitude: 112.7,
                timestamp: wibNow(),
                accuracy: 1,
                altitude: 0,
                altitudeAccuracy: 0,
                heading: 0,
                headingAccuracy: 0,
                speed: 0,
                speedAccuracy: 0));
    await tester.pumpAndSettle();
    client.delayedNoLocationSearch!.complete();
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Dokter Uji')).dy,
        lessThan(tester.getTopLeft(find.text('Dokter Tanpa Koordinat')).dy));
  });
  testWidgets('review draft cannot submit after account changes',
      (tester) async {
    final client = _Client();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(_session);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Scaffold(
                body: DoctorReviewActions(
                    apiClient: MalvaApiClient(
                        baseUrl: 'http://test', httpClient: client),
                    professionalId: 'doctor',
                    accessToken: _session.accessToken,
                    onSubmitted: () {})))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tulis ulasan'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('doctor-review-text')), 'A private draft');
    container.read(authStateProvider.notifier).setSession(const AuthSession(
        role: UserRole.patient,
        identifier: 'other',
        displayName: 'Other',
        backendUserId: 'other',
        accessToken: 'other-token'));
    await tester.pumpAndSettle();
    expect(find.text('Sesi akun telah berubah.'), findsOneWidget);
    expect(find.byKey(const Key('doctor-review-text')), findsNothing);
    expect(client.requests.where((r) => r.method == 'POST'), isEmpty);
    container.read(authStateProvider.notifier).setSession(_session);
    await tester.pumpAndSettle();
    expect(find.text('Sesi akun telah berubah.'), findsOneWidget);
    expect(find.byKey(const Key('doctor-review-text')), findsNothing);
  });
  testWidgets(
      'review survives same-account token rotation and refresh on submit',
      (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    AuthSession sessionWithToken(String token) => AuthSession(
        role: _session.role,
        identifier: _session.identifier,
        displayName: _session.displayName,
        backendUserId: _session.backendUserId,
        accessToken: token);
    container.read(authStateProvider.notifier).setSession(_session);
    final authorization = <String?>[];
    final finishReview = Completer<void>();
    final api = MalvaApiClient(
        baseUrl: 'http://test',
        httpClient: MockClient((request) async {
          if (request.url.path == '/v1/review-entitlements') {
            return http.Response(
                '{"entitlements":[{"session_id":"session","professional_id":"doctor"}]}',
                200);
          }
          if (request.url.path == '/v1/auth/refresh') {
            return http.Response(
                jsonEncode({
                  'user': {'id': 'patient', 'role': 'patient'},
                  'access_token': 'rotated-token',
                  'refresh_token': 'rotated-refresh'
                }),
                200);
          }
          authorization.add(request.headers['authorization']);
          if (request.headers['authorization'] == 'Bearer fresh-token') {
            return http.Response('{"error":"expired"}', 401);
          }
          await finishReview.future;
          return http.Response('{}', 201);
        }),
        onTokenRefreshed: (access, refresh) => container
            .read(authStateProvider.notifier)
            .setSession(sessionWithToken(access)))
      ..setRefreshToken('refresh');
    var submitted = 0;
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: Scaffold(
                body: DoctorReviewActions(
                    apiClient: api,
                    professionalId: 'doctor',
                    accessToken: _session.accessToken,
                    onSubmitted: () => submitted++)))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tulis ulasan'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('doctor-review-text')), 'Review after refresh');
    container
        .read(authStateProvider.notifier)
        .setSession(sessionWithToken('fresh-token'));
    await tester.pumpAndSettle();
    expect(find.text('Review after refresh'), findsOneWidget);
    await tester.tap(find.text('Kirim ulasan'));
    await tester.pumpAndSettle();
    expect(authorization, ['Bearer fresh-token', 'Bearer rotated-token']);
    expect(find.text('Sesi akun telah berubah.'), findsNothing);
    expect(find.text('Mengirim…'), findsOneWidget);
    finishReview.complete();
    await tester.pumpAndSettle();
    expect(find.text('Ulasan sesi'), findsNothing);
    expect(submitted, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'MyCare loads linked professional even outside first100 directory',
      (tester) async {
    final client = _Client()..excludeLinkedFromDirectory = true;
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: MyCareScreen(
                session: _session,
                apiClient: MalvaApiClient(
                    baseUrl: 'http://test', httpClient: client)))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Terhubung'));
    await tester.pumpAndSettle();
    expect(find.textContaining('4.5 / 5'), findsOneWidget);
    expect(
        client.requests
            .where((request) => request.url.path == '/v1/doctors/doctor'),
        isNotEmpty,
        reason:
            'linked professional details must load beyond the directory page');
  });
  testWidgets('discovery shows real stars and honest unknown distance',
      (tester) async {
    final api = MalvaApiClient(baseUrl: 'http://test', httpClient: _Client());
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(home: DoctorDiscoveryScreen(apiClient: api))));
    await tester.pumpAndSettle();
    expect(find.textContaining('4.5'), findsOneWidget);
    expect(find.textContaining('Lokasi pasien belum tersedia'), findsOneWidget);
    expect(
        find.textContaining('Lokasi praktik belum tersedia'), findsOneWidget);
    expect(find.text('999.0 km'), findsNothing);
  });

  testWidgets('MyCare professional cards use the same live rating and profile',
      (tester) async {
    final client = _Client();
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: MyCareScreen(
                session: _session,
                apiClient: MalvaApiClient(
                    baseUrl: 'http://test', httpClient: client)))));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ChoiceChip, 'Terhubung'));
    await tester.pumpAndSettle();
    expect(find.textContaining('4.5 / 5'), findsOneWidget);
    expect(find.text('Lihat profil ›'), findsOneWidget);
    await tester.tap(find.text('Lihat profil ›'));
    await tester.pumpAndSettle();
    expect(find.byType(DoctorProfileScreen), findsOneWidget);
    expect(
        client.requests
            .where((request) => request.url.path == '/v1/doctors/doctor')
            .length,
        greaterThanOrEqualTo(2));
  });

  testWidgets('location changes refresh search and replace old server distance',
      (tester) async {
    final client = _Client();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: DoctorDiscoveryScreen(
                apiClient: MalvaApiClient(
                    baseUrl: 'http://test', httpClient: client)))));
    await tester.pumpAndSettle();
    container.read(patientLocationProvider.notifier).state =
        PatientLocationState(
            position: Position(
                latitude: -7.3,
                longitude: 112.7,
                timestamp: wibNow(),
                accuracy: 1,
                altitude: 0,
                altitudeAccuracy: 0,
                heading: 0,
                headingAccuracy: 0,
                speed: 0,
                speedAccuracy: 0));
    await tester.pumpAndSettle();
    expect(
        client.requests
            .where((r) => r.url.queryParameters['patient_lat'] == '-7.3'),
        isNotEmpty);
    expect(find.text('0.0 km'), findsOneWidget);
  });

  testWidgets(
      'patient submits stars helpful and text and sees persisted feedback',
      (tester) async {
    final client = _Client();
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.read(authStateProvider.notifier).setSession(_session);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            home: DoctorProfileScreen(
                doctorUserId: 'doctor',
                session: _session,
                apiClient: MalvaApiClient(
                    baseUrl: 'http://test', httpClient: client)))));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Tulis ulasan'), 300);
    await tester.tap(find.text('Tulis ulasan'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('4 bintang'));
    await tester.enterText(
        find.byKey(const Key('doctor-review-text')), 'Penjelasan jelas');
    await tester.tap(find.text('Sesi ini membantu saya'));
    await tester.tap(find.text('Kirim ulasan'));
    await tester.pumpAndSettle();
    final posted =
        client.requests.where((r) => r.method == 'POST').single as http.Request;
    expect(jsonDecode(posted.body), {
      'stars': 4,
      'review_text': 'Penjelasan jelas',
      'helpful': false,
      'session_id': 'session'
    });
    expect(client.reviewed, isTrue);
    await tester.scrollUntilVisible(find.text('Penjelasan jelas'), -200);
    expect(find.text('Penjelasan jelas'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
