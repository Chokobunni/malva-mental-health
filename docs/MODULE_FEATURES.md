# MODULE_FEATURES — Matriks Fitur Malva

Pembaruan 15 November 2026: diary pasien memakai editor halaman penuh, tipografi, kamera/galeri privat dan kanvas dengan alat gambar lengkap. Riwayat diary lama dan pembagian berizin tetap kompatibel. Medication Check-in memproyeksikan waktu konsumsi terakhir dari riwayat, menyelaraskan stok server dan membatasi taken/partial obat yang sama minimal 24 jam dengan retry idempoten. Rujukan: [rencana diary/obat](superpowers/plans/2026-11-15-patient-diary-medication.md).

Perbaikan 5 November 2026: booking/payment pending idempoten dan dapat dilanjutkan; Paket MyCare difilter status; pasien membagikan Therapy Record dari chat dan profesional membuka detail berotorisasi. CF memakai interpretasi dukungan rule. Notifikasi mobile pasien hanya chat sesi aktif + reminder lokal goals/obat; profesional hanya chat sesi aktif. Rujukan implementasi: [rencana perbaikan](superpowers/plans/2026-11-05-patient-flow-repairs.md).

Dokumen ini memetakan fitur per modul dan per peran (**Pasien**, **Profesional**, **Admin**).
Sumber kebenaran endpoint: `docs/API_ROUTES.md` (dibuat otomatis dari `internal/server/server.go`).
Status `Aktif` berarti endpoint terdaftar di `Routes()` dan diimplementasikan di handler + store.

> Konvensi ID: `FEAT-<modul><urut>`. Kolom "Bergantung" menandai integrasi eksternal
> (Midtrans / Fonnte / Google) yang bila tidak dikonfigurasi menonaktifkan sebagian perilaku.

## 1. Auth & Profil

| FEAT-ID | Fitur | Role | Endpoint utama | Status |
|---|---|---|---|---|
| FEAT-001 | Registrasi & login email/password (JWT) | Pasien, Profesional | `POST /v1/auth/register`, `POST /v1/auth/login` | Aktif |
| FEAT-002 | Refresh & logout token | Semua | `POST /v1/auth/refresh`, `POST /v1/auth/logout` | Aktif |
| FEAT-003 | Login / tautkan Google | Semua | `POST /v1/auth/google`, `/v1/auth/link-google`, `/v1/auth/google-token-exchange` | Aktif (butuh GoogleClientID) |
| FEAT-004 | Profil saya (lihat/ubah) | Semua | `GET /v1/me`, `PATCH /v1/me` | Aktif |
| FEAT-005 | Ganti password | Semua | `POST /v1/auth/change-password` | Aktif |
| FEAT-006 | Registrasi perangkat (token FCM) | Semua | `POST /v1/device-tokens` | Aktif |
| FEAT-007 | Persetujuan privasi (consent) | Semua | `GET /v1/privacy/consents`, `PUT /v1/privacy/consents` | Aktif |
| FEAT-008 | Audit log aktivitas | Semua | `GET /v1/audit-logs` | Aktif |

## 2. Screening (PHQ-9 / GAD-7)

| FEAT-ID | Fitur | Role | Endpoint utama | Status |
|---|---|---|---|---|
| FEAT-010 | Kirim skrining (skoring server FC+CF) | Pasien, Profesional | `POST /v1/screenings` | Aktif |
| FEAT-011 | Riwayat skrining | Pasien, Profesional | `GET /v1/screenings` | Aktif |
| FEAT-012 | Review hasil skrining | Profesional | `POST /v1/screenings/{screening_id}/review` | Aktif |
| FEAT-013 | Daftar review skrining | Pasien, Profesional | `GET /v1/screening-reviews` | Aktif |

## 3. Mood / Diary / Obat / Terapi

