#!/usr/bin/env sh
# Backup harian PostgreSQL Malva (dijalankan via cron di VM Azure).
# Membutuhkan: postgresql-client (pg_dump) dan MALVA_DATABASE_URL di environment.
set -eu

BACKUP_DIR=/var/backups/malva
STAMP=$(date +%Y%m%d_%H%M%S)
FILE="$BACKUP_DIR/malva_$STAMP.dump"

mkdir -p "$BACKUP_DIR"

# pg_dump menerima connection URI langsung (SSL disertakan di URL).
pg_dump --format=custom --no-owner --file="$FILE" "$MALVA_DATABASE_URL"

# Retensi 14 hari.
find "$BACKUP_DIR" -name 'malva_*.dump' -mtime +14 -delete

echo "backup ok: $FILE"
