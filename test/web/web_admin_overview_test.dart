import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/web/screens/admin/web_admin_overview_screen.dart';

import 'web_admin_fakes.dart';
import 'web_test_helpers.dart';

void main() {
  group('Ringkasan admin', () {
    testWidgets('menampilkan metrik dari /v1/admin/overview',
        (WidgetTester tester) async {
      final api = FakeAdminApi(
        overview: const AdminOverview(
          usersTotal: 42,
          usersPatients: 30,
          usersProfessionals: 11,
          usersDisabled: 1,
          paidCount: 7,
          pendingCount: 2,
          monthRevenue: 1250000,
          sessionsToday: 3,
          credentialsPending: 4,
        ),
      );
      await pumpAdminScreen(
        tester,
        WebAdminOverviewScreen(displayName: 'Admin Malva', onNavigate: (_) {}),
        api: api,
      );

      expect(find.text('Pengguna terdaftar'), findsOneWidget);
      expect(find.text('42'), findsOneWidget);
      expect(
        find.text('30 pasien · 11 profesional · 1 nonaktif'),
        findsOneWidget,
      );
      expect(find.text('Rp1.250.000'), findsOneWidget);
      expect(find.text('2 menunggu verifikasi'), findsOneWidget);
      expect(find.text('3 sesi terjadwal hari ini'), findsOneWidget);
    });

    testWidgets('gagal memuat menampilkan pesan ramah, bukan exception',
        (WidgetTester tester) async {
      final api = FakeAdminApi()
        ..failWith = const MalvaApiException('connection timeout');

      await pumpAdminScreen(
        tester,
        WebAdminOverviewScreen(displayName: 'Admin', onNavigate: (_) {}),
        api: api,
      );

      expect(
        find.textContaining('Koneksi ke server bermasalah'),
        findsOneWidget,
      );
    });
  });
}
