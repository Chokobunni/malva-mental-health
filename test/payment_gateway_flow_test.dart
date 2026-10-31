import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:malva_mental_health/src/models.dart';
import 'package:malva_mental_health/src/providers/auth_providers.dart';
import 'package:malva_mental_health/src/screens/booking/payment_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';
import 'package:malva_mental_health/src/theme.dart';

// ============================================================
// PEMBAYARAN MODE GATEWAY (MIDTRANS)
//
// Aturan bisnis yang dikunci:
//   - Saat `createPayment` mengembalikan `redirect_url` (mode gateway), klien
//     TIDAK memanggil `markPaymentPaid` (server membalas 410). Pembayaran
//     dikonfirmasi webhook Midtrans dan status dipantau lewat
//     `GET /v1/payments/{reference}`.
//   - Belum dibayar bukan kegagalan: layar menampilkan keadaan "Menunggu
//     pembayaran" dengan tombol cek status / buka halaman pembayaran.
//   - Status berubah `paid` -> pindah ke layar sukses.
//   - Mode gateway menyembunyikan grid metode lokal (metode dipilih di
//     halaman Midtrans).
// ============================================================

const _patientSession = AuthSession(
  role: UserRole.patient,
  identifier: 'pasien@malva.app',
  displayName: 'Pasien',
  backendUserId: 'user_pasien_1',
  accessToken: 'token_test',
);

const _redirectUrl = 'https://app.sandbox.midtrans.com/snap/v4/redirection/abc';

BackendBooking _booking() => BackendBooking.fromJson(<String, dynamic>{
      'id': 'booking_1',
      'patient_id': 'user_pasien_1',
      'professional_id': 'user_pro_1',
      'service_type': 'quick_consult',
      'booking_date': '2099-01-02',
      'status': 'pending',
      'price': 150000,
    });

http.Response _json(Object body, {int status = 200}) => http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json'},
    );

Widget _wrap(MalvaApiClient api, Widget child) {
  final container = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(api)],
  );
  addTearDown(container.dispose);
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: buildMalvaTheme(), home: child),
  );
}

/// Fake backend untuk alur gateway. `statusSequence` menentukan jawaban
/// `GET /v1/payments/{reference}` (default: selalu pending).
class _GatewayBackend {
  _GatewayBackend({this.statusSequence = const ['pending']});

  final List<String> statusSequence;
  int markPaidCalls = 0;
  int statusCalls = 0;

  http.Client client() {
    return _FakeClient((request) async {
      final key = '${request.method} ${request.url.path}';
      if (key == 'GET /v1/config/payment') {
        return _json(
            {'mode': 'gateway', 'provider': 'midtrans', 'env': 'sandbox'});
      }
      if (key == 'POST /v1/payments') {
        return _json({
          'payment': {
            'id': 'pay_1',
            'booking_id': 'booking_1',
            'reference': 'TXN-1',
            'status': 'pending',
            'redirect_url': _redirectUrl,
            'snap_token': 'snap-token-1',
          },
          'breakdown': const {},
        }, status: 201);
      }
      if (key == 'POST /v1/payments/mark-paid') {
        markPaidCalls++;
        return _json(
            {'error': 'mark-paid dinonaktifkan; gunakan gateway (webhook)'},
            status: 410);
      }
      if (key == 'GET /v1/payments/TXN-1') {
        final index = statusCalls < statusSequence.length
            ? statusCalls
            : statusSequence.length - 1;
        statusCalls++;
        return _json({
          'payment': {
            'id': 'pay_1',
            'booking_id': 'booking_1',
            'reference': 'TXN-1',
            'status': statusSequence[index],
            'redirect_url': _redirectUrl,
          },
          'session_id': statusSequence[index] == 'paid' ? 'sess_1' : '',
        });
      }
      return _json({'error': 'unexpected $key'}, status: 404);
    });
  }
}

class _FakeClient extends http.BaseClient {
  _FakeClient(this.handler);

  final FutureOr<http.Response> Function(http.Request request) handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final body = request is http.Request ? request.body : '';
    final replay = http.Request(request.method, request.url)
      ..headers.addAll(request.headers)
      ..body = body;
    final response = await handler(replay);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      request: request,
    );
  }
}

MalvaApiClient _api(_GatewayBackend backend) => MalvaApiClient(
      baseUrl: 'http://backend.test',
      httpClient: backend.client(),
    );

Widget _screen(MalvaApiClient api) => PaymentScreen(
      booking: _booking(),
      doctorName: 'dr. Hafid',
      session: _patientSession,
      apiClient: api,
    );

void main() {
  testWidgets(
      'redirect_url ada → markPaymentPaid TIDAK dipanggil, keadaan menunggu',
      (tester) async {
    final backend = _GatewayBackend();
    final api = _api(backend);

    await tester.pumpWidget(_wrap(api, _screen(api)));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Bayar Sekarang'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(backend.markPaidCalls, 0,
        reason: 'mode gateway tidak boleh memanggil mark-paid (server 410)');
    expect(find.text('Menunggu pembayaran'), findsOneWidget);
    expect(find.text('Cek status'), findsOneWidget);
    expect(find.text('Buka halaman pembayaran'), findsOneWidget);
    // Tombol bayar diganti panel menunggu.
    expect(find.widgetWithText(FilledButton, 'Bayar Sekarang'), findsNothing);

    // Tidak ada error merah: belum bayar bukan kegagalan.
    expect(find.textContaining('tidak selesai'), findsNothing);
  });

  testWidgets('status berubah paid → pindah ke layar sukses', (tester) async {
    final backend = _GatewayBackend(statusSequence: const ['pending', 'paid']);
    final api = _api(backend);

    await tester.pumpWidget(_wrap(api, _screen(api)));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Bayar Sekarang'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Menunggu pembayaran'), findsOneWidget);

    // Polling pertama (masih pending) lalu polling berikutnya: paid.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.text('Payment Received!'), findsOneWidget,
        reason: 'status paid harus membawa pasien ke layar sukses');
    expect(find.text('Menunggu pembayaran'), findsNothing);
  });

  testWidgets('mode gateway menyembunyikan grid metode lokal', (tester) async {
    final backend = _GatewayBackend();
    final api = _api(backend);

    await tester.pumpWidget(_wrap(api, _screen(api)));
    await tester.pumpAndSettle();

    // Grid e-wallet/bank tidak ditampilkan; diganti keterangan Midtrans.
    expect(find.text('E-Wallet'), findsNothing);
    expect(find.text('Virtual Account, Bank & QRIS'), findsNothing);
    expect(find.text('BCA Virtual Account'), findsNothing);
    expect(find.text('GoPay'), findsNothing);
    expect(
      find.text('GoPay, QRIS, Virtual Account & kartu'),
      findsOneWidget,
      reason:
          'mode gateway harus menjelaskan metode dipilih di halaman Midtrans',
    );
  });

  testWidgets('status cancelled → pesan jelas & tombol bayar muncul lagi',
      (tester) async {
    final backend = _GatewayBackend(statusSequence: const ['cancelled']);
    final api = _api(backend);

    await tester.pumpWidget(_wrap(api, _screen(api)));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Bayar Sekarang'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    expect(find.textContaining('Pembayaran tidak selesai'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Bayar Sekarang'), findsOneWidget,
        reason: 'pasien harus bisa mencoba lagi setelah pembayaran batal');
  });
}
