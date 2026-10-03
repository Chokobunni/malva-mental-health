# Business Requirements Document (BRD) - Malva Mental Health

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
| | **Professional** | Chat + 1 video call 30 menit per sesi |
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
