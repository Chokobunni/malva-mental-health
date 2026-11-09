import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/assessment_history_screen.dart';
import 'package:malva_mental_health/src/screens/portal/professional_assessment_history_screen.dart';
import 'package:malva_mental_health/src/web/services/web_assessment_service.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

void main() {
  testWidgets(
      'partial professional history keeps known score and unknown detail',
      (tester) async {
    final api = MalvaApiClient(
        baseUrl: 'http://backend.test',
        httpClient: MockClient((request) async {
          final data = request.url.path == '/v1/patient-professional-links'
              ? {
                  'links': [
                    {
                      'patient_id': 'patient',
                      'patient_display_name': 'Pasien',
                      'status': 'active'
                    }
                  ]
                }
              : {
                  'screenings': [
                    {
                      'id': 'screening',
                      'overall_level': 'minimal',
                      'bundle': {
                        'gad7': {'score': 7, 'max_score': 21}
                      }
                    }
                  ]
                };
          return http.Response(jsonEncode(data), 200);
        }));
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            home: ProfessionalAssessmentHistoryScreen(
      apiClient: api,
      session: const AuthSession(
          role: UserRole.professional,
          identifier: 'professional',
          displayName: 'Profesional',
          accessToken: 'synthetic'),
    ))));
    await tester.pumpAndSettle();
    expect(find.text('7/21'), findsOneWidget);
    expect(find.text('-1/27'), findsNothing);
    expect(find.text('Belum tersedia'), findsWidgets);
    await tester.tap(find.text('7/21'));
    await tester.pumpAndSettle();
    expect(find.text('PHQ-9 • Belum tersedia'), findsOneWidget);
    expect(find.text('GAD-7 • 7/21'), findsOneWidget);
  });
  for (final malformed in [null, 'invalid', <Object>[]]) {
    test('malformed instrument object stays partial and unknown ($malformed)',
        () {
      final session = BackendScreeningSession.fromJson({
        'overall_level': 'minimal',
        'bundle': {
          'phq9': malformed,
          'gad7': {'score': 7, 'max_score': 21},
        }
      });
      expect(session.phq9.score, -1);
      expect(session.gad7.level, 'mild');
      expect(session.overallLevel, isEmpty);
      expect(screeningScoreSummary(session), contains('PHQ-9 Belum tersedia'));
      expect(webHistoryFromScreening(session).scoreText,
          contains('PHQ-9 Belum tersedia'));
    });
  }
  for (final value in [
    (0, 'minimal', 'minimal'),
    (4, 'minimal', 'minimal'),
    (5, 'mild', 'mild'),
    (9, 'mild', 'mild'),
    (10, 'moderate', 'moderate'),
    (14, 'moderate', 'moderate'),
    (15, 'moderately_severe', 'severe'),
    (19, 'moderately_severe', 'severe'),
    (20, 'severe', 'severe'),
    (21, 'severe', 'severe'),
  ]) {
    test(
        'validated totals ${value.$1} override stale instrument/overall labels',
        () {
      final session = BackendScreeningSession.fromJson({
        'overall_level': 'minimal',
        'bundle': {
          'phq9': {'score': value.$1, 'max_score': 27, 'level': 'minimal'},
          'gad7': {'score': value.$1, 'max_score': 21, 'level': 'minimal'},
        }
      });
      expect(session.phq9.level, value.$2);
      expect(session.gad7.level, value.$3);
      expect(session.overallLevel, value.$3);
    });
  }
  for (final instrument in [('phq9', 27), ('gad7', 21)]) {
    for (final invalid in [null, -1, instrument.$2 + 1, 2.5, '7']) {
      test('${instrument.$1} malformed score stays unknown ($invalid)', () {
        final summary = BackendAssessmentSummary.fromJson({
          'type': instrument.$1,
          'score': invalid,
          'max_score': instrument.$2,
          'level': 'minimal',
        });
        expect(summary.score, -1);
        expect(summary.level, isEmpty);
      });
    }
    test('${instrument.$1} mismatched maximum stays unknown', () {
      final summary = BackendAssessmentSummary.fromJson({
        'type': instrument.$1,
        'score': 7,
        'max_score': 100,
        'level': 'minimal',
      });
      expect(summary.score, -1);
      expect(summary.level, isEmpty);
    });
  }
}
