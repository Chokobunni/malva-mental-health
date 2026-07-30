# API Documentation

**Malva Mental Health App — Go Backend API**

| Field | Value |
|---|---|
| Base URL | `http://localhost:8080` (dev) |
| Version | v1 |
| Auth | JWT Bearer token |
| Format | JSON |
| Total Endpoints | 39 |

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
| limit | int | ❌ | 20 (max 200) |

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
      "status": "active"
    }
  ]
}
```

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