Home pasien mengikuti referensi dengan check-in5langkah (mood, obat, tidur, energi, kecemasan/iritabilitas), banner tracker, Self-care dan Professional Care. Add Mood Entry dan Riwayat Minum Obat menjadi halaman tersendiri; history memuat seluruh log server per tanggal WIB. Home profesional memakai header/kartu baru dan dropdown ketersediaan yang sama fungsinya. Chat hanya menampilkan satu presence untuk peer terpilih. Retry offline mempertahankan stok dan isolasi akun; lihat [rencana dan kontrak](superpowers/plans/2026-11-10-home-checkin-reference.md).

| FEAT-ID | Fitur | Role | Endpoint utama | Status |
|---|---|---|---|---|
| FEAT-020 | Mood check-in harian | Pasien | `GET /v1/mood-checkins`, `POST /v1/mood-checkins` | Aktif |
| FEAT-021 | Diary (CRUD + feedback) | Pasien | `/v1/diary-entries` (GET/POST/PUT/DELETE/PATCH) | Aktif |
| FEAT-022 | Manajemen obat | Pasien | `/v1/medications` (GET/POST/PUT/DELETE) | Aktif |
| FEAT-023 | Log minum obat | Pasien | `GET /v1/medication-logs`, `POST /v1/medication-logs` | Aktif |
| FEAT-024 | Goals & habit: yes/no, nilai, sub-tugas; jadwal harian/mingguan/bulanan, target mingguan fleksibel/hari tertentu, pengingat lokal, riwayat; tambah/edit/hapus dengan konfirmasi dan retry; di luar jadwal sub-tugas hanya mengoreksi catatan tanggal tersebut; scroll progres tetap | Pasien | `/v1/goals`, `/v1/habit-logs` | Aktif |
| FEAT-025 | Therapy worksheet (simpan/bagikan) | Pasien, Profesional | `/v1/therapy-submissions` | Aktif |
| FEAT-026 | Timeline aktivitas | Semua | `GET /v1/timeline` | Aktif |

## 4. Booking & Pembayaran

| FEAT-ID | Fitur | Role | Endpoint utama | Status |
|---|---|---|---|---|
| FEAT-030 | Cari dokter & ketersediaan slot | Pasien (publik) | `GET /v1/doctors/search`, `/v1/doctors/{user_id}/slots`, `/availability` | Aktif |
| FEAT-031 | Profil dokter publik | Pasien (publik) | `GET /v1/doctors/{user_id}` | Aktif |
| FEAT-032 | Booking konsultasi; pasien otomatis Video, default 60 menit | Pasien, Profesional | `POST /v1/bookings` | Aktif |
| FEAT-033 | Batalkan booking pending | Pasien | `POST /v1/bookings/{booking_id}/cancel` | Aktif |
| FEAT-034 | Bayar konsultasi (simulasi/gateway) | Pasien | `POST /v1/payments`, `POST /v1/payments/mark-paid` | Aktif (Midtrans untuk gateway) |
| FEAT-035 | Webhook pembayaran (signature) | Sistem | `POST /v1/webhooks/payment` | Aktif (Midtrans) |
| FEAT-036 | Ulasan dokter | Pasien | `GET/POST /v1/doctors/{user_id}/reviews` | Aktif |
| FEAT-037 | Pendapatan & pencairan (payout) | Profesional | `GET /v1/earnings`, `POST /v1/earnings/payout` | Aktif |
| FEAT-038 | E-prescription CRUD draft/issued, rutinitas WIB dan stok obat | Profesional (Sp.KJ) | `POST/GET /v1/e-prescriptions`, `GET/PUT/DELETE /v1/e-prescriptions/{id}`, `GET /v1/e-prescriptions/verify` | Aktif; migrasi 037, 039–040 sebelum rilis |

## 5. Care Package & Sesi

