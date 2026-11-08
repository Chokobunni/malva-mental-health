import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/platform/contracts/ports.dart';
import 'package:malva_mental_health/src/platform/platform_providers.dart';
import 'package:malva_mental_health/src/screens/more_screen.dart';

class _PdfPort implements FileExporter {
  final names = <String>[];
  bool reject = false;
  @override
  Future<void> saveBytes(
      {required String filename,
      required Uint8List bytes,
      required String mimeType,
      String? subject}) async {
    if (reject) throw StateError('synthetic save failure');
    expect(filename.endsWith('.pdf'), isTrue);
    expect(mimeType, 'application/pdf');
    expect(latin1.decode(bytes).startsWith('%PDF-'), isTrue);
    names.add(filename);
  }

  @override
  Future<void> saveText(
          {required String filename,
          required String content,
          required String mimeType,
          String? subject}) async =>
      fail('PDF must be binary');
}

void main() {
  testWidgets('all five export actions generate actual PDF files',
      (tester) async {
    final port = _PdfPort();
    await tester.pumpWidget(ProviderScope(
      overrides: [fileExporterProvider.overrideWithValue(port)],
      child: MaterialApp(home: MoreScreen(onLogout: () {})),
    ));
    await tester.pumpAndSettle();
    final actions = {
      'Export Mood History': 'mood_history',
      'Export Screening Results': 'screenings',
      'Export Medication Log': 'medication_log',
      'Export Diary Entries': 'diary',
      'Export All Data (PDF)': 'full_export',
    };
    for (final action in actions.entries) {
      await tester.ensureVisible(find.text(action.key));
      await tester.tap(find.text(action.key));
      await tester.pumpAndSettle();
      expect(port.names.last, 'malva_${action.value}.pdf');
    }
    expect(port.names.length, 5);
    expect(find.text('Pengaturan Privasi'), findsNothing);
    expect(find.byType(SwitchListTile), findsNothing);
    expect(find.text('Consent Management'), findsOneWidget);
  });

  testWidgets('PDF save failure is visible and permits retry', (tester) async {
    final port = _PdfPort()..reject = true;
    await tester.pumpWidget(ProviderScope(
      overrides: [fileExporterProvider.overrideWithValue(port)],
      child: MaterialApp(home: MoreScreen(onLogout: () {})),
    ));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Export Mood History'));
    await tester.tap(find.text('Export Mood History'));
    await tester.pumpAndSettle();
    expect(find.textContaining('PDF belum dapat dibuat'), findsOneWidget);
    port.reject = false;
    await tester.tap(find.text('Export Mood History'));
    await tester.pumpAndSettle();
    expect(port.names, ['malva_mood_history.pdf']);
  });
}
