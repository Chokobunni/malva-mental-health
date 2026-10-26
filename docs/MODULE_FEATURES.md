# MODULE_FEATURES — Matriks Fitur Malva

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

| FEAT-ID | Fitur | Role | Endpoint utama | Status |
|---|---|---|---|---|
| FEAT-020 | Mood check-in harian | Pasien | `GET /v1/mood-checkins`, `POST /v1/mood-checkins` | Aktif |
| FEAT-021 | Diary (CRUD + feedback) | Pasien | `/v1/diary-entries` (GET/POST/PUT/DELETE/PATCH) | Aktif |
| FEAT-022 | Manajemen obat | Pasien | `/v1/medications` (GET/POST/PUT/DELETE) | Aktif |
| FEAT-023 | Log minum obat | Pasien | `GET /v1/medication-logs`, `POST /v1/medication-logs` | Aktif |
| FEAT-024 | Goals & habit | Pasien | `/v1/goals`, `/v1/habit-logs` | Aktif |
| FEAT-025 | Therapy worksheet (simpan/bagikan) | Pasien, Profesional | `/v1/therapy-submissions` | Aktif |
| FEAT-026 | Timeline aktivitas | Semua | `GET /v1/timeline` | Aktif |

## 4. Booking & Pembayaran

| FEAT-ID | Fitur | Role | Endpoint utama | Status |
|---|---|---|---|---|
| FEAT-030 | Cari dokter & ketersediaan slot | Pasien (publik) | `GET /v1/doctors/search`, `/v1/doctors/{user_id}/slots`, `/availability` | Aktif |
| FEAT-031 | Profil dokter publik | Pasien (publik) | `GET /v1/doctors/{user_id}` | Aktif |
| FEAT-032 | Buat booking konsultasi | Pasien, Profesional | `POST /v1/bookings` | Aktif |
| FEAT-033 | Batalkan booking pending | Pasien | `POST /v1/bookings/{booking_id}/cancel` | Aktif |
| FEAT-034 | Bayar konsultasi (simulasi/gateway) | Pasien | `POST /v1/payments`, `POST /v1/payments/mark-paid` | Aktif (Midtrans untuk gateway) |
| FEAT-035 | Webhook pembayaran (signature) | Sistem | `POST /v1/webhooks/payment` | Aktif (Midtrans) |
| FEAT-036 | Ulasan dokter | Pasien | `GET/POST /v1/doctors/{user_id}/reviews` | Aktif |
| FEAT-037 | Pendapatan & pencairan (payout) | Profesional | `GET /v1/earnings`, `POST /v1/earnings/payout` | Aktif |
| FEAT-038 | E-prescription (resep elektronik) | Profesional (Sp.KJ) | `POST/GET /v1/e-prescriptions`, `GET /v1/e-prescriptions/verify` | Aktif |

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
| FEAT-048 | Quick video call (Meet) | Profesional | `POST /v1/meet/quick` | Aktif (butuh Google; fallback Jitsi) |

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
