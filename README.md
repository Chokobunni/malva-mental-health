# Malva Mental Health App

Flutter MVP untuk aplikasi pasien dan profesional mental health. Source ini dibuat sebagai fondasi produk: UI utama sudah ada, data Flutter masih lokal, dan backend produksi mulai dipindahkan ke Go + PostgreSQL. Firebase hanya dipakai sebagai jalur push notification Android melalui FCM.

## Fitur MVP

- Login demo sebagai pasien atau profesional
- Home pasien dengan self-care, health check-in, dan alert
- Mood tracker dengan sleep, energy, anxiety, irritability, catatan, dan chart
- Medication tracker dengan reminder time, stock/refill alert, edit/add medication, dan `Take Now`
- Diary history dengan mood, catatan, dan professional feedback
- Goals & habits dengan streak, progress, reminder, dan create goal
- Health record untuk diagnosis, medication, dan dokumen klinis
- Professional dashboard untuk patient overview, alert, assessment review, dan diary queue
- PHQ-9 dan GAD-7 screening menggunakan deterministic forward chaining rule engine

## Cara menjalankan

Flutter SDK tidak tersedia di PATH pada environment pembuatan ini, jadi build belum dijalankan di sini. Setelah Flutter terpasang:

```bash
cd outputs/malva_app
flutter create . --platforms=android,web,windows --project-name malva_mental_health
flutter pub get
flutter run
```

Di Windows, cara yang lebih aman adalah menjalankan script ini dari root project:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup_flutter_project.ps1
```

Script tersebut membuat folder native `android/`, `web/`, dan `windows/`, lalu mengembalikan source Malva agar tidak tertimpa template default.

Untuk test rule engine:

```bash
flutter test
```

## Backend produksi Go

Backend awal ada di `backend/`:

```powershell
cd backend
copy .env.example .env
go run ./cmd/api
```

Komponen backend:

- PostgreSQL untuk database utama.
- Go HTTP API untuk auth, screening, token device, dan notification outbox.
- WebSocket untuk realtime saat app sedang terbuka.
- FCM sebagai push gateway Android saat app background/tertutup.

Flutter sudah punya dependency HTTP, WebSocket, secure storage, FCM, local
notifications, dan timezone. Untuk menjalankan Android emulator ke backend
lokal:

```powershell
flutter run --dart-define=MALVA_API_BASE_URL=http://10.0.2.2:8080
```

Untuk web/desktop lokal:

```powershell
flutter run --dart-define=MALVA_API_BASE_URL=http://127.0.0.1:8080
```

Gunakan Firebase hanya untuk konfigurasi FCM, bukan sebagai database utama.
Detail backend ada di `backend/README.md`; setup FCM ada di `docs/FCM_SETUP.md`.

## Reminder obat

Untuk medication reminder yang harus tepat waktu:

- Jadwalkan reminder lokal di device memakai `flutter_local_notifications`.
- Simpan jadwal di PostgreSQL melalui Go API.
- Pakai FCM untuk sinkronisasi perubahan jadwal, reminder lintas device, refill alert, dan pesan profesional.
- Jangan hanya mengandalkan FCM untuk jam minum obat karena delivery push tidak selalu presisi.
- Siapkan permission Android 13+ `POST_NOTIFICATIONS` dan kebutuhan exact alarm jika reminder harus presisi.

## Catatan klinis dan keamanan

- PHQ-9/GAD-7 di MVP ini memakai label ringkas/parafrasa. Untuk produksi, gunakan wording resmi atau terjemahan tervalidasi.
- Hasil asesmen harus ditampilkan sebagai screening, bukan diagnosis.
- PHQ-9 item self-harm positif harus memicu crisis flow.
- Data kesehatan mental adalah data sangat sensitif. Terapkan consent, role-based access control, audit log, retention policy, backup terenkripsi, dan minimisasi data.
- Jangan kirim diagnosis, diary lengkap, atau nama obat sensitif di notification lock screen jika privacy mode aktif.

## File penting

- `lib/src/assessment_engine.dart`: forward chaining PHQ-9/GAD-7
- `lib/src/store/malva_store.dart`: store lokal dengan jalur Go API untuk auth dan screening
- `lib/src/services/malva_api_client.dart`: client HTTP/WebSocket backend Go
- `lib/src/services/push_notification_service.dart`: registrasi token FCM ke backend
- `lib/src/screens/`: semua layar fitur
- `backend/`: Go API, migration PostgreSQL, WebSocket realtime, dan FCM outbox
- `lib/src/services/firebase_contracts.dart`: kontrak lama untuk gateway notifikasi; akan diganti repository Go API saat integrasi Flutter
- `test/assessment_engine_test.dart`: boundary test scoring
- `firebase/firestore.rules`: peninggalan starter Firebase rules, tidak menjadi database utama pada arsitektur Go
