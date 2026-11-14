# Business Requirements Document (BRD) - Malva Mental Health

### Diary dan konsumsi obat pasien — 15 November 2026

Pasien menulis diary di halaman penuh bertanggal WIB, dengan judul, tulisan, pengaturan tipografi, foto opsional dari kamera/galeri dan kanvas gambar. Mood tetap dicatat melalui Mood Tracker. Foto diary bersifat privat; profesional hanya dapat melihat gambar dalam diary yang dibagikan dengan relasi dan consent yang berlaku.

Konsumsi obat yang sama dibatasi minimal 24 jam sejak dosis terakhir. Catatan konsumsi memperbarui riwayat, waktu terakhir dan stok sesuai dosis satu kali, termasuk saat pengiriman diulang atau koneksi terputus. Tidak ada perubahan skema database.

### Ketentuan operasional pasien — 5 November 2026

Satu intent pembelian pending harus dapat dilanjutkan tanpa membuat paket atau pembayaran ganda. MyCare menyediakan filter paket `pending_payment`, `active`, dan `cancelled`. Status lunas harus dikonfirmasi server ke Midtrans sebelum aktivasi dan pemilihan data yang dibagikan.

Push mobile pasien dibatasi ke chat sesi aktif; goals harian dan waktu obat memakai reminder lokal. Profesional menerima push chat sesi aktif saja. Riwayat in-app tetap dipertahankan. CF ditampilkan sebagai dukungan rule, bukan probabilitas diagnosis; Therapy Record dapat dibagikan secara eksplisit dari chat.

**Malva Mental Health App**

| Field | Value |
|---|---|
| Version | **2.0** |
| Date | 2026-08-01 |
| Status | Production Ready + Safety Protocol |
| Author | Malva Team |

---

## 1. Business Context

### 1.1 Problem Statement

Indonesia memiliki kekurangan profesional kesehatan mental dengan rasio 1 psikiater per 100.000+ penduduk. Banyak pasien tidak memiliki akses rutin ke profesional, dan monitoring antar-sesi konsultasi sangat terbatas. Hal ini menyebabkan:

- Deteksi dini gangguan mental yang terlambat
- Kepatuhan obat yang rendah
- Kehilangan data klinis antar-sesi
- **Krisis yang tidak terdeteksi dan tidak tertangani tepat waktu**
- **Stigma & hambatan akses**: pasien enggan daftar karena form panjang & data sensitif diminta di awal

### 1.2 Solution

Malva menyediakan platform digital yang menghubungkan pasien dengan profesional kesehatan mental melalui:

1. **Self-assessment screening** (PHQ-9/GAD-7) untuk deteksi dini
2. **Mood & diary tracking** untuk monitoring harian
3. **Medication management** dengan reminder untuk kepatuhan obat
4. **Real-time chat** untuk komunikasi langsung
5. **Professional dashboard** untuk monitoring dan intervensi
6. **Safety Net Protocol**: SOS button, silent alert, emergency contacts blast, dan guided grounding untuk situasi krisis
7. **Personalized Home**: konten disesuaikan dengan kondisi klinis pasien (anxiety, depression, insomnia, normal)
8. **Doctor Discovery & Booking**: pencarian profesional terverifikasi dengan transparansi lisensi dan jadwal

### 1.3 Target Users

| Segment | Description | Est. Size |
|---|---|---|
| **Primary** | Pasien kesehatan mental (18-55 tahun) | 10M+ di Indonesia |
| **Secondary** | Psikiater (Sp.KJ), psikolog (M.Psi) | 10,000+ di Indonesia |
| **Tertiary** | Rumah sakit, klinik mental health | 500+ fasilitas |
| **Expansion** | Couple/family counseling, pre-marital, student accommodations | TAM tambahan |

---

## 2. Business Objectives

| Objective | KPI | Timeline | Target |
|---|---|---|---|
| Launch MVP | App live di Play Store | Q3 2026 | ✅ |
| Safety Protocol Live | Crisis detection → escalation rate | Q4 2026 | 100% |
| User Acquisition | Total registered users | Q4 2026 | 1,000 |
| Professional Onboarding | Verified professionals (STR/SIP) | Q4 2026 | 50 |
| Screening Completion | % pasien yang mengisi screening | Q4 2026 | 85% |
| Medication Adherence | % obat tercatat | Q1 2027 | 80% |
| Revenue | Booking + package revenue | Q2 2027 | Rp 50M/bulan |

---

## 3. Business Rules

### 3.1 User Registration

