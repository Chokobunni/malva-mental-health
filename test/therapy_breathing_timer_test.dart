import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/widgets/therapy_library.dart';

void main() {
  testWidgets('breathing advances 4-2-6 and counts only completed cycles',
      (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: TherapyDetailScreen(module: breathingModule)),
    ));
    final start = find.text('Mulai');
    await tester.scrollUntilVisible(start, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(start);
    await tester.pump();
    expect(find.text('Tarik Napas'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Tahan Napas'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Hembuskan Perlahan'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    expect(find.text('Tarik Napas'), findsOneWidget);
    expect(find.text('1/3 Terisi'), findsOneWidget);
    await tester.tap(find.text('Berhenti'));
    await tester.pump();
    expect(start, findsOneWidget);
    await tester.tap(start);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 12));
    expect(tester.takeException(), isNull);
  });
}
