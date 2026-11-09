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
- **Ulasan:** satu per sesi satu kali `completed`, atau satu per paket setelah
  `completed`/`no_show` menghabiskan kuota pembelian, tanpa sesi scheduled/pending
  dalam rentang pembelian dan minimal satu completed. Saldo merged 4+4 tetap 8,
  tetapi ID pembelian awal/merged mendapat masing-masing satu hak. Kuota awal
  adalah total target dikurangi semua kuota child merged; sesi pemakai kuota
  diurut scheduled_at,id dan dibagi rentang awal lalu merged_at,created_at,id.
  Hak renewal menunggu semua pertemuan pemakai kuota sebelumnya terminal agar
  absensi profesional yang terlambat/credit replacement tidak menggeser hak terpakai.
  Ownership/rantai merge/kuota ambigu ditolak konservatif. Tidak ada ulasan per pertemuan paket atau
  paket seluruhnya no-show. `GET /v1/review-entitlements` pasien membaca unit yang
  belum dipakai; POST review menerima `session_id`/`care_package_id` opsional,
  klien lama memilih unit tertua. Store mengunci pasangan dalam transaksi dan
  index unik migrasi 035 mencegah replay/paralel. Ulasan legacy tidak dibackfill;
  unit selesai pada/sebelum ulasan legacy terakhir pasangan ditekan konservatif
  (created_at NULL menutup semua sampai rekonsiliasi); unit sesudahnya tersedia.
  Prompt pasien pada refresh/resume/poll hanya sekali per akun/unit selama sesi
  aplikasi; aksi manual tetap tersedia setelah dialog ditutup. Tidak ada push baru.
- Home pasien/profesional menampilkan sesi video dan chat terdekat; dropdown membuka seluruh sesi mendatang. Kartu tetap mematuhi jendela akses server. Messages profesional memakai daftar percakapan yang sama dengan pasien.
- Feed HTTP sesi mempertahankan semua scheduled; upcoming/today/ongoing terurut terdekat dahulu. Past/all menyertakan seluruh scheduled dan maksimal 100 riwayat lain. Jangan memotong sesi mendatang atau sesi perlu diselesaikan sebelum klien menyusun kartu. Method store bounded `ListCareSessions` tetap mempertahankan limit/urutan lamanya.
- Jadwal profesional menampilkan sesi terjadwal yang sudah lewat durasi pada bagian **Perlu diselesaikan**, sebelum riwayat dan tanpa batas sepuluh item. **Selesaikan sesi** tidak muncul sebelum akhir jadwal; Quick Video Call ikut menggulir dengan konten jadwal. Jangan tampilkan judul kehadiran tanpa isi pada sesi mendatang atau terminal.
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
- Payload jadwal/reschedule kedua peran adalah wall-clock WIB `yyyy-MM-ddTHH:mm`. Hasil pemilih pasien membawa akhiran `|chat`/`|video` untuk keperluan UI; pisahkan akhiran tersebut sebelum mengirim `scheduled_at`, termasuk saat reschedule.
- Sesi video **wajib** memakai Google Meet. Tidak ada penyedia fallback: bila pembuatan link gagal, permintaan ditolak dan bisa diulang lewat `POST /v1/care-sessions/{id}/meet-link`.
- Token Google dikelola senyap (tanpa notifikasi izin kedaluwarsa). Sweeper sepuluh menit menyegarkan access token yang tersisa ≤15 menit atau pemeliharaan tujuh hari jatuh tempo; hasil/rotasi/`last_refreshed_at` atomik. `invalid_grant` dihapus tanpa notifikasi. Batas tujuh hari Testing tidak dapat diperpanjang programatik; operator harus OAuth consent screen → Publish app. Rujukan: `docs/GOOGLE_CALENDAR_SETUP.md`, migrasi 030.

## Presentasi profesional (2026-11-09)

