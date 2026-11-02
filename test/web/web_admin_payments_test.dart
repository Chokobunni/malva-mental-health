import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/web/screens/admin/web_admin_payments_screen.dart';

import 'web_admin_fakes.dart';
import 'web_test_helpers.dart';

/// Satu transaksi pending sebagai data stub (tanpa HTTP).
final AdminPaymentItem _stubPending = AdminPaymentItem(
  id: 'pay-1',
  reference: 'INV-2026-0001',
  status: 'pending',
  paymentMethod: 'qris',
  grossAmount: 250000,
  serviceFeeAmount: 15000,
  platformFeeAmount: 10000,
  netAmount: 225000,
  createdAt: DateTime.parse('2026-11-02T09:30:00+07:00'),
  patientName: 'Rani Pertiwi',
  patientEmail: 'rani@malva.test',
  professionalName: 'Dr. Ayu Lestari',
  sessionType: 'quick_video',
  bookingDate: '2026-11-05',
  slotTime: '10:00:00',
);

AdminPaymentPage _stubPage() => AdminPaymentPage(
      items: <AdminPaymentItem>[_stubPending],
      total: 1,
      summary: const AdminPaymentSummary(
        pending: 1,
        paid: 0,
        failed: 0,
        refunded: 0,
        grossPaid: 0,
      ),
    );

AdminPaymentDetail _stubDetail() => AdminPaymentDetail(
      payment: _stubPending,
      events: <AdminPaymentEvent>[
        AdminPaymentEvent(
          gateway: 'midtrans',
          externalId: 'ext-1',
          eventType: 'settlement',
          status: 'pending',
          createdAt: DateTime.parse('2026-11-02T09:35:00+07:00'),
        ),
      ],
      refunds: const <AdminRefundItem>[],
    );

void main() {
  group('Tabel pembayaran admin', () {
    testWidgets('menampilkan data transaksi dari server (rupiah & WIB)',
        (WidgetTester tester) async {
      final api = FakeAdminApi(page: _stubPage(), detail: _stubDetail());
      await pumpAdminScreen(tester, const WebAdminPaymentsScreen(), api: api);

      expect(find.text('INV-2026-0001'), findsOneWidget);
      expect(find.text('Rani Pertiwi'), findsOneWidget);
      expect(find.text('Dr. Ayu Lestari'), findsOneWidget);
      expect(find.text('Rp250.000'), findsOneWidget);
      // Waktu ditampilkan dalam WIB (dd/MM/yyyy HH:mm).
      expect(find.text('02/11/2026 09:30'), findsOneWidget);
      expect(find.textContaining('dari 1'), findsOneWidget);
    });

    testWidgets('error server ditampilkan sebagai pesan ramah',
        (WidgetTester tester) async {
      final api = FakeAdminApi()
        ..failWith = const MalvaApiException('internal server error');

      await pumpAdminScreen(tester, const WebAdminPaymentsScreen(), api: api);

      expect(
        find.textContaining('Server sedang bermasalah'),
        findsOneWidget,
      );
    });
  });

  group('Override pembayaran', () {
    testWidgets('dialog override mewajibkan alasan sebelum mengirim',
        (WidgetTester tester) async {
      final api = FakeAdminApi(page: _stubPage(), detail: _stubDetail());
      await pumpAdminScreen(tester, const WebAdminPaymentsScreen(), api: api);

      await tester.tap(find.text('Detail'));
      await tester.pumpAndSettle();
      expect(find.text('EVENT GATEWAY'), findsOneWidget);

      await tester.tap(find.byKey(const Key('web-payment-mark-paid')));
      await tester.pumpAndSettle();

      // Tombol konfirmasi terkunci selama alasan kosong.
      final confirm = find.byKey(const Key('web-reason-confirm'));
      expect(confirm, findsOneWidget);
      expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

      await tester.enterText(
        find.byKey(const Key('web-reason-field')),
        'verifikasi manual webhook telat',
      );
      await tester.pumpAndSettle();
      expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);

      await tester.tap(confirm);
      await tester.pumpAndSettle();
      expect(find.text('Konfirmasi perubahan status'), findsOneWidget);

      await tester.tap(find.text('Ya, ubah status'));
      await tester.pumpAndSettle();

      expect(api.overrides.length, 1);
      expect(api.overrides.single.paymentId, 'pay-1');
      expect(api.overrides.single.status, 'paid');
      expect(api.overrides.single.reason, 'verifikasi manual webhook telat');
    });

    testWidgets('refund hanya tersedia untuk transaksi lunas',
        (WidgetTester tester) async {
      const paid = AdminPaymentItem(
        id: 'pay-2',
        reference: 'INV-2026-0002',
        status: 'paid',
        paymentMethod: 'qris',
        grossAmount: 300000,
        serviceFeeAmount: 0,
        platformFeeAmount: 0,
        netAmount: 300000,
        patientName: 'Budi',
        professionalName: 'Dr. Ayu',
      );
      final api = FakeAdminApi(
        page: const AdminPaymentPage(
          items: <AdminPaymentItem>[paid],
          total: 1,
          summary: AdminPaymentSummary(
            pending: 0,
            paid: 1,
            failed: 0,
            refunded: 0,
            grossPaid: 300000,
          ),
        ),
        detail: const AdminPaymentDetail(
          payment: paid,
          events: <AdminPaymentEvent>[],
          refunds: <AdminRefundItem>[],
        ),
      );
      await pumpAdminScreen(tester, const WebAdminPaymentsScreen(), api: api);

      await tester.tap(find.text('Detail'));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('web-payment-refund')), findsOneWidget);
      expect(find.byKey(const Key('web-payment-mark-paid')), findsNothing);
    });
  });
}
