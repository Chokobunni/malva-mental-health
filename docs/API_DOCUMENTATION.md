# API Documentation

### Ulasan dan jarak profesional — 8 November 2026

`GET /v1/doctors/search` mengirim `average_stars`, `review_count`, dan
`helpfulness_count` dari ulasan pasien yang tersimpan, termasuk urutan populer
dan rating. `POST /v1/doctors/{user_id}/reviews` menerima `stars` wajib 1–5,
`review_text` opsional maksimal 2.000 karakter, dan `helpful` opsional (default
true). Bintang disimpan independen dari pilihan terbantu. Hanya pasien yang
memiliki hak ulasan yang belum dipakai dengan profesional tersebut dapat mengirim.
`GET /v1/review-entitlements` (pasien terautentikasi) mengembalikan `entitlements`
berisi `professional_id`, `professional_name`, `completed_at` WIB dan tepat satu
dari `session_id` / `care_package_id`. Satu sesi satu kali `completed` memberi satu
hak. Setiap pembelian paket memberi satu hak setelah seluruh kuota pembeliannya
terpakai oleh `completed`/`no_show`, tanpa sesi scheduled/pending pada rentang
pembelian itu, dan setidaknya satu completed;
pembatalan profesional tidak menghabiskan kuota. Paket seluruhnya no-show tidak
memberi hak. Pemeriksaan berasal dari sesi aktual, tanpa menunggu sweeper paket.
Penggabungan saldo paket tetap berlaku: pembelian 4+4 tampil sebagai saldo 8, tetapi
tetap memiliki dua hak terpisah memakai ID baris pembelian asal yang dipertahankan.
Kuota pembelian awal adalah total target dikurangi kuota seluruh pembelian merged;
baris merged menyimpan kuota pembelian tambahannya. Sesi yang memakai kuota
(completed/no_show/scheduled/pending_payment, tanpa pembatalan) diurut scheduled_at,id
dan dialokasikan ke rentang pembelian: awal lebih dulu, lalu merged_at,created_at,id
(tanggal merge legacy kosong lebih dulu). Empat pertama terminal dapat diulas
walau empat berikutnya masih scheduled. Hak pembelian lanjutan juga menunggu seluruh pertemuan pemakai kuota
sebelumnya terminal: kehadiran yang belum diputuskan masih dapat dibatalkan
profesional dan mengembalikan kredit, sehingga urutan belum stabil. Setelah
prefix terminal, pembatalan/reschedule tidak dapat menghapus urutan sebelumnya.
Pembelian tambahan tidak mengganti ID hak
lama, dan unique index mencegah reschedule/pembatalan membuat ulasan kedua pada ID
yang sudah dipakai. Ownership tidak cocok, kuota tidak dapat direkonsiliasi atau
rantai merged bertingkat yang ambigu tidak diberi hak sampai rekonsiliasi.
`completed_at` adalah akhir jadwal sesi terminal, atau akhir jadwal terakhir hanya
dari sesi completed/no_show dalam rentang pembelian; bukan waktu konfirmasi profesional yang mungkin
terlambat. Akhir jadwal stabil setelah terminal, sementara updated_at berubah saat
edit ringkasan. Karena itu detail edit tidak membuka lagi hak legacy. Penyelesaian
terlambat atas jadwal lama dapat tetap ditekan oleh cutoff legacy secara konservatif.
POST menerima salah satu ID tersebut (opsional); klien lama tanpa ID memakai hak
tertua yang tersedia. Otorisasi, pemeriksaan dan penyimpanan atomik di server;
konflik, belum selesai, ID asing atau sudah diulas menghasilkan 409. Salah role 403.
Pengiriman paralel tetap menghasilkan satu ulasan per unit. Nama penulis pada
daftar ulasan tetap tersamar.

Migrasi 035 mempertahankan ulasan lama tanpa mengarang tautan: unit yang selesai
pada/sebelum ulasan legacy tanpa ID terakhir untuk pasangan pasien/profesional
tidak ditawarkan lagi. Unit yang selesai sesudahnya tetap tersedia. Legacy dengan
created_at NULL menutup seluruh unit pasangan itu sampai rekonsiliasi manual.
Tidak ada backfill atau penghapusan ulasan. Aplikasi meminta ulasan setelah refresh,
resume atau kembali ke layar pasien (poll 30 detik); pembatalan dialog menekan
prompt otomatis unit itu selama sesi aplikasi, sementara aksi manual tetap ada.
Profil profesional hanya menampilkan ulasan pasien yang tersimpan; contoh/demo
tidak ditampilkan. Rata-rata, jumlah ulasan dan persentase terbantu memakai ulasan nyata.

Jarak dihitung dari koordinat pasien terkini dan praktik yang diketahui; tanpa
salah satunya aplikasi menampilkan alasan jarak belum tersedia. Urutan terdekat
menempatkan praktik tanpa koordinat terakhir. Migrasi 033 memperbaiki penghitung
legacy dan mengembalikan koordinat RSI Jemursari yang sudah dicatat migrasi 007
hanya bila identitas, nama/alamat praktik masih cocok dan kedua koordinat kosong.

### Perbaikan alur pasien — 5 November 2026

Kontrak yang ada dipertahankan: booking paket memakai `package_id` care package dan server memvalidasi pemilik serta menyelesaikan profesional dari paket. Retry pending memakai identifier yang sama; pembayaran dan aktivasi mengacu ke `care_packages.booking_id`, bukan `bookings.package_id` legacy. Respons status pembayaran direkonsiliasi terhadap Midtrans dan nominal sebelum dianggap lunas.