| FEAT-ID | Fitur | Role | Endpoint utama | Status |
|---|---|---|---|---|
| FEAT-040 | Beli paket care (4 sesi / 6 minggu) | Pasien | `POST /v1/care-packages` | Aktif |
| FEAT-041 | Daftar paket | Pasien, Profesional | `GET /v1/care-packages` | Aktif |
| FEAT-042 | Batalkan paket pending | Pasien | `POST /v1/care-packages/{package_id}/cancel` | Aktif |
| FEAT-043 | Jadwalkan sesi | Pasien, Profesional | `POST /v1/care-sessions` | Aktif |
| FEAT-044 | Daftar sesi | Pasien, Profesional | `GET /v1/care-sessions` | Aktif |
| FEAT-045 | Tandai kehadiran / ubah status sesi | Profesional, Pasien | `PATCH /v1/care-sessions/{session_id}` | Aktif |
| FEAT-046 | Reschedule sesi | Pasien, Profesional | `POST /v1/care-sessions/{session_id}/reschedule` | Aktif |
| FEAT-047 | Refund / kredit sesi | Pasien, Profesional, Admin | `POST /v1/care-sessions/{session_id}/refund`, `GET /v1/care-refunds` | Aktif |
| FEAT-048 | Quick video call (Meet) | Profesional | `POST /v1/meet/quick` | Aktif (wajib Google Meet, tanpa fallback) |
| FEAT-049 | Link Meet otomatis untuk sesi video | Pasien, Profesional | `POST /v1/care-sessions/{session_id}/meet-link` | Aktif — dibuat saat sesi dijadwalkan/dibooking, bisa diulang |
| FEAT-049a | Undangan + pengingat Google Calendar ke pasien | Pasien | (internal, `calendar.go` attendee) | Aktif |
| FEAT-049b | Status tautan Google Calendar | Profesional | `GET /v1/google/status` | Aktif |
| FEAT-049c | Pengingat sesi otomatis (15–25 menit sebelum) | Pasien, Profesional | (sweeper backend) | Aktif |

## 6. Chat & Realtime

| FEAT-ID | Fitur | Role | Endpoint utama | Status |
|---|---|---|---|---|
| FEAT-050 | Pesan (kirim/daftar) | Pasien, Profesional | `GET/POST /v1/messages` | Aktif |
| FEAT-051 | Izin chat | Pasien, Profesional | `GET /v1/chat-permission` | Aktif |
| FEAT-052 | WebSocket realtime | Semua | `GET /v1/realtime/ws` | Aktif |

## 7. Notifikasi

| FEAT-ID | Fitur | Role | Endpoint utama | Status |
|---|---|---|---|---|
| FEAT-060 | Daftar & tandai baca notifikasi | Semua | `GET /v1/notifications`, `PATCH /v1/notifications/read-all`, `PATCH /v1/notifications/{notification_id}/read` | Aktif |
| FEAT-061 | Tes notifikasi | Semua | `POST /v1/notifications/test` | Aktif |

## 8. Safety / SOS

| FEAT-ID | Fitur | Role | Endpoint utama | Status |
|---|---|---|---|---|
| FEAT-070 | Kontak darurat (maks 5) | Pasien | `/v1/emergency-contacts` (GET/POST/PUT/DELETE) | Aktif |
| FEAT-071 | Kirim SOS (crisis alert) | Pasien | `POST /v1/crisis-alerts` | Aktif (blast butuh Fonnte) |
| FEAT-072 | Riwayat & penyelesaian insiden | Pasien, Profesional | `GET /v1/crisis-incidents`, `POST /v1/crisis-incidents/{id}/resolve` | Aktif |
| FEAT-073 | Status blast SOS per kontak | Pasien | `GET /v1/sos-blast-status` | Aktif |

## 9. Kredensial & Praktik Profesional

