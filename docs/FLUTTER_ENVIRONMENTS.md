# Environment Flutter Malva

Flutter Malva sudah disiapkan agar backend bisa diganti tanpa edit kode
langsung. Kuncinya adalah `--dart-define=MALVA_API_BASE_URL=...`.

## Default saat development

Jika tidak diberi `MALVA_API_BASE_URL`, app memakai default:

| Target | Default |
|---|---|
| Android emulator | `http://10.0.2.2:8080` |
| Web | origin browser saat ini |

`10.0.2.2` adalah alamat khusus Android emulator untuk mengakses backend yang
jalan di laptop host.

## Run lokal Android emulator

Pastikan backend Go lokal aktif di `127.0.0.1:8080`, lalu:

```bash
flutter run
```

Atau eksplisit:

```bash
flutter run --dart-define=MALVA_API_BASE_URL=http://10.0.2.2:8080
```

## Build production APK

Setelah Oracle domain siap:

```bash
flutter build apk --release --dart-define=MALVA_API_BASE_URL=https://api.malva.id
```

Untuk debug build yang mengarah ke production API:

```bash
flutter build apk --debug --dart-define=MALVA_API_BASE_URL=https://api.malva.id
```

## Build web jika nanti dibutuhkan

```bash
flutter build web --dart-define=MALVA_API_BASE_URL=https://api.malva.id
```

## Validasi sebelum build production

Jalankan:

```bash
flutter analyze
flutter test
flutter build apk --debug --dart-define=MALVA_API_BASE_URL=http://10.0.2.2:8080
```

Setelah API Oracle siap:

```bash
flutter build apk --release --dart-define=MALVA_API_BASE_URL=https://api.malva.id
```

## Catatan FCM

Push notification membutuhkan:

```text
android/app/google-services.json
```

Jika file belum ada, build tetap boleh berjalan untuk development, dan service
push notification akan gagal secara aman tanpa membuat app crash. Untuk
production, file ini wajib tersedia dan harus sesuai package name Android.

Package name production Malva:

```text
id.malva.app
```
