import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/chat/clinical_chat_card.dart';
import 'package:malva_mental_health/src/time/wib.dart';

void main() {
  testWidgets('legacy malformed metadata does not break chat rendering',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ClinicalChatCard(
      message: ChatMessage(
          id: 'old',
          senderId: 'p1',
          senderName: 'Pasien',
          text: 'Goals',
          timestamp: wibNow(),
          isMine: false,
          kind: 'goals',
          metadata: {'goals': 'bad', 'goal_ids': 1, 'size': 'unknown'}),
      isPatient: false,
    ))));
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'summary shows complete saved content inline without detail action',
      (tester) async {
    var opened = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ClinicalChatCard(
      message: ChatMessage(
          id: 'm1',
          senderId: 'pro1',
          senderName: 'Dokter',
          text: 'Rangkuman sesi',
          timestamp: wibFromParts(2026, 11, 6, 13, 8),
          isMine: false,
          kind: 'session_summary',
          metadata: {
            'goal_ids': ['g1'],
            'goals': [
              {'id': 'g1', 'title': 'Latihan napas', 'target_per_week': 4}
            ],
            'insight': 'Praktikkan perlahan.',
          }),
      isPatient: true,
      onAction: () => opened = true,
    ))));
    expect(find.text('Latihan napas'), findsOneWidget);
    expect(find.text('Praktikkan perlahan.'), findsOneWidget);
    expect(find.text('Detail Record'), findsOneWidget);
    expect(find.text('Rangkuman Sesi'), findsOneWidget);
    expect(find.text('Catatan & Target Konseling'), findsOneWidget);
    expect(find.text('Target: 4x / minggu'), findsOneWidget);
    expect(find.text('06/11/2026'), findsOneWidget);
    expect(find.text('13:08'), findsOneWidget);
    expect(find.text('Lihat detail'), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    await tester.tap(find.text('Latihan napas'));
    expect(opened, isFalse);
  });
  testWidgets('assessment action is available only to receiving patient',
      (tester) async {
    final message = ChatMessage(
        id: 'm1',
        senderId: 'pro1',
        senderName: 'Dokter',
        text: 'Permintaan asesmen',
        timestamp: wibNow(),
        isMine: false,
        kind: 'assessment_request',
        metadata: {'module_id': 'who5'});
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ClinicalChatCard(
                message: message, isPatient: false, onAction: () {}))));
    expect(find.text('Isi assessment'), findsNothing);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ClinicalChatCard(
                message: message, isPatient: true, onAction: () {}))));
    expect(find.text('WHO-5'), findsOneWidget);
    expect(find.text('Isi assessment'), findsOneWidget);
  });
}