| FEAT-ID | Fitur | Role | Endpoint utama | Status |
|---|---|---|---|---|
| FEAT-080 | Unggah kredensial STR/SIP/SIPP | Profesional | `POST /v1/credentials`, `GET /v1/credentials/me` | Aktif |
| FEAT-081 | Unggah berkas media (foto/video) | Profesional | `POST /v1/upload` | Aktif |
| FEAT-082 | Jadwal praktik mingguan | Profesional | `GET/PUT /v1/professional/schedules`, `DELETE /v1/professional/schedules/{id}` | Aktif |
| FEAT-083 | Hari libur | Profesional | `/v1/professional/time-off` (GET/POST/DELETE) | Aktif |
| FEAT-084 | Harga layanan | Profesional | `GET /v1/pricing`, `PUT /v1/professional/pricing` | Aktif |
| FEAT-085 | Keterkaitan pasien–profesional | Pasien, Profesional | `GET/POST /v1/patient-professional-links` | Aktif |
| FEAT-086 | Catatan profesional | Profesional | `GET/POST /v1/professional-notes` | Aktif |
| FEAT-087 | Follow-up pasien | Profesional | `/v1/follow-ups` (GET/POST/PATCH) | Aktif |
| FEAT-088 | Rekam medis | Pasien, Profesional | `GET/PUT /v1/health-record` | Aktif |

## 10. Administrasi (Admin)

| FEAT-ID | Fitur | Role | Endpoint utama | Status |
|---|---|---|---|---|
| FEAT-090 | Kelola pengguna | Admin | `GET/PATCH/DELETE /v1/admin/users` | Aktif |
| FEAT-091 | Verifikasi kredensial profesional | Admin | `GET /v1/admin/credentials/pending`, `POST /v1/admin/credentials/{id}/verify` | Aktif |
| FEAT-092 | Kelola dokter | Admin | `GET/POST/PUT /v1/admin/doctors` | Aktif |

---

**Total fitur terdaftar:** 10 modul. Endpoint lengkap per rute: lihat `API_ROUTES.md`.

### Check-in dan record 0.1.9

Diary dan mood terpisah. Kedua role memakai statistik hari WIB, kalender, combo
chart mood/tidur, Symptoms Balance Map dengan filter periode, serta Recent yang
berasal dari data tersimpan. Mini Summary mengambil diary/goals dari server.
Seluruh kartu chat dan Therapy Record membuka detail, termasuk jawaban lama.
PHQ/GAD memakai satu filter dan label Total Score.

Pasien mendapat tepat satu rating/ulasan per sesi satu kali selesai atau seluruh
paket pembelian selesai (kuota completed/no_show habis, minimal satu completed).
Saldo paket merged 4+4 tetap 8 tetapi memberi satu hak per ID pembelian setelah
rentang empat pertemuannya terminal; server
menegakkan entitlement atomik termasuk klien lama. Pasien diminta mengulas setelah
refresh/resume/poll, sekali per unit/akun selama sesi aplikasi. Ulasan lama tetap
terlihat tanpa backfill dugaan; unit historis pada/sebelum ulasan legacy terakhir
ditekan konservatif. `GET /v1/review-entitlements` menampilkan hak tersedia. Agregat berasal dari
ulasan nyata; contoh/demo tidak ditampilkan. Discovery
dan MyCare memakai jarak koordinat aktual dengan proteksi respons lokasi lama.
Home profesional menempatkan Klinis sebelum Operasional; Earnings sebelum dropdown
Ketersediaan & Harga yang membaca server dan dimuat ulang setelah Atur. Panel ini
tidak lagi berada di Jadwal. Detail pasien menampilkan Mood Entries tanpa diary
dan tanpa Catatan sesi; data tersimpan tetap ada. PHQ/GAD mempertahankan hasil
klinis dan CF berlabel tanpa string aturan/penjelasan teknis.
PDF obat/screening memakai tabel berkode warna; mood memakai emoji, combo/radar
chart; diary memuat catatan lengkap dari server. Semua ekspor terikat akun aktif.

### Koreksi mobile 0.1.3

Home pasien: sesi berjalan dan video mendatang dengan foto profesional. Profesional: kartu video responsif, detail pasien terautentikasi dan Hadir tanpa penutupan dini. Pembayaran: binding legacy dan retry token terbarui. Push: data-only, validasi sesi aktif di background, cleanup shade/transport historis tanpa menghapus riwayat atau alarm yang valid.
# Tambahan konsultasi 2026-11-06

