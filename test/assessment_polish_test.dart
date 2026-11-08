import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/screens/assessment_history_screen.dart';

void main() {
  final entries = [
    AssessmentHistoryEntry(
        kind: 'worksheet',
        title: 'who-old',
        subtitle: '',
        moduleId: 'who5',
        date: DateTime(2026, 11, 1)),
    AssessmentHistoryEntry(
        kind: 'screening',
        title: 'combined',
        subtitle: '',
        date: DateTime(2026, 11, 4)),
    AssessmentHistoryEntry(
        kind: 'worksheet',
        title: 'dass-new',
        subtitle: '',
        moduleId: 'dass21',
        date: DateTime(2026, 11, 5)),
    const AssessmentHistoryEntry(
        kind: 'worksheet',
        title: 'unknown-date',
        subtitle: '',
        moduleId: 'who5'),
  ];
  testWidgets('records provide independent instrument check chips and ordering',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AssessmentHistoryFilters(
      selected: const {'who5', 'gad7', 'phq9', 'dass21'},
      oldestFirst: false,
      onChanged: (_, __) {},
    ))));
    expect(find.byType(FilterChip), findsNWidgets(4));
    expect(find.text('Terbaru'), findsOneWidget);
    expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, 'WHO-5'))
            .selected,
        isTrue);
  });
  test(
      'instrument union keeps combined PHQ GAD as one record and missing dates last',
      () {
    expect(
        filterAssessmentHistory(entries, instruments: {'gad7'})
            .map((e) => e.title),
        ['combined']);
    expect(
        filterAssessmentHistory(entries, instruments: {'gad7', 'phq9'})
            .map((e) => e.title),
        ['combined']);
    expect(
        filterAssessmentHistory(entries,
                instruments: {'who5', 'dass21'}, oldestFirst: true)
            .map((e) => e.title),
        ['who-old', 'dass-new', 'unknown-date']);
    expect(filterAssessmentHistory(entries, instruments: {}).isEmpty, isTrue);
    expect(formatAssessmentDate(null), 'Tanggal tidak tercatat');
    expect(entries.first.title, 'who-old');
  });
}
