import 'package:flutter_test/flutter_test.dart';
import 'package:malva_mental_health/src/screens/care_package_screen.dart';
import 'package:malva_mental_health/src/services/malva_api_client.dart';

// ============================================================
// W4 — regresi "Lanjut Bayar" paket pending_payment.
//
// Bug: pencarian booking pending dicocokkan lewat `packageId`, padahal
// `bookings.package_id` TIDAK diisi untuk paket. Akibatnya tidak pernah cocok
// dan aplikasi membuat booking KEDUA yang ditolak server.
//
// Test ini mengunci `pickPendingPackageBooking`: harus menemukan booking
// pending berdasarkan profesional + tipe layanan + status, walau packageId
// null.
// ============================================================

BackendBooking _booking({
  required String id,
  required String professionalId,
  required String status,
  required String serviceType,
  required String bookingDate,
  String? packageId,
}) {
  return BackendBooking(
    id: id,
    patientId: 'patient_1',
    professionalId: professionalId,
    serviceType: serviceType,
    bookingDate: bookingDate,
    status: status,
    price: 100000,
    packageId: packageId,
  );
}

void main() {
  test('menemukan booking pending paket walau packageId null', () {
    final bookings = [
      // Booking pending paket — packageId SENGAJA null (persis kondisi produksi).
      _booking(
        id: 'b_pending',
        professionalId: 'profA',
        status: 'pending',
        serviceType: 'package_session',
        bookingDate: '2026-11-02',
      ),
      _booking(
        id: 'b_paid',
        professionalId: 'profA',
        status: 'paid',
        serviceType: 'package_session',
        bookingDate: '2026-11-01',
      ),
    ];

    final found = pickPendingPackageBooking(bookings, 'profA');
    expect(found, isNotNull);
    expect(found!.id, 'b_pending');
  });

  test('bila ada beberapa pending, ambil tanggal booking terbaru', () {
    final bookings = [
      _booking(
        id: 'b_old',
        professionalId: 'profA',
        status: 'pending',
        serviceType: 'package_session',
        bookingDate: '2026-11-01',
      ),
      _booking(
        id: 'b_new',
        professionalId: 'profA',
        status: 'pending',
        serviceType: 'package_session',
        bookingDate: '2026-11-05',
      ),
    ];

    expect(pickPendingPackageBooking(bookings, 'profA')!.id, 'b_new');
  });

  test('mengabaikan profesional lain dan tipe layanan lain', () {
    final bookings = [
      _booking(
        id: 'b_other_prof',
        professionalId: 'profB',
        status: 'pending',
        serviceType: 'package_session',
        bookingDate: '2026-11-02',
      ),
      _booking(
        id: 'b_quick',
        professionalId: 'profA',
        status: 'pending',
        serviceType: 'quick_consult',
        bookingDate: '2026-11-02',
      ),
    ];

    expect(pickPendingPackageBooking(bookings, 'profA'), isNull);
  });

  test('daftar kosong menghasilkan null', () {
    expect(pickPendingPackageBooking(const [], 'profA'), isNull);
  });
}
