# SHA-1 / SHA-256 Fingerprints — Malva (Android)

Gunakan fingerprint berikut saat membuat **Android OAuth Client** di Google
Cloud Console untuk aplikasi Malva.

## Release keystore (APK produksi saat ini)

APK `Malva-release-*.apk` yang dipublish 28 Okt 2026 ditandatangani dengan
release keystore (`android/malva-release-key.jks`, alias `malva` —
gitignored, JANGAN di-commit). **Fingerprint inilah yang WAJIB terdaftar**
sebagai Android OAuth Client, kalau tidak Login Google di APK release gagal
tanpa pesan / `ApiException: 10`.

| Algoritma | Fingerprint |
|---|---|
| SHA-1 | `9F:FC:92:19:10:39:31:77:B0:A4:5A:3C:4E:96:6E:90:DF:51:F5:91` |
| SHA-256 | `96:5F:74:30:EC:7F:67:A4:4B:7A:99:E8:3F:15:5E:60:11:16:FF:16:C1:8F:A8:DB:57:A4:E7:9D:E4:F2:D3:00` |

Keystore valid 28 Okt 2026 – 15 Mar 2054.

## Debug keystore (build lokal / flutter run)

APK debug / `flutter run` ditandatangani dengan debug keystore
(`%USERPROFILE%\.android\debug.keystore`). Daftarkan JUGA sebagai OAuth
client terpisah agar login Google jalan saat development:

| Algoritma | Fingerprint |
|---|---|
| SHA-1 | `C3:09:B8:22:F4:D0:2F:B3:D5:4A:88:B0:9C:ED:08:E9:0E:20:AA:01` |
| SHA-256 | `49:6F:22:F9:78:FB:84:CA:21:0D:BB:70:F2:87:F7:A4:69:53:34:0B:D2:47:AC:38:9F:78:BA:62:3D:94:75:57` |

## Cara mengecek ulang

```powershell
$keytool = "C:\Program Files\Microsoft\jdk-17.0.20.8-hotspot\bin\keytool.exe"
& $keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" `
  -alias androiddebugkey -storepass android -keypass android |
  Select-String "SHA1|SHA256"
```

## Mengecek ulang fingerprint keystore aktif

Release keystore aktif: `android/malva-release-key.jks`, alias `malva`
(gitignored, JANGAN di-commit; kredensial di `android/key.properties`,
juga gitignored). Bila keystore diganti/rotasi, daftarkan SHA-1 BARU
sebagai Android OAuth Client tambahan, lalu perbarui tabel di atas:

```powershell
$keytool = "C:\Program Files\Microsoft\jdk-17.0.20.8-hotspot\bin\keytool.exe"
& $keytool -list -v -keystore "android\malva-release-key.jks" -alias malva | Select-String "SHA1|SHA256|Valid"
```

CATATAN: jangan hapus OAuth client lama sebelum semua APK lama yang
masih dipakai ikut cocok dengan client baru (boleh ada banyak client
untuk satu package name).

## Package name

`id.malva.app` (lihat `android/app/build.gradle.kts` → `applicationId`).

## Verifikasi bahwa Android OAuth Client BENAR-BENAR ada

Mendaftarkan SHA-1 di Google Cloud Console tidak cukup — harus dibuktikan
bahwa konfigurasi itu benar-benar sampai ke aplikasi. Caranya: periksa file
`android/app/google-services.json`.

```bash
# Android OAuth Client = client_type 1. Web client = client_type 3.
grep -n '"client_type"' android/app/google-services.json
```

Yang benar: file memuat **minimal satu** entri `"client_type": 1` (Android)
yang `package_name`-nya `id.malva.app`, di samping entri `"client_type": 3`
(Web) yang dipakai sebagai `serverClientId`.

Yang SALAH (gejala bug 28 Okt 2026): file hanya berisi `client_type: 3`.
Artinya **Android OAuth Client belum pernah dibuat** untuk package + SHA-1
ini, sehingga Google Credential Manager (google_sign_in v7) tidak bisa
menerbitkan ID token. Dampaknya:

- tombol "Continue with Google" gagal di perangkat, dan
- **tidak ada** request `POST /v1/auth/google` sama sekali di log server
  (`journalctl -u malva-api`), karena kegagalan terjadi sebelum request
  keluar dari HP.

Bila `client_type: 1` belum ada:

1. Buka Google Cloud Console → APIs & Services → Credentials →
   **Create credentials → OAuth client ID → Android**.
2. Package name: `id.malva.app`.
3. SHA-1: daftarkan **dua kali** (dua client terpisah) — satu dengan SHA-1
   release, satu dengan SHA-1 debug dari tabel di atas.
4. Simpan, tunggu 5–10 menit (propagasi Google), lalu **unduh ulang**
   `google-services.json` dari Firebase Console → Project settings → Your
   apps → Android (`id.malva.app`) → `google-services.json`.
5. Ulangi pemeriksaan `grep '"client_type"'` di atas — harus muncul
   `client_type: 1`. Bila belum muncul, OAuth client belum tersimpan di
   project yang benar.

Langkah lengkap (termasuk cara mengecek APK sudah memuat client ID yang
sama): lihat `docs/GOOGLE_SIGNIN_SETUP.md` bagian **Diagnosa cepat**.