| Modul | Pasien | Profesional |
|---|---|---|
| Kehadiran sesi | Hadir/Tidak hadir sendiri; no-show memakai kuota | Hadir/Tidak hadir sendiri; absen mengembalikan kuota |
| Penyelesaian | Riwayat sesudah akhir, chat ditutup tepat waktu | Sesi selesai hanya sesudah akhir jadwal |
| Attachment chat | Isi assessment saat sesi; buka goals/rangkuman; unduh file privat | Goals/habits dan tambah goal; permintaan assessment; diagnosis; Medication psikiater; file/gambar; rangkuman homework/insight |
| Sinkronisasi | Obat dari profesional masuk Medication Check-in lewat event in-app dan dipulihkan saat resume/reconnect | Perubahan memakai scope sesi aktif dan consent |
| Pembayaran | Status Midtrans resmi mengaktifkan paket tepat sekali | Kebijakan earnings yang ada dipertahankan |

### Penyempurnaan tampilan 0.1.5

- Home kedua peran: video dan sesi chat mendatang menampilkan yang terdekat, dengan dropdown seluruh jadwal.
- Profesional: Messages pada navigasi, Quick Video Call ikut scroll, sesi lewat durasi yang perlu diselesaikan ditampilkan di awal jadwal.
- MyCare Jadwal/Riwayat: jenis sesi, konteks check-in dan hasil sesi; tidak ada judul kehadiran kosong.
- Crisis Incident Log: screening berupa riwayat; hanya SOS belum resolved dihitung sebagai perlu tindak lanjut, dengan konfirmasi penanganan tanpa wajib mengetik.

## Skrining WHO-5 dan assessment terpadu (7 November 2026)

Symptoms Assessment dimulai dengan WHO-5 lengkap. Persentase = raw x4;
raw <13 atau satu item 0-1 mengaktifkan PHQ-9/GAD-7, sedangkan hasil baik
berakhir pada kesimpulan WHO tanpa membuat skor PHQ/GAD. DASS-21 tetap manual.
Katalog pasien dan detail profesional menyatukan empat instrumen. Skor baku
terpisah dari CF dukungan model yang belum dikalibrasi klinis. Kontrak data,
consent dan berbagi tetap memakai mekanisme sebelumnya.
Rincian: [scoring dan Forward Chaining](SCREENING_SCORING.md).


## Koreksi pengalaman pasien/profesional — 8 November 2026

Symptoms Assessment hanya pada registrasi pasien baru, sekali. Login/restore
menuju Home; skip/back tidak menjadi hasil tes. Tampilan pasien mempertahankan
penjelasan instrumen, total/arti skor, jangkar jawaban dan disclaimer tanpa rumus.
Katalog `Screening`, filter instrumen/urutan dan lima hasil awal yang dapat diperluas
berlaku bagi pasien/profesional. Share menyediakan PDF dan profesional berizin.
Semua aksi ekspor menggunakan PDF; ringkasan memuat data yang tersedia dengan
batas feed yang dinyatakan, bukan backup lengkap seumur hidup.

Mood Medication Check-in masuk Self-Care; Therapy Record melalui bagian bawah
Psychological Therapy; tujuh jenis jebakan pikiran memiliki penjelasan singkat.
Profil memakai data akun nyata. Switch privasi lokal dihapus, izin berbagi tetap
melalui Consent Management. Home profesional menempatkan data dibagikan setelah
pasien terhubung; nav Messages sebelum Lainnya; Profil Profesional paling atas di
Lainnya, tanpa audit/export ringkasan atau duplikasi Crisis Log.

Reschedule kedua peran menjaga format WIB; kartu aturan paket putih. SOS menampilkan
status aktual, polling terbatas serta galat/timeout; status terkirim ke gateway
bukan bukti diterima kontak. Tidak ada perubahan skema atau rumus/CF klinis.
Rujukan implementasi: [desain koreksi](superpowers/specs/2026-11-08-patient-professional-polish-design.md).

### Pengalaman klinis 0.1.10

