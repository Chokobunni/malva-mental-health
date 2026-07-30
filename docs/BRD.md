# Business Requirements Document (BRD)

**Malva Mental Health App**

| Field | Value |
|---|---|
| Version | 1.0 |
| Date | 2026-07-30 |
| Status | Production Ready |

---

## 1. Business Context

### 1.1 Problem Statement

Indonesia memiliki kekurangan profesional kesehatan mental dengan rasio 1 psikiater per 100.000+ penduduk. Banyak pasien tidak memiliki akses rutin ke profesional, dan monitoring antar-sesi konsultasi sangat terbatas. Hal ini menyebabkan:

- Deteksi dini gangguan mental yang terlambat
- Kepatuhan obat yang rendah
- Kehilangan data klinis antar-sesi
- Krisis yang tidak terdeteksi tepat waktu

### 1.2 Solution

Malva menyediakan platform digital yang menghubungkan pasien dengan profesional kesehatan mental melalui:

1. **Self-assessment screening** (PHQ-9/GAD-7) untuk deteksi dini
2. **Mood & diary tracking** untuk monitoring harian
3. **Medication management** dengan reminder untuk kepatuhan obat
4. **Real-time chat** untuk komunikasi langsung
5. **Professional dashboard** untuk monitoring dan intervensi

### 1.3 Target Users

| Segment | Description | Est. Size |
|---|---|---|
| **Primary** | Pasien kesehatan mental (18-55 tahun) | 10M+ di Indonesia |
| **Secondary** | Psikiater, psikolog, konselor | 10,000+ di Indonesia |
| **Tertiary** | Rumah sakit, klinik mental health | 500+ fasilitas |

## 2. Business Objectives

| Objective | KPI | Timeline | Target |
|---|---|---|---|
| Launch MVP | App live di Play Store | Q3 2026 | ✅ |
| User Acquisition | Total registered users | Q4 2026 | 1,000 |
| Professional Onboarding | Active professionals | Q4 2026 | 50 |
| Screening Completion | % pasien yang mengisi screening | Q4 2026 | 80% |
| Medication Adherence | % obat tercatat | Q1 2027 | 70% |
| Revenue (v2.0) | Subscription revenue | Q2 2027 | Rp 50M/bulan |

## 3. Business Rules

### 3.1 User Registration

| Rule | Description |
|---|---|
| BR-01 | Pasien bisa mendaftar sendiri dengan email |
| BR-02 | Profesional memerlukan `professional_id` (license number) saat registrasi |
| BR-03 | Profesional harus diverifikasi sebelum bisa mengakses data pasien |
| BR-04 | Satu akun email hanya bisa memiliki satu role (patient ATAU professional) |

### 3.2 Patient-Professional Relationship

| Rule | Description |
|---|---|
| BR-10 | Pasien harus secara eksplisit menghubungkan (link) ke profesional |
| BR-11 | Profesional tidak bisa menghubungkan diri ke pasien |
| BR-12 | Satu pasien bisa terhubung ke multiple profesional |
| BR-13 | Hubungan bisa dinonaktifkan oleh pasien |

### 3.3 Data Access & Consent

| Rule | Description |
|---|---|
| BR-20 | Profesional hanya bisa melihat data pasien yang terhubung DAN memiliki consent |
| BR-21 | Pasien mengontrol data sharing per profesional (screening, mood, medication, timeline) |
| BR-22 | Catatan profesional (notes) hanya visible untuk profesional yang membuatnya |
| BR-23 | Follow-up message visible untuk pasien yang dituju |
| BR-24 | Audit log mencatat semua akses data |

### 3.4 Screening Rules

| Rule | Description |
|---|---|
| BR-30 | PHQ-9 item 9 (self-harm) positif = crisis flag |
| BR-31 | Crisis flag otomatis mengirim alert ke linked professionals |
| BR-32 | Backend selalu menghitung ulang skor dari jawaban mentah |
| BR-33 | Client tidak dipercaya untuk mengirim skor final |
| BR-34 | Screening结果 bukan diagnosis |

### 3.5 Medication Rules

| Rule | Description |
|---|---|
| BR-40 | Stock berkurang saat pasien menekan "Take Now" |
| BR-41 | Low-stock alert saat stock < alert_below |
| BR-42 | Reminder dijadwalkan di device menggunakan local notification |
| BR-43 | FCM digunakan untuk sinkronisasi perubahan jadwal |

### 3.6 Chat Rules

| Rule | Description |
|---|---|
| BR-50 | Chat hanya antara pasien dan profesional yang terhubung |
| BR-51 | Pesan di-persist di database (bukan hanya real-time) |
| BR-52 | Typing indicator hanya sementara (tidak di-persist) |
| BR-53 | Online presence real-time |

### 3.7 Notification Rules

| Rule | Description |
|---|---|
| BR-60 | Tidak ada data sensitif di push notification payload |
| BR-61 | Notification outbox untuk retryable delivery |
| BR-62 | Privacy mode: sembunyikan detail di lock screen |

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

## 5. Compliance Requirements

### 5.1 Health Data Regulations

| Regulation | Requirement | Status |
|---|---|---|
| UU PDP (Indonesia) | Consent untuk pengumpulan data pribadi | ✅ Implemented |
| UU Praktik Kedokteran | Data medis harus terenkripsi | ✅ Implemented |
| HIPAA (reference) | Minimum necessary access | ✅ Implemented |
| GDPR (reference) | Right to erasure | ⏳ Planned |

### 5.2 Security Requirements

| Requirement | Implementation | Status |
|---|---|---|
| Authentication | JWT with refresh token rotation | ✅ |
| Authorization | Role-based access control (RBAC) | ✅ |
| Data encryption | TLS in transit, encrypted backups | ✅ |
| Password security | bcrypt with salt | ✅ |
| Audit trail | All data mutations logged | ✅ |
| Consent management | Per-professional data sharing | ✅ |
| Rate limiting | Auth endpoints (20 req/min) | ✅ |

## 6. Revenue Model

### 6.1 Current (Free)

- Semua fitur gratis untuk MVP
- Target: user acquisition dan retention

### 6.2 Planned (v2.0)

| Tier | Price | Features |
|---|---|---|
| Basic | Free | Screening, mood, diary, medication |
| Premium | Rp 49,900/bulan | + Chat, advanced analytics |
| Professional | Rp 199,900/bulan | + Dashboard, patient management |
| Enterprise | Custom | + Multi-clinic, API access |

## 7. Risk Assessment

| Risk | Impact | Probability | Mitigation |
|---|---|---|---|
| Data breach | Critical | Low | Encryption, RBAC, audit logs |
| Professional liability | High | Medium | Disclaimer: screening bukan diagnosis |
| User low adoption | Medium | Medium | Onboarding flow, reminder |
| Server downtime | High | Low | Health checks, auto-restart |
| Regulatory changes | Medium | Medium | Modular compliance layer |

## 8. Success Criteria

| Criteria | Measurement | Target |
|---|---|---|
| Product-market fit | User retention (30-day) | > 40% |
| Clinical value | Professional satisfaction survey | > 4.0/5.0 |
| Technical reliability | API uptime | > 99.5% |
| Security | Zero data breaches | 0 incidents |
| Scalability | Support 10K+ users | Ready |
