# 🔐 Google Sign-In Setup Guide - Malva Mental Health

Panduan lengkap untuk mengaktifkan **Login dengan Google** di aplikasi Malva (Android & Web).

---

## 📋 **Prerequisites**

1. ✅ Akun Google (gunakan: `lxsdora@gmail.com`)
2. ✅ Akses ke [Google Cloud Console](https://console.cloud.google.com)
3. ✅ Akses ke [Firebase Console](https://console.firebase.google.com) (optional, jika pakai Firebase)

---

## 🎯 **Overview: Apa yang Dibutuhkan?**

Untuk Google Sign-In, Anda perlu:

1. **Google Cloud Project** dengan OAuth 2.0 Credentials
2. **Web Client ID** (untuk backend JWT verification)
3. **Android Client ID** (untuk Flutter app)
4. **OAuth Consent Screen** (configured)
5. **SHA-1/SHA-256 fingerprints** dari Android signing key

---

## 🚀 **STEP 1: Create Google Cloud Project**

### 1.1 Buka Google Cloud Console
- Go to: https://console.cloud.google.com
- Login dengan: `lxsdora@gmail.com`

### 1.2 Create New Project
1. Klik **Select a project** (top bar) → **NEW PROJECT**
2. **Project name**: `Malva Mental Health`
3. **Organization**: (leave as No organization)
4. Klik **CREATE**
5. **Wait 30-60 seconds** sampai project selesai dibuat

### 1.3 Enable Google Sign-In API
1. Di left sidebar: **APIs & Services** → **Library**
2. Search: `Google Sign-In API`
3. Klik **Google Sign-In API**
4. Klik **ENABLE**

---

## 🔑 **STEP 2: Configure OAuth Consent Screen**

### 2.1 Buka OAuth Consent Screen
- Left sidebar: **APIs & Services** → **OAuth consent screen**

### 2.2 Setup Consent Screen
1. **User Type**: Pilih **External** (untuk testing dengan akun manapun)
2. Klik **CREATE**

### 2.3 Fill App Information
- **App name**: `Malva Mental Health`
- **User support email**: `lxsdora@gmail.com`
- **App logo**: (optional, upload logo.png if available)
- **Application home page**: `https://malva.app` (atau leave blank)
- **Developer contact email**: `lxsdora@gmail.com`
- Klik **SAVE AND CONTINUE**

### 2.4 Scopes (Step 2)
- **Add or Remove Scopes**:
  - Pilih: `userinfo.email`
  - Pilih: `userinfo.profile`
  - Pilih: `openid`
- Klik **SAVE AND CONTINUE**

### 2.5 Test Users (Step 3)
- Klik **+ ADD USERS**
- Masukkan: `lxsdora@gmail.com`
- Masukkan akun test lain jika perlu
- Klik **SAVE AND CONTINUE**

### 2.6 Summary (Step 4)
- Review info
- Klik **BACK TO DASHBOARD**

---

## 🔐 **STEP 3: Create OAuth 2.0 Credentials**

### 3.1 Create Web Client ID (untuk Backend)
1. Left sidebar: **APIs & Services** → **Credentials**
2. Klik **+ CREATE CREDENTIALS** → **OAuth client ID**
3. **Application type**: **Web application**
4. **Name**: `Malva Backend Web Client`
5. **Authorized redirect URIs**: (leave empty for backend JWT verification)
6. Klik **CREATE**
7. **IMPORTANT**: Copy **Client ID** (format: `xxxxx.apps.googleusercontent.com`)
   - Save ke Notepad: `WEB_CLIENT_ID=xxxxx.apps.googleusercontent.com`

### 3.2 Create Android Client ID
1. Kembali ke **Credentials** page
2. Klik **+ CREATE CREDENTIALS** → **OAuth client ID**
3. **Application type**: **Android**
4. **Name**: `Malva Android App`
5. **Package name**: `id.malva.app` (PENTING — bukan `com.malva.mentalhealth`)
6. **SHA-1 certificate fingerprint**: gunakan nilai di bawah (lihat `docs/ANDROID_SHA_FINGERPRINTS.md`)

### 3.3 Get Android SHA-1 Fingerprint

Fingerprint debug keystore yang dipakai APK Malva saat ini:

- **SHA-1**: `C3:09:B8:22:F4:D0:2F:B3:D5:4A:88:B0:9C:ED:08:E9:0E:20:AA:01`
- **SHA-256**: `49:6F:22:F9:78:FB:84:CA:21:0D:BB:70:F2:87:F7:A4:69:53:34:0B:D2:47:AC:38:9F:78:BA:62:3D:94:75:57`

**Method A: Debug Keystore (untuk testing)**
```powershell
& "C:\Program Files\Microsoft\jdk-17.0.20.8-hotspot\bin\keytool.exe" -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -alias androiddebugkey -storepass android -keypass android
```
- Copy **SHA1** dan **SHA256** dari output
- Paste ke OAuth credential form

**Method B: Release Keystore (production)**
```powershell
& "C:\Program Files\Microsoft\jdk-17.0.20.8-hotspot\bin\keytool.exe" -list -v -keystore "D:\path\to\release.keystore" -alias upload -storepass YOUR_PASSWORD
```

7. Paste **SHA-1** ke form
8. Klik **CREATE**

> Catatan: bila nanti APK ditandatangani release keystore (android/key.properties),
> daftarkan juga SHA-1 release sebagai Android OAuth Client tambahan.

---

## 🛠️ **STEP 4: Configure Flutter App**

### 4.1 Add Web Client ID to Project

Edit file: `lib/src/config/google_config.dart` (already exists, just needs client ID)

**Cara 1: Build-time (Recommended)**
```powershell
# Build APK dengan Google Client ID:
flutter build apk --release --dart-define=MALVA_GOOGLE_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com --dart-define=MALVA_API_BASE_URL=http://192.168.1.2:8080
```

**Cara 2: Hardcode (Quick Testing)**
```dart
// Edit lib/src/config/google_config.dart:
class GoogleConfig {
  static const serverClientId = 'YOUR_WEB_CLIENT_ID.apps.googleusercontent.com';
  static bool get isConfigured => serverClientId.isNotEmpty;
}
```

### 4.2 No Android-specific Config Needed for Google Sign-In SDK
Package `google_sign_in` v7+ **TIDAK PERLU** file `google-services.json` untuk
proses OAuth-nya — cukup SHA-1 fingerprint terdaftar. (File `google-services.json`
tetap dipakai oleh Firebase FCM, bukan oleh Google Sign-In.)

---

## 🖥️ **STEP 5: Configure Backend (Go)**

Backend **sudah siap** — endpoint `/v1/auth/google` sudah ada dan akan
memverifikasi Google ID Token dengan public key Google.

Yang perlu dilakukan: isi **Web Client ID** (yang sama dengan
`MALVA_GOOGLE_CLIENT_ID` saat build Flutter) ke environment backend:

```powershell
# backend/.env
MALVA_GOOGLE_CLIENT_ID=xxxxx.apps.googleusercontent.com
```

Untuk sesi PowerShell saat menjalankan `api.exe`:

```powershell
$env:MALVA_GOOGLE_CLIENT_ID = "xxxxx.apps.googleusercontent.com"
```

Tanpa ini, `/v1/auth/google` menjawab HTTP 501 dan tombol Google di app
menampilkan pesan "Login Google belum dikonfigurasi".

> CATATAN: `MALVA_GOOGLE_CLIENT_ID` di backend dan `--dart-define` di Flutter
> **harus Client ID yang sama** (Web application type).

---

## ✅ **STEP 6: Test Google Sign-In**

### 6.1 Build & Install APK
```powershell
cd "D:\Project\Malva\2026-07-09\say\outputs\malva"
flutter build apk --release --dart-define=MALVA_GOOGLE_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com --dart-define=MALVA_API_BASE_URL=http://192.168.1.2:8080
```

### 6.2 Install di Phone
```powershell
adb install build\app\outputs\flutter-apk\app-release.apk
```

### 6.3 Test Login
1. Buka app Malva
2. Pilih **Pasien**
3. Klik button **Continue with Google**
4. Pilih akun Google (`lxsdora@gmail.com`)
5. Allow permissions
6. ✅ Seharusnya langsung masuk & account tersimpan di database

---

## 🐛 **Troubleshooting**

### **Error: "Login Google belum dikonfigurasi"**
- Pastikan `MALVA_GOOGLE_CLIENT_ID` sudah diisi saat build
- Atau hardcode `serverClientId` di `google_config.dart`

### **Error: "DEVELOPER_ERROR" / "API_NOT_AVAILABLE"**
- SHA-1 fingerprint salah atau belum didaftarkan
- Package name tidak match (`id.malva.app`)
- Tunggu 5-10 menit setelah add SHA-1 (propagation delay)

### **Error: "Tidak bisa menampilkan layar login Google"**
- Google Play Services belum terinstall di device
- Atau device tidak support (emulator butuh Google APIs)

### **Error: Backend JWT verification gagal**
- Web Client ID salah
- Pastikan backend terima ID token dari client dengan benar

---

## 📊 **Verify Setup**

### Check di Google Cloud Console:
1. **APIs & Services** → **Credentials**
2. Lihat 2 OAuth clients:
   - ✅ Web client (untuk backend)
   - ✅ Android client (dengan SHA-1)

### Check di Database:
```sql
-- Setelah login Google berhasil, cek:
SELECT email, display_name, role, created_at 
FROM users 
WHERE email = 'lxsdora@gmail.com';
```

---

## 🎯 **Summary Checklist**

- [ ] Google Cloud Project created
- [ ] OAuth Consent Screen configured
- [ ] Web Client ID created & copied
- [ ] Android Client ID created with SHA-1
- [ ] `MALVA_GOOGLE_CLIENT_ID` set saat build APK
- [ ] APK installed & tested di real device
- [ ] Login Google berhasil & user masuk database

**Selesai! Google Sign-In sekarang aktif. 🎉**
