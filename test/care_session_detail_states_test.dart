import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/providers.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/services/server_clock.dart';
import 'package:malva_mental_health/src/time/wib.dart';
import 'package:malva_mental_health/src/widgets/care_session_card.dart';

Map<String, dynamic> sessionJson(
        {String status = 'scheduled',
        bool future = false,
        bool video = true,
        String? packageId,
        bool attended = false,
        String summary = ''}) =>
    {
      'id': 'actual-session',
      'patient_id': 'patient',
      'professional_id': 'professional',
      'patient_name': 'Pasien Contoh',
      'professional_name': 'Profesional Contoh',
      'session_type': video ? 'video' : 'chat',
      'scheduled_at': wibIso(ServerClock.now()
          .add(future ? const Duration(days: 2) : const Duration(minutes: -5))),
      'duration_minutes': 60,
      'status': status,
      'meeting_url': 'https://meet.google.com/abc-defg-hij',
      if (packageId != null) 'package_id': packageId,
      'patient_attendance': attended ? 'attended' : '',
      'summary_for_patient': summary,
    };
Future<void> mountDetail(WidgetTester tester,
    {required UserRole role,
    required Map<String, dynamic> data,
    BackendChatAccess access = const BackendChatAccess(),
    bool rejectFinish = false,
    Future<http.Response>? delayedFeed,
    List<Map<String, dynamic>>? patches,
    double scale = 1}) async {
  final api = MalvaApiClient(
      baseUrl: 'https://synthetic.test',
      httpClient: MockClient((request) async {
        if (request.method == 'PATCH') {
          patches?.add(jsonDecode(request.body) as Map<String, dynamic>);
          if (rejectFinish)
            return http.Response(
                jsonEncode({'error': 'Sesi belum dapat diselesaikan.'}), 400);
          data = {...data, 'status': 'completed'};
          return http.Response(jsonEncode({'session': data}), 200);
        }
        if (request.url.path == '/v1/care-sessions')
          return delayedFeed ??
              http.Response(
                  jsonEncode({
                    'sessions': [data]
                  }),
                  200);
        if (request.url.path == '/v1/chat-permission')
          return http.Response(
              jsonEncode({
                'access': {
                  'can_send_text': access.canSendText,
                  'has_active_package': access.hasActivePackage
                }
              }),
              200);
        return http.Response(jsonEncode({'packages': []}), 200);
      }));
  final owner = AuthSession(
      role: role,
      identifier: role.name,
      backendUserId: role == UserRole.professional ? 'professional' : 'patient',
      displayName: 'Akun',
      accessToken: 'real-token');
  await tester.pumpWidget(ProviderScope(
      overrides: [
        currentSessionProvider.overrideWith((ref) => owner),
        apiClientProvider.overrideWithValue(api)
      ],
      child: MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: child!),
          home: CareSessionDetailScreen(
              card: CareSessionCard(
                  session: BackendCareSession.fromJson(data),
                  role: role,
                  apiClient: api,
                  onOpenChat: () {},
                  onChanged: () async {})))));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  setUp(initializeWib);

  testWidgets('expired professional detail locks new session notes',
      (tester) async {
    await mountDetail(tester, role: UserRole.professional, data: {
      ...sessionJson(status: 'completed'),
      'scheduled_at':
          wibIso(ServerClock.now().subtract(const Duration(hours: 26))),
    });
    final submit = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Isi Catatan Sesi'));
    expect(submit.onPressed, isNull);
    expect(find.byIcon(Icons.lock_outline), findsOneWidget);
    await tester.scrollUntilVisible(
        find.text('Batas Waktu Pengisian Berakhir'), 180,
        scrollable: find.byType(Scrollable).first);
    expect(find.textContaining('24 jam'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  for (final role in [UserRole.patient, UserRole.professional]) {
    testWidgets(
        '$role live video has join and guarded role-specific completion',
        (tester) async {
      await mountDetail(tester, role: role, data: sessionJson(attended: true));
      expect(find.text('Sesi Konsultasi Aktif'), findsOneWidget);
      expect(find.text('Masuk Video Call'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Sisa Waktu Sesi'), 180,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('Sisa Waktu Sesi'), findsOneWidget);
      expect(find.text('Tandai Sesi Selesai'),
          role == UserRole.professional ? findsOneWidget : findsNothing);

      await tester.pumpWidget(const SizedBox());
    });
    testWidgets('$role future one-time chat remains closed with preparation',
        (tester) async {
      await mountDetail(tester,
          role: role, data: sessionJson(future: true, video: false));
      final button = tester.widget<FilledButton>(
          find.widgetWithText(FilledButton, 'Masuk Ruang Chat (Belum Dibuka)'));
      expect(button.onPressed, isNull);
      expect(find.text('Sesi Terjadwal'), findsOneWidget);
      expect(find.text('Menunggu Jadwal'), findsOneWidget);
      if (role == UserRole.professional)
        expect(
            tester
                .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, 'Tandai Sesi Selesai'))
                .onPressed,
            isNull);
      await tester.pumpWidget(const SizedBox());
    });
    testWidgets(
        '$role completed detail shows the appropriate saved summary or notes',
        (tester) async {
      await mountDetail(tester,
          role: role,
          data: sessionJson(
              status: 'completed',
              summary:
                  'Keluhan Utama\nKeluhan tersimpan\n\nRekomendasi Praktis\nRekomendasi tersimpan'));
      if (role == UserRole.patient) {
        expect(find.text('Catatan Sesi Konsultasi'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Keluhan tersimpan'), 180,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('Keluhan tersimpan'), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Rekomendasi Praktis'), 160,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('Rekomendasi Praktis'), findsOneWidget);
        expect(find.text('Lihat / Edit Catatan Sesi'), findsNothing);
        expect(find.text('Kembali ke Riwayat'), findsOneWidget);
      } else {
        expect(find.text('Sesi Selesai'), findsOneWidget);
        expect(find.text('Lihat / Edit Catatan Sesi'), findsOneWidget);
        await tester.scrollUntilVisible(
            find.text('Catatan sesi sudah tersimpan'), 180,
            scrollable: find.byType(Scrollable).first);
        expect(find.text('Catatan sesi sudah tersimpan'), findsOneWidget);
      }
      expect(find.text('Selesai pukul'), findsNothing);
      expect(find.text('Tandai Sesi Selesai'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets(
      'professional finish uses real session endpoint and renders server completion',
      (tester) async {
    final patches = <Map<String, dynamic>>[];
    await mountDetail(tester,
        role: UserRole.professional,
        data: sessionJson(attended: true),
        patches: patches);
    await tester.tap(find.text('Tandai Sesi Selesai'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(patches, [
      {'status': 'completed'}
    ]);
    expect(find.text('Sesi Selesai'), findsOneWidget);
    expect(find.text('Tandai Sesi Selesai'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('professional cannot finish without saved patient attendance',
      (tester) async {
    final patches = <Map<String, dynamic>>[];
    await mountDetail(tester,
        role: UserRole.professional, data: sessionJson(), patches: patches);
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Tandai Sesi Selesai'))
            .onPressed,
        isNull);
    expect(patches, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'server rejection keeps live state instead of inventing completion',
      (tester) async {
    await mountDetail(tester,
        role: UserRole.professional,
        data: sessionJson(attended: true),
        rejectFinish: true);
    await tester.tap(find.text('Tandai Sesi Selesai'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Sesi Konsultasi Aktif'), findsOneWidget);
    expect(find.text('Sesi Selesai'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  for (final allowed in [true, false]) {
    testWidgets(
        'future package chat requires both server text permission and active package $allowed',
        (tester) async {
      await mountDetail(tester,
          role: UserRole.patient,
          data: sessionJson(
              future: true, video: false, packageId: 'real-package'),
          access:
              BackendChatAccess(canSendText: true, hasActivePackage: allowed));
      final label =
          allowed ? 'Masuk Ruang Chat' : 'Masuk Ruang Chat (Belum Dibuka)';
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, label))
              .onPressed,
          allowed ? isNotNull : isNull);
      expect(find.text('Paket'), findsOneWidget);
      expect(find.text('Sesi 1 dari 4'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  }
  testWidgets('detail remains usable with narrow enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await mountDetail(tester,
        role: UserRole.patient,
        data: sessionJson(status: 'completed', summary: 'Ringkasan lama'),
        scale: 1.4);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('late scheduled refresh cannot undo successful server completion',
      (tester) async {
    final feed = Completer<http.Response>();
    final initial = sessionJson(attended: true);
    await mountDetail(tester,
        role: UserRole.professional, data: initial, delayedFeed: feed.future);
    await tester.tap(find.text('Tandai Sesi Selesai'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Sesi Selesai'), findsOneWidget);
    feed.complete(http.Response(
        jsonEncode({
          'sessions': [initial]
        }),
        200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Sesi Selesai'), findsOneWidget);
    expect(find.text('Tandai Sesi Selesai'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
}
