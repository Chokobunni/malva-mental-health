# Product Requirements Document (PRD) - Malva Mental Health

### Kriteria penerimaan perbaikan pasien — 5 November 2026

- Retry booking/payment dan “Lanjut Bayar” mengacu ke intent pending yang sama. Cek status serta refresh otomatis merekonsiliasi Midtrans; callback bukan bukti lunas.
- Tab Paket MyCare memiliki filter `pending_payment`, `active`, dan `cancelled`.
- Chat pasien menyediakan pemilihan Therapy Record; asesmen tidak masuk daftar terapi. Profesional dapat membuka detail record yang dibagikan lewat pemeriksaan akses server.
- Pasien: chat sesi aktif, goals harian dan waktu obat saja untuk notifikasi mobile. Profesional: chat sesi aktif saja. Logout/pergantian role membatalkan reminder pasien dan menolak hasil async milik akun lama.
- Hasil ringan dapat menampilkan `CF 68%` dari `0.72 × 0.95`; UI menjelaskan bahwa CF bukan probabilitas diagnosis atau tingkat keparahan.

**Malva Mental Health App**

| Field | Value |
|---|---|
| Version | **2.0** |
| Date | 2026-08-01 |
| Status | Production Ready + Safety Protocol |
| Author | Malva Team |

---

## 1. Executive Summary

Malva adalah aplikasi mental health yang menghubungkan pasien dengan profesional kesehatan mental. Dua jalur pengalaman pasien: **Jalur Normal** (dashboard dipersonalisasi berdasar kondisi screening) dan **Jalur Kritis** (Safety Protocol saat terdeteksi risiko self-harm). Semua UI menggunakan palet Malva (plum/orchid/pink/mint/amber/danger) secara konsisten.

## 2. Product Goals

| Goal | Metric | Target |
|---|---|---|
| Deteksi dini gangguan mental | Screening completion rate | > 85% pasien baru |
| **Keselamatan pasien** | **Zero-miss crisis escalation** | **100%** |
| Kepatuhan obat | Medication adherence rate | > 80% |
| Respon profesional | Crisis alert response time | < 24 jam; push alert < 10 detik |
| Kepuasan pengguna | User satisfaction score | > 4.5/5.0 |

## 3. User Roles

### 3.1 Patient (Pasien)
- Onboarding: splash → role selection → SSO/email → micro-consent → PHQ-9/GAD-7 carousel → hasil → home
- Jalur kritis: SOS FAB, silent alert, hotline, grounding, emergency contacts
- Jalur normal: check-in mood inline, small wins, exercises, mood/diary/medication tracker, chat, booking
- Health record read-only (diagnosis oleh dokter saja) + document vault
- Consent management per profesional
- Emergency contacts management (maks 5 kontak)

### 3.2 Professional (Profesional)
- Registrasi dengan STR/SIP upload + verifikasi admin (PENDING → VERIFIED)
- Portal: metrics (Active/Unread/Pending), status chips (Crisis/Risk/Stable), patient cards dengan skor
- Manajemen: review screening, pro notes, follow-up, diary feedback, medication monitoring
- E-Prescription (psikiater): digital signature + STR/SIP number + QR
- Crisis incident log: active/past, resolution notes, liability trail
- Koreksi mobile 0.1.5: home kedua peran menampilkan video dan sesi chat terdekat dengan dropdown seluruh jadwal; Messages tersedia pada navigasi profesional. Quick Video Call ikut scroll jadwal, dan sesi lewat durasi diprioritaskan untuk diselesaikan. Screening pada Crisis Log ditampilkan sebagai riwayat; hanya SOS belum resolved memerlukan konfirmasi tindak lanjut, tanpa wajib mengetik catatan.
- Earnings: gross → platform fee → net → payout + transaction history
- Profil: STR/SIPP, video intro, pendidikan, topik keahlian, paket harga

---

## 4. Feature Requirements

### 4.1 Authentication & Session

