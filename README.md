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
Get-ChildItem .\migrations\*.sql | Sort-Object Name | ForEach-Object {
  & 'C:\Program Files\PostgreSQL\18\bin\psql.exe' -h localhost -U malva -d malva -f $_.FullName
}
```

> Migrasi saat ini: `001` s.d. `011` (auth, clinical, safety, chat, seed dokter,
> faskes Surabaya, kolom FC/CF, goals/therapy, field profil pengguna).
> Semua idempoten — aman dijalankan ulang.

### Akses database untuk admin

- **Backup & restore**: lihat `backend/admin_scripts/README_ADMIN_DATABASE.md`.
- **Kelola kontak darurat pasien**: `backend/admin_scripts/manage_emergency_contacts.sql`
  (monitor, tambah, edit, hapus, set kontak utama).
- **Kelola dokter & profilnya**: `backend/admin_scripts/manage_doctors.sql`
  (tambah profesional, atur spesialisasi/sub-spesialisasi, jadwal, paket,
  nonaktifkan/aktifkan, hapus).
- **Lewat aplikasi**: login sebagai admin → More → **Panel Admin**
  (kelola pengguna, dokter, dan verifikasi kredensial).

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

- Real register/login (email + password) & **Login with Google** — akun
  tersimpan di database (phone, birth date, gender tersimpan saat daftar)
- PHQ-9 + GAD-7 screening (server-side scoring + Forward Chaining &
  Certainty Factor, 18 rule pakar)
- Mood & Daily Check-in (great/good/okay/sad/awful + sleep, energy,
  anxiety, irritability) — tersimpan ke server
- My Diary History (mood + diary + catatan profesional, sesuai Figma)
- Goals & Habits dengan target mingguan + streak (tersimpan di server)
- Psychological Therapy lengkap (CBT/DBT/Relaksasi/Psikoedukasi) dengan
  worksheet yang bisa disimpan ke **folder therapy**, diunduh, dan
  dikirim ke profesional
- Continuous Support **7 Days** (pilih tanggal mulai, konsen sharing,
  pembayaran, terhubung ke chat dengan psikiater)
- Real-time chat + bagikan ringkasan/assessment/resep/goals/habits
- Kontak darurat (sampai 5, CRUD penuh + kontak utama) & Silent SOS
- Emergency contacts full CRUD

### Professional

- Patient dashboard with priority view
- Screening review (status + note, CF & rule trace)
- Professional notes (private / shared with patient)
- Follow-up messages
- Patient timeline
- CSV data export
- Crisis alerts

### Admin

- Panel Admin di aplikasi: kelola pengguna (nama/role/phone/birth
  date/gender/nonaktif), dokter (tambah/edit lengkap: spesialisasi,
  jadwal, paket, BPJS, koordinat), verifikasi kredensial
- Script SQL di `backend/admin_scripts/` untuk akses langsung database

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
│   ├── migrations/           # SQL migrations (001-011)
│   ├── admin_scripts/        # Script SQL admin (kontak darurat, dokter)
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
