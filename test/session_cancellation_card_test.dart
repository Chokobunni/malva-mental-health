import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/chat/session_cancellation_card.dart';
import 'package:malva_mental_health/src/time/wib.dart';

void main() {
  setUpAll(() async {
    await (FontLoader('Roboto')
          ..addFont(rootBundle.load('assets/fonts/roboto-regular.ttf'))
          ..addFont(rootBundle.load('assets/fonts/roboto-bold.ttf')))
        .load();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
  });
  const chatCases = [
    (1, 'professional', true, 'credit', '+1 Kredit Sesi'),
    (2, 'professional', false, 'refund', 'Dana Rp 150.000 otomatis direfund'),
    (4, 'patient', true, 'credit', '+1 Kredit Sesi'),
    (
      5,
      'patient',
      true,
      'penalty',
      'Kredit Sesi pasien tidak dapat dikembalikan'
    ),
    (6, 'patient', false, 'refund', 'Dana otomatis direfund'),
    (7, 'patient', false, 'penalty', 'Dana pasien tidak dapat direfund'),
  ];
  for (final (number, role, package, outcome, copy) in chatCases) {
    testWidgets('cancellation reference $number renders at phone width',
        (tester) async {
      final capture = GlobalKey();
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto'),
          home: Scaffold(
              body: Align(
                  alignment: Alignment.topCenter,
                  child: SizedBox(
                      width: 352,
                      child: RepaintBoundary(
                          key: capture,
                          child: SessionCancellationCard(
                            message: ChatMessage(
                                id: 'cancellation',
                                senderId: role,
                                senderName: role,
                                text: '',
                                timestamp: wibFromParts(2026, 11, 27, 21, 21),
                                isMine: false,
                                kind: 'session_cancellation',
                                metadata: {
                                  'actor_role': role,
                                  'package': package,
                                  'outcome': outcome,
                                  'refund_amount': 150000,
                                  'scheduled_at': '2026-11-27T14:00:00+07:00',
                                  'session_type': 'chat',
                                  'reason': role == 'professional'
                                      ? 'Maaf, ada keperluan mendadak.'
                                      : 'Maaf, ada jadwal mendadak yang tidak bisa ditinggalkan.',
                                }),
                          )))))));
      await tester.pumpAndSettle();
      final subject = role == 'patient' ? 'Pasien' : 'Profesional';
      expect(find.text('Sesi Dibatalkan oleh $subject'), findsOneWidget);
      expect(find.text('21:21'), findsOneWidget);
      expect(find.text('Alasan pembatalan:'), findsOneWidget);
      expect(find.textContaining(copy, findRichText: true), findsOneWidget);
      expect(
          find.textContaining(
              package ? 'Jadwal Sesi Paket' : 'Sekali Sesi (Chat)',
              findRichText: true),
          findsOneWidget);
      expect(tester.takeException(), isNull);
      final folder = Platform.environment['MALVA_CHAT_QA_DIR'];
      if (folder == null) return;
      await tester.runAsync(() async {
        final boundary = capture.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        await Directory(folder).create(recursive: true);
        await File('$folder/cancellation-$number.png')
            .writeAsBytes(data!.buffer.asUint8List());
      });
    });
  }
}