Chat memakai `POST /v1/therapy-submissions/{id}/share` dengan `professional_id`, lalu riwayat pesan; hindari `POST /v1/messages` kedua. Detail dibaca lewat `GET /v1/therapy-submissions/{id}` dengan otorisasi pemilik/penerima. Tidak ada endpoint atau DTO baru untuk fitur ini.

**Malva Mental Health App — Go Backend API**

| Field | Value |
|---|---|
| Base URL | `http://localhost:8080` (dev) |
| Version | v1 |
| Auth | JWT Bearer token |
| Format | JSON |
| Total Endpoints | 123 API (+1 static `/uploads/`) |

> **Catatan sinkronisasi:** inventaris rute lengkap dan **selalu sinkron** dengan
> kode ada di [`API_ROUTES.md`](API_ROUTES.md) (dibuat otomatis oleh
> `cd backend && go run ./cmd/apidoc`). Skema mesin-terbaca (OpenAPI 3.0.3) ada di
> [`openapi.yaml`](openapi.yaml). Dokumen ini adalah narasi manusia; sumber
> kebenaran jumlah & daftar endpoint adalah generator tersebut.
>
> **Keterbatasan `openapi.yaml`:** skema mencakup **seluruh** path, method, autentikasi,
> dan respons (200/400/401/403/404/422/500). Namun `requestBody` baru terisi untuk
> **12 endpoint inti** (register, login, refresh, change-password, screenings,
> mood-checkins, bookings, payments, care-packages, care-sessions, crisis-alerts,
> webhooks/payment); `requestBody` endpoint lain menyusul per modul.

---

## 1. Authentication

All authenticated endpoints accept JWT via:
- Header: `Authorization: Bearer <token>`
- Query: `?access_token=<token>`

### Token Lifecycle

```
Register/Login → {access_token, refresh_token}
                    ↓
         Use access_token for API calls
                    ↓
         access_token expires (24h)
                    ↓
         POST /v1/auth/refresh → new tokens
                    ↓
         Old refresh_token is revoked
```

## 2. Common Response Formats

### Success

```json
{
  "key": { ... }
}
```

### Error

```json
{
  "error": "error message"
}
```

### Rate Limit (auth endpoints only)

```
429 Too Many Requests
```

## 3. Endpoints

### 3.1 System

---

#### `GET /`

Returns an HTML status page.

**Auth:** None

**Response:** HTML page

---

#### `GET /healthz`

Health check endpoint.

**Auth:** None

**Response:**
```json
{
  "status": "ok"
}
```

---

### 3.2 Authentication

---

#### `POST /v1/auth/register`

Register a new user.

**Auth:** None (rate-limited: 20 req/min per IP)

