# Deployment Oracle Cloud Always Free untuk Malva

Dokumen ini menyiapkan jalur production Malva di Oracle Cloud Always Free:

```text
Flutter app
  -> HTTPS + WebSocket
  -> Caddy
  -> Go backend Malva
  -> PostgreSQL lokal/private
  -> FCM untuk push notification
```

FCM hanya dipakai sebagai gateway push notification Android. Data pasien, auth,
screening, realtime WebSocket, dan audit tetap berada di Go backend +
PostgreSQL yang kita kontrol sendiri.

## Kenapa Oracle Always Free

Oracle Cloud Always Free masih menjadi opsi paling cocok untuk target Malva:

- ada VM Always Free jangka panjang;
- bisa menjalankan proses Go yang hidup terus;
- bisa memasang PostgreSQL sendiri;
- WebSocket lebih stabil dibanding serverless function;
- bisa pakai Caddy untuk HTTPS otomatis;
- tidak memaksa backend pindah ke layanan database berlangganan.

Catatan penting dari dokumentasi Oracle:

- Ampere A1 Always Free setara total 2 OCPU dan 12 GB RAM untuk tenancy Free.
- Block Volume Always Free total 200 GB.
- VM Always Free yang idle dapat direklaim Oracle.
- Kapasitas Always Free bisa habis di region tertentu.

Sumber resmi:

- <https://www.oracle.com/cloud/free/>
- <https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm>

## Resource Oracle yang disarankan

Pilih resource sederhana dulu, jangan dibuat rumit:

| Komponen | Rekomendasi |
|---|---|
| OS image | Ubuntu 24.04 LTS atau Ubuntu 22.04 LTS |
| Shape | VM.Standard.A1.Flex |
| CPU | 1 OCPU cukup untuk awal, 2 OCPU jika tersedia |
| RAM | 6 GB cukup untuk awal, 12 GB jika memakai semua kuota A1 |
| Boot volume | 50-100 GB |
| Region | Singapore jika tersedia; jika penuh, pilih region terdekat yang bisa dibuat |
| Public IP | Ya |

Jangan buka PostgreSQL ke publik.

## Port yang perlu dibuka

Di Oracle Security List / Network Security Group:

| Port | Fungsi |
|---:|---|
| 22 | SSH |
| 80 | HTTP, validasi Let's Encrypt |
| 443 | HTTPS API + WebSocket |

Jangan buka port `5432` ke internet. PostgreSQL harus tetap lokal/private.

## Domain

Ideal:

```text
api.malva.id
```

Sementara sebelum domain siap, backend masih bisa dites lewat:

```text
http://PUBLIC_IP:8080
```

Namun untuk aplikasi pasien production, gunakan domain + HTTPS.

## Persiapan Firebase FCM

Sebelum push notification sungguhan aktif, siapkan:

- Firebase project;
- Android app Firebase dengan package name production;
- `android/app/google-services.json`;
- service account JSON untuk backend;
- file service account disimpan di server:

```text
/etc/malva/firebase-service-account.json
```

Referensi internal:

- `docs/FCM_SETUP.md`

Referensi resmi:

- <https://firebase.google.com/docs/cloud-messaging/flutter/get-started>
- <https://firebase.google.com/docs/admin/setup>

## Alur deployment setelah VM siap

SSH ke VM:

```bash
ssh ubuntu@PUBLIC_IP_ORACLE
```

Upload atau clone repo Malva ke VM. Jika repo sudah ada di GitHub:

```bash
git clone REPO_URL /opt/malva/app
cd /opt/malva/app
```

Jika belum ada repo remote, upload folder project ke VM lalu masuk ke folder
project tersebut.

Jalankan setup:

```bash
sudo MALVA_DOMAIN=api.malva.id bash ./backend/scripts/oracle_ubuntu_setup.sh
```

Jika domain belum siap:

```bash
sudo bash ./backend/scripts/oracle_ubuntu_setup.sh
```

Script akan:

- install dependency OS;
- install Go jika belum ada atau terlalu lama;
- membuat user Linux `malva`;
- membuat database PostgreSQL `malva`;
- membuat password DB dan JWT secret kuat;
- menjalankan migration pertama jika schema belum ada;
- build binary Go production;
- memasang systemd service;
- memasang Caddy jika domain disediakan;
- membuka firewall OS untuk SSH/HTTP/HTTPS;
- menjalankan health check lokal.

## File environment production

Script membuat:

```text
/etc/malva/malva-api.env
```

Contoh isi:

```env
MALVA_HTTP_ADDR=127.0.0.1:8080
MALVA_DATABASE_URL=postgres://malva:password-kuat@127.0.0.1:5432/malva?sslmode=disable
MALVA_JWT_SECRET=secret-minimal-32-karakter
MALVA_ALLOWED_ORIGINS=https://api.malva.id
MALVA_FCM_CREDENTIALS_FILE=/etc/malva/firebase-service-account.json
MALVA_FCM_CREDENTIALS_JSON=
```

Jangan commit file `.env`, service account, atau secret ke repository.

## Command operasional

Cek status backend:

```bash
sudo systemctl status malva-api --no-pager
```

Cek log backend:

```bash
sudo journalctl -u malva-api -f
```

Restart backend:

```bash
sudo systemctl restart malva-api
```

Cek Caddy:

```bash
sudo systemctl status caddy --no-pager
```

Cek health:

```bash
curl -fsS http://127.0.0.1:8080/healthz
curl -fsS https://api.malva.id/healthz
```

## Validasi production

Setelah deployment:

```bash
MALVA_BASE_URL=https://api.malva.id bash ./backend/scripts/validate_production.sh
```

Untuk smoke test mutating yang membuat user test sementara:

```bash
MALVA_BASE_URL=https://api.malva.id MALVA_VALIDATE_MUTATING=1 bash ./backend/scripts/validate_production.sh
```

Gunakan mutating test hanya saat deployment awal atau maintenance window.

## Backup database

Backup manual:

```bash
sudo bash /opt/malva/app/backend/scripts/backup_postgres.sh
```

Lokasi backup default:

```text
/var/backups/malva
```

Minimal backup harian perlu aktif sebelum pasien sungguhan masuk.

## Checklist go-live

- [ ] VM Oracle Always Free dibuat.
- [ ] Port 22, 80, 443 dibuka di Oracle.
- [ ] PostgreSQL tidak terbuka ke publik.
- [ ] Domain `api...` mengarah ke IP publik VM.
- [ ] `/healthz` sukses lewat HTTPS.
- [ ] `MALVA_JWT_SECRET` bukan placeholder.
- [ ] Password PostgreSQL bukan placeholder.
- [ ] Firebase `google-services.json` sudah masuk Android app.
- [ ] Firebase service account sudah ada di `/etc/malva`.
- [ ] Backend log tidak menunjukkan provider FCM no-op di production.
- [ ] Flutter production build memakai `MALVA_API_BASE_URL=https://api...`.
- [ ] Backup database diuji minimal satu kali.
- [ ] Security headers tervalidasi.