| Rule | Description |
|---|---|
| BR-01 | Pasien bisa mendaftar dengan email ATAU **Single Sign-On (Google/Apple)** — tanpa diminta nomor telepon di awal |
| BR-01b | **Progressive Profiling**: nomor telepon hanya diminta saat (a) Safety Protocol terpicu, atau (b) booking tele-konsultasi |
| BR-02 | Profesional memerlukan `professional_id` (license number) saat registrasi |
| BR-03 | Profesional harus **diverifikasi dokumen STR/SIP oleh admin** sebelum bisa mengakses data pasien (status `PENDING` → `VERIFIED`/`REJECTED`) |
| BR-04 | Satu akun email hanya bisa memiliki satu role (patient ATAU professional) |
| BR-05 | Profesional **diwajibkan mengaktifkan 2FA** (TOTP/email OTP) sebelum akses data rekam medis pasien |

### 3.2 Patient-Professional Relationship

| Rule | Description |
|---|---|
| BR-10 | Pasien harus secara eksplisit menghubungkan (link) ke profesional |
| BR-11 | Profesional tidak bisa menghubungkan diri ke pasien |
| BR-12 | Satu pasien bisa terhubung ke multiple profesional |
| BR-13 | Hubungan bisa dinonaktifkan oleh pasien |
| BR-14 | Profesional hanya bisa melihat data pasien yang **memiliki consent** untuk kategori data tersebut |

### 3.3 Data Access & Consent

| Rule | Description |
|---|---|
| BR-20 | Profesional hanya bisa melihat data pasien yang terhubung DAN memiliki consent |
| BR-21 | Pasien mengontrol data sharing per profesional (screening, mood/diary, medication, timeline, **health record**) |
| BR-22 | Catatan profesional (notes) hanya visible untuk profesional yang membuatnya, kecuali `shared_with_patient` |
| BR-23 | Follow-up message visible untuk pasien yang dituju |
| BR-24 | Audit log mencatat semua akses data |
| BR-25 | **Diagnosis resmi (health record) HANYA dapat diubah oleh profesional terverifikasi** — pasien read-only |

### 3.4 Screening Rules

| Rule | Description |
|---|---|
| BR-30 | PHQ-9 item 9 (self-harm) positif = crisis flag |
| BR-31 | Crisis flag otomatis mengirim alert ke linked professionals |
| BR-32 | Backend selalu menghitung ulang skor dari jawaban mentah |
| BR-33 | Client tidak dipercaya untuk mengirim skor final |
| BR-34 | Screening adalah alat bantu, bukan diagnosis final |
| BR-35 | **Crisis flag memicu Safety Protocol UI**: empathetic message + breathing animation + hotline + silent SOS + guided grounding |

### 3.5 Safety Protocol Rules

| Rule | Description |
|---|---|
| BR-40 | **Zero-Miss Crisis Protocol**: 100% kasus PHQ-9 Q9 > 0 dieskalasi |
| BR-41 | Silent SOS blast terkirim dalam **< 30 detik** ke semua emergency contacts |
| BR-42 | Silent SOS mencakup GPS location pasien (Google Maps link) |
| BR-43 | High-priority notification ke profesional tertaut dalam **< 5 detik** |
| BR-44 | Setiap crisis incident wajib dicatat (incident log) dan memiliki resolution trail (liability protection profesional) |
| BR-45 | **Unggahan SOS blast ke SMS/WhatsApp gateway dilindungi rate-limit anti-spam (max 1x per 10 menit per pasien)** |
| BR-46 | Emergency contacts maksimal 5 kontak per pasien; wajib format telepon Indonesia valid |
| BR-47 | Guided grounding TIDAK memerlukan input suara/typing — mendukung pasien panic attack (vocal freeze) |

### 3.6 Medication Rules

| Rule | Description |
|---|---|
| BR-50 | Stock berkurang saat pasien menekan "Take Now" |
| BR-51 | Low-stock alert saat stock < alert_below |
| BR-52 | Reminder dijadwalkan di device menggunakan local notification |
| BR-53 | FCM digunakan untuk sinkronisasi perubahan jadwal |

### 3.7 Booking & Payment Rules

| Rule | Description |
|---|---|
| BR-60 | Pasien bisa pilih layanan: **Quick Consult (one-time)** atau **Continuous Support (package)** |
| BR-61 | **Package pricing**: diskon bertingkat untuk 2/3/6 sesi dengan masa berlaku bervariasi (60/90/365 hari) — paket terlaris ditandai "Lebih Hemat" |
| BR-62 | Breakdown pembayaran transparan: biaya konsultasi + service fee ditampilkan sebelum pembayaran |
| BR-63 | Setiap transaksi menghasilkan **transaction reference** unik untuk audit |
| BR-64 | **Platform fee** dipotong dari pembayaran profesional (contoh: 10%) — ditampilkan dengan transparan di earnings profesional |
| BR-65 | **Data sharing consent diminta setelah pembayaran berhasil** (per kategori data) |
| BR-66 | Profesional hanya bisa booking jika terverifikasi STR/SIP |
| BR-67 | **Professional liability protection**: semua crisis incident memiliki audit trail untuk perlindungan hukum profesional |

