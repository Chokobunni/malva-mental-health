# System Architecture

**Malva Mental Health App**

| Field | Value |
|---|---|
| Version | 2.0 (Production) |
| Date | 2026-07-30 |
| Last Updated | 2026-07-30 |

---

## 1. Architecture Overview

```mermaid
graph TB
    subgraph Client["Flutter Client"]
        UI["UI Layer<br/>Screens + Widgets"]
        Store["State Management<br/>MalvaStore"]
        API["API Client<br/>MalvaApiClient"]
        Chat["Chat Service<br/>WebSocket"]
        FCM["Push Service<br/>FirebaseMessaging"]
        Local["Local Notifications<br/>flutter_local_notifications"]
    end

    subgraph Backend["Go Backend"]
        Router["HTTP Router<br/>39 endpoints"]
        Auth["Auth Middleware<br/>JWT + RBAC"]
        WS["WebSocket Hub<br/>Realtime Events"]
        Handlers["Handlers<br/>Business Logic"]
        StoreB["Store Layer<br/>SQL Queries"]
        Notif["Notification Service<br/>Outbox Pattern"]
    end

    subgraph Data["Data Layer"]
        PG[("PostgreSQL 18<br/>20 tables")]
        FCM2["Firebase Cloud<br/>Messaging"]
    end

    UI --> Store
    Store --> API
    Store --> Chat
    API --> Router
    Chat --> WS
    Router --> Auth
    Auth --> Handlers
    Handlers --> StoreB
    StoreB --> PG
    Notif --> FCM2
    WS --> Handlers
    FCM --> FCM2
    Local --> FCM
```

## 2. Component Architecture

### 2.1 Flutter Client

```
lib/
├── main.dart                          # Entry point + Firebase init
├── firebase_options.dart              # FlutterFire config (generated)
├── src/
│   ├── malva_app.dart                 # App root, session management
│   ├── models.dart                    # Data models (MoodValue, ScreeningBundle, etc.)
│   ├── theme.dart                     # Material 3 theme (light + dark)
│   ├── assessment_engine.dart         # PHQ-9/GAD-7 scoring engine
│   ├── store/
│   │   └── malva_store.dart           # Central state management + secure storage
│   ├── services/
│   │   ├── malva_api_client.dart      # HTTP client (all API calls)
│   │   ├── chat_service.dart          # WebSocket chat
│   │   ├── push_notification_service.dart  # FCM + local notifications
│   │   ├── medication_reminder_service.dart # Local notification scheduling
│   │   └── dashboard_sync_service.dart     # 30s polling sync
│   └── screens/
│       ├── login_screen.dart          # Auth (register + login)
│       ├── patient_shell.dart         # Patient bottom nav container
│       ├── home_screen.dart           # Patient home
│       ├── mood_screen.dart           # Mood tracking
│       ├── medication_screen.dart     # Medication management
│       ├── diary_screen.dart          # Diary
│       ├── assessment_screen.dart     # PHQ-9 + GAD-7
│       ├── chat_screen.dart           # Real-time chat
│       ├── more_screen.dart           # Settings + extras
│       ├── professional_dashboard_screen.dart  # Professional dashboard
│       └── consent_management_screen.dart      # Privacy controls
```

### 2.2 Go Backend

```
backend/
├── cmd/api/main.go                    # Entry point
├── internal/
│   ├── config/config.go               # Environment config
│   ├── auth/
│   │   ├── password.go                # bcrypt hash/check
│   │   ├── jwt.go                     # JWT create/verify
│   │   ├── refresh.go                 # Refresh token gen/hash
│   │   └── role.go                    # Role normalization
│   ├── store/store.go                 # PostgreSQL data access
│   ├── server/server.go               # HTTP handlers + routing
│   ├── realtime/hub.go                # WebSocket hub
│   └── screening/engine.go            # PHQ-9/GAD-7 scoring
├── migrations/
│   ├── 001_initial.sql                # Core tables
│   ├── 002_auth_sessions.sql          # Auth sessions
│   ├── 003_professional_features.sql  # Notes, follow-ups, reviews
│   ├── 004_notification_center.sql    # Notifications + outbox
│   └── 005_chat.sql                   # Chat messages
├── .env                               # Local environment
├── Dockerfile                         # Container build
└── docker-compose.yml                 # Local dev stack
```

