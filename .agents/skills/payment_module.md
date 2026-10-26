# Skill: Payment Module (Midtrans + Simulasi)

Pembayaran konsultasi/paket via Midtrans Snap, dengan mode simulasi untuk dev/test.

## Lokasi kode
- Gateway: `backend/internal/payment/midtrans.go` (`NewMidtransGateway`, `CreateTransaction`, `ParseWebhook`, `VerifySignature`, `MidtransSignature`).
- Handler: `backend/internal/server/handlers_booking.go` (`createPayment`, `markPaymentPaid`, `paymentWebhook`, `activatePaidBooking`).
- Store: `CreatePayment`, `MarkPaymentPaid`, `UpdatePaymentGateway`, `RecordPaymentEvent`, `PaymentEventStatus`, `AuthorizePaymentByReference`.
- Tabel: `payments`, `payment_events` (`migrations/013`).
- Config: `internal/config/config.go` (`PaymentMode`, `MidtransServerKey/ClientKey/Env/SnapBase`).

## Endpoint
| Method | Path | Auth | Catatan |
|---|---|---|---|
| POST | `/v1/payments` | bearer (pasien pemilik booking) | buat payment + (mode gateway) transaksi Snap |
| POST | `/v1/payments/mark-paid` | bearer | **hanya mode `simulation`**; di `gateway` → 410 |
| POST | `/v1/webhooks/payment` | **signature** (publik) | verifikasi SHA-512, idempoten via `payment_events` |

## Aturan mengikat
- **Denominasi: Rupiah utuh (IDR), TANPA `*100`.** `gross_amount` Midtrans = nilai rupiah apa adanya. (Beda dari konvensi POS hepipay.)
- Breakdown di `createPayment`: `consultation = booking.Price`, `platform_fee = price * 10 / 100`, `service_fee = 2000`, `net_to_doctor = gross - platform_fee`. Nilai Snap yang dikirim = `gross + service_fee`. **Harga dihitung server**, bukan dari klien.
- Signature Midtrans = `sha512(order_id + status_code + gross_amount + serverKey)`; verifikasi waktu-konstan. Tidak cocok → **401 tanpa efek**.
- Idempoten: event disimpan di `payment_events`. Hanya event berstatus `processed` yang dianggap selesai; selain itu diproses ulang (jangan telan kegagalan jadi pembayaran hilang).
- Event `settlement`/`capture` (fraud `accept`) → `MarkPaymentPaid` + `activatePaidBooking`. `expire/cancel/deny` → `ignored`.
- **Pendapatan profesional TIDAK diakui saat bayar** — diakui saat sesi `completed` (lihat care_session_module).
- Otorisasi sebelum mutasi: `AuthorizePaymentByReference` wajib sebelum `MarkPaymentPaid` (cegah 403 yang terlanjur menandai lunas).
- Gateway aktif bila `MALVA_PAYMENT_MODE=gateway` (wajib server key) atau server key diisi manual. Tanpa gateway → `s.payment = nil`.
