# GitHub Push Guide - Development Version

Status project: development / belum final.

## Tujuan

Push project Malva ke GitHub tanpa menandainya sebagai versi final.

Cara yang aman:

- Push ke branch `develop`, bukan langsung menganggap `main` sebagai final.
- Jangan membuat release `v1.0.0`.
- Jangan membuat tag production.
- Gunakan commit message yang jelas bahwa ini masih MVP/dev.

## File yang Wajib Ikut GitHub

```text
.gitignore
analysis_options.yaml
pubspec.yaml
pubspec.lock
README.md
docs/
firebase/
lib/
scripts/
test/
web/
android/
windows/
```

## File yang Tidak Boleh Ikut GitHub

```text
.dart_tool/
build/
android/local.properties
*.iml
*.log
flutter_web_stdout.log
flutter_web_stderr.log
```

Alasan:

- `.dart_tool/` dan `build/` bisa dibuat ulang oleh Flutter.
- `android/local.properties` berisi path SDK lokal dari komputer tertentu.
- `.iml` dan folder IDE sering berbeda antar device.
- Log tidak dibutuhkan untuk source control.

## Command Push Pertama Kali

Jalankan dari folder project:

```powershell
cd C:\Users\dhima\Documents\Codex\2026-07-09\say\outputs\malva_app
git init
git checkout -b develop
git add .
git status
git commit -m "chore: initial Malva MVP development snapshot"
git remote add origin https://github.com/USERNAME/malva_app.git
git push -u origin develop
```

Ganti `USERNAME` dengan username GitHub kamu.

## Jika Ingin Main Tetap Ada Tetapi Tidak Final

```powershell
git checkout -b main
git push -u origin main
git checkout develop
```

Lalu di GitHub:

1. Buka repository settings.
2. Jadikan default branch `develop` selama development, atau tetap `main` tapi semua kerja harian masuk `develop`.
3. Gunakan Pull Request dari `develop` ke `main` hanya ketika fitur sudah stabil.

## Nama Branch yang Disarankan

```text
develop
feature/firebase-auth
feature/medication-reminder
feature/professional-dashboard
fix/diary-goals-edit
```

## Verifikasi Setelah Clone di Device Baru

```powershell
flutter pub get
flutter analyze
flutter test
flutter run
```

Jika Android Studio membuat ulang `android/local.properties`, itu normal.

## Catatan Keamanan

- Jangan commit file credential Firebase service account.
- Jangan commit `.env` berisi API key rahasia.
- Firebase web config bukan rahasia mutlak, tetapi tetap harus dipasangkan dengan Firebase Security Rules dan App Check.
- Data pasien mental health harus dianggap sensitif sejak awal.