| ID | Feature | Priority | Status |
|---|---|---|---|
| A-01 | Email/password registration | P0 | ✅ Done |
| A-02 | Login with JWT access token | P0 | ✅ Done |
| A-03 | Token refresh rotation | P0 | ✅ Done |
| A-04 | Session persistence (secure storage) | P0 | ✅ Done |
| A-05 | Logout (revoke refresh token) | P0 | ✅ Done |
| A-06 | **Account lockout protection** | P0 | ✅ Done |
| A-07 | **Change password** | P0 | ✅ Done |
| A-08 | **Google/Apple Single Sign-On** | P1 | 🔲 New |
| A-09 | **Progressive profiling** (no phone upfront) | P1 | 🔲 New |
| A-10 | **2FA/TOTP untuk profesional** | P1 | 🔲 New |
| A-11 | **Forgot password flow** | P1 | 🔲 New |

### 4.2 Onboarding & Screening

| ID | Feature | Priority | Status |
|---|---|---|---|
| OB-01 | Splash screen (flower logo + tagline) | P0 | ✅ Done |
| OB-02 | **Role selection screen** (I'm a Patient / I'm a Professional) | P0 | 🔲 New |
| OB-03 | Micro-consent modal sebelum screening | P0 | ✅ Done |
| OB-04 | **PHQ-9/GAD-7 carousel UI** (1 pertanyaan/slide, opsi bulat 0-3, progress dots) | P0 | 🔲 New |
| OB-05 | Screening result dengan **severity gauge/arc** + perayaan + rekomendasi dokter | P0 | 🔲 New |
| OB-06 | **Edukasi Psikiater vs Psikolog modal** di halaman hasil | P0 | 🔲 New |

### 4.3 Personalized Home (Jalur Normal)

| ID | Feature | Priority | Status |
|---|---|---|---|
| P-HOME-01 | **Condition banner** sesuai screening terakhir (Depression/Anxiety/Insomnia/Normal) | P0 | 🔲 New |
| P-HOME-02 | **Inline mood check-in** (5 emoji di home header) | P0 | 🔲 New |
| P-HOME-03 | **Small Wins Today** (behavioral activation micro-tasks checklist) | P0 | 🔲 New |
| P-HOME-04 | **Daily Exercises grid** (4-7-8 Breathing 3min, CBT Thought Practice 5min, Mindfulness 10min, Mood Journaling) dengan durasi | P0 | 🔲 New |
| P-HOME-05 | **Active Doctor Session card** (countdown sesi + Join Video + online dot) | P1 | 🔲 New |
| P-HOME-06 | **Doctor continuous support card** (Send Message) | P1 | 🔲 New |
| P-HOME-07 | **Medication tracker dengan adherence streak ring** | P1 | 🔲 New |

### 4.4 Safety Protocol (Jalur Kritis) — P0 URGENT

