# Product Requirements Document (PRD)

**Malva Mental Health App**

| Field | Value |
|---|---|
| Version | 1.0 |
| Date | 2026-07-30 |
| Status | Production Ready |
| Author | Malva Team |

---

## 1. Executive Summary

Malva adalah aplikasi mobile mental health yang menghubungkan pasien dengan profesional kesehatan mental. Aplikasi ini menyediakan screening自我评估 (PHQ-9/GAD-7), mood tracking, medication management, diary, chat real-time, dan dashboard profesional untuk monitoring pasien.

## 2. Product Goals

| Goal | Metric | Target |
|---|---|---|
| Deteksi dini gangguan mental | Screening completion rate | > 80% pasien baru |
| Kepatuhan obat | Medication adherence rate | > 70% |
| Respon profesional | Crisis alert response time | < 24 jam |
| Kepuasan pengguna | User satisfaction score | > 4.0/5.0 |

## 3. User Roles

### 3.1 Patient (Pasien)
- Mengisi screening PHQ-9/GAD-7
- Tracking mood harian
- Menulis diary
- Mengelola obat dan reminder
- Chat dengan profesional
- Mengelola consent data sharing

### 3.2 Professional (Profesional)
- Melihat dashboard prioritas pasien
- Review screening results
- Memberikan feedback pada diary
- Membuat catatan klinis
- Mengirim follow-up message
- Monitoring obat pasien

## 4. Feature Requirements

### 4.1 Authentication & Session

| ID | Feature | Priority | Status |
|---|---|---|---|
| A-01 | Email/password registration (patient & professional) | P0 | ✅ Done |
| A-02 | Login with JWT access token | P0 | ✅ Done |
| A-03 | Token refresh rotation | P0 | ✅ Done |
| A-04 | Session persistence (secure storage) | P0 | ✅ Done |
| A-05 | Logout (revoke refresh token) | P0 | ✅ Done |

### 4.2 Screening (PHQ-9 & GAD-7)

| ID | Feature | Priority | Status |
|---|---|---|---|
| S-01 | PHQ-9 questionnaire (9 items) | P0 | ✅ Done |
| S-02 | GAD-7 questionnaire (7 items) | P0 | ✅ Done |
| S-03 | Combined screening (both in one session) | P0 | ✅ Done |
| S-04 | Server-side scoring (backend computes scores) | P0 | ✅ Done |
| S-05 | Crisis flag detection (PHQ-9 item 9 positive) | P0 | ✅ Done |
| S-06 | Screening history (list + trend) | P1 | ✅ Done |
| S-07 | Professional review (status + note) | P1 | ✅ Done |
| S-08 | Review-before-submit confirmation dialog | P1 | ✅ Done |

### 4.3 Mood Tracking

| ID | Feature | Priority | Status |
|---|---|---|---|
| M-01 | Daily mood check-in (great/good/okay/sad/awful) | P0 | ✅ Done |
| M-02 | Sleep hours tracking | P0 | ✅ Done |
| M-03 | Energy level (0-10) | P0 | ✅ Done |
| M-04 | Anxiety level (0-10) | P0 | ✅ Done |
| M-05 | Irritability level (0-10) | P0 | ✅ Done |
| M-06 | Free-form note | P1 | ✅ Done |
| M-07 | Mood chart visualization | P1 | ✅ Done |

### 4.4 Diary

| ID | Feature | Priority | Status |
|---|---|---|---|
| D-01 | Create diary entry (title + note + mood) | P0 | ✅ Done |
| D-02 | Diary history | P0 | ✅ Done |
| D-03 | Share with professionals toggle | P1 | ✅ Done |
| D-04 | Professional feedback on diary | P1 | ✅ Done |

### 4.5 Medication Management

| ID | Feature | Priority | Status |
|---|---|---|---|
| MD-01 | Add medication (name, dosage, form) | P0 | ✅ Done |
| MD-02 | Medication list | P0 | ✅ Done |
| MD-03 | Take Now / skip / miss logging | P0 | ✅ Done |
| MD-04 | Medication log history | P1 | ✅ Done |
| MD-05 | Stock tracking + low-stock alert | P1 | ✅ Done |
| MD-06 | Local notification reminder | P1 | ✅ Done |
| MD-07 | Reminder time configuration | P1 | ✅ Done |

### 4.6 Chat (Real-time)

