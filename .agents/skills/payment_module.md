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
- Rekonsiliasi `GET /v2/{order_id}/status` langsung ke API HTTPS Midtrans memakai server-key Basic auth sebagai sumber otoritatif; jangan mensyaratkan signature webhook pada respons GET. `order_id` respons wajib persis sama dengan reference permintaan; nominal dan fraud tetap diverifikasi sebelum menandai paid. Webhook masuk tetap wajib signature valid. Rujukan: [verifikasi GET Status API](https://docs.midtrans.com/docs/https-notification-webhooks#verify-using-get-status-api-call).
- Kode body status GET non-200 diterima hanya untuk pasangan `201/pending`, `202/deny`, dan `407/expire`, dengan order yang cocok. `settlement/capture` wajib kode `200`; kode/kombinasi tak dikenal dan transaksi belum ada (`404`) tetap pending.
- Idempoten: event disimpan di `payment_events`. Hanya event berstatus `processed` yang dianggap selesai; selain itu diproses ulang (jangan telan kegagalan jadi pembayaran hilang).
- Event `settlement`/`capture` (fraud `accept`) → `MarkPaymentPaid` + `activatePaidBooking`, hanya bila jumlah sama dengan gross + service fee. `expire/cancel/deny` menyimpan status terminal payment lalu event `ignored`.
- Retry booking/pembayaran memakai identitas yang sama: booking terkunci saat pemilihan payment dan inisialisasi gateway; payment pending (termasuk belum punya token) atau paid digunakan ulang. Payment paid yang lebih lama menang atas pending legacy yang lebih baru.
- Resume dengan access token kedaluwarsa memakai token hasil refresh untuk retry dan permintaan berikutnya yang masih membawa token lama. Endpoint refresh tidak boleh me-refresh dirinya sendiri; hasil terlambat dari generasi akun lain ditolak. Rotasi token memperbarui sesi aktif dan secure storage secara terserialisasi pada mobile/web tanpa menghapus data akun yang sudah dimuat.
- Kegagalan respons Snap tetap mengembalikan payment pending dengan reference yang dapat direkonsiliasi. Jangan membuat order/reference baru otomatis. Jika provider menerima order tetapi token hilang, retry memakai reference sama; status backend dapat mengonfirmasi pembayaran, tetapi pemulihan token dapat memerlukan bantuan operator.
- Android sandbox memakai checkout WebView milik aplikasi (`malva/payment`), dengan tombol kembali dan penutupan setelah backend mengonfirmasi paid. Callback Snap `malva://payment/return?reference=...` hanya memicu pemeriksaan status backend terautentikasi; query status callback tidak boleh menandai lunas. Produksi membuka browser eksternal.
- Pembatalan paket pending membatalkan booking/payment lokal secara atomik. Pembatalan lokal tidak membatalkan transaksi provider; settlement terlambat tetap cancelled, tidak mengaktifkan sesi, dan mengirim notifikasi rekonsiliasi yang dideduplikasi.
- **Pendapatan profesional TIDAK diakui saat bayar** — diakui saat sesi `completed` (lihat care_session_module).
- Otorisasi sebelum mutasi: `AuthorizePaymentByReference` wajib sebelum `MarkPaymentPaid` (cegah 403 yang terlanjur menandai lunas).
- Gateway aktif bila `MALVA_PAYMENT_MODE=gateway` (wajib server key) atau server key diisi manual. Tanpa gateway → `s.payment = nil`.