**Request:**
```json
{
  "email": "user@example.com",
  "password": "min8chars",
  "display_name": "John Doe",
  "role": "patient",
  "professional_id": "1234567890123456"
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| email | string | ✅ | Unique |
| password | string | ✅ | Min 8 characters |
| display_name | string | ✅ | |
| role | string | ✅ | "patient" or "professional" |
| professional_id | string | ⚠️ | Required if role="professional" (license number) |

**Response:** `201 Created`
```json
{
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "role": "patient",
    "display_name": "John Doe"
  },
  "access_token": "eyJ...",
  "refresh_token": "abc...",
  "token_type": "Bearer",
  "expires_in": 86400
}
```

---

#### `POST /v1/auth/login`

Login with email and password.

**Auth:** None (rate-limited)

**Request:**
```json
{
  "email": "user@example.com",
  "password": "password"
}
```

**Response:** `200 OK`
```json
{
  "user": { "id": "uuid", "email": "...", "role": "...", "display_name": "..." },
  "access_token": "eyJ...",
  "refresh_token": "abc...",
  "token_type": "Bearer",
  "expires_in": 86400
}
```

---

#### `POST /v1/auth/refresh`

Rotate refresh token and get new access + refresh tokens.

**Auth:** None (rate-limited)

**Request:**
```json
{
  "refresh_token": "old_refresh_token"
}
```

**Response:** `200 OK`
```json
{
  "user": { "id": "uuid", "email": "...", "role": "...", "display_name": "..." },
  "access_token": "new_jwt...",
  "refresh_token": "new_refresh...",
  "token_type": "Bearer",
  "expires_in": 86400
}
```

---

#### `POST /v1/auth/logout`

Revoke a refresh token.

**Auth:** None (rate-limited)

**Request:**
```json
{
  "refresh_token": "token_to_revoke"
}
```

**Response:** `200 OK`
```json
{
  "status": "logged_out"
}
```

---

#### `GET /v1/me`

Get current authenticated user info.

**Auth:** Any authenticated user

**Response:** `200 OK`
```json
{
  "user": {
    "id": "uuid",
    "email": "user@example.com",
    "role": "patient",
    "display_name": "John Doe"
  }
}
```

---

#### `POST /v1/auth/unbind-google`

Lepas tautan akun Google (Gmail) dari akun pasien/profesional **tanpa mengubah UUID user**. Bila akun dibuat lewat "Login Google" (hash password acak), `new_password` **wajib** diisi agar akun tetap bisa login setelah Gmail dilepas; akun ber-password boleh memakai `current_password`. Unbind juga menghapus token OAuth Google (Google Meet ikut nonaktif). Kolom `email` akun **tidak diubah**: setelah unbind akun tetap ada dan Gmail itu tetap email kontaknya.

**Auth:** Bearer (patient/professional), rate-limited

**Request (body opsional — boleh kosong):**
```json
{
  "current_password": "opsional — password saat ini",
  "new_password": "opsional — password baru (wajib bila akun Google-only)"
}
```

**Response:** `200 OK` (bentuk sama dengan `GET /v1/auth/google-identity`)
```json
{
  "linked": false,
  "email_is_placeholder": false
}
```

**Error 409 `perlu_password`** (kredensial belum diberikan):
```json
{ "error": "Tetapkan password baru dulu agar akun tetap bisa dipakai setelah Gmail dilepas.", "code": "perlu_password" }
```

Kode mesin lain: `password_salah` (401, password saat ini salah), `google_belum_tertaut` (409, akun belum tertaut Google).

---

### 3.3 Device Tokens

---

#### `POST /v1/device-tokens`

Register or update a push notification device token.

**Auth:** Any authenticated user

**Request:**
```json
{
  "platform": "android",
  "token": "fcm_device_token_..."
}
```

**Response:** `200 OK`
```json
{
  "status": "saved"
}
```

---

### 3.4 Screening

---

#### `POST /v1/screenings`

Create a new PHQ-9/GAD-7 screening. Backend computes scores from raw answers.

**Auth:** Patient (self) or linked professional

**Request:**
```json
{
  "patient_id": "uuid",
  "phq9": [0, 1, 2, 0, 1, 0, 0, 0, 0],
  "gad7": [1, 0, 1, 2, 0, 1, 0],
  "source": "patient_app",
  "is_initial": true
}
```

| Field | Type | Required | Notes |
|---|---|---|---|
| patient_id | string | ⚠️ | Required if submitted by professional |
| phq9 | []int | ✅ | 9 answers, each 0-3 |
| gad7 | []int | ✅ | 7 answers, each 0-3 |
| source | string | ❌ | Default: "patient_app" |
| is_initial | bool | ❌ | Default: false |

**Response:** `201 Created`
```json
{
  "screening": {
    "id": "uuid",
    "patient_id": "uuid",
    "submitted_by": "uuid",
    "source": "patient_app",
    "is_initial": true,
    "rule_version": "2026.1",
    "overall_level": "mild",
    "crisis_flag": false,
    "created_at": "2026-07-30T10:00:00Z",
    "bundle": {
      "phq9": {
        "type": "phq9",
        "score": 4,
        "max_score": 27,
        "level": "mild",
        "summary": "Gejala ringan...",
        "crisis_flag": false,
        "answers": [...]
      },
      "gad7": { ... },
      "overall_level": "mild",
      "crisis_flag": false
    }
  }
}
```

**Side effects:**
- If crisis_flag=true, broadcasts to linked professionals via WebSocket

---

#### `GET /v1/screenings`

List screening sessions for a patient.

**Auth:** Patient (self) or linked professional (with consent)

**Query Parameters:**
| Param | Type | Required | Default |
|---|---|---|---|
| patient_id | string | ✅ | — |
| limit | int | ❌ | 20 (positive values max 100; `0` returns complete authorized patient history) |

**Response:** `200 OK`
```json
{
  "screenings": [
    {
      "id": "uuid",
      "patient_id": "uuid",
      "overall_level": "mild",
      "crisis_flag": false,
      "created_at": "...",
      "bundle": { "phq9": {...}, "gad7": {...} }
    }
  ]
}
```

---

#### `POST /v1/screenings/{screening_id}/review`

Review a screening session (professional only).

**Auth:** Professional only (must be linked to patient)

**Request:**
```json
{
  "status": "reviewed",
  "note": "Skor ringan, pantau rutin"
}
```

| Status Values | Description |
|---|---|
| `reviewed` | Screening has been reviewed |
| `needs_follow_up` | Requires follow-up action |
| `closed` | Review complete, no action needed |

**Response:** `200 OK`
```json
{
  "review": {
    "id": "uuid",
    "screening_session_id": "uuid",
    "status": "reviewed",
    "note": "...",
    "created_at": "..."
  }
}
```

---

#### `GET /v1/screening-reviews`

List screening reviews for a patient.

**Auth:** Patient (self) or linked professional

**Query:** `patient_id` (required), `limit` (optional, default 20)

**Response:** `200 OK`
```json
{
  "reviews": [
    {
      "id": "uuid",
      "screening_session_id": "uuid",
      "status": "reviewed",
      "note": "...",
      "created_at": "..."
    }
  ]
}
```

---

### 3.5 Patient-Professional Links

---

#### `POST /v1/patient-professional-links`

Link the current patient to a professional.

**Auth:** Patient only

**Request:**
```json
{
  "professional_id": "9999888877776666"
}
```

Note: `professional_id` is the license code from `professional_profiles.professional_id`.

**Response:** `201 Created`
```json
{
  "link": {
    "patient_id": "uuid",
    "professional_user_id": "uuid",
    "professional_id": "9999888877776666",
    "patient_display_name": "...",
    "professional_display_name": "...",
    "professional_photo_url": "https://.../photo.png",
    "status": "active",
    "created_at": "..."
  }
}
```

**Side effects:**
- Creates notification for the professional

---

#### `GET /v1/patient-professional-links`

List patient-professional links for the current user.

**Auth:** Any authenticated user

**Response:** `200 OK`
```json
{
  "links": [
    {
      "patient_id": "uuid",
      "professional_user_id": "uuid",
      "professional_id": "9999888877776666",
      "patient_display_name": "...",
      "professional_display_name": "...",
      "professional_photo_url": "https://.../photo.png",
      "status": "active"
    }
  ]
}
```

**Fields (setiap item `links`):**
| Field | Type | Keterangan |
|---|---|---|
| patient_id | string | UUID pasien |
| professional_user_id | string | UUID akun profesional |
| professional_id | string | Nomor/kode profesi (STR) dari `professional_profiles` |
| patient_display_name | string | Nama tampilan pasien |
| professional_display_name | string | Nama tampilan profesional |
| professional_photo_url | string | URL foto profil profesional (`professional_credentials.photo_intro_url`); string kosong bila profesional belum mengunggah foto |
| status | string | Status relasi, mis. `active` |

---

### 3.6 Professional Notes

---

#### `POST /v1/professional-notes`

Create a clinical note (professional only).

**Auth:** Professional only

**Request:**
```json
{
  "patient_id": "uuid",
  "body": "Pasien menunjukkan perbaikan mood...",
  "visibility": "private"
}
```

| Visibility | Description |
|---|---|
| `private` | Only visible to the authoring professional |
| `shared_with_patient` | Also visible to the patient |

**Response:** `201 Created`
```json
{
  "note": {
    "id": "uuid",
    "patient_id": "uuid",
    "professional_id": "uuid",
    "body": "...",
    "visibility": "private",
    "created_at": "..."
  }
}
```

---

#### `GET /v1/professional-notes`

List professional notes.

**Auth:** Patient (self) or linked professional

**Query:** `patient_id`, `professional_id`, `limit`

**Response:** `200 OK`
```json
{
  "notes": [...]
}
```

---

### 3.7 Follow-up Messages

---

#### `POST /v1/follow-ups`

Create a follow-up message (professional only).

**Auth:** Professional only

**Request:**
```json
{
  "patient_id": "uuid",
  "body": "Bagaimana kondisi Anda minggu ini?",
  "status": "sent"
}
```

**Response:** `201 Created`
```json
{
  "follow_up": {
    "id": "uuid",
    "patient_id": "uuid",
    "professional_id": "uuid",
    "body": "...",
    "status": "sent",
    "created_at": "..."
  }
}
```

---

#### `GET /v1/follow-ups`

List follow-up messages.

**Auth:** Patient (self) or linked professional

**Query:** `patient_id`, `limit`

**Response:** `200 OK`
```json
{
  "follow_ups": [...]
}
```

---

#### `PATCH /v1/follow-ups/{follow_up_id}/read`

Mark a follow-up message as read.

**Auth:** Patient only

**Response:** `200 OK`
```json
{
  "follow_up": { "...": "..." }
}
```

---

### 3.8 Mood Check-ins

---

#### `POST /v1/mood-checkins`

Create a daily mood check-in.

**Auth:** Patient only

**Request:**
```json
{
  "mood": "good",
  "sleep_hours": 7.5,
  "energy": 4,
  "anxiety": 2,
  "irritability": 1,
  "note": "Feeling good today",
  "occurred_at": "2026-07-30T10:00:00Z"
}
```

| Mood Values | Description |
|---|---|
| `great` | Sangat baik |
| `good` | Baik |
| `okay` | Cukup |
| `sad` | Sedih |
| `awful` | Buruk |

**Response:** `201 Created`
```json
{
  "mood": {
    "id": "uuid",
    "mood": "good",
    "sleep_hours": 7.5,
    "energy": 4,
    "anxiety": 2,
    "irritability": 1,
    "note": "...",
    "occurred_at": "...",
    "created_at": "..."
  }
}
```

---

#### `GET /v1/mood-checkins`

List mood check-ins.

**Auth:** Patient (self) or linked professional (with consent)

**Query:** `patient_id`, `limit`

**Response:** `200 OK`
```json
{
  "moods": [...]
}
```

---

### 3.9 Diary Entries

---

#### `POST /v1/diary-entries`

Create a diary entry.

**Auth:** Patient only

**Request:**
```json
{
  "mood": "great",
  "title": "Hari yang menyenangkan",
  "note": "Aktivitas hari ini sangat positif...",
  "shared_with_professionals": true,
  "occurred_at": "2026-07-30T10:00:00Z"
}
```

**Response:** `201 Created`
```json
{
  "diary": {
    "id": "uuid",
    "mood": "great",
    "title": "...",
    "note": "...",
    "shared_with_professionals": true,
    "occurred_at": "...",
    "created_at": "..."
  }
}
```

---

#### `GET /v1/diary-entries`

List diary entries.

**Auth:** Patient (self) or linked professional (with consent)

**Query:** `patient_id`, `limit`

**Response:** `200 OK`
```json
{
  "diaries": [...]
}
```

---

#### `PATCH /v1/diary-entries/{diary_id}/feedback`

Add professional feedback to a diary entry.

**Auth:** Professional only (must be linked, with consent)

**Request:**
```json
{
  "patient_id": "uuid",
  "feedback": "Catatan yang sangat baik, pertahankan!"
}
```

**Response:** `200 OK`
```json
{
  "diary": { "...": "..." }
}
```

---

### 3.10 Medications

---

#### `POST /v1/medications`

Create a medication entry.

**Auth:** Patient only

**Request:**
```json
{
  "name": "Sertraline",
  "dosage": "50mg",
  "form": "tablet",
  "reminder_time": "08:00",
  "relation_to_meal": "after_meal",
  "current_stock": 30,
  "alert_below": 5,
  "source": "professional"
}
```

**Response:** `201 Created`
```json
{
  "medication": {
    "id": "uuid",
    "name": "Sertraline",
    "dosage": "50mg",
    "form": "tablet",
    "reminder_time": "08:00",
    "relation_to_meal": "after_meal",
    "current_stock": 30,
    "alert_below": 5,
    "source": "professional",
    "active": true,
    "created_at": "..."
  }
}
```

---

#### `GET /v1/medications`

List medications.

**Auth:** Patient (self) or linked professional (with consent)

**Query:** `patient_id`, `limit`

**Response:** `200 OK`
```json
{
  "medications": [...]
}
```

---

### 3.11 Medication Logs

---

#### `POST /v1/medication-logs`

Log a medication intake/skip/miss.

**Auth:** Patient only

**Request:**
```json
{
  "medication_id": "uuid",
  "medication_name": "Sertraline",
  "status": "taken",
  "taken_at": "2026-07-30T08:05:00Z"
}
```

| Status Values | Description |
|---|---|
| `taken` | Medication taken |
| `skipped` | Intentionally skipped |
| `missed` | Forgot to take |

**Response:** `201 Created`
```json
{
  "medication_log": {
    "id": "uuid",
    "medication_name": "Sertraline",
    "status": "taken",
    "taken_at": "...",
    "created_at": "..."
  }
}
```

---

#### `GET /v1/medication-logs`

List medication logs.

**Auth:** Patient (self) or linked professional (with consent)

**Query:** `patient_id`, `limit`

**Response:** `200 OK`
```json
{
  "medication_logs": [...]
}
```

---

### 3.12 Timeline

---

#### `GET /v1/timeline`

Get merged timeline of events for a patient.

**Auth:** Patient (self) or linked professional (with consent)

**Query:** `patient_id`, `limit`

**Response:** `200 OK`
```json
{
  "events": [
    {
      "id": "uuid",
      "type": "screening|mood|diary|medication|medication_log",
      "title": "...",
      "body": "...",
      "created_at": "..."
    }
  ]
}
```

---

### 3.13 Audit Logs

---

#### `GET /v1/audit-logs`

List audit logs.

**Auth:** Patient (self) or linked professional

**Query:** `patient_id`, `limit`

**Response:** `200 OK`
```json
{
  "audit_logs": [
    {
      "id": "uuid",
      "action": "chat_message.sent",
      "entity_type": "chat_message",
      "created_at": "..."
    }
  ]
}
```

---

### 3.14 Privacy & Consent

---

#### `GET /v1/privacy/consents`

Get privacy consent settings for a specific professional.

**Auth:** Patient only

**Query:** `professional_id` (required)

**Response:** `200 OK`
```json
{
  "consent": {
    "professional_id": "uuid",
    "share_screenings": true,
    "share_mood_diary": true,
    "share_medications": true,
    "share_timeline": true
  }
}
```

---

#### `PUT /v1/privacy/consents`

Update privacy consent settings.

**Auth:** Patient only

**Request:**
```json
{
  "professional_id": "uuid",
  "share_screenings": true,
  "share_mood_diary": false,
  "share_medications": true,
  "share_timeline": false
}
```

**Response:** `200 OK`
```json
{
  "consent": { "...": "..." }
}
```

---

### 3.15 Chat Messages

---

#### `GET /v1/messages`

List chat messages between a patient and professional.

**Auth:** Must be one of the two linked users

**Query:**
| Param | Type | Required |
|---|---|---|
| patient_id | string | ✅ |
| professional_id | string | ✅ |
| limit | int | ❌ (default 20, max 200) |

**Response:** `200 OK`
```json
{
  "messages": [
    {
      "id": "msg_1234567890",
      "patient_id": "uuid",
      "professional_id": "uuid",
      "sender_id": "uuid",
      "sender_name": "Dr. Budi",
      "text": "Halo, bagaimana kondisi Anda?",
      "created_at": "2026-07-30T10:00:00Z"
    }
  ]
}
```

---

### 3.16 Notifications

---

#### `GET /v1/notifications`

List notifications for the current user.

**Auth:** Any authenticated user

**Query:** `limit` (optional, default 20)

**Response:** `200 OK`
```json
{
  "notifications": [
    {
      "id": "uuid",
      "type": "patient_linked",
      "title": "Pasien baru terhubung",
      "body": "...",
      "status": "sent",
      "created_at": "...",
      "read_at": "..."
    }
  ]
}
```

---

#### `PATCH /v1/notifications/read-all`

Mark all notifications as read.

**Auth:** Any authenticated user

**Response:** `200 OK`
```json
{
  "updated": 5
}
```

---

#### `PATCH /v1/notifications/{notification_id}/read`

Mark a single notification as read.

**Auth:** Any authenticated user

**Response:** `200 OK`
```json
{
  "notification": { "...": "..." }
}
```

---

#### `POST /v1/notifications/test`

Create and push a test notification.

**Auth:** Any authenticated user

**Response:** `201 Created`
```json
{
  "notification": { "...": "..." }
}
```

---

### 3.17 Crisis Alerts

---

#### `POST /v1/crisis-alerts`

Broadcast a crisis alert to all connected professionals.

**Auth:** Any authenticated user

**Request:**
```json
{
  "message": "Patient reported severe distress during session"
}
```

**Response:** `200 OK`
```json
{
  "status": "sent",
  "message": "Crisis alert dikirim ke profesional"
}
```

**Side effects:**
- Broadcasts via WebSocket to all connected professionals

---

### 3.18 WebSocket

---

#### `GET /v1/realtime/ws`

WebSocket endpoint for real-time events.

**Auth:** Via query param `?access_token=<jwt>` or `Authorization` header

**Protocol:** WebSocket (ws:// or wss://)

#### Client → Server Messages

**Chat Message:**
```json
{
  "type": "chat_message",
  "data": {
    "id": "msg_1234567890",
    "sender_id": "uuid",
    "sender_name": "Dr. Budi",
    "recipient_id": "uuid",
    "text": "Halo!",
    "timestamp": "2026-07-30T10:00:00Z"
  }
}
```

**Typing Indicator:**
```json
{
  "type": "typing_indicator",
  "data": {
    "sender_id": "uuid",
    "recipient_id": "uuid",
    "typing": true
  }
}
```

#### Server → Client Events

**Connection Confirmed:**
```json
{
  "type": "realtime.connected",
  "data": { "status": "ok" }
}
```

**Chat Message:**
```json
{
  "type": "chat_message",
  "data": {
    "id": "msg_1234567890",
    "sender_id": "uuid",
    "sender_name": "Dr. Budi",
    "recipient_id": "uuid",
    "text": "Halo!",
    "timestamp": "2026-07-30T10:00:00Z"
  }
}
```

**Typing Indicator:**
```json
{
  "type": "typing_indicator",
  "data": {
    "sender_id": "uuid",
    "typing": true
  }
}
```

**Presence:**
```json
{
  "type": "presence",
  "data": {
    "user_id": "uuid",
    "online": true
  }
}
```

**Screening Created:**
```json
{
  "type": "screening.created",
  "data": {
    "id": "uuid",
    "overall_level": "moderate",
    "crisis_flag": true
  }
}
```

**Notification Created:**
```json
{
  "type": "notification.created",
  "data": {
    "id": "uuid",
    "type": "patient_linked",
    "title": "...",
    "body": "..."
  }
}
```

### 3.19 Therapy Worksheet (Submissions)

---

#### `GET /v1/therapy-submissions`

`GET /v1/therapy-submissions` accepts optional `limit` (default 100, positive
values capped at 100). Explicit `limit=0` returns complete authorized history;
patient ownership, professional links, category consent and individual sharing
checks remain applicable.

#### `GET /v1/therapy-submissions/{submission_id}`

Detail memakai aturan kepemilikan/berbagi yang sama dengan daftar: pasien hanya
miliknya sendiri; profesional dengan relasi aktif dapat membaca pembagian
individual kepadanya atau consent kategori `therapy_records` dari pasien yang
sama. Consent milik pasangan lain tidak memberi akses. Akses data profesional
tetap dibatasi jendela sesi satu kali atau paket aktif. Record yang hilang atau
tidak berizin menghasilkan 404; klien tidak membuka jawaban snapshot sebagai
fallback atas penolakan tersebut.

#### `POST /v1/therapy-submissions/{submission_id}/share`

Bagikan worksheet terapi (termasuk hasil DASS-21 & WHO-5) ke profesional, atau
tarik izin berbagi bila `professional_id` dikirim kosong.

**Auth:** Patient only

**Path:**
| Param | Type | Required |
|---|---|---|
| submission_id | string | ✅ |

**Request:**
```json
{
  "professional_id": "uuid"
}
```

**Response:** `200 OK`
```json
{
  "submission": {
    "id": "uuid",
    "module_id": "dass21",
    "title": "DASS-21 (Depression Anxiety Stress Scales)",
    "summary": "Depresi 10 (Ringan) • Kecemasan 8 (Ringan) • Stres 12 (Normal)",
    "shared_with_professional_id": "uuid",
    "shared_at": "2026-07-30T10:00:00Z"
  },
  "chat_message_id": "uuid"
}
```

**Fields respons:**
| Field | Type | Keterangan |
|---|---|---|
| submission | object | Worksheet setelah diperbarui (`shared_with_professional_id`, `shared_at`) |
| chat_message_id | string | Opsional. Ada hanya bila pesan chat berhasil dibuat; kegagalan membuat pesan chat TIDAK menggagalkan share (worksheet tetap tersimpan dan profesional tetap menerima notifikasi in-app) |

**Side effects:**
- Membuat notifikasi in-app untuk profesional (`therapy_shared`)
- Membuat pesan chat berisi ringkasan worksheet: `kind` = `assessment` untuk DASS-21/WHO-5, `worksheet` untuk worksheet latihan lain. Pesan disiarkan lewat event realtime `chat_message` ke pasien & profesional

**Errors:** 400 (payload tidak valid) · 401 · 403 (bukan pasien, atau tidak punya paket sesi aktif dengan profesional tersebut) · 404 (worksheet tidak ditemukan) · 500

---

## 4. Error Codes

| HTTP Status | Meaning |
|---|---|
| 400 | Bad Request — invalid input |
| 401 | Unauthorized — missing or invalid token |
| 403 | Forbidden — wrong role or no consent |
| 404 | Not Found — resource doesn't exist |
| 409 | Conflict — duplicate resource |
| 429 | Too Many Requests — rate limited |
| 500 | Internal Server Error — server bug |

## 5. Rate Limits

| Endpoint Category | Limit | Window |
|---|---|---|
| Auth (register, login, refresh, logout) | 20 requests | Per minute per IP |
| All other endpoints | No limit | — |
# Session and clinical chat contracts — 2026-11-06

- PATCH /v1/care-sessions/{id}: status attended/absent marks the caller's own attendance; professional completed is allowed only after scheduled end. Responses add patient_attendance/professional_attendance (empty, attended, absent) and nullable *_attendance_marked_at. Legacy attended_marked_at remains available. Patient responses omit private_note. Omitted detail fields in PATCH are preserved.
- GET /v1/care-sessions: mobile feeds retain every scheduled session. Upcoming/today/ongoing are ordered nearest first; past/all include every scheduled row plus at most 100 other history rows. The response fields, scope values and ownership checks are unchanged. Internal bounded ListCareSessions callers retain their existing limit semantics.
- GET /v1/crisis-incident-log: counts.total covers SOS and screening records; counts.unresolved counts only SOS without resolved_at, independently of the item limit. Screening flags are historical records and do not support SOS resolution. POST /v1/crisis-incidents/{id}/resolve accepts empty resolution_notes after explicit confirmation.
- GET /v1/chat-permission: access adds session_id and nullable session_ends_at with WIB offset. Scheduled end is exclusive; terminal sessions never grant live access.
- POST /v1/messages and chat_message WebSocket events accept optional client_message_id UUID. Reuse the same UUID for one intent; a changed payload under the same UUID fails. Professional kinds: assessment_request metadata {session_id,module_id}, modules screening/dass21/who5; goals {session_id,goal_ids}; session_summary {session_id,goal_ids,insight}. Maximum 20 goal IDs, insight 2000 bytes. Server adds authoritative goals snapshots [{id,title,target_per_week}] to persisted homework cards. Clients cannot supply snapshots.
- POST /v1/goals accepts patient_id for verified linked professionals during the active, consented session and optional Idempotency-Key header (at most 128 printable ASCII characters without spaces). POST /v1/medications accepts the same optional header, scoped to caller and patient: an unchanged normalized payload returns the same active record; changed medication details with the same key are rejected.
- POST /v1/chat-attachments uses multipart recipient_id, file, optional client_message_id UUID. JPEG/PNG/WebP/PDF, 1 byte–10 MiB, content validated. Returns {message}, kind attachment, metadata {session_id,attachment_id,filename,mime,size,content_sha256}.
- GET /v1/chat-attachments/{id} returns private authenticated bytes with safe download headers; only the persisted message participants can read, including after session end. No public URL or access token query is returned.
- clinical_data_changed realtime event: {patient_id,resource}, resource medications/goals/health_record. Emitted after successful mutation. Refresh the patient data using current credentials; discard stale account responses. This event is not OS push.
- Medication create/update/delete by professional requires verified psychiatrist, linked patient, consent and active session. Health-record diagnosis and goals use corresponding consent scopes. Existing patient self-management remains supported.
- Payment GET status trusts configured authenticated HTTPS provider transport, binds response order to requested reference and enforces amount/fraud validation. Webhook signature remains required.
- Provider body codes are accepted only as 200 for capture/settlement, 201/pending, 202/deny and 407/expire. Unrecognized non-200 combinations stay pending; missing or mismatched orders cannot change state. Terminal reconciliation is idempotent and never activates an unpaid booking.

## Session and prescription contracts — 2026-11-10

- New patient `POST /v1/bookings` and `POST /v1/care-sessions` requests select
  Video automatically. An existing pending package booking retains its chosen
  type when payment is resumed. Historical Chat records remain readable.
  Session and availability duration defaults are 60 minutes; explicit values
  must be 60–180. Package scheduling derives duration from the practice slot.
- With server Calendar configured, a patient may book Video before the
  professional's Google grant is ready. Activation can return a session waiting
  for Meet; a server without Calendar integration still rejects Video.
- `POST /v1/care-sessions/{session_id}/reschedule` continues to accept
  `scheduled_at` as WIB `yyyy-MM-ddTHH:mm`. Session and originating booking
  date/time update atomically. Duration overlaps exclude the session being
  moved; competing moves/creates serialize per professional. Calendar failures
  after persistence are reported as warnings.
- `GET/PUT /v1/privacy/consents` reads/writes pair preferences, including before
  the session. Without an active package, professional record access and patient
  record sharing require a `scheduled` session with `start <= now < end`.
  An active package preserves access between sessions under explicit consent.
  Chat/Meet keep their separate ten-minute early join window.
- Worksheet share accepts a running one-time session or active package.
  Professional worksheet list/detail expires with one-time access. Professional
  `POST /v1/chat-attachments` requires verification, relationship and session,
  independently of patient-data consent. Persisted chat/attachment history
  retains its existing participant authorization.
- `POST /v1/e-prescriptions` item fields add `form`, `unit`, `current_stock`,
  `alert_below` and optional `schedule`; reads return them alongside the
  generated `medication_id`. New routines require positive dosage/stock, valid
  form/unit, selected days and positive `units_per_dose`. Scheduled routines
  require dose times; flexible routines use an explicit empty array. The verified
  psychiatrist and linked-patient authorization remains in force. Prescription,
  items and patient medications persist in one transaction.
- `schedule` uses `times` (`HH:mm`, WIB), `weekdays` (Monday=1, Sunday=7),
  `start_at` (RFC3339 with `+07:00`), `interval_hours`, `interval_days`,
  optional `interval_months` (integer, omitted/default 0, positive range 1–12),
  `units_per_dose` and `refill_enabled`. Hour/day/month intervals are mutually
  exclusive; zero means no interval of that kind. Legacy medication routines
  may be `{}` and keep their existing `reminder_time` behavior.
- Flexible routines use `times: []`, `interval_hours: 0`, `interval_days: 0`, `interval_months: 0`,
  valid `weekdays` and positive `units_per_dose`; `start_at` may represent the
  selected date at WIB midnight. Missing/null `times` and empty times with a
  nonzero interval are invalid. The patient medication keeps an empty
  `reminder_time`; no dose time is invented. Stock/refill settings and dose
  consumption continue to use the existing fields. Flexible mode requires no migration.
- Monthly routines (including psychiatric injections) retain the selected
  `start_at` and dose times with `interval_months: 1` through `12`. They represent
  calendar-month recurrence, not a fixed 30-day interval. Month intervals cannot
  be negative, null, fractional, strings, above 12 or combined with hour/day
  intervals; they require at least one dose time. Older schedules omitting the
  field remain valid. The key lives in existing schedule JSON; no migration or
  top-level request field is added.
- Monthly response compatibility: medication POST/PUT/list and prescription
  POST/PUT/detail/list/public QR responses expose `schedule.times: []` and
  `schedule.monthly_times` containing the canonical dose times when
  `interval_months > 0`. Medication responses also clear `reminder_time`.
  This prevents older clients from turning monthly injections into daily alarms.
  Updated clients restore `monthly_times` only for monthly schedules and send
  canonical nonempty `times` on writes, omitting the response-only key.
  Storage and audit snapshots keep canonical `times`; daily/flexible responses
  are unchanged. Previously installed alarms clear when the old client next
  refreshes medication data; the server cannot cancel offline device alarms.

Example daily routine:

```json
{"times":["08:00","20:00"],"weekdays":[1,2,3,4,5,6,7],"start_at":"2026-11-10T08:00:00+07:00","interval_hours":0,"interval_days":0,"units_per_dose":1,"refill_enabled":true}
```

Deploy migrations 036–040 before this backend version. They have been exercised
locally and have not been applied to production in this work. Migration 036
raises legacy durations below 60 without shifting appointment starts; adjacent
legacy appointments may therefore overlap. Unpaid checkouts continue to follow
the existing non-reservation policy and activation reschedule flow.

### Prescription CRUD and stock semantics

- `POST /v1/e-prescriptions` accepts `patient_id`, `status` (`issued` by default,
  or `draft`), `diagnosis`, `notes`, `instructions` and `items`. A draft may have
  no items. POST returns 201 and PUT returns 200 with the complete
  `{ "prescription": { ...header, "items": [...] } }` response.
- `PUT /v1/e-prescriptions/{id}` replaces the editable prescription contents.
  Omitted `patient_id` and `status` retain their existing values; the patient
  cannot change. Send each existing item's `id` to preserve its linked
  `medication_id`; omit `id` for new items. Missing old items are deactivated.
  Foreign/removed IDs or changed medication references return 409 and roll back
  the entire update. All other editable fields are full replacement values.
- `DELETE /v1/e-prescriptions/{id}` returns 200 `{ "status": "deleted" }`.
  It soft-deletes the prescription and deactivates its medications. Medication
  logs, removed item rows and audit records remain available in storage.
- Create/update/delete require a verified psychiatrist; only the author can
  update/delete (other verified authors receive 404; patients receive 403).
  Draft reads/lists are author-only. Patient lists/detail and public QR
  verification expose only issued prescriptions. Each save rotates the random
  QR token; draft/delete invalidate the previous QR and clear the signature.
- Item `current_stock` is the supplied quantity snapshot. Read-only
  `remaining_stock` is the linked medication's live stock. Editing supply applies
  the difference atomically: supplied 30 with remaining 25, changed to supplied
  40, yields remaining 35. An unchanged supply preserves consumption and patient
  stock adjustments. Draft → issued retains item/medication IDs and consumption.
  Do not send `remaining_stock` as the supplied quantity.
- Optional per-item `schedule.relation_to_meal` and `schedule.instructions`
  persist with the routine. Both are combined for the patient's medication meal
  instructions; global prescription instructions are the fallback only if both
  per-item values are empty. New routine items on issued prescriptions require
  positive supply; existing exhausted items may retain zero.
- Migration 039 adds diagnosis and item activity; migration 040 is a separate,
  idempotent backfill restricted to positive linked supply snapshots with no
  edits, taken/partial logs or ambiguous medication references. Unknown legacy
  zero supply is left unchanged.

### Goals & Habits configuration and daily progress (2026-11-12)

Migration 041 adds optional `details` to goal create/update/read and `value` /
`completed_step_ids` to habit logs. Existing goals without details preserve legacy
yes/no behavior, categories, weekly targets and history. Full field names, bounds
and response shapes are in [OpenAPI](openapi.yaml) and the
[feature contract](superpowers/specs/2026-11-12-patient-goals-reference.md).

GET `/v1/goals?on=YYYY-MM-DD` projects the selected WIB date's `done_today`,
`today_value`, `today_completed_step_ids`, `streak_days`, `is_due`, `failed_today`.
Create/update responses project today. Clients editing a historical view must
preserve that day's progress until the selected-date refresh completes.
Numeric/checklist completion derives from the current definition; progress fields
are independently patched atomically. Configured goals reject future/pre-start
logs; lock-past permits today and yesterday WIB. Inactive goals reject new progress.
Outside schedule, checklist writes may only correct an existing owned log for
that exact goal/date, including a row cleared to empty step IDs. A missing row
is rejected before upsert. These corrections do not count toward scheduled
weekly completion or streak. GET `/v1/habit-logs?from=DATE&to=DATE` returns all
owned logs on that date, including empty rows; broader history retains its
400-row cap. Flutter scopes presence to the account/request/date and does not
grant new correction permission when that read fails. Other methods
still require a scheduled date. Missing elapsed occurrences fail
only with auto-fail enabled. Goal/log ownership and clinical consent checks remain
mandatory. Additive migration 041 must run before the new API binary.

Refinement 2026-11-13 adds `recurrence: monthly` (interval1–12), anchored to
the original start day with short-month clamp and anchor restoration. Optional
`details.weekly_target`0–7 selects flexible weekly frequency; omission retains
selected weekdays, 0 has no quota. Empty rest days do not fail a flexible quota;
only fully elapsed active weeks below quota break auto-fail streaks. Explicit
failed logs still break streaks. `completed_weekdays` is the sorted ISO weekday
list of actual qualifying completions in the selected week through `on`.
`target_per_week` remains unchanged. Monthly/flexible writes normalize irrelevant
weekdays to[] after validation so older schedulers cannot guess daily alarms;
editing these settings requires the updated app. No additional migration is needed.

Synchronization correction 2026-11-13: steps on yes/no and numeric are activity
descriptions only, displayed as bullets without step controls. Legacy edit uses
the saved weekly quota and does not invent a reminder time. Card weekday counts
and enabled dates use the same effective schedule, clipped at the start date.
Reminder bells require a configured time and at least one offset (including 0).
The reminder dialog omits range helper text but still rejects values outside
0–10080. Existing payloads and schema remain unchanged.