| ID | Feature | Priority | Status |
|---|---|---|---|
| S-PROTO-01 | **Empathetic crisis UI** (tema coral/amber lembut — gunakan palet Malva: paper + orchid/pink untuk breathing — bukan merah menyala) | P0 | 🔲 New |
| S-PROTO-02 | **Animated breathing circle** (4-7-8 guide, ring membesar-mengecil dengan countdown detik) | P0 | 🔲 New |
| S-PROTO-03 | **Pilar 1: PANGGIL HOTLINE 119 EXT 8 (BEBAS PULSA)** — tombol besar (MalvaColors.danger) | P0 | 🔲 New |
| S-PROTO-04 | **Pilar 2: SILENT SOS ALERT (KIRIM GPS KE KONTAK DARURAT)** — tombol (MalvaColors.amber) | P0 | 🔲 New |
| S-PROTO-05 | **Pilar 3: GUIDED GROUNDING (NO TALKING)** — tombol (MalvaColors.mint) | P0 | 🔲 New |
| S-PROTO-06 | **Feeling quick-chips** ("Napas Sesak", "Gemetaran", "Takut Sendirian") — tanpa suara/type | P0 | 🔲 New |
| S-PROTO-07 | **Emergency contacts list** dengan tombol Panggil/SMS per kontak | P0 | 🔲 New |
| S-PROTO-08 | **SOS FAB persisten** (ungu, semua layar pasien) | P0 | 🔲 New |
| S-PROTO-09 | **SOS confirmation state**: ✅ label sent + preview pesan SMS/WhatsApp dengan GPS link + status "Contacting Emergency Contacts... [LIVE]" + "dr. [nama] Notified (High Priority)" + fallback "Tap to Start Silent Grounding" | P0 | 🔲 New |
| S-PROTO-10 | **GPS sharing** dalam pesan SOS (geolocator, Google Maps link) | P0 | 🔲 New |
| S-PROTO-11 | **Rate-limit SOS blast** (1x per 10 menit per pasien — anti-spam) | P0 | 🔲 New |
| S-PROTO-12 | **Crisis incident log** (backend `crisis_incidents`: active→resolved dengan note + timestamp + triggered_by) | P0 | 🔲 New |
| S-PROTO-13 | **Escalation ladder**: unacknowledged doctor alert 5 menit → escalate ke admin piket | P1 | 🔲 New |
| S-PROTO-14 | **GPS purge** setelah incident resolved (privacy) | P1 | 🔲 New |

### 4.5 Emergency Contacts Management

| ID | Feature | Priority | Status |
|---|---|---|---|
| EC-01 | **CRUD emergency contacts** (nama, telepon, relasi) | P0 | 🔲 New |
| EC-02 | **Maksimal 5 kontak**, validasi format telepon Indonesia | P0 | 🔲 New |
| EC-03 | **Panggil/SMS langsung** dari emergency dashboard | P0 | 🔲 New |
| EC-04 | **Default kontak wajib saat crisis flag** | P0 | 🔲 New |

### 4.6 Mood & Daily Check-In

| ID | Feature | Priority | Status |
|---|---|---|---|
| D-CI-01 | Daily mood check-in (5 mood) + streak | P0 | ✅ Done |
| D-CI-02 | **Form lengkap**: 3 sliders 0-High (Anxiety, Irritability, Energy) + sleep hours stepper + medication toggle + note + Save Entry | P0 | 🔲 New |
| D-CI-03 | Sleep hours, Energy/Anxiety/Irritability 0-10 | P0 | ✅ Done |
| D-CI-04 | Mood chart visualization | P0 | ✅ Done |
| D-CI-05 | **Mood calendar** dengan hari berwarna | P1 | 🔲 New |
| D-CI-06 | **Metrics**: longest/current streak, total days | P1 | 🔲 New |
| D-CI-07 | **Combo chart** (mood bar + sleep line) | P1 | ✅ Done |
| D-CI-08 | **Radar chart Symptoms Balance** (pentagon 5-axis) | P1 | 🔲 New |

### 4.7 Medication Management

| ID | Feature | Priority | Status |
|---|---|---|---|
| MD-01 | Add medication + list + take/skip logging | P0 | ✅ Done |
| MD-02 | Stock tracking + low-stock alert | P0 | ✅ Done |
| MD-03 | Local notification reminder | P0 | ✅ Done |
| MD-04 | **Streak ring** ("Perfect! 100% adherence") | P0 | 🔲 New |
| MD-05 | **Today's Schedule** (08:00 Taken ✓ / 21:00 Take Now) | P0 | 🔲 New |
| MD-06 | **My Cabinet** (stock pills count + refill warnings) | P0 | 🔲 New |
| MD-07 | **Refill Now CTA prominent** saat stok < threshold | P0 | 🔲 New |

### 4.8 Health Record & Documents