### 3.8 Chat Rules

| Rule | Description |
|---|---|
| BR-70 | Chat hanya antara pasien dan profesional yang terhubung |
| BR-71 | Pesan di-persist di database (bukan hanya real-time) |
| BR-72 | Typing indicator tidak di-persist |
| BR-73 | Online presence real-time |
| BR-74 | **Attachment chat mendukung**: photo, camera, file (PDF), **voice note**, dan share diary/goals/progress |
| BR-75 | **AI Mini Summary** tersedia di chat untuk dokter (ringkasan 14 hari data pasien) — data pasien tidak dipakai melatih model publik |

### 3.9 Notification Rules

| Rule | Description |
|---|---|
| BR-80 | Tidak ada data sensitif di push notification payload |
| BR-81 | Notification outbox untuk retryable delivery |
| BR-82 | Privacy mode: sembunyikan detail di lock screen |
| BR-83 | **Crisis alert menggunakan high-priority FCM channel terpisah** |

### 3.10 Professional Discovery & Trust Rules

| Rule | Description |
|---|---|
| BR-90 | **Trust signals wajib tampil di profil profesional**: nomor STR/SIPP, jumlah sesi, tingkat bantuan (%), jumlah ulasan, tahun pengalaman |
| BR-91 | Availability badge ("Tersedia/Tidak Tersedia") di daftar profesional |
| BR-92 | Sorting profesional: nama A-Z/Z-A, jadwal tersedia, sesi terbanyak, populer, jarak terdekat (Haversine) |
| BR-93 | Filter: spesialisasi, harga, jarak (km), BPJS |
| BR-94 | **Psikiater (Sp.KJ) vs Psikolog (M.Psi) dibedakan jelas** — psikiater bisa e-prescription, psikolog fokus terapi |
| BR-95 | E-Prescription hanya oleh psikiater terverifikasi dengan digital signature + STR/SIP number + QR code |
| BR-96 | Revenue share & earnings profesional transparan (gross, platform fee, net, payout) |

---

## 4. Data Classification

| Data Type | Sensitivity | Retention | Encryption |
|---|---|---|---|
| PHQ-9/GAD-7 scores | Sensitive | 7 tahun | At rest + transit |
| Mood check-ins | Sensitive | 7 tahun | At rest + transit |
| Diary entries | Highly Sensitive | Sampai pasien hapus | At rest + transit |
| Medication data | Sensitive | 7 tahun | At rest + transit |
| Chat messages | Sensitive | 3 tahun | At rest + transit |
| Professional notes | Highly Restricted | 10 tahun | At rest + transit |
| Audit logs | Critical | 10 tahun | At rest + transit |
| User credentials | Critical | Sampai akun hapus | Bcrypt + transit |
| **Emergency contacts** | Sensitive | Sampai pasien hapus | At rest + transit |
| **Crisis incidents** | Critical | 10 tahun | At rest + transit |
| **STR/SIP documents** | Critical | Permanen (verifikasi) | At rest + transit + object storage |
| **Payment transactions** | Critical | 10 tahun | At rest + transit |
| **GPS coordinates (crisis)** | Highly Sensitive | **Sementara — hanya durasi incident aktif** | Transit only, purge after resolve |

## 5. Compliance Requirements

### 5.1 Health Data Regulations

| Regulation | Requirement | Status |
|---|---|---|
| UU PDP (Indonesia) | Consent untuk pengumpulan data pribadi | ✅ Implemented |
| UU Praktik Kedokteran | Data medis terenkripsi, STR/SIP profesi terverifikasi | ✅ Implemented |
| HIPAA (reference) | Minimum necessary access | ✅ Implemented |
| GDPR (reference) | Right to erasure | ⏳ Planned |

### 5.2 Security Requirements

| Requirement | Implementation | Status |
|---|---|---|
| Authentication | JWT with refresh token rotation | ✅ |
| Authorization | Role-based access control (RBAC) | ✅ |
| Data encryption | TLS in transit, encrypted backups | ✅ |
| Password security | bcrypt with salt + password policy | ✅ |
| Audit trail | All data mutations logged | ✅ |
| Consent management | Per-professional, per-category sharing | ✅ |
| Rate limiting | Auth endpoints (20 req/min), SOS blast anti-spam | ✅ |
| 2FA | TOTP untuk profesional | ⏳ Planned |

