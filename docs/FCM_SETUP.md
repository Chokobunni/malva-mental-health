# FCM Setup untuk Malva

FCM dipakai hanya sebagai push gateway Android. Database, auth, screening,
realtime, dan audit tetap ada di Go + PostgreSQL.

## Yang perlu dibuat manual

1. Buat akun/proyek Firebase di console Firebase.
2. Tambahkan Android app dengan package name production Malva.
3. Unduh `google-services.json`.
4. Letakkan file itu di:

   ```text
   android/app/google-services.json
   ```

   Build Android akan tetap berjalan jika file ini belum ada. Begitu file
   tersedia, Gradle plugin Google Services akan otomatis aktif.

5. Pastikan package name Firebase sama dengan `applicationId` Android:

   ```text
   id.malva.app
   ```

6. Buat service account JSON untuk backend.
7. Simpan di server, misalnya:

   ```text
   /etc/malva/firebase-service-account.json
   ```

8. Set environment backend:

   ```text
   MALVA_FCM_CREDENTIALS_FILE=/etc/malva/firebase-service-account.json
   ```

   Jika file ini belum ada, kosongkan dulu env tersebut agar backend tetap
   jalan dengan no-op provider saat development/staging.

9. Restart backend setelah file credential masuk:

   ```bash
   sudo systemctl restart malva-api
   sudo journalctl -u malva-api -n 50 --no-pager
   ```

   Di production, log tidak boleh lagi menunjukkan provider FCM `no-op`.

## Checklist Android

- Package name di Firebase harus sama dengan `applicationId` Android.
- `android/app/google-services.json` tidak boleh di-commit.
- Android 13+ membutuhkan permission notification; manifest Malva sudah
  menyiapkan `POST_NOTIFICATIONS`.
- Flutter mengambil token dengan Firebase Messaging lalu mengirimnya ke backend
  `/v1/device-tokens` setelah login/register backend.
- Untuk production build, gunakan API Oracle:

  ```bash
  flutter build apk --release --dart-define=MALVA_API_BASE_URL=https://api.malva.id
  ```

## Checklist backend

- Service account JSON hanya disimpan di server, misalnya:

  ```text
  /etc/malva/firebase-service-account.json
  ```

- Permission file disarankan:

  ```bash
  sudo chown root:malva /etc/malva/firebase-service-account.json
  sudo chmod 640 /etc/malva/firebase-service-account.json
  ```

- Payload push notification Malva harus minimal. Jangan kirim isi catatan
  pasien, detail diagnosis, atau jawaban PHQ-9/GAD-7 lewat FCM. Kirim ID/event
  pendek, lalu app mengambil detail lewat API backend yang terautentikasi.

## Status kode saat ini

- Flutter sudah punya dependency `firebase_core` dan `firebase_messaging`.
- Flutter sudah mencoba registrasi token FCM setelah login backend.
- Backend sudah punya FCM provider.
- Jika credential Firebase belum ada, backend memakai no-op provider agar
  development lokal tetap berjalan.

## Penting

Jangan commit file berikut ke repository:

```text
android/app/google-services.json
firebase-service-account.json
```

Referensi resmi:

- <https://firebase.google.com/docs/cloud-messaging/flutter/get-started>
- <https://firebase.google.com/docs/admin/setup>
