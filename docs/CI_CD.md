# CI/CD — Malva (GitHub Actions)

Dokumen ini menjelaskan cara kerja deployment otomatis Malva dan **sekali-setup**
yang perlu dilakukan agar `push` ke `main` langsung men-deploy tanpa SSH manual.

## 1. Workflow yang tersedia

| File | Trigger | Fungsi |
|---|---|---|
| `.github/workflows/deploy-backend.yml` | push `backend/**` (kecuali `backend/deploy/landing/**`) | Build binary Go linux/amd64 → upload ke VM → `systemctl restart malva-api` → health check `/healthz` |
| `.github/workflows/deploy-web.yml` | push `backend/deploy/landing/**` | `rsync` landing site ke `/var/www/malva` → health check website |
| `.github/workflows/build-apk.yml` | push `lib/**`, `android/**`, `assets/**`, `pubspec.*` | Build APK release + `--dart-define` wajib → verifikasi define tertanam → upload artifact → (opsional) upload ke `/downloads/malva-latest.apk` |
| `.github/workflows/deploy.yml` | manual (`workflow_dispatch`) | Orkestrator: deploy `all` / `backend` / `web` / `apk` |
| `.github/workflows/backend-ci.yml` | push/PR `backend/**` | Lint, unit test (Postgres service), build, docker, security scan |
| `.github/workflows/flutter-ci.yml` | push/PR Flutter paths | Analyze, test, build Android/Web/Windows |

> Deploy otomatis **tidak** menunggu CI hijau. Pastikan `backend-ci.yml` dan
> `flutter-ci.yml` sudah lolos sebelum push ke `main`, atau jalankan lewat
> tombol manual setelah CI selesai.

## 2. Halaman GitHub yang perlu dibuka

Ganti `<owner>/<repo>` bila perlu. Untuk repo ini:

- **Variables** → https://github.com/Chokobunni/malva-mental-health/settings/variables/actions
- **Secrets** → https://github.com/Chokobunni/malva-mental-health/settings/secrets/actions
- **Daftar workflow & run** → https://github.com/Chokobunni/malva-mental-health/actions

Di halaman **Variables**, klik **New repository variable** untuk setiap baris
tabel di bawah. Di halaman **Secrets**, klik **New repository secret**.

## 3. Variables (bukan rahasia)

| Nama | Contoh | Wajib | Dipakai oleh |
|---|---|---|---|
| `DEPLOY_HOST` | `20.10.10.10` atau `vm.malva.web.id` | ✅ | backend, web, apk |
| `DEPLOY_USER` | `azureuser` | ✅ | backend, web, apk |
| `DEPLOY_PORT` | `22` | opsional (default 22) | backend, web, apk |
| `MALVA_API_BASE_URL` | `https://api.malva.web.id` | opsional (default) | apk |
| `MALVA_GOOGLE_CLIENT_ID` | `910496426601-....apps.googleusercontent.com` | ✅ untuk APK | apk |
| `WEB_ROOT` | `/var/www/malva` | opsional (default) | web |
| `SITE_URL` | `https://malva.web.id` | opsional (default) | web, apk |

`MALVA_GOOGLE_CLIENT_ID` adalah **Web Client ID** (bukan rahasia) — nilai yang
sama dengan `--dart-define` di `scripts/build_release_apk.ps1`.

## 4. Secrets (rahasia)

| Nama | Wajib | Isi |
|---|---|---|
| `DEPLOY_SSH_KEY` | ✅ | Isi lengkap private key SSH (termasuk baris `BEGIN`/`END`) |
| `ANDROID_KEYSTORE_BASE64` | ⚠️ wajib untuk distribusi | Base64 dari `android/malva-release-key.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | ⚠️ | `storePassword` |
| `ANDROID_KEY_ALIAS` | ⚠️ | `keyAlias` (contoh `malva`) |
| `ANDROID_KEY_PASSWORD` | ⚠️ | `keyPassword` |
| `GOOGLE_SERVICES_JSON_BASE64` | opsional | Base64 dari `android/app/google-services.json` (FCM) |

Jika `ANDROID_KEYSTORE_BASE64` kosong, APK tetap dibuild sebagai artifact CI
(tanda tangan debug) tetapi **job deploy dilewati** — tidak ada APK yang
diunggah ke `/downloads`. Ini mencegah APK debug-signed terpublikasi; debug key
runner berbeda tiap build sehingga Google Sign-In bisa gagal dan update antar
APK tidak bisa (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`).