## 6. Revenue Model

### 6.1 Service Tiers (Layanan Bertingkat)

| Kategori | Tier | Deskripsi |
|---|---|---|
| **e-Counseling** | **Essential** | Chat asinkron dengan profesional, respons dalam 24 jam |
| | **Professional** | Sesi Video default 60 menit; chat dan berbagi record mengikuti hak sesi/paket |
| | **Premium** | Chat + video call + akses penuh monitoring diary/mood/medication pasien |
| **Counseling Corner** | Essential / Professional / Premium | Varian layanan paket dengan harga bertingkat |
| **Couple e-Counseling** | Pre-Marriage / Marriage | Layanan pasangan — ekspansi segmen baru |
| **Family Counseling** | Paket keluarga | Sesi multi-partisipan |

### 6.2 Monetization

| Tier | Price | Features |
|---|---|---|
| Basic | Free | Screening, mood, diary, medication, emergency hotline |
| **Quick Consult** | Per sesi (Rp 80.000–399.000) | Sesi sekali jalan (chat/video) |
| **Package** | 2/3/6 sesi (diskon bertingkat) | "Lebih Hemat" — masa berlaku 60/90/365 hari |
| **Continuous Support** | Mingguan/Bulanan | Pemantauan diary + chat asinkron + feedback |
| Premium | Rp 49,900/bulan | + Chat, advanced analytics |
| Professional | Rp 199,900/bulan | + Dashboard, patient management |
| Enterprise | Custom | + Multi-clinic, API access |

### 6.3 Psychology Tests Marketplace (Upsell)

Katalog tes psikologi berbayar: Tes Kepribadian, 5 Bahasa Cinta, Happiness, Purpose of Life, Self Efficacy, Mental Health, Loneliness. Setiap tes **wajib menampilkan disclaimer**: "Tes ini TIDAK ditujukan untuk mendiagnosis gangguan psikologis, namun untuk membantu mengenali kondisi diri."

---

## 7. Risk Assessment

| Risk | Impact | Probability | Mitigation |
|---|---|---|---|
| Data breach | Critical | Low | Encryption, RBAC, audit logs |
| **Missed crisis** | **Critical** | **Medium** | **Safety Protocol wajib: SOS FAB di semua layar, PHQ-9 Q9 detector, high-priority alert, incident log wajib** |
| SOS abuse/spam | Medium | Medium | Rate-limit 1x/10 menit, incident log audit, professional dapat menandai false positive |
| **Professional malpractice liability** | **High** | **Medium** | **Crisis incident log + resolution trail untuk bukti respons profesional** |
| Professional liability | High | Medium | Disclaimer: screening bukan diagnosis |
| User low adoption | Medium | Medium | Onboarding flow, reminder |
| Server downtime (crisis alert gagal) | Critical | Low | Escalation ladder: unacknowledged 5 menit → escalate ke admin piket |
| SMS/WhatsApp blast failure | High | Low | Fallback: notifikasi in-app + email + retry outbox |
| Regulatory changes | Medium | Medium | Modular compliance layer |

## 8. Success Criteria

| Criteria | Measurement | Target |
|---|---|---|
| Product-market fit | User retention (30-day) | > 40% |
| **Safety** | **Crisis escalation rate (100% kasus terdeteksi tertangani)** | **100%** |
| **Safety response** | **Waktu crisis detection → alert profesional** | **< 10 detik** |
| **Safety blast** | **Waktu silent SOS → terkirim ke kontak** | **< 30 detik** |
| Clinical value | Professional satisfaction survey | > 4.0/5.0 |
| Technical reliability | API uptime | > 99.5% |
| **Crisis reliability** | **SOS blast delivery rate** | **> 99.9%** |
| Security | Zero data breaches | 0 incidents |
| Professional trust | Verified STR/SIP rate | 100% sebelum akses data |
| Scalability | Support 10K+ users | Ready |

## Koreksi rilis 0.1.3 (5 November 2026)

Home pasien menyediakan sesi berjalan dan video call mendatang beserta foto profesional. Kehadiran profesional tidak menutup sesi sebelum waktunya. Detail pasien tetap memakai otorisasi profesional. Notifikasi historis pada shade/antrean transport dihentikan; riwayat dalam aplikasi dipertahankan. Scope notifikasi OS tetap pasien: chat sesi aktif, goals harian, jam obat; profesional: chat sesi aktif.
# Koreksi konsultasi dan alat klinis — 6 November 2026

