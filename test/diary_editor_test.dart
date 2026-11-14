import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/models/diary_content.dart';
import 'package:malva_mental_health/src/screens/diary_history_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

void main() {
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  testWidgets(
      'Tambah opens full diary page with font tools and preserves failed draft',
      (tester) async {
    var fail = true;
    Map<String, dynamic>? saved;
    final api = MalvaApiClient(httpClient: MockClient((r) async {
      if (r.method == 'GET') return http.Response('{"diaries":[]}', 200);
      if (fail) return http.Response('{"error":"Sementara gagal"}', 503);
      saved = jsonDecode(r.body) as Map<String, dynamic>;
      return http.Response(
          jsonEncode({
            'diary': {...saved!, 'id': 'saved'}
          }),
          201);
    }));
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: buildMalvaTheme(),
            home: DiaryHistoryScreen(
                apiClient: api,
                session: const AuthSession(
                    role: UserRole.patient,
                    identifier: 'p',
                    displayName: 'P',
                    accessToken: 'test')))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tambah'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byTooltip('Tambah media'), findsOneWidget);
    expect(find.byTooltip('Menggambar'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextField, 'Judul'), 'Hari baru');
    await tester.enterText(
        find.widgetWithText(TextField, 'Catatan diary'), 'Cerita saya');
    await tester.tap(find.byTooltip('Pengaturan font'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('H2'));
    await tester.tap(find.byTooltip('Rata tengah'));
    await tester.tap(find.byTooltip('Selesai mengatur font'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(find.text('Cerita saya'), findsOneWidget);
    expect(find.textContaining('Diary belum tersimpan'), findsWidgets);
    fail = false;
    await tester.tap(find.text('Simpan'));
    await tester.pumpAndSettle();
    expect(find.text('My Diary History'), findsOneWidget);
    final content = DiaryContent.parse(saved!['note'] as String);
    expect(content.text, 'Cerita saya');
    expect(content.size, 24);
    expect(content.align, TextAlign.center);
  });
}
