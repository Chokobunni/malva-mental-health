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

Jika `ANDROID_KEYSTORE_BASE64` kosong, APK tetap dibuild tetapi memakai
**debug signing** — jangan dibagikan ke pengguna karena update berikutnya akan
gagal dengan `INSTALL_FAILED_UPDATE_INCOMPATIBLE`.

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
sudo chown -R www-data:www-data /var/www/malva
```

Service `malva-api` sudah ada di `/etc/systemd/system/malva-api.service` dan
binary-nya di `/usr/local/bin/malva-api` (lihat
`backend/deploy/systemd/malva-api.service`).

## 6. Setup Android signing

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

Backend **tidak** menjalankan migrasi otomatis saat start. Setelah deploy yang
mengubah skema, jalankan di VM:

```bash
# dari folder migrasi yang sudah ada di VM
for f in /opt/malva/app/backend/migrations/*.sql; do
  sudo -u malva psql "$MALVA_DATABASE_URL" -f "$f"
done
```

Migrasi di repo bersifat idempoten (`CREATE TABLE IF NOT EXISTS`), jadi aman
dijalankan berulang. Jika folder migrasi belum ada di VM, salin dulu:

```bash
scp -r backend/migrations <DEPLOY_USER>@<DEPLOY_HOST>:/tmp/malva-migrations
ssh <DEPLOY_USER>@<DEPLOY_HOST> 'sudo mkdir -p /opt/malva/app/backend/migrations && sudo cp -r /tmp/malva-migrations/* /opt/malva/app/backend/migrations/'
```

## 10. Troubleshooting

| Gejala | Penyebab & solusi |
|---|---|
| `sudo: a password is required` | Sudoers belum dibuat / path beda. Cek `command -v install rsync systemctl`, sesuaikan `/etc/sudoers.d/malva-deploy`, lalu `sudo visudo -c`. |
| `Permission denied (publickey)` | Public key belum masuk `~/.ssh/authorized_keys` user deploy, atau `DEPLOY_USER` salah. |
| `Host key verification failed` | `ssh-keyscan` gagal. Pastikan `DEPLOY_HOST`/`DEPLOY_PORT` benar dan VM bisa dijangkau dari internet. |
| `rsync: command not found` | `sudo apt-get install -y rsync` di VM. |
| `MALVA_GOOGLE_CLIENT_ID kosong` | Isi repo variable `MALVA_GOOGLE_CLIENT_ID` (Settings → Variables). |
| APK Google login gagal | Cek step **Verify dart-define embedded** di log. Pastikan variable terisi dan APK di-build ulang. |
| APK tidak bisa di-update di HP | Signature beda (debug vs release). Isi secret keystore, lalu uninstall APK lama sekali. |
| Health check API gagal | `sudo systemctl status malva-api` dan `journalctl -u malva-api -n 100 --no-pager`. Cek juga CORS/env di `/etc/malva/malva-api.env`. |
| Website 404 setelah deploy | Pastikan `WEB_ROOT` benar dan Caddy `root * /var/www/malva`. Cek `sudo caddy validate --config /etc/caddy/Caddyfile`. |

## 11. Keamanan

- Private key & keystore **hanya** di GitHub Secrets; jangan pernah commit.
- Gunakan user deploy khusus (bukan `root`) dan sudoers terbatas.
- Rotasi `DEPLOY_SSH_KEY` bila ada indikasi bocor.
- `--rsync-path="sudo rsync"` memberi akses tulis root ke `/var/www/malva`;
  batasi user deploy hanya untuk mesin ini.
- Aktifkan **branch protection** di `main` agar perubahan workflow di-review.