## 3. Data Flow

### 3.1 Authentication Flow

```mermaid
sequenceDiagram
    participant C as Client
    participant API as Go API
    participant DB as PostgreSQL

    C->>API: POST /v1/auth/login {email, password}
    API->>DB: GetUserByEmail(email)
    DB-->>API: User{password_hash}
    API->>API: CheckPassword(hash, password)
    API->>API: Generate JWT (access_token)
    API->>API: GenerateRefreshToken()
    API->>DB: INSERT auth_sessions (refresh_token_hash)
    API-->>C: {access_token, refresh_token, user}

    Note over C,API: Subsequent requests
    C->>API: GET /v1/me (Authorization: Bearer access_token)
    API->>API: Verify JWT → Claims{sub, role}
    API-->>C: {user}
```

### 3.2 Screening Flow

```mermaid
sequenceDiagram
    participant P as Patient
    participant API as Go API
    participant DB as PostgreSQL
    participant WS as WebSocket Hub
    participant Prof as Professional

    P->>API: POST /v1/screenings {phq9: [0,1,2...], gad7: [1,0,2...]}
    API->>API: ScoreBundle(answers) → computed scores
    API->>DB: INSERT screening_sessions + screening_results + screening_answers
    API->>DB: Check crisis_flag (PHQ-9 item 9)
    alt Crisis flagged
        API->>WS: Broadcast to linked professionals
        WS->>Prof: {"type":"screening.created", "crisis_flag":true}
    end
    API-->>P: {screening: {id, overall_level, crisis_flag, bundle}}
```

### 3.3 Chat Flow

```mermaid
sequenceDiagram
    participant P as Patient
    participant WS as WebSocket Hub
    participant DB as PostgreSQL
    participant Prof as Professional

    P->>WS: {"type":"chat_message", "data":{sender_id, recipient_id, text}}
    WS->>DB: AreUsersLinked(sender, recipient)
    WS->>DB: CreateChatMessage(message)
    WS->>P: Echo: {"type":"chat_message", ...}
    WS->>Prof: Deliver: {"type":"chat_message", ...}

    Note over P,Prof: Typing indicator (ephemeral)
    P->>WS: {"type":"typing_indicator", "data":{recipient_id, typing:true}}
    WS->>Prof: {"type":"typing_indicator", ...}
```

### 3.4 Medication Reminder Flow

```mermaid
sequenceDiagram
    participant P as Patient
    participant App as Flutter App
    participant API as Go API
    participant DB as PostgreSQL
    participant OS as OS Notifications

    P->>App: Create medication (reminder_time: "08:00")
    App->>API: POST /v1/medications
    API->>DB: INSERT medications
    App->>App: Schedule local notification at 08:00

    Note over App,OS: At reminder time
    OS->>App: Notification tap
    App->>P: Show "Take Now" dialog
    P->>App: Tap "Take Now"
    App->>API: POST /v1/medication-logs {status: "taken"}
    API->>DB: INSERT medication_logs + UPDATE medications.stock
```

## 4. Security Architecture

### 4.1 Authentication & Authorization

```mermaid
graph LR
    Request --> AuthCheck{Auth Middleware}
    AuthCheck -->|No token| Reject[401 Unauthorized]
    AuthCheck -->|Invalid token| Reject
    AuthCheck -->|Valid JWT| Claims[Extract Claims]
    Claims --> RoleCheck{Role Check}
    RoleCheck -->|Wrong role| Reject[403 Forbidden]
    RoleCheck -->|Correct role| ConsentCheck{Consent Check}
    ConsentCheck -->|No consent| Reject
    ConsentCheck -->|Has consent| Handler[Execute Handler]
```

### 4.2 Data Access Matrix

| Resource | Patient Owner | Linked Professional | Unlinked Professional |
|---|---|---|---|
| Own screening | ✅ Read/Write | ✅ Read (with consent) | ❌ |
| Own mood | ✅ Read/Write | ✅ Read (with consent) | ❌ |
| Own diary | ✅ Read/Write | ✅ Read (with consent) | ❌ |
| Own medication | ✅ Read/Write | ✅ Read (with consent) | ❌ |
| Professional notes | ❌ (unless shared) | ✅ Read/Write (own) | ❌ |
| Follow-up messages | ✅ Read | ✅ Read/Write | ❌ |
| Chat messages | ✅ Read/Write | ✅ Read/Write | ❌ |
| Audit logs | ✅ Read (own) | ✅ Read (linked) | ❌ |
| Consent settings | ✅ Read/Write | ❌ | ❌ |

