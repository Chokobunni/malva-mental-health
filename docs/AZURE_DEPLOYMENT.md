# Deployment Azure — Malva (Student Credit)

Arsitektur produksi aktif (Oktober 2026):

```text
APK Malva (Android)
   │ HTTPS / WSS  →  https://api.malva.web.id
   ▼
Azure VM malva-vm (Ubuntu 24.04, Standard_B2ats_v2, Indonesia Central)
   ├── Caddy  : TLS otomatis Let's Encrypt + reverse proxy + WebSocket
   └── malva-api (Go, systemd) : 127.0.0.1:8080
          │ postgres://...?sslmode=require
          ▼
Azure Database for PostgreSQL Flexible Server (B1ms, PG 17, 32 GiB)
```

Region: **Indonesia Central** (catatan: Azure tidak punya region "Batam";
Indonesia Central = Jakarta).

## Ringkasan resource

| Resource | Nilai |
|---|---|
| Resource group | `malva-rg` |
| VM | `malva-vm` — Standard_B2ats_v2 (2 vCPU/1 GiB), disk Premium_LRS 64 GiB (P6) |
| Public IP | Static — lihat portal (di DNS: `api.malva.web.id`) |
| PostgreSQL | `malva-pg.postgres.database.azure.com` (PG 17.11, Burstable B1ms) |
| Domain | `malva.web.id` (idwebhost), record: `api` → A → IP VM |
| TLS | Caddy + Let's Encrypt (auto-renew) |

## Kuota gratis yang dipakai (Azure for Students)

- VM BS/Basv2: **750 jam/bulan** (cukup untuk 1 VM 24/7).
- PostgreSQL Flexible Server B1ms: **750 jam/bulan** + storage 32 GiB + backup 32 GiB.
- Public IP: 1.500 jam/bulan; egress 15 GiB/bulan.
- Kredit **US$100** sebagai cadangan; pasang budget alert di Cost Management.

## Database

- Migrasi dijalankan dari `backend/migrations/001–011` (idempoten).
  - **Catatan Azure**: ekstensi `pgcrypto` **tidak di-allowlist** Azure
    Flexible Server. Tidak diperlukan: `gen_random_uuid()` sudah bawaan
    PG 13+, dan tidak ada kolom yang memakai `crypt()`/`digest()`.
    Saat menjalankan migrasi di Azure, baris `CREATE EXTENSION pgcrypto`
    boleh dilewati/di-comment.
- User aplikasi: `malva_app` (bukan admin `malva`). Grant: CONNECT,
  USAGE+CREATE schema, CRUD semua tabel, sequences, default privileges.
- Kredensial runtime di VM: `/etc/malva/malva-api.env` (chmod 600).
- Backup harian: cron 02:00 → `/var/backups/malva` (retensi 14 hari),
  memakai `pg_dump` 17 (repo PGDG, karena server PG 17 > client bawaan 16).

### Migrasi data dari DB lokal (pola yang dipakai)

1. `pg_dump --data-only --column-inserts --on-conflict-do-nothing` dari lokal.
2. **Petakan ID**: user yang sama (berdasarkan email) punya ID berbeda antara
   seed lokal dan seed Azure. Ganti ID lokal → ID Azure di file dump sebelum
   import (contoh pemetaan: `preview_pasien@malva.app`, 2 akun profesional seed).
3. Import users dulu, lalu tabel lain (agar FK terpenuhi).
4. Selalu pakai `--column-inserts` bila urutan kolom kedua DB berbeda.

## Deploy backend (ulang/rutin)

```powershell
# 1. Build binary Linux dari Windows
$env:GOOS="linux"; $env:GOARCH="amd64"; $env:CGO_ENABLED="0"
cd backend; go build -ldflags="-s -w" -o malva-api ./cmd/api

# 2. Upload
scp -i "$env:USERPROFILE\.ssh\malva_azure" malva-api malva@<IP>:/home/malva/malva-api-new

# 3. Pasang & restart
ssh -i "$env:USERPROFILE\.ssh\malva_azure" malva@<IP> `
  "sudo mv /home/malva/malva-api-new /usr/local/bin/malva-api && " +
  "sudo chmod 755 /usr/local/bin/malva-api && sudo systemctl restart malva-api"
```

Service: `/etc/systemd/system/malva-api.service` (template di
`backend/deploy/systemd/malva-api.service`), env dari `/etc/malva/malva-api.env`.

Caddy: `/etc/caddy/Caddyfile` (template `backend/deploy/Caddyfile`):

```text
api.malva.web.id {
	encode zstd gzip
	reverse_proxy 127.0.0.1:8080
}
```

## Build APK produksi

```powershell
flutter build apk --release --target-platform android-arm64 `
  --dart-define=MALVA_API_BASE_URL=https://api.malva.web.id
```

## Operasi harian

```bash
sudo systemctl status malva-api caddy     # status layanan
sudo journalctl -u malva-api -f           # log backend
sudo journalctl -u caddy | grep -i tls    # log sertifikat
ls -lh /var/backups/malva                 # backup terbaru
curl https://api.malva.web.id/healthz     # smoke test
```

## DNS (idwebhost)

- Record yang dipakai: `A  api  <IP VM statis>`  TTL default.
- Tidak perlu custom nameserver; biarkan `ns1/ns2.idwebhost.id`.
- Setelah DNS propagasi, restart Caddy agar sertifikat terbit:
  `sudo systemctl restart caddy` (Caddy ambil cert otomatis).

## Keamanan

- SSH hanya dengan key (`~/.ssh/malva_azure`, ed25519). Persempit port 22
  ke IP rumah lewat NSG Azure bila memungkinkan.
- PostgreSQL: **jangan** pakai rule firewall `0.0.0.0–255.255.255.255`.
  Gunakan "Allow public access from Azure services" + IP admin saat migrasi.
- `MALVA_JWT_SECRET` produksi ada di env VM (bukan di repo).
- Jangan commit `.env` / kredensial; script admin ada di `backend/admin_scripts`.

## Biaya

Kedua layanan inti (VM B2ats_v2 & PG B1ms) masuk kuota **12 bulan gratis**
untuk pelanggan baru — biaya efektif **$0/bulan** selama di dalam kuota.
Kredit US$100 adalah cadangan. Pasca presentasi (Feb 2027): dump final ke
lokal, lalu hapus resource group agar tidak ada tagihan nyangkut.
