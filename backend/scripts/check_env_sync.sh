#!/usr/bin/env bash
# ============================================================
# Malva — gate sinkronisasi environment (R6.1)
# ============================================================
# Setiap variabel MALVA_* yang dibaca internal/config/config.go WAJIB
# didokumentasikan di .env.example. Gate ini mencegah drift yang pernah
# terjadi (MALVA_GOOGLE_CLIENT_SECRET & MALVA_UPLOAD_DIR sempat hilang
# dari .env.example padahal dipakai kode).
#
# Pemakaian: bash scripts/check_env_sync.sh
# ============================================================
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

cfg="$(grep -oE 'MALVA_[A-Z0-9_]+' internal/config/config.go | sort -u)"
example="$(grep -oE '^MALVA_[A-Z0-9_]+' .env.example | sort -u)"

missing="$(comm -23 <(printf '%s\n' "$cfg") <(printf '%s\n' "$example") || true)"
extra="$(comm -13 <(printf '%s\n' "$cfg") <(printf '%s\n' "$example") || true)"

fail=0

if [ -n "$missing" ]; then
  printf 'ERROR: variabel berikut dibaca config.go tapi TIDAK ada di .env.example:\n' >&2
  printf '  %s\n' $missing >&2
  fail=1
fi

# Kelebihan di .env.example hanya peringatan: boleh berisi variabel yang
# dipakai skrip deploy (mis. MALVA_MIGRATIONS_DIR), bukan config.go.
if [ -n "$extra" ]; then
  printf 'CATATAN: variabel di .env.example yang tidak dibaca config.go (boleh, pastikan dipakai skrip):\n'
  printf '  %s\n' $extra
fi

if [ "$fail" -eq 0 ]; then
  printf 'OK: %s variabel MALVA_* di config.go seluruhnya terdokumentasi di .env.example.\n' \
    "$(printf '%s\n' "$cfg" | wc -l | tr -d ' ')"
fi
exit "$fail"
