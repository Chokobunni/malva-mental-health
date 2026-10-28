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

## Aturan mengikat (JANGAN dilanggar)
- **Pendapatan diakui HANYA saat sesi `completed`** — bukan saat bayar lunas. `no_show` **tidak** diakui. `recognizeEarningForSession` dipanggil dalam transaksi yang sama dengan perubahan status (`care.go`).
- 1 sesi `completed` = 1 baris `earnings` (idempoten via unique `earnings_session_unique`).
- **Pembatalan pasien < 24 jam** sebelum sesi → sesi **hangus**. Pasien boleh batal/reschedule hanya bila ≥ 24 jam.
- **Profesional boleh batal** kapan saja sebelum sesi mulai → kredit sesi otomatis kembali (`recordAutoCredit`, idempoten).
- **Refund uang** hanya untuk sesi `cancelled_by_professional`; nilai refund = `price / total_sessions` (`RefundValue`). Cegah double-refund (409).
- Validasi slot berlaku untuk kedua peran: di dalam jam praktik, bukan hari libur, belum terisi. Lead time 24 jam hanya untuk pasien.
- Sesi video **wajib** memakai Google Meet. Tidak ada penyedia fallback: bila pembuatan link gagal, permintaan ditolak dan bisa diulang lewat `POST /v1/care-sessions/{id}/meet-link`.