## 5. Setup sekali jalan di VM

### 5.1 Buat SSH key untuk deploy (di laptop)

```bash
ssh-keygen -t ed25519 -C "github-actions@malva" -f ~/.ssh/malva_deploy -N ""
```

Tempel isi **public key** ke VM:

```bash
ssh-copy-id -i ~/.ssh/malva_deploy.pub <DEPLOY_USER>@<DEPLOY_HOST>
```

Lalu salin isi **private key** ke secret `DEPLOY_SSH_KEY`:

```bash
cat ~/.ssh/malva_deploy
```

> Jangan commit private key. Simpan salinan aman di password manager.

### 5.2 Pastikan `rsync` terpasang di VM

```bash
sudo apt-get update && sudo apt-get install -y rsync
```

### 5.3 Beri sudo terbatas untuk deploy user

Workflow memakai `sudo` hanya untuk 3 hal: `install`, `rsync`, dan
`systemctl restart malva-api`. Buat file sudoers:

```bash
sudo visudo -f /etc/sudoers.d/malva-deploy
```

Isi (ganti `<DEPLOY_USER>`):

```sudoers
<DEPLOY_USER> ALL=(root) NOPASSWD: /usr/bin/install, /usr/bin/rsync, /usr/bin/systemctl restart malva-api
```

Cek path asli dengan `command -v install rsync systemctl` — sesuaikan bila
berbeda. Validasi:

```bash
sudo visudo -c
```

### 5.4 Pastikan folder & permission benar

```bash
sudo mkdir -p /var/www/malva/downloads
sudo chown -R caddy:caddy /var/www/malva
```

Service `malva-api` sudah ada di `/etc/systemd/system/malva-api.service` dan
binary-nya di `/usr/local/bin/malva-api` (lihat
`backend/deploy/systemd/malva-api.service`).

## 6. Setup Android signing

### 6.1 Buat keystore release (sekali saja, jika belum ada)

```bash
keytool -genkeypair -v \
  -keystore android/malva-release-key.jks \
  -alias malva \
  -keyalg RSA -keysize 2048 -validity 10000
```

Simpan file `.jks` dan password-nya di tempat aman (password manager + backup
offline). Lalu daftarkan SHA-1-nya ke Google Cloud Console:

```bash
keytool -list -v -keystore android/malva-release-key.jks -alias malva | grep SHA1
```

Tambahkan SHA-1 tersebut sebagai **Android OAuth Client** untuk package
`id.malva.app` (satu package boleh punya beberapa SHA-1). Tanpa langkah ini,
Google Sign-In di APK release akan gagal dengan `ApiException: 10`.

### 6.2 Dapatkan base64 untuk GitHub Secrets

Di mesin yang punya keystore release:

**Windows (PowerShell):**
```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android\malva-release-key.jks")) | Set-Clipboard
```

**Linux/macOS/Git Bash:**
```bash
base64 -w0 android/malva-release-key.jks | clip   # Windows
base64 -w0 android/malva-release-key.jks | pbcopy # macOS
```

Tempel hasilnya ke secret `ANDROID_KEYSTORE_BASE64`. Isi juga
`ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`
sesuai `android/key.properties` lokal.

Workflow akan membuat `android/key.properties` otomatis dengan:

```properties
storePassword=<secret>
keyPassword=<secret>
keyAlias=<secret>
storeFile=../malva-release-key.jks
```

## 7. Setup FCM (opsional)

