import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/screens/pro_schedule_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

void main() {
  testWidgets('video Link copies actual saved URL without editing it',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData')
        copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    const s = BackendCareSession(
        id: 's',
        patientId: 'p',
        professionalId: 'pro',
        status: 'scheduled',
        sessionType: 'video',
        meetingUrl: 'https://meet.google.com/abc-defg-hij');
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: ProfessionalSessionActions(
                    session: s, onChanged: () async {})))));
    await tester.tap(find.text('Aksi lain'));
    await tester.pumpAndSettle();
    expect(find.text('Profil'), findsOneWidget);
    expect(find.text('Reschedule'), findsOneWidget);
    await tester.tap(find.text('Link'));
    await tester.pumpAndSettle();
    expect(copied, s.meetingUrl);
    expect(find.text('Link sesi video'), findsNothing);
    expect(find.text('Ubah link video'), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('chat actions offer full width reschedule and omit video Link',
      (tester) async {
    const s = BackendCareSession(
        id: 's', patientId: 'p', professionalId: 'pro', status: 'scheduled');
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: Scaffold(
                body: ProfessionalSessionActions(
                    session: s, onChanged: () async {})))));
    await tester.tap(find.text('Aksi lain'));
    await tester.pumpAndSettle();
    expect(find.text('Link'), findsNothing);
    expect(find.text('Ubah link video'), findsNothing);
    final reschedule =
        tester.getSize(find.widgetWithText(OutlinedButton, 'Reschedule'));
    final profile =
        tester.getSize(find.widgetWithText(OutlinedButton, 'Profil'));
    expect(reschedule.width, greaterThan(profile.width * 1.8));
    await tester.pumpWidget(const SizedBox());
  });
}