| ID | Feature | Priority | Status |
|---|---|---|---|
| C-01 | WebSocket connection | P0 | ✅ Done |
| C-02 | Send/receive messages | P0 | ✅ Done |
| C-03 | Message persistence (PostgreSQL) | P0 | ✅ Done |
| C-04 | Typing indicator | P1 | ✅ Done |
| C-05 | Online presence | P1 | ✅ Done |
| C-06 | Offline message queue | P2 | ✅ Done |

### 4.7 Professional Dashboard

| ID | Feature | Priority | Status |
|---|---|---|---|
| P-01 | Patient list (linked patients) | P0 | ✅ Done |
| P-02 | Screening history per patient | P0 | ✅ Done |
| P-03 | Review screening (status + note) | P0 | ✅ Done |
| P-04 | Create professional note | P1 | ✅ Done |
| P-05 | Send follow-up message | P1 | ✅ Done |
| P-06 | View patient mood/diary/medication | P1 | ✅ Done |
| P-07 | Patient timeline | P1 | ✅ Done |
| P-08 | Crisis alert | P0 | ✅ Done |
| P-09 | CSV data export | P2 | ✅ Done |

### 4.8 Consent & Privacy

| ID | Feature | Priority | Status |
|---|---|---|---|
| CP-01 | Patient controls data sharing per professional | P0 | ✅ Done |
| CP-02 | Share screenings toggle | P0 | ✅ Done |
| CP-03 | Share mood/diary toggle | P0 | ✅ Done |
| CP-04 | Share medications toggle | P0 | ✅ Done |
| CP-05 | Share timeline toggle | P0 | ✅ Done |

### 4.9 Notifications

| ID | Feature | Priority | Status |
|---|---|---|---|
| N-01 | In-app notification list | P1 | ✅ Done |
| N-02 | Mark read / mark all read | P1 | ✅ Done |
| N-03 | FCM push notification | P1 | ✅ Done |
| N-04 | Notification outbox (retryable delivery) | P1 | ✅ Done |

### 4.10 Audit & Compliance

| ID | Feature | Priority | Status |
|---|---|---|---|
| AC-01 | Audit log for all data access | P0 | ✅ Done |
| AC-02 | Audit log viewer (professional) | P1 | ✅ Done |
| AC-03 | Data retention policy | P2 | ⏳ Planned |

## 5. Non-Functional Requirements

| Category | Requirement |
|---|---|
| **Security** | JWT HS256 authentication, bcrypt password hashing, role-based access control |
| **Security** | Consent-gated data access for professionals |
| **Security** | Audit logging for all data mutations |
| **Security** | No sensitive data in push notification payload |
| **Performance** | API response < 500ms (p95) |
| **Performance** | WebSocket message delivery < 100ms |
| **Availability** | Backend uptime > 99.5% |
| **Scalability** | Support 1000+ concurrent users |
| **Compliance** | Mental health data treated as sensitive health data |
| **Compliance** | Patient consent required for professional data access |
| **Platform** | Android (primary), Web, Windows (desktop) |

## 6. Tech Stack

| Component | Technology |
|---|---|
| Mobile Client | Flutter 3.44+ |
| Backend API | Go 1.22+ |
| Database | PostgreSQL 18 |
| Realtime | WebSocket (gorilla/websocket) |
| Push Notifications | Firebase Cloud Messaging (FCM) |
| Local Notifications | flutter_local_notifications |
| Secure Storage | flutter_secure_storage |
| Authentication | JWT (HS256) |

## 7. Success Metrics

| Metric | Measurement | Target |
|---|---|---|
| Daily Active Users | Firebase Analytics | 100+ by month 3 |
| Screening Completion | Backend audit logs | 80% of new patients |
| Medication Adherence | Medication logs / medications | 70% |
| Professional Response Time | Time between crisis alert and review | < 24 hours |
| User Retention | 30-day retention | > 40% |

## 8. Release Plan

| Phase | Scope | Status |
|---|---|---|
| MVP | Core features (screening, mood, diary, medication, chat, dashboard) | ✅ Complete |
| v1.0 | Production deployment, monitoring, security audit | 🔄 In Progress |
| v1.1 | Advanced analytics, multi-language support | ⏳ Planned |
| v2.0 | AI-powered insights, telehealth integration | ⏳ Planned |

## 9. Open Items

| Item | Owner | Due Date |
|---|---|---|
| Security audit for health data compliance | TBD | Before production |
| Load testing for 1000+ users | TBD | Before production |
| App Store / Play Store submission | TBD | v1.0 |
| Professional onboarding flow | TBD | v1.1 |
| Multi-language (Indonesian + English) | TBD | v1.1 |