- Home profesional memuat Sesi berjalan, Video call mendatang dan Sesi chat mendatang; Operasional berisi Ketersediaan & harga serta Earnings, Klinis berisi E-Prescription sesuai kewenangan psikiater. Data pasien dibagikan berada pada tab Pasien. Lainnya hanya memuat Profil Profesional, Portal Profesional (termasuk STR/SIP) dan relasi pasien–profesional.
- Crisis Incident Log dihapus dari navigasi, konten dan pemuatan dashboard profesional. Endpoint/riwayat insiden global serta alur SOS pasien dipertahankan.
- Jadwal menampilkan Quick Video Call, sesi hari ini, mendatang, ketersediaan/harga dan riwayat. Aksi lain membuka Detail pasien/Batal/Reschedule/Link & ringkasan; aturan check-in, penyelesaian dan jendela akses tetap berlaku. Ringkasan praktik hanya menampilkan slot aktif, dikelompokkan per hari, dengan hari libur dan harga server.
- Ringkasan klinis mengelompokkan sesi menurut paket, memakai progres/kuota server, tanggal WIB serta status aktual; no-show dipudarkan dan tanggal dicoret. Pemantauan harian tidak lagi menampilkan atau mengambil kiriman chat dan timeline pasien.

## Kontrak pengganti — sesi satu jam dan Video (2026-11-10)

- Ketentuan bagian ini menggantikan pilihan Chat/durasi lama untuk permintaan baru pasien. Sesi satu kali maupun paket default 60 menit; API/store menolak durasi eksplisit di bawah 60 atau di atas 180. Jadwal praktik minimum 60 menit per slot, dengan rentang yang cukup untuk satu slot penuh.
- Booking dan penjadwalan paket baru pasien otomatis `session_type=video`. Jenis sesi historis dan booking Chat yang sedang dilanjutkan pembayarannya tidak dikonversi. Paket tetap berbeda pada jumlah sesi dan masa berlaku, bukan kemampuan chat/berbagi saat sesi.
- Jika integrasi Calendar server tersedia, akun Google profesional yang belum siap tidak menghalangi booking Video pasien; aktivasi/jadwal boleh menunggu link Meet. Server tanpa integrasi tetap menolak Video. Tidak ada penyedia video alternatif.
- Reschedule mengubah `care_sessions.scheduled_at` dan tanggal/jam booking asal secara atomik, mereset reminder/kehadiran, serta memeriksa irisan seluruh durasi. Pemeriksaan mengecualikan sesi yang dipindahkan dan memakai kunci transaksi profesional yang sama dengan pembuatan sesi. Sinkronisasi Calendar dilakukan setelah jadwal tersimpan, dengan warning bila gagal.
- Slot harian dan ringkasan ketersediaan memeriksa irisan durasi; jangan hanya membandingkan jam mulai atau memotong daftar sesi pada 200 entri. Pending checkout tetap mengikuti kebijakan lama: belum menjadi reservasi slot; aktivasi yang kalah memakai alur perlu reschedule.
- Preferensi consent pasangan dapat disimpan sebelum booking/sesi. Tanpa paket aktif, izin baca profesional dan berbagi record pasien hanya berlaku pada sesi `scheduled`, sejak `scheduled_at` sampai sebelum `scheduled_at + duration`. Ini lebih sempit daripada jendela chat/Meet yang mulai 10 menit lebih awal. Dengan paket aktif, berbagi antarsesi dan akses sesuai consent tetap tersedia.
- Worksheet satu kali memakai endpoint share yang sama. Daftar/detail record profesional ditutup setelah sesi berakhir jika tidak ada paket aktif. Riwayat percakapan/lampiran yang telah dikirim tetap mengikuti otorisasi peserta yang sudah ada; tidak menghapus pesan lama.
- Lampiran profesional tidak memerlukan consent kategori pasien; tetap memerlukan profesional terverifikasi, relasi sah dan sesi aktif. Tombol di luar sesi menjelaskan waktu akses.
- Messages memuat pasangan sesi mendatang meskipun percakapan kosong. Pembatalan satu kali, termasuk ketidakhadiran profesional, menonaktifkan link hanya jika tidak ada sesi scheduled/pending, paket aktif/pending atau pembelian lain yang memberi hak. Migrasi 038 memperbaiki pembatalan historis dengan guard yang sama; relasi manual tanpa bukti pembatalan dipertahankan.
- Migrasi 036 menormalkan semua durasi lama di bawah 60 dan default ke 60, tanpa mengubah waktu mulai. Migrasi 036–038 masih menunggu penerapan produksi pada pekerjaan ini. Sesi lama yang semula berjarak 30 menit dapat bertumpang tindih setelah diperpanjang; jangan menggeser atau membatalkannya diam-diam.
