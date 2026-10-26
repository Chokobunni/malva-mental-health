#!/usr/bin/env bash
# ============================================================
# Malva — gate konvensi migrasi SQL (R1.3, R8.2)
# ============================================================
# Aturan yang ditegakkan:
#   1. Nama berkas wajib NNN_nama_underscore.sql (3 digit, huruf kecil).
#   2. Nomor unik dan menaik sesuai urutan berkas (tidak ada duplikat).
#   3. Migrasi BARU (nomor >= 018) wajib idempoten:
#        - CREATE TABLE ... IF NOT EXISTS
#        - ADD COLUMN ... IF NOT EXISTS
#      Migrasi 001–017 dikecualikan (sudah terlanjur berjalan di produksi;
#      mengubahnya melanggar aturan "jangan edit migrasi yang sudah jalan").
#
# Pemakaian: bash scripts/check_migrations.sh
# ============================================================
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../migrations"

LEGACY_MAX=17
fail=0
prev=0
count=0

for f in *.sql; do
  [ -e "$f" ] || continue
  count=$((count + 1))

  if ! printf '%s' "$f" | grep -Eq '^[0-9]{3}_[a-z0-9_]+\.sql$'; then
    printf 'ERROR: nama migrasi tidak sesuai pola NNN_nama.sql: %s\n' "$f" >&2
    fail=1
    continue
  fi

  num=$((10#$(printf '%s' "$f" | cut -c1-3)))
  if [ "$num" -le "$prev" ]; then
    printf 'ERROR: nomor migrasi tidak menaik/duplikat: %s (sebelumnya %03d)\n' "$f" "$prev" >&2
    fail=1
  fi
  prev=$num

  if [ "$num" -gt "$LEGACY_MAX" ]; then
    bad="$(grep -inE 'CREATE TABLE|ADD COLUMN' "$f" \
      | grep -viE 'IF NOT EXISTS' || true)"
    if [ -n "$bad" ]; then
      printf 'ERROR: migrasi baru wajib idempoten (IF NOT EXISTS): %s\n' "$f" >&2
      printf '%s\n' "$bad" >&2
      fail=1
    fi
  fi
done

if [ "$fail" -eq 0 ]; then
  printf 'OK: %s migrasi, penomoran valid, migrasi baru (>=%03d) idempoten.\n' "$count" "$((LEGACY_MAX + 1))"
fi
exit "$fail"