| ID | Feature | Priority | Status |
|---|---|---|---|
| HR-01 | Health Record screen (record_screen) | P0 | ✅ Done |
| HR-02 | **Diagnosis banner dengan label "Only your doctor can edit"** (read-only pasien) | P0 | 🔲 New |
| HR-03 | **Document Vault**: search + filter tabs (All/Prescriptions/Billing/Letters) + upload + grid thumbnails dengan type icon (PDF/JPG) | P0 | 🔲 New |
| HR-04 | **Role-based write**: hanya profesional terverifikasi bisa edit diagnosis | P0 | 🔲 New |
| HR-05 | **Diagnosis banner prominen** (contoh: "F31.4 Bipolar Affective Disorder") | P0 | 🔲 New |

### 4.9 Goals & Habits

| ID | Feature | Priority | Status |
|---|---|---|---|
| G-01 | Goals screen | P0 | ✅ Done |
| G-02 | **Daily Progress bar** (persen completed) | P0 | 🔲 New |
| G-03 | **Streak indicator per goal** ("5🔥streak") | P0 | 🔲 New |
| G-04 | Goals/History tabs | P1 | 🔲 New |
| G-05 | FAB + tambah habit | P0 | ✅ Done |

### 4.10 Chat (Real-time)

| ID | Feature | Priority | Status |
|---|---|---|---|
| C-01 | WebSocket connection | P0 | ✅ Done |
| C-02 | Send/receive messages + persistence | P0 | ✅ Done |
| C-03 | Typing indicator + presence | P1 | ✅ Done |
| C-04 | Offlinemessage queue | P2 | ✅ Done |
| C-05 | **Mini Summary button** (ringkasan AI 14 hari data pasien) | P1 | 🔲 New |
| C-06 | **Video Session Summary card** dengan tasks checklist | P1 | 🔲 New |
| C-07 | **PDF attachment bubble** (icon + preview) | P1 | 🔲 New |
| C-08 | **Attachment toolbar**: photo, camera, file, voice, emoji | P1 | 🔲 New |
| C-09 | **Safety disclaimer chip** di awal chat | P1 | 🔲 New |
| C-10 | **Voice note recording** (record + playback bubble) | P1 | 🔲 New |

### 4.11 Booking & Payment

| ID | Feature | Priority | Status |
|---|---|---|---|
| B-01 | **Doctor discovery**: search + 6 sort (nama/jadwal/sesi/populer/jarak) + stats (sesi count, helpfulness%, ulasan, tahun pengalaman) + availability badge | P0 | 🔲 New |
| B-02 | **Filter profesional**: spesialisasi, harga, jarak (Haversine), BPJS | P0 | 🔲 New |
| B-03 | **Doctor profile page**: STR/SIPP number + video intro + pendidikan + topik keahlian chips + bio | P0 | 🔲 New |
| B-04 | **Booking detail**: tanggal + time slot chips (Haversine-priority) + durasi + harga | P0 | 🔲 New |
| B-05 | **Service selection**: Online/Offline; Quick Consult / Continuous Support | P0 | 🔲 New |
| B-06 | **Package picker**: 1/2/3/6 sesi + "Lebih Hemat" badge + validity 60/90/365 hari | P0 | 🔲 New |
| B-07 | **Payment Detail**: break-down (konsultasi + service fee = total) | P0 | 🔲 New |
| B-08 | **4 metode pembayaran**: E-Wallet (GoPay/OVO/DANA/ShopeePay), VA, Bank, Credit Card | P0 | 🔲 New |
| B-09 | **Payment Success**: cekmark + transaction reference + View Receipt + Continue | P0 | 🔲 New |
| B-10 | **Earnings (profesional)**: gross → platform fee -10% → net + payout request + transactions | P1 | 🔲 New |
| B-11 | **Data sharing consent modal** setelah pembayaran | P1 | 🔲 New |

### 4.12 Screening

| ID | Feature | Priority | Status |
|---|---|---|---|
| SCR-01 | PHQ-9/GAD-7 combined | P0 | ✅ Done |
| SCR-02 | Server-side scoring | P0 | ✅ Done |
| SCR-03 | Crisis flag detection | P0 | ✅ Done |
| SCR-04 | Screening history + trend + review | P0 | ✅ Done |

