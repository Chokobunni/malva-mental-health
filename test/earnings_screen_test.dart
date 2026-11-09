import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/screens/portal/earnings_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

void main() {
  testWidgets('earnings starts at payout and preserves balance and withdrawal',
      (tester) async {
    var pending = 401602;
    final withdrawals = <http.Request>[];
    final api = MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: MockClient((request) async {
        if (request.method == 'POST') {
          withdrawals.add(request);
          pending = 0;
          return http.Response('{"count":2,"net_amount":401602}', 200);
        }
        return http.Response(
            jsonEncode({
              'summary': {
                'total_sessions': 2,
                'gross_amount': 500000,
                'platform_fee': 98398,
                'net_amount': 401602,
                'pending_net': pending,
              },
              'transactions': [
                {
                  'id': 'earning',
                  'reference': 'TXN-REAL',
                  'payment_method': 'malva_bank',
                  'net': 200801,
                }
              ],
            }),
            200);
      }),
    );
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        theme: buildMalvaTheme(),
        home: EarningsScreen(
          session: const AuthSession(
            role: UserRole.professional,
            identifier: 'professional',
            displayName: 'Professional',
            accessToken: 'professional-token',
          ),
          apiClient: api,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Total'), findsNothing);
    expect(find.text('All time'), findsNothing);
    expect(tester.getTopLeft(find.text('Payout')).dy, lessThan(130));
    expect(find.text('Balance: Rp 401.602'), findsOneWidget);
    expect(find.text('TXN-REAL'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'BCA');
    await tester.enterText(find.byType(TextField).last, '1234567890');
    await tester.tap(find.text('Request Payout'));
    await tester.pumpAndSettle();
    expect(withdrawals.single.url.path, '/v1/earnings/payout');
    expect(withdrawals.single.headers['Authorization'],
        'Bearer professional-token');
    expect(jsonDecode(withdrawals.single.body),
        {'bank': 'BCA', 'account': '1234567890'});
    expect(find.text('Balance: Rp 0'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Request Payout'))
            .onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });
}
