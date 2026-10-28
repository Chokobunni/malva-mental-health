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

## Untuk production (release keystore)

Bila nanti memakai release keystore (file `android/key.properties`):

```powershell
& $keytool -list -v -keystore "C:\path\keystore.jks" -alias upload
```

Daftarkan SHA-1 release tersebut sebagai Android OAuth Client **tambahan**
(boleh ada banyak client untuk satu package name).

## Package name

`id.malva.app` (lihat `android/app/build.gradle.kts` → `applicationId`).