### 4.13 Professional Platform

| ID | Feature | Priority | Status |
|---|---|---|---|
| PP-01 | Priority dashboard (crisis queue + review queue) | P0 | ✅ Done |
| PP-02 | Patient list dengan search | P0 | ✅ Done |
| PP-03 | Patient detail + screening history | P0 | ✅ Done |
| PP-04 | Review, notes, follow-up, mood/diary/medication view, timeline, audit, export | P0 | ✅ Done |
| PP-05 | **Portal metrics**: Active/Unread/Pending count | P0 | 🔲 New |
| PP-06 | **Status chips**: Crisis/Risk/Stable count berwarna | P0 | 🔲 New |
| PP-07 | **Patient card dengan skor** (GAD-7/PHQ-9 + Crisis Severe badge + Review/Start Session) | P0 | 🔲 New |
| PP-08 | **E-Prescription (psikiater)**: tabel obat + instruksi + digital signature + STR/SIP + QR + issue | P0 | 🔲 New |
| PP-09 | **Crisis Incident Log**: active/past, triggered_by score, resolution notes, Mark Resolved | P0 | 🔲 New |
| PP-10 | **Advanced filter** pada daftar pasien (crisis/risk/stable) | P1 | 🔲 New |
| PP-11 | **Earnings dashboard** | P1 | 🔲 New |
| PP-12 | **Schedule management** (available slots untuk booking) | P1 | 🔲 New |

### 4.14 STR/SIP Verification (Admin)

| ID | Feature | Priority | Status |
|---|---|---|---|
| V-01 | **professional_credentials table** (str_number, sip_number, specialization, sub_specialties[], verification_status, document_url) | P0 | 🔲 New |
| V-02 | Profesional PENDING → tidak bisa akses data pasien sebelum VERIFIED | P0 | 🔲 New |
| V-03 | "Waiting verification" screen | P0 | 🔲 New |
| V-04 | **Admin interface**: list PENDING + approve/reject + review documents | P1 | 🔲 New |

### 4.15 Psychology Tests Marketplace

| ID | Feature | Priority | Status |
|---|---|---|---|
| TM-01 | Test catalog (Personality, Love Language, Happiness, Purpose of Life, Self Efficacy, Mental Health, Loneliness) | P1 | 🔲 New |
| TM-02 | Disclaimer wajib per tes: "Tes ini TIDAK ditujukan untuk mendiagnosis gangguan psikologis, namun untuk membantu mengenali kondisi diri" | P0 | 🔲 New |
| TM-03 | Hero "Apakah kamu baik-baik saja hari ini?" | P1 | 🔲 New |
| TM-04 | Per-test pricing | P1 | 🔲 New |

### 4.16 Consent & Privacy

| ID | Feature | Priority | Status |
|---|---|---|---|
| CP-01 | Patient controls data sharing per professional | P0 | ✅ Done |
| CP-02-05 | Share screenings/mood/medication/timeline | P0 | ✅ Done |
| CP-06 | **Granular consent**: Diary, Goals, **Health Record**, Mood Check-in, Medication Check-in | P0 | 🔲 New |
| CP-07 | Consent modal setelah pembayaran | P1 | 🔲 New |

### 4.17 Audit & Compliance

| ID | Feature | Priority | Status |
|---|---|---|---|
| AC-01 | Audit log for all data access | P0 | ✅ Done |
| AC-02 | Audit log viewer | P0 | ✅ Done |
| AC-03 | **Crisis incident audit trail** terpisah | P0 | 🔲 New |
| AC-04 | Data retention policy | P2 | ⏳ Planned |

### 4.18 UI/UX Global

| ID | Feature | Priority | Status |
|---|---|---|---|
| UX-01 | Crisis hero element HANYA warna MalvaColors.danger (no decorative red elsewhere) | P0 | ✅ Done |
| UX-02 | Warna status: semangat/mint, warning/amber, orchid/info, danger/krisis — selalu konsisten | P0 | ✅ Done |
| UX-03 | Rating/helpfulness badge hijau di kartu dokter | P0 | 🔲 New |
| UX-04 | Struktur nomor section dihapus dari navigasi professional (kembali ke tab-centric, konten tetapkomprehensif) | P1 | ✅ Done (current) |

