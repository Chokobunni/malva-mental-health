# Malva Architecture, Deployment, and Notification Plan

Last reviewed: 2026-07-10

## Prinsip

- UI utama aplikasi harus dibangun dengan Flutter. File `web/index.html` hanya dipakai sebagai bootstrap wajib Flutter Web.
- Data kesehatan mental adalah data sensitif. MVP boleh memakai free tier, tetapi produksi tetap membutuhkan audit keamanan, consent, backup, dan monitoring kuota.
- Screening PHQ-9 dan GAD-7 adalah data pendukung profesional, bukan diagnosis otomatis.

## Rekomendasi Stack Gratis Untuk MVP

### Database dan auth

Gunakan Firebase Spark plan untuk MVP:

- Firebase Auth: email/password pasien dan profesional.
- Cloud Firestore: data pasien, diary, mood, medication, goals, asesmen, dan link pasien-profesional.
- Firebase Security Rules: isolasi data per pasien dan akses profesional hanya melalui link resmi.
- Firebase Cloud Messaging: push channel, tetapi pengiriman otomatis tetap butuh trusted environment.

Catatan penting:

- Spark plan tidak meminta payment method, tetapi kuotanya terbatas.
- Cloud Functions tidak tersedia di Spark; server-side scheduled push yang benar membutuhkan Blaze atau server lain.
- Jangan menaruh isi diary lengkap dalam payload push notification.

### Deploy web gratis

Pilihan utama:

1. Cloudflare Pages untuk Flutter Web static build dari folder `build/web`.
2. GitHub Pages untuk demo statis sederhana.
3. Firebase Hosting Spark jika ingin satu ekosistem dengan Firebase.

Untuk mobile app:

- APK dapat dibuild lokal gratis.
- Distribusi Play Store/App Store tidak gratis dan membutuhkan akun developer berbayar.

## Struktur Firestore

```text
users/{uid}
  role: patient | professional
  displayName
  email
  professionalId
  createdAt

patients/{patientId}
  profile
    name
    dateOfBirth
    gender
    primaryProfessionalId
  initialScreeningStatus
  diagnosisSummary
  updatedAt

patients/{patientId}/screening_bundles/{bundleId}
  isInitial
  source
  createdAt
  phq9: { score, level, crisisFlag, answers }
  gad7: { score, level, crisisFlag, answers }
  overallLevel
  summary

patients/{patientId}/mood_entries/{entryId}
  date
  mood
  sleepHours
  energy
  anxiety
  irritability
  note
  createdAt
  updatedAt

patients/{patientId}/diary_entries/{entryId}
  createdAt
  updatedAt
  mood
  title
  note
  professionalFeedback
  reviewedBy
  reviewedAt

patients/{patientId}/goals/{goalId}
  title
  frequency
  reminderMinutesAfterMidnight
  note
  completedToday
  streakDays
  createdBy
  updatedAt

patients/{patientId}/medications/{medId}
  name
  dosage
  form
  currentStock
  alertBelow
  source
  active
  updatedAt

patients/{patientId}/medications/{medId}/reminders/{reminderId}
  hour
  minute
  relationToMeal
  repeatDaily
  timezone
  enabled

patients/{patientId}/medication_logs/{logId}
  medicationId
  medicationName
  takenAt
  status: taken | skipped | missed
  createdAt

patients/{patientId}/health_records/{recordId}
  title
  type
  storagePath
  lockedByProfessional
  createdBy
  createdAt

patient_professional_links/{patientId}_{professionalId}
  patientId
  professionalId
  status
  createdAt

notification_tokens/{uid}_{tokenHash}
  uid
  platform
  token
  createdAt
  lastSeenAt

audit_logs/{logId}
  actorUid
  targetPatientId
  action
  entityPath
  createdAt
```

## Notifikasi Medication Reminder

### MVP gratis dan tepat waktu di device

Gunakan local scheduled notifications:

1. Pasien/profesional mengubah jadwal obat.
2. App menyimpan jadwal di Firestore.
3. Saat app pasien aktif atau terbuka, app sync jadwal terbaru.
4. App menjadwalkan ulang local notification di device sesuai timezone pasien.
5. Saat pasien menekan "Take Now", app menulis `medication_logs` dan mengurangi stok.

Kelebihan:

- Tidak butuh server berbayar.
- Tetap bisa berbunyi pada jam obat karena alarm dijadwalkan di device.

Keterbatasan:

- Jika jadwal diubah profesional saat app pasien sudah lama tidak dibuka, device belum tentu menerima perubahan sampai app sync lagi.
- Perlu handling permission, timezone, daylight saving, dan reschedule setelah reboot.

### Realtime push lintas device

Untuk push otomatis ketika app tertutup:

1. Simpan FCM token di `notification_tokens`.
2. Firestore write pada medication reminder memicu trusted environment.
3. Trusted environment mengirim FCM data message tanpa isi data sensitif.
4. App pasien menerima data message dan menjadwalkan ulang local notification.

Catatan:

- FCM tidak berbayar, tetapi pengiriman otomatis yang aman membutuhkan trusted environment.
- Cloud Functions tidak tersedia di Spark. Jika wajib tanpa biaya kartu, gunakan local notification + sync saat app dibuka untuk MVP.

## Checklist Pindah Device atau IDE

1. Extract ZIP project.
2. Pastikan Flutter SDK tersedia.
3. Jalankan `flutter pub get`.
4. Jalankan `flutter analyze`.
5. Jalankan `flutter test`.
6. Untuk web: `flutter run -d chrome` atau `flutter run -d web-server`.
7. Untuk Android: buka folder di Android Studio dan biarkan Gradle regenerate `local.properties`.
