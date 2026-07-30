# Malva Go Backend

Backend ini menggantikan rencana database Firebase untuk data utama. Firebase
Cloud Messaging hanya dipakai sebagai push gateway Android; database, auth,
screening, audit, realtime, dan notification outbox tetap dikelola oleh Go dan
PostgreSQL.

## Komponen

- Go HTTP API untuk auth, screening, device token, dan realtime WebSocket.
- PostgreSQL sebagai database klinis utama.
- WebSocket untuk update realtime saat aplikasi sedang terbuka.
- Notification outbox untuk push yang retryable.
- FCM provider sebagai adapter push Android. Provider ini bisa diganti tanpa
  mengubah logic domain.

## Jalankan lokal

```powershell
cd backend
copy .env.example .env
go run ./cmd/api
```

Di mesin Windows ini PostgreSQL 16 sudah dipasang native. Database development:

```text
database: malva
user: malva
password: malva_dev_password
port: 5432
```

Health check:

```powershell
Invoke-RestMethod http://localhost:8080/healthz
```

## Environment

- `MALVA_HTTP_ADDR`: alamat listen API, default `:8080`.
- `MALVA_DATABASE_URL`: URL PostgreSQL.
- `MALVA_JWT_SECRET`: secret HS256. Wajib diganti sebelum produksi.
- `MALVA_ALLOWED_ORIGINS`: daftar origin yang boleh memanggil API.
- `MALVA_FCM_CREDENTIALS_FILE`: path service-account JSON Firebase.
- `MALVA_FCM_CREDENTIALS_JSON`: isi JSON service-account Firebase.

Kalau credential FCM kosong, server memakai no-op provider. Ini sengaja agar
development backend tidak bergantung pada Firebase.

## Migration lokal

```powershell
$env:PGPASSWORD='malva_dev_password'
& 'C:\Program Files\PostgreSQL\16\bin\psql.exe' -h localhost -U malva -d malva -f .\migrations\001_initial.sql
& 'C:\Program Files\PostgreSQL\16\bin\psql.exe' -h localhost -U malva -d malva -f .\migrations\002_auth_sessions.sql
```

Jika database lokal lama sudah punya `001_initial.sql`, jalankan hanya migration
yang belum pernah diterapkan.

## Endpoint utama

- `GET /healthz`
- `POST /v1/auth/register`
- `POST /v1/auth/login`
- `POST /v1/auth/refresh`
- `POST /v1/auth/logout`
- `GET /v1/me`
- `POST /v1/device-tokens`
- `POST /v1/screenings`
- `GET /v1/screenings`
- `POST /v1/patient-professional-links`
- `GET /v1/patient-professional-links`
- `POST /v1/notifications/test`
- `GET /v1/realtime/ws`

## Catatan keamanan

- Jangan kirim skor, diagnosis, diary, nama obat, atau data sensitif di payload
  FCM yang muncul di lock screen.
- Backend selalu menghitung ulang PHQ-9/GAD-7 dari jawaban mentah. Client tidak
  boleh dipercaya untuk mengirim hasil final.
- Semua perubahan penting perlu audit log. Migration awal sudah menyiapkan
  tabel `audit_logs`.
- Endpoint auth punya rate limit in-memory dasar. Untuk multi-server production,
  pindahkan rate limit ke reverse proxy atau Redis.
- Contoh self-host deployment ada di `deploy/` dan `../docs/SELF_HOST_DEPLOYMENT.md`.
