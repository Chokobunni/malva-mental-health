# SHA-1 / SHA-256 Fingerprints — Malva (Android)

Gunakan fingerprint berikut saat membuat **Android OAuth Client** di Google
Cloud Console untuk aplikasi Malva.

## Debug keystore (dipakai APK yang dibagikan saat ini)

APK release yang dibangun tanpa `android/key.properties` ditandatangani dengan
debug keystore (`%USERPROFILE%\.android\debug.keystore`), jadi fingerprint
debug inilah yang cocok untuk testing.

| Algoritma | Fingerprint |
|---|---|
| SHA-1 | `C3:09:B8:22:F4:D0:2F:B3:D5:4A:88:B0:9C:ED:08:E9:0E:20:AA:01` |
| SHA-256 | `49:6F:22:F9:78:FB:84:CA:21:0D:BB:70:F2:87:F7:A4:69:53:34:0B:D2:47:AC:38:9F:78:BA:62:3D:94:75:57` |

Keystore ini valid dari 30 Juli 2026 sampai 22 Juli 2056.

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
