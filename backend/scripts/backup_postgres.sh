#!/usr/bin/env bash
set -Eeuo pipefail

BACKUP_DIR="${BACKUP_DIR:-/var/backups/malva}"
ENV_FILE="${ENV_FILE:-/etc/malva/malva-api.env}"
RETENTION_DAYS="${RETENTION_DAYS:-14}"

if [[ ! -r "$ENV_FILE" ]]; then
  echo "Cannot read env file: $ENV_FILE" >&2
  exit 1
fi

set -a
source "$ENV_FILE"
set +a

if [[ -z "${MALVA_DATABASE_URL:-}" ]]; then
  echo "MALVA_DATABASE_URL is missing from $ENV_FILE" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
chmod 750 "$BACKUP_DIR"

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
output="${BACKUP_DIR}/malva-${timestamp}.dump"

pg_dump "$MALVA_DATABASE_URL" --format=custom --no-owner --file="$output"
chmod 640 "$output"

find "$BACKUP_DIR" -type f -name 'malva-*.dump' -mtime "+${RETENTION_DAYS}" -delete

echo "$output"

