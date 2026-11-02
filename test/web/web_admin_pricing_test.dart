import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/web/screens/admin/web_admin_pricing_screen.dart';

import 'web_admin_fakes.dart';
import 'web_test_helpers.dart';

const AdminPricingItem _stubPricing = AdminPricingItem(
  professionalId: 'pro-1',
  name: 'Dr. Ayu Lestari',
  email: 'ayu@malva.test',
  specialization: 'Sp.KJ',
  quickChatPrice: 100000,
  quickVideoPrice: 200000,
  packagePrice: 500000,
);

void main() {
  group('Pengaturan harga admin', () {
    testWidgets('harga negatif ditolak dan tidak dikirim ke server',
        (WidgetTester tester) async {
      final api = FakeAdminApi(pricing: const <AdminPricingItem>[_stubPricing]);
      await pumpAdminScreen(tester, const WebAdminPricingScreen(), api: api);

      expect(find.text('Dr. Ayu Lestari'), findsOneWidget);
      expect(find.text('Rp100.000'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('price-chat')), '-100');
      await tester.pumpAndSettle();

      expect(find.text('Harga chat tidak boleh negatif.'), findsOneWidget);
      // Tombol simpan mati selama validasi gagal → tidak ada panggilan API.
      final save = find.byKey(const Key('price-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNull);
      expect(api.pricingUpdates, isEmpty);
    });

    testWidgets('harga baru disimpan setelah dialog konfirmasi',
        (WidgetTester tester) async {
      final api = FakeAdminApi(pricing: const <AdminPricingItem>[_stubPricing]);
      await pumpAdminScreen(tester, const WebAdminPricingScreen(), api: api);

      await tester.enterText(find.byKey(const Key('price-chat')), '150000');
      await tester.pumpAndSettle();

      final save = find.byKey(const Key('price-save'));
      expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(find.text('Simpan harga Dr. Ayu Lestari'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Simpan'),
        ),
      );
      await tester.pumpAndSettle();

      expect(api.pricingUpdates.length, 1);
      expect(api.pricingUpdates.single.professionalId, 'pro-1');
      expect(api.pricingUpdates.single.chat, 150000);
      // Dua harga lain tidak berubah.
      expect(api.pricingUpdates.single.video, 200000);
      expect(api.pricingUpdates.single.package, 500000);
    });

    testWidgets('harga melebihi batas server ditolak',
        (WidgetTester tester) async {
      final api = FakeAdminApi(pricing: const <AdminPricingItem>[_stubPricing]);
      await pumpAdminScreen(tester, const WebAdminPricingScreen(), api: api);

      await tester.enterText(
        find.byKey(const Key('price-video')),
        '100000001',
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Harga video maksimal Rp100.000.000.'),
        findsOneWidget,
      );
      expect(api.pricingUpdates, isEmpty);
    });
  });
}