Kehadiran dicatat masing-masing oleh pasien dan profesional. Ketidakhadiran pasien memakai kuota; ketidakhadiran profesional mengembalikan kuota. Profesional hanya menyelesaikan sesi setelah durasi jadwal berakhir; chat/Meet tertutup pada akhir, riwayat tetap terbaca. Transaksi sukses diverifikasi melalui status Midtrans dengan referensi dan nominal yang sama, mengaktifkan paket tepat sekali.

Selama sesi aktif, profesional dapat mengelola goals/habits, meminta assessment yang tersedia, mengubah diagnosis dan obat sesuai kewenangan psikiater, mengirim file/gambar resep privat, serta mengirim rangkuman homework dan insight. Perubahan obat langsung disinkronkan ke Medication Check-in pasien melalui event in-app. Batas push tetap chat sesi aktif, dengan reminder lokal goals dan obat hanya bagi pasien.

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

## Koreksi pengalaman klinis — 9 November 2026

Ulasan dibatasi satu per sesi satu kali selesai atau per pembelian paket kontinu
yang seluruh kuotanya selesai/terpakai, dengan minimal satu pertemuan completed.
Perpanjangan yang digabung ke saldo paket tetap mempunyai hak per pembelian;
aturan pembayaran, kuota dan jadwal tidak berubah. Pasien mendapat prompt setelah
server mengonfirmasi kelayakan, dan server menolak pengiriman ulang secara atomik.
Ulasan lama dipertahankan tanpa menebak tautan sesi historis.

Home profesional berfokus pada sesi, Operasional dan Klinis. Data pasien dibagikan
berada di Pasien. Crisis Incident Log dan isinya dihilangkan dari antarmuka
profesional; alur SOS pasien dan data keselamatan server tetap tersedia sesuai
otorisasi. Ringkasan Klinis serta screening memakai data pasien sebenarnya.

Chat kedua peran membuka detail semua record; pasien memilih diary mana yang
dibagikan. Mini Summary memakai tujuh tanggal WIB termasuk hari ini, tanpa last
diary entry. Ekspor diary menghilangkan tanggapan profesional, dan ekspor mood
menghilangkan kolom catatan. Diary asli, emoji dan chart mood tetap dipertahankan.
Rujukan: [spesifikasi](superpowers/specs/2026-11-09-clinical-experience-design.md).

## Sesi satu jam dan rutinitas resep — 10 November 2026

Sesi satu kali dan paket menggunakan Video pada booking baru pasien, dengan
durasi default 60 menit dan minimum 60 menit. Paket menambah jumlah pertemuan
dan masa berlaku; sesi satu kali tetap memiliki chat, worksheet dan lampiran
profesional pada waktu yang diizinkan. Pilihan Chat dan durasi lama tidak lagi
ditawarkan untuk booking baru; riwayat dan pembayaran lama tetap dipertahankan.

Pasien dapat menentukan consent sebelum sesi. Tanpa paket aktif, berbagi dan
akses record profesional berlangsung hanya sepanjang durasi sesi; paket aktif
mempertahankan akses sesuai consent antarsesi. Reschedule memperbarui semua
informasi jadwal, dan pembatalan satu kali tidak menyisakan relasi tanpa hak
perawatan lain. Messages juga menampilkan pasangan sesi mendatang yang belum
bertukar pesan.

Psikiater terverifikasi menerbitkan resep beserta rutinitas obat dan stok pasien
melalui satu alur. Jadwal WIB, jumlah per dosis dan pengingat stok tersimpan
bersama resep, sehingga pasien tidak perlu menyusun ulang instruksi dokter.
Migrasi 036–038 tersedia dan diuji lokal; penerapan produksi belum dilakukan
dalam pekerjaan ini. Perpanjangan sesi legacy mempertahankan jam mulai dan
dapat menimbulkan irisan jadwal yang perlu direkonsiliasi sebelum rilis.

Penulis resep yang merupakan psikiater terverifikasi dapat menyimpan draft,
menerbitkan, mengedit beberapa obat dan menghapus resep secara soft-delete.
Diagnosis/indikasi dan instruksi per obat disimpan dari input dokter. Draft
hanya terlihat penulis; penghapusan/draft menonaktifkan obat pasien, sementara
riwayat konsumsi dan audit dipertahankan. Pasokan resep dipisahkan dari stok
berjalan: perubahan pasokan menyesuaikan selisihnya tanpa menghapus konsumsi
pasien. QR lama tidak berlaku setelah revisi, draft atau penghapusan.
