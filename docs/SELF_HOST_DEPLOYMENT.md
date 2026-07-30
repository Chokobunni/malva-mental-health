# Self-host Deployment Malva

Target paling sederhana: satu VPS Linux kecil menjalankan PostgreSQL, backend
Go, dan reverse proxy HTTPS.

## Komponen

- PostgreSQL 16
- Binary `malva-api`
- Caddy atau Nginx untuk HTTPS reverse proxy
- Firebase service account JSON hanya untuk FCM push

## Build backend

```bash
cd backend
go test ./...
go build -buildvcs=false -o malva-api ./cmd/api
```

Copy binary:

```bash
sudo cp malva-api /usr/local/bin/malva-api
```

## Environment

Gunakan template:

```text
backend/deploy/env.production.example
```

Simpan sebagai:

```text
/etc/malva/malva-api.env
```

## Service

Copy:

```text
backend/deploy/systemd/malva-api.service
```

ke:

```text
/etc/systemd/system/malva-api.service
```

Lalu:

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now malva-api
sudo systemctl status malva-api
```

## HTTPS

Contoh Caddy ada di:

```text
backend/deploy/Caddyfile.example
```

Ganti `malva.example.com` dengan domain asli.
