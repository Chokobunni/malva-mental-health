# Skill: Care Session Module (Paket Care + Sesi)

Paket care 4 sesi / 6 minggu (menggantikan Continuous Support 7 hari) dan penjadwalan sesinya.

## Lokasi kode
- Handler: `backend/internal/server/handlers_care_packages.go` (paket + sesi), `handlers_care.go` (refund/kredit).
- Store: `backend/internal/store/care.go` (`CreateCarePackage`, `CreateCareSession`, `UpdateCareSessionStatus`, `RescheduleCareSession`, `RecordRefund`, `SweepCareState`).
- Konstanta: `CarePackageSessionsTotal = 4`, `CarePackageValidityDays = 42`.
- Tabel: `care_packages`, `care_sessions`, `care_refunds` (`migrations/012`, `013`, `016`).

## Endpoint
| Method | Path | Peran |
|---|---|---|
| POST | `/v1/care-packages` | pasien membeli paket (status awal `pending_payment`) |
| GET | `/v1/care-packages` | pasien/profesional |
| POST | `/v1/care-packages/{package_id}/cancel` | pasien (hanya paket `pending_payment`) |
| POST | `/v1/care-sessions` | pasien/profesional menjadwalkan sesi |
| GET | `/v1/care-sessions?scope=` | pasien/profesional |
| PATCH | `/v1/care-sessions/{session_id}` | profesional (kehadiran/ringkasan), pasien (cancel) |
| POST | `/v1/care-sessions/{session_id}/reschedule` | pasien/profesional |
| POST | `/v1/care-sessions/{session_id}/refund` | pasien/profesional/admin |
| GET | `/v1/care-refunds` | pasien/profesional/admin |

## Status sesi
`scheduled` → `completed` | `no_show` | `cancelled_by_professional` | `cancelled_by_patient` | `expired_unpaid`.
Status paket: `pending_payment` → `active` (saat booking dibayar) → `completed`/`expired`/`cancelled`.

## Pembelian paket dan retry
- Pembelian identik yang masih pending digunakan ulang per pasien/profesional; perubahan harga/jumlah/validitas saat pembelian pending ditolak sebagai konflik.
- Payload booking paket memakai `package_id`; server memvalidasi pemilik dan menurunkan profesional dari paket. Hubungan pembayaran adalah `care_packages.booking_id` (unik). Jangan pakai `bookings.package_id`, karena FK tersebut milik `service_packages` legacy.
- Booking paket terkunci pada slot/jenis sesi/harga yang sama saat retry; resume Flutter memakai booking terikat, dan tidak membuat booking baru saat pembacaan daftar gagal. Legacy hanya diadopsi bila kandidat tunggal dan harga sesuai.
- Resume legacy wajib mengikat kandidat ke paket yang dipilih melalui POST booking sebelum membuka pembayaran, dengan slot/jenis/durasi booking lama. Kandidat yang sudah terikat ke paket lain tidak boleh dipinjam.
- Aktivasi menggunakan paket yang terikat ke booking paid, termasuk replay paket yang sudah digabung. Jangan mengaktifkan pending terbaru berdasarkan pasangan pasien/profesional.
- Pembatalan pending dilakukan server secara atomik untuk paket, booking terikat, dan payment pending; booking paid tidak dapat dibatalkan melalui jalur ini.
- MyCare mempertahankan paket pending dan terminal dalam daftar dan menyediakan filter status; penggabungan tampilan paket aktif tidak menyembunyikan pembelian pending.

## Aturan mengikat (JANGAN dilanggar)
- Pasien dan profesional mengisi **Kehadiran saya** sendiri melalui PATCH `status=attended` / `absent`, sejak 10 menit sebelum jadwal. Masing-masing memiliki `patient_attendance` / `professional_attendance` dan timestamp sendiri (migrasi 032); replay pilihan sama idempoten, pilihan yang sudah dikonfirmasi tidak ditimpa. Hadir tidak menyelesaikan sesi atau mengakui pendapatan. Marker legacy `attended_marked_at` dipertahankan tanpa mengarang identitas peserta; konfirmasi hadir profesional baru juga mengisinya untuk kompatibilitas sweeper.
- Pasien **Tidak hadir** → `no_show`, kuota terpakai, tanpa pendapatan. Profesional **Tidak hadir** → `cancelled_by_professional`, kuota kembali dan ledger kredit idempoten; memenuhi jalur refund yang sudah ada. Tidak hadir seseorang tidak mengarang kehadiran peserta lainnya.
- Profesional boleh **Sesi selesai** hanya setelah durasi terjadwal berakhir. `completed`, pembatalan dan `no_show` terminal: penandaan status lain/reschedule tidak boleh membukanya kembali. Sesi hadir yang lewat durasi tetap diselesaikan sweeper; penyelesaian dan ledger pendapatan atomik.
- Chat/Meet hanya untuk `scheduled` sejak jadwal−10 menit sampai **sebelum** jadwal+durasi (`now >= end` tertutup), memakai `ServerClock` pada klien. `completed` langsung menutup akses. UI menyegarkan batas waktu, resume dan data berkala; riwayat tetap dibaca. `ChatAccess` mengirim `session_id` dan `session_ends_at` untuk tenggat composer. Profesional dapat menyelesaikan sesi terjadwal yang sudah berakhir dari riwayat.
- Respons sesi kepada pasien tidak memuat `private_note`; PATCH detail mempertahankan field yang tidak dikirim (string kosong eksplisit menghapus field).
- **Pendapatan diakui HANYA saat sesi `completed`** — bukan saat bayar lunas. `no_show` **tidak** diakui. `recognizeEarningForSession` dipanggil dalam transaksi yang sama dengan perubahan status (`care.go`).
- Pendapatan tetap satu baris per pembayaran (termasuk pembayaran paket penuh pada sesi pertama yang selesai), dilindungi kunci payment dan pemeriksaan `payment_id`; `earnings_session_unique` mencegah replay sesi. Jangan membagi ulang nominal paket dalam perbaikan lifecycle.
- **Pembatalan pasien < 24 jam** sebelum sesi → sesi **hangus**. Pasien boleh batal/reschedule hanya bila ≥ 24 jam.
- **Profesional boleh batal** kapan saja sebelum sesi mulai → kredit sesi otomatis kembali (`recordAutoCredit`, idempoten).
- **Refund uang** hanya untuk sesi `cancelled_by_professional`; nilai refund = `price / total_sessions` (`RefundValue`). Cegah double-refund (409).
- Validasi slot berlaku untuk kedua peran: di dalam jam praktik, bukan hari libur, belum terisi. Lead time 24 jam hanya untuk pasien.
- Sesi video **wajib** memakai Google Meet. Tidak ada penyedia fallback: bila pembuatan link gagal, permintaan ditolak dan bisa diulang lewat `POST /v1/care-sessions/{id}/meet-link`.
- Token Google dikelola senyap (tanpa notifikasi izin kedaluwarsa). Sweeper sepuluh menit menyegarkan access token yang tersisa ≤15 menit atau pemeliharaan tujuh hari jatuh tempo; hasil/rotasi/`last_refreshed_at` atomik. `invalid_grant` dihapus tanpa notifikasi. Batas tujuh hari Testing tidak dapat diperpanjang programatik; operator harus OAuth consent screen → Publish app. Rujukan: `docs/GOOGLE_CALENDAR_SETUP.md`, migrasi 030.