---

## 5. Non-Functional Requirements

| Category | Requirement |
|---|---|
| **Security** | JWT HS256, bcrypt, RBAC, 2FA (planned), consent-gated, audit logging, CSRF, CSP, HSTS, SOS rate-limit |
| **Privacy** | GPS hanya durasi incident aktif (purge setelah resolve); professional data sensitive |
| **Performance** | API < 500ms p95; WebSocket < 100ms; SOS blast < 30 detik; FCM alert < 10 detik |
| **Availability** | Backend > 99.5%; SOS > 99.9% delivery |
| **Scalability** | 1000+ users; PostGIS untuk jarak |
| **Compliance** | UU PDP, UU Praktik Kedokteran (STR/SIP verifikasi), HIPAA reference, medical disclaimer wajib |
| **Design** | **Palet Malva 100% konsisten**: plum/orchid/pink gradient, mint (sehat), amber (warning), danger (krisis saja), ink (teks), paper (bg) |

## 6. Tech Stack

| Component | Technology |
|---|---|
| Mobile | Flutter 3.44+, Material 3, Riverpod |
| Backend | Go 1.22+ |
| Database | PostgreSQL 18 + **PostGIS** (jarak/discovery) |
| Realtime | WebSocket + FCM |
| Push | Firebase Cloud Messaging |
| AI Summary | **Gemini 1.5 Flash via Firebase AI Logic / Vertex AI** (script Go backend → JSON) — data tidak dipakai melatih model |
| Payment | **Midtrans/Xendit** (E-Wallet, VA, Bank, CC) — webhook dengan signature validation |
| SMS/WhatsApp gateway | **Fonnte/Twilio** — SOS blast |
| Maps | **flutter_map + OpenStreetMap** (gratis, no API key) |

## 7. Success Metrics

| Metric | Measurement | Target |
|---|---|---|
| Daily Active Users | Firebase Analytics | 100+ month 3 |
| Screening Completion | Backend audit | > 85% new patients |
| **Crisis Escalation** | **% crisis detected → escalated** | **100%** |
| **SOS Blast Delivery** | **% silent SOS terkirim &lt; 30 detik** | **> 99.9%** |
| Medication Adherence | Med logs / medications | > 80% |
| Professional Response Time | Crisis alert → review | < 24 jam |
| User Retention | 30-day retention | > 40% |
| Booking Conversion | Screening result → booking | > 15% |

## 8. Release Plan

| Phase | Scope | Status |
|---|---|---|
| **MVP** | Core: screening, mood, diary, medication, chat, dashboard, security | ✅ Complete |
| **v1.0** | Safety Protocol + emergency contacts + STR/SIP + booking/payment + discovery + portal metrics + earnings | 🚧 In Progress |
| v1.1 | CBT library + voice note + radar chart + multi-language | ⏳ Planned |
| v2.0 | AI-powered insights + telehealth video + E-Prescription fully + BPJS integration | ⏳ Planned |

## 9. Medical Disclaimer (Wajib di Semua Layar Screening)

> Hasil screening AI menggunakan instrumen PHQ-9/GAD-7 yang tervalidasi, tetapi **bukan diagnosis final**. Hasil harus divalidasi oleh psikiater/psikolog berlisensi sebelum keputusan medis apa pun. Dalam situasi darurat, hubungi hotline 119 ext 8 atau layanan darurat setempat.

## Regresi mobile 0.1.3