Jika ingin notifikasi push aktif di APK hasil CI:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android\app\google-services.json")) | Set-Clipboard
```

Tempel ke secret `GOOGLE_SERVICES_JSON_BASE64`. Tanpa ini, build tetap jalan
tetapi Firebase/FCM tidak terkonfigurasi.

## 8. Cara menjalankan

### Otomatis
Cukup `git push` ke `main`:

| Perubahan | Workflow yang jalan |
|---|---|
| `backend/**` | Deploy Backend |
| `backend/deploy/landing/**` | Deploy Website |
| `lib/**`, `android/**`, `assets/**`, `pubspec.*` | Build & Deploy APK |

### Manual
Buka **Actions → Deploy All (manual) → Run workflow**, pilih `target`:
`all`, `backend`, `web`, atau `apk`.

Untuk APK, buka **Actions → Build & Deploy APK → Run workflow** bila ingin
mengatur `target_platform` dan apakah APK diunggah ke server.

## 9. Migrasi database (tetap manual)

Backend **tidak** menjalankan migrasi otomatis saat start, dan workflow
deploy backend **hanya mengirim binary** (`scp backend/malva-api`) — folder
`migrations/` **tidak** ikut tersalin. Jadi setiap ada migrasi baru, dua hal
harus dilakukan: salin berkasnya, lalu terapkan.

### 9.1 Menyalin berkas migrasi ke VM

```bash
# dari root repo, di laptop
scp -i ~/.ssh/malva_azure backend/migrations/*.sql \
  malva@api.malva.web.id:/tmp/malva-migrations/

ssh -i ~/.ssh/malva_azure malva@api.malva.web.id '
  sudo mkdir -p /opt/malva/app/backend/migrations
  sudo cp /tmp/malva-migrations/*.sql /opt/malva/app/backend/migrations/
  ls -1 /opt/malva/app/backend/migrations/
'
```

### 9.2 Menerapkan migrasi

Gunakan skrip di `backend/deploy/scripts/apply_migrations.sh` (idempoten,
menghentikan diri pada error SQL pertama, dan langsung memverifikasi hasilnya).

```bash
# lihat migrasi yang tersedia
sudo /opt/malva/app/backend/deploy/scripts/apply_migrations.sh --list

# periksa kesehatan skema tanpa mengubah apa pun
sudo /opt/malva/app/backend/deploy/scripts/apply_migrations.sh --check

# terapkan satu migrasi tertentu (disarankan: eksplisit per nomor)
sudo /opt/malva/app/backend/deploy/scripts/apply_migrations.sh 015
sudo /opt/malva/app/backend/deploy/scripts/apply_migrations.sh 016

# terapkan semua migrasi berurutan (perilaku lama)
sudo /opt/malva/app/backend/deploy/scripts/apply_migrations.sh --all
```

Migrasi terbaru yang harus jalan sebelum binary versi ini dipakai:

| Migrasi | Isi | Bila terlewat |
|---|---|---|
| `015` | `medication_logs.status` menerima `partial` | Log obat "Partial" ditolak database |
| `016` | `earnings.session_id` + unique parsial | Menandai sesi selesai **gagal** (kolom tidak ada) → pendapatan tidak tercatat |

Skrip membaca `MALVA_DATABASE_URL` dari `/etc/malva/malva-api.env`; bila berkas
itu tidak terbaca, berikan URL lewat lingkungan:

```bash
sudo MALVA_DATABASE_URL='postgres://...' \
  /opt/malva/app/backend/deploy/scripts/apply_migrations.sh 015
```

Tanpa skrip, setara dengan:

```bash
for f in /opt/malva/app/backend/migrations/*.sql; do
  sudo -u malva psql "$MALVA_DATABASE_URL" -f "$f"
done
```

### 9.3 Verifikasi setelah migrasi

Migrasi `015` mengubah CHECK constraint `medication_logs`. Bila constraint
lama masih aktif, log "Partial" akan **ditolak database** walau handler sudah
menerimanya — jadi jangan berhenti di "tidak ada error". Pastikan definisinya
sudah memuat `partial`:

```bash
sudo -u malva psql "$MALVA_DATABASE_URL" -c "
  SELECT pg_get_constraintdef(oid) AS definisi
  FROM pg_constraint
  WHERE conrelid = 'medication_logs'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%status%';"
```

Hasil yang benar memuat `status IN ('taken','missed','skipped','partial')`.
Cara cepat: `apply_migrations.sh --check` mencetak
`medication_logs.status : OK — 'partial' diterima`.

Migrasi `016` menambah `earnings.session_id`. Bila kolomnya belum ada,
**menandai sesi sebagai selesai akan gagal** (INSERT earnings error) sehingga
pendapatan profesional tidak tercatat. Periksa:

```bash
sudo -u malva psql "$MALVA_DATABASE_URL" -c "
  SELECT column_name FROM information_schema.columns
  WHERE table_name = 'earnings' AND column_name = 'session_id';"
sudo -u malva psql "$MALVA_DATABASE_URL" -c "
  SELECT indexname FROM pg_indexes
  WHERE tablename = 'earnings' AND indexname = 'earnings_session_unique';"
```

Dua-duanya harus mengembalikan satu baris. Cara cepat: `apply_migrations.sh
--check` mencetak `earnings.session_id : OK` dan
`earnings.session_unique: OK — pendapatan per sesi tidak bisa ganda`.

### 9.4 Mengubah variabel lingkungan service

Perubahan env **tidak** ikut ter-deploy otomatis. Setelah mengedit
`/etc/malva/malva-api.env`, service wajib di-restart karena `EnvironmentFile`
hanya dibaca saat start:

```bash
sudo systemctl restart malva-api
systemctl is-active malva-api
sudo journalctl -u malva-api -n 30 --no-pager
```

Contoh nyata: `MALVA_FONNTE_TOKEN` untuk blast SOS WhatsApp. Bila variabel ini
kosong, backend memakai mode stub dan melaporkan status apa adanya (tidak
mengklaim terkirim), tetapi pesan SOS **tidak** benar-benar dikirim.

## 10. Troubleshooting

| Gejala | Penyebab & solusi |
|---|---|
| `sudo: a password is required` | Sudoers belum dibuat / path beda. Cek `command -v install rsync systemctl`, sesuaikan `/etc/sudoers.d/malva-deploy`, lalu `sudo visudo -c`. |
| `Permission denied (publickey)` | Public key belum masuk `~/.ssh/authorized_keys` user deploy, atau `DEPLOY_USER` salah. |
| `Host key verification failed` | `ssh-keyscan` gagal. Pastikan `DEPLOY_HOST`/`DEPLOY_PORT` benar dan VM bisa dijangkau dari internet. |
| `rsync: command not found` | `sudo apt-get install -y rsync` di VM. |
| `MALVA_GOOGLE_CLIENT_ID kosong` | Isi repo variable `MALVA_GOOGLE_CLIENT_ID` (Settings → Variables). |
| APK Google login gagal | Cek step **Verify dart-define embedded** di log. Pastikan variable terisi dan APK di-build ulang. |
| APK tidak bisa di-update di HP | Signature beda. Isi secret keystore release (bagian 6), lalu uninstall APK lama sekali. Debug key runner berubah tiap build, jadi APK debug tidak bisa dijadikan distribusi. |
| APK tidak terunggah ke server | Normal bila `ANDROID_KEYSTORE_BASE64` kosong — job deploy sengaja dilewati. Isi secret keystore lalu jalankan ulang. |
| Health check API gagal | `sudo systemctl status malva-api` dan `journalctl -u malva-api -n 100 --no-pager`. Cek juga CORS/env di `/etc/malva/malva-api.env`. |
| Website 404 setelah deploy | Pastikan `WEB_ROOT` benar dan Caddy `root * /var/www/malva`. Cek `sudo caddy validate --config /etc/caddy/Caddyfile`. |

## 11. Keamanan

- Private key & keystore **hanya** di GitHub Secrets; jangan pernah commit.
- Gunakan user deploy khusus (bukan `root`) dan sudoers terbatas.
- Rotasi `DEPLOY_SSH_KEY` bila ada indikasi bocor.
- `--rsync-path="sudo rsync"` memberi akses tulis root ke `/var/www/malva`;
  batasi user deploy hanya untuk mesin ini.
- Aktifkan **branch protection** di `main` agar perubahan workflow di-review.