Chat membuka seluruh jenis record lewat bubble dan menyediakan pemilihan diary.
Popup obat/goals/diary/ringkasan/assessment mengikuti referensi. Mini Summary tujuh
tanggal WIB tanpa last diary; Recent mood tiga entri. Ekspor diary tanpa tanggapan
dan mood tanpa catatan. Medication aman saat reminder belum diatur. Notifikasi putih.

Home profesional berisi sesi, Operasional dan Klinis; Data pasien dibagikan berada
di Pasien. Lainnya memuat profil, portal dan relasi. Crisis Incident Log beserta
loading/log tampilannya dihapus, tanpa menghapus insiden atau alur SOS pasien.
Jadwal dan Ringkasan Klinis menampilkan status/kuota aktual; PHQ/GAD, WHO dan DASS
memiliki kartu skor, makna dan jawaban. Pemantauan harian tanpa Kiriman/Timeline.
Ulasan memakai entitlement per sesi/pembelian di atas, termasuk renewal merged.

## Kontrak sesi dan resep — 10 November 2026

- Data Pasien Dibagikan profesional memiliki tab Screening untuk WHO-5, DASS-21,
  PHQ-9/GAD-7, terpisah dari worksheet Terapi. Riwayat dan detail mengikuti pasien
  terpilih serta izin sumber masing-masing. Detail pasien tidak menampilkan panel
  “Gejala teridentifikasi”; skor, CF, indikator klinis/keselamatan, interpretasi
  dan detail jawaban tetap tersedia.

- E-Prescription mendukung diagnosis/indikasi, draft, revisi penuh beberapa obat
  dengan ID stabil, dan soft-delete oleh penulis psikiater terverifikasi.
  Draft hanya terlihat penulis. `current_stock` item adalah pasokan;
  `remaining_stock` adalah stok obat berjalan. Revisi memakai selisih pasokan,
  mempertahankan konsumsi dan log. Instruksi makan/catatan per obat tersimpan
  pada schedule. Draft/delete menonaktifkan obat dan membatalkan QR/tanda tangan;
  audit tetap disimpan. Migrasi 039 DDL terpisah dari backfill konservatif 040.

- Booking baru pasien otomatis Video, default 60 menit. Sesi satu kali/paket
  dan slot praktik minimum 60 menit, maksimum 180. Jenis sesi historis serta
  pembayaran Chat lama tetap dapat dibaca/dilanjutkan.
- Reschedule menyimpan sesi dan booking asal atomik serta memblokir irisan
  durasi sesi lain. Messages memuat pasangan sesi mendatang tanpa pesan.
- Consent dapat dipilih sebelum sesi; tanpa paket aktif, akses record dan
  berbagi hanya selama durasi sesi scheduled. Paket aktif mempertahankan
  akses antarsesi sesuai consent. Worksheet satu kali memakai alur yang sama;
  lampiran profesional tidak bergantung pada consent kategori pasien.
- Pembatalan satu kali menghentikan link hanya jika tidak ada hak sesi/paket/
  pembelian lain; migrasi 038 membenahi relasi historis secara konservatif.
- Wizard E-Prescription Sp.KJ mengirim bentuk/dosis/satuan, rutinitas WIB,
  jumlah per dosis, stok awal serta batas/toggle pengingat. Server menerbitkan
  resep dan obat pasien atomik; checklist dan pengingat memakai jadwal tersimpan.
- Migrasi 036–040 telah diterapkan di produksi. Verifikasi ulang rilis0.1.15+16:
  tidak ada sesi/booking/slot di bawah60menit, ketiga default60. Normalisasi
  mempertahankan jam mulai legacy.

Rujukan: [kontrak API](API_DOCUMENTATION.md), [skema](DATABASE_SCHEMA.md).

- Tambah Resep memakai Detail Obat → Atur Rutinitas → pengingat konsumsi → pengingat isi ulang. Stok hanya di tahap terakhir. Fleksibel tanpa jam; pola khusus mendukung interval jam/hari/bulan kalender, jam presisi dan hari tertentu. Interval bulan adalah kalender, mendukung injeksi bulanan tanpa drift30hari.