### 4.3 Security Controls

| Control | Implementation |
|---|---|
| Password hashing | bcrypt with cost factor 10 |
| JWT signing | HS256 with configurable secret |
| Token rotation | Refresh token rotated on every use |
| Session expiry | Access: 24h, Refresh: 30 days |
| Rate limiting | 20 req/min per IP on auth endpoints |
| Input validation | Server-side validation on all inputs |
| SQL injection | Parameterized queries (no string concatenation) |
| CORS | Configurable allowed origins |
| Audit logging | All data mutations logged with actor/patient |
| Data minimization | Only necessary data in responses |

## 5. Deployment Architecture

### 5.1 Development

```mermaid
graph LR
    Dev[Developer Machine]
    Flutter[Flutter Run]
    Go[Go Run]
    PG[(PostgreSQL Local)]

    Dev --> Flutter
    Dev --> Go
    Go --> PG
    Flutter -->|http://10.0.2.2:8080| Go
```

### 5.2 Production

```mermaid
graph TB
    subgraph Users["End Users"]
        Android[Android App]
        Web[Web App]
    end

    subgraph Cloud["Cloud Infrastructure"]
        LB["Load Balancer<br/>(Nginx/Caddy)"]
        API1["Go API Instance 1"]
        API2["Go API Instance 2"]
        PGPrimary[("PostgreSQL Primary")]
        PGReplica[("PostgreSQL Replica")]
        Redis["Redis<br/>(Session Cache)"]
    end

    subgraph External["External Services"]
        FCM["Firebase Cloud<br/>Messaging"]
        Firebase["Firebase Project<br/>(FCM only)"]
    end

    Android --> LB
    Web --> LB
    LB --> API1
    LB --> API2
    API1 --> PGPrimary
    API2 --> PGPrimary
    PGPrimary --> PGReplica
    API1 --> Redis
    API2 --> Redis
    API1 --> FCM
    API2 --> FCM
    FCM --> Firebase
```

### 5.3 Container Configuration

```dockerfile
# Dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 go build -o api ./cmd/api

FROM alpine:3.19
RUN apk --no-cache add ca-certificates
COPY --from=builder /app/api /api
EXPOSE 8080
CMD ["/api"]
```

## 6. Monitoring & Observability

| Metric | Tool | Alert Threshold |
|---|---|---|
| API response time | Application logs | > 500ms (p95) |
| Error rate | Application logs | > 1% of requests |
| WebSocket connections | Hub metrics | > 1000 concurrent |
| Database connections | PostgreSQL stats | > 80% pool usage |
| Memory usage | Container stats | > 80% of limit |
| Disk usage | PostgreSQL | > 80% of volume |
| FCM delivery rate | Firebase console | < 95% delivery |

## 7. Scalability Considerations

| Component | Current | Scaling Strategy |
|---|---|---|
| Flutter Client | Single build | Platform-specific builds (Android/iOS/Web) |
| Go API | Single instance | Horizontal scaling (multiple containers) |
| PostgreSQL | Single instance | Read replicas + connection pooling |
| WebSocket | Single hub | Sticky sessions or Redis pub/sub |
| FCM | Stateless | Managed by Firebase (auto-scales) |

## 8. Disaster Recovery

| Scenario | Recovery Strategy | RTO | RPO |
|---|---|---|---|
| API crash | Auto-restart (systemd/docker) | < 30s | 0 |
| Database crash | Restore from backup + WAL replay | < 1 hour | < 5 min |
| Full outage | Re-deploy from container image | < 2 hours | < 1 hour |
| Data corruption | Point-in-time recovery | < 4 hours | < 1 hour |

## 9. Migration Strategy

| Version | Changes | Downtime |
|---|---|---|
| 001_initial | Core tables (users, screenings, mood, diary, medication) | Zero |
| 002_auth_sessions | Refresh token sessions | Zero |
| 003_professional_features | Notes, follow-ups, screening reviews | Zero |
| 004_notification_center | Notifications + outbox | Zero |
| 005_chat | Chat messages | Zero |

All migrations use `CREATE TABLE IF NOT EXISTS` and are idempotent.
