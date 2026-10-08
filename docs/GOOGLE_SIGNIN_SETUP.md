# Google Sign-In Setup — Malva (Azure edition)

Panduan mengaktifkan **Login dengan Google** di aplikasi Malva.
Server produksi: `https://api.malva.web.id` (Azure VM).

> **PENTING — TIDAK PERLU PREPAYMENT / BILLING.**
> OAuth Client ID dan Firebase Authentication (Google provider) berjalan di
> Firebase **Spark plan** (gratis, tanpa kartu kredit). Abaikan semua tawaran
> "activate billing" / "start free trial" / prepayment Google Cloud.
> Malva di-host di Azure, bukan di Google Cloud — Google hanya dipakai untuk
> memverifikasi identitas Google saat login.

---

## Apa yang dibutuhkan

| Item | Keterangan |
|---|---|
| Akun Google | `amiradiandra73@gmail.com` (pemilik project Firebase) |
| Project Firebase | `malva-7084e` (sama dengan `android/app/google-services.json`) |
| Web Client ID | Dari Google Cloud → Credentials → OAuth client (Web) |
| Android Client ID | Package `id.malva.app` + SHA-1 (lihat `docs/ANDROID_SHA_FINGERPRINTS.md`) |

SHA-1 debug APK saat ini:

```
C3:09:B8:22:F4:D0:2F:B3:D5:4A:88:B0:9C:ED:08:E9:0E:20:AA:01
```

## Client ID terpasang (produksi, Oktober 2026)

| Jenis | Client ID | Dipasang di |
|---|---|---|
| **Web** (server client ID) | `910496426601-thlkor62046ftqplmon364p3qhobkntv.apps.googleusercontent.com` | ✅ Server Azure (`/etc/malva/malva-api.env` → `MALVA_GOOGLE_CLIENT_ID`) + dart-define APK |
| **Android** (fingerprint) | `910496426601-p7o8i299fjpi2k4eae1innvv0sah3m6v.apps.googleusercontent.com` | Tidak perlu dipasang — Google mengenalinya otomatis dari package `id.malva.app` + SHA-1 |

Catatan: client ID bukan rahasia (bukan kredensial); aman didokumentasikan.

---

## STEP 1 — Buka project yang benar

1. Login https://console.firebase.google.com dengan `amiradiandra73@gmail.com`.
2. Pilih project **malva-7084e** (project yang sama dipakai FCM).
   - Bila akun ini belum memiliki akses: minta pemilik project menambahkan
     sebagai **Owner/Editor** di Firebase Console → ⚙️ Project settings →
     Users and permissions. Tanpa akses, Google login dan FCM tidak sinkron.

## STEP 2 — Aktifkan provider Google (Firebase, gratis)

1. Firebase Console → **Authentication** → **Get started** (sekali saja).
2. Tab **Sign-in method** → **Add new provider** → **Google** → **Enable**.
3. Isi **Public-facing name**: `Malva`.
4. **Project support email**: pilih email kamu. → **Save**.
5. Buka tab **Users** → pastikan **Authorized domains** berisi
   `api.malva.web.id` (tambahkan bila belum ada; `localhost` sudah default).

## STEP 3 — Buat OAuth client (Google Cloud, tanpa billing)

1. Di Firebase Console → ⚙️ **Project settings** → tab **General** →
   scroll ke **Your apps** → pastikan ada app Android `id.malva.app`.
2. Klik link **Google Cloud Console** di banner atas Firebase
   (atau buka https://console.cloud.google.com/apis/credentials?project=malva-7084e).
   - **Jangan** klik "Start free trial" / "Activate" bila muncul — langsung
     ke APIs & Services saja.
3. **Create Credentials → OAuth client ID**:
   - **Application type: Web application**
   - Name: `Malva Backend Web`
   - Authorized redirect URIs: **kosongkan**
   - **Create** → **COPY Client ID** (`xxxx.apps.googleusercontent.com`) →
     ini yang dipakai server.
4. **Create Credentials → OAuth client ID** lagi:
   - **Application type: Android**
   - Name: `Malva Android`
   - **Package name**: `id.malva.app`
   - **SHA-1**: `C3:09:B8:22:F4:D0:2F:B3:D5:4A:88:B0:9C:ED:08:E9:0E:20:AA:01`
   - **Create**.

> Bila OAuth consent screen diminta: pilih **External**, isi App name `Malva`,
> support email kamu, Save. Di **Audience**, tambahkan
> `amiradiandra73@gmail.com` sebagai **Test user** selama status masih
> "Testing" — tanpa ini login akan diblokir.

## STEP 4 — Pasang Web Client ID

Ada 2 tempat (nilai **sama persis**):

**A. Server (Azure VM)** — edit `/etc/malva/malva-api.env`:

```
MALVA_GOOGLE_CLIENT_ID=xxxx.apps.googleusercontent.com
```

lalu:

```bash
sudo systemctl restart malva-api
```

**B. Build APK** — sertakan saat build:

```powershell
flutter build apk --release --target-platform android-arm64 `
  --dart-define=MALVA_API_BASE_URL=https://api.malva.web.id `
  --dart-define=MALVA_GOOGLE_CLIENT_ID=xxxx.apps.googleusercontent.com
```

## STEP 5 — Uji

1. Install APK, pilih **Pasien** → **Continue with Google** → pilih akun.
2. Backend membuat/menautkan akun otomatis (kolom `sso_provider=google`).
3. Cek di database: `SELECT email, sso_provider FROM users WHERE sso_provider='google';`

## Troubleshooting

| Gejala | Penyebab | Solusi |
|---|---|---|
| "Login Google belum dikonfigurasi" | `MALVA_GOOGLE_CLIENT_ID` belum diisi di VM | Isi env + restart `malva-api` |
| Tombol Google tidak muncul / error konfigurasi | APK di-build tanpa `--dart-define` | Build ulang APK |
| `DEVELOPER_ERROR` di HP | SHA-1 salah / belum didaftarkan | Daftarkan SHA-1 di OAuth client Android; tunggu 5–10 menit |
| "Email Google belum terverifikasi" | Akun Google belum verifikasi email | Gunakan akun Google terverifikasi |
| Akses ditolak "has not completed the Google verification" | Status OAuth masih Testing | Tambahkan akun sebagai **Test user** di OAuth consent screen |
| Backend 501 | Client ID kosong di server | Step 4A |

## Catatan

- Web Client ID **bukan rahasia** (aman dibagikan); Client Secret **tidak dipakai**
  untuk alur Android ID-token (validasi memakai public key Google).
- Login Google untuk pasien. Profesional login memakai nomor STR/SIP.
- FCM push (project `malva-7084e`) tetap berjalan tanpa billing.