- Kartu video profesional tetap terbaca pada viewport 360px; tombol tidak menekan nama/jadwal menjadi vertikal.
- Aksi Detail pasien meneruskan sesi dan API profesional; Hadir memakai kontrak `attended` di backend.
- Sesi berjalan dan Video call mendatang tampil di home pasien, dengan avatar, keadaan kosong/error terpisah dan retry. Pasien tidak diberi aksi membuat link Meet milik profesional.
- Lanjut bayar paket legacy mengikat booking yang dipilih secara eksplisit dan tidak mengambil booking paket lain. Access token yang di-refresh dipakai untuk retry dan dipersistensikan.
- FCM data-only dan validator background menolak event di luar scope; upgrade/start/ganti akun membersihkan notifikasi yang sudah tampil tanpa menghapus jadwal goals/obat yang sah.
# Konsultasi dan attachment profesional — 2026-11-06

- Jadwal kedua peran menampilkan Hadir/Tidak hadir untuk kehadiran sendiri. Tombol Sesi selesai profesional aktif setelah akhir jadwal, dengan perpindahan ke riwayat dan penolakan transisi terminal ulang.
- Chat profesional memiliki lima alat: Goals & Habits pasien beserta penambahan goal; permintaan PHQ-9/GAD-7, DASS-21 atau WHO-5; Health Record diagnosis dan Medication khusus psikiater; gambar/PDF privat; rangkuman goals/homework dan insight.
- Pasien membuka form assessment yang sudah ada dari kartu permintaan pada sesi berjalan; hasil tetap dikirim oleh pasien. Kartu rangkuman menampilkan snapshot goal tersimpan dan tautan Goals. Lampiran dapat dibuka/diunduh oleh kedua peserta setelah sesi selesai.
- Composer chat menutup tepat pada session_ends_at, mempertahankan riwayat. Resume/reconnect menyegarkan izin dan data klinis; respons akun sebelumnya tidak boleh masuk akun berikutnya.
- Pembayaran capture/accept atau settlement yang diverifikasi server selesai tanpa menunggu webhook; jumlah, order dan fraud tetap divalidasi. Retry menggunakan transaksi yang sama.

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

- Popup chat obat, goals, diary, ringkasan dan assessment mengikuti referensi
  dengan hierarki skor/status yang terbaca. Seluruh bubble record dapat ditekan
  oleh profesional, termasuk akses detail melalui API berotorisasi. Diary dapat
  dipilih dari seluruh riwayat; timestamp mentah therapy tidak ditampilkan.
- Mini Summary memakai tujuh tanggal WIB, tanpa last diary entry atau label
  periode tetap pada Symptoms Balance Map. Recent mood maksimal tiga entri.
  PDF diary tanpa tanggapan; PDF mood tanpa kolom Catatan.
- Medication mendukung resep tanpa reminder di kartu, checklist, edit dan save.
  Ketiadaan jadwal tetap tersimpan tanpa mengarang jam. Notifikasi berwarna putih.
- Satu ulasan per sesi satu kali atau pembelian paket kontinu selesai. Paket
  merged 4+4 tetap memberi satu hak per pembelian setelah empat pertemuan masing-
  masing terminal dan minimal satu completed. Prompt mengikuti refresh/resume/poll
  pasien aktif; duplikasi dan kepemilikan ditegakkan server untuk semua klien.
- Home profesional memuat Sesi berjalan, Video call mendatang, Sesi chat mendatang,
  Operasional (Ketersediaan & Harga, Earnings), Klinis (e-prescription). Pasien
  memuat Data pasien dibagikan. Lainnya memuat Profil Profesional, Portal
  Profesional (termasuk STR/SIP) dan relasi pasien-profesional.
- Crisis Incident Log, Riwayat assessment dan Pasien terhubung di Home dihapus.
  Pemantauan harian tanpa Kiriman pasien/Timeline. Jadwal, Ringkasan Klinis serta
  hasil PHQ/GAD, WHO-5 dan DASS mengikuti referensi dengan data Malva; skala internal
  DASS tidak tampil. Aturan klinis, otorisasi, sesi dan SOS tetap berlaku.

Rujukan: [spesifikasi](superpowers/specs/2026-11-09-clinical-experience-design.md).
