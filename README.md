# Malva Mental Health App

Aplikasi mobile mental health yang menghubungkan pasien dengan profesional kesehatan mental. Built with Flutter + Go backend + PostgreSQL.

## Documentation

| Document | Description |
|---|---|
| [PRD](docs/PRD.md) | Product Requirements Document — fitur, user roles, success metrics |
| [BRD](docs/BRD.md) | Business Requirements Document — business rules, compliance, revenue |
| [Architecture](docs/ARCHITECTURE.md) | System architecture — components, data flows, security, deployment |
| [Database Schema](docs/DATABASE_SCHEMA.md) | All 20 tables with ERD, columns, constraints, indexes |
| [API Documentation](docs/API_DOCUMENTATION.md) | All 39 endpoints with request/response formats |
| [UI/UX Specification](docs/UI_UX_SPECIFICATION.md) | Design system, screen layouts, navigation, interactions |

## Tech Stack

| Component | Technology |
|---|---|
| Client | Flutter 3.44+ (Android, Web, Windows) |
| Backend | Go 1.22+ |
| Database | PostgreSQL 18 |
| Realtime | WebSocket (gorilla/websocket) |
| Push | Firebase Cloud Messaging (FCM) |
| Auth | JWT (HS256) + refresh token rotation |

## Quick Start

### Backend

```powershell
cd backend
copy .env.example .env
go run ./cmd/api
```

Database:

```text
database: malva
user: malva
password: malva_dev_password
port: 5432
```

Run migrations:

```powershell
$env:PGPASSWORD='malva_dev_password'
& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -h localhost -U malva -d malva -f .\migrations\001_initial.sql
& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -h localhost -U malva -d malva -f .\migrations\002_auth_sessions.sql
& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -h localhost -U malva -d malva -f .\migrations\003_professional_features.sql
& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -h localhost -U malva -d malva -f .\migrations\004_notification_center.sql
& 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -h localhost -U malva -d malva -f .\migrations\005_chat.sql
```

### Flutter

```powershell
flutter pub get
flutter test
flutter run --dart-define=MALVA_API_BASE_URL=http://127.0.0.1:8080
```

Android emulator:

```powershell
flutter run --dart-define=MALVA_API_BASE_URL=http://10.0.2.2:8080
```

## Features

### Patient

- PHQ-9 + GAD-7 screening (server-side scoring)
- Mood tracking (great/good/okay/sad/awful + sleep, energy, anxiety, irritability)
- Diary with professional feedback
- Medication management with reminders
- Real-time chat with professional
- Consent management (per-professional data sharing)

### Professional

- Patient dashboard with priority view
- Screening review (status + note)
- Professional notes (private / shared with patient)
- Follow-up messages
- Patient timeline
- CSV data export
- Crisis alerts

## File Structure

```
├── lib/
│   ├── src/
│   │   ├── screens/          # All UI screens
│   │   ├── services/         # API client, chat, push notifications
│   │   ├── store/            # State management
│   │   ├── models.dart       # Data models
│   │   ├── theme.dart        # Material 3 theme
│   │   └── assessment_engine.dart  # PHQ-9/GAD-7 scoring
│   └── main.dart
├── backend/
│   ├── cmd/api/main.go       # Entry point
│   ├── internal/
│   │   ├── server/           # HTTP handlers
│   │   ├── store/            # PostgreSQL queries
│   │   ├── realtime/         # WebSocket hub
│   │   ├── auth/             # JWT + password
│   │   └── screening/        # Assessment engine
│   ├── migrations/           # SQL migrations (001-005)
│   └── .env                  # Environment config
├── docs/                     # All documentation
└── test/                     # Flutter tests
```

## Security

- JWT authentication with refresh token rotation
- Role-based access control (patient / professional)
- Consent-gated data sharing
- Audit logging for all data mutations
- No sensitive data in push notification payloads
- Server-side screening score computation

## License

Private — Malva Team
